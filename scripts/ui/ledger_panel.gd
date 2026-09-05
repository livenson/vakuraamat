# The vakuraamat: the town's ledger as a book. Tabs: Parcels (nearest first, filter all / mine / for
# sale), Plot (one parcel's card with the actions), Portfolio (cash, income, obligations, meters, donate),
# Offers (bids in and out), Town (month, index, status). Talks only to the Ledger facade.
class_name LedgerPanel
extends PanelContainer

signal show_parcel(tunnus: String)
signal guide(tunnus: String)      # point the HUD arrow at a plot
signal teleport(tunnus: String)   # jump to a plot

const GOLD := Color(0.93, 0.78, 0.35)
const MAX_ROWS := 120

var world: Node3D
var tabs: TabContainer
var _filter := "all"
var _selected := ""
var _pages: Dictionary = {}
var _price_box: SpinBox
var _bid_box: SpinBox
var _build_pick: OptionButton
var _donate_box: SpinBox


func setup(w: Node3D) -> void:
	world = w
	custom_minimum_size = Vector2(980, 640)
	visible = false
	var v := VBoxContainer.new()
	v.name = "Body"
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	var t := Label.new()
	t.name = "Title"
	t.add_theme_font_size_override("font_size", 26)
	t.add_theme_color_override("font_color", GOLD)
	v.add_child(t)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(tabs)
	for key in ["UI_LEDGER_PARCELS", "UI_LEDGER_PLOT", "UI_LEDGER_PORTFOLIO", "UI_LEDGER_OFFERS", "UI_LEDGER_TOWN"]:
		var sc := ScrollContainer.new()
		sc.name = key
		sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var body := VBoxContainer.new()
		body.name = "Page"
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_theme_constant_override("separation", 6)
		sc.add_child(body)
		tabs.add_child(sc)
		_pages[key] = body
	tabs.tab_changed.connect(func(_i): fill())
	Ledger.player_changed.connect(func(): if visible: fill())
	Ledger.month_changed.connect(func(_m): if visible: fill())


func fill() -> void:
	get_node("Body/Title").text = "%s   ·   %s   ·   %s" % [tr("UI_LEDGER_TITLE"), Ledger.date_string(), Ledger.format_money(Ledger.cash())]
	for i in tabs.get_tab_count():
		tabs.set_tab_title(i, tr(tabs.get_child(i).name))
	match tabs.current_tab:
		0: _fill_parcels()
		1: _fill_plot()
		2: _fill_portfolio()
		3: _fill_offers()
		_: _fill_town()


func open_parcel(tunnus: String) -> void:
	_selected = tunnus
	tabs.current_tab = 1
	fill()


# ---------------------------------------------------------------- parcels

func _fill_parcels() -> void:
	var body := _clear(_pages["UI_LEDGER_PARCELS"])
	var row := HBoxContainer.new()
	body.add_child(row)
	for f in ["all", "mine", "sale"]:
		var b := Button.new()
		b.text = tr("UI_LEDGER_FILTER_" + f.to_upper())
		b.disabled = f == _filter
		b.pressed.connect(func():
			_filter = f
			_fill_parcels())
		row.add_child(b)
	var player: Node3D = world.get_node_or_null("Player") if world else null
	var pos := Vector2(player.global_position.x, player.global_position.z) if player else Vector2.ZERO
	var rows: Array = Ledger.parcels().filter(func(p):
		return (_filter == "all" and (p.sellable or int(p.owner_id) != 0)) or (_filter == "mine" and Ledger.is_mine(p.tunnus)) or (_filter == "sale" and p.for_sale))
	rows.sort_custom(func(a, b): return pos.distance_to(Vector2(float(a.x), float(a.z))) < pos.distance_to(Vector2(float(b.x), float(b.z))))
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 14)
	body.add_child(grid)
	for h in ["UI_LEDGER_COL_ADDRESS", "UI_LEDGER_COL_PURPOSE", "UI_LEDGER_COL_AREA", "UI_LEDGER_COL_VALUE", "UI_LEDGER_COL_PRICE", "UI_LEDGER_COL_OWNER", "UI_LEDGER_COL_YIELD", ""]:
		grid.add_child(_lbl(tr(h) if h != "" else "", 13, GOLD))
	var n := 0
	for p in rows:
		if n >= MAX_ROWS:
			break
		n += 1
		var b := Button.new()
		b.text = "%s" % p.address if p.address != "" else p.tunnus
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.tooltip_text = p.tunnus
		var tunnus: String = p.tunnus
		b.pressed.connect(func(): open_parcel(tunnus))
		grid.add_child(b)
		grid.add_child(_lbl(_purpose(p.purpose), 13))
		grid.add_child(_lbl("%d m²" % int(p.area), 13))
		grid.add_child(_lbl(Ledger.format_money(int(p.land_value)), 13))
		grid.add_child(_lbl(Ledger.format_money(int(p.price)) if p.for_sale else "–", 13))
		grid.add_child(_lbl(tr("UI_LEDGER_YOU") if Ledger.is_mine(p.tunnus) else str(p.owner_name), 13, GOLD if Ledger.is_mine(p.tunnus) else Color.WHITE))
		grid.add_child(_lbl(Ledger.format_money(Ledger.yield_of(p.tunnus)) + tr("UI_PER_MONTH"), 13))
		grid.add_child(_nav_buttons(tunnus))
	if rows.size() > MAX_ROWS:
		body.add_child(_lbl(tr("UI_LEDGER_MORE") % (rows.size() - MAX_ROWS), 13))


