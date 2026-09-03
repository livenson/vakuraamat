# Headless check of Phase 2 farming in the real 1938 scene: seed bin -> sow -> clock -> harvest,
# and that farming code never references the timeline systems.
#   godot --headless --path . res://tools/godot/farming_test.tscn
extends Node


var _failed := false


func _check(cond: bool, msg: String) -> void:
	if not cond and not _failed:
		_failed = true
		print("[farm] FAILED: ", msg)
		get_tree().quit(1)


func _ready() -> void:
	get_tree().create_timer(120.0).timeout.connect(func():
		print("[farm] FAILED: watchdog")
		get_tree().quit(2))
	GameState.reset()
	TranslationServer.set_locale("en")
	var world: Node3D = load("res://scenes/world/world.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	GameState.register_unlocked = true
	GameState.chapter = 2
	await GameState.switch_era("era_1938")
	for i in 3:
		await get_tree().process_frame
	var layer: Node = world.get_node("EraLayers/era_1938")
	var bin: Node = layer.find_child("SeedBin", true, false)
	var plot: FarmPlot = layer.find_child("Plot0", true, false)
	_check(bin != null and plot != null, "farm nodes missing")
	_check(plot.state() == "EMPTY", "plot not empty at start")
	bin.interact(world.player)
	_check(Inventory.local_items("era_1938").size() == 1, "seed bin gave nothing")
	plot.interact(world.player)
	_check(plot.state() == "GROWING", "plot did not plant; state=%s" % plot.state())
	_check(Inventory.local_items("era_1938").is_empty(), "seed not consumed")
	Farming.game_hours += 2.0
	_check(plot.state() == "GROWING" and Farming.progress(plot._key()) > 0.2, "growth not progressing")
	Farming.game_hours += 10.0
	_check(plot.state() == "READY", "plot not ready after growth time")
	plot.interact(world.player)
	var bag := Inventory.local_items("era_1938")
	print("[farm] harvested bag: ", bag)
	_check(bag.size() >= 3 and plot.state() == "EMPTY", "harvest failed")
	# era-local: nothing crosses eras
	await GameState.switch_era("era_2026")
	_check(Inventory.local_items("era_2026").is_empty(), "harvest crossed eras")
	# save round trip keeps plot state
	await GameState.switch_era("era_1938")
	bin.interact(world.player)
	plot.interact(world.player)
	_check(plot.state() == "GROWING", "second sowing failed")
	_check(SaveManager.save("farm_test"), "save failed")
	Farming.plots = {}
	var ok: bool = await SaveManager.load_slot("farm_test")
	_check(ok and plot.state() == "GROWING", "plot state not restored")
	# isolation check: no timeline references in scripts/farming
	for f in ["crop_definition.gd", "farming.gd", "farm_plot.gd", "seed_bin.gd"]:
		var src := FileAccess.get_file_as_string("res://scripts/farming/" + f)
		_check(not ("TimelineState" in src or "ConsequencePoint" in src or "ArtifactItem" in src), "isolation broken in " + f)
	if not _failed:
		print("[farm] PASSED")
	get_tree().quit()
