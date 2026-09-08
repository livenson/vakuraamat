# Autoload "Locator": finds places (Maa-amet in-ADS geocoder, coarse IP geolocation) and asks the
# tile service (tools/tile_service.py) for a playable pack for a point, which it installs under
# user://sites/<id> and user://tiles/<id>. The world then builds the Terrain3D data on first visit.
extends Node

signal progress(text: String, fraction: float)

const SETTINGS := "user://settings.cfg"
const MIN_FREE_BYTES := 1024 * 1024 * 1024   # a pack installs ~150 MB plus its built region data; keep a margin
const DEFAULT_SERVICE := "http://127.0.0.1:8765"
const GEOCODER := "https://inaadress.maaamet.ee/inaadress/gazetteer?results=8&features=EHAK,TANAV,KATASTRIYKSUS,EHITISHOONE&address="
const IP_API := "http://ip-api.com/json/?fields=status,country,countryCode,city,lat,lon"

# EPSG:3301 (L-EST97): Lambert conformal conic 2SP on GRS80
const LAT1 := 59.33333333333334
const LAT2 := 58.0
const LAT0 := 57.51755393055556
const LON0 := 24.0
const X0 := 500000.0
const Y0 := 6375000.0
const A_GRS80 := 6378137.0
const F_GRS80 := 1.0 / 298.257222101


func service_url() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		return str(cfg.get_value("service", "url", DEFAULT_SERVICE)).trim_suffix("/")
	return DEFAULT_SERVICE


## One HTTP round trip. Returns {code, body(String), ok}. code 0 = no connection.
func http(url: String, method: int = HTTPClient.METHOD_GET, body: String = "", download_to: String = "") -> Dictionary:
	var r := HTTPRequest.new()
	r.timeout = 60.0
	if download_to != "":
		r.download_file = download_to
	add_child(r)
	var headers := PackedStringArray(["Content-Type: application/json"]) if body != "" else PackedStringArray()
	var err := r.request(url, headers, method, body)
	if err != OK:
		r.queue_free()
		return {"code": 0, "body": "", "ok": false}
	var res: Array = await r.request_completed
	r.queue_free()
	var code: int = res[1]
	var text := ""
	if download_to == "":
		text = (res[3] as PackedByteArray).get_string_from_utf8()
	return {"code": code, "body": text, "ok": res[0] == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300}


## What a pack for (x, y) would download, from the service's HEAD requests: {items [{name, bytes,
## cached}], bytes, download_bytes, rate_bps, seconds_download, seconds_process, free_bytes}; {} if unknown.
func estimate(x: float, y: float, size: int = 1024) -> Dictionary:
	var r := await http(service_url() + "/estimate?x=%d&y=%d&size=%d" % [int(x), int(y), size])
	if not r.ok:
		return {}
	var d = JSON.parse_string(r.body)
	return d if typeof(d) == TYPE_DICTIONARY else {}


## The service's own cache: {bytes, packs [{id, bytes}], free_bytes, path}; {} if it does not answer.
func service_cache() -> Dictionary:
	var r := await http(service_url() + "/cache")
	if not r.ok:
		return {}
	var d = JSON.parse_string(r.body)
	return d if typeof(d) == TYPE_DICTIONARY else {}


## Free bytes on the disk holding user:// (-1 when unknown).
static func free_bytes() -> int:
	var d := DirAccess.open("user://")
	return d.get_space_left() if d else -1


## Bytes under a user:// directory, recursively.
static func dir_bytes(path: String) -> int:
	var d := DirAccess.open(path)
	if d == null:
		return 0
	var total := 0
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if d.current_is_dir():
			total += dir_bytes(path.path_join(f))
		else:
			var fa := FileAccess.open(path.path_join(f), FileAccess.READ)
			if fa:
				total += fa.get_length()
		f = d.get_next()
	d.list_dir_end()
	return total


