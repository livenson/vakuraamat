# Rails from OpenStreetMap (rail.json, tools/pipeline/fetch_osm.py) and what runs on them, built under
# the RoadNetwork after the street furniture: tram tracks laid in the street (the rails flush with the
# asphalt) or on their own bed, railway lines on ballast and sleepers, the trams and trains that use
# them. Double track runs on the right: a track whose twin lies to its left is travelled forward only,
# one whose twin lies to its right backward only, a single track either way. A tram stops at the tram
# stops the map has beside its track and keeps a headway of one per TRAM_SPACING metres of line; a
# train comes through every few minutes. A line leaving the tile ends at its margin, and so does the
# vehicle on it (the neighbour's own carries on); new ones come in where a line enters.
class_name Rails
extends Node3D

const TRAM_MODEL := "res://assets/vendor/sketchfab/tram.glb"
const TRAIN_MODEL := "res://assets/vendor/sketchfab/train.glb"
const TRAM := {"length": 30.0, "cars": 1, "speed": 8.0}      # Helsinki's Artic is 27.6 m, Rīga's Škoda 15T 31 m
const TRAIN := {"length": 75.0, "cars": 1, "speed": 14.0}    # the model is a whole four-car FLIRT unit
const TRAM_SPACING := 450.0     # metres of line per tram
const MAX_TRAMS := 8
const TRAIN_EVERY := Vector2(70.0, 160.0)   # real seconds between trains
const ACTIVE_REACH := 900.0     # vehicles only move on a tile whose middle is this near the player
const EDGE_REACH := 45.0        # a line end this near the tile's edge is where vehicles come and go
const STEEL := Color(0.52, 0.52, 0.54)
const BALLAST := Color(0.46, 0.44, 0.41)
const SLEEPER := Color(0.3, 0.26, 0.22)

var graph: RoadGraph
var dir_ok: Dictionary = {}     # edge id -> 0 either way, 1 forward only, -1 backward only
var stops_on: Dictionary = {}   # edge id -> Array of distances along it where a tram stops
var vehicles: Array = []
var size_m := 1024.0
var _rn: RoadNetwork
var _terrain: Terrain3D
var _entries := {"tram": [], "rail": []}   # [edge id, forward]: where a line comes into the tile
var _tram_target := 0
var _tram_in := 0.0
var _train_in := 20.0
var _rng := RandomNumberGenerator.new()


## The tracks drawn, the graph built, the first trams placed. False when the network left the tree.
func build(rn: RoadNetwork, terrain: Terrain3D) -> bool:
	_rn = rn
	_terrain = terrain
	var pack := Sites.pack_of(rn)
	var path := Sites.path_in(pack, "rail.json")
	if not FileAccess.file_exists(path):
		return true
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY or parsed.get("tracks", []).is_empty():
		return true
	size_m = float(TerrainBuilder.read_meta(Sites.tile_dir_of(pack)).get("size_m", 1024.0))
	_rng.seed = hash(pack)
	var tracks: Array = parsed.tracks
	if not await _draw(tracks):
		return false
	graph = RoadGraph.new()
	var lines: Array = []
	for t in tracks:
		lines.append({"kind": "tram" if str(t.get("kind", "")) in ["tram", "light_rail"] else "rail", "width": float(t.get("gauge", 1435)) / 1000.0,
			"points": t.points, "name": t.get("name"), "bridge": t.get("bridge") == true})
	graph.build(lines)
	_directions()
	_stop_marks(parsed.get("stops", []))
	_find_entries()
	var tram_m := 0.0
	for e in graph.edges:
		if e.kind == "tram":
			tram_m += e.length
	if tram_m > 150.0 and ResourceLoader.exists(TRAM_MODEL):
		_tram_target = clampi(int(tram_m * 0.5 / TRAM_SPACING), 1, MAX_TRAMS)   # both tracks of a line are counted
		for i in _tram_target:
			_spawn_anywhere("tram")
	return true


