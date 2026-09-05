# Scatters vegetation over a terrain tile with the Terrain3D instancer, driven by the land-cover
# class stored in the control map by import_terrain.gd (see scripts/worldgen/terrain_builder.gd).
#   godot --headless --path . -s res://tools/godot/scatter_vegetation.gd -- --site=palupera [--tile=<tile>]
extends SceneTree


func _init() -> void:
	var site := "palupera"
	var tile := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--site="):
			site = a.trim_prefix("--site=")
		elif a.begins_with("--tile="):
			tile = a.trim_prefix("--tile=")
	if tile == "":
		var mtext := FileAccess.get_file_as_string("res://sites/%s/site.json" % site)
		var manifest = JSON.parse_string(mtext) if not mtext.is_empty() else null
		tile = str(manifest.get("terrain", {}).get("tile", site)) if typeof(manifest) == TYPE_DICTIONARY else site
	var dir := "res://assets/terrain/%s" % tile
	var terrain := Terrain3D.new()
	terrain.data_directory = dir + "/data"
	terrain.assets = load(dir + "/terrain_assets.tres")
	# Headless initialisation drops the ground texture assets (no texture arrays can be built);
	# keep a copy so the save does not lose them.
	var texture_list: Array = terrain.assets.texture_list.duplicate()
	get_root().add_child(terrain)
	await process_frame
	if terrain.data == null or terrain.data.region_locations.is_empty():
		push_error("no terrain data in %s - run import_terrain.gd first" % dir)
		quit(1)
		return
	# Keep authored spots (buildings, the oak, the well...) clear: circles from the site layout.
	var exclusions: Array = []
	var layout_path := "res://sites/%s/layout.json" % site
	if FileAccess.file_exists(layout_path):
		var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(layout_path))
		exclusions = layout.get("exclusions", [])
	var manifest_text := FileAccess.get_file_as_string("res://sites/%s/site.json" % site)
	var manifest = JSON.parse_string(manifest_text) if manifest_text != "" else null
	if typeof(manifest) == TYPE_DICTIONARY and manifest.get("water", "") != "":
		exclusions = exclusions + TerrainBuilder.water_exclusions("res://sites/%s/%s" % [site, manifest.water])   # nothing grows in the ponds
	var builder := TerrainBuilder.new()
	var counts: Array = await builder.scatter(terrain, dir, exclusions, 1798, texture_list)
	print("[scatter_vegetation] saved -> %s (%d instances)" % [dir, counts.reduce(func(a, b): return a + b, 0)])
	quit()
