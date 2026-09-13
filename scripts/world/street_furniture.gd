# What OpenStreetMap maps along a pack's streets (street.json, tools/pipeline/fetch_osm.py), built under
# the RoadNetwork after its ribbons and lamps: zebra stripes on the marked crossings, traffic lights at
# the signalled junctions and crossings (their lenses follow TrafficSignals, the state the cars obey),
# benches, bins, bike racks and bollards where they stand, the fences, hedges and walls, flowerbeds and
# piers. Nothing here is placed by rule: a street the map has no bench on has none. Pieces are cut to
# the tile (a line crossing into the neighbour is drawn by the tile its middle is on), so two tiles
# never draw one fence twice.
class_name StreetFurniture
extends Node3D

const RANGE := 250.0             # benches, bins and bollards are specks beyond this
const BARRIER_RANGE := 450.0
const SIGNAL_RANGE := 300.0
const MODELS := {"bench": ["park_bench", 1.8, false], "bin": ["litter_bin", 0.95, true], "bike_rack": ["bike_rack", 0.85, true],
	"bollard": ["bollard", 0.9, true]}   # kind -> [sketchfab model, metres, fitted by height (else longest side)]
const SKETCHFAB := "res://assets/vendor/sketchfab/"
# kind -> [height m, thickness m, colour]; the map's height tag wins where it has one
const BARRIERS := {
	"fence": [1.4, 0.06, Color(0.42, 0.43, 0.44)],
	"hedge": [1.2, 0.8, Color(0.2, 0.36, 0.15)],
	"wall": [1.8, 0.3, Color(0.6, 0.56, 0.5)],
	"retaining_wall": [1.0, 0.4, Color(0.58, 0.57, 0.55)],
	"city_wall": [5.0, 1.5, Color(0.56, 0.5, 0.43)],
	"guard_rail": [0.75, 0.08, Color(0.72, 0.73, 0.74)],
	"jersey_barrier": [0.8, 0.6, Color(0.76, 0.75, 0.72)],
}
const WOOD := Color(0.45, 0.32, 0.2)
const BRICK := Color(0.55, 0.3, 0.22)
const FLOWERS := [Color(0.85, 0.2, 0.25), Color(0.95, 0.75, 0.2), Color(0.9, 0.9, 0.92), Color(0.6, 0.3, 0.75), Color(0.95, 0.5, 0.2)]

var _rn: RoadNetwork
var _terrain: Terrain3D
var _size := 1024.0
var _heads: Array = []           # [{lenses: [MeshInstance3D x3], group: int (-1 crossing, -2 walkers), offset, state}]
var _clock := 0.0
static var _lens_mats: Dictionary = {}   # "red1" | "red0" | "amber1" ... -> StandardMaterial3D


static func release() -> void:
	_lens_mats.clear()


## Everything street.json lists, a few milliseconds a frame (the network's budget). False when the
## network left the tree meanwhile.
func build(rn: RoadNetwork, terrain: Terrain3D) -> bool:
	_rn = rn
	_terrain = terrain
	var pack := Sites.pack_of(rn)
	var data := StreetData.of(pack)
	if data.is_empty():
		return true
	_size = float(TerrainBuilder.read_meta(Sites.tile_dir_of(pack)).get("size_m", 1024.0))
	_crossings(data.get("crossings", []))
	if not await rn._breathe():
		return false
	_signals(pack)
	if not await rn._breathe():
		return false
	_furniture(data.get("furniture", []))
	if not await rn._breathe():
		return false
	_parking(data.get("parking", {}))
	if not await rn._breathe():
		return false
	return await _solids(data)