# ---------------------------------------------------------------- one plot

func _fill_plot() -> void:
	var body := _clear(_pages["UI_LEDGER_PLOT"])
	var p := Ledger.parcel(_selected)
	if p.is_empty():
		body.add_child(_lbl(tr("UI_LEDGER_PICK"), 16))
		return
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	body.add_child(head)
	head.add_child(_lbl("%s   %s" % [p.address, p.tunnus], 22, GOLD))
	head.add_child(_nav_buttons(p.tunnus))
	var mine := Ledger.is_mine(p.tunnus)
	body.add_child(_lbl("%s · %d m² · %s: %s · %s: %s" % [_purpose(p.purpose), int(p.area), tr("UI_LEDGER_COL_VALUE"), Ledger.format_money(int(p.land_value)),
		tr("UI_LEDGER_COL_OWNER"), tr("UI_LEDGER_YOU") if mine else str(p.owner_name)], 15))
	body.add_child(_lbl("%s: %s%s" % [tr("UI_LEDGER_COL_YIELD"), Ledger.format_money(Ledger.yield_of(p.tunnus)), tr("UI_PER_MONTH")], 15))
	var tenants := Ledger.tenants_of(p.tunnus)
	if tenants.is_empty():
		body.add_child(_lbl(tr("UI_LEDGER_NO_TENANTS"), 14))
	else:
		body.add_child(_lbl(tr("UI_LEDGER_TENANTS"), 15, GOLD))
		var arrears := 0
		for t in tenants:
			arrears += int(t.arrears)
			var status := "" if t.status == "R" else "  (%s)" % tr("UI_TENANT_INACTIVE")
			var owe := "  · %s %s" % [tr("UI_LEDGER_ARREARS"), Ledger.format_money(int(t.arrears))] if int(t.arrears) > 0 else ""
			body.add_child(_lbl("   %s · %s · %s %s%s%s" % [t.name, t.legal_form, tr("UI_SINCE"), t.since, status, owe], 14))
	var imps := Ledger.improvements_of(p.tunnus)
	if imps.size() > 0:
		body.add_child(_lbl(tr("UI_LEDGER_BUILT") + ": " + ", ".join(imps.map(func(i): return _struct_name(i.structure_id))), 14))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	body.add_child(actions)
	if not mine and p.for_sale and p.sellable:
		_btn(actions, tr("BTN_BUY") + "  " + Ledger.format_money(int(p.price)), func(): _do(await Ledger.buy(p.tunnus), "NOTICE_BOUGHT", p.address))
	if not mine and int(p.owner_id) != 0:
		_bid_box = _spin(actions, int(p.price), 1000, 5_000_000)
		_btn(actions, tr("BTN_BID"), func(): _do(await Ledger.place_bid(p.tunnus, int(_bid_box.value)), "", ""))
	if mine:
		_price_box = _spin(actions, int(p.price) if p.for_sale else int(p.land_value), 1000, 5_000_000)
		_btn(actions, tr("BTN_LIST"), func(): _do(await Ledger.list_for_sale(p.tunnus, int(_price_box.value)), "", ""))
		if p.for_sale:
			_btn(actions, tr("BTN_UNLIST"), func(): _do(await Ledger.list_for_sale(p.tunnus, 0), "", ""))
	var arrears_total := 0
	for t in tenants:
		arrears_total += int(t.arrears)
	if arrears_total > 0:
		if mine:
			_btn(actions, tr("BTN_PRESS") + "  " + Ledger.format_money(arrears_total), func(): _do(await Ledger.press_tenant(p.tunnus), "", ""))
		else:
			_btn(actions, tr("BTN_ARREARS") + "  " + Ledger.format_money(arrears_total), func(): _do(await Ledger.buy_arrears(p.tunnus), "", ""))
	if mine and Ledger.structures().size() > 0:
		var brow := HBoxContainer.new()
		brow.add_theme_constant_override("separation", 10)
		body.add_child(brow)
		_build_pick = OptionButton.new()
		var built: Array = imps.map(func(i): return i.structure_id)
		for s in Ledger.structures():
			if s.id in built:
				continue
			var need := "" if s.requires == "" or s.requires in built else "  (%s %s)" % [tr("UI_LEDGER_NEEDS"), _struct_name(s.requires)]
			_build_pick.add_item("%s  %s  +%s%s%s" % [_struct_name(s.id), Ledger.format_money(int(s.cost)), Ledger.format_money(int(s.rent_bonus)), tr("UI_PER_MONTH"), need])
			_build_pick.set_item_metadata(_build_pick.item_count - 1, s.id)
		brow.add_child(_build_pick)
		if _build_pick.item_count > 0:
			_btn(brow, tr("BTN_BUILD"), func():
				var sid: String = str(_build_pick.get_item_metadata(_build_pick.selected))
				_do(await Ledger.build(p.tunnus, sid), "", ""))
	var bids := Ledger.bids_for(p.tunnus)
	if bids.size() > 0:
		body.add_child(_lbl(tr("UI_LEDGER_OFFERS"), 15, GOLD))
		for b in bids:
			var line := HBoxContainer.new()
			body.add_child(line)
			line.add_child(_lbl("   %s: %s" % [b.bidder_name, Ledger.format_money(int(b.amount))], 14))
			if mine:
				_btn(line, tr("BTN_ACCEPT"), func(): _do(await Ledger.accept_bid(int(b.id)), "", ""))
			elif int(b.bidder_id) == int(Ledger.me().get("id", -1)):
				_btn(line, tr("BTN_WITHDRAW"), func(): _do(await Ledger.withdraw_bid(int(b.id)), "", ""))
	show_parcel.emit(p.tunnus)


