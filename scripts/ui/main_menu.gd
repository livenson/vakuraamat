# Main menu: continue / new game, the Locations panel (packs you have, packs ready on the tile
# service, suggested places to generate, a place search, friends' worlds), language, fullscreen.
extends Control

const SUGGESTED := "res://assets/data/suggested_places.json"

@onready var box: VBoxContainer = $Box

var _picked: Dictionary = {}
var _status: Label
var _results: VBoxContainer
var _name_edit: LineEdit
var _query: LineEdit
var _code_edit: LineEdit
var _service_box: VBoxContainer


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if "--locations" in OS.get_cmdline_user_args():
		GameState.menu_open_locations = true
	if GameState.menu_open_locations:
		GameState.menu_open_locations = false
		_build_locations_panel()
	else:
		_build()


func _clear() -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _build() -> void:
	_clear()
	var title := Label.new()
	title.text = "Vakuraamat"
	title.add_theme_font_size_override("font_size", 56)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := Label.new()
	sub.text = tr(str(Sites.get_value("subtitle_key", "MENU_SUBTITLE")))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	var where := Label.new()
	where.text = "%s: %s" % [tr("MENU_SITE"), Sites.display_name(Sites.active)]
	if Friends.visiting_code != "":
		where.text += "   " + tr("MENU_VISITING") % [Friends.visiting_owner, Friends.visiting_code]
	where.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	where.add_theme_font_size_override("font_size", 14)
	box.add_child(where)
	box.add_child(Control.new())
	if SaveManager.has_save():
		_button("UI_CONTINUE_GAME", func():
			var saved := SaveManager.saved_site()
			if saved != "" and saved != Sites.active:
				Sites.select(saved)
			GameState.pending_load = true
			get_tree().change_scene_to_file("res://scenes/world/world.tscn"))
	_button("UI_NEW_GAME", func(): _start_new_game())
	_button("MENU_LOCATIONS", _build_locations_panel)
	_button("MENU_LANGUAGE", func():
		TranslationServer.set_locale("en" if TranslationServer.get_locale().begins_with("et") else "et")
		_build())
	var fs := Button.new()
	fs.toggle_mode = true
	fs.add_theme_font_size_override("font_size", 24)
	fs.custom_minimum_size = Vector2(320, 44)
	var relabel := func(on: bool):
		fs.set_pressed_no_signal(on)
		fs.text = "%s: %s  (%s)" % [tr("MENU_FULLSCREEN"), tr("MENU_ON") if on else tr("MENU_OFF"), WindowMode.shortcut_text()]
	relabel.call(WindowMode.is_fullscreen())
	fs.toggled.connect(func(on: bool): WindowMode.set_fullscreen(on))
	WindowMode.changed.connect(relabel)
	box.add_child(fs)
	_button("UI_QUIT", func(): get_tree().quit())
	var credit := Label.new()
	credit.text = tr("MENU_CREDIT")
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	credit.add_theme_font_size_override("font_size", 13)
	box.add_child(credit)


func _start_new_game(site_id: String = "") -> void:
	if site_id != "" and site_id != Sites.active:
		Sites.select(site_id)
	Friends.stop_visiting()
	GameState.reset()
	get_tree().change_scene_to_file("res://scenes/world/world.tscn")