## Barriers, flowerbeds and piers: one vertex-coloured mesh and one collider.
func _solids(data: Dictionary) -> bool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 0
	var items: Array = []
	for b in data.get("barriers", []):
		items.append(["barrier", b])
	for bed in data.get("flowerbeds", []):
		items.append(["bed", bed])
	for p in data.get("piers", []):
		items.append(["pier", p])
	for i in items.size():
		var it: Array = items[i]
		match str(it[0]):
			"barrier":
				n += _barrier(st, it[1])
			"bed":
				n += _flowerbed(st, it[1])
			_:
				n += _pier(st, it[1])
		if i % 40 == 39 and not await _rn._breathe():
			return false
	if n > 0:
		_solid(st, "Barriers", BARRIER_RANGE)
	return true


func _process(delta: float) -> void:
	_clock -= delta
	if _clock > 0.0 or _heads.is_empty():
		return
	_clock = 0.25
	for h in _heads:
		var state: int
		match int(h.group):
			-1:
				state = TrafficSignals.crossing_state(float(h.offset))
			-2:   # the walkers' light: green while the cars have red
				state = TrafficSignals.GREEN if TrafficSignals.crossing_state(float(h.offset)) == TrafficSignals.RED else TrafficSignals.RED
			_:
				state = TrafficSignals.group_state(int(h.group), float(h.offset))
		if state == int(h.state):
			continue
		h.state = state
		var lenses: Array = h.lenses
		lenses[0].material_override = _lens("red", state == TrafficSignals.RED)
		if lenses.size() == 3:
			lenses[1].material_override = _lens("amber", state == TrafficSignals.AMBER_LIGHT)
		lenses[-1].material_override = _lens("green", state == TrafficSignals.GREEN)


func _on_tile(p: Vector2) -> bool:
	return p.x >= 0.0 and p.y >= 0.0 and p.x < _size and p.y < _size


# ---------------------------------------------------------------- crossings

## White bars along the road across its whole width at every marked crossing on a carriageway.
func _crossings(list: Array) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 0
	for c in list:
		if c.get("marked") != true:
			continue
		var p := Vector2(float(c.get("x", 0.0)), float(c.get("z", 0.0)))
		var r := _rn.road_near(p, ["street", "road"], 6.0)
		if r.is_empty():
			continue
		var d: Vector2 = r.dir
		var across := Vector2(-d.y, d.x)
		var half: float = maxf(float(r.width), 3.0) * 0.5
		var centre: Vector2 = r.point
		var o := -half + 0.45
		while o <= half - 0.4:
			var m := centre + across * o
			var corners := [m - d * 1.5 - across * 0.25, m - d * 1.5 + across * 0.25, m + d * 1.5 + across * 0.25, m + d * 1.5 - across * 0.25]
			var v: Array[Vector3] = []
			for q: Vector2 in corners:
				v.append(_rn._on_ground(q, _terrain, _rn.lift + 0.02))
			for i in [0, 1, 2, 0, 2, 3]:
				st.set_normal(Vector3.UP)
				st.add_vertex(v[i])
			o += 1.0
		n += 1
	if n == 0:
		return
	var mi := MeshInstance3D.new()
	mi.name = "Crossings"
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.9, 0.87)
	mat.roughness = 0.8
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = SIGNAL_RANGE
	add_child(mi)


# ---------------------------------------------------------------- traffic lights