func _physics_process(delta: float) -> void:
	if graph == null or GameState.world == null or GameState.world.player == null:
		return
	var player: Node3D = GameState.world.player
	var mid := to_global(Vector3(size_m * 0.5, 0.0, size_m * 0.5))
	if Vector2(player.global_position.x - mid.x, player.global_position.z - mid.z).length() > ACTIVE_REACH:
		return
	for v in vehicles:
		if is_instance_valid(v):
			v.advance(delta, vehicles)
	vehicles = vehicles.filter(func(v): return is_instance_valid(v) and not v.is_queued_for_deletion())
	var trams := vehicles.filter(func(v): return v.kind == "tram").size()
	_tram_in -= delta
	if trams < _tram_target and _tram_in <= 0.0:
		_tram_in = _rng.randf_range(8.0, 20.0)
		_spawn_at_entry("tram")
	_train_in -= delta
	if _train_in <= 0.0:
		_train_in = _rng.randf_range(TRAIN_EVERY.x, TRAIN_EVERY.y)
		if ResourceLoader.exists(TRAIN_MODEL):
			_spawn_at_entry("rail")


# ---------------------------------------------------------------- the way on

## Where a vehicle goes from the end of `e` travelling `forward`: the straightest track on of its own
## kind that may be travelled that way. {} where the line ends (at the tile's edge it leaves; a single
## track ending inside the tile turns it round).
func next_edge(e: Dictionary, forward: bool) -> Dictionary:
	var node: int = e.b if forward else e.a
	var here := graph.dir_at(e, e.length if forward else 0.0, forward)
	var best := {}
	var best_dot := -0.3
	for id in graph.node_edges.get(node, []):
		if id == e.id:
			continue
		var n: Dictionary = graph.edges[id]
		if n.kind != e.kind:
			continue
		var fwd: bool = n.a == node
		var ok: int = dir_ok.get(id, 0)
		if (fwd and ok < 0) or (not fwd and ok > 0):
			continue
		var d := graph.dir_at(n, 0.0 if fwd else n.length, fwd)
		var dot := d.dot(here)
		if dot > best_dot:
			best_dot = dot
			best = {"edge": n, "forward": fwd}
	if best.is_empty() and int(dir_ok.get(e.id, 0)) == 0 and not _near_edge(graph.node_pos(node)):
		return {"edge": e, "forward": not forward}   # a terminus stub: back the way it came
	return best


## The rail's top at a point of an edge: the ground, or a straight line between a bridge's ends.
func rail_height(e: Dictionary, s: float, p: Vector2) -> float:
	var top := (_rn.lift + 0.02) if e.kind == "tram" else 0.34
	if e.get("bridge") == true:
		var ya := _ground(e.pts[0])
		var yb := _ground(e.pts[-1])
		return lerpf(ya, yb, s / maxf(e.length, 0.01)) + top
	return _ground(p) + top


func _ground(p: Vector2) -> float:
	return _rn._on_ground(p, _terrain, 0.0).y


func _near_edge(p: Vector2) -> bool:
	return p.x < EDGE_REACH or p.y < EDGE_REACH or p.x > size_m - EDGE_REACH or p.y > size_m - EDGE_REACH


func _on_tile(p: Vector2) -> bool:
	return p.x >= 0.0 and p.y >= 0.0 and p.x < size_m and p.y < size_m


