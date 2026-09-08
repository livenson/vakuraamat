# Cadastral units of the installed packs (sites/<id>/parcels.json), for the book, the find bar,
# the codes overlay, the debug map and F8 reports: which unit is under a point, its number, purpose,
# 2022 taxation value, ownership form and the registry link.
#
# `units(pack)` is one pack's own file, in that pack's local metres. `all()` is every unit of every
# tile standing right now, in world metres: a streamed neighbour's x/z AND its boundary polygon are
# shifted by its tile offset, so anything taken from a row can be walked to, flown to, drawn, or
# handed to the georeference directly.
class_name Parcels
extends RefCounted

static var _cache: Dictionary = {}      # parcels.json path -> Array of units
static var _merged: Array = []          # all(): every ready tile's units, offsets applied
static var _merged_key := ""            # the tile layout _merged was built for
static var _by_tunnus: Dictionary = {}  # tunnus -> row, into _merged


static func units(pack: String = "") -> Array:
	var path := Sites.path_in(pack if pack != "" else Sites.active, "parcels.json")
	if not _cache.has(path):
		var text := FileAccess.get_file_as_string(path)
		var parsed = JSON.parse_string(text) if text != "" else null
		_cache[path] = parsed.get("parcels", []) if typeof(parsed) == TYPE_DICTIONARY else []
	return _cache[path]


## Forget the parsed files: a pack reinstalled under the player (Locator.take_refined) or a hot
## reload would otherwise keep answering from the old rows.
static func forget() -> void:
	_cache.clear()
	_merged.clear()
	_merged_key = ""
	_by_tunnus.clear()


## Every cadastral unit of every tile that is standing, in world metres. The origin pack answers
## first, so a unit an edge shares with a neighbour keeps the origin's copy.
static func all() -> Array:
	var key := _layout_key()
	if key != _merged_key:
		_rebuild(key)
	return _merged


## One unit by cadastral number, in world metres, or {} if no standing tile has it.
static func by_tunnus(tunnus: String) -> Dictionary:
	if tunnus == "":
		return {}
	var key := _layout_key()
	if key != _merged_key:
		_rebuild(key)
	return _by_tunnus.get(tunnus, {})


## The unit's dominant purpose code. The register gives an array with a percentage each; the first
## is the largest. Units with none are "SIHTOTSTARBETA_MAA" (no purpose set), which is a real value.
static func purpose_of(u: Dictionary) -> String:
	var list = u.get("purpose")
	if typeof(list) == TYPE_ARRAY and not list.is_empty():
		return str(list[0])
	return "SIHTOTSTARBETA_MAA"


static func at(pos: Vector3) -> Dictionary:
	var pack := ""
	var local := pos
	if GameState.world and GameState.world.streamer:
		var t: Dictionary = GameState.world.streamer.pack_at(pos)
		if t.is_empty():
			return {}
		pack = t.id
		local = pos - t.offset
	var p := Vector2(local.x, local.z)
	for u in units(pack):
		var poly := PackedVector2Array()
		for c in u.polygon:
			poly.append(Vector2(float(c[0]), float(c[1])))
		if Geometry2D.is_point_in_polygon(p, poly):
			return u
	return {}


## Short human line for a unit.
static func describe(u: Dictionary) -> String:
	if u.is_empty():
		return ""
	var purpose := ", ".join(u.get("purpose_text", u.get("purpose", [])))
	return "%s  %s  %s  %d m²  %s" % [u.get("tunnus", "?"), str(u.get("address", "")), purpose, int(u.get("area", 0)), str(u.get("ownership", ""))]


# ---------------------------------------------------------------- internals

## Which tiles are standing, as a string: the merged view is rebuilt when this changes, which is
## once a tile finishes loading or is dropped, not every time someone asks for the list.
static func _layout_key() -> String:
	var streamer: Node = GameState.world.streamer if GameState.world else null
	if streamer == null:
		return Sites.active
	var parts: Array[String] = []
	for loc in streamer.tiles:
		if streamer.is_ready(loc):
			parts.append("%d,%d=%s" % [loc.x, loc.y, streamer.tiles[loc].pack])
	parts.sort()
	return "|".join(parts)


static func _rebuild(key: String) -> void:
	_merged = []
	_by_tunnus = {}
	var streamer: Node = GameState.world.streamer if GameState.world else null
	if streamer == null:
		_add(Sites.active, Vector3.ZERO)
	else:
		# the origin tile first, so a unit two tiles share keeps the coordinates of the one we are in
		var locs: Array = streamer.tiles.keys()
		locs.sort_custom(func(a, b): return a.length_squared() < b.length_squared())
		for loc in locs:
			if streamer.is_ready(loc):
				_add(str(streamer.tiles[loc].pack), streamer.offset_of(loc))
	_merged_key = key


static func _add(pack: String, offset: Vector3) -> void:
	if pack == "":
		return
	for u in units(pack):
		var tunnus := str(u.get("tunnus", ""))
		if tunnus == "" or _by_tunnus.has(tunnus):
			continue
		var row: Dictionary = u.duplicate()
		row["pack"] = pack
		row["x"] = float(u.get("x", 0)) + offset.x
		row["z"] = float(u.get("z", 0)) + offset.z
		if offset != Vector3.ZERO:
			# a new array, not the cached one shifted: units() hands out the pack's own file and the
			# boundary has to stay in that pack's metres for whoever asks for it there
			var moved: Array = []
			for c in u.get("polygon", []):
				moved.append([float(c[0]) + offset.x, float(c[1]) + offset.z])
			row["polygon"] = moved
		_merged.append(row)
		_by_tunnus[tunnus] = row