## A head on a pole at the right-hand kerb of every arm of a signalled junction, facing the traffic
## coming in on it; at a signalled crossing with no junction, one each side for the cars and a walkers'
## light on each kerb.
func _signals(pack: String) -> void:
	var data := StreetData.of(pack)
	if data.get("signals", []).is_empty():
		return
	var graph := RoadGraph.from_pack(pack)
	var ts := TrafficSignals.of(pack, graph)
	for node: int in ts.junctions:
		var j: Dictionary = ts.junctions[node]
		for id in graph.node_edges.get(node, []):
			var e: Dictionary = graph.edges[id]
			if not (e.kind in ["street", "road"]):
				continue
			var out_dir := graph.dir_at(e, 0.0 if e.a == node else e.length, e.a == node)   # from the junction outwards
			var travel := -out_dir
			var right := Vector2(-travel.y, travel.x)
			var at: Vector2 = j.pos + out_dir * TrafficSignals.STOP_BACK + right * (float(e.width) * 0.5 + 0.8)
			if not _on_tile(at):
				continue
			var group := 0 if absf(travel.dot(j.axis)) >= 0.7071 else 1
			_head(at, out_dir, group, float(j.offset), 3.4)
	for c in ts.crossings:
		var e: Dictionary = graph.edges[int(c.edge)]
		var t := graph.dir_at(e, float(c.s), true)
		var centre := graph.point_at(e, float(c.s))
		for sgn in [1.0, -1.0]:
			var travel: Vector2 = t * sgn
			var right := Vector2(-travel.y, travel.x)
			var kerb := centre + right * (float(e.width) * 0.5 + 0.8)
			if _on_tile(kerb):
				_head(kerb - travel * 2.0, -travel, -1, float(c.offset), 3.4)
				_head(kerb + travel * 1.0, Vector2(-right.x, -right.y), -2, float(c.offset), 2.4)   # the walkers', facing across


## A pole with a three-lens head `height` up, the lenses facing `face` (tile metres, unit).
func _head(at: Vector2, face: Vector2, group: int, offset: float, height: float) -> void:
	var base := _rn._on_ground(at, _terrain, 0.0)
	var holder := Node3D.new()
	holder.position = base
	holder.rotation.y = atan2(face.x, face.y)   # local +Z onto `face`
	add_child(holder)
	var pole := MeshInstance3D.new()
	pole.mesh = _shared_mesh("pole")
	pole.material_override = _lens("pole", false)
	pole.position = Vector3(0, height * 0.5, 0)
	pole.scale = Vector3(1, height, 1)
	pole.visibility_range_end = SIGNAL_RANGE
	holder.add_child(pole)
	var box := MeshInstance3D.new()
	box.mesh = _shared_mesh("head")
	box.material_override = _lens("pole", false)
	box.position = Vector3(0, height + 0.1, 0.12)
	box.visibility_range_end = SIGNAL_RANGE
	holder.add_child(box)
	var lenses: Array = []
	var small := group == -2
	for i in (2 if small else 3):
		var lens := MeshInstance3D.new()
		lens.mesh = _shared_mesh("lens")
		lens.rotation.x = PI / 2.0
		lens.position = Vector3(0, height + 0.1 + (0.15 - i * 0.3 if small else 0.3 - i * 0.3), 0.25)
		lens.visibility_range_end = SIGNAL_RANGE
		lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(lens)
		lenses.append(lens)
	_heads.append({"lenses": lenses, "group": group, "offset": offset, "state": -1})


func _shared_mesh(key: String) -> Mesh:
	match key:
		"pole":
			var c := CylinderMesh.new()
			c.top_radius = 0.06
			c.bottom_radius = 0.07
			c.height = 1.0
			c.radial_segments = 8
			c.rings = 1
			return c
		"head":
			var b := BoxMesh.new()
			b.size = Vector3(0.34, 0.98, 0.22)
			return b
		_:
			var l := CylinderMesh.new()
			l.top_radius = 0.1
			l.bottom_radius = 0.1
			l.height = 0.04
			l.radial_segments = 12
			l.rings = 1
			return l


static func _lens(colour: String, on: bool) -> StandardMaterial3D:
	var key := colour + ("1" if on else "0")
	if not _lens_mats.has(key):
		var m := StandardMaterial3D.new()
		var c: Color = {"red": Color(1.0, 0.12, 0.08), "amber": Color(1.0, 0.62, 0.05), "green": Color(0.15, 1.0, 0.45), "pole": Color(0.2, 0.21, 0.22)}[colour]
		if colour == "pole":
			m.albedo_color = c
			m.roughness = 0.6
		elif on:
			m.albedo_color = c
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = 4.0
		else:
			m.albedo_color = c.darkened(0.8)
			m.roughness = 0.3
		_lens_mats[key] = m
	return _lens_mats[key]


