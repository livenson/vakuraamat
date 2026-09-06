# A real building: the Maa-amet LOD2 model (walls and roof faces) when the pack's buildings.json has
# one for this id, else the ETAK footprint polygon extruded to its measured height with a flat roof.
# Either way a foundation skirt goes below ground and a trimesh collider stops the player.
# Generated era scenes place one per building whose first year of use is not later than the era.
class_name FootprintBuilding
extends Node3D

@export var polygon: PackedVector2Array = PackedVector2Array()   # x east, y = z south, around the origin
@export var height := 5.0
@export var wall_color := Color(0.84, 0.76, 0.6)
@export var roof_color := Color(0.35, 0.3, 0.26)
@export var skirt := 3.0                                          # metres below the origin
@export var source := ""                                          # buildings.json inside the active pack
@export var building_id := 0
@export var kind := "dwelling"                                    # dwelling | outbuilding | other | ruin
@export var floors := 0                                           # register floors; 0 = from the height
@export var facade := ""                                          # register facade material text
@export var roof_cover := ""                                      # register roof covering text
@export var ehr := ""                                             # Building Register code
@export var address := ""                                         # ETAK near address, e.g. "Madruse tn 22"
@export var purpose := ""                                         # register use text
@export var year := 0                                             # first year of use, 0 = unknown
@export var tunnus := ""                                          # cadastral unit the register links it to

const TEX := "res://assets/textures/buildings/"
var _windows := SurfaceTool.new()
var _trim := SurfaceTool.new()
var _wall_faces: Array = []   # {pts: Array[Vector3], n: Vector3, t: Vector3, umin, umax, ymin, ymax}

static var _models: Dictionary = {}   # source path -> {id -> lod2 dict}
var _sign: Label3D
var _mesh_node: MeshInstance3D
var _body_node: StaticBody3D


var _walls := SurfaceTool.new()
var _roof := SurfaceTool.new()


func _ready() -> void:
	_walls.begin(Mesh.PRIMITIVE_TRIANGLES)
	_roof.begin(Mesh.PRIMITIVE_TRIANGLES)
	_windows.begin(Mesh.PRIMITIVE_TRIANGLES)
	_trim.begin(Mesh.PRIMITIVE_TRIANGLES)
	var model := _model()
	if model.is_empty():
		if polygon.size() < 3:
			return
		_extrude()
	else:
		_faces(model.faces)
	_skirt()
	if kind != "ruin":
		_openings()
	_walls.generate_normals()
	_roof.generate_normals()
	_windows.generate_normals()
	_trim.generate_normals()
	var mesh: ArrayMesh = _walls.commit()
	mesh = _roof.commit(mesh)
	mesh = _windows.commit(mesh)
	mesh = _trim.commit(mesh)
	# surfaces: 0 walls, 1 roof, 2 windows (named "Window": EraController lights them after dark), 3 trim
	var mats := [_wall_material(), _roof_material(), _window_material(), _trim_material()]
	for i in mesh.get_surface_count():
		mesh.surface_set_material(i, mats[i] if i < mats.size() else mats[0])
	var mi := MeshInstance3D.new()
	_mesh_node = mi
	mi.mesh = mesh
	add_child(mi)
	var body := StaticBody3D.new()
	_body_node = body
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	# walls and roof only: sills, casings and trim in the collider snagged a player walking along a wall
	var solid: ArrayMesh = _walls.commit()
	solid = _roof.commit(solid)
	shape.shape = solid.create_trimesh_shape()
	body.add_child(shape)
	add_child(body)


## The LOD2 model for this building from the pack's buildings.json (parsed once per pack).
func _model() -> Dictionary:
	if source == "" or building_id == 0:
		return {}
	var path := Sites.path_in(Sites.pack_of(self), source)
	if not _models.has(path):
		var table := {}
		var text := FileAccess.get_file_as_string(path)
		var parsed = JSON.parse_string(text) if text != "" else null
		var list: Array = parsed.get("buildings", []) if typeof(parsed) == TYPE_DICTIONARY else (parsed if typeof(parsed) == TYPE_ARRAY else [])
		for b in list:
			if b.get("lod2") != null:
				table[int(b.id)] = b.lod2
		_models[path] = table
	return _models[path].get(building_id, {})


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	for v in [a, b, c]:
		st.add_vertex(v)