## What an installed pack takes: its site files, its tile (engine files and built region data) and
## the downloaded zip. {site, tile, zip, total} in bytes.
static func pack_bytes(id: String) -> Dictionary:
	var tile := str(Sites.manifest_for(id).get("terrain", {}).get("tile", id))
	var site := dir_bytes(Sites.USER_ROOT + id)
	var t := dir_bytes(Sites.USER_TILES + tile)
	var z := 0
	var fa := FileAccess.open("user://cache/%s.zip" % id, FileAccess.READ)
	if fa:
		z = fa.get_length()
	return {"site": site, "tile": t, "zip": z, "total": site + t + z}


## Remove an installed pack (site, tile, zip) to the system trash. Never the active site.
static func remove_pack(id: String) -> bool:
	if id == Sites.active or not Sites.is_user_pack(id):
		return false
	var tile := str(Sites.manifest_for(id).get("terrain", {}).get("tile", id))
	for p in [Sites.USER_ROOT + id, Sites.USER_TILES + tile, "user://cache/%s.zip" % id]:
		var g := ProjectSettings.globalize_path(p)
		if DirAccess.dir_exists_absolute(g) or FileAccess.file_exists(g):
			if OS.move_to_trash(g) != OK:
				push_warning("could not remove " + g)
	Sites.scan()
	return true


static func fmt_bytes(n: float) -> String:
	if n >= 1024.0 * 1024.0 * 1024.0:
		return "%.1f GB" % (n / (1024.0 * 1024.0 * 1024.0))
	return "%d MB" % int(n / (1024.0 * 1024.0))


static func fmt_seconds(n: float) -> String:
	return ("%d min" % int(ceil(n / 60.0))) if n >= 60.0 else ("%d s" % int(n))


## Packs already generated and cached on the service: [{id, name, x, y, size, eras, seed, blocks}].
func list_service_packs() -> Array:
	var r := await http(service_url() + "/packs")
	if not r.ok:
		return []
	var d = JSON.parse_string(r.body)
	return d if typeof(d) == TYPE_ARRAY else []


func service_alive() -> bool:
	var r := await http(service_url() + "/health")
	return r.ok


## The tile service, started from the source tree if it is not running (see spawn_local).
func ensure_service() -> bool:
	if await service_alive():
		return true
	return await spawn_local("tools/tile_service.py", 8765, service_url() + "/health")


## The tile-service sidecar shipped beside an exported game (tools/service/build.sh): next to the
## executable, or inside the macOS bundle's MacOS directory. "" when there is none.
static func sidecar_path() -> String:
	var dir := OS.get_executable_path().get_base_dir()
	for name in ["tile_service", "tile_service.exe"]:
		if FileAccess.file_exists(dir.path_join(name)):
			return dir.path_join(name)
	return ""


## Start the tile service as a background process when the configured URL is local: from the
## source tree the Python script, in an exported build the sidecar executable (its packs and cache
## under user://service). Remote URLs and headless tests leave it alone. Waits until /health answers
## (up to ~15 s). From the source tree the process outlives the game (tools/play.sh manages it);
## the sidecar ends with the game (killed on quit, and it watches the game's pid itself).
var _sidecar_pid := -1


func _exit_tree() -> void:
	if _sidecar_pid > 0:
		OS.kill(_sidecar_pid)


