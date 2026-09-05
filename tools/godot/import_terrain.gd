# Vakuraamat terrain pipeline, step 2 of 2: engine files -> Terrain3D region data.
#
# Reads assets/terrain/<tile>/{terrain_meta.json, heightmap.r32, canopy.r32, ortho.jpg}
# produced by tools/pipeline/fetch_tile.py and writes:
#   assets/terrain/<tile>/data/terrain3d_00_00.res   (height + control + colour maps)
#   assets/terrain/<tile>/terrain_assets.tres         (ground textures; mesh assets kept)
# The work is done by scripts/worldgen/terrain_builder.gd, which the game also uses at runtime.
#
#   godot --headless --path . -s res://tools/godot/import_terrain.gd -- --site=palupera [--tile=<tile>] [--z-scale=1]
#
# World mapping (see terrain_meta.json): the tile's north-west corner sits at
# Godot (0, y, 0); +X is east, +Z is south, so north is -Z.
extends SceneTree


func _init() -> void:
	var args := _user_args()
	var site: String = args.get("site", "palupera")
	var site_meta: Dictionary = _site_manifest(site)
	var tile: String = args.get("tile", site_meta.get("terrain", {}).get("tile", site))
	var dir := "res://assets/terrain/%s" % tile
	var layout_text := FileAccess.get_file_as_string("res://sites/%s/layout.json" % site)
	var layout: Dictionary = JSON.parse_string(layout_text) if not layout_text.is_empty() else {}
	if not TerrainBuilder.has_inputs(dir):
		push_error("missing %s/terrain_meta.json - run tools/pipeline/fetch_tile.py first" % dir)
		quit(1)
		return
	print("[import_terrain] tile=%s site=%s" % [tile, site])
	# Terrain3D only creates its data object if the data directory exists.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir + "/data"))
	var terrain := Terrain3D.new()
	terrain.name = "Terrain3D"
	terrain.data_directory = dir + "/data"
	get_root().add_child(terrain)
	# Nodes added from SceneTree._init() only enter the tree on the first frame;
	# Terrain3D creates its data/material/assets objects on ENTER_TREE.
	await process_frame
	var builder := TerrainBuilder.new()
	var ok: bool = await builder.import(terrain, dir, layout, float(args.get("z-scale", -1.0)))
	if not ok:
		quit(1)
		return
	var size := int(TerrainBuilder.read_meta(dir).size_px)
	var c := size / 2
	for p in [Vector3(c, 0, c), Vector3(1, 0, 1), Vector3(size - 1, 0, size - 1)]:
		print("[import_terrain] height at (%d,%d) = %.3f" % [p.x, p.z, terrain.data.get_height(p)])
	print("[import_terrain] regions=%s done -> %s/data" % [terrain.data.region_locations, dir])
	quit()


func _site_manifest(site: String) -> Dictionary:
	var text := FileAccess.get_file_as_string("res://sites/%s/site.json" % site)
	var parsed = JSON.parse_string(text) if not text.is_empty() else null
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _user_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1]
	return out
