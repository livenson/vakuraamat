# What a plot is linked to, read out of the pack files with no world running: the companies on it,
# the buildings that stand on it, and the plots whose companies share an owner with its own. Also
# the rule that matters more than any of them - an owner hash never leaves links.gd.
#   godot --headless --path . res://tools/godot/links_test.tscn
extends Node

const FOCUS := "79514:036:0090"     # the one Kvissentali plot with two owner-linked neighbours
const SIBLING := "79514:036:0085"
const NO_LINKS := "79514:036:0006"  # buildings, companies, but nothing tying it to another plot
const REG_A := "79301:001:0371"     # Pootsmani tn 30 and 28: one registered immovable, two units
const REG_B := "79301:001:0373"
const BOTH_A := "79514:036:0060"    # Lootsi tänav T21 and T19: one kinnistu and one building over both
const BOTH_B := "79514:036:0066"
const FLAT := "79501:002:0167"      # Aeru tn 1, whose land_registry is the word "korteriomand"

var _failed := false


func _check(cond: bool, msg: String) -> void:
	if not cond and not _failed:
		_failed = true
		print("[links] FAILED: ", msg)
		get_tree().quit(1)


func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func():
		print("[links] FAILED: watchdog")
		get_tree().quit(2))
	Sites.select("kvissentali", false)
	GameState.reset()
	await get_tree().process_frame

	var l := Links.of(FOCUS)
	_check(l.tunnus == FOCUS, "the answer is not about the plot that was asked for")
	_check(l.companies.size() == Tenants.of(l.pack, FOCUS).size(), "the companies are not the register's")
	var sibs: Array = l.parcels.map(func(p): return str(p.tunnus))
	_check(sibs.size() == 2 and SIBLING in sibs, "%s links to %s, expected two including %s" % [FOCUS, sibs, SIBLING])
	for p in l.parcels:
		_check("owner" in p.kinds, "a plot linked to %s does not say why" % FOCUS)
		_check(int(p.shared) >= 1, "a linked plot shares no owner with %s" % FOCUS)
		_check(p.at is Vector3, "a linked plot has no place to point at")

	# the cadastre's own two rules, which is where most of the graph lives: one registered immovable
	# made of two units, and one building standing over a boundary
	_check(_kinds_between(REG_A, REG_B) == ["registry"],
			"%s and %s are one kinnistu, got %s" % [REG_A, REG_B, _kinds_between(REG_A, REG_B)])
	var both := _kinds_between(BOTH_A, BOTH_B)
	_check("registry" in both and "building" in both,
			"%s and %s share a kinnistu and a building, got %s" % [BOTH_A, BOTH_B, both])
	_check(int(Links.of(REG_A).parcels[0].shared) == 0, "a kinnistu link claims owners in common")

	# and the trap under that rule: land_registry carries the word "korteriomand" for a flat, which
	# is a form of ownership and not a property. Reading it as a number ties thirty flats together.
	_check(Links.of(FLAT).parcels.is_empty(),
			"%s is tied to %d plots through the word korteriomand" % [FLAT, Links.of(FLAT).parcels.size()])

	# the link runs both ways, or the ribbon would only exist from one end
	var back: Array = Links.of(SIBLING).parcels.map(func(p): return str(p.tunnus))
	_check(FOCUS in back, "%s links to %s but not back" % [FOCUS, SIBLING])

	# buildings come from the register's own cadastral field, with a footprint to draw
	_check(not l.buildings.is_empty(), "%s has no building, though the register lists one" % FOCUS)
	_check(l.buildings.any(func(b): return b.polygon.size() >= 3), "a building has no footprint")

	# a plot nobody else's owner touches answers empty, not wrongly and not with an error
	var lone := Links.of(NO_LINKS)
	_check(lone.parcels.is_empty(), "%s should share no owner, got %d" % [NO_LINKS, lone.parcels.size()])
	_check(not lone.buildings.is_empty(), "%s should still carry its buildings" % NO_LINKS)

	# nothing asked for, nothing invented
	_check(Links.of("").tunnus == "" and Links.of("").parcels.is_empty(), "the empty query answered something")
	var nonsense := Links.of("nonsense")
	_check(nonsense.parcels.is_empty() and nonsense.buildings.is_empty() and nonsense.companies.is_empty(),
			"an unknown plot answered something")

	# the rule the whole file exists for: the register's people are hashes in the pack and they stay
	# there. `companies` is the register's own rows, which the book already shows, so it is skipped -
	# everything links.gd builds itself must be clean.
	var built := {"parcels": l.parcels, "buildings": l.buildings, "at": l.at, "address": l.address}
	_check(_clean(built), "an owner id reached the caller")

	if not _failed:
		print("[links] PASSED: %s → %d companies, %d buildings, %d linked plots; kinnistu and shared-building links hold, korteriomand ties nothing, no owner id leaves"
				% [FOCUS, l.companies.size(), l.buildings.size(), l.parcels.size()])
		get_tree().quit(0)


## Why two plots are tied, as the answer for the first names the second. Empty when they are not.
func _kinds_between(a: String, b: String) -> Array:
	for p in Links.of(a).parcels:
		if str(p.tunnus) == b:
			var kinds: Array = p.kinds.duplicate()
			kinds.sort()
			return kinds
	return []


## True when nothing anywhere in the value is an owner id or a key that would hold one.
func _clean(v: Variant) -> bool:
	match typeof(v):
		TYPE_DICTIONARY:
			for k in v:
				if str(k) == "owners":
					return false
				if not _clean(v[k]):
					return false
		TYPE_ARRAY:
			for e in v:
				if not _clean(e):
					return false
		TYPE_STRING:
			# the register's people are stored as uuids; a cadastral number never looks like one
			if RegEx.create_from_string("^[0-9a-f]{8}-[0-9a-f]{4}-").search(str(v)):
				return false
	return true
