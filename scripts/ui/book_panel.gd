# The vakuraamat: what the registers say about this square kilometre, as a book. Four pages, all
# read-only - Plots (the cadastre, sortable, searchable), Plot (one unit's card and its land over
# the years), Companies (the Business Register's rows for the tile), Place (the pack itself: where
# it is, when it was fetched, what the land is worth, who the data belongs to).
#
# Nothing here is invented. Every figure is a field of sites/<id>/*.json, and where a register says
# nothing the line is simply absent.
class_name BookPanel
extends PanelContainer

signal show_parcel(tunnus: String)
signal guide(tunnus: String)      # point the HUD arrow at a plot
signal teleport(tunnus: String)   # jump to a plot
signal focus(tunnus: String)      # light this plot and what it is linked to, in every view

const GOLD := BookTheme.BLUE   # the accent of the book: a heading, a name, a number that matters
const MAX_ROWS := 120

# The plot list's columns, and what each sorts by. "address" is the default: a list of plots is
# read by name, and the nearest-first order it used to have looked like no order at all.
const COLUMNS := [
	{"key": "UI_BOOK_COL_ADDRESS", "by": "address", "right": false},
	{"key": "UI_BOOK_COL_PURPOSE", "by": "purpose", "right": false},
	{"key": "UI_BOOK_COL_AREA", "by": "area", "right": true},
	{"key": "UI_BOOK_COL_VALUE", "by": "land_value", "right": true},
	{"key": "UI_BOOK_COL_OWNERSHIP", "by": "ownership", "right": false},
	{"key": "", "by": "near", "right": false},
]

# The companies list's columns. Same click-to-sort as the plot list; a figure column starts at its
# largest (the biggest employer is what the page is read for), a word column at its first letter.
const COMPANY_COLUMNS := [
	{"key": "UI_BOOK_COL_COMPANY", "by": "name", "right": false},
	{"key": "UI_BOOK_COL_SECTOR", "by": "sector", "right": false},
	{"key": "UI_BOOK_COL_EMPLOYEES", "by": "employees", "right": true},
	{"key": "UI_BOOK_COL_TURNOVER", "by": "turnover", "right": true},
	{"key": "UI_BOOK_COL_ADDRESS", "by": "address", "right": false},
]

var world: Node3D
var tabs: TabContainer
var _query := ""
var _sort := "address"
var _sort_desc := false
var _selected := ""
var _sector_filter := ""
var _co_sort := "employees"
var _co_desc := true
var _pages: Dictionary = {}
var _focus := ""                  # the plot lit everywhere, and
var _linked: Dictionary = {}      # the plots it is linked to, as a set, so a row can ask in one step


func setup(w: Node3D) -> void:
	world = w
	EventBus.parcel_focused.connect(_on_focused)
	theme = BookTheme.theme()
	custom_minimum_size = Vector2(980, 640)
	visible = false
	var v := VBoxContainer.new()
	v.name = "Body"
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	var t := Label.new()
	t.name = "Title"
	t.theme_type_variation = "HeadLabel"
	v.add_child(t)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(tabs)
	for key in ["UI_BOOK_PLOTS", "UI_BOOK_PLOT", "UI_BOOK_COMPANIES", "UI_BOOK_PLACE"]:
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


func fill() -> void:
	get_node("Body/Title").text = "%s      %s" % [tr("UI_BOOK_TITLE"), Sites.display_name(Sites.active)]
	for i in tabs.get_tab_count():
		tabs.set_tab_title(i, tr(tabs.get_child(i).name))
	match tabs.current_tab:
		0: _fill_plots()
		1: _fill_plot()
		2: _fill_companies()
		_: _fill_place()


func open_parcel(tunnus: String) -> void:
	_selected = tunnus
	tabs.current_tab = 1
	fill()


## The focus changed somewhere - a row here, the map, the key in the world. The pages are rebuilt
## whole on every refresh, so remembering the set is all the marking needs.
func _on_focused(tunnus: String) -> void:
	if _linked == null:
		_linked = {}
	_focus = tunnus
	_linked.clear()
	for p in Links.of(tunnus).parcels:
		_linked[str(p.tunnus)] = true
	if visible:
		fill()


