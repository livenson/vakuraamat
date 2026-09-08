# Headless smoke test: autoloads present, the pack's single layer loads, the cadastre and the
# companies read from the pack's files, translations resolve, a save round-trips the place you
# were standing in.
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
	for n in ["EventBus", "Sites", "Locator", "Reporter", "DevChannel", "SaveManager", "GameState", "WindowMode"]:
		_check(root.has_node(n), "missing autoload " + n)
	_check(GameState.eras.size() == 1 and GameState.eras.has("era_2026"), "a pack has exactly one present-day layer: %s" % [GameState.eras.keys()])
	GameState.reset()
	var units := Parcels.units()
	_check(units.size() > 10, "the pack's parcels.json gave %d units" % units.size())
	_check(not Parcels.by_tunnus(str(units[0].tunnus)).is_empty(), "by_tunnus does not find the pack's own first unit")
	var with_companies := units.filter(func(u): return Tenants.of(Sites.active, str(u.get("tunnus", ""))).size() > 0)
	_check(with_companies.size() > 0, "no unit of the pack has a registered company")
	GameState.current_era = "era_2026"
	_check(SaveManager.save("boot_test"), "save failed")
	var summary := SaveManager.summary("boot_test")
	_check(str(summary.get("site", "")) == Sites.active and str(summary.get("saved_at", "")) != "", "save summary: %s" % summary)
	GameState.reset()
	var loaded: bool = await SaveManager.load_slot("boot_test")
	_check(loaded, "save round-trip failed")
	print("[boot] save/load ok (%s)" % ProjectSettings.globalize_path(SaveManager.slot_path("boot_test")))
	TranslationServer.set_locale("en")
	_check(tr("ERA_2026_NAME") != "ERA_2026_NAME" and tr("UI_BOOK_TITLE") != "UI_BOOK_TITLE", "translations missing")
	var et: Translation = TranslationServer.get_translation_object("et")
	print("[boot] en: ", tr("ERA_2026_NAME"), " | et: ", et.get_message("ERA_2026_NAME") if et else "n/a")
	if not _failed:
		print("[boot] PASSED")
	get_tree().quit()
