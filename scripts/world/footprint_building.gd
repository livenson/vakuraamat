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

static var _models: Dictionary = {}   # source path -> {id -> lod2 dict}


var _walls := SurfaceTool.new()
var _roof := SurfaceTool.new()


func _ready() -> void:
	_walls.begin(Mesh.PRIMITIVE_TRIANGLES)
	_roof.begin(Mesh.PRIMITIVE_TRIANGLES)
	var model := _model()
	if model.is_empty():
		if polygon.size() < 3:
			return
		_extrude()
	else:
		_faces(model.faces)
	_skirt()
	_walls.generate_normals()
	_roof.generate_normals()
	var mesh: ArrayMesh = _walls.commit()
	mesh = _roof.commit(mesh)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	for i in mesh.get_surface_count():
		var mat := StandardMaterial3D.new()
		mat.albedo_color = wall_color if i == 0 else roof_color
		mat.roughness = 0.9
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.set_surface_override_material(i, mat)
	add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	add_child(body)


## The LOD2 model for this building from the pack's buildings.json (parsed once per pack).
func _model() -> Dictionary:
	if source == "" or building_id == 0:
		return {}
	var path := Sites.path(source)
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


## Fallback: the footprint extruded to `height` with a flat roof.
func _extrude() -> void:
	var n := polygon.size()
	for i in n:
		var a := polygon[i]
		var b := polygon[(i + 1) % n]
		_tri(_walls, Vector3(a.x, 0, a.y), Vector3(b.x, 0, b.y), Vector3(b.x, height, b.y))
		_tri(_walls, Vector3(a.x, 0, a.y), Vector3(b.x, height, b.y), Vector3(a.x, height, a.y))
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
