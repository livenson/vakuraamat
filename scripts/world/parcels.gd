# Cadastral units of the active pack (sites/<id>/parcels.json), for the codes overlay, the debug map
# and F8 reports: which unit is under a point, its number, purpose and the registry link.
class_name Parcels
extends RefCounted

static var _cache: Dictionary = {}   # pack path -> Array of units


static func units(pack: String = "") -> Array:
	var path := Sites.path_in(pack if pack != "" else Sites.active, "parcels.json")
	if not _cache.has(path):
		var text := FileAccess.get_file_as_string(path)
		var parsed = JSON.parse_string(text) if text != "" else null
		_cache[path] = parsed.get("parcels", []) if typeof(parsed) == TYPE_DICTIONARY else []
	return _cache[path]


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
