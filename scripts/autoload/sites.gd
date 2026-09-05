# Autoload "Sites": the location/story packs under res://sites/<id>/ and which one is active.
# A site is a directory holding site.json (manifest), layout.json (authored positions), data/
# (era, consequence-point, item, manor, structure, trade-good, crop and animal resources),
# narrative/ (ink sources and compiled json), scenes/ (generated era layers) and strings.csv.
# Engine code never names a site: terrain tile, spawn, sky, journal locations, objectives
# and ending rules all come through the manifest. Listed first among the autoloads.
extends Node

signal site_changed(id: String)

const ROOT := "res://sites/"
const SETTINGS := "user://settings.cfg"
const DEFAULT_SITE := "palupera"

var available: Array[String] = []
var active := ""
var manifest: Dictionary = {}
var _translations: Array[Translation] = []
var _initialised := false


func _ready() -> void:
	_ensure()


## Pick the active site once. Called from _ready and lazily by every accessor, because the main
## scene's _enter_tree can run before autoload _ready notifications are delivered.
func _ensure() -> void:
	if _initialised:
		return
	_initialised = true
	scan()
	var wanted := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--site="):
			wanted = a.trim_prefix("--site=")
	if wanted == "":
		var cfg := ConfigFile.new()
		if cfg.load(SETTINGS) == OK:
			wanted = str(cfg.get_value("site", "id", ""))
	if not available.has(wanted):
		wanted = DEFAULT_SITE if available.has(DEFAULT_SITE) else (available[0] if not available.is_empty() else "")
	_activate(wanted)


func scan() -> void:
	available.clear()
	var d := DirAccess.open(ROOT)
	if d == null:
		return
	for sub in d.get_directories():
		if FileAccess.file_exists(ROOT + sub + "/site.json"):
			available.append(sub)
	available.sort()


## Switch the active site (main menu). Registries listen to site_changed and reload.
## remember=false (tests) leaves user://settings.cfg alone.
func select(id: String, remember: bool = true) -> void:
	_ensure()
	if id == active or not available.has(id):
		return
	_activate(id)
	if remember:
		var cfg := ConfigFile.new()
		cfg.load(SETTINGS)
		cfg.set_value("site", "id", id)
		cfg.save(SETTINGS)
	site_changed.emit(id)


func _activate(id: String) -> void:
	active = id
	manifest = {}
	if id == "":
		push_error("no site packs under %s" % ROOT)
		return
	manifest = manifest_for(id)
	for t in _translations:
		TranslationServer.remove_translation(t)
	_translations.clear()
	for loc in ["et", "en"]:
		var p := path("strings.%s.translation" % loc)
		if ResourceLoader.exists(p):
			var t: Translation = load(p)
			TranslationServer.add_translation(t)
			_translations.append(t)
	print("[Sites] active site %s (%d available)" % [id, available.size()])


func manifest_for(id: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(ROOT + id + "/site.json")
	if text.is_empty():
		return {}
	var parsed = JSON.parse_string(text)
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


## res:// path of a file inside the active site.
func path(rel: String) -> String:
	_ensure()
	return ROOT + active + "/" + rel


func data_dir(sub: String) -> String:
	return path("data/" + sub + "/")


func get_value(key: String, default: Variant = null) -> Variant:
	_ensure()
	return manifest.get(key, default)


func terrain() -> Dictionary:
	_ensure()
	return manifest.get("terrain", {})


func tile() -> String:
	return str(terrain().get("tile", active))


func layout() -> Dictionary:
	_ensure()
	var text := FileAccess.get_file_as_string(path("layout.json"))
	if text.is_empty():
		return {}
	var parsed = JSON.parse_string(text)
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


## Translation key of a site's display name (falls back to the id).
func name_key(id: String) -> String:
	_ensure()
	var m := manifest_for(id) if id != active else manifest
	return str(m.get("name_key", id))


## Load every .tres/.res under dir into `into`, keyed by the resource's `id` property.
static func load_dir(dir: String, into: Dictionary) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		f = f.trim_suffix(".remap")   # exported builds list converted resources with this suffix
		if f.ends_with(".tres") or f.ends_with(".res"):
			var r: Resource = load(dir + f)
			if r and "id" in r:
				into[r.id] = r
