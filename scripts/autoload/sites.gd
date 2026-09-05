# Autoload "Sites": the location/story packs under res://sites/<id>/ and which one is active.
# A site is a directory holding site.json (manifest), layout.json (authored positions), data/
# (era, consequence-point, item, manor, structure, trade-good, crop and animal resources),
# narrative/ (ink sources and compiled json), scenes/ (generated era layers) and strings.csv.
# Engine code never names a site: terrain tile, spawn, sky, journal locations, objectives
# and ending rules all come through the manifest. Listed first among the autoloads.
extends Node

signal site_changed(id: String)

const ROOT := "res://sites/"            # packs shipped with the game
const USER_ROOT := "user://sites/"      # packs generated or downloaded at runtime (tile service, friends)
const USER_TILES := "user://tiles/"
const SETTINGS := "user://settings.cfg"
const DEFAULT_SITE := "palupera"

var available: Array[String] = []
var active := ""
var manifest: Dictionary = {}
var _translations: Array[Translation] = []
var _initialised := false
var _root_of: Dictionary = {}           # id -> root it was found under


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
		elif a.begins_with("--report="):
			var rep = JSON.parse_string(FileAccess.get_file_as_string(a.trim_prefix("--report=")))
			if typeof(rep) == TYPE_DICTIONARY:
				wanted = str(rep.get("site", wanted))
	if wanted == "":
		var cfg := ConfigFile.new()
		if cfg.load(SETTINGS) == OK:
			wanted = str(cfg.get_value("site", "id", ""))
	if not available.has(wanted):
		wanted = DEFAULT_SITE if available.has(DEFAULT_SITE) else (available[0] if not available.is_empty() else "")
	_activate(wanted)


func scan() -> void:
	available.clear()
	_root_of.clear()
	for root in [ROOT, USER_ROOT]:
		var d := DirAccess.open(root)
		if d == null:
			continue
		for sub in d.get_directories():
			if FileAccess.file_exists(root + sub + "/site.json") and not _root_of.has(sub):
				available.append(sub)
				_root_of[sub] = root
	available.sort()


func is_user_pack(id: String) -> bool:
	return _root_of.get(id, ROOT) == USER_ROOT


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


## Re-read the active pack from disk (dev hot reload): registries and strings follow via site_changed.
func reload_active() -> void:
	_ensure()
	_activate(active)
	site_changed.emit(active)


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
	var imported := false
	for loc in ["et", "en"]:
		var p := path("strings.%s.translation" % loc)
		if ResourceLoader.exists(p):
			var t: Translation = load(p)
			TranslationServer.add_translation(t)
			_translations.append(t)
			imported = true
	if not imported:
		# runtime packs have no imported .translation files: read strings.csv directly
		for t in csv_translations(path("strings.csv")):
			TranslationServer.add_translation(t)
			_translations.append(t)
	print("[Sites] active site %s (%d available%s)" % [id, available.size(), ", user pack" if is_user_pack(id) else ""])


func manifest_for(id: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(str(_root_of.get(id, ROOT)) + id + "/site.json")
	if text.is_empty():
		return {}
	var parsed = JSON.parse_string(text)
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


## res:// path of a file inside the active site.
func path(rel: String) -> String:
	_ensure()
	return str(_root_of.get(active, ROOT)) + active + "/" + rel


## Root a pack was found under (res://sites/ or user://sites/).
func root_of(id: String) -> String:
	_ensure()
	return str(_root_of.get(id, ROOT))


## Path of a file inside any installed pack (active or a streamed neighbour).
func path_in(id: String, rel: String) -> String:
	return root_of(id) + id + "/" + rel


## The pack a scene node belongs to: the nearest ancestor carrying a "pack_id" meta (a streamed
## neighbour tile's root), else the active site.
func pack_of(node: Node) -> String:
	var n := node
	while n:
		if n.has_meta("pack_id"):
			return str(n.get_meta("pack_id"))
		n = n.get_parent()
	return active


## Tile directory of any installed pack (see tile_dir).
func tile_dir_of(id: String) -> String:
	if id == active:
		return tile_dir()
	var t := str(manifest_for(id).get("terrain", {}).get("tile", id))
	var shipped := "res://assets/terrain/%s" % t
	if FileAccess.file_exists(shipped + "/terrain_meta.json"):
		return shipped
	return USER_TILES + t


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


## Directory of the tile's engine files: shipped under res://assets/terrain, else downloaded under user://tiles.
func tile_dir() -> String:
	var t := tile()
	var shipped := "res://assets/terrain/%s" % t
	if FileAccess.file_exists(shipped + "/terrain_meta.json"):
		return shipped
	return USER_TILES + t


## Translation objects from a keys,et,en CSV (quotes, doubled quotes and newlines inside quotes handled).
static func csv_translations(csv_path: String) -> Array[Translation]:
	var out: Array[Translation] = []
	var text := FileAccess.get_file_as_string(csv_path)
	if text.is_empty():
		return out
	var rows: Array = []
	var row: Array = []
	var field := ""
	var quoted := false
	var i := 0
	while i < text.length():
		var ch := text[i]
		if quoted:
			if ch == '"':
				if i + 1 < text.length() and text[i + 1] == '"':
					field += '"'
					i += 1
				else:
					quoted = false
			else:
				field += ch
		elif ch == '"':
			quoted = true
		elif ch == ",":
			row.append(field)
			field = ""
		elif ch == "\n" or ch == "\r":
			if ch == "\r" and i + 1 < text.length() and text[i + 1] == "\n":
				i += 1
			row.append(field)
			field = ""
			if row.size() > 1 or row[0] != "":
				rows.append(row)
			row = []
		else:
			field += ch
		i += 1
	if field != "" or not row.is_empty():
		row.append(field)
		rows.append(row)
	if rows.is_empty():
		return out
	var header: Array = rows[0]
	for col in range(1, header.size()):
		var t := Translation.new()
		t.locale = str(header[col]).strip_edges()
		for r in rows.slice(1):
			if r.size() > col and str(r[0]) != "":
				t.add_message(str(r[0]), str(r[col]))
		out.append(t)
	return out


func layout() -> Dictionary:
	_ensure()
	var text := FileAccess.get_file_as_string(path("layout.json"))
	if text.is_empty():
		return {}
	var parsed = JSON.parse_string(text)
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


## Display name of any pack (active or not) in the current locale, read from its strings.csv.
func display_name(id: String) -> String:
	_ensure()
	var key := name_key(id)
	if id == active and tr(key) != key:
		return tr(key)
	var loc := TranslationServer.get_locale().substr(0, 2)
	for t in csv_translations(str(_root_of.get(id, ROOT)) + id + "/strings.csv"):
		if t.locale == loc and t.get_message(key) != "":
			return t.get_message(key)
	return key if key != "" else id


## Translation key of a site's display name (falls back to the id).
func name_key(id: String) -> String:
	_ensure()
	var m := manifest_for(id) if id != active else manifest
	return str(m.get("name_key", id))


## Load every .tres/.res under dir into `into`, keyed by the resource's `id` property.
## First 8 hex digits of sha256(parcels.json bytes ++ tenants.json bytes), the same as tools/town_admin.py.
func pack_hash(id: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for name in ["parcels.json", "tenants.json"]:
		var path := path_in(id, name)
		if FileAccess.file_exists(path):
			ctx.update(FileAccess.get_file_as_bytes(path))
	return ctx.finish().hex_encode().substr(0, 8)


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
