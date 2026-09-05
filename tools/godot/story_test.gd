# Generic play-through of a composed (block-based) pack, driven only by the pack's own data:
# picks up every artifact, talks to every NPC, triggers every consequence point by trying the
# dialogue options (or the story point), checks the flags, chapters and the epilogue.
#   godot --headless --path . res://tools/godot/story_test.tscn -- --site=kvissentali
extends Node

var world: Node3D
var choices: Array = []
var lines: Array = []
var _failed := false
var site := "kvissentali"


func _check(cond: bool, msg: String) -> void:
	if not cond and not _failed:
		_failed = true
		print("[story] FAILED: ", msg)
		get_tree().quit(1)


func _ready() -> void:
	get_tree().create_timer(240.0).timeout.connect(func():
		print("[story] FAILED: watchdog timeout")
		get_tree().quit(2))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--site="):
			site = a.trim_prefix("--site=")
	await get_tree().process_frame
	_check(Sites.available.has(site), "no such pack: " + site)
	Sites.select(site, false)
	GameState.reset()
	TranslationServer.set_locale("en")
	Narrative.line.connect(func(t, sp, _tags): lines.append("%s: %s" % [sp, t]))
	Narrative.choices.connect(func(opts): choices = opts)
	world = load("res://scenes/world/world.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	await _run()


func _settle() -> void:
	for i in 3:
		await get_tree().process_frame


func _layer(era: String) -> Node:
	return world.get_node("EraLayers").get_node_or_null(era)


func _switch(era: String) -> void:
	await GameState.switch_era(era)
	await _settle()


func _talk(node: Node) -> void:
	lines.clear()
	choices.clear()
	node.interact(world.player)
	await _settle()


func _close() -> void:
	# leave the conversation: choose options until none are left (the last generic one ends it)
	for i in 12:
		if choices.is_empty():
			return
		var idx: int = choices[-1].index
		choices.clear()
		Narrative.choose(idx)
		await _settle()


func _npc_by_id(era: String, npc_id: String) -> Node:
	for n in _layer(era).find_children("*", "NPC", true, false):
		if n.npc_id == npc_id:
			return n
	return null


## Try the dialogue options until the flag flips (delivery blocks add a give option to the target NPC).
## Options naming the item are tried first, so two deliveries to one NPC do not get mixed up.
func _deliver(era: String, npc_id: String, flag: String, item_name: String = "") -> void:
	var npc := _npc_by_id(era, npc_id)
	_check(npc != null, "delivery NPC %s missing in %s" % [npc_id, era])
	await _talk(npc)
	var tried := {}
	for round in 10:
		if TimelineState.has_flag(flag) or choices.is_empty():
			break
		var pick := -1
		for o in choices:
			if item_name != "" and item_name in o.text.to_lower() and not tried.has(o.text):
				pick = o.index
				tried[o.text] = true
				break
		if pick < 0:
			for o in choices:
				if not tried.has(o.text):
					pick = o.index
					tried[o.text] = true
					break
		if pick < 0:
			break
		choices.clear()
		Narrative.choose(pick)
		await _settle()
		if choices.is_empty() and not TimelineState.has_flag(flag):
			await _talk(npc)   # the option ended the talk; start again for the next one
	await _close()


func _run() -> void:
	var eras := GameState.eras_in_order()
	var start: Dictionary = Sites.get_value("start", {})
	_check(GameState.current_era == str(start.era) and GameState.chapter == 0, "start era/chapter")
	print("[story] %s: %d eras, blocks %s" % [site, eras.size(), Sites.get_value("story", {}).get("blocks", [])])
	# prologue: meet the local, take the register
	var greeter := _layer(GameState.current_era).find_children("*", "NPC", true, false)
	_check(not greeter.is_empty(), "no NPC in the start era")
	await _talk(greeter[0])
	_check(not lines.is_empty() and not choices.is_empty(), "greeter said nothing / offered nothing")
	await _close()
	var book: Node = _layer(GameState.current_era).find_child("RegisterBook", true, false)
	_check(book != null, "no register in the start era")
	book.interact(world.player)
	_check(GameState.register_unlocked and GameState.chapter == 1, "prologue did not commit")
	# chapter 1: visit every era, picking up every pickup and greeting every NPC on the way
	for era in eras:
		await _switch(era.id)
		for p in _layer(era.id).find_children("*", "Pickup", true, false):
			if p.visible:
				p.interact(world.player)
		for n in _layer(era.id).find_children("*", "NPC", true, false):
			await _talk(n)
			_check(not lines.is_empty(), "%s in %s said nothing" % [n.name, era.id])
			await _close()
	_check(GameState.chapter == 2, "chapter 1 did not end after visiting every era (chapter %d)" % GameState.chapter)
	var artifacts := Inventory.artifacts.duplicate()
	print("[story] artifacts found: %s" % [artifacts])
	# chapter 2+: every consequence point, in era order of their trigger
	var cps := GameState.consequence_points.values()
	cps.sort_custom(func(a, b): return GameState.era(a.trigger_era).order < GameState.era(b.trigger_era).order)
	for cp in cps:
		await _switch(cp.trigger_era)
		var artifact: ArtifactItem = null
		for it in GameState.items.values():
			if it is ArtifactItem and it.linked_consequence_point_id == cp.id:
				artifact = it
		var coop: bool = cp.flag_name in Sites.get_value("story", {}).get("coop_flags", [])
		if TimelineState.has_flag(cp.flag_name):
			print("[story] %s already set while talking to a shared NPC" % cp.id)
			continue
		var item_name := tr(artifact.display_name_key).to_lower() if artifact else ""
		if artifact and coop:
			_check(Inventory.has(artifact.id), "artifact %s for %s was never picked up" % [artifact.id, cp.id])
			Narrative.force_visiting = false
			await _deliver(cp.trigger_era, artifact.valid_delivery_target, cp.flag_name, item_name)
			_check(not TimelineState.has_flag(cp.flag_name), "co-op consequence %s could be done without a visitor" % cp.id)
			Narrative.force_visiting = true
			await _deliver(cp.trigger_era, artifact.valid_delivery_target, cp.flag_name, item_name)
			Narrative.force_visiting = false
		elif artifact:
			_check(Inventory.has(artifact.id), "artifact %s for %s was never picked up" % [artifact.id, cp.id])
			await _deliver(cp.trigger_era, artifact.valid_delivery_target, cp.flag_name, item_name)
		else:
			var sp := _layer(cp.trigger_era).find_children("*", "StoryPoint", true, false)
			_check(not sp.is_empty(), "choice consequence %s has no story point in %s" % [cp.id, cp.trigger_era])
			await _talk(sp[0])
			_check(not choices.is_empty(), "story point offered no choice")
			var first: int = choices[0].index
			choices.clear()
			Narrative.choose(first)
			await _settle()
		_check(TimelineState.has_flag(cp.flag_name), "consequence %s did not set %s" % [cp.id, cp.flag_name])
		print("[story] %s -> %s (chapter %d)" % [cp.id, cp.flag_name, GameState.chapter])
	_check(GameState.chapter >= 3, "chapter 2 never ended (chapter %d)" % GameState.chapter)
	# visible consequences exist in the later eras
	for era in eras:
		await _switch(era.id)
		for c in _layer(era.id).find_children("*", "Conditional", true, false):
			if c.flag != "":
				_check(c.visible == (TimelineState.has_flag(c.flag) == c.visible_when), "conditional %s wrong in %s" % [c.name, era.id])
	# epilogue with the newest era's local
	await _switch(eras[-1].id)
	var last := _layer(eras[-1].id).find_children("*", "NPC", true, false)
	await _talk(last[0])
	var sat := false
	for o in choices:
		if "finish" in o.text.to_lower() or "lõpuni" in o.text.to_lower():
			Narrative.choose(o.index)
			await _settle()
			sat = true
	_check(sat and TimelineState.has_flag(str(Sites.get_value("ending", {}).get("trigger_flag", "epilogue"))), "epilogue option missing or flag not set")
	_check(Journal.entries.size() == cps.size(), "ledger has %d entries for %d consequences" % [Journal.entries.size(), cps.size()])
	print("[story] all %d consequences set; ledger:" % cps.size())
	for e in Journal.entries:
		print("   - ", tr(e.text_key))
	Sites.select("palupera", false)
	if not _failed:
		print("[story] PASSED")
	get_tree().quit()