func spawn_local(script_rel: String, port: int, health_url: String) -> bool:
	if DisplayServer.get_name() == "headless" or not (health_url.contains("127.0.0.1") or health_url.contains("localhost")):
		return false   # headless tests and remote services: never spawn
	var pid := -1
	var script := ProjectSettings.globalize_path("res://" + script_rel)
	var sidecar := sidecar_path()
	if not OS.has_feature("template") and FileAccess.file_exists(script):
		var venv := ProjectSettings.globalize_path("res://.venv-service/bin/python")   # the pipeline's venv (make setup)
		pid = OS.create_process(venv if FileAccess.file_exists(venv) else "python3", [script, "--port", str(port)])
	elif sidecar != "":
		var work := ProjectSettings.globalize_path("user://service")
		DirAccess.make_dir_recursive_absolute(work)
		var log_path := ProjectSettings.globalize_path("user://logs/tile_service.log")
		DirAccess.make_dir_recursive_absolute(log_path.get_base_dir())
		pid = OS.create_process(sidecar, ["--port", str(port), "--workspace", work, "--raw-dir", work.path_join("data_raw"),
				"--parent-pid", str(OS.get_process_id()), "--log", log_path])
		_sidecar_pid = pid
		script_rel = sidecar.get_file()
	else:
		return false
	if pid <= 0:
		push_warning("could not start %s" % script_rel)
		return false
	print("[Locator] started %s (pid %d)" % [script_rel, pid])
	# A frozen sidecar unpacks ~75 MB before its first line runs (measured 10.7 s on a warm machine),
	# and a cold first launch is slower still: 15 s used to be the whole budget.
	for i in 90:
		await get_tree().create_timer(0.5).timeout
		var r := await http(health_url)
		if r.ok:
			print("[Locator] %s answered after %.1f s" % [script_rel, (i + 1) * 0.5])
			return true
	# say which of the two it was: the process never got as far as Python, or it ran and did not serve
	var log_path := "user://logs/tile_service.log"
	var wrote: bool = FileAccess.file_exists(log_path) and FileAccess.open(log_path, FileAccess.READ).get_length() > 0
	push_warning("%s (pid %d) did not answer %s in 45 s; it %s - see %s" % [script_rel, pid, health_url,
			"logged something" if wrote else "wrote nothing, so it never started", ProjectSettings.globalize_path(log_path)])
	return false


## Places for a query: "E N" in L-EST97, "lat, lon", or an address / place name via in-ADS.
## Returns [{name, x, y}].
func geocode(q: String) -> Array:
	q = q.strip_edges()
	var nums := q.replace(";", " ").replace(",", " ").split(" ", false)
	if nums.size() == 2 and nums[0].is_valid_float() and nums[1].is_valid_float():
		var a := float(nums[0])
		var b := float(nums[1])
		if a > 100000.0 and b > 100000.0:
			return [{"name": "L-EST97 %d %d" % [a, b], "x": a, "y": b}]
		if a > 50.0 and a < 70.0:
			var p := wgs84_to_lest97(a, b)
			return [{"name": "%.4f N %.4f E" % [a, b], "x": p.x, "y": p.y}]
	var r := await http(GEOCODER + q.uri_encode())
	if not r.ok:
		return []
	var parsed = JSON.parse_string(r.body)
	var out := []
	if typeof(parsed) == TYPE_DICTIONARY:
		for a in parsed.get("addresses", []):
			if a.has("viitepunkt_x") and a.has("viitepunkt_y"):
				out.append({"name": str(a.get("pikkaadress", a.get("ipikkaadress", q))), "x": float(a.viitepunkt_x), "y": float(a.viitepunkt_y)})
	return out


## Coarse position from the IP address: {ok, x, y, name}. City-level at best.
func locate_by_ip() -> Dictionary:
	var r := await http(IP_API)
	if not r.ok:
		return {"ok": false}
	var d = JSON.parse_string(r.body)
	if typeof(d) != TYPE_DICTIONARY or d.get("status") != "success":
		return {"ok": false}
	var p := wgs84_to_lest97(float(d.lat), float(d.lon))
	return {"ok": true, "x": p.x, "y": p.y, "name": "%s, %s" % [d.get("city", ""), d.get("country", "")], "country": str(d.get("countryCode", ""))}


func in_estonia(x: float, y: float) -> bool:
	return x > 369000.0 and x < 740000.0 and y > 6377000.0 and y < 6635000.0


static func _m(phi: float, e: float) -> float:
	return cos(phi) / sqrt(1.0 - pow(e * sin(phi), 2))


static func _t(phi: float, e: float) -> float:
	return tan(PI / 4.0 - phi / 2.0) / pow((1.0 - e * sin(phi)) / (1.0 + e * sin(phi)), e / 2.0)