## LOD2 faces: planar polygons in metres relative to the origin (x east, y up from the base, z south).
func _faces(faces: Array) -> void:
	var roof_faces: Array = []       # Array[Vector3] per roof face, for the gap pass
	var wall_tops: Array = []        # [Vector3 a, Vector3 b] the ground line of each wall face
	for face in faces:
		var pts: Array[Vector3] = []
		for p in face:
			pts.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
		if pts.size() < 3:
			continue
		var nrm := Vector3.ZERO
		for i in pts.size():
			nrm += pts[i].cross(pts[(i + 1) % pts.size()])   # Newell's method
		nrm = nrm.normalized()
		if nrm.y < -0.5:
			continue   # floor: never seen
		var st := _roof if nrm.y > 0.3 else _walls
		if st == _walls:
			_register_face(pts)
			# the wall's line on the ground: the two vertices farthest apart in xz (gables included)
			var pa := pts[0]
			var pb := pts[0]
			var best := -1.0
			for i in pts.size():
				for j in range(i + 1, pts.size()):
					var dd := Vector2(pts[i].x, pts[i].z).distance_squared_to(Vector2(pts[j].x, pts[j].z))
					if dd > best:
						best = dd
						pa = pts[i]
						pb = pts[j]
			var low := INF
			var high := -INF
			for q in pts:
				low = minf(low, q.y)
				high = maxf(high, q.y)
			wall_tops.append([pa, pb, low, high])
		else:
			roof_faces.append(pts)
		# triangulate in the plane: drop the dominant axis
		var proj: PackedVector2Array = PackedVector2Array()
		var ax := absf(nrm.x)
		var ay := absf(nrm.y)
		var az := absf(nrm.z)
		for p in pts:
			if ay >= ax and ay >= az:
				proj.append(Vector2(p.x, p.z))
			elif ax >= az:
				proj.append(Vector2(p.y, p.z))
			else:
				proj.append(Vector2(p.x, p.y))
		var idx := Geometry2D.triangulate_polygon(proj)
		if idx.is_empty():
			continue
		for i in range(0, idx.size(), 3):
			var a := pts[idx[i]]
			var b := pts[idx[i + 1]]
			var c := pts[idx[i + 2]]
			if (b - a).cross(c - a).dot(nrm) < 0.0:
				_tri(st, a, c, b)
			else:
				_tri(st, a, b, c)
	_close_gaps(roof_faces, wall_tops)


