# Headless check of Phase 4 trading and Phase 5 base building in the 1938 scene.
#   godot --headless --path . res://tools/godot/economy_test.tscn
extends Node

var _failed := false


func _check(cond: bool, msg: String) -> void:
	if not cond and not _failed:
		_failed = true
		print("[econ] FAILED: ", msg)
		get_tree().quit(1)


func _ready() -> void:
	get_tree().create_timer(120.0).timeout.connect(func():
		print("[econ] FAILED: watchdog")
		get_tree().quit(2))
	GameState.reset()
	TranslationServer.set_locale("en")
	var world: Node3D = load("res://scenes/world/world.tscn").instantiate()
	add_child(world)
	await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	GameState.register_unlocked = true
	GameState.chapter = 2
	await GameState.switch_era("era_1938")
	var layer: Node = world.get_node("EraLayers/era_1938")
	var post: TradePost = layer.find_child("TradePost", true, false)
	_check(post != null and post.era_id == "era_1938", "no 1938 trade post")
	# --- sell farm produce, buy timber; money stays in 1938
	for i in 6:
		Inventory.add("rye")
	var start := Trading.balance("era_1938")
	var rye_good: TradeGood = Trading.goods_for("era_1938").filter(func(g): return g.item_id == "rye")[0]
	_check(Trading.sell(rye_good, "era_1938"), "sell failed")
	_check(Trading.balance("era_1938") == start + rye_good.sell_price, "sell price not credited")
	var timber_good: TradeGood = Trading.goods_for("era_1938").filter(func(g): return g.item_id == "timber")[0]
	_check(Trading.buy(timber_good, "era_1938") and Inventory.local_items("era_1938").has("timber"), "buy failed")
	_check(not Trading.sell(rye_good, "era_2026"), "sold into another era")
	_check(Trading.balance("era_2026") == 2000 and Trading.balance("era_1798") == 12, "money leaked across eras")
	# artifacts can never be traded
	var fake := TradeGood.new()
	fake.item_id = "manor_key"
	fake.era_id = "era_1938"
	fake.buy_price = 1
	_check(not Trading.buy(fake, "era_1938"), "artifact was tradeable")
	print("[econ] trading ok: balance %d, bag %s" % [Trading.balance("era_1938"), Inventory.local_items("era_1938")])
	# --- build at the home manor
	var home: ManorController = layer.find_child("Manor_kaseoja_farm", true, false)
	var park: ManorController = layer.find_child("Manor_manor_park", true, false)
	_check(home != null and park != null, "manor controllers missing")
	var m := home.manor
	var store: StructureDefinition = Manors.structures["storehouse"]
	_check(Manors.can_build(m, Manors.structures["sauna"]) == "BUILD_REQUIRES", "prerequisite not enforced")
	_check(Manors.can_build(m, store) == "", "cannot build storehouse: %s" % Manors.can_build(m, store))
	var children_before := home.get_child_count()
	_check(Manors.build(m, store), "build failed")
	await get_tree().process_frame
	_check(home.get_child_count() > children_before, "structure not spawned")
	_check(Manors.can_build(m, store) == "BUILD_ALREADY", "rebuild allowed")
	_check(not Manors.is_unlocked(park.manor), "park unlocked without its flag")
	TimelineState.set_flag("family_recorded_1798", true)
	_check(Manors.is_unlocked(park.manor), "park not unlocked by flag")
	_check(TimelineState.flags.keys().filter(func(k): return "storehouse" in k).is_empty(), "building wrote a timeline flag")
	# save round trip
	_check(SaveManager.save("econ_test"), "save failed")
	Manors.built = {}
	Trading.money = {}
	var ok: bool = await SaveManager.load_slot("econ_test")
	_check(ok and Manors.development_level("kaseoja_farm") == 1 and Trading.balance("era_1938") > 0, "economy state not restored")
	for f in ["trade_good.gd", "trading.gd", "trade_post.gd"]:
		var src := FileAccess.get_file_as_string("res://scripts/trading/" + f)
		_check(not ("TimelineState" in src or "ConsequencePoint" in src), "trading references timeline: " + f)
	if not _failed:
		print("[econ] PASSED")
	get_tree().quit()
