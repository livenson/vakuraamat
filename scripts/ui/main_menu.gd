extends Control

@onready var box: VBoxContainer = $Box


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build()


func _build() -> void:
	for c in box.get_children():
		c.queue_free()
	var title := Label.new()
	title.text = "Vakuraamat"
	title.add_theme_font_size_override("font_size", 56)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := Label.new()
	sub.text = tr(str(Sites.get_value("subtitle_key", "MENU_SUBTITLE")))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	box.add_child(Control.new())
	if SaveManager.has_save():
		_button("UI_CONTINUE_GAME", func():
			var saved := SaveManager.saved_site()
			if saved != "" and saved != Sites.active:
				Sites.select(saved)
			GameState.pending_load = true
			get_tree().change_scene_to_file("res://scenes/world/world.tscn"))
	_button("UI_NEW_GAME", func():
		GameState.reset()
		get_tree().change_scene_to_file("res://scenes/world/world.tscn"))
	if Sites.available.size() > 1:
		var sb := Button.new()
		sb.text = "%s: %s" % [tr("MENU_SITE"), tr(Sites.name_key(Sites.active))]
		sb.add_theme_font_size_override("font_size", 24)
		sb.custom_minimum_size = Vector2(320, 44)
		sb.pressed.connect(func():
			var i := Sites.available.find(Sites.active)
			Sites.select(Sites.available[(i + 1) % Sites.available.size()])
			_build())
		box.add_child(sb)
	_button("MENU_NEW_LOCATION", _build_location_panel)
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


func _button(key: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = tr(key)
	b.add_theme_font_size_override("font_size", 24)
	b.custom_minimum_size = Vector2(320, 44)
	b.pressed.connect(cb)
	box.add_child(b)


# ---------------------------------------------------------------- new location (tile service)
var _picked: Dictionary = {}
var _loc_status: Label
var _loc_results: VBoxContainer
var _loc_name: LineEdit
var _loc_query: LineEdit


func _build_location_panel() -> void:
	for c in box.get_children():
		c.queue_free()
	_picked = {}
	var title := Label.new()
	title.text = tr("MENU_NEW_LOCATION").trim_suffix("...")
	title.add_theme_font_size_override("font_size", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var hint := Label.new()
	hint.text = tr("MENU_LOCATION_HINT")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(520, 0)
	box.add_child(hint)
	_loc_query = LineEdit.new()
	_loc_query.custom_minimum_size = Vector2(520, 40)
	_loc_query.placeholder_text = "Kvissentali tee, Tartu"
	_loc_query.text_submitted.connect(func(_t): _search())
	box.add_child(_loc_query)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	_small(row, "MENU_SEARCH", _search)
	_small(row, "MENU_USE_MY_LOCATION", _use_my_location)
	_loc_results = VBoxContainer.new()
	box.add_child(_loc_results)
	var nrow := HBoxContainer.new()
	nrow.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(nrow)
	var nl := Label.new()
	nl.text = tr("MENU_LOCATION_NAME") + ": "
	nrow.add_child(nl)
	_loc_name = LineEdit.new()
	_loc_name.custom_minimum_size = Vector2(300, 36)
	nrow.add_child(_loc_name)
	_small(nrow, "MENU_CREATE_WORLD", _create_world)
	_loc_status = Label.new()
	_loc_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loc_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_loc_status.custom_minimum_size = Vector2(520, 0)
	box.add_child(_loc_status)
	_button("MENU_BACK", _build)
	_loc_query.grab_focus()


func _small(parent: Node, key: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = tr(key)
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(cb)
	parent.add_child(b)


func _show_results(results: Array) -> void:
	for c in _loc_results.get_children():
		c.queue_free()
	if results.is_empty():
		_loc_status.text = tr("MENU_NO_RESULTS")
		return
	for r in results.slice(0, 6):
		var b := Button.new()
		b.text = "%s   (%d, %d)" % [r.name, r.x, r.y]
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(func():
			_picked = r
			_loc_name.text = str(r.name).split(",")[-1].strip_edges() if "," in str(r.name) else str(r.name)
			_loc_status.text = "%s: %d, %d" % [r.name, r.x, r.y])
		_loc_results.add_child(b)


func _search() -> void:
	_loc_status.text = "..."
	var results: Array = await Locator.geocode(_loc_query.text)
	_show_results(results)
	if results.size() == 1:
		_picked = results[0]
		_loc_name.text = str(results[0].name).split(",")[-1].strip_edges()


func _use_my_location() -> void:
	_loc_status.text = "..."
	var d: Dictionary = await Locator.locate_by_ip()
	if not d.get("ok", false):
		_loc_status.text = tr("MENU_NO_RESULTS")
		return
	if not Locator.in_estonia(d.x, d.y):
		_loc_status.text = tr("MENU_OUTSIDE_ESTONIA") + "  (%s)" % d.name
		return
	_show_results([d])
	_picked = d
	_loc_name.text = str(d.name).split(",")[0].strip_edges()


func _create_world() -> void:
	if _picked.is_empty():
		_loc_status.text = tr("MENU_NO_RESULTS")
		return
	var name := _loc_name.text.strip_edges()
	if name == "":
		name = str(_picked.name)
	var cb := func(t: String): _loc_status.text = t
	Locator.progress.connect(cb)
	_loc_status.text = tr("MENU_GENERATING") % "..."
	var res: Dictionary = await Locator.create_world(name, float(_picked.x), float(_picked.y))
	Locator.progress.disconnect(cb)
	if not res.ok:
		_loc_status.text = str(res.error)
		return
	_loc_status.text = tr("MENU_WORLD_READY")
	GameState.reset()
	get_tree().change_scene_to_file("res://scenes/world/world.tscn")