## Some Geo3D models are fragments: a whole roof with walls under one corner only (the rest reads as
## a slab in the air). Every outer roof edge that no wall face reaches gets a wall down to the ground.
func _close_gaps(roof_faces: Array, wall_tops: Array) -> void:
	var edges: Array = []   # [a, b, face index]
	for fi in roof_faces.size():
		var pts: Array = roof_faces[fi]
		for i in pts.size():
			edges.append([pts[i], pts[(i + 1) % pts.size()], fi])
	var added := 0
	for e in edges:
		var a: Vector3 = e[0]
		var b: Vector3 = e[1]
		if a.distance_to(b) < 1.5 or minf(a.y, b.y) < 2.5:
			continue
		var mid := (a + b) * 0.5
		var covered := false
		# wall faces standing along this edge (eaves overhang the wall by a metre or so), taken
		# together (models split walls into bands): they must reach well below it, a parapet alone
		# does not hold a roof up
		var lowest := INF
		for w in wall_tops:
			if _dist_xz(mid, w[0], w[1]) < 1.5:
				lowest = minf(lowest, float(w[2]))
				if float(w[2]) <= mid.y + 0.5 and float(w[3]) >= mid.y + 1.0:
					covered = true   # a taller part rises from this edge: an inner edge of a lower roof
		if lowest <= mid.y - 2.0:
			covered = true
		if not covered:
			# a lower roof lies under this edge (a skylight, a penthouse, a setback): nothing to close
			for fi in roof_faces.size():
				if fi == e[2]:
					continue
				var face2: Array = roof_faces[fi]
				var below := false
				var poly2 := PackedVector2Array()
				for q in face2:
					poly2.append(Vector2(q.x, q.z))
					if q.y < mid.y - 0.3:
						below = true
				if below and Geometry2D.is_point_in_polygon(Vector2(mid.x, mid.z) + Vector2(c_out(e, roof_faces)).limit_length(0.3), poly2):
					covered = true
					break
		if not covered:
			for o in edges:   # an inner edge: another roof face shares it
				if o[2] != e[2] and _dist_xz(mid, o[0], o[1]) < 0.4 and absf(((o[0] + o[1]) * 0.5).y - mid.y) < 1.5:
					covered = true
					break
		if covered:
			continue
		var ga := Vector3(a.x, 0.0, a.z)
		var gb := Vector3(b.x, 0.0, b.z)
		# outward: away from the roof face's centre
		var face: Array = roof_faces[e[2]]
		var c := Vector3.ZERO
		for q in face:
			c += q
		c /= face.size()
		var out := Vector3(-(b.z - a.z), 0.0, b.x - a.x)
		if out.dot(mid - c) < 0.0:
			var t := a
			a = b
			b = t
			ga = Vector3(a.x, 0.0, a.z)
			gb = Vector3(b.x, 0.0, b.z)
		_tri(_walls, ga, gb, b)
		_tri(_walls, ga, b, a)
		_register_face([ga, gb, b, a])
		added += 1
	if added > 0:
		print("[building] %s: %d roof edges without walls closed to the ground" % [address if address != "" else str(building_id), added])


## The xz direction from an edge's midpoint towards its face's centre.
static func c_out(e: Array, roof_faces: Array) -> Vector2:
	var face: Array = roof_faces[e[2]]
	var c := Vector3.ZERO
	for q in face:
		c += q
	c /= face.size()
	var mid: Vector3 = (e[0] + e[1]) * 0.5
	return Vector2(c.x - mid.x, c.z - mid.z)


