# Main menu: the first page of the book. A rubric rule down the margin, the running head (the place,
# the saved book's month and cash), the menu as ruled entries with their detail in the right column,
# and the plate: the pack's square kilometre with its cadastral units drawn over the orthophoto.
# The Locations page (packs you have, packs on the tile service, suggested places, a search, the town)
# is the second page.
extends Control

const SUGGESTED := "res://assets/data/suggested_places.json"
const MARGIN := 72.0

var box: VBoxContainer          # the left column (menu) or the page body (locations)
var _page: Control
var _picked: Dictionary = {}
var _status: Label
var _results: VBoxContainer
var _name_edit: LineEdit
var _query: LineEdit
var _service_box: VBoxContainer
var _estimate: Label
var _suggest_timer: Timer
var _suggest_serial := 0
var _storage_box: VBoxContainer


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	theme = BookTheme.theme()
	if "--locations" in OS.get_cmdline_user_args():
		GameState.menu_open_locations = true
	if GameState.menu_open_locations:
		GameState.menu_open_locations = false
		_build_locations_panel()
	else:
		_build()


## A fresh page: paper, grain, the rubric margin rule; returns the body area right of the margin.
func _new_page() -> MarginContainer:
	if _page:
		_page.queue_free()
	_page = Control.new()
	_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_page)
	var paper := ColorRect.new()
	paper.color = BookTheme.PAGE
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_page.add_child(paper)
	var grain := TextureRect.new()
	grain.texture = BookTheme.grain()
	grain.stretch_mode = TextureRect.STRETCH_TILE
	grain.modulate = Color(0.3, 0.25, 0.15, 0.07)
	grain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page.add_child(grain)
	var rubric := ColorRect.new()
	rubric.color = Color(BookTheme.RUBRIC, 0.8)
	rubric.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	rubric.offset_left = MARGIN
	rubric.offset_right = MARGIN + 1.5
	_page.add_child(rubric)
	var credit := BookTheme.label(tr("MENU_CREDIT"), "DetailLabel")
	credit.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 24)
	credit.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	credit.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_page.add_child(credit)
	var body := MarginContainer.new()
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.add_theme_constant_override("margin_left", int(MARGIN) + 28)
	body.add_theme_constant_override("margin_right", 48)
	body.add_theme_constant_override("margin_top", 44)
	body.add_theme_constant_override("margin_bottom", 56)
	_page.add_child(body)
	return body


func _build() -> void:
	var body := _new_page()
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 56)
	body.add_child(columns)
	box = VBoxContainer.new()
	box.custom_minimum_size = Vector2(520, 0)
	box.size_flags_horizontal = Control.SIZE_FILL
	box.add_theme_constant_override("separation", 0)
	columns.add_child(box)
	BookTheme.label("Vakuraamat", "TitleLabel", box)
	BookTheme.label(tr(str(Sites.get_value("subtitle_key", "MENU_SUBTITLE"))), "ProseLabel", box)
	var summary := SaveManager.summary()
	var saved_here: bool = not summary.is_empty() and summary.site == Sites.active
	var head := BookTheme.label(Sites.display_name(Sites.active), "DetailLabel", box)
	head.add_theme_font_size_override("font_size", 15)
	if saved_here:
		head.text += "   " + _book_line(summary)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 28)
	box.add_child(gap)
	if not summary.is_empty():
		_entry("UI_CONTINUE_GAME", (Sites.display_name(summary.site) + ", " if not saved_here else "") + _book_line(summary), func():
			if summary.site != "" and summary.site != Sites.active and Sites.available.has(summary.site):
				Sites.select(summary.site)
			GameState.pending_load = true
			get_tree().change_scene_to_file("res://scenes/world/world.tscn"))
	_entry("UI_NEW_GAME", Sites.display_name(Sites.active), func(): _start_new_game())
	_entry("MENU_LOCATIONS", tr("MENU_PACKS_COUNT") % Sites.available.size(), _build_locations_panel)
	_entry("MENU_LANGUAGE", "English" if TranslationServer.get_locale().begins_with("et") else "Eesti", func():
		TranslationServer.set_locale("en" if TranslationServer.get_locale().begins_with("et") else "et")
		_build())
	var fs := _entry("MENU_FULLSCREEN", "", func(): WindowMode.set_fullscreen(not WindowMode.is_fullscreen()))
	var relabel := func(on: bool):
		if is_instance_valid(fs):
			fs.get_child(0).text = "%s   %s" % [tr("MENU_ON") if on else tr("MENU_OFF"), WindowMode.shortcut_text()]
	relabel.call(WindowMode.is_fullscreen())
	WindowMode.changed.connect(relabel, CONNECT_REFERENCE_COUNTED)
	fs.tree_exiting.connect(func(): WindowMode.changed.disconnect(relabel))
	_entry("UI_QUIT", "", func(): get_tree().quit())
	var plate := MapPlate.new()
	plate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plate.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_child(plate)
	plate.setup(Sites.active, summary.get("owned", []) if saved_here else [])