## Which way each track may be travelled: its twin (a parallel track 2.4-5 m beside it) on the left
## means forward, on the right backward, none either way.
func _directions() -> void:
	var cells := {}
	for e in graph.edges:
		var pts: PackedVector2Array = e.pts
		for i in range(1, pts.size()):
			var n := maxi(1, int(pts[i - 1].distance_to(pts[i]) / 8.0))
			for j in n + 1:
				var q := pts[i - 1].lerp(pts[i], float(j) / n)
				var c := Vector2i(floori(q.x / 16.0), floori(q.y / 16.0))
				var list: Array = cells.get_or_add(c, [])
				var seg := [pts[i - 1], pts[i], e.id]
				if list.is_empty() or list[-1] != seg:
					list.append(seg)
	for e in graph.edges:
		var s: float = e.length * 0.5
		var p := graph.point_at(e, s)
		var d := graph.dir_at(e, s, true)
		var right := Vector2(-d.y, d.x)
		var on_left := _twin(cells, e, p, -right, d)
		var on_right := _twin(cells, e, p, right, d)
		dir_ok[e.id] = 1 if on_left and not on_right else (-1 if on_right and not on_left else 0)


func _twin(cells: Dictionary, e: Dictionary, p: Vector2, side: Vector2, d: Vector2) -> bool:
	for o: float in [2.4, 3.0, 3.6, 4.2, 4.8]:
		var q: Vector2 = p + side * o
		var c := Vector2i(floori(q.x / 16.0), floori(q.y / 16.0))
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for seg in cells.get(c + Vector2i(dx, dy), []):
					if seg[2] == e.id or graph.edges[seg[2]].kind != e.kind:
						continue
					var a: Vector2 = seg[0]
					var b: Vector2 = seg[1]
					if absf((b - a).normalized().dot(d)) < 0.9:
						continue
					if Geometry2D.get_closest_point_to_segment(q, a, b).distance_to(q) < 0.5:
						return true
	return false


## Every tram edge passing within 15 m of a mapped tram stop stops there.
func _stop_marks(stops: Array) -> void:
	for st in stops:
		if str(st.get("kind", "")) != "tram":
			continue
		var p := Vector2(float(st.get("x", 0.0)), float(st.get("z", 0.0)))
		for e in graph.edges:
			if e.kind != "tram":
				continue
			var s := graph.nearest_s(e, p)
			if graph.point_at(e, s).distance_to(p) < 15.0:
				stops_on.get_or_add(e.id, []).append(s)


## The line ends at the tile's edge where a vehicle may enter, by kind.
func _find_entries() -> void:
	for e in graph.edges:
		var ok: int = dir_ok.get(e.id, 0)
		for end in [[e.a, true], [e.b, false]]:
			var node: int = end[0]
			if graph.node_edges.get(node, []).size() != 1 or not _near_edge(graph.node_pos(node)):
				continue
			var fwd: bool = end[1]
			if (fwd and ok < 0) or (not fwd and ok > 0):
				continue
			_entries[e.kind].append([e.id, fwd])


func _spawn_anywhere(kind: String) -> void:
	var edges := graph.edges.filter(func(e): return e.kind == kind and e.length > 20.0)
	if edges.is_empty():
		return
	var e: Dictionary = edges[_rng.randi() % edges.size()]
	var ok: int = dir_ok.get(e.id, 0)
	var fwd := ok > 0 or (ok == 0 and _rng.randf() < 0.5)
	_spawn(kind, e, _rng.randf_range(0.2, 0.8) * e.length, fwd)


func _spawn_at_entry(kind: String) -> void:
	var list: Array = _entries.get(kind, [])
	if list.is_empty():
		return
	var pick: Array = list[_rng.randi() % list.size()]
	var e: Dictionary = graph.edges[int(pick[0])]
	var fwd: bool = pick[1]
	for v in vehicles:   # the entry is still occupied by the last one in
		if v.edge.id == e.id and ((v.s < 60.0) if fwd else (v.s > e.length - 60.0)):
			return
	_spawn(kind, e, 0.0 if fwd else e.length, fwd)


func _spawn(kind: String, e: Dictionary, s: float, fwd: bool) -> void:
	var spec: Dictionary = TRAM if kind == "tram" else TRAIN
	var v := RailVehicle.new()
	add_child(v)
	if v.setup(self, kind, e, s, fwd, TRAM_MODEL if kind == "tram" else TRAIN_MODEL, float(spec.length), int(spec.cars), float(spec.speed)):
		vehicles.append(v)
	else:
		v.queue_free()


