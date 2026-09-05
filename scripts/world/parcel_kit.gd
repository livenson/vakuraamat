# Props for one cadastral unit, chosen by assets/data/parcel_rules.json from the unit's registered
# purpose: a playground (swing frame, slide, sandpit, bench), park benches, a garden hedge along the
# boundary, or an industrial fence. Cheap geometry, all in one mesh, on the terrain via the group snap.
class_name ParcelKit
extends Node3D

@export var kit := ""                         # playground | park | hedge | fence | solar | court
@export var tunnus := ""                      # cadastral number, for the codes overlay
@export var polygon: PackedVector2Array = PackedVector2Array()   # boundary around the origin (x east, y = z south)
@export var row_period := 6.0                 # solar: metres between rows (from the orthophoto)
@export var row_angle := 0.0                  # solar: direction the rows run, degrees from east towards south
@export var anchor := Vector2.INF             # court: a pinned spot from the pack's parcel_rules.json (metres from the origin)
@export var anchor_yaw := 0.0                 # court: its heading in degrees from north

var _st := SurfaceTool.new()
var _colors: Array[Color] = []


func _ready() -> void:
	if polygon.size() < 3:
		return
	if kit in ["hedge", "fence", "solar", "playground", "court"]:
		# these place every piece on the ground themselves: neither the kit nor its parcel group may be snapped
		set_meta("no_snap", true)
		if get_parent():
			get_parent().set_meta("no_snap", true)
	match kit:
		"playground":
			_playground()
		"court":
			_court()
		"park":
			_park()
		"hedge":
			_boundary(0.9, 0.7, Color(0.22, 0.4, 0.18), 1.2, true)
		"fence":
			_boundary(2.0, 0.08, Color(0.45, 0.45, 0.42), 0.4, false)
		"solar":
			_solar()
			_boundary(1.8, 0.06, Color(0.5, 0.5, 0.48), 0.5, false)
	if _colors.is_empty():
		return
	var mi := MeshInstance3D.new()
	var mesh: ArrayMesh = _st.commit()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.85
	mi.material_override = mat
	add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	add_child(body)


