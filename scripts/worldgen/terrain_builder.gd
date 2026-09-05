# Builds Terrain3D region data for a tile from the pipeline's engine files
# (terrain_meta.json, heightmap.r32, canopy.r32, ortho.jpg) and scatters vegetation on it.
# Shared by the headless tools (tools/godot/import_terrain.gd, scatter_vegetation.gd) and by the
# world at runtime, when a downloaded tile in user:// has inputs but no region data yet.
# Long loops yield every few rows when `yielding` is true so a progress overlay can redraw.
class_name TerrainBuilder
extends RefCounted

signal progress(stage: String, fraction: float)

const NEUTRAL_ROUGHNESS_ALPHA := 0.5  # Terrain3D colour map alpha: 0.5 = no roughness change

# Texture ids used by classify(); order must match assets/terrain/textures.
const MATERIALS := [
	{"name": "meadow", "uv_scale": 0.2},        # 0: mid/dark green, rough grass
	{"name": "field", "uv_scale": 0.25},        # 1: bright saturated green (crops, lawns)
	{"name": "forest_floor", "uv_scale": 0.3},  # 2: dark canopy, shadow, brown soil
	{"name": "gravel", "uv_scale": 0.8},        # 3: bright, unsaturated (roads, yards, roofs)
	{"name": "soil", "texture": "forest_floor", "uv_scale": 0.4},  # 4: brown bare/ploughed soil (no trees)
]

# Vegetation rules. Control-map ids: 0 meadow, 1 field, 2 canopy/forest, 3 gravel, 4 bare soil.
# "height" = [min, max] canopy height (m, from canopy.r32) the rule applies to; trees are
# scaled so the model (MODEL_HEIGHT m tall) matches the measured canopy height.
const MODEL_HEIGHT := {"tree_birch": 18.8, "tree_pine": 20.7, "tree_spruce": 22.2, "tree_juniper": 7.8, "tree_juniper_dead": 5.6}
const RULES := [
	{"scene": "tree_pine", "ids": [2], "height": Vector2(13.0, 40.0), "per_100m2": 1.6, "scale": Vector2(0.9, 1.1), "range": 1200.0, "lod": [110.0, 1200.0], "shadows": true},
	{"scene": "tree_spruce", "ids": [2], "height": Vector2(11.0, 40.0), "per_100m2": 1.3, "scale": Vector2(0.9, 1.1), "range": 1200.0, "lod": [110.0, 1200.0], "shadows": true},
	{"scene": "tree_birch", "ids": [2], "height": Vector2(6.0, 18.0), "per_100m2": 1.4, "scale": Vector2(0.85, 1.15), "range": 1200.0, "lod": [110.0, 1200.0], "shadows": true},
	{"scene": "tree_juniper", "ids": [2], "height": Vector2(3.0, 8.0), "per_100m2": 1.0, "scale": Vector2(0.85, 1.15), "range": 500.0, "shadows": true},
	{"scene": "tree_juniper_dead", "ids": [2], "height": Vector2(3.0, 40.0), "per_100m2": 0.08, "scale": Vector2(0.85, 1.15), "range": 400.0, "shadows": true},
	{"scene": "bush_jello", "ids": [2], "height": Vector2(0.8, 3.0), "per_100m2": 3.0, "scale": Vector2(0.8, 1.6), "range": 250.0, "shadows": true},
	{"scene": "bush_brush", "ids": [0, 2], "height": Vector2(0.0, 3.0), "per_100m2": 0.5, "scale": Vector2(0.8, 1.6), "range": 150.0, "shadows": false},
	{"scene": "grass_card", "ids": [0, 1], "per_100m2": 45.0, "scale": Vector2(0.7, 1.3), "range": 80.0, "shadows": false},
	{"scene": "grass_tuft", "ids": [0, 1], "per_100m2": 6.0, "scale": Vector2(0.8, 1.4), "range": 60.0, "shadows": false},
	{"scene": "clover", "ids": [0], "per_100m2": 5.0, "scale": Vector2(0.8, 1.3), "range": 40.0, "shadows": false},
]

