# Scatters vegetation over a terrain tile with the Terrain3D instancer, driven by the
# land-cover class stored in the control map by import_terrain.gd. Instances are saved
# into the region files; mesh assets into terrain_assets.tres. Re-runnable.
#   godot --headless --path . -s res://tools/godot/scatter_vegetation.gd -- --tile=palupera
extends SceneTree

# Control-map ids: 0 meadow, 1 field, 2 canopy/forest, 3 gravel, 4 bare soil.
# "height" = [min, max] canopy height (m, from canopy.r32) the rule applies to; trees are
# scaled so the model (MODEL_HEIGHT m tall) matches the measured canopy height.
const MODEL_HEIGHT := {"tree_birch": 18.8, "tree_pine": 20.7, "tree_spruce": 22.2, "tree_juniper": 7.8, "tree_juniper_dead": 5.6}
# Species by measured canopy height (Otepää mix: pine/spruce tall stands, birch mid, juniper edges).
# "lod": [LOD0 range, LOD1 range] metres; LOD1 is the baked impostor.
const RULES := [
	{"scene": "tree_pine", "ids": [2], "height": Vector2(13.0, 40.0), "per_100m2": 1.6, "scale": Vector2(0.9, 1.1), "range": 1200.0, "lod": [110.0, 1200.0], "shadows": true},
	{"scene": "tree_spruce", "ids": [2], "height": Vector2(11.0, 40.0), "per_100m2": 1.3, "scale": Vector2(0.9, 1.1), "range": 1200.0, "lod": [110.0, 1200.0], "shadows": true},
	{"scene": "tree_birch", "ids": [2], "height": Vector2(6.0, 18.0), "per_100m2": 1.4, "scale": Vector2(0.85, 1.15), "range": 1200.0, "lod": [110.0, 1200.0], "shadows": true},
	{"scene": "tree_juniper", "ids": [2], "height": Vector2(3.0, 8.0), "per_100m2": 1.0, "scale": Vector2(0.85, 1.15), "range": 500.0, "shadows": true},
	{"scene": "tree_juniper_dead", "ids": [2], "height": Vector2(3.0, 40.0), "per_100m2": 0.08, "scale": Vector2(0.85, 1.15), "range": 400.0, "shadows": true},
	{"scene": "bush_jello", "ids": [2], "height": Vector2(0.8, 3.0), "per_100m2": 3.0, "scale": Vector2(0.8, 1.6), "range": 250.0, "shadows": true},
	{"scene": "bush_brush", "ids": [0, 2], "height": Vector2(0.0, 3.0), "per_100m2": 0.5, "scale": Vector2(0.8, 1.6), "range": 150.0, "shadows": false},
	{"scene": "grass_tuft", "ids": [0, 1], "per_100m2": 30.0, "scale": Vector2(0.8, 1.4), "range": 70.0, "shadows": false},
	{"scene": "clover", "ids": [0], "per_100m2": 5.0, "scale": Vector2(0.8, 1.3), "range": 40.0, "shadows": false},
]


func _init() -> void:
	var tile := "palupera"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tile="):
			tile = a.trim_prefix("--tile=")
	var dir := "res://assets/terrain/%s" % tile
	var terrain := Terrain3D.new()
	terrain.data_directory = dir + "/data"
	terrain.assets = load(dir + "/terrain_assets.tres")
	# Headless initialisation drops the ground texture assets (no texture arrays can be built);
	# keep a copy so the save below does not lose them.
	var texture_list: Array = terrain.assets.texture_list.duplicate()
	get_root().add_child(terrain)
	await process_frame
	if terrain.data == null or terrain.data.region_locations.is_empty():
		push_error("no terrain data in %s - run import_terrain.gd first" % dir)
		quit(1)
		return

	var assets: Terrain3DAssets = terrain.assets
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

	# Keep authored spots (buildings, the oak, the well...) clear: circles from data/site_layout.json.
	var exclusions: Array = []
	if FileAccess.file_exists("res://data/site_layout.json"):
		var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/site_layout.json"))
		exclusions = layout.get("exclusions", [])
	var ctrl: Image = terrain.data.control_maps[0]
	var size := ctrl.get_width()
	var canopy: Image = null
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir + "/terrain_meta.json"))
	if meta.get("canopy") != null:
		canopy = Image.create_from_data(size, size, false, Image.FORMAT_RF, FileAccess.get_file_as_bytes(dir + "/" + meta.canopy.file))
		print("[scatter_vegetation] using canopy heights from %s" % meta.canopy.source)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1798
	var batches: Array = []
	for i in RULES.size():
		batches.append([] as Array[Transform3D])
	for y in size:
		for x in size:
			var id := Terrain3DUtil.get_base(Terrain3DUtil.as_uint(ctrl.get_pixel(x, y).r))
			var excluded := false
			for e in exclusions:
				if Vector2(x, y).distance_to(Vector2(e[0], e[1])) < float(e[2]):
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
	for i in RULES.size():
		if batches[i].size() > 0:
			terrain.instancer.add_transforms(i, batches[i], PackedColorArray(), i == RULES.size() - 1)
		print("[scatter_vegetation] %-18s %6d instances" % [RULES[i].scene, batches[i].size()])
	terrain.data.save_directory(dir + "/data")
	assets.texture_list = texture_list
	assets.save(dir + "/terrain_assets.tres")
	print("[scatter_vegetation] saved -> %s (textures kept: %d)" % [dir, texture_list.size()])
	quit()
