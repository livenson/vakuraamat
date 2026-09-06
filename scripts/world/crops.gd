# Crops on the farmed fields: PRIA's field register (tools/pipeline/fetch_fields.py writes
# fields_2026.json with each field's polygon and the crop declared for area aid) becomes rows of
# plants, one MultiMesh per crop kind. Cereals stand golden, rape yellow, potatoes and legumes as
# low green rows, maize tall; grassland and fallow stay as the terrain shows them. Plants are
# crossed cards with a procedural texture, no assets; rows follow the field's longest edge.
class_name Crops
extends Node3D

const MAX_PER_FIELD := 40000
const VIEW_RANGE := 260.0

# kind -> plant: height and width in metres, spacing along the row and between rows, texture colours
const PLANTS := {
	"cereal": {"height": 0.85, "width": 0.7, "step": 0.55, "row": 0.6, "stem": Color(0.84, 0.74, 0.4), "head": Color(0.9, 0.78, 0.42), "shape": "ear"},
	"rape": {"height": 1.1, "width": 0.8, "step": 0.6, "row": 0.65, "stem": Color(0.42, 0.55, 0.25), "head": Color(0.92, 0.85, 0.2), "shape": "ear"},
	"potato": {"height": 0.45, "width": 0.7, "step": 0.45, "row": 0.8, "stem": Color(0.25, 0.42, 0.16), "head": Color(0.32, 0.52, 0.2), "shape": "bush"},
	"legume": {"height": 0.6, "width": 0.6, "step": 0.4, "row": 0.6, "stem": Color(0.3, 0.48, 0.2), "head": Color(0.38, 0.58, 0.24), "shape": "bush"},
	"maize": {"height": 2.2, "width": 0.9, "step": 0.3, "row": 0.75, "stem": Color(0.35, 0.5, 0.2), "head": Color(0.45, 0.6, 0.22), "shape": "leaf"},
	"other": {"height": 0.5, "width": 0.6, "step": 0.5, "row": 0.6, "stem": Color(0.3, 0.46, 0.2), "head": Color(0.36, 0.54, 0.22), "shape": "bush"},
}

static var _meshes: Dictionary = {}   # kind -> ArrayMesh (shared between tiles)


## Plant every field of `pack` under `root`, sampling the ground of `terrain`.
static func place(pack: String, root: Node3D, terrain: Terrain3D) -> void:
	var path := Sites.path_in(pack, "fields_2026.json")
	if not FileAccess.file_exists(path):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("fields"):
		return
	var crops := Crops.new()
	crops.name = "Crops"
	root.add_child(crops)
	var offset := root.position   # a streamed tile's root sits at its tile offset; plants stay local
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("crops_" + pack)
	var batches: Dictionary = {}   # kind -> [Transform3D]
	var counts: Dictionary = {}
	for f in parsed.fields:
		var kind := str(f.get("kind", "grass"))
		if not PLANTS.has(kind):
			continue   # grassland and fallow: the ground already shows them
		var poly := PackedVector2Array()
		for c in f.get("polygon", []):
			poly.append(Vector2(float(c[0]), float(c[1])))
		if poly.size() < 3:
			continue
		if not batches.has(kind):
			batches[kind] = [] as Array[Transform3D]
		var n0: int = batches[kind].size()
		crops._sow(poly, PLANTS[kind], terrain, offset, rng, batches[kind])
		counts[str(f.get("crop", kind))] = int(counts.get(str(f.get("crop", kind)), 0)) + batches[kind].size() - n0
	for kind in batches:
		if batches[kind].is_empty():
			continue
		var mmi := MultiMeshInstance3D.new()
		mmi.name = kind
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _mesh(kind)
		mm.instance_count = batches[kind].size()
		for i in batches[kind].size():
			mm.set_instance_transform(i, batches[kind][i])
			var v := rng.randf_range(0.85, 1.1)
			mm.set_instance_color(i, Color(v, v * rng.randf_range(0.95, 1.05), v))
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = VIEW_RANGE
		mmi.visibility_range_end_margin = 40.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		crops.add_child(mmi)
	if not counts.is_empty():
		print("[crops] %s: %s" % [pack, counts])


