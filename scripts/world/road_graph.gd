# The road network as a graph: ETAK segments (sites/<id>/roads.json) become edges between nodes
# snapped within a metre. Agents walk, ride and drive along edges and pick the next one at nodes.
class_name RoadGraph
extends RefCounted

var edges: Array[Dictionary] = []     # {id, kind, width, pts: PackedVector2Array, cum: PackedFloat32Array, length, a, b, name}
var node_edges: Dictionary = {}       # node id -> Array[int]
var _nodes: PackedVector2Array = PackedVector2Array()


static func from_pack(pack: String = "") -> RoadGraph:
	var g := RoadGraph.new()
	var text := FileAccess.get_file_as_string(Sites.path_in(pack if pack != "" else Sites.active, "roads.json"))
	var parsed = JSON.parse_string(text) if text != "" else null
	if typeof(parsed) == TYPE_DICTIONARY:
		g.build(parsed.get("roads", []))
	return g


func build(roads: Array) -> void:
	for r in roads:
		var pts := PackedVector2Array()
		for p in r.points:
			pts.append(Vector2(float(p[0]), float(p[1])))
		if pts.size() < 2:
			continue
		var cum := PackedFloat32Array([0.0])
		for i in range(1, pts.size()):
			cum.append(cum[i - 1] + pts[i - 1].distance_to(pts[i]))
		if cum[-1] < 2.0:
			continue
		var e := {"id": edges.size(), "kind": str(r.get("kind", "road")), "width": float(r.get("width", 4.0)), "pts": pts, "cum": cum,
				"length": cum[-1], "a": _node(pts[0]), "b": _node(pts[-1]), "name": str(r.get("name", "") if r.get("name") else "")}
		edges.append(e)
		node_edges[e.a].append(e.id)
		node_edges[e.b].append(e.id)


func _node(p: Vector2) -> int:
	for i in _nodes.size():
		if _nodes[i].distance_squared_to(p) < 1.0:
			return i
	_nodes.append(p)
	node_edges[_nodes.size() - 1] = []
	return _nodes.size() - 1


## Position along an edge at distance s from its start.
func point_at(e: Dictionary, s: float) -> Vector2:
	var cum: PackedFloat32Array = e.cum
	var pts: PackedVector2Array = e.pts
	s = clampf(s, 0.0, e.length)
	var i := 1
	while i < cum.size() - 1 and cum[i] < s:
		i += 1
	var seg := cum[i] - cum[i - 1]
	var t := 0.0 if seg <= 0.0 else (s - cum[i - 1]) / seg
	return pts[i - 1].lerp(pts[i], t)


func dir_at(e: Dictionary, s: float, forward: bool) -> Vector2:
	var d := point_at(e, minf(s + 1.0, e.length)) - point_at(e, maxf(s - 1.0, 0.0))
	if d.length_squared() < 0.0001:
		d = (e.pts[-1] - e.pts[0])
	d = d.normalized()
	return d if forward else -d


## Edges of the given kinds whose middle lies between rmin and rmax from `center`.
func edges_near(center: Vector2, rmin: float, rmax: float, kinds: Array) -> Array[int]:
	var out: Array[int] = []
	for e in edges:
		if not (e.kind in kinds):
			continue
		var d := point_at(e, e.length * 0.5).distance_to(center)
		if d >= rmin and d <= rmax:
			out.append(e.id)
	return out


## Where to go from the end of `e` (travelling `forward`): another edge of an allowed kind at that
## node, preferring not to turn straight back. Returns {edge, forward} or {} at a dead end.
func next_edge(e: Dictionary, forward: bool, kinds: Array, rng: RandomNumberGenerator) -> Dictionary:
	var node: int = e.b if forward else e.a
	var options := []
	for id in node_edges.get(node, []):
		var n: Dictionary = edges[id]
		if id != e.id and n.kind in kinds:
			options.append(n)
	if options.is_empty():
		if e.kind in kinds:
			return {"edge": e, "forward": not forward}   # dead end: turn around
		return {}
	var n: Dictionary = options[rng.randi() % options.size()]
	return {"edge": n, "forward": n.a == node}
