# Autoload "Friends": share a world by code, visit a friend's world, and carry consequences between
# them through the world service (tools/world_service.py). A shared world is a small descriptor
# (place, story seed and blocks, committed flags), which the visitor's own tile service regenerates.
# Deliveries a visitor makes inside a friend's world are posted to the service and applied, as
# consequences, when the owner next loads that world. No live simulation, no live netcode: flags.
extends Node

signal status(text: String)

const SETTINGS := "user://settings.cfg"
const DEFAULT_SERVICE := "http://127.0.0.1:8766"

var visiting_code := ""     # non-empty while playing a friend's world
var visiting_owner := ""


func _ready() -> void:
	EventBus.consequence_triggered.connect(_on_consequence)
	EventBus.chapter_committed.connect(func(_c): republish_flags())


func service_url() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		return str(cfg.get_value("service", "worlds_url", DEFAULT_SERVICE)).trim_suffix("/")
	return DEFAULT_SERVICE


func player_name() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		return str(cfg.get_value("player", "name", ""))
	return ""


## The code this machine published for a site, "" if none.
func my_code(site_id: String) -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		return str(cfg.get_value("worlds", site_id, ""))
	return ""


func _setting(section: String, key: String, value: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value(section, key, value)
	cfg.save(SETTINGS)


## The world service, started from the source tree if it is not running (Locator.spawn_local).
func alive() -> bool:
	var r := await Locator.http(service_url() + "/health")
	if r.ok:
		return true
	return await Locator.spawn_local("tools/world_service.py", 8766, service_url() + "/health")


## Publish the active site as a world descriptor. Returns {ok, code, error}.
func publish() -> Dictionary:
	var base := service_url()
	if not await alive():
		return {"ok": false, "code": "", "error": tr("MENU_WORLDS_DOWN") % base}
	var m := Sites.manifest
	var years := GameState.eras_in_order().map(func(e): return e.year_label)
	var flags := {}
	for f in TimelineState.flags:
		if TimelineState.is_committed(f) and GameState.consequence_for_flag(f) != null:
			flags[f] = true
	var body := {
		"name": tr(str(m.get("name_key", Sites.active))), "site_id": Sites.active, "generated": m.has("story"),
		"center": m.get("terrain", {}).get("center"), "size": int(m.get("terrain", {}).get("size", 1024)), "eras": ",".join(years),
		"seed": m.get("story", {}).get("seed"), "blocks": m.get("story", {}).get("blocks"), "flags": flags, "owner": player_name(),
	}
	var r := await Locator.http(base + "/worlds", HTTPClient.METHOD_POST, JSON.stringify(body))
	if not r.ok:
		return {"ok": false, "code": "", "error": r.body if r.body != "" else "HTTP %d" % r.code}
	var d = JSON.parse_string(r.body)
	var code := str(d.get("code", "")) if typeof(d) == TYPE_DICTIONARY else ""
	if code == "":
		return {"ok": false, "code": "", "error": "no code in reply"}
	_setting("worlds", Sites.active, code)
	_setting("worlds_since", code, 0)
	return {"ok": true, "code": code, "error": ""}


func fetch(code: String) -> Dictionary:
	var r := await Locator.http(service_url() + "/worlds/" + code.strip_edges().to_upper())
	if not r.ok:
		return {}
	var d = JSON.parse_string(r.body)
	return d if typeof(d) == TYPE_DICTIONARY else {}


## Make a friend's world playable here: regenerate it (or use the shipped pack), preset its
## committed flags, mark the session as visiting. Returns {ok, id, error}.
func visit(code: String) -> Dictionary:
	code = code.strip_edges().to_upper()
	if not await alive():
		return {"ok": false, "id": "", "error": tr("MENU_WORLDS_DOWN") % service_url()}
	var d := await fetch(code)
	if d.is_empty():
		return {"ok": false, "id": "", "error": tr("MENU_NO_SUCH_WORLD")}
	var id := str(d.get("site_id", ""))
	if bool(d.get("generated", true)):
		id = "visit_" + code.to_lower()
		var c: Array = d.get("center", [])
		if c.size() != 2:
			return {"ok": false, "id": id, "error": "descriptor has no centre"}
		var seed_v: int = int(d.seed) if d.get("seed") != null else -1
		var blocks: Array = d.get("blocks") if d.get("blocks") != null else []
		status.emit(tr("MENU_GENERATING") % "...")
		var res: Dictionary = await Locator.create_world(str(d.get("name", code)), float(c[0]), float(c[1]), int(d.get("size", 1024)), str(d.get("eras", "1798,1938,2026")), id, seed_v, blocks)
		if not res.ok:
			return res
	elif Sites.available.has(id):
		Sites.select(id)
	else:
		return {"ok": false, "id": id, "error": "that world's pack (%s) is not available here" % id}
	GameState.preset_flags = {}
	for f in d.get("flags", {}):
		if bool(d.flags[f]):
			GameState.preset_flags[str(f)] = true
	visiting_code = code
	visiting_owner = str(d.get("owner", ""))
	return {"ok": true, "id": id, "error": ""}


## Leaving a friend's world (new game in your own): no more deliveries are posted.
func stop_visiting() -> void:
	visiting_code = ""
	visiting_owner = ""
	GameState.preset_flags = {}


func _on_consequence(cp_id: String) -> void:
	if visiting_code == "":
		return
	var cp := GameState.consequence(cp_id)
	if cp == null:
		return
	var body := JSON.stringify({"flag": cp.flag_name, "by": player_name(), "era": cp.trigger_era})
	var r := await Locator.http(service_url() + "/worlds/" + visiting_code + "/deliveries", HTTPClient.METHOD_POST, body)
	if r.ok:
		print("[Friends] delivered %s to world %s" % [cp.flag_name, visiting_code])


## Owner side: fetch what visitors did in this world since last time and apply it as consequences.
## Returns the number of new deliveries applied.
func pull_deliveries() -> int:
	var code := my_code(Sites.active)
	if code == "" or visiting_code != "":
		return 0
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	var since := int(cfg.get_value("worlds_since", code, 0))
	var r := await Locator.http(service_url() + "/worlds/%s/deliveries?since=%d" % [code, since])
	if not r.ok:
		return 0
	var d = JSON.parse_string(r.body)
	if typeof(d) != TYPE_DICTIONARY:
		return 0
	var applied := 0
	for dl in d.get("deliveries", []):
		since = maxi(since, int(dl.get("n", 0)))
		var flag := str(dl.get("flag", ""))
		var cp := GameState.consequence_for_flag(flag)
		if cp == null or TimelineState.has_flag(flag):
			continue
		GameState.trigger_consequence(cp.id)
		EventBus.notice.emit(tr("NOTICE_FRIEND_DELIVERY") % [str(dl.get("by", "?")), tr(cp.effect_description_key)])
		applied += 1
	if applied > 0:
		TimelineState.commit()   # a friend's deed is permanent
		SaveManager.autosave()
	_setting("worlds_since", code, since)
	return applied


## Owner side: keep the published descriptor's flags current (after every chapter commit).
func republish_flags() -> void:
	var code := my_code(Sites.active)
	if code == "" or visiting_code != "":
		return
	var flags := {}
	for f in TimelineState.flags:
		if TimelineState.is_committed(f) and GameState.consequence_for_flag(f) != null:
			flags[f] = true
	await Locator.http(service_url() + "/worlds/" + code + "/flags", HTTPClient.METHOD_PUT, JSON.stringify({"flags": flags}))