func _box(center: Vector3, size: Vector3, col: Color, yaw := 0.0, tilt := 0.0) -> void:
	if _colors.is_empty():
		_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_colors.append(col)
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt)
	var h := size / 2.0
	var c := [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
			Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
	var faces := [[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0]]
	for f in faces:
		var p := [center + b * c[f[0]], center + b * c[f[1]], center + b * c[f[2]], center + b * c[f[3]]]
		var n: Vector3 = (p[1] - p[0]).cross(p[3] - p[0]).normalized()
		for v in [p[0], p[1], p[2], p[0], p[2], p[3]]:
			_st.set_normal(n)
			_st.set_color(col)
			_st.add_vertex(v)


func _centroid() -> Vector2:
	var c := Vector2.ZERO
	for p in polygon:
		c += p
	return c / polygon.size()


const MODELS := "res://assets/vendor/polypizza/"

## A playground from the Poly Pizza models (see THIRD_PARTY.md): a swing set, a slide and a seesaw
## around the centre, a sandpit, a bench; bigger grounds add a jungle gym, monkey bars, a trampoline
## and a play structure. The pieces stand on the ground wherever the terrain puts it.
func _playground() -> void:
	var c := _centroid()
	var area := absf(_area())
	var wood := Color(0.55, 0.38, 0.2)
	var sand := Color(0.85, 0.78, 0.6)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(tunnus)
	var spin := rng.randf_range(0.0, TAU)
	var pieces: Array = [["swing", 3.6, 0.0], ["slide", 3.2, 2.2], ["seesaw", 3.0, 4.2]]
	if area > 1200.0:
		pieces.append(["junglegym", 3.2, 1.1])
		pieces.append(["monkeybars", 2.6, 3.3])
	if area > 2200.0:
		pieces.append(["trampoline", 3.2, 5.3])
		pieces.append(["playstructure", 6.5, 0.6])
	var ring := 4.5 if area < 1200.0 else 6.5
	for i in pieces.size():
		var piece: Array = pieces[i]
		var ang: float = spin + piece[2]
		var at := c + Vector2(cos(ang), sin(ang)) * (ring if i < 3 else ring + 5.0)
		if not Geometry2D.is_point_in_polygon(at, polygon):
			at = c + (at - c) * 0.4
		if not _model(str(piece[0]), at, float(piece[1]), atan2(-sin(ang), -cos(ang)) + PI / 2.0):
			_box(Vector3(at.x, 1.0, at.y), Vector3(float(piece[1]), 2.0, 0.6), wood)   # stand-in without the model
	# sandpit
	var px := c.x - 5.0
	var pz := c.y - 1.5
	_box(Vector3(px, 0.15, pz), Vector3(3.0, 0.3, 3.0), sand)
	for side in [[Vector3(0, 0.2, -1.55), Vector3(3.2, 0.4, 0.12)], [Vector3(0, 0.2, 1.55), Vector3(3.2, 0.4, 0.12)], [Vector3(-1.55, 0.2, 0), Vector3(0.12, 0.4, 3.2)], [Vector3(1.55, 0.2, 0), Vector3(0.12, 0.4, 3.2)]]:
		_box(Vector3(px, 0, pz) + side[0], side[1], wood)
	_bench(Vector3(c.x, 0, c.y + ring + 2.0), 0.0)


## A tennis court (24 x 11 m) fitted along the parcel's longest side; a basketball half court beside
## it when the parcel is big enough.
func _court() -> void:
	var c := _centroid()
	var best := 0.0
	var dir := Vector2.RIGHT
	for i in polygon.size():
		var d: Vector2 = polygon[(i + 1) % polygon.size()] - polygon[i]
		if d.length() > best:
			best = d.length()
			dir = d.normalized()
	var yaw := atan2(dir.x, dir.y)   # the model's long axis (local Z) along the parcel's long side
	var at := _deepest(c, dir)
	if anchor != Vector2.INF:
		at = anchor
		yaw = deg_to_rad(anchor_yaw)
		dir = Vector2(sin(yaw), cos(yaw))
	var across := Vector2(-dir.y, dir.x)
	var area := absf(_area())
	if area > 2500.0 and Geometry2D.is_point_in_polygon(at + across * 14.0, polygon) and Geometry2D.is_point_in_polygon(at - across * 14.0, polygon):
		_model("tenniscourt", at - across * 7.0, 24.0, yaw)   # two courts side by side
		_model("tenniscourt", at + across * 7.0, 24.0, yaw)
	else:
		_model("tenniscourt", at, 24.0, yaw)
	if area > 4000.0:
		var bt := at + dir * 22.0
		if Geometry2D.is_point_in_polygon(bt, polygon):
			_model("basketball", bt, 15.0, yaw)


## The point on the line through `c` along `dir` that lies deepest inside the parcel (farthest
## from every boundary edge): where a court or a field sits, away from the street.
func _deepest(c: Vector2, dir: Vector2) -> Vector2:
	var best := c
	var best_d := -1.0
	for i in range(-20, 21):
		var q := c + dir * (i * 1.0)
		if not Geometry2D.is_point_in_polygon(q, polygon):
			continue
		var d := INF
		for k in polygon.size():
			d = minf(d, _dist_to_segment(q, polygon[k], polygon[(k + 1) % polygon.size()]))
		if d > best_d:
			best_d = d
			best = q
	return best


static func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## A vendored model on the ground at `at`, scaled so its longest side is `length` metres, turned by
## `yaw` about its centre. False when the model is not vendored.
func _model(name: String, at: Vector2, length: float, yaw: float) -> bool:
	var path := MODELS + name + ".glb"
	if not ResourceLoader.exists(path):
		return false
	var model: Node3D = (load(path) as PackedScene).instantiate()
	var b: AABB = Interiors._bounds(model)
	var longest := maxf(b.size.x, b.size.z)
	if longest < 0.0001:
		return false
	var k := length / longest
	var holder := Node3D.new()
	model.scale = Vector3.ONE * k
	model.position = Vector3(-(b.position.x + b.size.x * 0.5) * k, -b.position.y * k, -(b.position.z + b.size.z * 0.5) * k)
	if b.size.x > b.size.z:
		var turn := Node3D.new()   # the long axis along local Z, whatever the export did
		turn.rotation.y = PI / 2.0
		turn.add_child(model)
		holder.add_child(turn)
	else:
		holder.add_child(model)
	holder.position = Vector3(at.x, _ground(at), at.y)
	holder.rotation.y = yaw
	add_child(holder)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(b.size.x * k, maxf(b.size.y * k, 0.3), b.size.z * k)
	shape.shape = box
	shape.position = Vector3(0, box.size.y * 0.5, 0)
	body.add_child(shape)
	holder.add_child(body)
	return true


func _area() -> float:
	var a := 0.0
	for i in polygon.size():
		var p := polygon[i]
		var q := polygon[(i + 1) % polygon.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


func _bench(at: Vector3, yaw: float) -> void:
	var wood := Color(0.5, 0.35, 0.2)
	var b := Basis(Vector3.UP, yaw)
	_box(at + Vector3(0, 0.45, 0), Vector3(1.8, 0.06, 0.4), wood, yaw)
	_box(at + Vector3(0, 0.8, 0) + b * Vector3(0, 0, -0.2), Vector3(1.8, 0.4, 0.05), wood, yaw)
	for dx in [-0.75, 0.75]:
		_box(at + b * Vector3(dx, 0.22, 0), Vector3(0.08, 0.45, 0.4), Color(0.25, 0.25, 0.25), yaw)


func _park() -> void:
	var c := _centroid()
	var ext := Vector2.ZERO
	for p in polygon:
		ext = ext.max((p - c).abs())
	var r := minf(ext.x, ext.y) * 0.5
	if r < 3.0:
		return
	for i in 4:
		var a := i * TAU / 4.0
		_bench(Vector3(c.x + cos(a) * r, 0, c.y + sin(a) * r), -a)


## Hedge or fence along the boundary, inset a little; gaps where the boundary is long enough for a gate.
func _boundary(h: float, thickness: float, col: Color, seg: float, gaps: bool) -> void:
	var n := polygon.size()
	var c := _centroid()
	for i in n:
		var a := polygon[i]
		var b := polygon[(i + 1) % n]
		var dir := b - a
		var length := dir.length()
		if length < 1.0:
			continue
		dir /= length
		var inward := (c - (a + b) / 2.0).normalized() * 0.6
		var count := int(length / seg)
		for k in count:
			if gaps and k % 9 == 4:
				continue   # a gate
			var t := (k + 0.5) * seg
			var p := a + dir * t + inward
			_box(Vector3(p.x, _ground(p) + h / 2.0 - 0.15, p.y), Vector3(seg * 0.95, h, thickness + 0.0), col, -atan2(dir.y, dir.x))


## Solar park: tables of panels along the rows the orthophoto shows, tilted 35 degrees towards the
## south (rows run east-west in Estonia), on posts, every row_period metres, inside the boundary.
func _solar() -> void:
	var dir := Vector2(cos(deg_to_rad(row_angle)), sin(deg_to_rad(row_angle)))
	if dir.y < 0.0:
		dir = -dir   # keep one consistent handedness so the "south" side is the same for every row
	var nrm := Vector2(-dir.y, dir.x)   # points towards +z (south) for east-west rows
	var lo_n := INF
	var hi_n := -INF
	var lo_d := INF
	var hi_d := -INF
	for p in polygon:
		lo_n = minf(lo_n, p.dot(nrm))
		hi_n = maxf(hi_n, p.dot(nrm))
		lo_d = minf(lo_d, p.dot(dir))
		hi_d = maxf(hi_d, p.dot(dir))
	var period := maxf(row_period, 3.0)
	var table := 3.0
	var panel := Color(0.09, 0.11, 0.2)
	var frame := Color(0.6, 0.6, 0.62)
	var yaw := -atan2(dir.y, dir.x)
	var placed := 0
	var o := lo_n + period * 0.5
	while o < hi_n and placed < 3000:
		var t := lo_d + table * 0.5
		while t < hi_d:
			var p := nrm * o + dir * t
			var a := p - dir * (table * 0.5 + 1.0)
			var b := p + dir * (table * 0.5 + 1.0)
			if Geometry2D.is_point_in_polygon(p, polygon) and Geometry2D.is_point_in_polygon(a, polygon) and Geometry2D.is_point_in_polygon(b, polygon):
				var g := _ground(p)
				_box(Vector3(p.x, g + 1.25, p.y), Vector3(table * 0.96, 0.05, 2.0), panel, yaw, deg_to_rad(35.0))
				_box(Vector3(p.x, g + 0.55, p.y), Vector3(0.08, 1.1, 0.08), frame)
				placed += 1
			t += table
		o += period


## Terrain height under a kit-local point, in kit space (the kit itself stays at y 0).
func _ground(p: Vector2) -> float:
	var terrain: Terrain3D = GameState.world.terrain if GameState.world else null
	if terrain == null or terrain.data == null:
		return 0.0
	var gp := to_global(Vector3(p.x, 0.0, p.y))
	var h := terrain.data.get_height(gp)
	return 0.0 if is_nan(h) else h - global_position.y
