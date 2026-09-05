# Headless smoke test: autoloads present, the pack's single layer loads, the offline ledger starts
# with the pack's parcels, translations resolve, a save round-trips.
#   godot --headless --path . res://tools/godot/boot_test.tscn
extends Node

var _failed := false


func _check(cond: bool, msg: String) -> void:
	if not cond and not _failed:
		_failed = true
		print("[boot] FAILED: ", msg)
		get_tree().quit(1)


func _ready() -> void:
	await get_tree().process_frame
	var root := get_tree().root
	for n in ["EventBus", "Sites", "Locator", "SpacetimeDB", "Ledger", "Reporter", "DevChannel", "SaveManager", "GameState", "WindowMode"]:
		_check(root.has_node(n), "missing autoload " + n)
	_check(GameState.eras.size() == 1 and GameState.eras.has("era_2026"), "a pack has exactly one present-day layer: %s" % [GameState.eras.keys()])
	GameState.reset()
	_check(Ledger.local() != null and Ledger.parcels().size() > 10, "offline ledger did not load the pack's parcels")
	_check(Ledger.cash() > 0 and Ledger.month() == 0, "fresh ledger state")
	GameState.current_era = "era_2026"
	await Ledger.debug_grant(777)
	var cash := Ledger.cash()
	_check(SaveManager.save("boot_test"), "save failed")
	GameState.reset()
	_check(Ledger.cash() != cash, "reset did not clear the ledger")
	var loaded: bool = await SaveManager.load_slot("boot_test")
	_check(loaded and Ledger.cash() == cash, "save round-trip failed: %d vs %d" % [Ledger.cash(), cash])
	print("[boot] save/load ok (%s)" % ProjectSettings.globalize_path(SaveManager.slot_path("boot_test")))
	TranslationServer.set_locale("en")
	_check(tr("ERA_2026_NAME") != "ERA_2026_NAME" and tr("UI_LEDGER_TITLE") != "UI_LEDGER_TITLE", "translations missing")
	var et: Translation = TranslationServer.get_translation_object("et")
	print("[boot] en: ", tr("ERA_2026_NAME"), " | et: ", et.get_message("ERA_2026_NAME") if et else "n/a")
	if not _failed:
		print("[boot] PASSED")
	get_tree().quit()