# ---------------------------------------------------------------- benches, bins, racks, bollards

## Each piece where it stands, facing where the map says or the nearest path; one MultiMesh per model
## and 128 m cell. A kind whose model is not vendored draws a plain stand-in.
func _furniture(list: Array) -> void:
	var cells: Dictionary = {}   # "<kind>" -> {Vector2i: Array[Transform3D]}
	var walls := _barrier_grid()
	for f in list:
		var kind := str(f.get("kind", ""))
		if not (kind in MODELS or kind == "block"):
			continue
		var p := Vector2(float(f.get("x", 0.0)), float(f.get("z", 0.0)))
		if not _on_tile(p):
			continue
		# a piece mapped against a fence or wall stands clear of it, a bench with its back to it (playtest
		# 2026-09-13, Helsinki: "bench is going through the fence")
		var back := _clear_of(walls, p, float(CLEARANCE.get(kind, 0.5)))
		p = back[0]
		var face := Vector2.DOWN
		if f.get("dir") != null:
			var a := deg_to_rad(float(f.dir))
			face = Vector2(sin(a), -cos(a))   # the map's direction: 0 = north, clockwise
		elif back[1] != Vector2.ZERO:
			face = back[1]
		else:
			var r := _rn.road_near(p, ["path", "street", "road", "trail"], 12.0)
			if not r.is_empty() and (r.point as Vector2).distance_to(p) > 0.2:
				face = ((r.point as Vector2) - p).normalized()
		var xf := Transform3D(Basis(Vector3.UP, atan2(face.x, face.y)), _rn._on_ground(p, _terrain, 0.0))
		var cell := Vector2i(floori(p.x / RoadNetwork.LAMP_CELL), floori(p.y / RoadNetwork.LAMP_CELL))
		cells.get_or_add(kind, {}).get_or_add(cell, []).append(xf)
	for kind in cells:
		var mesh: Mesh
		var fit := Transform3D.IDENTITY
		var mat: Material = null
		var spec: Array = MODELS.get(kind, [])
		var path := SKETCHFAB + str(spec[0]) + ".glb" if not spec.is_empty() else ""
		if path != "" and ResourceLoader.exists(path):
			mesh = MeshMerge.baked(path)
			var b := mesh.get_aabb()
			var size: float = b.size.y if spec[2] else maxf(b.size.x, b.size.z)
			var k := float(spec[1]) / maxf(size, 0.001)
			fit = Transform3D(Basis.from_scale(Vector3.ONE * k), Vector3(-(b.position.x + b.size.x * 0.5) * k, -b.position.y * k, -(b.position.z + b.size.z * 0.5) * k))
		else:
			mesh = _stand_in(kind)
			var m := StandardMaterial3D.new()
			m.albedo_color = {"bench": WOOD, "bin": Color(0.18, 0.28, 0.2), "bike_rack": Color(0.6, 0.6, 0.62), "bollard": Color(0.3, 0.31, 0.32), "block": Color(0.7, 0.69, 0.66)}[kind]
			mat = m
		for cell in cells[kind]:
			var xforms: Array = cells[kind][cell]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mesh
			mm.instance_count = xforms.size()
			for i in xforms.size():
				mm.set_instance_transform(i, xforms[i] * fit)
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "Furniture_" + kind
			mmi.multimesh = mm
			if mat:
				mmi.material_override = mat
			mmi.visibility_range_end = RANGE
			add_child(mmi)