static func _dist_xz(p: Vector3, a: Vector3, b: Vector3) -> float:
	var p2 := Vector2(p.x, p.z)
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	var ab := b2 - a2
	var t := clampf((p2 - a2).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p2.distance_to(a2 + ab * t)


## Fallback: the footprint extruded to `height` with a flat roof.
func _extrude() -> void:
	var n := polygon.size()
	for i in n:
		var a := polygon[i]
		var b := polygon[(i + 1) % n]
		_tri(_walls, Vector3(a.x, 0, a.y), Vector3(b.x, 0, b.y), Vector3(b.x, height, b.y))
		_tri(_walls, Vector3(a.x, 0, a.y), Vector3(b.x, height, b.y), Vector3(a.x, height, a.y))
		_register_face([Vector3(a.x, 0, a.y), Vector3(b.x, 0, b.y), Vector3(b.x, height, b.y), Vector3(a.x, height, a.y)])
	var tris := Geometry2D.triangulate_polygon(polygon)
	for i in range(0, tris.size(), 3):
		var p0 := polygon[tris[i]]
		var p1 := polygon[tris[i + 1]]
		var p2 := polygon[tris[i + 2]]
		_tri(_roof, Vector3(p0.x, height, p0.y), Vector3(p2.x, height, p2.y), Vector3(p1.x, height, p1.y))


## Walls from the base down into the ground, so a sloping site shows no gap under the model.
func _skirt() -> void:
	if polygon.size() < 3 or skirt <= 0.0:
		return
	var n := polygon.size()
	for i in n:
		var a := polygon[i]
		var b := polygon[(i + 1) % n]
		_tri(_walls, Vector3(a.x, -skirt, a.y), Vector3(b.x, -skirt, b.y), Vector3(b.x, 0.05, b.y))
		_tri(_walls, Vector3(a.x, -skirt, a.y), Vector3(b.x, 0.05, b.y), Vector3(a.x, 0.05, a.y))


# ---------------------------------------------------------------- register-driven details
@export var chimney := false   # heat source with a flue (stove, boiler on solid fuel or gas)
@export var solar := false     # solar electricity: panels on the roof
@export var well := false      # own dug well: a stone ring beside the house


func _enter_tree() -> void:
	# the plain mesh is built in _ready; these small props come after it so they sit on the model
	ready.connect(_details, CONNECT_ONE_SHOT)


func _details() -> void:
	var top := height
	var model := _model()
	if not model.is_empty():
		top = float(model.get("z_max", 0.0)) - float(model.get("z_min", 0.0))
	var c := Vector2.ZERO
	for p in polygon:
		c += p
	if polygon.size() > 0:
		c /= polygon.size()
	if chimney:
		var box := CSGBox3D.new()
		box.size = Vector3(0.6, 1.6, 0.6)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.5, 0.32, 0.26)
		box.material = m
		box.position = Vector3(c.x + 1.5, top + 0.3, c.y)
		if not model.is_empty():
			# on the LOD2 roof: at its highest vertex, nudged towards the centre, sunk half a metre in
			var ridge := Vector3(c.x, -INF, c.y)
			for face in model.faces:
				for v in face:
					if float(v[1]) > ridge.y:
						ridge = Vector3(float(v[0]), float(v[1]), float(v[2]))
			var toward := (Vector3(c.x, ridge.y, c.y) - ridge)
			toward.y = 0.0
			ridge += toward.limit_length(0.6)
			box.position = Vector3(ridge.x, ridge.y + 0.3, ridge.z)
			call_deferred("_settle_chimney", box)   # the highest vertex may be a spike or a dormer: drop to the roof there
		add_child(box)
	if solar:
		var panel := CSGBox3D.new()
		panel.size = Vector3(minf(6.0, maxf(2.0, _extent().x * 0.4)), 0.08, minf(3.0, maxf(1.0, _extent().y * 0.3)))
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Color(0.08, 0.1, 0.2)
		pm.metallic = 0.6
		pm.roughness = 0.2
		panel.material = pm
		panel.position = Vector3(c.x - 1.0, top + 0.2, c.y)
		add_child(panel)
	if well:
		var ring := CSGTorus3D.new()
		ring.inner_radius = 0.6
		ring.outer_radius = 0.95
		ring.sides = 12
		ring.ring_sides = 6
		var rm := StandardMaterial3D.new()
		rm.albedo_color = Color(0.55, 0.53, 0.5)
		ring.material = rm
		var ext := _extent()
		ring.position = Vector3(c.x + ext.x / 2 + 4.0, 0.3, c.y + ext.y / 2 + 2.0)
		add_child(ring)


func _extent() -> Vector2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in polygon:
		lo = lo.min(p)
		hi = hi.max(p)
	return hi - lo if polygon.size() > 0 else Vector2(6, 6)


# ---------------------------------------------------------------- appearance from the register
func _tex(name: String) -> Texture2D:
	return load(TEX + name + "_color.jpg")


func _nrm(name: String) -> Texture2D:
	return load(TEX + name + "_normal.jpg")