## The type variation that marks a row: the focused plot, one linked to it, or neither.
func _row_mark(tunnus: String) -> String:
	if tunnus != "" and tunnus == _focus:
		return "FocusRow"
	return "LinkedRow" if _linked != null and _linked.has(tunnus) else ""


# ---------------------------------------------------------------- the cadastre

func _fill_plots() -> void:
	var body := _clear(_pages["UI_BOOK_PLOTS"])
	var row := HBoxContainer.new()
	body.add_child(row)
	# a page holds 120 of a few hundred plots, so sorted by name you would see the As and never the
	# rest: typing narrows the list instead of scrolling it
	var find := LineEdit.new()
	find.placeholder_text = tr("UI_BOOK_FIND_PLACEHOLDER")
	find.text = _query
	find.custom_minimum_size = Vector2(260, 0)
	find.right_icon = null
	find.text_changed.connect(func(t: String):
		_query = t
		_fill_plots())
	row.add_child(find)
	if _query != "":
		var clear := Button.new()
		clear.text = "×"
		clear.pressed.connect(func():
			_query = ""
			_fill_plots())
		row.add_child(clear)
	find.call_deferred("grab_focus")
	find.call_deferred("set_caret_column", _query.length())
	var player: Node3D = world.get_node_or_null("Player") if world else null
	var pos := Vector2(player.global_position.x, player.global_position.z) if player else Vector2.ZERO
	var rows: Array = Parcels.all().duplicate()
	if _query.strip_edges() != "":
		# the address, the cadastral number, or a company registered on the plot
		rows = rows.filter(func(p):
			if PlaceSearch.score(str(p.get("address", "")), _query) > 0 or PlaceSearch.score(str(p.tunnus), _query) > 0:
				return true
			for t in Tenants.of(str(p.get("pack", "")), str(p.tunnus)):
				if PlaceSearch.score(str(t.get("name", "")), _query) > 0:
					return true
			return false)
	_sort_rows(rows, pos)
	var grid := GridContainer.new()
	grid.columns = COLUMNS.size()
	grid.add_theme_constant_override("h_separation", 14)
	body.add_child(grid)
	# the headings sort the list: click one to sort by it, again to reverse
	for h in COLUMNS:
		if h.key == "":
			BookTheme.label("", "ColumnLabel", grid)
			continue
		var b := Button.new()
		b.flat = true
		b.theme_type_variation = "ColumnLabel"
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			b.add_theme_stylebox_override(st, StyleBoxEmpty.new())   # a button's padding would widen every column
		b.text = tr(h.key) + ("  ↓" if _sort == h.by and not _sort_desc else ("  ↑" if _sort == h.by else ""))
		b.alignment = HORIZONTAL_ALIGNMENT_RIGHT if h.right else HORIZONTAL_ALIGNMENT_LEFT
		b.tooltip_text = tr("UI_BOOK_SORT_BY") % tr(h.key)
		var by: String = h.by
		b.pressed.connect(func():
			_sort_desc = _sort == by and not _sort_desc
			_sort = by
			_fill_plots())
		grid.add_child(b)
	var n := 0
	for p in rows:
		if n >= MAX_ROWS:
			break
		n += 1
		var b := Button.new()
		b.text = "%s" % p.address if p.address != "" else p.tunnus
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.tooltip_text = p.tunnus
		var tunnus: String = p.tunnus
		var mark := _row_mark(tunnus)
		b.flat = mark == ""
		b.theme_type_variation = mark
		b.pressed.connect(func(): open_parcel(tunnus))
		grid.add_child(b)
		grid.add_child(_lbl(_purpose(Parcels.purpose_of(p)), 13))
		grid.add_child(_num("%d m²" % int(p.get("area", 0))))
		grid.add_child(_num(BookTheme.money(int(_value(p)))) if _value(p) > 0 else _num("–"))
		grid.add_child(_lbl(str(p.get("ownership", "")), 13))
		grid.add_child(_nav_buttons(tunnus))
	if rows.size() > MAX_ROWS:
		body.add_child(_lbl(tr("UI_BOOK_MORE") % (rows.size() - MAX_ROWS), 13))
	elif rows.is_empty():
		body.add_child(_lbl(tr("UI_BOOK_NO_MATCH") % _query, 14))