## WGS84 degrees -> L-EST97 metres (forward Lambert conformal conic, two standard parallels).
static func wgs84_to_lest97(lat_deg: float, lon_deg: float) -> Vector2:
	var e := sqrt(2.0 * F_GRS80 - F_GRS80 * F_GRS80)
	var p1 := deg_to_rad(LAT1)
	var p2 := deg_to_rad(LAT2)
	var p0 := deg_to_rad(LAT0)
	var n := (log(_m(p1, e)) - log(_m(p2, e))) / (log(_t(p1, e)) - log(_t(p2, e)))
	var f := _m(p1, e) / (n * pow(_t(p1, e), n))
	var rho0 := A_GRS80 * f * pow(_t(p0, e), n)
	var rho := A_GRS80 * f * pow(_t(deg_to_rad(lat_deg), e), n)
	var theta := n * (deg_to_rad(lon_deg) - deg_to_rad(LON0))
	return Vector2(X0 + rho * sin(theta), Y0 + rho0 - rho * cos(theta))


static func slug(name: String) -> String:
	var s := name.to_lower().replace("õ", "o").replace("ä", "a").replace("ö", "o").replace("ü", "u").replace("š", "s").replace("ž", "z")
	var out := ""
	var last_us := false
	for ch in s:
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
			last_us = false
		elif not last_us:
			out += "_"
			last_us = true
	out = out.strip_edges().trim_prefix("_").trim_suffix("_")
	if out == "" or not (out[0] >= "a" and out[0] <= "z"):
		out = "site_" + out
	return out


## Ask the service for a pack at (x, y), wait for it, install it, make it the active site.
## Returns {ok, id, error}.
func create_world(name: String, x: float, y: float, size: int = 1024, eras: String = "2026", id_override: String = "", seed_value: int = -1, blocks: Array = []) -> Dictionary:
	var id := id_override if id_override != "" else slug(name)
	var r := await fetch_pack(id, name, x, y, size, eras, seed_value, blocks)
	if r.ok:
		Sites.scan()
		Sites.select(id)
	return r


## Generate (or reuse from the service cache), download and install a pack without activating it:
## the world streamer uses this for neighbouring tiles. Returns {ok, id, error}.
## `refresh` asks the service to rebuild a pack it already has, keeping the ground it already
## fetched and re-running only the register stages - a minute or two rather than the twenty a full
## rebuild costs, and nothing under `tile/` changes, which is what lets a refreshed pack be swapped
## in without touching the terrain. `quiet` keeps the stage out of `progress`, which the streamer
## shows on the HUD and in the notice explaining why the player is held at an edge: a refresh
## running in the background must not take that line over.
func fetch_pack(id: String, name: String, x: float, y: float, size: int = 1024, eras: String = "2026", seed_value: int = -1, blocks: Array = [],
		refresh: bool = false, quiet: bool = false) -> Dictionary:
	var base := service_url()
	var error := ""
	var say := func(text: String, at: float):
		if not quiet:
			progress.emit(text, at)
	say.call(tr("MENU_STAGE_SERVICE"), 0.0)
	var free := free_bytes()
	if not await ensure_service():
		error = tr("MENU_SERVICE_DOWN") % base
	elif not in_estonia(x, y):
		error = tr("MENU_OUTSIDE_ESTONIA")
	elif free >= 0 and free < MIN_FREE_BYTES:
		error = tr("MENU_LOW_DISK") % [fmt_bytes(free), fmt_bytes(MIN_FREE_BYTES)]
	var req := {}
	if error == "":
		req = {"id": id, "name": name, "x": x, "y": y, "size": size, "eras": eras}
		if refresh:
			req["refresh"] = true
		if seed_value >= 0:
			req["seed"] = seed_value
		if not blocks.is_empty():
			req["blocks"] = blocks
		var body := JSON.stringify(req)
		say.call(tr("MENU_STAGE_REQUEST"), 0.02)
		var r := await http(base + "/tile", HTTPClient.METHOD_POST, body)
		if not r.ok:
			error = r.body if r.body != "" else "HTTP %d" % r.code
	if error == "":
		error = await _wait_for_job(base, id, quiet)
		if error == "status: HTTP 404" and not req.is_empty():
			# the service was restarted mid-job and forgot it: submit once more (its caches make it quick)
			say.call(tr("MENU_STAGE_REQUEST"), 0.02)
			var again := await http(base + "/tile", HTTPClient.METHOD_POST, JSON.stringify(req))
			error = await _wait_for_job(base, id, quiet) if again.ok else ("HTTP %d" % again.code)
	if error == "":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://cache"))
		var zip_path := "user://cache/%s.zip" % id
		say.call(tr("MENU_STAGE_DOWNLOAD"), 0.93)
		var dl := await http(base + "/download?id=" + id, HTTPClient.METHOD_GET, "", zip_path)
		if not dl.ok:
			error = "download: HTTP %d" % dl.code
		else:
			say.call(tr("MENU_STAGE_INSTALL"), 0.97)
			if not install_zip(zip_path, id, refresh):
				error = "could not unpack " + zip_path
	return {"ok": error == "", "id": id, "error": error}