func _textured(name: String, tint: Color, scale: float, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex(name)
	m.normal_enabled = true
	m.normal_texture = _nrm(name)
	m.albedo_color = tint
	m.roughness = rough
	m.uv1_triplanar = true
	m.uv1_world_triplanar = false
	m.uv1_scale = Vector3(scale, scale, scale)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Facade material text -> texture (Poly Haven CC0 sets, see tools/pipeline/fetch_polyhaven.py):
## [register substrings, texture, lighten, uv scale, roughness]; rendered walls get plaster.
const WALL_RULES := [
	[["palk"], "logs", 0.2, 0.5, 0.9],
	[["puit", "laudis"], "woodsiding", 0.25, 0.5, 0.9],
	[["tellis"], "brick", 0.3, 0.6, 0.85],
	[["paneel", "raudbetoon"], "panel", 0.2, 0.45, 0.9],
	[["betoon"], "concrete", 0.15, 0.5, 0.9],
	[["kivi"], "rock", 0.2, 0.4, 0.9],
]


func _wall_material() -> StandardMaterial3D:
	var f := facade.to_lower()
	if f == "" and kind == "outbuilding":
		return _textured("woodsiding", wall_color.lightened(0.15), 0.5)
	for r in WALL_RULES:
		for key in r[0]:
			if key in f:
				return _textured(r[1], wall_color.lightened(r[2]), r[3], r[4])
	return _textured("plaster", wall_color.lightened(0.05), 0.6)


func _roof_material() -> StandardMaterial3D:
	var r := roof_cover.to_lower()
	if "kivi" in r:
		return _textured("rooftiles", roof_color.lightened(0.35), 0.7, 0.8)
	if "roo" in r or "õlg" in r:
		return _textured("thatch", roof_color.lightened(0.4), 0.6)
	if "plekk" in r or "profiil" in r:
		return _textured("metalroof", roof_color.lightened(0.3), 0.6, 0.5)
	var m := StandardMaterial3D.new()
	m.albedo_color = roof_color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if "plekk" in r:
		m.metallic = 0.5
		m.roughness = 0.45
	else:
		m.roughness = 0.95
	return m


func _window_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = "Window"
	m.albedo_color = Color(0.1, 0.13, 0.17)
	m.metallic = 0.3
	m.roughness = 0.12
	return m


func _trim_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.93, 0.92, 0.88) if kind == "dwelling" else Color(0.3, 0.22, 0.16)
	m.roughness = 0.8
	return m


# ---------------------------------------------------------------- windows and doors
func _register_face(pts: Array) -> void:
	"""Remember a vertical wall face for the openings pass."""
	var nrm := Vector3.ZERO
	for i in pts.size():
		nrm += (pts[i] as Vector3).cross(pts[(i + 1) % pts.size()])
	nrm = nrm.normalized()
	if absf(nrm.y) > 0.3 or nrm.length() < 0.5:
		return
	var t := nrm.cross(Vector3.UP).normalized()
	var umin := INF
	var umax := -INF
	var ymin := INF
	var ymax := -INF
	for p in pts:
		var u: float = (p as Vector3).dot(t)
		umin = minf(umin, u)
		umax = maxf(umax, u)
		ymin = minf(ymin, p.y)
		ymax = maxf(ymax, p.y)
	_wall_faces.append({"pts": pts, "n": nrm, "t": t, "umin": umin, "umax": umax, "ymin": ymin, "ymax": ymax})


## Whether a w x h opening centred at (u, y) lies within the face polygon (gable ends are pentagons).
func _fits_face(f: Dictionary, u: float, y: float, w: float, h: float) -> bool:
	var outline := PackedVector2Array()
	for p in f.pts:
		outline.append(Vector2((p as Vector3).dot(f.t), (p as Vector3).y))
	if outline.size() < 3:
		return true
	for corner in [Vector2(u - w / 2.0, y - h / 2.0), Vector2(u + w / 2.0, y - h / 2.0), Vector2(u + w / 2.0, y + h / 2.0), Vector2(u - w / 2.0, y + h / 2.0)]:
		if not Geometry2D.is_point_in_polygon(corner, outline):
			return false
	return true


