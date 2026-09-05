# Headless check of shared worlds: starts tools/world_service.py on a spare port, publishes the
# active site, fetches the descriptor, posts a visitor's delivery and pulls it back as an applied
# consequence. Needs python3 on the PATH (the pipeline needs it anyway).
#   godot --headless --path . res://tools/godot/friends_test.tscn
extends Node

const PORT := 8799
var _failed := false
var _pid := -1


func _check(cond: bool, msg: String) -> void:
	if not cond and not _failed:
		_failed = true
		print("[friends] FAILED: ", msg)
		_stop()
		get_tree().quit(1)


func _stop() -> void:
	if _pid > 0:
		OS.kill(_pid)
		_pid = -1


func _ready() -> void:
	await get_tree().process_frame
	var store := ProjectSettings.globalize_path("user://cache/friends_test_store")
	_pid = OS.create_process("python3", [ProjectSettings.globalize_path("res://tools/world_service.py"), "--port", str(PORT), "--store", store])
	_check(_pid > 0, "could not start python3 tools/world_service.py")
	var cfg := ConfigFile.new()
	cfg.load(Friends.SETTINGS)
	var old_url = cfg.get_value("service", "worlds_url", null)
	var old_code = cfg.get_value("worlds", Sites.active, null)
	cfg.set_value("service", "worlds_url", "http://127.0.0.1:%d" % PORT)
	cfg.set_value("player", "name", "Tester")
	cfg.save(Friends.SETTINGS)
	var up := false
	for i in 40:
		await get_tree().create_timer(0.25).timeout
		if await Friends.alive():
			up = true
			break
	_check(up, "world service did not come up")
	GameState.reset()
	GameState.current_era = "era_2026"
	TimelineState.set_flag("well_kept_open", true)
	TimelineState.commit()
	var pub: Dictionary = await Friends.publish()
	_check(pub.ok and pub.code.length() == 6, "publish failed: %s" % pub.get("error", ""))
	var d := await Friends.fetch(pub.code)
	_check(d.get("site_id") == Sites.active and d.get("flags", {}).has("well_kept_open") and not bool(d.get("generated", true)), "descriptor wrong: %s" % [d])
	print("[friends] published %s -> %s, flags %s" % [Sites.active, pub.code, d.flags.keys()])
	# a visitor delivers into this world
	Friends.visiting_code = pub.code
	var cp := GameState.consequence_for_flag("north_field_ploughed")
	Friends._on_consequence(cp.id)
	await get_tree().create_timer(0.6).timeout
	Friends.visiting_code = ""
	# the owner pulls it: the flag arrives as a consequence with a ledger line
	TimelineState.set_flag("north_field_ploughed", false)
	Journal.entries.clear()
	var applied: int = await Friends.pull_deliveries()
	_check(applied == 1 and TimelineState.has_flag("north_field_ploughed") and TimelineState.is_committed("north_field_ploughed"), "delivery not applied (%d)" % applied)
	_check(Journal.entries.size() == 1, "ledger did not record the friend's deed")
	var again: int = await Friends.pull_deliveries()
	_check(again == 0, "delivery applied twice")
	print("[friends] delivery pulled and applied: ", tr(Journal.entries[0].text_key))
	# restore settings
	cfg.load(Friends.SETTINGS)
	if old_url == null:
		cfg.erase_section_key("service", "worlds_url")
	else:
		cfg.set_value("service", "worlds_url", old_url)
	if old_code == null:
		cfg.erase_section_key("worlds", Sites.active)
	else:
		cfg.set_value("worlds", Sites.active, old_code)
	cfg.save(Friends.SETTINGS)
	_stop()
	if not _failed:
		print("[friends] PASSED")
	get_tree().quit()