## The 2022 taxation value, 0 when the register carries none (the file uses null, not a missing key).
static func _value(p: Dictionary) -> float:
	var v = p.get("land_value")
	return 0.0 if v == null else float(v)


## Order the plot list by the chosen column. Addresses sort naturally - "Aruküla tee 9" before
## "Aruküla tee 30", which a plain string sort gets backwards - and a plot with no address sorts
## after the named ones rather than at the top under its cadastral number.
func _sort_rows(rows: Array, near: Vector2) -> void:
	var key := func(p: Dictionary) -> Variant:
		match _sort:
			"address": return _address_key(str(p.get("address", "")), str(p.get("tunnus", "")))
			"purpose": return _purpose(Parcels.purpose_of(p))
			"ownership": return str(p.get("ownership", ""))
			"area": return float(p.get("area", 0))
			"land_value": return _value(p)
			_: return near.distance_to(Vector2(float(p.x), float(p.z)))
	rows.sort_custom(func(a, b):
		var ka = key.call(a)
		var kb = key.call(b)
		if ka == kb:
			return str(a.tunnus) < str(b.tunnus)
		return kb < ka if _sort_desc else ka < kb)


## An address as something that sorts the way a person reads it: the street, then the house number
## as a number, then the rest. Plots without an address go last, under their cadastral number.
static func _address_key(address: String, tunnus: String) -> String:
	if address.strip_edges() == "":
		return "￿" + tunnus
	var out := ""
	var digits := ""
	for ch in address.to_lower():
		if ch >= "0" and ch <= "9":
			digits += ch
		else:
			if digits != "":
				out += "%09d" % int(digits)     # numbers compare as numbers, not as text
				digits = ""
			out += ch
	if digits != "":
		out += "%09d" % int(digits)
	return out


# ---------------------------------------------------------------- one plot

func _fill_plot() -> void:
	var body := _clear(_pages["UI_BOOK_PLOT"])
	var p := Parcels.by_tunnus(_selected)
	if p.is_empty():
		body.add_child(_lbl(tr("UI_BOOK_PICK"), 16))
		return
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	body.add_child(head)
	head.add_child(_lbl("%s   %s" % [p.address, p.tunnus], 22, GOLD))
	head.add_child(_nav_buttons(p.tunnus))
	body.add_child(_lbl("%s, %d m²" % [_purpose(Parcels.purpose_of(p)), int(p.get("area", 0))], 15))
	if _value(p) > 0:
		var per := ""
		if p.get("land_value_per_m2") != null:
			per = "   (%s/m²)" % BookTheme.money(int(round(float(p.land_value_per_m2))))
		body.add_child(_lbl("%s: %s%s" % [tr("UI_BOOK_COL_VALUE"), BookTheme.money(int(_value(p))), per], 15))
	for pair in [["UI_BOOK_COL_OWNERSHIP", "ownership"], ["UI_BOOK_LAND_REGISTRY", "land_registry"], ["UI_BOOK_REGISTERED", "registered"]]:
		var v := str(p.get(pair[1], "") if p.get(pair[1]) != null else "")
		if v != "":
			body.add_child(_lbl("%s: %s" % [tr(pair[0]), v.trim_suffix("Z")], 15))
	var where: Array[String] = []
	for field in ["settlement", "municipality", "county"]:
		var v := str(p.get(field, "") if p.get(field) != null else "")
		if v != "" and not (v in where):
			where.append(v)
	if not where.is_empty():
		body.add_child(_lbl(", ".join(where), 14, BookTheme.FADED))
	var rows := Tenants.of(str(p.get("pack", "")), str(p.tunnus))
	if rows.is_empty():
		body.add_child(_lbl(tr("UI_BOOK_NONE_REGISTERED"), 14))
	else:
		# a plot whose companies are all struck off has none registered on it: say that, rather than
		# heading a list of closed firms with "registered here"
		var live := rows.any(func(t): return str(t.get("status", "")) == "R")
		body.add_child(_lbl(tr("UI_BOOK_REGISTERED_HERE") if live else tr("UI_BOOK_FORMERLY_HERE"), 15, GOLD))
		for t in rows:
			var crow := HBoxContainer.new()
			crow.add_theme_constant_override("separation", 10)
			body.add_child(crow)
			crow.add_child(_lbl("   " + Tenants.headline(t), 14))
			_link_button(crow, str(t.get("link", "")), tr("UI_BOOK_IN_THE_REGISTER"))
			var facts := Tenants.facts(t)
			if facts != "":
				body.add_child(_lbl("      " + facts, 13, BookTheme.FADED if str(t.get("health", "")) != "distressed" else BookTheme.RUBRIC))
	_fill_links(body, str(p.tunnus))
	var lrow := HBoxContainer.new()
	body.add_child(lrow)
	_link_button(lrow, Countries.parcel_link(p), tr("UI_BOOK_IN_THE_REGISTER"))   # the pack's link, else the country's (a Latvian plot: its property's Lursoft card)
	_fill_plot_history(body, p.tunnus)
	show_parcel.emit(p.tunnus)