func _quad_on_face(st: SurfaceTool, f: Dictionary, u: float, y: float, w: float, h: float, out: float) -> void:
	var a: Vector3 = f.pts[0]
	var base: Vector3 = a + f.t * (u - a.dot(f.t)) + Vector3.UP * (y - a.y) + f.n * out
	var du: Vector3 = f.t * (w / 2.0)
	var dy: Vector3 = Vector3.UP * (h / 2.0)
	var p0 := base - du - dy
	var p1 := base + du - dy
	var p2 := base + du + dy
	var p3 := base - du + dy
	_tri(st, p0, p1, p2)
	_tri(st, p0, p2, p3)
	_tri(st, p0, p2, p1)   # both sides, so the normal sign of the face does not matter
	_tri(st, p0, p3, p2)


## Windows in rows per floor and a door on the longest wall; sizes and spacing by building kind.
func _openings() -> void:
	if _wall_faces.is_empty():
		return
	var eave := _eave()
	if eave < 2.2:
		return
	var n_floors := floors if floors > 0 else maxi(1, int(round(eave / 3.0)))
	n_floors = mini(n_floors, int(eave / 2.4))
	var fh := eave / maxf(n_floors, 1)
	var win_w := 1.1 if kind == "dwelling" else 0.8
	var win_h := minf(1.35, fh * 0.45) if kind == "dwelling" else 0.6
	var spacing := 2.8 if kind == "dwelling" else 5.0
	var longest: Dictionary = {}
	for f in _wall_faces:
		if longest.is_empty() or (float(f.umax) - float(f.umin)) > (float(longest.umax) - float(longest.umin)):
			longest = f
	for f in _wall_faces:
		var width: float = float(f.umax) - float(f.umin)
		if width < 2.4:
			continue
		var cols := int((width - 1.6) / spacing)
		if cols < 1:
			cols = 1
		var step := width / (cols + 1)
		var base: float = maxf(float(f.ymin), _ground_on(f))
		for k in n_floors:
			var y: float = base + k * fh + (0.9 if kind == "dwelling" else 1.3) + win_h / 2.0
			if y + win_h / 2.0 > float(f.ymax) - 0.2:
				continue
			for c in cols:
				var u: float = float(f.umin) + step * (c + 1)
				if f == longest and k == 0 and c == cols / 2:
					continue   # the door goes here
				if not _fits_face(f, u, y, win_w + 0.3, win_h + 0.3):
					continue   # under the slope of a gable: the face is a pentagon there
				_quad_on_face(_trim, f, u, y, win_w + 0.16, win_h + 0.16, 0.02)
				_quad_on_face(_windows, f, u, y, win_w, win_h, 0.04)
	if not longest.is_empty():
		var door_w := 1.0 if kind == "dwelling" else 2.4
		var door_h := 2.1 if kind == "dwelling" else 2.4
		var lw: float = float(longest.umax) - float(longest.umin)
		var cols := maxi(1, int((lw - 1.6) / spacing))
		var u: float = float(longest.umin) + lw / (cols + 1) * (cols / 2 + 1)
		var y0: float = maxf(float(longest.ymin), _ground_on(longest)) + door_h / 2.0
		_quad_on_face(_trim, longest, u, y0, door_w + 0.16, door_h + 0.1, 0.02)
		var door := _windows if kind != "dwelling" else _trim
		_quad_on_face(door, longest, u, y0, door_w, door_h, 0.05)


## A name plate above the building: the tenants of its cadastral unit (empty text removes it).
func set_sign(text: String) -> void:
	if text == "":
		if _sign:
			_sign.queue_free()
			_sign = null
		return
	if _sign == null:
		_sign = Label3D.new()
		_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_sign.font_size = 40
		_sign.pixel_size = 0.012
		_sign.outline_size = 10
		_sign.modulate = Color(0.98, 0.9, 0.7)
		_sign.visibility_range_end = 140.0
		_sign.no_depth_test = false
		add_child(_sign)
	_sign.text = text
	_sign.position = Vector3(0, height + 1.2, 0)