# ---------------------------------------------------------------- the tracks

## Rails, sleepers and ballast as one vertex-coloured mesh, cut to the tile.
func _draw(tracks: Array) -> bool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 0
	for i in tracks.size():
		var t: Dictionary = tracks[i]
		var pts := _rn._resample(t.points)
		var g := float(t.get("gauge", 1435)) / 1000.0
		var embedded: bool = t.get("embedded") == true
		var hs: Array[float] = []
		for p in pts:
			hs.append(_ground(p))
		if t.get("bridge") == true and hs.size() >= 2:
			for k in hs.size():
				hs[k] = lerpf(hs[0], hs[-1], float(k) / (hs.size() - 1))
		var acc := 0.0
		for k in range(1, pts.size()):
			var a: Vector2 = pts[k - 1]
			var b: Vector2 = pts[k]
			var seg := a.distance_to(b)
			if not _on_tile((a + b) * 0.5) or seg < 0.05:
				acc += seg
				continue
			if embedded:
				for side in [-1.0, 1.0]:
					_strip(st, a, b, hs[k - 1], hs[k], side * g * 0.5, 0.07, _rn.lift + 0.004, _rn.lift + 0.018, STEEL)
			else:
				_strip(st, a, b, hs[k - 1], hs[k], 0.0, g + 1.8, -0.1, 0.12, BALLAST)
				var d := (b - a) / seg
				var x := fmod(0.65 - fmod(acc, 0.65), 0.65)
				while x < seg:
					var c := a + d * x
					var y := lerpf(hs[k - 1], hs[k], x / seg)
					_strip(st, c - d * 0.12, c + d * 0.12, y, y, 0.0, g + 0.55, 0.1, 0.2, SLEEPER)
					x += 0.65
				for side in [-1.0, 1.0]:
					_strip(st, a, b, hs[k - 1], hs[k], side * g * 0.5, 0.07, 0.2, 0.34, STEEL)
			acc += seg
			n += 1
		if i % 20 == 0 and not await _rn._breathe():
			return false
	if n == 0:
		return true
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = "Tracks"
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.7
	mi.material_override = m
	mi.visibility_range_end = 600.0
	add_child(mi)
	return true


## A box from `a` to `b` shifted `offset` metres to the side, `width` wide, from `lo` to `hi` above
## the heights at its ends: its top and long sides.
func _strip(st: SurfaceTool, a: Vector2, b: Vector2, ya: float, yb: float, offset: float, width: float, lo: float, hi: float, col: Color) -> void:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x)
	var l := n * (offset - width * 0.5)
	var r := n * (offset + width * 0.5)
	var p := [Vector3(a.x + l.x, ya + lo, a.y + l.y), Vector3(b.x + l.x, yb + lo, b.y + l.y), Vector3(b.x + l.x, yb + hi, b.y + l.y), Vector3(a.x + l.x, ya + hi, a.y + l.y),
		Vector3(a.x + r.x, ya + lo, a.y + r.y), Vector3(b.x + r.x, yb + lo, b.y + r.y), Vector3(b.x + r.x, yb + hi, b.y + r.y), Vector3(a.x + r.x, ya + hi, a.y + r.y)]
	for f in [[3, 2, 6, 7], [0, 1, 2, 3], [5, 4, 7, 6]]:
		var q0: Vector3 = p[f[0]]
		var q1: Vector3 = p[f[1]]
		var q2: Vector3 = p[f[2]]
		var q3: Vector3 = p[f[3]]
		var nrm := (q1 - q0).cross(q3 - q0).normalized()
		if f[0] == 3 and nrm.y < 0.0:
			nrm = -nrm
		for v in [q0, q1, q2, q0, q2, q3]:
			st.set_normal(nrm)
			st.set_color(col)
			st.add_vertex(v)
