# Roads from ETAK (sites/<id>/roads.json) as ribbons laid on the terrain: asphalt with a pale kerb for
# streets, light paving for pedestrian and cycle paths (kergliiklustee), gravel for other roads and
# trails. Heights are sampled every few metres so the ribbon follows the ground; a small lift keeps it
# above the drape. One mesh per kind. Hover text and the codes overlay read `nearest()`.
class_name RoadNetwork
extends Node3D

@export var source := "roads.json"     # inside the active pack
@export var lift := 0.08
const STEP := 3.0
const STYLE := {
	"street": {"color": Color(0.16, 0.16, 0.17), "kerb": Color(0.7, 0.68, 0.63), "rough": 0.95},
	"road": {"color": Color(0.48, 0.44, 0.36), "kerb": null, "rough": 1.0},
	"path": {"color": Color(0.62, 0.6, 0.56), "kerb": Color(0.5, 0.48, 0.45), "rough": 0.95},
	"trail": {"color": Color(0.42, 0.36, 0.26), "kerb": null, "rough": 1.0},
}

var roads: Array = []


func _ready() -> void:
	var text := FileAccess.get_file_as_string(Sites.path_in(Sites.pack_of(self), source))
	var parsed = JSON.parse_string(text) if text != "" else null
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	roads = parsed.get("roads", [])
	var terrain: Terrain3D = GameState.world.terrain if GameState.world else null
	if terrain == null:
		return
	var tools := {}   # "<kind>" and "<kind>_kerb" -> SurfaceTool; one plain material each
	for r in roads:
		var kind := str(r.get("kind", "road"))
		var style: Dictionary = STYLE.get(kind, STYLE.road)
		for key in [kind, kind + "_kerb"]:
			if not tools.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[key] = st
		var pts := _resample(r.points)
		var half: float = maxf(float(r.get("width", 3.0)), 1.2) / 2.0
		_ribbon(tools[kind], pts, half, terrain, lift, 0.0)
		if style.kerb != null:
			for side_sign in [-1.0, 1.0]:
				_ribbon(tools[kind + "_kerb"], pts, 0.18, terrain, lift + 0.05, side_sign * (half + 0.18))
	for key in tools:
		var st: SurfaceTool = tools[key]
		var mesh: ArrayMesh = st.commit()
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var kind: String = str(key).trim_suffix("_kerb")
		var style: Dictionary = STYLE.get(kind, STYLE.road)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = style.kerb if key.ends_with("_kerb") else style.color
		mat.roughness = style.rough
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.name = "Roads_" + key
		add_child(mi)


func _resample(points: Array) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in range(points.size() - 1):
		var a := Vector2(float(points[i][0]), float(points[i][1]))
		var b := Vector2(float(points[i + 1][0]), float(points[i + 1][1]))
		var n := maxi(1, int(a.distance_to(b) / STEP))
		for k in n:
			out.append(a.lerp(b, float(k) / n))
	var last: Array = points[points.size() - 1]
	out.append(Vector2(float(last[0]), float(last[1])))
	return out


## A strip `half` wide, `offset` metres to the side of the centre line, `up` above the ground.
func _ribbon(st: SurfaceTool, pts: Array[Vector2], half: float, terrain: Terrain3D, up: float, offset: float) -> void:
	if pts.size() < 2:
		return
	var left: Array[Vector3] = []
	var right: Array[Vector3] = []
	for i in pts.size():
		var dir := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var normal := Vector2(-dir.y, dir.x)
		var p := pts[i] + normal * offset
		var side := normal * half
		for s in [p + side, p - side]:
			var h := terrain.data.get_height(to_global(Vector3(s.x, 0, s.y)))
			if is_nan(h):
				h = 0.0
			(left if s == p + side else right).append(Vector3(s.x, h + up, s.y))
	for i in range(pts.size() - 1):
		var a := left[i]
		var b := right[i]
		var c := right[i + 1]
		var d := left[i + 1]
		for v in [a, b, c, a, c, d]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)


## Nearest road segment to a tile position: {name, kind, type, width, surface, distance}.
func nearest(pos: Vector3, max_dist := 12.0) -> Dictionary:
	var best := {}
	var best_d := max_dist
	var local := to_local(pos)
	var p2 := Vector2(local.x, local.z)
	for r in roads:
		var pts: Array = r.points
		for i in range(pts.size() - 1):
			var a := Vector2(float(pts[i][0]), float(pts[i][1]))
			var b := Vector2(float(pts[i + 1][0]), float(pts[i + 1][1]))
			var d := p2.distance_to(Geometry2D.get_closest_point_to_segment(p2, a, b))
			if d < best_d:
				best_d = d
				best = {"name": r.get("name"), "kind": r.kind, "type": r.get("type"), "width": r.get("width"), "surface": r.get("surface"), "distance": snappedf(d, 0.1), "id": r.get("id")}
	return best