# ---------------------------------------------------------------- portfolio, offers, town

func _fill_portfolio() -> void:
	var body := _clear(_pages["UI_LEDGER_PORTFOLIO"])
	var me := Ledger.me()
	var owned := Ledger.parcels().filter(func(p): return Ledger.is_mine(p.tunnus))
	body.add_child(_lbl("%s: %s" % [tr("UI_LEDGER_CASH"), Ledger.format_money(Ledger.cash())], 20, GOLD))
	body.add_child(_lbl("%s: %d   ·   %s: %s%s" % [tr("UI_LEDGER_OWNED"), owned.size(), tr("UI_LEDGER_INCOME"), Ledger.format_money(Ledger.monthly_income()), tr("UI_PER_MONTH")], 15))
	body.add_child(_lbl("%s %d   ·   %s %d   ·   %s %d" % [tr("UI_LEDGER_FAVOURS"), int(me.get("favours", 0)), tr("UI_LEDGER_HEAT"), int(me.get("heat", 0)),
		tr("UI_LEDGER_REPUTATION"), int(me.get("reputation", 0))], 15))
	var due := Ledger.obligations()
	body.add_child(_lbl(tr("UI_LEDGER_OBLIGATIONS") + (": –" if due.is_empty() else ""), 15, GOLD))
	for o in due:
		var line := HBoxContainer.new()
		body.add_child(line)
		var p := Ledger.parcel(o.tunnus)
		line.add_child(_lbl("   %s · %s · %s %s · %s" % [tr("UI_LEDGER_" + str(o.kind).to_upper()), p.get("address", o.tunnus), tr("UI_LEDGER_DUE"), _month_name(int(o.due_month)), Ledger.format_money(int(o.amount))], 14))
		_btn(line, tr("BTN_PAY"), func(): _do(await Ledger.pay(int(o.id)), "", ""))
	var drow := HBoxContainer.new()
	drow.add_theme_constant_override("separation", 10)
	body.add_child(drow)
	drow.add_child(_lbl(tr("UI_LEDGER_DONATE_HINT"), 14))
	_donate_box = _spin(drow, 1000, 100, 1_000_000)
	_btn(drow, tr("BTN_DONATE"), func(): _do(await Ledger.donate(int(_donate_box.value)), "", ""))
	for p in owned:
		var b := Button.new()
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "%s   %s   %s%s" % [p.address, p.tunnus, Ledger.format_money(Ledger.yield_of(p.tunnus)), tr("UI_PER_MONTH")]
		var tunnus: String = p.tunnus
		b.pressed.connect(func(): open_parcel(tunnus))
		body.add_child(b)


