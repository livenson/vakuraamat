# One still-water patch from a pack's water file ({x, z, w, d, level, area}): a rippling water
# surface (lake.gdshader), a basin carved into the terrain under it so the water has depth (the
# laser DTM records the surface as flat), and a school of fish circling below the surface.
# Placed by World.place_water for the active pack and for streamed tiles (under their offset root).
class_name Pond
extends Node3D

const FISH_RANGE := 70.0            # metres from the player within which the fish are animated
const MAX_DEPTH := 3.2

var level := 0.0                    # water surface, metres
var size := Vector2(10, 10)         # w, d in metres
var area := 100.0
var _fish: MultiMeshInstance3D
var _fish_state: Array = []         # {c: Vector2, r: Vector2, w: float, phase: float, depth: float, len: float}
var _t := 0.0


func setup(p: Dictionary, material: Material) -> void:
	size = Vector2(float(p.w), float(p.d))
	level = float(p.level)
	area = float(p.get("area", size.x * size.y))
	position = Vector3(float(p.x), level + 0.05, float(p.z))
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size + Vector2(4.0, 4.0)
	pm.subdivide_width = clampi(int(pm.size.x / 2.0), 2, 96)
	pm.subdivide_depth = clampi(int(pm.size.y / 2.0), 2, 96)
	mi.mesh = pm
	mi.material_override = material
	mi.name = "Surface"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_make_fish()


## Depth: from the edges the bed falls over a 3 m margin to a flat bottom, deeper for larger water.
func depth_at(local: Vector2) -> float:
	var max_depth := clampf(sqrt(area) / 18.0, 0.7, MAX_DEPTH)
	var half := size * 0.5
	var inside := half - local.abs()          # distance to the nearest edge along each axis
	var edge := minf(inside.x, inside.y)
	if edge <= 0.0:
		return 0.0
	var t := clampf(edge / 3.0, 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)
	return max_depth * t


## Lower the terrain under the water to the basin profile; only ever lowers, so it is idempotent.
func carve(terrain: Terrain3D) -> void:
	if terrain == null or terrain.data == null:
		return
	var half := size * 0.5
	var origin := global_position
	var changed := 0
	for z in range(int(-half.y), int(half.y) + 1):
		for x in range(int(-half.x), int(half.x) + 1):
			var d := depth_at(Vector2(x, z))
			if d <= 0.0:
				continue
			var gp := Vector3(origin.x + x, 0.0, origin.z + z)
			var h := terrain.data.get_height(gp)
			var target := level - d
			# only ground the laser saw as flat water gets a bed; land inside the patch's bounding box stays
			if not is_nan(h) and h > target and absf(h - level) < 0.35:
				terrain.data.set_height(gp, target)
				changed += 1
	if changed > 0:
		terrain.data.update_maps()


func _make_fish() -> void:
	var n := clampi(int(area / 150.0), 4, 30)
	var mesh := _fish_mesh()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = n
	_fish = MultiMeshInstance3D.new()
	_fish.multimesh = mm
	_fish.name = "Fish"
	_fish.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_fish)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2(position.x, position.z))
	var half := size * 0.5 - Vector2(4.0, 4.0)
	for i in n:
		var c := Vector2(rng.randf_range(-half.x, half.x), rng.randf_range(-half.y, half.y)) * 0.7
		var r := Vector2(rng.randf_range(2.0, maxf(3.0, half.x * 0.5)), rng.randf_range(1.5, maxf(2.5, half.y * 0.5)))
		_fish_state.append({"c": c, "r": r, "w": rng.randf_range(0.15, 0.4) * (1.0 if rng.randf() < 0.5 else -1.0),
				"phase": rng.randf() * TAU, "depth": rng.randf_range(0.25, 0.8), "len": rng.randf_range(0.3, 0.6)})
	_t = rng.randf() * 100.0
	_update_fish()


## A low-poly fish (body of two joined cones, a tail fin), 1 m long along -Z, scaled per instance.
static func _fish_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring := []
	var segs := 6
	for i in segs:
		var a := TAU * i / segs
		ring.append(Vector3(cos(a) * 0.09, sin(a) * 0.14, 0.0))
	var nose := Vector3(0, 0, -0.5)
	var mid := Vector3(0, 0, -0.15)
	var tail := Vector3(0, 0, 0.3)
	for i in segs:
		var a: Vector3 = ring[i] + mid
		var b: Vector3 = ring[(i + 1) % segs] + mid
		st.set_normal((a + b).normalized())
		st.add_vertex(nose)
		st.add_vertex(b)
		st.add_vertex(a)
		st.add_vertex(tail)
		st.add_vertex(a)
		st.add_vertex(b)
	# tail fin: a vertical triangle
	for v in [Vector3(0, 0.16, 0.5), Vector3(0, -0.16, 0.5), Vector3(0, 0, 0.25)]:
		st.set_normal(Vector3.RIGHT)
		st.add_vertex(v)
	for v in [Vector3(0, 0, 0.25), Vector3(0, -0.16, 0.5), Vector3(0, 0.16, 0.5)]:
		st.set_normal(Vector3.LEFT)
		st.add_vertex(v)
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.74, 0.66)   # pale, readable through the water's tint
	mat.roughness = 0.4
	mat.metallic = 0.2
	mat.metallic_specular = 0.7
	mesh.surface_set_material(0, mat)
	return mesh


func _process(delta: float) -> void:
	if _fish == null or GameState.world == null:
		return
	var player: Node3D = GameState.world.player
	var near := player != null and player.global_position.distance_to(global_position) < FISH_RANGE + size.length() * 0.5
	_fish.visible = near
	if not near:
		return
	_t += delta
	_update_fish()


func _update_fish() -> void:
	var mm := _fish.multimesh
	for i in _fish_state.size():
		var f: Dictionary = _fish_state[i]
		var ang: float = _t * f.w + f.phase
		var c: Vector2 = f.c
		var r: Vector2 = f.r
		var p := Vector2(c.x + cos(ang) * r.x, c.y + sin(ang) * r.y)
		var v := Vector2(-sin(ang) * r.x, cos(ang) * r.y) * signf(f.w)
		var yaw := atan2(-v.x, -v.y) + sin(_t * 6.0 + f.phase) * 0.12   # heading along the path, tail wiggle
		var bob := sin(_t * 0.7 + f.phase) * 0.08
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * f.len)
		mm.set_instance_transform(i, Transform3D(basis, Vector3(p.x, -f.depth + bob, p.y)))