## What else the registers tie this plot to: the buildings standing on it, and the plots whose
## companies share an owner with its own. The owners are people, and the pack keeps them as ids, so
## the page counts them and names the land - never the person. The land itself is not jointly held:
## the cadastre says only who the form of ownership is, which is why the note is there.
func _fill_links(body: Node, tunnus: String) -> void:
	var l := Links.of(tunnus)
	body.add_child(_lbl(tr("UI_LINK_HEAD"), 15, GOLD))
	if not l.buildings.is_empty():
		body.add_child(_lbl("   " + tr("UI_LINK_BUILDINGS") % l.buildings.size(), 14))
	if l.parcels.is_empty():
		body.add_child(_lbl("   " + tr("UI_LINK_NONE"), 14, BookTheme.FADED))
		return
	body.add_child(_lbl("   " + tr("UI_LINK_PLOTS") % l.parcels.size(), 14))
	var by_owner := false
	for s in l.parcels:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		body.add_child(row)
		row.add_child(_lbl("      ", 14))
		var b := Button.new()
		b.theme_type_variation = "TextButton"
		b.text = str(s.address) if str(s.address) != "" else str(s.tunnus)
		b.tooltip_text = str(s.tunnus)
		var other: String = str(s.tunnus)
		b.pressed.connect(func(): open_parcel(other))
		row.add_child(b)
		row.add_child(_lbl(_why(s), 13, BookTheme.FADED))
		by_owner = by_owner or ("owner" in s.get("kinds", []))
	# the caveat belongs to the owner rule alone: the other two are the cadastre's own statements
	if by_owner:
		body.add_child(_lbl("   " + tr("UI_LINK_OWNERS_NOTE"), 12, BookTheme.FADED))


## Why two plots are tied, in the register's terms. A plot can be tied by more than one rule, and
## then it says all of them - "same registered immovable, a building on both" is a real answer.
func _why(s: Dictionary) -> String:
	var bits: Array[String] = []
	for kind in s.get("kinds", []):
		match str(kind):
			"owner": bits.append(tr("UI_LINK_WHY_OWNER") % int(s.get("shared", 0)))
			"registry": bits.append(tr("UI_LINK_WHY_REGISTRY"))
			"building": bits.append(tr("UI_LINK_WHY_BUILDING"))
	return ", ".join(bits)


# ------------------------------------------------------- the plot over the years

## The land itself, campaign by campaign: the plot's square out of every orthophoto flown over it
## since 1993, with its boundary drawn on each. The newest is a crop of the tile's own photograph
## and costs nothing; the older ones are fetched once and cached, so this fills in over a second or
## two the first time a plot is opened and instantly ever after. A tile with no georeference, a
## plot from another pack, or a service that does not answer simply leaves the strip out.
func _fill_plot_history(body: Node, tunnus: String) -> void:
	if not PlotStrip.can_show(world, tunnus):
		return
	var strip := PlotStrip.new()
	body.add_child(strip)
	strip.setup(world, tunnus)


## Checks: the plot list filtered by `text` (--open=plots:<text>).
func debug_filter(text: String) -> void:
	_query = text
	fill()


