# Traffic lights where OpenStreetMap maps them (street.json "signals"), on a pack's road graph. A
# signal within JUNCTION_REACH of a junction controls that junction: its arms take turns in two groups
# by direction (the arms along the first street one way, those across it the other), so a car coming
# in on a red arm waits at the line. A signal with no junction near is a pedestrian crossing's: the
# cars on its street stop for the walkers part of the cycle. The phases run on the real clock, like
# the cars. StreetFurniture draws the heads and lights their lenses from the same state.
class_name TrafficSignals
extends RefCounted

const CYCLE := 40.0              # seconds for both groups to have had their green
const AMBER := 3.0
const JUNCTION_REACH := 25.0     # how far a mapped signal may stand from the junction it controls
const CROSSING_REACH := 10.0     # how far a lone signal may stand from its street
const STOP_BACK := 7.0           # metres short of the junction's centre where a car waits

enum { GREEN, AMBER_LIGHT, RED }

var junctions: Dictionary = {}   # graph node id -> {pos: Vector2, axis: Vector2, offset: float}
var crossings: Array = []        # [{pos: Vector2, edge: int, s: float, offset: float}]
static var _by_pack: Dictionary = {}


## The signals of `pack`, built once per pack: the traffic's graph and the furniture's are made from
## the same roads.json, so their node ids agree and the heads show the light the cars obey.
static func of(pack: String, graph: RoadGraph) -> TrafficSignals:
	var key := pack
	if not _by_pack.has(key):
		var ts := TrafficSignals.new()
		ts._build(StreetData.of(pack).get("signals", []), graph)
		_by_pack[key] = ts
	return _by_pack[key]


static func forget() -> void:
	_by_pack.clear()


func _build(signals: Array, graph: RoadGraph) -> void:
	var car_kinds := ["street", "road"]
	for q in signals:
		var p := Vector2(float(q[0]), float(q[1]))
		# the nearest junction of three or more car arms
		var best := -1
		var best_d := JUNCTION_REACH
		for id in graph.edges_near(p, 0.0, JUNCTION_REACH + RoadGraph.CELL, car_kinds):
			var e: Dictionary = graph.edges[id]
			for n: int in [e.a, e.b]:
				if _arms(graph, n, car_kinds).size() < 3:
					continue
				var d := graph.node_pos(n).distance_to(p)
				if d < best_d:
					best_d = d
					best = n
		if best >= 0:
			if not junctions.has(best):
				var arms := _arms(graph, best, car_kinds)
				var first: Dictionary = graph.edges[arms[0]]
				var axis := graph.dir_at(first, 0.0 if first.a == best else first.length, first.a == best)
				junctions[best] = {"pos": graph.node_pos(best), "axis": axis, "offset": float(hash(best) % 40)}
			continue
		# a crossing's lights: the nearest car edge and where along it
		var near := {}
		var near_d := CROSSING_REACH
		for id in graph.edges_near(p, 0.0, CROSSING_REACH + RoadGraph.CELL, car_kinds):
			var e: Dictionary = graph.edges[id]
			var s := graph.nearest_s(e, p)
			var d := graph.point_at(e, s).distance_to(p)
			if d < near_d:
				near_d = d
				near = {"pos": p, "edge": id, "s": s, "offset": float(hash(p) % 40)}
		if not near.is_empty():
			crossings.append(near)


static func _arms(graph: RoadGraph, node: int, kinds: Array) -> Array:
	return graph.node_edges.get(node, []).filter(func(id): return graph.edges[id].kind in kinds)


## The light a car sees coming into `node` travelling `dir`: GREEN, AMBER_LIGHT or RED.
func junction_state(node: int, dir: Vector2) -> int:
	var j: Dictionary = junctions[node]
	var group := 0 if absf(dir.dot(j.axis)) >= 0.7071 else 1
	return group_state(group, float(j.offset))


## The light of one of a junction's two groups at this moment.
static func group_state(group: int, offset: float) -> int:
	var t := fmod(Time.get_ticks_msec() / 1000.0 + offset, CYCLE)
	var half := CYCLE * 0.5
	var own := t if group == 0 else fmod(t + half, CYCLE)   # the other group is half a cycle behind
	if own < half - AMBER:
		return GREEN
	if own < half:
		return AMBER_LIGHT
	return RED


## The cars' light at a pedestrian crossing: green most of the cycle, red while the walkers cross.
static func crossing_state(offset: float) -> int:
	var t := fmod(Time.get_ticks_msec() / 1000.0 + offset, CYCLE)
	if t < CYCLE * 0.7:
		return GREEN
	if t < CYCLE * 0.7 + AMBER:
		return AMBER_LIGHT
	return RED


## How far ahead a car on `edge` at `s`, going `forward`, has to stop for a light: INF when nothing
## ahead on this edge is red (or amber and still far enough to stop for).
func stop_distance(graph: RoadGraph, edge: Dictionary, s: float, forward: bool) -> float:
	var best := INF
	var node: int = edge.b if forward else edge.a
	if junctions.has(node):
		var to_node: float = (edge.length - s) if forward else s
		var line := to_node - STOP_BACK
		if line > -1.0 and line < 40.0:
			var st := junction_state(node, graph.dir_at(edge, s, forward))
			if st == RED or (st == AMBER_LIGHT and line > 4.0):
				best = maxf(line, 0.0)
	for c in crossings:
		if int(c.edge) != int(edge.id):
			continue
		var d: float = (float(c.s) - s) if forward else (s - float(c.s))
		var line := d - 3.0
		if line > -1.0 and line < 40.0:
			var st := crossing_state(float(c.offset))
			if st == RED or (st == AMBER_LIGHT and line > 4.0):
				best = minf(best, maxf(line, 0.0))
	return best
