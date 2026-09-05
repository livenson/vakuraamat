# Autoload "Locator": finds places (Maa-amet in-ADS geocoder, coarse IP geolocation) and asks the
# tile service (tools/tile_service.py) for a playable pack for a point, which it installs under
# user://sites/<id> and user://tiles/<id>. The world then builds the Terrain3D data on first visit.
extends Node

signal progress(text: String)

const SETTINGS := "user://settings.cfg"
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
func create_world(name: String, x: float, y: float, size: int = 1024, eras: String = "1798,1938,2026", id_override: String = "", seed_value: int = -1, blocks: Array = []) -> Dictionary:
	var id := id_override if id_override != "" else slug(name)
	var base := service_url()
	var error := ""
	if not await service_alive():
		error = tr("MENU_SERVICE_DOWN") % base
	elif not in_estonia(x, y):
		error = tr("MENU_OUTSIDE_ESTONIA")
	if error == "":
		var req := {"id": id, "name": name, "x": x, "y": y, "size": size, "eras": eras}
		if seed_value >= 0:
			req["seed"] = seed_value
		if not blocks.is_empty():
			req["blocks"] = blocks
		var body := JSON.stringify(req)
		var r := await http(base + "/tile", HTTPClient.METHOD_POST, body)
		if not r.ok:
			error = r.body if r.body != "" else "HTTP %d" % r.code
	if error == "":
		error = await _wait_for_job(base, id)
	if error == "":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://cache"))
		var zip_path := "user://cache/%s.zip" % id
		var dl := await http(base + "/download?id=" + id, HTTPClient.METHOD_GET, "", zip_path)
		if not dl.ok:
			error = "download: HTTP %d" % dl.code
		elif not install_zip(zip_path, id):
			error = "could not unpack " + zip_path
	if error == "":
		Sites.scan()
		Sites.select(id)
	return {"ok": error == "", "id": id, "error": error}


## Poll the job until it is done; "" on success, else the error text.
func _wait_for_job(base: String, id: String) -> String:
	while true:
		var st := await http(base + "/status?id=" + id)
		if not st.ok:
			return "status: HTTP %d" % st.code
		var d = JSON.parse_string(st.body)
		if typeof(d) != TYPE_DICTIONARY:
			return "bad status"
		progress.emit(tr("MENU_GENERATING") % str(d.get("stage", "")))
		if d.get("error", "") != "":
			return str(d.error)
		if bool(d.get("done", false)):
			return ""
		await get_tree().create_timer(1.5).timeout
	return ""


## Unpack a service zip: site/* -> user://sites/<id>/, tile/* -> user://tiles/<tile>/.
func install_zip(zip_path: String, id: String) -> bool:
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
	# a fresh tile: any stale region data from an earlier download must go
	var old_data := ProjectSettings.globalize_path(Sites.USER_TILES + tile + "/data")
	if DirAccess.dir_exists_absolute(old_data):
		for f in DirAccess.get_files_at(old_data):
			DirAccess.remove_absolute(old_data + "/" + f)
	print("[Locator] installed pack %s (%d files)" % [id, files.size()])
	return true