## "October 2026, 250 000 €" for a saved book (the town's name when the book is online).
func _book_line(summary: Dictionary) -> String:
	var when := Ledger.date_for(int(summary.get("month", 0)), str(summary.get("site", "")))
	if str(summary.get("backend", "local")) == "town":
		return "%s, %s" % [when, tr("UI_ONLINE_BADGE")]
	var cash := int(summary.get("cash", -1))
	return when if cash < 0 else "%s, %s" % [when, BookTheme.money(cash)]


## A ruled ledger entry: the action on the left, its detail in the right column.
func _entry(key: String, detail: String, cb: Callable) -> Button:
	var b := Button.new()
	b.theme_type_variation = "RowButton"
	b.text = tr(key)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 50)
	b.pressed.connect(cb)
	var d := BookTheme.label(detail, "DetailLabel")
	d.add_theme_font_size_override("font_size", 15)
	d.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	d.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	d.grow_vertical = Control.GROW_DIRECTION_BOTH
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(d)
	box.add_child(b)
	return b


func _start_new_game(site_id: String = "") -> void:
	if site_id != "" and site_id != Sites.active:
		Sites.select(site_id)
	GameState.reset()
	get_tree().change_scene_to_file("res://scenes/world/world.tscn")


func _button(key: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = tr(key)
	b.pressed.connect(cb)
	box.add_child(b)


# ---------------------------------------------------------------- Locations
func _build_locations_panel() -> void:
	var body := _new_page()
	_picked = {}
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	body.add_child(box)
	var title := BookTheme.label(tr("MENU_LOCATIONS").trim_suffix("..."), "TitleLabel", box)
	title.add_theme_font_size_override("font_size", 40)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	# --- what you have
	_section(list, "MENU_AVAILABLE")
	var saved := SaveManager.saved_site()
	for id in Sites.available:
		if _is_tile_pack(id):
			continue   # streamed neighbour tiles are ground, not worlds to start in (see Storage)
		var m := Sites.manifest_for(id)
		var t: Dictionary = m.get("terrain", {})
		var tags := [tr("MENU_INSTALLED") if Sites.is_user_pack(id) else tr("MENU_SHIPPED")]
		if id == Sites.active:
			tags.append(tr("MENU_CURRENT"))
		var story: Dictionary = m.get("story", {})
		var detail := "L-EST97 %s   %s" % [_fmt_center(t.get("center", [])), ", ".join(tags)]
		if not story.is_empty():
			detail += "   " + ", ".join(story.get("blocks", []))
		var row := _row(list, Sites.display_name(id), detail)
		if saved == id:
			_row_button(row, "UI_CONTINUE_GAME", func():
				Sites.select(id)
				GameState.pending_load = true
				get_tree().change_scene_to_file("res://scenes/world/world.tscn"))
		_row_button(row, "MENU_PLAY", func(): _start_new_game(id))

	# --- ready on the tile service (filled in when it answers)
	_section(list, "MENU_ON_SERVICE")
	_service_box = VBoxContainer.new()
	list.add_child(_service_box)
	var waiting := Label.new()
	waiting.text = "..."
	_service_box.add_child(waiting)
	_fill_service_packs()

	# --- suggested places
	_section(list, "MENU_SUGGESTED")
	var text := FileAccess.get_file_as_string(SUGGESTED)
	var places = JSON.parse_string(text) if text != "" else []
	var et := TranslationServer.get_locale().begins_with("et")
	for p in (places if typeof(places) == TYPE_ARRAY else []):
		var row := _row(list, str(p.name), "%s   L-EST97 %d %d" % [str(p.get("note_et" if et else "note_en", "")), int(p.x), int(p.y)])
		_row_button(row, "MENU_CREATE", func(): _create(str(p.name), float(p.x), float(p.y)))

	# --- search
	_section(list, "MENU_SEARCH_PLACES")
	var hint := BookTheme.label(tr("MENU_LOCATION_HINT"), "DetailLabel", list)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var srow := HBoxContainer.new()
	list.add_child(srow)
	_query = LineEdit.new()
	_query.placeholder_text = "Kvissentali tee, Tartu"
	_query.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_query.text_submitted.connect(func(_t): _search())
	_query.text_changed.connect(_on_query_changed)   # suggestions while typing
	srow.add_child(_query)
	_small(srow, "MENU_SEARCH", _search)
	_small(srow, "MENU_USE_MY_LOCATION", _use_my_location)
	_results = VBoxContainer.new()
	list.add_child(_results)
	_estimate = BookTheme.label("", "DetailLabel", list)
	_estimate.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var nrow := HBoxContainer.new()
	list.add_child(nrow)
	var nl := Label.new()
	nl.text = tr("MENU_LOCATION_NAME") + ": "
	nrow.add_child(nl)
	_name_edit = LineEdit.new()
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nrow.add_child(_name_edit)
	_small(nrow, "MENU_CREATE_WORLD", func():
		if _picked.is_empty():
			_status.text = tr("MENU_NO_RESULTS")
			return
		var n := _name_edit.text.strip_edges()
		_create(n if n != "" else str(_picked.name), float(_picked.x), float(_picked.y)))

	# --- storage: what created worlds and streamed tiles take on disk, and how to drop them
	_section(list, "MENU_STORAGE")
	_storage_box = VBoxContainer.new()
	_storage_box.add_theme_constant_override("separation", 6)
	list.add_child(_storage_box)
	_fill_storage()

	# --- town (the shared ledger)
	_section(list, "MENU_TOWN")
	var trow := HBoxContainer.new()
	list.add_child(trow)
	var town_db := Ledger.db_name_for(Sites.active)
	var town_url := str(Ledger.setting("town", "url", Ledger.DEFAULT_TOWN_URL))
	BookTheme.label(tr("MENU_TOWN_ADDRESS") % [town_url, town_db], "", trow)
	_small(trow, "MENU_COPY", func():
		DisplayServer.clipboard_set("%s %s" % [town_url, town_db])
		_status.text = tr("MENU_COPIED"))
	var urow := HBoxContainer.new()
	list.add_child(urow)
	var ul := Label.new()
	ul.text = tr("MENU_TOWN_URL") + ": "
	urow.add_child(ul)
	var url_edit := LineEdit.new()
	url_edit.text = town_url
	url_edit.custom_minimum_size = Vector2(300, 0)
	urow.add_child(url_edit)
	_small(urow, "MENU_SAVE", func():
		var cfg := ConfigFile.new()
		cfg.load(Sites.SETTINGS)
		cfg.set_value("town", "url", url_edit.text.strip_edges())
		cfg.save(Sites.SETTINGS)
		_status.text = tr("MENU_SAVED"))
	var offline := CheckButton.new()
	offline.text = tr("MENU_PLAY_OFFLINE")
	offline.button_pressed = bool(Ledger.setting("town", "offline", false))
	offline.toggled.connect(func(on: bool):
		var cfg := ConfigFile.new()
		cfg.load(Sites.SETTINGS)
		cfg.set_value("town", "offline", on)
		cfg.save(Sites.SETTINGS))
	urow.add_child(offline)

	_status = BookTheme.label("", "DetailLabel", box)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var back := Button.new()
	back.text = tr("MENU_BACK")
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(_build)
	box.add_child(back)


func _fmt_center(c: Array) -> String:
	return "%d %d" % [int(c[0]), int(c[1])] if c.size() == 2 else "?"


func _section(list: VBoxContainer, key: String) -> void:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	list.add_child(gap)
	BookTheme.label(tr(key), "HeadLabel", list)
	BookTheme.rule(list)


func _row(list: VBoxContainer, name: String, detail: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	list.add_child(row)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	var n := BookTheme.label(name, "", v)
	n.add_theme_font_size_override("font_size", 17)
	BookTheme.label(detail, "DetailLabel", v)
	return row


func _row_button(row: HBoxContainer, key: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = tr(key)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if key in ["MENU_PLAY", "UI_CONTINUE_GAME", "MENU_INSTALL_PLAY"]:
		b.theme_type_variation = "PrimaryButton"
	b.pressed.connect(cb)
	row.add_child(b)


func _small(parent: Node, key: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = tr(key)
	b.pressed.connect(cb)
	parent.add_child(b)


func _fill_service_packs() -> void:
	var alive: bool = await Locator.ensure_service()
	if not is_instance_valid(_service_box):
		return
	for c in _service_box.get_children():
		c.queue_free()
	if not alive:
		var l := BookTheme.label(tr("MENU_SERVICE_DOWN") % Locator.service_url(), "DetailLabel", _service_box)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		return
	var packs: Array = await Locator.list_service_packs()
	if not is_instance_valid(_service_box):
		return
	var shown := 0
	for p in packs:
		if Sites.available.has(str(p.id)):
			continue
		var row := _row(_service_box, str(p.name), "L-EST97 %d %d   %s" % [int(p.x), int(p.y), ", ".join(p.get("blocks", []) if p.get("blocks") != null else [])])
		_row_button(row, "MENU_INSTALL_PLAY", func(): _create(str(p.name), float(p.x), float(p.y), str(p.id)))
		shown += 1
	if shown == 0:
		var l := Label.new()
		l.text = "-"
		_service_box.add_child(l)


func _show_results(results: Array) -> void:
	for c in _results.get_children():
		c.queue_free()
	if results.is_empty():
		_status.text = tr("MENU_NO_RESULTS")
		return
	for r in results.slice(0, 6):
		var b := Button.new()
		b.theme_type_variation = "TextButton"
		b.text = "%s   (%d, %d)" % [r.name, r.x, r.y]
		b.pressed.connect(func():
			_pick(r)
			_status.text = "%s: %d, %d" % [r.name, r.x, r.y])
		_results.add_child(b)


## A chosen place: the name field follows it and the service estimates its download.
func _pick(r: Dictionary) -> void:
	_picked = r
	_name_edit.text = str(r.name).split(",")[-1].strip_edges() if "," in str(r.name) else str(r.name)
	_show_estimate(float(r.x), float(r.y))


func _show_estimate(x: float, y: float) -> void:
	if not is_instance_valid(_estimate):
		return
	_estimate.text = tr("MENU_ESTIMATING")
	var e: Dictionary = await Locator.estimate(x, y)
	if not is_instance_valid(_estimate) or _picked.is_empty() or float(_picked.x) != x:
		return
	if e.is_empty():
		_estimate.text = tr("MENU_ESTIMATE_UNKNOWN")
		return
	var free := Locator.free_bytes()
	var total := float(e.get("seconds_download", 0)) + float(e.get("seconds_process", 0))
	_estimate.text = tr("MENU_ESTIMATE") % [Locator.fmt_bytes(float(e.get("bytes", 0))), Locator.fmt_bytes(float(e.get("cached_bytes", 0))),
		Locator.fmt_seconds(total), Locator.fmt_seconds(float(e.get("seconds_download", 0))), Locator.fmt_seconds(float(e.get("seconds_process", 0))),
		Locator.fmt_bytes(float(free)) if free >= 0 else "?"]
	if free >= 0 and free < Locator.MIN_FREE_BYTES:
		_estimate.text += "  " + tr("MENU_LOW_DISK") % [Locator.fmt_bytes(float(free)), Locator.fmt_bytes(float(Locator.MIN_FREE_BYTES))]


## Suggestions while typing: a short pause after the last key, then the gazetteer; late answers to
## an older query are dropped.
func _on_query_changed(text: String) -> void:
	if _suggest_timer == null:
		_suggest_timer = Timer.new()
		_suggest_timer.one_shot = true
		_suggest_timer.wait_time = 0.35
		add_child(_suggest_timer)
		_suggest_timer.timeout.connect(_suggest)
	if text.strip_edges().length() < 3:
		return
	_suggest_timer.start()


func _suggest() -> void:
	_suggest_serial += 1
	var serial := _suggest_serial
	var q := _query.text
	var results: Array = await Locator.geocode(q)
	if serial != _suggest_serial or not is_instance_valid(_results) or _query.text != q:
		return
	if not results.is_empty():
		_show_results(results)


func _search() -> void:
	_status.text = "..."
	_suggest_serial += 1   # a submitted search outranks pending suggestions
	var results: Array = await Locator.geocode(_query.text)
	_show_results(results)
	if results.size() == 1:
		_pick(results[0])


func _use_my_location() -> void:
	_status.text = "..."
	var d: Dictionary = await Locator.locate_by_ip()
	if not d.get("ok", false):
		_status.text = tr("MENU_NO_RESULTS")
		return
	if not Locator.in_estonia(d.x, d.y):
		_status.text = tr("MENU_OUTSIDE_ESTONIA") + "  (%s)" % d.name
		return
	_show_results([d])
	_pick(d)
	_name_edit.text = str(d.name).split(",")[0].strip_edges()


## The storage section: each installed world with its size and a Remove button (two presses),
## the streamed neighbour tiles as one line, the service's cache, and the free space.
func _fill_storage() -> void:
	for c in _storage_box.get_children():
		c.queue_free()
	var worlds := 0
	var tiles := 0
	var tile_ids: Array[String] = []
	for id in Sites.available:
		if not Sites.is_user_pack(id):
			continue
		var n: int = Locator.pack_bytes(id).total
		if _is_tile_pack(id):
			tiles += n
			tile_ids.append(id)
			continue
		worlds += n
		var row := _row(_storage_box, Sites.display_name(id), Locator.fmt_bytes(float(n)) + ("   " + tr("MENU_CURRENT") if id == Sites.active else ""))
		if id != Sites.active:
			_remove_button(row, [id])
	if not tile_ids.is_empty():
		var row := _row(_storage_box, tr("MENU_NEIGHBOUR_TILES") % tile_ids.size(), Locator.fmt_bytes(float(tiles)))
		_remove_button(row, tile_ids, "MENU_DELETE_ALL_TILES")
	var free := Locator.free_bytes()
	var line := BookTheme.label(tr("MENU_STORAGE_LINE") % [Locator.fmt_bytes(float(worlds)), Locator.fmt_bytes(float(tiles)), Locator.fmt_bytes(float(free)) if free >= 0 else "?"], "DetailLabel", _storage_box)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var cache: Dictionary = await Locator.service_cache()
	if is_instance_valid(line) and not cache.is_empty():
		line.text += "\n" + tr("MENU_SERVICE_CACHE") % [Locator.fmt_bytes(float(cache.get("bytes", 0))), str(cache.get("path", ""))]


## A pack the streamer fetched for a neighbouring tile: t<E>_<N>.
static func _is_tile_pack(id: String) -> bool:
	return id.begins_with("t") and id.substr(1).replace("_", "").is_valid_int()


## Remove asks twice: the first press turns the button into "Really remove".
func _remove_button(row: HBoxContainer, ids: Array, key: String = "MENU_DELETE") -> void:
	var b := Button.new()
	b.text = tr(key)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.set_meta("armed", false)
	b.pressed.connect(func():
		if not b.get_meta("armed"):
			b.set_meta("armed", true)
			b.text = tr("MENU_CONFIRM_DELETE")
			return
		for id in ids:
			Locator.remove_pack(id)
		_status.text = tr("MENU_REMOVED")
		_fill_storage())
	row.add_child(b)


## Generate (or fetch from the service cache) a pack for a place and start a new game there.
## The page is frozen under a progress sheet until the world is ready or the job fails.
func _create(name: String, x: float, y: float, id_override: String = "") -> void:
	var sheet := _progress_sheet(name)
	var cb := func(text: String, f: float): sheet.get_meta("stage").call(text, f)
	Locator.progress.connect(cb)
	var res: Dictionary = await Locator.create_world(name, x, y, 1024, "2026", id_override)
	Locator.progress.disconnect(cb)
	if not is_instance_valid(sheet):
		return
	if not res.ok:
		sheet.get_meta("fail").call(str(res.error))
		return
	sheet.get_meta("stage").call(tr("MENU_WORLD_READY"), 1.0)
	_status.text = tr("MENU_WORLD_READY")
	await get_tree().create_timer(0.4).timeout
	_start_new_game(res.id)


## A modal sheet over the page: the heading, a note on what is fetched, the stage line, a bar and the
## elapsed time. Blocks the page (input and focus) while it is up; `stage(text, f)` advances it,
## `fail(error)` turns it into an error notice with a Close button that thaws the page.
func _progress_sheet(name: String) -> Control:
	var page := _page
	page.process_mode = Node.PROCESS_MODE_DISABLED
	get_viewport().gui_release_focus()
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.focus_mode = Control.FOCUS_ALL
	add_child(overlay)
	var tint := ColorRect.new()
	tint.color = Color(BookTheme.INK, 0.32)
	tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(tint)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", BookTheme.page_box(true, 32))
	panel.custom_minimum_size = Vector2(620, 0)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	overlay.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	var head := BookTheme.label(tr("MENU_GENERATING") % name, "HeadLabel", col)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var note := BookTheme.label(tr("MENU_CREATE_NOTE"), "DetailLabel", col)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	col.add_child(gap)
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 10)
	bar.add_theme_stylebox_override("background", BookTheme.box(BookTheme.PAGE_DARK, BookTheme.INK, 1))
	bar.add_theme_stylebox_override("fill", BookTheme.box(BookTheme.BLUE))
	col.add_child(bar)
	var row := HBoxContainer.new()
	col.add_child(row)
	var stage := BookTheme.label("...", "ProseLabel", row)
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var figures := BookTheme.label("0 %   0:00", "ColumnLabel", row)
	figures.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var error := BookTheme.label("", "ProseLabel", col)
	error.add_theme_color_override("font_color", BookTheme.RUBRIC)
	error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error.visible = false
	var close := Button.new()
	close.text = tr("UI_CLOSE")
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.visible = false
	close.pressed.connect(func():
		if is_instance_valid(page):
			page.process_mode = Node.PROCESS_MODE_INHERIT
		overlay.queue_free())
	col.add_child(close)
	var started := Time.get_ticks_msec()
	var frac := [0.0]
	var refresh := func():
		var secs := int((Time.get_ticks_msec() - started) / 1000)
		figures.text = "%d %%   %d:%02d" % [int(round(frac[0] * 100.0)), secs / 60, secs % 60]
	var tick := Timer.new()
	tick.wait_time = 1.0
	tick.autostart = true
	tick.timeout.connect(refresh)
	overlay.add_child(tick)
	overlay.set_meta("stage", func(text: String, f: float):
		stage.text = text
		frac[0] = maxf(frac[0], f)
		create_tween().tween_property(bar, "value", frac[0], 0.4)
		refresh.call())
	overlay.set_meta("fail", func(text: String):
		tick.stop()
		stage.text = tr("MENU_CREATE_FAILED")
		error.text = text
		error.visible = true
		close.visible = true
		close.grab_focus())
	overlay.grab_focus()
	return overlay