func _button(key: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = tr(key)
	b.add_theme_font_size_override("font_size", 24)
	b.custom_minimum_size = Vector2(320, 44)
	b.pressed.connect(cb)
	box.add_child(b)


# ---------------------------------------------------------------- Locations
func _build_locations_panel() -> void:
	_clear()
	_picked = {}
	var title := Label.new()
	title.text = tr("MENU_LOCATIONS").trim_suffix("...")
	title.add_theme_font_size_override("font_size", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(760, 560)
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
	var hint := Label.new()
	hint.text = tr("MENU_LOCATION_HINT")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 13)
	list.add_child(hint)
	var srow := HBoxContainer.new()
	list.add_child(srow)
	_query = LineEdit.new()
	_query.placeholder_text = "Kvissentali tee, Tartu"
	_query.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_query.text_submitted.connect(func(_t): _search())
	srow.add_child(_query)
	_small(srow, "MENU_SEARCH", _search)
	_small(srow, "MENU_USE_MY_LOCATION", _use_my_location)
	_results = VBoxContainer.new()
	list.add_child(_results)
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

	# --- friends
	_section(list, "MENU_FRIENDS")
	var frow := HBoxContainer.new()
	list.add_child(frow)
	var code := Friends.my_code(Sites.active)
	var share := Button.new()
	share.text = tr("MENU_WORLD_CODE") % code if code != "" else tr("MENU_SHARE_WORLD")
	share.add_theme_font_size_override("font_size", 16)
	share.pressed.connect(func():
		_status.text = "..."
		var res: Dictionary = await Friends.publish()
		if res.ok:
			share.text = tr("MENU_WORLD_CODE") % res.code
			DisplayServer.clipboard_set(res.code)
			_status.text = tr("MENU_WORLD_CODE") % res.code
		else:
			_status.text = str(res.error))
	frow.add_child(share)
	var vl := Label.new()
	vl.text = "   " + tr("MENU_VISIT") + ": "
	frow.add_child(vl)
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "ABC234"
	_code_edit.custom_minimum_size = Vector2(110, 0)
	_code_edit.max_length = 6
	frow.add_child(_code_edit)
	_small(frow, "MENU_VISIT_GO", func():
		_status.text = "..."
		var cb := func(t: String): _status.text = t
		Friends.status.connect(cb)
		Locator.progress.connect(cb)
		var res: Dictionary = await Friends.visit(_code_edit.text)
		Friends.status.disconnect(cb)
		Locator.progress.disconnect(cb)
		if not res.ok:
			_status.text = str(res.error)
			return
		GameState.reset()
		get_tree().change_scene_to_file("res://scenes/world/world.tscn"))

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(700, 0)
	box.add_child(_status)
	_button("MENU_BACK", _build)


func _fmt_center(c: Array) -> String:
	return "%d %d" % [int(c[0]), int(c[1])] if c.size() == 2 else "?"


func _section(list: VBoxContainer, key: String) -> void:
	var l := Label.new()
	l.text = tr(key)
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", Color(0.85, 0.68, 0.25))
	list.add_child(l)


func _row(list: VBoxContainer, name: String, detail: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	list.add_child(row)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	var n := Label.new()
	n.text = name
	n.add_theme_font_size_override("font_size", 18)
	v.add_child(n)
	var d := Label.new()
	d.text = detail
	d.add_theme_font_size_override("font_size", 12)
	d.modulate = Color(0.8, 0.8, 0.8)
	v.add_child(d)
	return row


func _row_button(row: HBoxContainer, key: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = tr(key)
	b.add_theme_font_size_override("font_size", 15)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(cb)
	row.add_child(b)


func _small(parent: Node, key: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = tr(key)
	b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(cb)
	parent.add_child(b)


func _fill_service_packs() -> void:
	var alive: bool = await Locator.service_alive()
	if not is_instance_valid(_service_box):
		return
	for c in _service_box.get_children():
		c.queue_free()
	if not alive:
		var l := Label.new()
		l.text = tr("MENU_SERVICE_DOWN") % Locator.service_url()
		l.add_theme_font_size_override("font_size", 13)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_service_box.add_child(l)
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
		b.text = "%s   (%d, %d)" % [r.name, r.x, r.y]
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(func():
			_picked = r
			_name_edit.text = str(r.name).split(",")[-1].strip_edges() if "," in str(r.name) else str(r.name)
			_status.text = "%s: %d, %d" % [r.name, r.x, r.y])
		_results.add_child(b)


func _search() -> void:
	_status.text = "..."
	var results: Array = await Locator.geocode(_query.text)
	_show_results(results)
	if results.size() == 1:
		_picked = results[0]
		_name_edit.text = str(results[0].name).split(",")[-1].strip_edges()


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
	_picked = d
	_name_edit.text = str(d.name).split(",")[0].strip_edges()


## Generate (or fetch from the service cache) a pack for a place and start a new game there.
func _create(name: String, x: float, y: float, id_override: String = "") -> void:
	var cb := func(t: String): _status.text = t
	Locator.progress.connect(cb)
	_status.text = tr("MENU_GENERATING") % "..."
	var res: Dictionary = await Locator.create_world(name, x, y, 1024, "1798,1938,2026", id_override)
	Locator.progress.disconnect(cb)
	if not res.ok:
		_status.text = str(res.error)
		return
	_status.text = tr("MENU_WORLD_READY")
	_start_new_game(res.id)