## Checks: the company list sorted by one column, as clicking its heading does
## (--open=companies:<name|sector|employees|turnover|address>).
func debug_sort_companies(by: String) -> void:
	_co_desc = not _co_desc if _co_sort == by else by in ["employees", "turnover"]
	_co_sort = by
	fill()


## Checks: open the strip's nth picture large, as clicking it does (--open=plot:<tunnus>#<n>).
func debug_enlarge(index: int) -> void:
	for strip in _pages["UI_BOOK_PLOT"].find_children("*", "PlotStrip", true, false):
		strip.enlarge(index)
		return


# ---------------------------------------------------------------- companies

## Every company of the tile with a plot, biggest employers first; a sector filter on top.
func _fill_companies() -> void:
	var body := _clear(_pages["UI_BOOK_COMPANIES"])
	var rows: Array = PlaceSearch.pack_list("tenants.json", "tenants").filter(func(r): return r.get("match") == "exact" and r.get("tunnus") != null)
	var sectors := {}
	for r in rows:
		if r.get("sector"):
			sectors[str(r.sector)] = sectors.get(str(r.sector), 0) + 1
	var bar := HFlowContainer.new()
	bar.add_theme_constant_override("h_separation", 6)
	body.add_child(bar)
	var all := Button.new()
	all.text = tr("UI_ALL") + " (%d)" % rows.size()
	all.theme_type_variation = "TextButton" if _sector_filter != "" else ""
	all.pressed.connect(func():
		_sector_filter = ""
		fill())
	bar.add_child(all)
	var keys := sectors.keys()
	keys.sort_custom(func(a, b): return sectors[a] > sectors[b])
	for k in keys:
		var b := Button.new()
		b.text = "%s (%d)" % [tr("SECTOR_" + str(k).to_upper()), sectors[k]]
		b.theme_type_variation = "TextButton" if _sector_filter != k else ""
		b.pressed.connect(func():
			_sector_filter = str(k)
			fill())
		bar.add_child(b)
	var shown: Array = rows.filter(func(r): return _sector_filter == "" or str(r.get("sector", "")) == _sector_filter)
	_sort_companies(shown)
	var grid := GridContainer.new()
	grid.columns = COMPANY_COLUMNS.size()
	grid.add_theme_constant_override("h_separation", 16)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	body.add_child(grid)
	# the headings sort the list: click one to sort by it, again to reverse
	for h in COMPANY_COLUMNS:
		var hb := Button.new()
		hb.flat = true
		hb.theme_type_variation = "ColumnLabel"
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			hb.add_theme_stylebox_override(st, StyleBoxEmpty.new())   # a button's padding would widen every column
		hb.add_theme_color_override("font_color", GOLD)
		hb.add_theme_color_override("font_hover_color", GOLD)
		hb.text = tr(h.key) + ("  ↓" if _co_sort == h.by and not _co_desc else ("  ↑" if _co_sort == h.by else ""))
		hb.alignment = HORIZONTAL_ALIGNMENT_RIGHT if h.right else HORIZONTAL_ALIGNMENT_LEFT
		hb.tooltip_text = tr("UI_BOOK_SORT_BY") % tr(h.key)
		var by: String = h.by
		var starts_desc: bool = h.right
		hb.pressed.connect(func():
			_co_desc = not _co_desc if _co_sort == by else starts_desc
			_co_sort = by
			_fill_companies())
		grid.add_child(hb)
	for r in shown.slice(0, MAX_ROWS):
		var nb := Button.new()
		nb.text = str(r.get("name", ""))
		var co_mark := _row_mark(str(r.get("tunnus", "")))
		nb.theme_type_variation = co_mark if co_mark != "" else "TextButton"
		nb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		nb.clip_text = true
		nb.custom_minimum_size = Vector2(280, 0)
		nb.tooltip_text = str(r.get("link", ""))
		nb.pressed.connect(func(): open_parcel(str(r.tunnus)))
		if str(r.get("health", "")) == "distressed":
			nb.add_theme_color_override("font_color", BookTheme.RUBRIC)
		grid.add_child(nb)
		var sl := _lbl(tr("SECTOR_" + str(r.get("sector", "")).to_upper()) if r.get("sector") else "-", 13)
		sl.clip_text = true
		sl.custom_minimum_size = Vector2(190, 0)
		grid.add_child(sl)
		var el := _lbl(str(int(r.employees)) if r.get("employees") != null and int(r.employees) > 0 else "-", 13)
		el.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		el.custom_minimum_size = Vector2(80, 0)
		grid.add_child(el)
		var tl := _lbl(BookTheme.money(int(r.turnover)) if r.get("turnover") != null and int(r.turnover) > 0 else "-", 13)
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		tl.custom_minimum_size = Vector2(130, 0)
		grid.add_child(tl)
		var al := _lbl(str(r.get("address", "")), 13)
		al.clip_text = true
		al.custom_minimum_size = Vector2(200, 0)
		grid.add_child(al)