var yielding := false          # await a frame every YIELD_ROWS rows (runtime use)
var tree: SceneTree = null     # needed when yielding
const YIELD_ROWS := 32


static func read_meta(tile_dir: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(tile_dir + "/terrain_meta.json")
	if text.is_empty():
		return {}
	var parsed = JSON.parse_string(text)
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


## True when the tile's inputs exist (heightmap + meta), regardless of region data.
static func has_inputs(tile_dir: String) -> bool:
	return FileAccess.file_exists(tile_dir + "/terrain_meta.json") and FileAccess.file_exists(tile_dir + "/heightmap.r32")


static func has_region_data(tile_dir: String) -> bool:
	return FileAccess.file_exists(tile_dir + "/data/terrain3d_00_00.res")


func _tick(stage: String, f: float) -> void:
	progress.emit(stage, f)
	if yielding and tree:
		await tree.process_frame


## Height + control + colour maps into `terrain` (already in the tree, data object present).
## `layout` supplies "pads" to level. Returns false on bad inputs.
func import(terrain: Terrain3D, tile_dir: String, layout: Dictionary, z_scale_override: float = -1.0) -> bool:
	var meta := read_meta(tile_dir)
	if meta.is_empty():
		push_error("missing %s/terrain_meta.json" % tile_dir)
		return false
	var size := int(meta.size_px)
	var z_scale: float = z_scale_override if z_scale_override > 0.0 else float(meta.get("z_scale", 1.0))
	var raw := FileAccess.get_file_as_bytes(tile_dir + "/" + str(meta.heightmap))
	if raw.size() != size * size * 4:
		push_error("heightmap.r32 has %d bytes, expected %d" % [raw.size(), size * size * 4])
		return false
	var height_img := Image.create_from_data(size, size, false, Image.FORMAT_RF, raw)
	level_building_pads(height_img, layout.get("pads", []))
	await _tick("heights", 0.1)

	var ortho := Image.load_from_file(tile_dir + "/" + str(meta.texture))
	if ortho == null:
		push_error("could not load %s" % meta.texture)
		return false
	ortho.convert(Image.FORMAT_RGBA8)
	ortho.resize(size, size, Image.INTERPOLATE_LANCZOS)
	for y in size:
		for x in size:
			var c := ortho.get_pixel(x, y)
			c.a = NEUTRAL_ROUGHNESS_ALPHA
			ortho.set_pixel(x, y, c)
		if y % YIELD_ROWS == 0:
			await _tick("colour", 0.1 + 0.2 * y / size)
	if terrain.data == null:
		push_error("Terrain3D has no data object (data_directory must exist before it enters the tree)")
		return false
	if terrain.region_size != size:
		terrain.region_size = size

	var assets_path := tile_dir + "/terrain_assets.tres"
	var assets: Terrain3DAssets = load(assets_path) if ResourceLoader.exists(assets_path) else Terrain3DAssets.new()
	var mesh_list: Array = assets.mesh_list.duplicate()
	var i := 0
	for m in MATERIALS:
		var tex := Terrain3DTextureAsset.new()
		tex.name = m.name
		tex.id = i
		var tex_name: String = m.get("texture", m.name)
		tex.albedo_texture = load("res://assets/terrain/textures/%s_alb_ht.png" % tex_name)
		tex.normal_texture = load("res://assets/terrain/textures/%s_nrm_rgh.png" % tex_name)
		tex.uv_scale = m.uv_scale
		assets.set_texture(i, tex)
		i += 1
	terrain.assets = assets
	var texture_list: Array = assets.texture_list.duplicate()

	var canopy := load_canopy(tile_dir, meta, size)
	var control := await classify(ortho, canopy)
	terrain.data.import_images([height_img, control, ortho], Vector3.ZERO, 0.0, z_scale)
	terrain.data.calc_height_range(true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(tile_dir + "/data"))
	terrain.data.save_directory(tile_dir + "/data")
	assets.texture_list = texture_list
	assets.mesh_list = mesh_list
	var err := ResourceSaver.save(assets, assets_path)
	if err != OK:
		push_error("could not save %s (%d)" % [assets_path, err])
	await _tick("saved", 0.6)
	return true


## Level the ground under authored buildings ("pads": x, z, w, d in tile metres): the footprint
## takes the mean height, blended out over a 5 m margin. Shared by all eras.
static func level_building_pads(img: Image, pads: Array) -> void:
	var size := img.get_width()
	for pad in pads:
		var cx: float = pad[0]
		var cz: float = pad[1]
		var hw: float = pad[2] / 2.0 + 1.0
		var hd: float = pad[3] / 2.0 + 1.0
		var margin := 5.0
		var sum := 0.0
		var n := 0
		for z in range(int(cz - hd), int(cz + hd) + 1):
			for x in range(int(cx - hw), int(cx + hw) + 1):
				if x >= 0 and z >= 0 and x < size and z < size:
					sum += img.get_pixel(x, z).r
					n += 1
		if n == 0:
			continue
		var level := sum / n
		for z in range(int(cz - hd - margin), int(cz + hd + margin) + 1):
			for x in range(int(cx - hw - margin), int(cx + hw + margin) + 1):
				if x < 0 or z < 0 or x >= size or z >= size:
					continue
				var dx := maxf(absf(x - cx) - hw, 0.0)
				var dz := maxf(absf(z - cz) - hd, 0.0)
				var d := sqrt(dx * dx + dz * dz)
				var t := clampf(1.0 - d / margin, 0.0, 1.0)
				t = t * t * (3.0 - 2.0 * t)
				var h := img.get_pixel(x, z).r
				img.set_pixel(x, z, Color(lerpf(h, level, t), 0, 0, 1))
		print("[terrain_builder] pad at (%d,%d) %dx%d m levelled to %.2f m" % [cx, cz, pad[2], pad[3], level])


## Optional canopy/object height layer (metres above ground) written by fetch_tile.py.
static func load_canopy(tile_dir: String, meta: Dictionary, size: int) -> Image:
	if meta.get("canopy") == null:
		return null
	var raw := FileAccess.get_file_as_bytes(tile_dir + "/" + str(meta.canopy.file))
	if raw.size() != size * size * 4:
		push_warning("canopy.r32 has unexpected size; ignoring")
		return null
	return Image.create_from_data(size, size, false, Image.FORMAT_RF, raw)


## Colour classification of the (vertex-resolution) orthophoto into material ids, encoded into
## a Terrain3D control map (base = overlay = id, blend 0). Measured canopy height overrides colour.
func classify(img: Image, canopy: Image = null) -> Image:
	var size := img.get_width()
	var ctrl := Image.create_empty(size, size, false, Image.FORMAT_RF)
	var counts := [0, 0, 0, 0, 0]
	for y in size:
		for x in size:
			var c := img.get_pixel(x, y)
			var v := maxf(c.r, maxf(c.g, c.b))
			var sat := 0.0 if v == 0.0 else (v - minf(c.r, minf(c.g, c.b))) / v
			var green_excess := c.g - maxf(c.r, c.b)
			var id: int
			if v > 0.62 and sat < 0.22:
				id = 3   # gravel / roofs / bare bright ground
			elif green_excess > 0.03:
				id = 1 if (v > 0.5 and sat > 0.35) else (0 if v > 0.36 else 2)  # field / meadow / canopy
			elif v < 0.25:
				id = 2   # deep shadow: under canopy
			else:
				id = 4   # brown bare or ploughed soil
			if canopy != null and canopy.get_pixel(x, y).r >= 2.5 and id != 3:
				id = 2
			counts[id] += 1
			var bits: int = Terrain3DUtil.enc_base(id) | Terrain3DUtil.enc_overlay(id) | Terrain3DUtil.enc_blend(0)
			ctrl.set_pixel(x, y, Color(Terrain3DUtil.as_float(bits), 0, 0, 1))
		if y % YIELD_ROWS == 0:
			await _tick("land cover", 0.3 + 0.3 * y / size)
	print("[terrain_builder] control map: meadow %d  field %d  canopy %d  gravel %d  soil %d texels" % counts)
	return ctrl


## Scatter trees, bushes and grass by land-cover class and canopy height; save into the region file.
## `exclusions` are [x, z, r] circles kept clear. Returns instance counts per rule.
func scatter(terrain: Terrain3D, tile_dir: String, exclusions: Array, seed_value: int = 1798) -> Array:
	var assets: Terrain3DAssets = terrain.assets
	var texture_list: Array = assets.texture_list.duplicate()   # headless init drops textures; keep them
	for i in RULES.size():
		var r: Dictionary = RULES[i]
		var ma := Terrain3DMeshAsset.new()
		ma.name = r.scene
		ma.id = i
		var scene_path: String = "res://assets/models/trees/%s_lod.tscn" % r.scene.trim_prefix("tree_") if r.has("lod") else "res://assets/vegetation/%s.tscn" % r.scene
		ma.scene_file = load(scene_path)
		if r.has("lod"):
			ma.last_lod = 1
			ma.lod0_range = r.lod[0]
			ma.lod1_range = r.lod[1]
			ma.last_shadow_lod = 0
		else:
			ma.last_lod = 0
			ma.lod0_range = r.range
		ma.cast_shadows = 1 if r.shadows else 0
		assets.set_mesh_asset(i, ma)
		terrain.instancer.clear_by_mesh(i)
	var ctrl: Image = terrain.data.control_maps[0]
	var size := ctrl.get_width()
	var canopy: Image = null
	var meta := read_meta(tile_dir)
	if meta.get("canopy") != null:
		canopy = Image.create_from_data(size, size, false, Image.FORMAT_RF, FileAccess.get_file_as_bytes(tile_dir + "/" + str(meta.canopy.file)))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var batches: Array = []
	var colors: Array = []
	for i in RULES.size():
		batches.append([] as Array[Transform3D])
		colors.append(PackedColorArray())
	for y in size:
		for x in size:
			var id := Terrain3DUtil.get_base(Terrain3DUtil.as_uint(ctrl.get_pixel(x, y).r))
			var excluded := false
			for e in exclusions:
				if Vector2(x, y).distance_to(Vector2(float(e[0]), float(e[1]))) < float(e[2]):
					excluded = true
					break
			if excluded:
				continue
			var h: float = canopy.get_pixel(x, y).r if canopy else -1.0
			for i in RULES.size():
				var r: Dictionary = RULES[i]
				if not (id in r.ids):
					continue
				if canopy and r.has("height") and (h < r.height.x or h >= r.height.y):
					continue
				if rng.randf() < r.per_100m2 / 100.0:
					var pos := Vector3(x + rng.randf(), 0.0, y + rng.randf())
					pos.y = terrain.data.get_height(pos)
					var s: float = rng.randf_range(r.scale.x, r.scale.y)
					if canopy and MODEL_HEIGHT.has(r.scene) and h > 0.0:
						s *= clampf(h / MODEL_HEIGHT[r.scene], 0.5, 3.0)
					var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s)
					batches[i].append(Transform3D(basis, pos))
					var v: float = rng.randf_range(0.72, 1.08)
					colors[i].append(Color(v * rng.randf_range(0.9, 1.15), v, v * rng.randf_range(0.8, 1.0)))
		if y % YIELD_ROWS == 0:
			await _tick("vegetation", 0.6 + 0.35 * y / size)
	var counts := []
	for i in RULES.size():
		if batches[i].size() > 0:
			terrain.instancer.add_transforms(i, batches[i], colors[i], i == RULES.size() - 1)
		counts.append(batches[i].size())
		print("[terrain_builder] %-18s %6d instances" % [RULES[i].scene, batches[i].size()])
	terrain.data.save_directory(tile_dir + "/data")
	assets.texture_list = texture_list
	ResourceSaver.save(assets, tile_dir + "/terrain_assets.tres")
	await _tick("done", 1.0)
	return counts