## The painted bays (a white line round every mapped parking space) and a parked car wherever the
## photograph shows one (street.json "parking", fetch_osm.parked), from the traffic's own car models at
## their own lengths, along the bay; one MultiMesh per model and 128 m cell, a box collider each.
func _parking(p: Dictionary) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 0
	for sp in p.get("spaces", []):
		var ring: Array = sp.get("points", [])
		if ring.size() < 3:
			continue
		var c := Vector2.ZERO
		for q in ring:
			c += Vector2(float(q[0]), float(q[1]))
		if not _on_tile(c / ring.size()):
			continue
		for i in ring.size():
			var a := Vector2(float(ring[i][0]), float(ring[i][1]))
			var b := Vector2(float(ring[(i + 1) % ring.size()][0]), float(ring[(i + 1) % ring.size()][1]))
			_line(st, a, b, 0.1)
		n += 1
	if n > 0:
		var mi := MeshInstance3D.new()
		mi.name = "ParkingBays"
		mi.mesh = st.commit()
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.88, 0.88, 0.85)
		mat.roughness = 0.85
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = RANGE
		add_child(mi)
	var cars: Array = p.get("cars", [])
	if cars.is_empty():
		return
	var names: Array = TrafficAgent.SKETCHFAB_CARS.keys()
	var cells: Dictionary = {}   # model -> {Vector2i: Array[Transform3D]}
	var body := StaticBody3D.new()
	body.collision_layer = 1
	for car in cars:
		var at := Vector2(float(car.get("x", 0.0)), float(car.get("z", 0.0)))
		if not _on_tile(at):
			continue
		var model: String = names[absi(hash(at)) % names.size()]
		var yaw := deg_to_rad(float(car.get("heading", 0.0))) + (PI if absi(hash(at * 3.0)) % 2 == 0 else 0.0)
		var ground := _rn._on_ground(at, _terrain, 0.0)
		var cell := Vector2i(floori(at.x / RoadNetwork.LAMP_CELL), floori(at.y / RoadNetwork.LAMP_CELL))
		cells.get_or_add(model, {}).get_or_add(cell, []).append(Transform3D(Basis(Vector3.UP, yaw), ground))
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.8, 1.4, float(TrafficAgent.SKETCHFAB_CARS[model]))
		shape.shape = box
		shape.transform = Transform3D(Basis(Vector3.UP, yaw), ground + Vector3(0, 0.7, 0))
		body.add_child(shape)
	for model in cells:
		var path := TrafficAgent.SKETCHFAB + str(model) + ".glb"
		if not ResourceLoader.exists(path):
			continue
		var mesh := MeshMerge.baked(path)
		var b := mesh.get_aabb()
		var k := float(TrafficAgent.SKETCHFAB_CARS[model]) / maxf(maxf(b.size.x, b.size.z), 0.001)
		var fit := Transform3D(Basis.from_scale(Vector3.ONE * k), Vector3(-(b.position.x + b.size.x * 0.5) * k, -b.position.y * k, -(b.position.z + b.size.z * 0.5) * k))
		if b.size.x > b.size.z:
			fit = Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3.ZERO) * fit   # its length along Z, the bay's
		for cell in cells[model]:
			var xforms: Array = cells[model][cell]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mesh
			mm.instance_count = xforms.size()
			for i in xforms.size():
				mm.set_instance_transform(i, xforms[i] * fit)
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "Parked_" + str(model)
			mmi.multimesh = mm
			mmi.visibility_range_end = RANGE
			add_child(mmi)
	add_child(body)


## A flat white strip `w` wide from `a` to `b` on the ground, a hair above the road ribbons.
func _line(st: SurfaceTool, a: Vector2, b: Vector2, w: float) -> void:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x) * w * 0.5
	var v: Array[Vector3] = []
	for q: Vector2 in [a - n, a + n, b + n, b - n]:
		v.append(_rn._on_ground(q, _terrain, _rn.lift + 0.02))
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_normal(Vector3.UP)
		st.add_vertex(v[i])


const CLEARANCE := {"bench": 1.0, "bin": 0.5, "bike_rack": 0.6, "bollard": 0.25, "block": 0.7}   # metres from a barrier's face


