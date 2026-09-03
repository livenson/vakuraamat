# Headless check of Phase 3 hunting in the real 1798 scene: spawner populates on the right
# land cover, a forced take yields an era-local item, nothing crosses eras, isolation holds.
#   godot --headless --path . res://tools/godot/hunting_test.tscn
extends Node

var _failed := false


func _check(cond: bool, msg: String) -> void:
	if not cond and not _failed:
		_failed = true
		print("[hunt] FAILED: ", msg)
		get_tree().quit(1)


func _ready() -> void:
	get_tree().create_timer(120.0).timeout.connect(func():
		print("[hunt] FAILED: watchdog")
		get_tree().quit(2))
	GameState.reset()
	TranslationServer.set_locale("en")
	var world: Node3D = load("res://scenes/world/world.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	GameState.register_unlocked = true
	await GameState.switch_era("era_1798")
	var spawner: HuntingSpawner = world.get_node("EraLayers/era_1798").find_child("HuntingSpawner", true, false)
	_check(spawner != null, "no spawner in 1798")
	spawner.check_interval = 0.05
	for i in 60:
		await get_tree().physics_frame
	var animals := spawner.get_children().filter(func(c): return c is Animal)
	print("[hunt] animals alive after spawning: %d" % animals.size())
	_check(animals.size() >= 3, "spawner produced too few animals")
	var terrain: Terrain3D = world.terrain
	var ok_cover := 0
	for a in animals:
		var cls := Terrain3DUtil.get_base(terrain.data.get_control(a.global_position))
		if cls in a.species.spawn_classes:
			ok_cover += 1
	_check(ok_cover >= animals.size() * 0.7, "animals not on their land cover (%d/%d)" % [ok_cover, animals.size()])
	# forced take: stand next to it
	var a: Animal = animals[0]
	world.player.global_position = a.global_position + Vector3(0.8, 1.0, 0)
	seed(1)
	var before := Inventory.local_items("era_1798").size()
	for tries in 20:
		if Inventory.local_items("era_1798").size() > before or not is_instance_valid(a):
			break
		a.interact(world.player)
		await get_tree().physics_frame
	print("[hunt] bag: ", Inventory.local_items("era_1798"))
	_check(Inventory.local_items("era_1798").size() == before + 1, "hunt never succeeded next to the animal")
	await GameState.switch_era("era_2026")
	_check(Inventory.local_items("era_2026").is_empty(), "yield crossed eras")
	var spawner26 = world.get_node("EraLayers/era_2026").find_child("HuntingSpawner", true, false)
	_check(spawner26 == null, "hunting present in 2026")
	for f in ["animal_definition.gd", "hunting.gd", "animal.gd", "hunting_spawner.gd"]:
		var src := FileAccess.get_file_as_string("res://scripts/hunting/" + f)
		_check(not ("TimelineState" in src or "ConsequencePoint" in src or "ArtifactItem" in src), "isolation broken in " + f)
	if not _failed:
		print("[hunt] PASSED")
	get_tree().quit()
