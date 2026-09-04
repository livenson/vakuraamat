# Vakuraamat terrain pipeline, step 2 of 2: engine files -> Terrain3D region data.
#
# Reads assets/terrain/<tile>/{terrain_meta.json, heightmap.r32, ortho.jpg}
# produced by tools/pipeline/fetch_tile.py and writes:
#   assets/terrain/<tile>/data/terrain3d_00_00.res   (height + control + colour maps)
#   assets/terrain/<tile>/terrain_assets.tres         (one neutral white ground texture)
#
# Run headless from the project root:
#   godot --headless --path . -s res://tools/godot/import_terrain.gd -- --tile=palmse
#
# World mapping (see terrain_meta.json): the tile's north-west corner sits at
# Godot (0, y, 0); +X is east, +Z is south, so north is -Z.
extends SceneTree

const NEUTRAL_ROUGHNESS_ALPHA := 0.5  # Terrain3D colour map alpha: 0.5 = no roughness change

# Texture ids used by _classify_orthophoto(); order must match assets/terrain/textures.
const MATERIALS := [
	{"name": "meadow", "uv_scale": 0.2},        # 0: mid/dark green, rough grass
	{"name": "field", "uv_scale": 0.25},        # 1: bright saturated green (crops, lawns)
	{"name": "forest_floor", "uv_scale": 0.3}, # 2: dark canopy, shadow, brown soil
	{"name": "gravel", "uv_scale": 0.8},        # 3: bright, unsaturated (roads, yards, roofs)
	{"name": "soil", "texture": "forest_floor", "uv_scale": 0.4},  # 4: brown bare/ploughed soil (no trees)
]


func _init() -> void:
	var args := _user_args()
	var tile: String = args.get("tile", "palmse")
	var dir := "res://assets/terrain/%s" % tile
	var meta_text := FileAccess.get_file_as_string(dir + "/terrain_meta.json")
	if meta_text.is_empty():
		push_error("missing %s/terrain_meta.json - run tools/pipeline/fetch_tile.py first" % dir)
		quit(1)
		return
	var meta: Dictionary = JSON.parse_string(meta_text)
	var size := int(meta.size_px)
	var z_scale := float(args.get("z-scale", meta.get("z_scale", 1.0)))
	print("[import_terrain] tile=%s size=%d z_scale=%.2f" % [tile, size, z_scale])

	# --- height map: raw float32 -> Image RF ---------------------------------
	var raw := FileAccess.get_file_as_bytes(dir + "/" + meta.heightmap)
	if raw.size() != size * size * 4:
		push_error("heightmap.r32 has %d bytes, expected %d" % [raw.size(), size * size * 4])
		quit(1)
		return
	var height_img := Image.create_from_data(size, size, false, Image.FORMAT_RF, raw)
	_level_building_pads(height_img)

	# --- colour map: orthophoto resampled to one texel per vertex ------------
	var ortho := Image.load_from_file(dir + "/" + meta.texture)
	if ortho == null:
		push_error("could not load %s" % meta.texture)
		quit(1)
		return
	ortho.convert(Image.FORMAT_RGBA8)
	ortho.resize(size, size, Image.INTERPOLATE_LANCZOS)
	# Alpha is the roughness modifier; keep it neutral so the ground reads matte but not chalky.
	for y in size:
		for x in size:
			var c := ortho.get_pixel(x, y)
			c.a = NEUTRAL_ROUGHNESS_ALPHA
			ortho.set_pixel(x, y, c)

	# --- build a Terrain3D node in the headless tree --------------------------
	# Terrain3D only creates its data object if the data directory exists.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir + "/data"))
	var terrain := Terrain3D.new()
	terrain.name = "Terrain3D"
	terrain.data_directory = dir + "/data"
	get_root().add_child(terrain)
	# Nodes added from SceneTree._init() only enter the tree on the first frame;
	# Terrain3D creates its data/material/assets objects on ENTER_TREE.
	await process_frame
	if terrain.data == null:
		push_error("Terrain3D has no data object after entering the tree")
		quit(1)
		return
	if terrain.region_size != size:
		terrain.region_size = size
	print("[import_terrain] region_size=%d vertex_spacing=%.2f" % [terrain.region_size, terrain.vertex_spacing])

	# Detail materials (assets/terrain/textures, CC0). The control map picks one per metre
	# from the orthophoto colour; the shader tints the detail with the orthophoto.
	# Reuse the existing assets file so mesh assets from scatter_vegetation.gd survive re-imports.
	var assets_path := dir + "/terrain_assets.tres"
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

	var canopy := _load_canopy(dir, meta, size)
	var control := _classify_orthophoto(ortho, canopy)

	# Region (0,0) spans Godot x 0..size, z 0..size; image row 0 lands at z=0 (north).
	terrain.data.import_images([height_img, control, ortho], Vector3.ZERO, 0.0, z_scale)
	terrain.data.calc_height_range(true)

	terrain.data.save_directory(dir + "/data")
	assets.texture_list = texture_list
	assets.mesh_list = mesh_list
	assets.save(assets_path)
	# The material is deliberately NOT saved: a Terrain3DMaterial written from headless
	# mode has uninitialised shader parameters. Scenes define it inline (world_background = None).
	# Likewise never set region_size on the Terrain3D node in a scene: the region file carries
	# its own size and setting it before load crashes Terrain3D 1.0.2 on Godot 4.7.

	# --- verification against the source raster ------------------------------
	var c := size / 2
	var probe := {
		"centre (%d,%d)" % [c, c]: Vector3(c, 0, c),
		"north-west (1,1)": Vector3(1, 0, 1),
		"south-east (%d,%d)" % [size - 1, size - 1]: Vector3(size - 1, 0, size - 1),
	}
	for label in probe:
		var p: Vector3 = probe[label]
		print("[import_terrain] height at %s = %.3f (source px %.3f)" % [
			label, terrain.data.get_height(p), height_img.get_pixel(int(p.x), int(p.z)).r * z_scale])
	print("[import_terrain] regions=%s has_region(-1,-1)=%s" % [
		terrain.data.region_locations, terrain.data.has_regionp(Vector3(-1, 0, -1))])
	print("[import_terrain] done -> %s/data" % dir)
	quit()


