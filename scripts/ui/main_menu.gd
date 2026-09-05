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
	sub.text = tr("MENU_SUBTITLE")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	box.add_child(Control.new())
	if SaveManager.has_save():
		_button("UI_CONTINUE_GAME", func():
			GameState.pending_load = true
			get_tree().change_scene_to_file("res://scenes/world/world.tscn"))
	_button("UI_NEW_GAME", func():
		GameState.reset()
		get_tree().change_scene_to_file("res://scenes/world/world.tscn"))
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
