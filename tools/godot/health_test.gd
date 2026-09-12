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


static func _area(p: PackedVector2Array) -> float:
	var s := 0.0
	for i in p.size():
		s += p[i].cross(p[(i + 1) % p.size()])
	return absf(s) * 0.5


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
	# the health layer colours a plot whose companies are all inactive by their worst verdict (it
	# showed grey: MapPalette.dominant skips them), while a live company still speaks for its plot
	var bankrupt := {"name": "A", "status": "N", "health": "distressed", "employees": 0}
	var live := {"name": "B", "status": "R", "health": "sound", "employees": 3}
	_check(MapPalette.pick("health", [bankrupt]).get("name") == "A", "a plot with only a bankrupt company is not red")
	_check(MapPalette.pick("health", [bankrupt, live]).get("name") == "B", "a bankrupt shell outranks the live company on its plot")
	_check(MapPalette.pick("sector", [bankrupt]).is_empty(), "the sector layer colours a plot by a bankrupt company")
	# the industry-mix and one-sector layers: a plot of three traders and one IT employee is three
	# quarters trade, and its trade stripes cover three quarters of it
	var shop := {"name": "S", "status": "R", "sector": "trade", "employees": 3}
	var it := {"name": "I", "status": "R", "sector": "media", "employees": 1}
	var parts := MapPalette.shares([shop, it, bankrupt])
	_check(is_equal_approx(float(parts.get("trade", 0.0)), 0.75) and is_equal_approx(float(parts.get("media", 0.0)), 0.25), "shares are %s" % parts)
	var square := PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)])
	var area := {}
	for piece in MapPalette.stripes(square, parts, MapPalette.STRIPE_M):
		area[piece[1]] = float(area.get(piece[1], 0.0)) + _area(piece[0])
	var trade: float = float(area.get(MapPalette.SECTOR_COLORS.trade, 0.0)) / 10000.0
	_check(absf(trade - 0.75) < 0.04, "the trade stripes cover %.2f of the plot, not 0.75" % trade)
	var staffless := MapPalette.shares([{"status": "R", "sector": "trade", "employees": null}, {"status": "R", "sector": null}])
	_check(is_equal_approx(float(staffless.get("", 0.0)), 0.5), "without staff figures each company does not count one: %s" % staffless)
	if not _failed:
		print("[health] PASSED: %d flagged companies each say why, in every interface language" % flagged)
		get_tree().quit(0)