## Order the company list by the chosen column. A missing figure is not a zero: it sorts last
## either way, so the rows the register says nothing about never head the page.
func _sort_companies(rows: Array) -> void:
	var num := func(r: Dictionary, field: String) -> float:
		var v = r.get(field)
		return -1.0 if v == null else float(v)
	var key := func(r: Dictionary) -> Variant:
		match _co_sort:
			"name": return str(r.get("name", "")).to_lower()
			"sector": return tr("SECTOR_" + str(r.get("sector", "")).to_upper()) if r.get("sector") else "\uffff"
			"employees": return num.call(r, "employees")
			"turnover": return num.call(r, "turnover")
			_: return _address_key(str(r.get("address", "")), str(r.get("name", "")))
	rows.sort_custom(func(a, b):
		var ka = key.call(a)
		var kb = key.call(b)
		if ka == kb:
			return str(a.get("name", "")).to_lower() < str(b.get("name", "")).to_lower()
		return kb < ka if _co_desc else ka < kb)



# ---------------------------------------------------------------- the place itself

## The pack's own page: where this square kilometre is, how much of it the registers know, what the
## land was valued at in 2022, and who every one of those figures belongs to.
func _fill_place() -> void:
	var body := _clear(_pages["UI_BOOK_PLACE"])
	var m := Sites.manifest
	var units := Parcels.units()
	var where: Array[String] = []
	for field in ["settlement", "municipality", "county"]:
		for u in units:
			var v := str(u.get(field, "") if u.get(field) != null else "")
			if v != "" and not (v in where):
				where.append(v)
				break
	body.add_child(_lbl(Sites.display_name(Sites.active), 22, GOLD))
	if not where.is_empty():
		body.add_child(_lbl(", ".join(where), 15))
	var terrain: Dictionary = m.get("terrain", {})
	var date: Array = terrain.get("date", []) if typeof(terrain) == TYPE_DICTIONARY else []
	if date.size() >= 3:
		body.add_child(_lbl(tr("UI_BOOK_VINTAGE") % ("%04d-%02d-%02d" % [int(date[0]), int(date[1]), int(date[2])]), 14))
	var companies: Array = PlaceSearch.pack_list("tenants.json", "tenants").filter(func(r): return r.get("match") == "exact")
	body.add_child(_lbl(tr("UI_BOOK_COUNTS") % [units.size(), PlaceSearch.pack_list("buildings.json", "buildings").size(), companies.size()], 15))
	_fill_values(body)
	body.add_child(_lbl("", 8))
	var sources := _lbl(tr("UI_BOOK_SOURCES"), 13, BookTheme.FADED)
	sources.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(sources)
	for line in _attributions():
		var a := _lbl("   " + line, 12, BookTheme.FADED)
		a.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(a)