## The mapped barriers' segments by 16 m cell: [a, b, half thickness].
func _barrier_grid() -> Dictionary:
	var grid := {}
	for b in StreetData.of(Sites.pack_of(_rn)).get("barriers", []):
		var spec: Array = BARRIERS.get(str(b.get("kind", "fence")), BARRIERS.fence)
		var pts: Array = b.get("points", [])
		for i in range(1, pts.size()):
			var a := Vector2(float(pts[i - 1][0]), float(pts[i - 1][1]))
			var c := Vector2(float(pts[i][0]), float(pts[i][1]))
			var n := maxi(1, int(a.distance_to(c) / 8.0))
			var seen := {}
			for j in n + 1:
				var q := a.lerp(c, float(j) / n)
				var cell := Vector2i(floori(q.x / 16.0), floori(q.y / 16.0))
				if not seen.has(cell):
					seen[cell] = true
					grid.get_or_add(cell, []).append([a, c, float(spec[1]) * 0.5])
	return grid


## [position, facing]: `p` moved to `clearance` metres off the face of the nearest mapped barrier when it
## stands closer, and the way away from that barrier; `p` and Vector2.ZERO when none is that close.
func _clear_of(grid: Dictionary, p: Vector2, clearance: float) -> Array:
	var best_d := INF
	var best_q := p
	var best_half := 0.0
	var best_seg: Array = []
	var c := Vector2i(floori(p.x / 16.0), floori(p.y / 16.0))
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			for s in grid.get(c + Vector2i(dx, dy), []):
				var q := Geometry2D.get_closest_point_to_segment(p, s[0], s[1])
				var d := q.distance_to(p)
				if d < best_d:
					best_d = d
					best_q = q
					best_half = s[2]
					best_seg = s
	var need := clearance + best_half
	if best_seg.is_empty() or best_d >= need:
		return [p, Vector2.ZERO]
	var away := p - best_q
	if away.length() < 0.01:   # on the line itself: off it to one side
		var along: Vector2 = ((best_seg[1] as Vector2) - (best_seg[0] as Vector2)).normalized()
		away = Vector2(-along.y, along.x)
	away = away.normalized()
	return [best_q + away * need, away]


func _stand_in(kind: String) -> Mesh:
	match kind:
		"bench":
			var b := BoxMesh.new()
			b.size = Vector3(1.8, 0.45, 0.5)
			var m := b as Mesh
			return _raised(m, 0.225)
		"block":
			var b2 := BoxMesh.new()
			b2.size = Vector3(1.2, 0.6, 0.6)
			return _raised(b2, 0.3)
		"bike_rack":
			var b3 := BoxMesh.new()
			b3.size = Vector3(0.05, 0.8, 0.7)
			return _raised(b3, 0.4)
		_:
			var c := CylinderMesh.new()
			c.top_radius = 0.1 if kind == "bollard" else 0.3
			c.bottom_radius = c.top_radius
			c.height = 0.9
			c.radial_segments = 10
			c.rings = 1
			return _raised(c, 0.45)


## A primitive mesh moved up so its base sits at y 0 (the MultiMesh places bases on the ground).
static func _raised(m: Mesh, up: float) -> Mesh:
	var st := SurfaceTool.new()
	st.create_from(m, 0)
	var out := st.commit()
	var arrays := out.surface_get_arrays(0)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in v.size():
		v[i].y += up
	arrays[Mesh.ARRAY_VERTEX] = v
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return am


# ---------------------------------------------------------------- fences, hedges, walls

## One mapped barrier as a slab following the ground, cut to the tile. Returns the pieces drawn.
func _barrier(st: SurfaceTool, b: Dictionary) -> int:
	var kind := str(b.get("kind", "fence"))
	var spec: Array = BARRIERS.get(kind, BARRIERS.fence)
	var h: float = clampf(float(b.height), 0.3, 8.0) if b.get("height") != null else float(spec[0])
	var t: float = spec[1]
	var col: Color = spec[2]
	var material := str(b.get("material", "")) if b.get("material") != null else ""
	if material == "wood":
		col = WOOD
	elif material == "brick":
		col = BRICK
	var pts := _resampled(b.get("points", []), 3.0)
	var n := 0
	for i in range(1, pts.size()):
		var a: Vector2 = pts[i - 1]
		var c: Vector2 = pts[i]
		if not _on_tile((a + c) * 0.5) or a.distance_to(c) < 0.05:
			continue
		_slab(st, a, c, t, h, col)
		n += 1
	return n