## A pack ships the 5 m ground model so a new place can be walked in about a minute; the service
## fetches the 1 m one afterwards. True when the tile still carries the coarse ground.
static func ground_is_coarse(id: String) -> bool:
	if not Sites.is_user_pack(id):
		return false
	var meta_path := Sites.tile_dir_of(id) + "/terrain_meta.json"
	if not FileAccess.file_exists(meta_path):
		return false
	var m = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
	return typeof(m) == TYPE_DICTIONARY and float(m.get("dtm_res_m", 1.0)) > 1.0


## Take the refined pack (1 m ground, measured trees, news) when the service has it ready. The
## install clears the tile's region data, so the world rebuilds the ground from the finer model on
## the way in. Returns true when something was installed. Quiet and quick when the service is down:
## the coarse ground is a complete world, not a placeholder.
func take_refined(id: String) -> bool:
	if not ground_is_coarse(id) or not await service_alive():
		return false
	var st := await http(service_url() + "/status?id=" + id)
	if not st.ok:
		return false
	var d = JSON.parse_string(st.body)
	if typeof(d) != TYPE_DICTIONARY or not bool(d.get("refined", false)) or not bool(d.get("done", true)):
		return false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://cache"))
	var zip_path := "user://cache/%s.zip" % id
	var dl := await http(service_url() + "/download?id=" + id, HTTPClient.METHOD_GET, "", zip_path)
	if not dl.ok or not install_zip(zip_path, id):
		return false
	if id == Sites.active:
		Sites.reload_active()   # the pack's own files changed under it (news, trees, the meta)
	print("[Locator] %s: the 1 m ground model replaced the 5 m one; the tile is rebuilt on the way in" % id)
	return true


## Rebuild a pack that an older pipeline built, and put the result in place. The registers are
## re-fetched and the ground is not, so nothing under user://tiles changes and the caller can swap
## the pack into a running world without touching a Terrain3D region.
##
## Returns {ok, id, error}. The caller is responsible for whatever is holding the old data: a
## streamed tile re-instances its era, the active pack goes through Sites.reload_active().
func refresh_pack(id: String, quiet: bool = true) -> Dictionary:
	var m := Sites.manifest_for(id)
	var t: Dictionary = m.get("terrain", {})
	var c: Array = t.get("center", []) if typeof(t) == TYPE_DICTIONARY else []
	if c.size() != 2:
		return {"ok": false, "id": id, "error": "no centre in the manifest"}
	# Never start the service for this. A pack built by an older pipeline is a complete, playable
	# place; the refresh is an improvement, and it must not cost a service launch on the way in.
	if not await service_alive():
		return {"ok": false, "id": id, "error": "the tile service is not running"}
	var r := await fetch_pack(id, str(m.get("description", id)), float(c[0]), float(c[1]), int(t.get("size", 1024)), _eras_of(id), -1, [], true, quiet)
	if not r.get("ok", false):
		return r
	# The service hands back the zip it has if a restart lost the job, so the pack that just landed
	# may still be the old one. Believe the stamp, not the request.
	Sites.scan()
	if Sites.pack_version(id) < Sites.PACK_VERSION:
		return {"ok": false, "id": id, "error": "the pack is still stamped %d" % Sites.pack_version(id)}
	forget_pack(id)
	print("[Locator] %s refreshed to pipeline %d" % [id, Sites.pack_version(id)])
	return {"ok": true, "id": id, "error": ""}


