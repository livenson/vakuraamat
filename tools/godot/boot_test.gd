# Headless smoke test: autoloads present, data loaded, a story starts, save round-trips.
#   godot --headless --path . res://tools/godot/boot_test.tscn
extends Node

func _ready() -> void:
	await get_tree().process_frame
	var root := get_tree().root
	for n in ["EventBus", "TimelineState", "SaveManager", "Inventory", "Journal", "Narrative", "GameState"]:
		assert(root.has_node(n), "missing autoload " + n)
	print("[boot] autoloads ok; eras=%d cps=%d items=%d" % [GameState.eras.size(), GameState.consequence_points.size(), GameState.items.size()])
	GameState.current_era = "era_2026"
	Inventory.add("aino_letter")
	Inventory.add("rusted_tool")
	assert(Inventory.has("aino_letter") and Inventory.has("rusted_tool"))
	assert(GameState.deliver_artifact("aino_letter", "npc_leida"))
	assert(TimelineState.has_flag("letter_delivered") and not Inventory.has("aino_letter"))
	assert(Journal.entries.size() == 1, "journal entry missing")
	print("[boot] consequence + journal ok: ", tr(Journal.entries[0].text_key).substr(0, 40))
	var lines := []
	Narrative.line.connect(func(t, _s, _tags): lines.append(t))
	var started: bool = await Narrative.start("leida")
	assert(started, "story start failed")
	print("[boot] ink lines: ", lines)
	assert(SaveManager.save("boot_test"))
	TimelineState.flags.clear()
	Journal.entries.clear()
	var loaded: bool = await SaveManager.load_slot("boot_test")
	assert(loaded)
	assert(TimelineState.has_flag("letter_delivered") and Journal.entries.size() == 1, "save round-trip failed")
	print("[boot] save/load ok (%s)" % ProjectSettings.globalize_path(SaveManager.slot_path("boot_test")))
	TranslationServer.set_locale("en")
	print("[boot] en: ", tr("ERA_1938_NAME"), " | et: ", TranslationServer.get_translation_object("et").get_message("ERA_1938_NAME") if TranslationServer.get_translation_object("et") else "n/a")
	get_tree().quit()