## A box from `a` to `b`, `t` thick, from a little under the ground to `h` above it at each end.
func _slab(st: SurfaceTool, a: Vector2, b: Vector2, t: float, h: float, col: Color) -> void:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x) * t * 0.5
	var ga := _rn._on_ground(a, _terrain, 0.0).y
	var gb := _rn._on_ground(b, _terrain, 0.0).y
	var lo_a := ga - 0.25
	var lo_b := gb - 0.25
	var p := [Vector3(a.x + n.x, lo_a, a.y + n.y), Vector3(b.x + n.x, lo_b, b.y + n.y), Vector3(b.x + n.x, gb + h, b.y + n.y), Vector3(a.x + n.x, ga + h, a.y + n.y),
		Vector3(a.x - n.x, lo_a, a.y - n.y), Vector3(b.x - n.x, lo_b, b.y - n.y), Vector3(b.x - n.x, gb + h, b.y - n.y), Vector3(a.x - n.x, ga + h, a.y - n.y)]
	for f in [[0, 1, 2, 3], [5, 4, 7, 6], [3, 2, 6, 7], [4, 0, 3, 7], [1, 5, 6, 2]]:
		_quad(st, p[f[0]], p[f[1]], p[f[2]], p[f[3]], col)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	var nrm := (b - a).cross(d - a).normalized()
	for v in [a, b, c, a, c, d]:
		st.set_normal(nrm)
		st.set_color(col)
		st.add_vertex(v)


static func _resampled(points: Array, step: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in range(points.size() - 1):
		var a := Vector2(float(points[i][0]), float(points[i][1]))
		var b := Vector2(float(points[i + 1][0]), float(points[i + 1][1]))
		var k := maxi(1, int(a.distance_to(b) / step))
		for j in k:
			out.append(a.lerp(b, float(j) / k))
	if not points.is_empty():
		var last: Array = points[points.size() - 1]
		out.append(Vector2(float(last[0]), float(last[1])))
	return out


# ---------------------------------------------------------------- flowerbeds and piers

## A raised bed of soil inside a low stone kerb, flowers dotted over it.
func _flowerbed(st: SurfaceTool, ring: Array) -> int:
	var poly := PackedVector2Array()
	for q in ring:
		poly.append(Vector2(float(q[0]), float(q[1])))
	if poly.size() < 3:
		return 0
	var c := Vector2.ZERO
	for q in poly:
		c += q
	if not _on_tile(c / poly.size()):
		return 0
	var tris := Geometry2D.triangulate_polygon(poly)
	var soil := Color(0.24, 0.17, 0.11)
	for i in range(0, tris.size(), 3):
		var v: Array[Vector3] = []
		for k in 3:
			v.append(_rn._on_ground(poly[tris[i + k]], _terrain, 0.22))
		if (v[1] - v[0]).cross(v[2] - v[0]).y < 0.0:
			v.reverse()
		for w in v:
			st.set_normal(Vector3.UP)
			st.set_color(soil)
			st.add_vertex(w)
	var closed: Array = ring.duplicate()
	closed.append(ring[0])
	for i in range(1, closed.size()):
		_slab(st, Vector2(float(closed[i - 1][0]), float(closed[i - 1][1])), Vector2(float(closed[i][0]), float(closed[i][1])), 0.14, 0.3, Color(0.62, 0.6, 0.56))
	var box := Rect2(poly[0], Vector2.ZERO)
	for q in poly:
		box = box.expand(q)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(poly[0])
	var want := mini(int(box.get_area() * 1.5), 400)
	for i in want:
		var q := Vector2(rng.randf_range(box.position.x, box.end.x), rng.randf_range(box.position.y, box.end.y))
		if not Geometry2D.is_point_in_polygon(q, poly):
			continue
		var g := _rn._on_ground(q, _terrain, 0.22)
		var col: Color = FLOWERS[rng.randi() % FLOWERS.size()]
		var s := rng.randf_range(0.1, 0.18)
		var lo := g + Vector3(-s, 0.0, -s)
		var hi := g + Vector3(s, s * 1.6, s)
		_quad(st, Vector3(lo.x, hi.y, lo.z), Vector3(lo.x, hi.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, hi.y, lo.z), col)
		_quad(st, Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z), col)
		_quad(st, Vector3(hi.x, lo.y, lo.z), Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), col)
	return 1


