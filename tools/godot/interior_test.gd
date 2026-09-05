# Headless check of enterable interiors on Kvissentali: doors attach to the real buildings, entering hides
# the exterior and generates floors, walls, a light and furniture, the player stands inside the footprint,
# leaving restores the exterior, and walking out through the door gap leaves too.
#   godot --headless --path . res://tools/godot/interior_test.tscn
extends Node

var _failed := false


func _check(cond: bool, msg: String) -> void:
	if not cond and not _failed:
		_failed = true
		print("[interior] FAILED: ", msg)
		get_tree().quit(1)


func _ready() -> void:
	get_tree().create_timer(150.0).timeout.connect(func():
		print("[interior] FAILED: watchdog")
		get_tree().quit(2))
	await get_tree().process_frame
	Sites.select("kvissentali", false)
	GameState.reset()
	var world: Node3D = load("res://scenes/world/world.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	var interiors: Interiors = world.get_node_or_null("Interiors")
	_check(interiors != null and Interiors.instance == interiors, "no Interiors node")
	var layer: Node = world.get_node("EraLayers").get_node_or_null(GameState.current_era)
	var doors := layer.find_children("Door", "BuildingDoor", true, false)
	_check(doors.size() > 50, "only %d doors attached" % doors.size())
	var door: BuildingDoor = null
	for d in doors:
		var b: FootprintBuilding = d.building
		if b.floors >= 2 and b.tunnus != "" and Ledger.tenants_of(b.tunnus).size() > 0:
			door = d
			break
	if door == null:
		door = doors[0]
	var b: FootprintBuilding = door.building
	_check(door.prompt() == tr("UI_PROMPT_ENTER") and door.label() != "", "door prompt/label before entering")
	await door.interact(world.player)
	await get_tree().process_frame
	_check(interiors.inside == b, "not inside after interact")
	var root: Node3D = b.get_node_or_null("Interior_%d" % b.building_id)
	_check(root != null and root.visible, "interior not generated")
	_check(root.find_children("*", "OmniLight3D", false, false).size() >= 1, "no light inside")
	_check(root.find_children("*", "MeshInstance3D", true, false).size() >= 6, "too few interior meshes")
	_check(root.find_children("*", "StaticBody3D", false, false).size() >= 3, "interior colliders missing")
	# rooms: a building over 60 m² is partitioned, every split has exactly one doorway, furniture keeps clear
	var area := Interiors._area(b.polygon)
	_check(area > 60.0, "test building too small for rooms: %.0f m²" % area)
	var splits: int = root.get_meta("splits", 0)
	var dws: Array = root.get_meta("doorways", [])
	_check(splits >= 2, "only %d partition walls for %.0f m²" % [splits, area])
	_check(dws.size() == splits, "doorways %d != partitions %d" % [dws.size(), splits])
	_check(root.find_children("Partition_*", "MeshInstance3D", false, false).size() >= splits, "partition meshes missing")
	var floor0: float = root.get_meta("floor0")
	for n in root.get_children():
		if n.has_meta("piece") and absf(n.position.y - floor0) < 0.01:
			for d in dws:
				_check(Vector2(n.position.x, n.position.z).distance_to(d) >= 1.0, "furniture in a doorway")
	var local := b.to_local(world.player.global_position)
	_check(Geometry2D.is_point_in_polygon(Vector2(local.x, local.z), b.polygon), "player not inside the footprint: %s" % local)
	_check(not b._mesh_node.visible and b._body_node.collision_layer == 0, "exterior still shown or solid")
	_check(door.prompt() == tr("UI_PROMPT_LEAVE"), "door prompt inside")
	await door.interact(world.player)
	await get_tree().process_frame
	_check(interiors.inside == null and b._mesh_node.visible and b._body_node.collision_layer == 1 and not root.visible, "exterior not restored")
	# in again, then walk far away: the manager notices and restores the exterior
	await door.interact(world.player)
	await get_tree().process_frame
	world.player.set_pose(b.global_position + Vector3(60, 5, 60), 0.0, 0.0)
	await get_tree().create_timer(0.3).timeout
	_check(interiors.inside == null and b._mesh_node.visible, "leaving by walking out was not detected")
	print("[interior] ok: %d doors, tested %s (%s, %d storeys)" % [doors.size(), b.address, b.kind, int(b.storeys().floors)])
	if not _failed:
		print("[interior] PASSED")
	get_tree().quit()
