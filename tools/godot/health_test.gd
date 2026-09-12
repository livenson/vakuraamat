# Every company the pipeline puts on watch or in distress says why, in every interface language: the verdict
# alone (a yellow plot, "watch" on the register sheet) left the player guessing. Checked on every
# shipped pack's tenants.json, with the two cases a playtest asked about pinned.
#   godot --headless --path . res://tools/godot/health_test.tscn
extends Node

var _failed := false


func _check(cond: bool, msg: String) -> void:
	if not cond and not _failed:
		_failed = true
		print("[health] FAILED: ", msg)
		get_tree().quit(1)


func _ready() -> void:
	var flagged := 0
	for site in ["kvissentali", "palupera", "pirita"]:
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://sites/%s/tenants.json" % site))
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		for t in parsed.get("tenants", []):
			if not str(t.get("health", "")) in ["watch", "distressed"]:
				continue
			flagged += 1
			for loc in ["en", "et", "lv"]:
				TranslationServer.set_locale(loc)
				var why := Tenants.health_reason(t)
				_check(why != "" and not why.begins_with("HEALTH_"), "%s (%s): no reason in %s" % [t.name, site, loc])
				_check(Tenants.facts(t).contains(": " + why), "%s: the facts line does not carry the reason" % t.name)
	TranslationServer.set_locale("en")
	var elrerand := {"health": "watch", "report_overdue": true}
	_check(Tenants.health_reason(elrerand) == "annual report overdue", "report overdue reads '%s'" % Tenants.health_reason(elrerand))
	var falling := {"health": "watch", "report_overdue": false, "quarters": [[2023, 1, 30000, 4], [2023, 2, 30000, 3], [2023, 3, 30000, 3], [2023, 4, 30000, 2],
		[2024, 1, 10000, 2], [2024, 2, 5000, null], [2024, 3, 5000, null], [2024, 4, 0, null]]}
	var why := Tenants.health_reason(falling)
	_check(why.contains("2023") and why.contains("2024") and why.begins_with("turnover fell"), "turnover drop reads '%s'" % why)
	if not _failed:
		print("[health] PASSED: %d flagged companies each say why, in every interface language" % flagged)
		get_tree().quit(0)