## Drop everything read from a pack's files. Every cache here is keyed on the path, which an
## in-place refresh does not change, and Parcels keys its merged view on which tiles are standing
## rather than on what is in them - so without this the game keeps serving the pack it had.
## GameState.forget_caches() is the one place that knows the five registry caches; the era scenes
## are re-parsed here because ResourceLoader would hand back the instance it already has.
func forget_pack(id: String) -> void:
	GameState.forget_caches()
	var dir := DirAccess.open(Sites.path_in(id, "scenes"))
	if dir == null:
		return
	for f in dir.get_files():
		if f.ends_with(".tscn"):
			ResourceLoader.load(Sites.path_in(id, "scenes/" + f), "PackedScene", ResourceLoader.CACHE_MODE_REPLACE)


## The years a pack already carries, as the service wants them ("2026" or "1939,2026"). Taken from
## the pack's own scenes rather than from GameState, which knows only the active site's.
func _eras_of(id: String) -> String:
	var years: Array[String] = []
	var dir := DirAccess.open(Sites.path_in(id, "scenes"))
	if dir:
		for f in dir.get_files():
			if f.begins_with("era_") and f.ends_with(".tscn"):
				years.append(f.trim_prefix("era_").trim_suffix(".tscn"))
	years.sort()
	return ",".join(years) if not years.is_empty() else "2026"


## Poll the job until it is done; "" on success, else the error text.
func _wait_for_job(base: String, id: String, quiet: bool = false) -> String:
	while true:
		var st := await http(base + "/status?id=" + id)
		if not st.ok:
			return "status: HTTP %d" % st.code
		var d = JSON.parse_string(st.body)
		if typeof(d) != TYPE_DICTIONARY:
			return "bad status"
		if not quiet:
			progress.emit(str(d.get("stage", "")), clampf(float(d.get("progress", 0.0)) * 0.9, 0.03, 0.9))
		if d.get("error", "") != "":
			return str(d.error)
		if bool(d.get("done", false)):
			return ""
		await get_tree().create_timer(1.5).timeout
	return ""


## Unpack a service zip: site/* -> user://sites/<id>/, tile/* -> user://tiles/<tile>/.
## `site_only` leaves the tile alone - a refresh rebuilds the registers, not the ground, and the
## region data under user://tiles is what the player is standing on.
func install_zip(zip_path: String, id: String, site_only: bool = false) -> bool:
	var z := ZIPReader.new()
	if z.open(zip_path) != OK:
		return false
	var files := z.get_files()
	var tile := id
	if "site/site.json" in files:
		var m = JSON.parse_string(z.read_file("site/site.json").get_string_from_utf8())
		if typeof(m) == TYPE_DICTIONARY:
			tile = str(m.get("terrain", {}).get("tile", id))
	for f in files:
		if f.ends_with("/"):
			continue
		var dest := ""
		if f.begins_with("site/"):
			dest = Sites.USER_ROOT + id + "/" + f.trim_prefix("site/")
		elif f.begins_with("tile/"):
			if site_only:
				continue
			dest = Sites.USER_TILES + tile + "/" + f.trim_prefix("tile/")
		else:
			continue
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dest.get_base_dir()))
		var out := FileAccess.open(dest, FileAccess.WRITE)
		if out == null:
			push_error("cannot write " + dest)
			z.close()
			return false
		out.store_buffer(z.read_file(f))
		out.close()
	z.close()
	if site_only:
		Sites.scan()
		return true
	# a fresh tile: any stale region data from an earlier download must go
	var old_data := ProjectSettings.globalize_path(Sites.USER_TILES + tile + "/data")
	if DirAccess.dir_exists_absolute(old_data):
		for f in DirAccess.get_files_at(old_data):
			DirAccess.remove_absolute(old_data + "/" + f)
	print("[Locator] installed pack %s (%d files)" % [id, files.size()])
	Sites.scan()   # a pack that has just appeared on disk: until this, Sites resolves its files under res://
	return true