## Rows of one plant across a field polygon (local metres), ground height from the terrain.
func _sow(poly: PackedVector2Array, plant: Dictionary, terrain: Terrain3D, offset: Vector3, rng: RandomNumberGenerator, out: Array) -> void:
	# rows run along the longest edge
	var best := 0.0
	var dir := Vector2.RIGHT
	for i in poly.size():
		var e := poly[(i + 1) % poly.size()] - poly[i]
		if e.length() > best:
			best = e.length()
			dir = e.normalized()
	var nrm := Vector2(-dir.y, dir.x)
	var smin := INF
	var smax := -INF
	var tmin := INF
	var tmax := -INF
	for p in poly:
		smin = minf(smin, p.dot(dir))
		smax = maxf(smax, p.dot(dir))
		tmin = minf(tmin, p.dot(nrm))
		tmax = maxf(tmax, p.dot(nrm))
	var step: float = plant.step
	var row: float = plant.row
	var cells := ((smax - smin) / step) * ((tmax - tmin) / row)
	var keep := minf(1.0, MAX_PER_FIELD / maxf(cells, 1.0))
	var yaw := atan2(dir.y, dir.x)
	var t := tmin + row * 0.5
	while t < tmax:
		var s := smin + step * rng.randf()
		while s < smax:
			if keep >= 1.0 or rng.randf() < keep:
				var p2 := dir * s + nrm * (t + rng.randf_range(-0.08, 0.08))
				if Geometry2D.is_point_in_polygon(p2, poly):
					var pos := Vector3(p2.x, 0.0, p2.y)
					pos.y = terrain.data.get_height(pos + offset)
					if not is_nan(pos.y):
						var sc: float = rng.randf_range(0.85, 1.15)
						var basis := Basis(Vector3.UP, -yaw + rng.randf_range(-0.25, 0.25)).scaled(Vector3(sc, sc * rng.randf_range(0.9, 1.1), sc))
						out.append(Transform3D(basis, pos))
			s += step
		t += row


## Three crossed cards of the plant's size with its procedural texture.
static func _mesh(kind: String) -> ArrayMesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var plant: Dictionary = PLANTS[kind]
	var w: float = plant.width
	var h: float = plant.height
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 3:
		var a := k * PI / 3.0
		var dx := Vector3(cos(a), 0.0, sin(a)) * w * 0.5
		var quad := [Vector3(-dx.x, 0.0, -dx.z), Vector3(dx.x, 0.0, dx.z), Vector3(dx.x, h, dx.z), Vector3(-dx.x, h, -dx.z)]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP)
			st.set_uv(uvs[idx])
			st.add_vertex(quad[idx])
	var mesh := st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/crop.gdshader")
	var baked := "res://assets/textures/crops/%s.png" % kind   # cards baked from the Sketchfab farm plants (tools/godot/bake_cards.tscn)
	mat.set_shader_parameter("tex", load(baked) if ResourceLoader.exists(baked) else _texture(plant))
	mesh.surface_set_material(0, mat)
	_meshes[kind] = mesh
	return mesh


## A plant drawn into a small RGBA image: stems with an ear, a leafy bush or maize blades.
static func _texture(plant: Dictionary) -> ImageTexture:
	var wpx := 48
	var hpx := 96
	var img := Image.create(wpx, hpx, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var stem: Color = plant.stem
	var head: Color = plant.head
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(plant))
	match str(plant.shape):
		"ear":
			for k in 5:
				var x0 := 6 + k * 9 + rng.randi_range(-2, 2)
				var top := rng.randi_range(4, 18)
				for y in range(top + 14, hpx):
					var x := x0 + int(sin(y * 0.15 + k) * 1.5)
					for dx in [0, 1]:
						img.set_pixel(clampi(x + dx, 0, wpx - 1), y, stem.darkened(rng.randf() * 0.1))
				for y in range(top, top + 16):
					var half := 2 + int(2.0 * sin(float(y - top) / 16.0 * PI))
					for x in range(x0 - half, x0 + half + 1):
						if x >= 0 and x < wpx and (x + y) % 2 == 0:
							img.set_pixel(x, y, head.lightened(rng.randf() * 0.12))
		"leaf":
			for k in 3:
				var x0 := 12 + k * 12
				for y in range(6, hpx):
					img.set_pixel(clampi(x0 + int(sin(y * 0.08) * 3.0), 0, wpx - 1), y, stem)
				for b in 4:
					var y0 := 14 + b * 18 + rng.randi_range(-3, 3)
					var sgn := 1 if (b + k) % 2 == 0 else -1
					for i in 18:
						var x := x0 + sgn * i
						var y := y0 + int(i * 0.35)
						for dy in [-1, 0, 1]:
							if x >= 0 and x < wpx and y + dy >= 0 and y + dy < hpx:
								img.set_pixel(x, y + dy, head.darkened(0.1 * (i % 3)))
		_:
			for b in 40:
				var cx := rng.randi_range(4, wpx - 5)
				var cy := rng.randi_range(hpx / 5, hpx - 8)
				var r := rng.randi_range(3, 6)
				for y in range(cy - r, cy + r + 1):
					for x in range(cx - r, cx + r + 1):
						if x >= 0 and x < wpx and y >= 0 and y < hpx and (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r:
							img.set_pixel(x, y, (head if (x + y) % 3 else stem).darkened(float(y) / hpx * 0.25))
			for x in range(wpx / 2 - 1, wpx / 2 + 1):
				for y in range(hpx / 2, hpx):
					img.set_pixel(x, y, stem)
	return ImageTexture.create_from_image(img)