## Very simple colour classification of the (already vertex-resolution) orthophoto into
## material ids, encoded into a Terrain3D control map (base = overlay = id, blend 0).
## Level the ground under authored buildings (data/site_layout.json "pads": x, z, w, d in tile metres):
## the footprint takes the mean height, blended out over a 5 m margin. Shared by all eras.
func _level_building_pads(img: Image) -> void:
	if not FileAccess.file_exists("res://data/site_layout.json"):
		return
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/site_layout.json"))
	var pads: Array = layout.get("pads", [])
	var size := img.get_width()
	for pad in pads:
		var cx: float = pad[0]
		var cz: float = pad[1]
		var hw: float = pad[2] / 2.0 + 1.0
		var hd: float = pad[3] / 2.0 + 1.0
		var margin := 5.0
		# mean height inside the footprint
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
		print("[import_terrain] pad at (%d,%d) %dx%d m levelled to %.2f m" % [cx, cz, pad[2], pad[3], level])


## Optional canopy/object height layer (metres above ground) written by fetch_tile.py.
func _load_canopy(dir: String, meta: Dictionary, size: int) -> Image:
	if meta.get("canopy") == null:
		return null
	var raw := FileAccess.get_file_as_bytes(dir + "/" + meta.canopy.file)
	if raw.size() != size * size * 4:
		push_warning("canopy.r32 has unexpected size; ignoring")
		return null
	return Image.create_from_data(size, size, false, Image.FORMAT_RF, raw)


func _classify_orthophoto(img: Image, canopy: Image = null) -> Image:
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
			# Measured heights beat colour: anything over 2.5 m that is not a bright roof is canopy.
			if canopy != null and canopy.get_pixel(x, y).r >= 2.5 and id != 3:
				id = 2
			counts[id] += 1
			var bits: int = Terrain3DUtil.enc_base(id) | Terrain3DUtil.enc_overlay(id) | Terrain3DUtil.enc_blend(0)
			ctrl.set_pixel(x, y, Color(Terrain3DUtil.as_float(bits), 0, 0, 1))
	print("[import_terrain] control map: meadow %d  field %d  canopy %d  gravel %d  soil %d texels" % counts)
	return ctrl


func _user_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1]
	return out
