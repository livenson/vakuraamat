# What OpenStreetMap maps on a pack's streets (tools/pipeline/fetch_osm.py writes street.json): the
# lamps, traffic signals, crossings, benches, bins, bike racks, bollards, the fences, hedges and walls,
# flowerbeds and piers. Read by RoadNetwork (lamps), StreetFurniture (the rest), TrafficSignals, and
# ParcelKit, which leaves out its own hedge, fence or benches where the map has the real ones. Cached
# per file, dropped by GameState.reload().
class_name StreetData
extends RefCounted

static var _cache: Dictionary = {}   # street.json path -> Dictionary (empty when the pack has none)


static func of(pack: String) -> Dictionary:
	var path := Sites.path_in(pack if pack != "" else Sites.active, "street.json")
	if not _cache.has(path):
		var d := {}
		if FileAccess.file_exists(path):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
			if typeof(parsed) == TYPE_DICTIONARY:
				d = parsed
		_cache[path] = d
	return _cache[path]


static func forget() -> void:
	_cache.clear()


## The world position of the tile a node stands on: a streamed tile's root, else the origin.
static func tile_origin(node: Node) -> Vector3:
	var n: Node = node
	while n:
		if n.has_meta("pack_id") and n is Node3D:
			return (n as Node3D).global_position
		n = n.get_parent()
	return Vector3.ZERO


## Whether the map has a fence, hedge or wall along or inside `poly` (tile metres): any of its points
## within `reach` of the outline or inside it.
static func barrier_near(pack: String, poly: PackedVector2Array, reach := 2.0) -> bool:
	if poly.size() < 3:
		return false
	var box := _box(poly).grow(reach)
	for b in of(pack).get("barriers", []):
		for q in b.get("points", []):
			var p := Vector2(float(q[0]), float(q[1]))
			if not box.has_point(p):
				continue
			if Geometry2D.is_point_in_polygon(p, poly) or _to_outline(p, poly) <= reach:
				return true
	return false


## Whether the map has a piece of furniture of `kind` (bench, bin, ...) inside `poly` (tile metres).
static func furniture_in(pack: String, poly: PackedVector2Array, kind: String) -> bool:
	if poly.size() < 3:
		return false
	var box := _box(poly)
	for f in of(pack).get("furniture", []):
		if str(f.get("kind", "")) != kind:
			continue
		var p := Vector2(float(f.get("x", 0.0)), float(f.get("z", 0.0)))
		if box.has_point(p) and Geometry2D.is_point_in_polygon(p, poly):
			return true
	return false


static func _box(poly: PackedVector2Array) -> Rect2:
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	return r


static func _to_outline(p: Vector2, poly: PackedVector2Array) -> float:
	var best := INF
	for i in poly.size():
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])))
	return best
