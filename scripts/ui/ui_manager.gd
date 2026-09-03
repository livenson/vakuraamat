# All in-game UI, built in code: HUD, notices, dialogue box, the register (era switch),
# inventory, journal (ledger + maps), chapter notices and the ending. Opening any panel
# blocks player input and frees the mouse.
extends CanvasLayer

const GOLD := Color(0.85, 0.68, 0.25)
const PAPER := Color(0.93, 0.88, 0.76)
const INK := Color(0.16, 0.12, 0.08)
const MAP_ORDER := ["era_1798", "era_1938", "era_2026"]
const LOCATIONS := {   # tile metres -> journal map markers
	"LOC_OAK": Vector2(560, 520), "LOC_MANOR": Vector2(600, 450), "LOC_ORCHARD": Vector2(585, 490),
	"LOC_FARMSTEAD": Vector2(545, 615), "LOC_WELL": Vector2(552, 570), "LOC_NORTH_FIELD": Vector2(600, 320),
}

var world: Node3D
var player: CharacterBody3D
var interactor: Interactor

var hud: Control
var prompt_label: Label
var hover_label: Label
var notice_label: Label
var era_label: Label
var keys_label: Label
var _notice_tween: Tween

var dialogue: PanelContainer
var speaker_label: Label
var text_label: RichTextLabel
var choice_box: VBoxContainer
var _line_queue: Array = []
var _pending_choices: Array = []
var _dialogue_ended := false

var register: PanelContainer
var inventory: PanelContainer
var journal: PanelContainer
var ledger_box: VBoxContainer
var map_slider: HSlider
var map_rects: Dictionary = {}
var map_markers: Control
var ending: PanelContainer
var _open_panel: Control = null


func _ready() -> void:
	world = get_parent()
	player = world.get_node("Player")
	interactor = player.get_node("Camera3D/Interactor")
	interactor.target_changed.connect(_on_target_changed)
	_build_hud()
	_build_dialogue()
	register = _build_panel("UI_REGISTER_TITLE")
	inventory = _build_panel("UI_INVENTORY")
	journal = _build_panel("UI_JOURNAL")
	ending = _build_panel("")
	move_child($Fade, get_child_count() - 1)
	EventBus.notice.connect(show_notice)
	EventBus.era_changed.connect(func(_e): _refresh_era_label())
	EventBus.chapter_committed.connect(_on_chapter_committed)
	EventBus.register_opened.connect(func(): show_notice(tr("UI_REGISTER_TITLE")))
	EventBus.flag_changed.connect(func(f, v): if f == "epilogue" and v: call_deferred("_show_ending"))
	EventBus.item_added.connect(func(_i, _e): if _open_panel == inventory: _fill_inventory())
	Narrative.line.connect(_on_line)
	Narrative.choices.connect(_on_choices)
	Narrative.ended.connect(_on_dialogue_ended)
	_refresh_era_label()


func _process(_delta: float) -> void:
	if era_label and world.has_method("clock_string"):
		_refresh_era_label()


# ---------------------------------------------------------------- building
func _build_hud() -> void:
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)
	era_label = _label(hud, 20)
	era_label.position = Vector2(16, 12)
	keys_label = _label(hud, 14)
	keys_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	keys_label.position = Vector2(16, -36)
	keys_label.text = tr("UI_KEYS")
	hover_label = _label(hud, 18)
	hover_label.set_anchors_preset(Control.PRESET_CENTER)
	hover_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hover_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hover_label.custom_minimum_size = Vector2(620, 0)
	hover_label.position = Vector2(-310, 40)
	prompt_label = _label(hud, 18)
	prompt_label.set_anchors_preset(Control.PRESET_CENTER)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.custom_minimum_size = Vector2(400, 0)
	prompt_label.position = Vector2(-200, 120)
	prompt_label.add_theme_color_override("font_color", GOLD)
	notice_label = _label(hud, 20)
	notice_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice_label.custom_minimum_size = Vector2(760, 0)
	notice_label.position = Vector2(-380, 60)
	notice_label.modulate.a = 0.0
	# crosshair
	var dot := ColorRect.new()
	dot.set_anchors_preset(Control.PRESET_CENTER)
	dot.size = Vector2(4, 4)
	dot.position = Vector2(-2, -2)
	dot.color = Color(1, 1, 1, 0.6)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(dot)


