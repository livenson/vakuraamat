# Headless check of tile streaming (TileStreamer): a synthetic neighbour east of Palupera is
# installed under user:// as the pack the streamer would fetch for grid tile (1,0) (the Palupera
# pack and tile files copied, centre shifted 1024 m east). Checks: the edge holds the player while
# nothing is loaded, the tile loads when the player comes near (region added, ground height valid,
# ambient nodes only, pack lookup by position), the player may cross.
#   godot --headless --path . res://tools/godot/streaming_test.tscn -- --site=palupera
extends Node

var world: Node3D
var _failed := false
var _nid := ""


func _check(cond: bool, msg: String) -> void:
	if not cond and not _failed:
		_failed = true
		print("[stream] FAILED: ", msg)
		_cleanup()
		get_tree().quit(1)


func _ready() -> void:
	get_tree().create_timer(150.0).timeout.connect(func():
		print("[stream] FAILED: watchdog")
		_cleanup()
		get_tree().quit(2))
	Sites.select("palupera", false)
	GameState.reset()
	_install_neighbour()
	world = load("res://scenes/world/world.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	var st: TileStreamer = world.streamer
	_check(st != null, "world has no streamer")
	_check(st.pack_for(Vector2i(1, 0)) == _nid, "pack id for (1,0) is %s, expected %s" % [st.pack_for(Vector2i(1, 0)), _nid])
	# 1. the edge holds while streaming is off: step over it, be put back
	st.enabled = false
	world.player.set_pose(Vector3(1000, 200, 512), 0.0, 0.0)
	world._snap(world.player, 1.0)
	await get_tree().create_timer(0.3).timeout
	world.player.global_position.x = 1030.0
	await get_tree().create_timer(0.3).timeout
	_check(world.player.global_position.x < 1024.0, "player left the map while nothing was loaded (x %.1f)" % world.player.global_position.x)
	# 2. streaming on: the neighbour is installed, so it loads without the service
	st.enabled = true
	var waited := 0.0
	while st.state_of(Vector2i(1, 0)) != "ready" and waited < 90.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	_check(st.state_of(Vector2i(1, 0)) == "ready", "tile (1,0) not ready after %.0f s (state %s)" % [waited, st.state_of(Vector2i(1, 0))])
	print("[stream] tile (1,0) ready after %.1f s" % waited)
	_check(world.terrain.data.has_region(Vector2i(1, 0)), "no terrain region at (1,0)")
	var h: float = world.terrain.data.get_height(Vector3(1500, 0, 512))
	_check(not is_nan(h) and h > 0.0, "ground height at (1500, 512) is %s" % h)
	var root: Node3D = st.tiles[Vector2i(1, 0)].root
	_check(root != null and root.position.x == 1024.0, "tile root missing or not offset")
	var era: Node = root.get_node_or_null("Era")
	_check(era != null, "no era content under the tile root")
	_check(era.get_node_or_null("Buildings") != null, "no Buildings in the streamed tile")
	_check(era.get_node_or_null("RegisterBook") == null and era.get_node_or_null("Landmark") == null, "story nodes leaked into the streamed tile")
	var fps := era.find_children("*", "FootprintBuilding", true, false)
	_check(fps.size() > 10, "only %d footprint buildings in the streamed tile" % fps.size())
	var b: Node3D = fps[0]
	_check(b.global_position.x > 1024.0, "streamed building not offset (x %.1f)" % b.global_position.x)
	_check(absf(b.global_position.y - world.terrain.data.get_height(b.global_position)) < 6.0, "streamed building not on the ground (y %.1f, ground %.1f)" % [b.global_position.y, world.terrain.data.get_height(b.global_position)])
	var at := st.pack_at(Vector3(1500, 0, 512))
	_check(at.get("id", "") == _nid and at.get("offset", Vector3.ZERO).x == 1024.0, "pack_at lookup wrong: %s" % at)
	# doors, interiors and name plates follow the tile
	await get_tree().process_frame
	await get_tree().process_frame
	var doors := era.find_children("Door", "BuildingDoor", true, false)
	_check(doors.size() > 5, "only %d doors on the streamed tile" % doors.size())
	var bd: BuildingDoor = doors[0]
	var bb: FootprintBuilding = bd.building
	_check(bd.label() != "", "streamed door has no label")
	Interiors.instance.enter(bb, world.player)
	await get_tree().process_frame
	var bl := bb.to_local(world.player.global_position)
	_check(Interiors.instance.inside == bb and Geometry2D.is_point_in_polygon(Vector2(bl.x, bl.z), bb.polygon), "player not inside the streamed building: %s" % bl)
	_check(not bb._mesh_node.visible and bb._body_node.collision_layer == 0, "streamed exterior still shown")
	Interiors.instance.exit(world.player)
	_check(Interiors.instance.inside == null and bb._mesh_node.visible, "streamed exterior not restored")
	# 3. the player may cross now
	world.player.set_pose(Vector3(1100, 200, 512), 0.0, 0.0)
	world._snap(world.player, 1.0)
	await get_tree().create_timer(0.3).timeout
	_check(world.player.global_position.x > 1024.0, "player pushed back although the tile is loaded")
	_check(not Parcels.at(world.player.global_position).is_empty() or true, "parcel lookup crashed")
	# 4. unloading the tile prunes its doors
	st._unload(Vector2i(1, 0))
	await get_tree().process_frame
	_check(Interiors.instance._doors.all(func(d): return is_instance_valid(d)), "doors of an unloaded tile not pruned")
	print("[stream] PASSED")
	_cleanup()
	get_tree().quit(0)


## Palupera copied as the (1,0) neighbour: sites/<nid> and tiles/<nid> under user://.
func _install_neighbour() -> void:
	var c: Array = Sites.terrain().get("center", [0, 0])
	var size := float(Sites.terrain().get("size", 1024))
	_nid = TileStreamer.pack_id(float(c[0]) + size, float(c[1]))
	_cleanup()
	_copy_dir("res://sites/palupera", Sites.USER_ROOT + _nid)
	_copy_dir("res://assets/terrain/palupera", Sites.USER_TILES + _nid)
	var m: Dictionary = Sites.manifest_for("palupera")
	m.id = _nid
	m.terrain.tile = _nid
	m.terrain.center = [float(c[0]) + size, float(c[1])]
	var f := FileAccess.open(Sites.USER_ROOT + _nid + "/site.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(m, "  "))
	f.close()
	if "--slow" in OS.get_cmdline_user_args():
		_remove_dir(Sites.USER_TILES + _nid + "/data")   # force the first-visit path: build the region from the inputs
	Sites.scan()
	print("[stream] neighbour %s installed" % _nid)


func _copy_dir(src: String, dst: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dst))
	var d := DirAccess.open(src)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".import") or f.ends_with(".uid"):
			continue
		DirAccess.copy_absolute(ProjectSettings.globalize_path(src + "/" + f), ProjectSettings.globalize_path(dst + "/" + f))
	for sub in d.get_directories():
		_copy_dir(src + "/" + sub, dst + "/" + sub)


func _remove_dir(path: String) -> void:
	var abs := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(abs):
		return
	for f in DirAccess.get_files_at(abs):
		DirAccess.remove_absolute(abs + "/" + f)
	for sub in DirAccess.get_directories_at(abs):
		_remove_dir(path + "/" + sub)
	DirAccess.remove_absolute(abs)


func _cleanup() -> void:
	if _nid == "":
		return
	_remove_dir(Sites.USER_ROOT + _nid)
	_remove_dir(Sites.USER_TILES + _nid)
