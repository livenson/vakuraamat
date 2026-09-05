# Headless check of the offline town ledger on the Kvissentali pack: prices from land values, buying,
# rent and land tax after a month, bids between two players, building with prerequisites, save round trip,
# and the isolation rule that ledger logic and UI never reference the SpacetimeDB SDK.
#   godot --headless --path . res://tools/godot/ledger_test.tscn
extends Node

var _failed := false


func _check(cond: bool, msg: String) -> void:
	if not cond and not _failed:
		_failed = true
		print("[ledger] FAILED: ", msg)
		get_tree().quit(1)


func _ready() -> void:
	get_tree().create_timer(90.0).timeout.connect(func():
		print("[ledger] FAILED: watchdog")
		get_tree().quit(2))
	await get_tree().process_frame
	TranslationServer.set_locale("en")
	Sites.select("kvissentali", false)
	GameState.reset()
	var l: LocalLedger = Ledger.local()
	_check(l != null and l.parcels.size() > 200, "parcels not loaded: %d" % (l.parcels.size() if l else -1))
	var sellable := Ledger.parcels().filter(func(p): return p.sellable)
	_check(sellable.size() > 100, "too few sellable parcels: %d" % sellable.size())
	_check(sellable.all(func(p): return int(p.price) > 0 and int(p.land_value) > 0), "a sellable parcel has no price")
	var roads := Ledger.parcels().filter(func(p): return p.purpose == "TRANSPORDIMAA")
	_check(roads.size() > 0 and roads.all(func(p): return not p.sellable), "transport land must not be sellable")
	_check(Ledger.cash() == 250000, "starting cash %d" % Ledger.cash())
	_check(Ledger.date_string() == "September 2026", "date string %s" % Ledger.date_string())
	_check(Ledger.format_money(1200) == "1200 €", "money format %s" % Ledger.format_money(1200))

	# buying: too expensive, then an affordable tenanted plot
	var tenanted := sellable.filter(func(p): return Ledger.tenants_of(p.tunnus).size() > 0 and int(p.price) <= 200000)
	_check(tenanted.size() > 0, "no affordable tenanted parcel")
	var target: Dictionary = tenanted[0]
	await Ledger.debug_grant(-Ledger.cash() + 10)
	_check(await Ledger.buy(target.tunnus) == "LEDGER_NO_MONEY", "buy should fail without money")
	await Ledger.debug_grant(250000 - 10)
	var before := Ledger.cash()
	_check(await Ledger.buy(target.tunnus) == "", "buy failed")
	_check(Ledger.is_mine(target.tunnus) and Ledger.cash() == before - int(target.price), "ownership or cash wrong after buy")
	_check(await Ledger.buy(target.tunnus) == "LEDGER_ALREADY_OWNER", "second buy should say already owner")
	_check(Ledger.events(5)[0].kind == "sale", "sale event missing")

	# a month: rent equals the yield when no tenant falls behind; land tax comes due
	l.config["arrears_chance"] = {"R": 0.0, "default": 0.0}
	l.config["ai_bid_chance"] = 0.0
	var yield_m := Ledger.yield_of(target.tunnus)
	_check(yield_m > 0, "no yield on a tenanted plot")
	before = Ledger.cash()
	Ledger.debug_advance_month()
	_check(Ledger.month() == 1 and Ledger.cash() == before + yield_m, "rent after a month: %d -> %d, yield %d" % [before, Ledger.cash(), yield_m])
	var due := Ledger.obligations()
	_check(due.size() == 1 and due[0].kind == "land_tax" and int(due[0].amount) == l.tax_month(int(target.land_value)), "land tax obligation wrong")
	before = Ledger.cash()
	_check(await Ledger.pay(int(due[0].id)) == "" and Ledger.obligations().size() == 0 and Ledger.cash() == before - int(due[0].amount), "paying tax failed")

	# bids: a second local player bids on my plot, I accept
	var other := l.add_player("Neighbour")
	_check(l.place_bid(other, target.tunnus, 1000) == "", "neighbour bid failed")
	_check(await Ledger.place_bid(target.tunnus, 500) == "LEDGER_NOT_BIDDABLE", "owner must not bid on own plot")
	var bid: Dictionary = Ledger.bids_for(target.tunnus)[0]
	before = Ledger.cash()
	_check(await Ledger.accept_bid(int(bid.id)) == "", "accept failed")
	_check(Ledger.owner_of(target.tunnus) == other and Ledger.cash() == before + 1000, "transfer after accept wrong")
	_check(l.players[other].cash == 250000 - 1000, "buyer not charged")

	# building on an owned plot: prerequisite, duplicate, cost
	var mine: Dictionary = sellable.filter(func(p): return int(p.owner_id) == 0 and int(p.price) <= 100000)[0]
	_check(await Ledger.buy(mine.tunnus) == "", "second buy failed")
	_check(await Ledger.build(mine.tunnus, "barn") == "LEDGER_REQUIRES", "barn should need the storehouse")
	before = Ledger.cash()
	_check(await Ledger.build(mine.tunnus, "storehouse") == "", "storehouse build failed")
	_check(Ledger.cash() == before - int(l.structures["storehouse"].cost), "build cost not charged")
	_check(await Ledger.build(mine.tunnus, "barn") == "" and await Ledger.build(mine.tunnus, "barn") == "LEDGER_ALREADY_BUILT", "barn build or duplicate check failed")
	_check(Ledger.improvements_of(mine.tunnus).size() == 2, "improvement count")
	_check(await Ledger.build(target.tunnus, "storehouse") == "LEDGER_NOT_OWNER", "building on a sold plot must fail")

	# save round trip
	var cash_before := Ledger.cash()
	_check(SaveManager.save("ledger_test"), "save failed")
	await Ledger.debug_grant(12345)
	var ok: bool = await SaveManager.load_slot("ledger_test")
	_check(ok, "load failed")
	_check(Ledger.month() == 1 and Ledger.cash() == cash_before and Ledger.is_mine(mine.tunnus) and Ledger.owner_of(target.tunnus) == other
		and Ledger.improvements_of(mine.tunnus).size() == 2, "state after load differs")

	# isolation: ledger logic and UI never touch the SDK; only town_ledger.gd may
	for f in ["res://scripts/ledger/local_ledger.gd", "res://scripts/autoload/ledger.gd", "res://scripts/ui/ui_manager.gd", "res://scripts/ui/main_menu.gd"]:
		var src := FileAccess.get_file_as_string(f)
		_check(not ("SpacetimeDB" in src or "spacetime_bindings" in src), "SDK referenced outside town_ledger: " + f)
	if not _failed:
		print("[ledger] PASSED")
		get_tree().quit()