func _label(parent: Control, size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _build_dialogue() -> void:
	dialogue = PanelContainer.new()
	dialogue.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	dialogue.offset_left = 160
	dialogue.offset_right = -160
	dialogue.offset_top = -260
	dialogue.offset_bottom = -30
	dialogue.visible = false
	add_child(dialogue)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	dialogue.add_child(v)
	speaker_label = Label.new()
	speaker_label.add_theme_font_size_override("font_size", 18)
	speaker_label.add_theme_color_override("font_color", GOLD)
	v.add_child(speaker_label)
	text_label = RichTextLabel.new()
	text_label.bbcode_enabled = true
	text_label.fit_content = true
	text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_label.add_theme_font_size_override("normal_font_size", 20)
	v.add_child(text_label)
	choice_box = VBoxContainer.new()
	v.add_child(choice_box)


func _build_panel(title_key: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.custom_minimum_size = Vector2(760, 520)
	p.position = Vector2(-380, -260)
	p.visible = false
	add_child(p)
	var v := VBoxContainer.new()
	v.name = "Body"
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	var t := Label.new()
	t.name = "Title"
	t.text = tr(title_key) if title_key != "" else ""
	t.add_theme_font_size_override("font_size", 26)
	t.add_theme_color_override("font_color", GOLD)
	v.add_child(t)
	return p


# ---------------------------------------------------------------- HUD
func _refresh_era_label() -> void:
	var era := GameState.era(GameState.current_era)
	if era == null:
		era_label.text = ""
		return
	var chap := ""
	match GameState.chapter:
		0: chap = ""
		4: chap = "  ·  " + tr("UI_EPILOGUE")
		_: chap = "  ·  " + tr("UI_CHAPTER") % GameState.chapter
	era_label.text = "%s  %s   %s%s" % [era.year_label, tr(era.display_name_key), world.clock_string(), chap]
	keys_label.text = tr("UI_KEYS")


func _on_target_changed(t: Interactable) -> void:
	if t == null:
		prompt_label.text = ""
		hover_label.text = ""
		return
	var lbl := t.label()
	prompt_label.text = ("%s  ·  " % lbl if lbl != "" else "") + "[E] " + t.prompt()
	hover_label.text = t.hover_text()


func show_notice(text: String) -> void:
	if text.is_empty():
		return
	notice_label.text = text
	if _notice_tween:
		_notice_tween.kill()
	notice_label.modulate.a = 1.0
	_notice_tween = create_tween()
	_notice_tween.tween_interval(3.5 + text.length() * 0.03)
	_notice_tween.tween_property(notice_label, "modulate:a", 0.0, 1.0)


func _on_chapter_committed(chapter: int) -> void:
	if chapter == 0:
		return
	var key := "UI_CHAPTER_COMMIT_FIRST" if not TimelineState.has_flag("told_commit") else "UI_CHAPTER_COMMIT"
	TimelineState.set_flag("told_commit", true)
	show_notice(tr(key) % str(chapter) if key == "UI_CHAPTER_COMMIT" else tr(key))


# ---------------------------------------------------------------- panels
func _open(p: Control) -> void:
	if _open_panel and _open_panel != p:
		_open_panel.visible = false
	_open_panel = p
	p.visible = true
	_set_gameplay_input(false)


func _close() -> void:
	if _open_panel:
		_open_panel.visible = false
		_open_panel = null
	if not dialogue.visible:
		_set_gameplay_input(true)


func _set_gameplay_input(on: bool) -> void:
	player.input_enabled = on
	interactor.blocked = not on
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE
	hud.visible = on


func _unhandled_input(event: InputEvent) -> void:
	if dialogue.visible:
		if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept") \
				or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
			_next_line()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		if _open_panel:
			_close()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("register"):
		_toggle(register, _fill_register)
	elif event.is_action_pressed("inventory"):
		_toggle(inventory, _fill_inventory)
	elif event.is_action_pressed("journal"):
		_toggle(journal, _fill_journal)
	elif event.is_action_pressed("language"):
		var next := "en" if TranslationServer.get_locale().begins_with("et") else "et"
		TranslationServer.set_locale(next)
		show_notice("English" if next == "en" else "Eesti keel")
		_refresh_era_label()
		if _open_panel:
			var p := _open_panel
			_close()
			_toggle(p, _filler_for(p))


func _filler_for(p: Control) -> Callable:
	if p == register: return _fill_register
	if p == inventory: return _fill_inventory
	return _fill_journal


func _toggle(p: PanelContainer, fill: Callable) -> void:
	if _open_panel == p:
		_close()
		return
	if p == register and not GameState.register_unlocked:
		show_notice(tr("UI_REGISTER_LOCKED"))
		return
	fill.call()
	_open(p)


func _clear_body(p: PanelContainer) -> VBoxContainer:
	var body: VBoxContainer = p.get_node("Body")
	for c in body.get_children():
		if c.name != "Title":
			c.queue_free()
	return body


# --- register: the era switch
func _fill_register() -> void:
	var body := _clear_body(register)
	body.get_node("Title").text = tr("UI_REGISTER_TITLE")
	var hint := Label.new()
	hint.text = tr("UI_REGISTER_HINT")
	body.add_child(hint)
	for era in GameState.eras_in_order():
		var b := Button.new()
		var mark := ""
		for e in Journal.entries:
			if era.id in e.era_to and not TimelineState.has_flag("seen_%s_%s" % [e.flag, era.id]):
				mark = "   ✦"
		var nudge := "   ←" if (GameState.chapter == 1 and era.id == "era_1798" and not GameState.visited_eras.has(era.id)) else ""
		b.text = "%s   %s%s%s" % [era.year_label, tr(era.display_name_key), mark, nudge]
		b.add_theme_font_size_override("font_size", 24)
		b.disabled = era.id == GameState.current_era
		b.pressed.connect(_on_era_pressed.bind(era.id))
		body.add_child(b)
	var closeb := Button.new()
	closeb.text = tr("UI_CLOSE")
	closeb.pressed.connect(_close)
	body.add_child(closeb)


func _on_era_pressed(era_id: String) -> void:
	_close()
	var left: Array = Inventory.local_items(GameState.current_era)
	if left.size() > 0 and not TimelineState.has_flag("taught_local_items"):
		TimelineState.set_flag("taught_local_items", true)
		show_notice(tr("NOTICE_LEFT_BEHIND") % tr(GameState.item(left[0]).display_name_key))
	await GameState.switch_era(era_id)
	for e in Journal.entries:
		if era_id in e.era_to:
			TimelineState.flags["seen_%s_%s" % [e.flag, era_id]] = true


# --- inventory
func _fill_inventory() -> void:
	var body := _clear_body(inventory)
	body.get_node("Title").text = tr("UI_INVENTORY")
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 24)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(h)
	for tier in [["UI_ARTIFACTS", Inventory.artifacts, true], ["UI_LOCAL_ITEMS", Inventory.local_items(GameState.current_era), false]]:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(col)
		var t := Label.new()
		t.text = tr(tier[0])
		t.add_theme_font_size_override("font_size", 20)
		if tier[2]:
			t.add_theme_color_override("font_color", GOLD)
		col.add_child(t)
		if tier[1].is_empty():
			var e := Label.new()
			e.text = tr("UI_EMPTY")
			col.add_child(e)
		for id in tier[1]:
			var item := GameState.item(id)
			var row := PanelContainer.new()
			var vb := VBoxContainer.new()
			row.add_child(vb)
			var n := Label.new()
			n.text = ("✦ " if tier[2] else "· ") + tr(item.display_name_key)
			n.add_theme_font_size_override("font_size", 18)
			if tier[2]:
				n.add_theme_color_override("font_color", GOLD)
			vb.add_child(n)
			var d := Label.new()
			d.text = tr(item.description_key)
			d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			vb.add_child(d)
			col.add_child(row)
	var closeb := Button.new()
	closeb.text = tr("UI_CLOSE")
	closeb.pressed.connect(_close)
	body.add_child(closeb)


# --- journal: ledger + maps
func _fill_journal() -> void:
	var body := _clear_body(journal)
	body.get_node("Title").text = tr("UI_JOURNAL")
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(tabs)
	# ledger
	var scroll := ScrollContainer.new()
	scroll.name = tr("UI_LEDGER")
	tabs.add_child(scroll)
	ledger_box = VBoxContainer.new()
	ledger_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ledger_box.add_theme_constant_override("separation", 10)
	scroll.add_child(ledger_box)
	if Journal.entries.is_empty():
		var e := Label.new()
		e.text = tr("UI_LEDGER_EMPTY")
		ledger_box.add_child(e)
	for e in Journal.entries:
		var l := Label.new()
		l.text = "%s  —  %s" % [e.get("game_time", ""), tr(e.text_key)]
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(700, 0)
		ledger_box.add_child(l)
	# maps
	var maps := VBoxContainer.new()
	maps.name = tr("UI_MAPS")
	tabs.add_child(maps)
	var stack := Control.new()
	stack.custom_minimum_size = Vector2(400, 400)
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	maps.add_child(stack)
	map_rects.clear()
	for id in MAP_ORDER:
		var era := GameState.era(id)
		var r := TextureRect.new()
		r.texture = era.terrain_texture
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		r.set_anchors_preset(Control.PRESET_FULL_RECT)
		stack.add_child(r)
		map_rects[id] = r
	map_markers = Control.new()
	map_markers.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_markers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(map_markers)
	map_markers.draw.connect(_draw_markers.bind(map_markers))
	var row := HBoxContainer.new()
	maps.add_child(row)
	var l1 := Label.new()
	l1.text = "1798"
	row.add_child(l1)
	map_slider = HSlider.new()
	map_slider.min_value = 0
	map_slider.max_value = 2
	map_slider.step = 0.01
	map_slider.value = 2
	map_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_slider.value_changed.connect(func(_v): _update_map_blend())
	row.add_child(map_slider)
	var l3 := Label.new()
	l3.text = "2026"
	row.add_child(l3)
	_update_map_blend()
	# codex: what is attested history and what is invented (design doc 6)
	var codex := ScrollContainer.new()
	codex.name = tr("UI_CODEX")
	tabs.add_child(codex)
	var cb := VBoxContainer.new()
	cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cb.add_theme_constant_override("separation", 8)
	codex.add_child(cb)
	for k in ["CODEX_REAL", "CODEX_INVENTED", "CODEX_WORDS", "CODEX_DATA"]:
		var h := Label.new()
		h.text = tr(k + "_TITLE")
		h.add_theme_color_override("font_color", GOLD)
		h.add_theme_font_size_override("font_size", 18)
		cb.add_child(h)
		var t := Label.new()
		t.text = tr(k)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.custom_minimum_size = Vector2(700, 0)
		cb.add_child(t)
	var closeb := Button.new()
	closeb.text = tr("UI_CLOSE")
	closeb.pressed.connect(_close)
	body.add_child(closeb)


## Debug hook for verification runs: open a panel by name.
func debug_open(which: String) -> void:
	match which:
		"register": _toggle(register, _fill_register)
		"journal": _toggle(journal, _fill_journal)
		"inventory": _toggle(inventory, _fill_inventory)


func _update_map_blend() -> void:
	# slider 0..2 across 1798 -> 1938 -> 2026; the upper layers fade in over the lower ones
	var v: float = map_slider.value
	map_rects["era_1798"].modulate.a = 1.0
	map_rects["era_1938"].modulate.a = clampf(v, 0.0, 1.0)
	map_rects["era_2026"].modulate.a = clampf(v - 1.0, 0.0, 1.0)
	map_markers.queue_redraw()


func _draw_markers(c: Control) -> void:
	var size := c.size
	var side := minf(size.x, size.y)
	var origin := (size - Vector2(side, side)) * 0.5
	for id in LOCATIONS:
		if not Journal.visited.has(id):
			continue
		var p: Vector2 = origin + LOCATIONS[id] / 1024.0 * side
		c.draw_circle(p, 6, GOLD)
		c.draw_circle(p, 6, INK, false, 1.5)
		c.draw_string(ThemeDB.fallback_font, p + Vector2(9, 5), tr(id), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, INK)
	# the player
	var pp := Vector2(player.global_position.x, player.global_position.z)
	c.draw_circle(origin + pp / 1024.0 * side, 4, Color.WHITE)


# ---------------------------------------------------------------- dialogue
func _on_line(text: String, speaker: String, _tags: Array) -> void:
	_line_queue.append([speaker, text])
	if not dialogue.visible:
		dialogue.visible = true
		_dialogue_ended = false
		_set_gameplay_input(false)
		_next_line()


func _on_choices(options: Array) -> void:
	_pending_choices = options
	if _line_queue.is_empty():
		_show_choices()


func _on_dialogue_ended() -> void:
	_dialogue_ended = true
	if _line_queue.is_empty():
		_end_dialogue()


func _next_line() -> void:
	if not _line_queue.is_empty():
		var l: Array = _line_queue.pop_front()
		speaker_label.text = tr(l[0]) if l[0] != "" else ""
		text_label.text = l[1]
		for c in choice_box.get_children():
			c.queue_free()
		if _line_queue.is_empty() and not _pending_choices.is_empty():
			_show_choices()
		elif _line_queue.is_empty() and _dialogue_ended:
			var b := Button.new()
			b.text = tr("UI_CLOSE")
			b.pressed.connect(_end_dialogue)
			choice_box.add_child(b)
		return
	if not _pending_choices.is_empty():
		return
	if _dialogue_ended:
		_end_dialogue()


func _show_choices() -> void:
	for c in choice_box.get_children():
		c.queue_free()
	for o in _pending_choices:
		var b := Button.new()
		b.text = o.text
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(_choose.bind(o.index))
		choice_box.add_child(b)


func _choose(index: int) -> void:
	_pending_choices = []
	for c in choice_box.get_children():
		c.queue_free()
	Narrative.choose(index)


func _end_dialogue() -> void:
	dialogue.visible = false
	_line_queue.clear()
	_pending_choices = []
	if _open_panel == null:
		_set_gameplay_input(true)


# ---------------------------------------------------------------- ending
func _show_ending() -> void:
	var kept := 0
	for f in ["family_recorded_1798", "north_field_ploughed", "well_kept_open", "cellar_opened"]:
		if TimelineState.has_flag(f):
			kept += 1
	var letter := TimelineState.has_flag("letter_delivered")
	var key := "ENDING_FOREST"
	if kept == 4 and letter:
		key = "ENDING_ORCHARD"
	elif kept >= 2:
		key = "ENDING_FURROWS"
	var body := _clear_body(ending)
	body.get_node("Title").text = tr(key + "_TITLE")
	var t := Label.new()
	t.text = tr(key)
	if letter and kept < 4:
		t.text += "\n\n" + tr("ENDING_BOX_PARTIAL")
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(700, 0)
	t.add_theme_font_size_override("font_size", 19)
	body.add_child(t)
	var kept_l := Label.new()
	kept_l.text = tr("ENDING_KEPT") % [kept, 4]
	body.add_child(kept_l)
	var again := Button.new()
	again.text = tr("UI_PLAY_AGAIN")
	again.pressed.connect(func():
		GameState.reset()
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn"))
	body.add_child(again)
	var quit := Button.new()
	quit.text = tr("UI_QUIT")
	quit.pressed.connect(func(): get_tree().quit())
	body.add_child(quit)
	SaveManager.autosave()
	_open(ending)
