# Headless check of the development loop: a report is captured (json, png, save, feed line), commands
# dropped into user://dev/commands.jsonl are executed (teleport, hot reload of a script, the layer
# scene and pack data) and answered in results.log.
#   godot --headless --path . res://tools/godot/devchannel_test.tscn
extends Node

var world: Node3D
var _failed := false


func _check(cond: bool, msg: String) -> void:
	if not cond and not _failed:
		_failed = true
		print("[dev] FAILED: ", msg)
		get_tree().quit(1)


func _ready() -> void:
	get_tree().create_timer(120.0).timeout.connect(func():
		print("[dev] FAILED: watchdog")
		get_tree().quit(2))
	Sites.select("palupera", false)
	GameState.reset()
	world = load("res://scenes/world/world.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	_check(DevChannel.enabled, "DevChannel disabled in a debug build")
	# --- report
	push_warning("devchannel_test: a warning the report should quote")
	var path := Reporter.capture("test note: the oak looks too small", world)
	_check(path != "" and FileAccess.file_exists(path), "report json missing")
	_check(DisplayServer.get_name() == "headless" or FileAccess.file_exists(path.replace(".json", ".png")), "report screenshot missing")
	var r: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(r.site == "palupera" and r.era == "era_2026" and r.position.size() == 3 and r.has("replay"), "report content")
	_check(SaveManager.has_save(str(r.save_slot)), "report save slot missing")
	_check(FileAccess.get_file_as_string(Reporter.FEED).contains("the oak looks too small"), "feed line missing")
	_check(str(r.errors).contains("a warning the report should quote"), "engine warning not captured: %s" % [r.errors])
	print("[dev] report ok: ", path.get_file())
	# --- commands through the file channel
	var cmdf := FileAccess.open(DevChannel.CMD, FileAccess.READ_WRITE if FileAccess.file_exists(DevChannel.CMD) else FileAccess.WRITE)
	cmdf.seek_end()
	var pid := OS.get_process_id()   # addressed to this test only, never to a game the player has open
	cmdf.store_line(JSON.stringify({"pid": pid, "teleport": [600, 320, 90]}))
	cmdf.store_line(JSON.stringify({"pid": pid, "reload": ["res://scripts/interaction/examinable.gd", "res://sites/palupera/scenes/era_2026.tscn", "res://sites/palupera/strings.csv", "res://assets/shaders/water.gdshader"]}))
	cmdf.close()
	await get_tree().create_timer(1.5).timeout
	await get_tree().create_timer(1.0).timeout
	_check(world.player.global_position.distance_to(Vector3(600, world.player.global_position.y, 320)) < 0.5, "teleport not applied: %s" % world.player.global_position)
	var results := FileAccess.get_file_as_string(DevChannel.RESULTS)
	_check(results.contains("examinable.gd: reloaded"), "script hot reload failed: " + results.right(600))
	_check(results.contains("era layer era_2026 re-instanced"), "layer scene reload failed")
	_check(results.contains("pack reloaded"), "pack data reload failed")
	_check(results.contains("water.gdshader: cache replaced"), "shader reload failed")
	_check(world.get_node("EraLayers").get_node_or_null("era_2026") != null and GameState.eras.size() == 1, "world state after reload")
	# the direct API too
	var out: Array = await DevChannel.execute({"note": "hello"})
	_check(out == ["note ok"], "execute() result")
	print("[dev] commands ok")
	Sites.select("palupera", false)
	if not _failed:
		print("[dev] PASSED")
	get_tree().quit()