## The 2022 valuation, by what the land is for: the median euro per square metre of the plots on
## this tile, and how many of them the median stands on (sites/<id>/market.json, make market).
func _fill_values(body: Node) -> void:
	var path := Sites.path("market.json")
	if not FileAccess.file_exists(path):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var by_purpose: Dictionary = parsed.get("by_purpose", {})
	if by_purpose.is_empty():
		return
	body.add_child(_lbl("", 8))
	body.add_child(_lbl(tr("UI_BOOK_VALUES") % int(parsed.get("valuation_year", 2022)), 15, GOLD))
	var keys := by_purpose.keys()
	# dearest land first, and the tile's own overall median last, under the purposes it is made of
	keys.sort_custom(func(a, b):
		if (a == "all") != (b == "all"):
			return b == "all"
		return float(by_purpose[a].get("median_eur_m2", 0)) > float(by_purpose[b].get("median_eur_m2", 0)))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	body.add_child(grid)
	for k in keys:
		var v: Dictionary = by_purpose[k]
		var pl := _lbl(tr("UI_ALL") if k == "all" else _purpose(str(k)), 13, GOLD if k == "all" else Color.WHITE)
		pl.custom_minimum_size = Vector2(320, 0)
		grid.add_child(pl)
		grid.add_child(_num("%.2f €/m²" % float(v.get("median_eur_m2", 0))))
		grid.add_child(_num(tr("UI_BOOK_OF_PLOTS") % int(v.get("n", 0))))


## Every "attribution" line the pack's data files carry, once each: the credits THIRD_PARTY.md says
## the game owes (the bus stops' OpenStreetMap credit is an ODbL condition), from the files that
## drew on each source. The tile's measured trees credit theirs as "source".
func _attributions() -> Array:
	var seen := {}
	var files := ["parcels.json", "buildings.json", "tenants.json", "roads.json", "market.json",
		"stops.json", "departures.json", "fields_2026.json"]
	var paths: Array = files.map(func(f): return [Sites.path(f), "attribution"])
	paths.append([Sites.tile_dir() + "/trees.json", "source"])
	for pk in paths:
		if not FileAccess.file_exists(pk[0]):
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(pk[0]))
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		for line in _lines_of(parsed.get(pk[1], "")):
			seen[line] = true
	return seen.keys()


## An "attribution" field as lines. The files write it three ways: one string, a list of them, or a
## dictionary of source name to credit (buildings.json credits ETAK, the register and the LOD2 roofs
## separately), and a dictionary printed whole is unreadable.
static func _lines_of(a: Variant) -> Array:
	var out: Array = []
	match typeof(a):
		TYPE_DICTIONARY:
			for k in a:
				out.append_array(_lines_of(a[k]))
		TYPE_ARRAY:
			for v in a:
				out.append_array(_lines_of(v))
		_:
			if str(a).strip_edges() != "":
				out.append(str(a))
	return out


# ---------------------------------------------------------------- helpers

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


## A figure cell: right-aligned so the euro columns line up.
func _num(text: String) -> Label:
	var l := _lbl(text, 13)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## A link out to the register the row came from - the cadastre for a plot, the Business Register for
## a company. The address is copied to the clipboard as well as opened, because a browser that is not
## running yet sometimes swallows the first shell_open.
func _link_button(parent: Node, url: String, label: String) -> Button:
	if url == "":
		return null
	var b := Button.new()
	b.theme_type_variation = "TextButton"
	b.text = label
	b.tooltip_text = url
	b.pressed.connect(func():
		DisplayServer.clipboard_set(url)
		OS.shell_open(url))
	parent.add_child(b)
	return b


## "Guide" points the HUD arrow at the plot; "Go" jumps there (the teleport, like T and the map).
func _nav_buttons(tunnus: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	var g := Button.new()
	g.theme_type_variation = "TextButton"
	g.text = tr("BTN_GUIDE")
	g.tooltip_text = tr("BTN_GUIDE_TIP")
	g.pressed.connect(func(): guide.emit(tunnus))
	h.add_child(g)
	var t := Button.new()
	t.theme_type_variation = "TextButton"
	t.text = tr("BTN_TELEPORT")
	t.tooltip_text = tr("BTN_TELEPORT_TIP")
	t.pressed.connect(func(): teleport.emit(tunnus))
	h.add_child(t)
	var f := Button.new()
	f.theme_type_variation = "TextButton"
	f.text = tr("BTN_FOCUS")
	f.tooltip_text = tr("BTN_FOCUS_TIP")
	f.pressed.connect(func(): focus.emit(tunnus))
	h.add_child(f)
	return h


func _purpose(code: String) -> String:
	var key := "PURPOSE_" + code
	var t := tr(key)
	return t if t != key else code
