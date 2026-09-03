# Headless play-through of the Phase 1 slice through the real world scene: picks up the
# artifacts, talks to every NPC, makes every choice, checks flags, journal, chapters,
# the ending and a save round-trip.
#   godot --headless --path . res://tools/godot/playthrough_test.tscn
extends Node

var world: Node3D
var lines: Array = []
var choices: Array = []


func _check(cond: bool, msg: String) -> void:
	if not cond:
		print("[play] FAILED: ", msg)
		get_tree().quit(1)
		await get_tree().process_frame


func _ready() -> void:
	get_tree().create_timer(150.0).timeout.connect(func():
		print("[play] FAILED: watchdog timeout")
		get_tree().quit(2))
	GameState.reset()
	TranslationServer.set_locale("en")
	Narrative.line.connect(func(t, sp, _tags): lines.append("%s: %s" % [sp, t]))
	Narrative.choices.connect(func(opts): choices = opts)
	world = load("res://scenes/world/world.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	await _run()


func _layer(era: String) -> Node:
	return world.get_node("EraLayers").get_node(era)


func _find(era: String, name: String) -> Node:
	var n := _layer(era).find_child(name, true, false)
	_check(n != null, "missing node %s in %s" % [name, era])
	return n


func _talk(era: String, npc_name: String) -> void:
	lines.clear()
	choices.clear()
	_find(era, npc_name).interact(world.player)
	await _settle()


func _choose_containing(fragment: String) -> void:
	for o in choices:
		if fragment in o.text:
			choices.clear()
			Narrative.choose(o.index)
			await _settle()
			return
	_check(false, "no choice containing '%s' in %s" % [fragment, choices.map(func(o): return o.text)])


func _choose_last() -> void:
	_check(not choices.is_empty(), "no choices to close with")
	var idx: int = choices[-1].index
	choices.clear()
	Narrative.choose(idx)
	await _settle()


func _settle() -> void:
	for i in 3:
		await get_tree().process_frame


func _switch(era: String) -> void:
	await GameState.switch_era(era)
	await _settle()


func _run() -> void:
	print("[play] era=%s chapter=%d" % [GameState.current_era, GameState.chapter])
	_check(GameState.current_era == "era_2026" and GameState.chapter == 0, "GameState.current_era == era_2026 and GameState.")
	# --- prologue: Leida, the rusted tool, the register
	await _talk("era_2026", "Leida")
	_check(TimelineState.has_flag("met_leida") and not choices.is_empty(), "Leida did not offer choices")
	await _choose_containing("go and look")
	_find("era_2026", "RustedTool").interact(world.player)
	_check(Inventory.has("rusted_tool"), "Inventory.has(rusted_tool)")
	_find("era_2026", "RegisterBook").interact(world.player)
	_check(GameState.register_unlocked and GameState.chapter == 1, "prologue did not commit")
	print("[play] prologue ok: chapter=%d" % GameState.chapter)
	# --- chapter 1: 1798
	await _switch("era_1798")
	_check(not Inventory.has("rusted_tool"), "era-local item crossed eras")
	_find("era_1798", "Ploughshare").interact(world.player)
	_find("era_1798", "ManorKey").interact(world.player)
	_check(Inventory.artifacts.has("ploughshare") and Inventory.artifacts.has("manor_key"), "Inventory.artifacts.has(ploughshare) and Invento")
	await _talk("era_1798", "Mart")
	await _choose_containing("I'll go")
	await _talk("era_1798", "WellStory")
	await _choose_containing("Help Mart")
	_check(TimelineState.has_flag("well_kept_open"), "CP3 not set")
	_check(Journal.entries.size() == 1, "ledger missing CP3")
	await _switch("era_1938")
	_check(GameState.chapter == 2, "chapter 1 did not end after visiting all eras; chapter=%d" % GameState.chapter)
	print("[play] chapter 1 ok; 1938 well ring visible=%s dip visible=%s" % [_find("era_1938", "WellKept").visible, _find("era_1938", "WellGone").visible])
	_check(_find("era_1938", "WellKept").visible and not _find("era_1938", "WellGone").visible, "_find(era_1938, WellKept).visible and not _fin")
	# --- chapter 2: 1938
	_check(_find("era_1938", "Chapter2").visible, "chapter 2 content hidden")
	await _talk("era_1938", "Juhan")
	await _choose_containing("Give Juhan")
	_check(TimelineState.has_flag("north_field_ploughed"), "CP2 not set")
	await _choose_last()
	await _talk("era_1938", "Aino")
	await _choose_containing("Give Aino")
	_check(TimelineState.has_flag("cellar_opened"), "CP4 not set")
	_check(_find("era_1938", "OrchardPlanted").visible, "saplings not shown")
	await _choose_last()
	_find("era_1938", "RegisterPage").interact(world.player)
	_find("era_1938", "AinoLetter").interact(world.player)
	await _talk("era_1938", "Villem")
	_check(not TimelineState.has_flag("family_recorded_1798"), "not TimelineState.has_flag(family_recorded_1798)")
	await _choose_last()
	print("[play] chapter after meeting all three: %d (commit expected)" % GameState.chapter)
	_check(GameState.chapter == 3, "chapter 2 did not commit")
	_check(TimelineState.is_committed("north_field_ploughed"), "commit did not snapshot")
	# --- back to 1798 with the page
	await _switch("era_1798")
	await _talk("era_1798", "Hans")
	await _choose_containing("Show Hans")
	_check(TimelineState.has_flag("family_recorded_1798"), "CP1 not set")
	await _choose_last()
	# --- 2026: witness + letter + sit
	await _switch("era_2026")
	_check(_find("era_2026", "StoneKept").visible and _find("era_2026", "FieldMeadow").visible and not _find("era_2026", "FieldForest").visible, "_find(era_2026, StoneKept).visible and _find(")
	_check(_find("era_2026", "OrchardKept").visible and _find("era_2026", "WellRing").visible, "_find(era_2026, OrchardKept).visible and _find")
	await _talk("era_2026", "Leida")
	await _choose_containing("Give Leida")
	_check(TimelineState.has_flag("letter_delivered"), "CP5 not set")
	await _choose_containing("Sit with")
	_check(TimelineState.has_flag("epilogue") and GameState.chapter == 4, "TimelineState.has_flag(epilogue) and GameState.c")
	_check(Journal.entries.size() == 5, "ledger has %d entries" % Journal.entries.size())
	print("[play] all 5 consequences set; ledger:")
	for e in Journal.entries:
		print("   - ", tr(e.text_key))
	# --- save round trip
	_check(SaveManager.save("playthrough"), "SaveManager.save(playthrough)")
	var flags_before := TimelineState.flags.duplicate()
	GameState.reset()
	var loaded: bool = await SaveManager.load_slot("playthrough")
	_check(loaded, "loaded")
	await _settle()
	_check(TimelineState.flags.size() == flags_before.size() and GameState.chapter == 4 and GameState.current_era == "era_2026", "save round-trip mismatch")
	print("[play] save/load ok. Sample lines:")
	for l in lines.slice(0, 4):
		print("   ", l)
	print("[play] PASSED")
	get_tree().quit()
