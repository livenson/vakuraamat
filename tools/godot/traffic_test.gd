# Headless check of ambient traffic and the player bicycle in the Palupera 2026 layer: the road graph
# loads, agents spawn on roads near the player and move, the bicycle mounts and dismounts.
#   godot --headless --path . res://tools/godot/traffic_test.tscn
extends Node

var world: Node3D
var _failed := false


func _check(cond: bool, msg: String) -> void:
	if not cond and not _failed:
		_failed = true
		print("[traffic] FAILED: ", msg)
		get_tree().quit(1)


func _ready() -> void:
	get_tree().create_timer(120.0).timeout.connect(func():
		print("[traffic] FAILED: watchdog")
		get_tree().quit(2))
	Sites.select("palupera", false)
	GameState.reset()
	world = load("res://scenes/world/world.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	GameState.register_unlocked = true
	var layer: Node = world.get_node("EraLayers/era_2026")
	var traffic: TrafficSystem = layer.find_child("Traffic", true, false)
	_check(traffic != null, "no Traffic node in era_2026")
	_check(traffic.graph != null and traffic.graph.edges.size() > 10, "road graph empty (%d edges)" % (traffic.graph.edges.size() if traffic.graph else 0))
	# stand by the village road so there is road within spawn range
	world.player.set_pose(Vector3(430, 200, 330), 0.0, 0.0)
	world._snap(world.player, 1.0)
	await get_tree().create_timer(4.0).timeout
	_check(traffic.agents.size() > 0, "no agents spawned (target uses %.0f time factor)" % traffic.time_factor())
	var before := {}
	for ag in traffic.agents:
		before[ag] = ag.global_position
	await get_tree().create_timer(2.0).timeout
	var moved := 0
	for ag in before:
		if is_instance_valid(ag) and ag.global_position.distance_to(before[ag]) > 0.5:
			moved += 1
	if moved == 0 and not traffic.agents.is_empty():
		var a: TrafficAgent = traffic.agents[0]
		print("[traffic] first agent: kind %s speed %.1f now %.2f s %.1f/%.1f edge %s gap %.1f pos %s" % [a.kind, a.speed, a._speed_now, a.s, a.edge.length, a.edge.kind, a.gap_ahead(traffic.agents), a.global_position])
	_check(moved > 0, "no agent moved in 2 s (%d agents)" % before.size())
	var kinds := {}
	for ag in traffic.agents:
		kinds[ag.kind] = kinds.get(ag.kind, 0) + 1
	print("[traffic] %d agents after 6 s: %s" % [traffic.agents.size(), kinds])
	for ag in traffic.agents:
		var h: float = world.terrain.data.get_height(ag.global_position)
		_check(absf(ag.global_position.y - h) < 1.5, "agent floating or buried: y %.1f ground %.1f" % [ag.global_position.y, h])
	# bicycle
	var bike: Bicycle = layer.find_child("Bicycle", true, false)
	_check(bike != null, "no Bicycle in era_2026")
	bike.interact(world.player)
	_check(world.player.riding == bike and not bike.visible, "mount failed")
	_check(world.player.current_speed() > 5.0, "ride speed not applied")
	world.player.dismount()
	_check(world.player.riding == null and bike.visible, "dismount failed")
	if not _failed:
		print("[traffic] PASSED")
	get_tree().quit()