## A wooden deck at the water's level (the lowest ground along it, plus a little), on posts: an area
## pier as its outline, a line pier as a walk `width` wide.
func _pier(st: SurfaceTool, p: Dictionary) -> int:
	var pts: Array[Vector2] = []
	for q in p.get("points", []):
		pts.append(Vector2(float(q[0]), float(q[1])))
	if pts.size() < 2:
		return 0
	var c := Vector2.ZERO
	for q in pts:
		c += q
	if not _on_tile(c / pts.size()):
		return 0
	var low := INF
	for q in _resampled(p.get("points", []), 2.0):
		low = minf(low, _rn._on_ground(q, _terrain, 0.0).y)
	var deck := low + 0.7
	var boards := Color(0.5, 0.38, 0.26)
	if p.get("area") == true and pts.size() >= 3:
		var poly := PackedVector2Array(pts)
		var tris := Geometry2D.triangulate_polygon(poly)
		for i in range(0, tris.size(), 3):
			var v: Array[Vector3] = []
			for k in 3:
				v.append(Vector3(poly[tris[i + k]].x, deck, poly[tris[i + k]].y))
			if (v[1] - v[0]).cross(v[2] - v[0]).y < 0.0:
				v.reverse()
			for w in v:
				st.set_normal(Vector3.UP)
				st.set_color(boards)
				st.add_vertex(w)
		pts.append(pts[0])
	else:
		var half: float = clampf(float(p.get("width", 2.5)), 1.0, 12.0) * 0.5
		for i in range(1, pts.size()):
			var a := pts[i - 1]
			var b := pts[i]
			var d := (b - a).normalized()
			var n := Vector2(-d.y, d.x) * half
			_quad(st, Vector3(a.x - n.x, deck, a.y - n.y), Vector3(a.x + n.x, deck, a.y + n.y), Vector3(b.x + n.x, deck, b.y + n.y), Vector3(b.x - n.x, deck, b.y - n.y), boards)
	# the posts, every 3 m along the edges, down into the water
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var k := maxi(1, int(a.distance_to(b) / 3.0))
		for j in k:
			var q := a.lerp(b, float(j) / k)
			var s := 0.12
			_quad(st, Vector3(q.x - s, deck - 2.5, q.y + s), Vector3(q.x + s, deck - 2.5, q.y + s), Vector3(q.x + s, deck, q.y + s), Vector3(q.x - s, deck, q.y + s), WOOD)
			_quad(st, Vector3(q.x + s, deck - 2.5, q.y - s), Vector3(q.x - s, deck - 2.5, q.y - s), Vector3(q.x - s, deck, q.y - s), Vector3(q.x + s, deck, q.y - s), WOOD)
	return 1


## The vertex-coloured mesh with a collider the player stands on and cannot walk through.
func _solid(st: SurfaceTool, name: String, range_end: float) -> void:
	var mesh := st.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED   # thin fences and deck undersides seen from either side
	mi.material_override = m
	mi.visibility_range_end = range_end
	add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var tri := mesh.create_trimesh_shape()
	tri.backface_collision = true   # Jolt collides with front faces only unless told otherwise
	shape.shape = tri
	body.add_child(shape)
	add_child(body)