func _fill_offers() -> void:
	var body := _clear(_pages["UI_LEDGER_OFFERS"])
	body.add_child(_lbl(tr("UI_LEDGER_OFFERS_IN"), 15, GOLD))
	var any := false
	for p in Ledger.parcels():
		if not Ledger.is_mine(p.tunnus):
			continue
		for b in Ledger.bids_for(p.tunnus):
			any = true
			var line := HBoxContainer.new()
			body.add_child(line)
			line.add_child(_lbl("   %s · %s: %s" % [p.address, b.bidder_name, Ledger.format_money(int(b.amount))], 14))
			_btn(line, tr("BTN_ACCEPT"), func(): _do(await Ledger.accept_bid(int(b.id)), "", ""))
	if not any:
		body.add_child(_lbl("   –", 14))
	body.add_child(_lbl(tr("UI_LEDGER_OFFERS_OUT"), 15, GOLD))
	var mine := Ledger.my_bids()
	if mine.is_empty():
		body.add_child(_lbl("   –", 14))
	for b in mine:
		var line := HBoxContainer.new()
		body.add_child(line)
		line.add_child(_lbl("   %s: %s" % [Ledger.parcel(b.tunnus).get("address", b.tunnus), Ledger.format_money(int(b.amount))], 14))
		_btn(line, tr("BTN_WITHDRAW"), func(): _do(await Ledger.withdraw_bid(int(b.id)), "", ""))


func _fill_town() -> void:
	var body := _clear(_pages["UI_LEDGER_TOWN"])
	body.add_child(_lbl("%s   ·   %s %d" % [Ledger.date_string(), tr("UI_LEDGER_MONTH"), Ledger.month()], 18, GOLD))
	body.add_child(_lbl("%s: %.2f" % [tr("UI_LEDGER_INDEX"), Ledger.price_index() / 1000.0], 15))
	body.add_child(_lbl("%s: %s" % [tr("UI_LEDGER_STATUS"), tr("UI_ONLINE") % Ledger.town_name if Ledger.online else tr("UI_OFFLINE")], 15))
	var owned := Ledger.parcels().filter(func(p): return int(p.owner_id) != 0)
	body.add_child(_lbl("%s: %d / %d" % [tr("UI_LEDGER_OWNED_TOWN"), owned.size(), Ledger.parcels().size()], 15))
	body.add_child(_lbl(tr("UI_LEDGER_TOWN_HINT"), 13))


# ---------------------------------------------------------------- helpers

func _do(err: String, ok_key: String, arg: String) -> void:
	if err != "":
		EventBus.notice.emit(tr(err))
	elif ok_key != "":
		EventBus.notice.emit(tr(ok_key) % arg)
	fill()


func _clear(page: VBoxContainer) -> VBoxContainer:
	for c in page.get_children():
		c.queue_free()
	return page


func _lbl(text: String, size: int, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	if color != Color.WHITE:
		l.add_theme_color_override("font_color", color)
	return l


func _btn(parent: Node, text: String, f: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(f)
	parent.add_child(b)
	return b


func _spin(parent: Node, value: int, min_v: int, max_v: int) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = 100
	s.value = clampi(value, min_v, max_v)
	s.suffix = tr("CUR_EUR")
	s.custom_minimum_size.x = 170
	parent.add_child(s)
	return s


## "Guide" points the HUD arrow at the plot; "Go" jumps there (the game's teleport, like T and the map).
func _nav_buttons(tunnus: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	var g := Button.new()
	g.text = tr("BTN_GUIDE")
	g.tooltip_text = tr("BTN_GUIDE_TIP")
	g.pressed.connect(func(): guide.emit(tunnus))
	h.add_child(g)
	var t := Button.new()
	t.text = tr("BTN_TELEPORT")
	t.tooltip_text = tr("BTN_TELEPORT_TIP")
	t.pressed.connect(func(): teleport.emit(tunnus))
	h.add_child(t)
	return h


func _purpose(code: String) -> String:
	var key := "PURPOSE_" + code
	var t := tr(key)
	return t if t != key else code


func _struct_name(id: String) -> String:
	for s in Ledger.structures():
		if s.id == id:
			return tr(str(s.display_name_key)) if s.display_name_key != "" else id
	return id


func _month_name(m: int) -> String:
	var t: Dictionary = Sites.get_value("terrain", {})
	var date: Array = t.get("date", [2026, 1, 1]) if typeof(t) == TYPE_DICTIONARY else [2026, 1, 1]
	var idx := int(date[1]) - 1 + m
	return "%s %d" % [tr("MONTH_%d" % (idx % 12 + 1)), int(date[0]) + int(idx / 12)]