## The door the exterior draws: local position at the threshold, outward normal, wall tangent, size, and
## the wall's base and eave heights. Empty when the building has no usable wall face.
func door_frame() -> Dictionary:
	var longest: Dictionary = {}
	for f in _wall_faces:
		if longest.is_empty() or (float(f.umax) - float(f.umin)) > (float(longest.umax) - float(longest.umin)):
			longest = f
	if longest.is_empty() or float(longest.ymax) < 2.2:
		return {}
	var spacing := 2.8 if kind == "dwelling" else 5.0
	var lw: float = float(longest.umax) - float(longest.umin)
	var cols := maxi(1, int((lw - 1.6) / spacing))
	var u: float = float(longest.umin) + lw / (cols + 1) * (cols / 2 + 1)
	var a: Vector3 = longest.pts[0]
	var pos: Vector3 = a + longest.t * (u - a.dot(longest.t)) + Vector3.UP * (float(longest.ymin) - a.y)
	return {"pos": pos, "n": longest.n, "t": longest.t, "width": 1.0 if kind == "dwelling" else 2.4, "height": 2.1 if kind == "dwelling" else 2.4,
		"ymin": float(longest.ymin), "eave": float(longest.ymax)}


## The ground along a wall face, relative to the building's origin (the model stands on its lowest
## corner, so on a slope the uphill walls start below grade): the highest terrain sample under it.
func _ground_on(f: Dictionary) -> float:
	var world: Node = GameState.world
	if world == null or not ("terrain" in world) or world.terrain == null or world.terrain.data == null:
		return 0.0
	# relative to the lowest corner of the footprint, where the model stands (the node may not be
	# snapped to the ground yet, so its own y is no reference)
	var origin := INF
	for p in polygon:
		var hp: float = world.terrain.data.get_height(to_global(Vector3(p.x, 0.0, p.y)))
		if not is_nan(hp):
			origin = minf(origin, hp)
	if origin == INF:
		return 0.0
	var g := 0.0
	var pts: Array = f.get("pts", [])
	var samples: Array = pts.duplicate()
	if pts.size() >= 2:
		samples.append((Vector3(pts[0]) + Vector3(pts[pts.size() / 2])) * 0.5)
	for p in samples:
		var h: float = world.terrain.data.get_height(to_global(Vector3(p.x, 0.0, p.z)))
		if not is_nan(h):
			g = maxf(g, minf(h - origin, 2.0))
	return g


## The eave: the top of the longest wall face (a porch or a low wing must not pull it down), else
## the register height.
func _eave() -> float:
	var best := -1.0
	var eave := height
	for f in _wall_faces:
		var w: float = float(f.umax) - float(f.umin)
		if w > best:
			best = w
			eave = float(f.ymax)
	return eave


## Eave height and floor count the openings use (the interior follows the same rhythm).
func storeys() -> Dictionary:
	var eave := _eave()
	var n_floors := floors if floors > 0 else maxi(1, int(round(eave / 3.0)))
	n_floors = clampi(n_floors, 1, maxi(1, int(eave / 2.4)))
	return {"eave": eave, "floors": n_floors, "floor_height": eave / maxf(n_floors, 1)}


## Hide the exterior while the player is inside (its collider too), and back.
func set_exterior_visible(on: bool) -> void:
	if _mesh_node:
		_mesh_node.visible = on
	if _body_node:
		_body_node.collision_layer = 1 if on else 0
	for c in get_children():
		if c is CSGShape3D:
			c.visible = on


## A chimney placed at the model's highest vertex may hang in the air where the roof is lower:
## cast down at its spot against this building's collider and sink it half a metre into the roof.
func _settle_chimney(box: CSGBox3D) -> void:
	if not is_inside_tree() or _body_node == null or not is_instance_valid(box):
		return
	var space := get_world_3d().direct_space_state
	var from := to_global(box.position + Vector3(0, 30.0, 0))
	var to := to_global(box.position - Vector3(0, 30.0, 0))
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	q.collide_with_bodies = true
	var hit := space.intersect_ray(q)
	if hit.is_empty() or hit.collider != _body_node:
		return
	var local := to_local(hit.position)
	box.position.y = local.y + box.size.y * 0.5 - 0.5

