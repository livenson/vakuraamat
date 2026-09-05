# All in-game UI, built in code: HUD, notices, dialogue box, the register (era switch),
# inventory, journal (ledger + maps), chapter notices and the ending. Opening any panel
# blocks player input and frees the mouse.
extends CanvasLayer

const GOLD := Color(0.85, 0.68, 0.25)
const PAPER := Color(0.93, 0.88, 0.76)
const INK := Color(0.16, 0.12, 0.08)
var _locations := {}   # LOC_* -> tile metres, from the site's layout.json via manifest "locations"

var world: Node3D
var player: CharacterBody3D
var interactor: Interactor

var hud: Control
var prompt_label: Label
var hover_label: Label
var notice_label: Label
var compass: Control
var marker: Control
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
var trade: PanelContainer
var _trade_post: TradePost = null
var build: PanelContainer
var _manor_ctl: ManorController = null
var debug_map: PanelContainer
var pause: PanelContainer
var report_panel: PanelContainer
var codes_label: Label            # K: cadastral number, building codes, road, registry links
var ledger_panel: LedgerPanel    # V (Tab once the register goes): the town's book
var news_panel: NewsPanel        # N: the town feed
var codes_on := false
var _codes_lines: MeshInstance3D = null
var _debug_canvas: Control
var _debug_bg: TextureRect
var _debug_bg_tile := Vector2i(9999, 9999)
var _tile_ortho: Dictionary = {}      # pack id -> ImageTexture of its orthophoto (debug map background)
var _open_panel: Control = null


func _ready() -> void:
	var layout: Dictionary = Sites.layout()
	var locs: Dictionary = Sites.get_value("locations", {})
	for loc_key in locs:
		var v: Array = layout.get(str(locs[loc_key]), [])
		if v.size() >= 2:
			_locations[loc_key] = Vector2(float(v[0]), float(v[1]))
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
	trade = _build_panel("UI_TRADE")
	build = _build_panel("UI_BUILD")
	debug_map = _build_panel("UI_DEBUG_MAP")
	pause = _build_panel("UI_MENU")
	report_panel = _build_panel("UI_REPORT_TITLE")
	report_panel.custom_minimum_size = Vector2(640, 0)
	ledger_panel = LedgerPanel.new()
	add_child(ledger_panel)
	ledger_panel.setup(world)
	_center_panel(ledger_panel)
	ledger_panel.show_parcel.connect(func(t):
		var marks: Node = world.get_node_or_null("ParcelMarks")
		if marks:
			marks.flash(t))
	news_panel = NewsPanel.new()
	add_child(news_panel)
	news_panel.setup()
	_center_panel(news_panel)
	news_panel.show_parcel.connect(func(t):
		_close()
		ledger_panel.open_parcel(t)
		_open(ledger_panel))
	Ledger.player_changed.connect(_refresh_era_label)
	Ledger.month_changed.connect(func(_m): _refresh_era_label())
	pause.custom_minimum_size = Vector2(600, 0)
	debug_map.custom_minimum_size = Vector2(1180, 840)
	_center_panel(debug_map)
	move_child($Fade, get_child_count() - 1)
	EventBus.notice.connect(show_notice)
	EventBus.era_changed.connect(func(_e): _refresh_era_label())
	EventBus.chapter_committed.connect(_on_chapter_committed)
	EventBus.register_opened.connect(func(): show_notice(tr("UI_REGISTER_TITLE")))
	EventBus.flag_changed.connect(func(f, v):
		if f == _ending_flag() and v:
			call_deferred("_show_ending"))
	EventBus.item_added.connect(func(_i, _e):
		if _open_panel == inventory:
			_fill_inventory())
	Narrative.line.connect(_on_line)
	Narrative.choices.connect(_on_choices)
	Narrative.ended.connect(_on_dialogue_ended)
	_refresh_era_label()


func _process(_delta: float) -> void:
	if era_label and world.has_method("clock_string"):
		_refresh_era_label()
	if compass:
		compass.queue_redraw()
	if codes_on and Engine.get_process_frames() % 20 == 0:
		_refresh_codes()
	if marker:
		marker.queue_redraw()
	if _debug_canvas and is_instance_valid(_debug_canvas) and debug_map.visible:
		_debug_canvas.queue_redraw()


## Heading in degrees, 0 = north (-Z), 90 = east (+X).
func _heading_deg() -> float:
	var fwd := -player.global_transform.basis.z
	return fmod(rad_to_deg(atan2(fwd.x, -fwd.z)) + 360.0, 360.0)


## The first matching rule of the site manifest's "objectives": {when: register_locked} |
## {chapter, flag, not_flag} conditions, "key" for the HUD text, optional "target" node name
## (with "era" and "lift") for the marker.
func _current_objective() -> Dictionary:
	for o in Sites.get_value("objectives", []):
		if o.get("when", "") == "register_locked":
			if not GameState.register_unlocked:
				return o
			continue
		if not GameState.register_unlocked:
			continue
		if o.has("chapter") and GameState.chapter != int(o.chapter):
			continue
		if o.has("flag") and not TimelineState.has_flag(str(o.flag)):
			continue
		if o.has("not_flag") and TimelineState.has_flag(str(o.not_flag)):
			continue
		return o
	return {}


## World position of the current objective, or null.
func _objective_target() -> Variant:
	var layer: Node = world.get_node("EraLayers").get_node_or_null(GameState.current_era)
	if layer == null:
		return null
	var o := _current_objective()
	if not o.has("target") or (o.has("era") and GameState.current_era != str(o.era)):
		return null
	var n: Node = layer.find_child(str(o.target), true, false)
	return n.global_position + Vector3(0, float(o.get("lift", 1.5)), 0) if n else null


func _ending_flag() -> String:
	return str(Sites.get_value("ending", {}).get("trigger_flag", "epilogue"))


func _draw_marker() -> void:
	var target = _objective_target()
	if target == null:
		return
	var cam: Camera3D = player.camera
	var dist: float = player.global_position.distance_to(target)
	var size := marker.size
	var behind := cam.is_position_behind(target)
	var p: Vector2 = cam.unproject_position(target)
	var on_screen := not behind and p.x > 20 and p.x < size.x - 20 and p.y > 60 and p.y < size.y - 40
	var font := ThemeDB.fallback_font
	if on_screen:
		var d := 9.0
		marker.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -d), p + Vector2(d, 0), p + Vector2(0, d), p + Vector2(-d, 0)]), GOLD)
		marker.draw_string(font, p + Vector2(-30, -14), "%d m" % int(dist), HORIZONTAL_ALIGNMENT_CENTER, 60, 14, GOLD)
	else:
		# direction on the compass ring: angle from the view forward
		var to: Vector3 = target - player.global_position
		var fwd: Vector3 = -cam.global_transform.basis.z
		var ang := atan2(fwd.cross(to).y, fwd.dot(Vector3(to.x, 0, to.z)))
		var centre := size / 2
		var r := minf(size.x, size.y) * 0.42
		var q := centre + Vector2(sin(ang), -cos(ang)) * r
		var dir := (q - centre).normalized()
		var tip := q + dir * 12
		var left := q + Vector2(-dir.y, dir.x) * 8
		var right := q - Vector2(-dir.y, dir.x) * 8
		marker.draw_colored_polygon(PackedVector2Array([tip, left, right]), GOLD)
		marker.draw_string(font, q - dir * 26 + Vector2(-30, 5), "%d m" % int(dist), HORIZONTAL_ALIGNMENT_CENTER, 60, 14, GOLD)


func _draw_compass() -> void:
	var c := compass
	var w := c.size.x
	var h := c.size.y
	var heading := _heading_deg()
	var px_per_deg := w / 120.0            # the tape shows 120 degrees
	c.draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.35))
	var font := ThemeDB.fallback_font
	for d in range(-180, 181, 15):
		var rel := fmod(d - heading + 540.0, 360.0) - 180.0
		if absf(rel) > 60.0:
			continue
		var x := w / 2 + rel * px_per_deg
		var deg := int(fmod(d + 360.0, 360.0))
		var big := deg % 90 == 0
		c.draw_line(Vector2(x, h - 6), Vector2(x, h - (14 if big else 10)), Color(1, 1, 1, 0.8), 1.0)
		if big:
			var name: String = ["N", "E", "S", "W"][deg / 90]
			c.draw_string(font, Vector2(x - 6, 15), name, HORIZONTAL_ALIGNMENT_CENTER, 12, 15, GOLD if name == "N" else Color.WHITE)
		elif deg % 45 == 0:
			c.draw_string(font, Vector2(x - 12, 15), str(deg), HORIZONTAL_ALIGNMENT_CENTER, 24, 10, Color(1, 1, 1, 0.7))
	c.draw_line(Vector2(w / 2, 2), Vector2(w / 2, h - 2), GOLD, 2.0)
	c.draw_string(font, Vector2(w / 2 + 6, h - 8), "%d°" % int(round(heading)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, GOLD)


# ---------------------------------------------------------------- building
func _build_hud() -> void:
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)
	era_label = _label(hud, 20)
	era_label.position = Vector2(16, 12)
	keys_label = _label(hud, 14)
	keys_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 16)
	keys_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	keys_label.text = tr("UI_KEYS")
	hover_label = _label(hud, 18)
	hover_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	hover_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hover_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hover_label.custom_minimum_size = Vector2(620, 0)
	hover_label.position = Vector2(-310, 40)
	prompt_label = _label(hud, 18)
	prompt_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.custom_minimum_size = Vector2(400, 0)
	prompt_label.position = Vector2(-200, 120)
	prompt_label.add_theme_color_override("font_color", GOLD)
	notice_label = _label(hud, 20)
	notice_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice_label.custom_minimum_size = Vector2(760, 0)
	notice_label.position = Vector2(-380, 70)
	notice_label.modulate.a = 0.0
	# compass tape, top centre: north is -Z on the tile (map up)
	compass = Control.new()
	compass.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	compass.custom_minimum_size = Vector2(420, 34)
	compass.size = Vector2(420, 34)
	compass.position = Vector2(-210, 8)
	compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	compass.draw.connect(_draw_compass)
	hud.add_child(compass)
	# objective marker: projected diamond + distance, arrow at the screen edge when off-screen
	marker = Control.new()
	marker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.draw.connect(_draw_marker)
	hud.add_child(marker)
	# crosshair
	var dot := ColorRect.new()
	dot.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
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


func _center_panel(p: Control) -> void:
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH


func _build_panel(title_key: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(760, 520)
	p.visible = false
	add_child(p)
	_center_panel(p)
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
func _objective() -> String:
	var o := _current_objective()
	return tr(str(o.key)) if o.has("key") else ""


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
	if Ledger.local() != null:
		era_label.text = "%s   %s   %s   %s%s" % [Sites.display_name(Sites.active), Ledger.date_string(), world.clock_string(), Ledger.format_money(Ledger.cash()), chap]
	var obj := _objective()
	if obj != "":
		era_label.text += "\n" + obj
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
	if event.is_action_pressed("ui_cancel"):
		if _open_panel:
			_close()
		else:
			_fill_pause()
			_open(pause)
		get_viewport().set_input_as_handled()
		return
	if _open_panel == pause:
		return
	if dialogue.visible:
		if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept") \
				or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
			_next_line()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("codes"):
		_toggle_codes()
		return
	if event.is_action_pressed("report"):
		if _open_panel != report_panel:
			Reporter.snapshot(world)   # the frame as seen, before the panel covers it
			_toggle(report_panel, _fill_report)
		return
	if event.is_action_pressed("ledger"):
		_toggle(ledger_panel, ledger_panel.fill)
	elif event.is_action_pressed("news"):
		_toggle(news_panel, news_panel.fill)
	elif event.is_action_pressed("buy_here"):
		_buy_here()
	elif event.is_action_pressed("register"):
		_toggle(register, _fill_register)
	elif event.is_action_pressed("inventory"):
		_toggle(inventory, _fill_inventory)
	elif event.is_action_pressed("journal"):
		_toggle(journal, _fill_journal)
	elif event.is_action_pressed("debug_map"):
		_toggle(debug_map, _fill_debug_map)
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
	if p == ledger_panel: return ledger_panel.fill
	if p == news_panel: return news_panel.fill
	if p == report_panel: return _fill_report
	if p == inventory: return _fill_inventory
	if p == debug_map: return _fill_debug_map
	if p == pause: return _fill_pause
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


# --- codes overlay (K): what the registers say about where you stand and what you look at
func _toggle_codes() -> void:
	codes_on = not codes_on
	if codes_label == null:
		codes_label = Label.new()
		codes_label.position = Vector2(16, 112)
		codes_label.add_theme_font_size_override("font_size", 14)
		codes_label.add_theme_color_override("font_color", GOLD)
		codes_label.add_theme_constant_override("outline_size", 4)
		codes_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		hud.add_child(codes_label)
	codes_label.visible = codes_on
	if codes_on:
		_refresh_codes()
		var links: Dictionary = Reporter.links_for(player.global_position, interactor.target, world.get_node("EraLayers").get_node_or_null(GameState.current_era))
		var urls := []
		for k in ["cadastre", "ehr", "xgis_map"]:
			if links.has(k):
				urls.append(str(links[k]))
		if not urls.is_empty():
			DisplayServer.clipboard_set("\n".join(urls))
			show_notice(tr("UI_CODES_COPIED") % urls.size())
	elif _codes_lines:
		_codes_lines.queue_free()
		_codes_lines = null


func _refresh_codes() -> void:
	if not codes_on or codes_label == null:
		return
	var pos := player.global_position
	var layer: Node = world.get_node("EraLayers").get_node_or_null(GameState.current_era)
	var lines := []
	var geo: TerrainGeoref = world.georef
	if geo and geo.is_valid():
		var e := geo.world_to_lest97(pos)
		lines.append("L-EST97 %d %d   tile %d,%d" % [int(e.x), int(e.y), int(pos.x), int(pos.z)])
	var u := Parcels.at(pos)
	lines.append(tr("UI_CODES_PARCEL") + ": " + (Parcels.describe(u) if not u.is_empty() else "-"))
	if not u.is_empty():
		lines.append("   " + str(u.get("link", "")))
		var row := Ledger.parcel(u.tunnus)
		if not row.is_empty():
			var owner: String = tr("UI_LEDGER_YOU") if Ledger.is_mine(u.tunnus) else str(row.owner_name)
			lines.append("   %s: %s   %s: %s   %s: %s%s" % [tr("UI_CODES_OWNER"), owner, tr("UI_LEDGER_COL_PRICE"), Ledger.format_money(int(row.price)),
				tr("UI_LEDGER_COL_YIELD"), Ledger.format_money(Ledger.yield_of(u.tunnus)), tr("UI_PER_MONTH")])
			var names := Ledger.tenants_of(u.tunnus).map(func(t): return str(t.name))
			if not names.is_empty():
				lines.append("   " + tr("UI_CODES_TENANT") + ": " + ", ".join(names))
	var links := Reporter.links_for(pos, interactor.target, layer)
	if links.has("etak_id"):
		lines.append(tr("UI_CODES_BUILDING") + ": ETAK %d   %s" % [int(links.etak_id), str(links.get("ehr", ""))])
	var road := Reporter._nearest_road(layer, pos)
	if not road.is_empty():
		lines.append(tr("UI_CODES_ROAD") + ": %s %s %s m %s (%.0f m)" % [str(road.get("name", "") if road.get("name") else ""), str(road.get("type", "")), str(road.get("width", "")), str(road.get("surface", "") if road.get("surface") else ""), float(road.get("distance", 0))])
	if interactor.target:
		lines.append(tr("UI_CODES_TARGET") + ": %s  %s" % [interactor.target.name, str(interactor.target.get_path())])
	codes_label.text = "\n".join(lines)
	_draw_parcel(u)


## B: open the book at the plot under the player's feet.
func _buy_here() -> void:
	if _open_panel and _open_panel != ledger_panel:
		return
	var u := Parcels.at(player.global_position)
	if u.is_empty() or Ledger.parcel(u.tunnus).is_empty():
		show_notice(tr("LEDGER_NO_PARCEL_HERE"))
		return
	ledger_panel.open_parcel(u.tunnus)
	if _open_panel != ledger_panel:
		_open(ledger_panel)


## The current cadastral unit's boundary as a line strip just above the ground.
func _draw_parcel(u: Dictionary) -> void:
	if _codes_lines:
		_codes_lines.queue_free()
		_codes_lines = null
	if u.is_empty():
		return
	var st := ImmediateMesh.new()
	st.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var poly: Array = u.polygon
	for i in poly.size() + 1:
		var c: Array = poly[i % poly.size()]
		var p := Vector3(float(c[0]), 0, float(c[1]))
		p.y = world.terrain.data.get_height(p) + 0.3
		st.surface_add_vertex(p)
	st.surface_end()
	_codes_lines = MeshInstance3D.new()
	_codes_lines.mesh = st
	var m := StandardMaterial3D.new()
	m.albedo_color = GOLD
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_codes_lines.material_override = m
	world.add_child(_codes_lines)


# --- issue report (F8): the frame is already grabbed; type what is wrong, where, how it should be
func _fill_report() -> void:
	var body := _clear_body(report_panel)
	body.get_node("Title").text = tr("UI_REPORT_TITLE")
	var hint := Label.new()
	hint.text = tr("UI_REPORT_HINT")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 14)
	body.add_child(hint)
	var t := TextEdit.new()
	t.custom_minimum_size = Vector2(600, 160)
	t.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	body.add_child(t)
	var row := HBoxContainer.new()
	body.add_child(row)
	var send := Button.new()
	send.text = tr("UI_REPORT_SEND")
	send.pressed.connect(func():
		var path := Reporter.capture(t.text.strip_edges(), world)
		_close()
		show_notice(tr("UI_REPORT_SENT") % path.get_file()))
	row.add_child(send)
	var cancel := Button.new()
	cancel.text = tr("UI_CLOSE")
	cancel.pressed.connect(_close)
	row.add_child(cancel)
	t.call_deferred("grab_focus")


# --- pause menu (Esc)
func _fill_pause() -> void:
	var body := _clear_body(pause)
	body.get_node("Title").text = tr("UI_MENU")
	_pause_button(body, tr("UI_CONTINUE"), _close)
	var fs := _pause_button(body, "", func(): WindowMode.set_fullscreen(not WindowMode.is_fullscreen()))
	var relabel := func(on: bool):
		fs.text = "%s: %s  (%s)" % [tr("MENU_FULLSCREEN"), tr("MENU_ON") if on else tr("MENU_OFF"), WindowMode.shortcut_text()]
	relabel.call(WindowMode.is_fullscreen())
	WindowMode.changed.connect(relabel, CONNECT_REFERENCE_COUNTED)
	fs.tree_exiting.connect(func(): WindowMode.changed.disconnect(relabel))
	_pause_button(body, tr("MENU_LANGUAGE"), func():
		var next := "en" if TranslationServer.get_locale().begins_with("et") else "et"
		TranslationServer.set_locale(next)
		_refresh_era_label()
		_fill_pause())
	_pause_button(body, tr("MENU_LOCATIONS"), func():
		SaveManager.autosave()
		GameState.menu_open_locations = true
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn"))
	_pause_button(body, tr("UI_SAVE_MENU"), func():
		SaveManager.autosave()
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn"))
	_pause_button(body, tr("UI_SAVE_QUIT"), func():
		SaveManager.autosave()
		get_tree().quit())
	var hint := Label.new()
	hint.text = tr("UI_KEYS")
	hint.add_theme_font_size_override("font_size", 13)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(hint)


func _pause_button(body: VBoxContainer, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 22)
	b.custom_minimum_size = Vector2(0, 42)
	b.pressed.connect(cb)
	body.add_child(b)
	return b


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
		var nd: Dictionary = Sites.get_value("register_nudge", {})
		var nudge := "   ←" if (not nd.is_empty() and GameState.chapter == int(nd.get("chapter", 1)) and era.id == str(nd.get("era", "")) and not GameState.visited_eras.has(era.id)) else ""
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
	var order := GameState.eras_in_order()
	for era in order:
		var id: String = era.id
		var r := TextureRect.new()
		r.texture = era.texture()
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
	l1.text = order[0].year_label if not order.is_empty() else ""
	row.add_child(l1)
	map_slider = HSlider.new()
	map_slider.min_value = 0
	map_slider.max_value = maxi(order.size() - 1, 1)
	map_slider.step = 0.01
	map_slider.value = map_slider.max_value
	map_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_slider.value_changed.connect(func(_v): _update_map_blend())
	row.add_child(map_slider)
	var l3 := Label.new()
	l3.text = order[-1].year_label if not order.is_empty() else ""
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
	for k in Sites.get_value("codex", []):
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


# --- trading (Phase 4): era-local goods for era-local money
func open_trade(post: TradePost) -> void:
	_trade_post = post
	_fill_trade()
	_open(trade)


func _fill_trade() -> void:
	var era: String = _trade_post.era_id
	var body := _clear_body(trade)
	body.get_node("Title").text = tr(_trade_post.post_name_key)
	var bal := Label.new()
	bal.text = tr("UI_BALANCE") % Trading.format_money(Trading.balance(era), era)
	bal.add_theme_font_size_override("font_size", 18)
	bal.add_theme_color_override("font_color", GOLD)
	body.add_child(bal)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 24)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(h)
	for side in [["UI_SELL", true], ["UI_BUY", false]]:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(col)
		var t := Label.new()
		t.text = tr(side[0])
		t.add_theme_font_size_override("font_size", 20)
		col.add_child(t)
		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col.add_child(scroll)
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(list)
		var bag: Array = Inventory.local_items(era)
		for g in Trading.goods_for(era):
			var selling: bool = side[1]
			var price: int = g.sell_price if selling else g.buy_price
			if price <= 0:
				continue
			var item := GameState.item(g.item_id)
			var count: int = bag.count(g.item_id)
			if selling and count == 0:
				continue
			var b := Button.new()
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.text = "%s%s   %s" % [tr(item.display_name_key), ("  ×%d" % count) if selling else "", Trading.format_money(price, era)]
			b.disabled = (not selling) and Trading.balance(era) < price
			b.pressed.connect(_on_trade.bind(g, selling))
			list.add_child(b)
	var closeb := Button.new()
	closeb.text = tr("UI_CLOSE")
	closeb.pressed.connect(_close)
	body.add_child(closeb)


func _on_trade(g: TradeGood, selling: bool) -> void:
	var era: String = _trade_post.era_id
	var ok: bool = Trading.sell(g, era) if selling else Trading.buy(g, era)
	if not ok:
		show_notice(tr("TRADE_NO_MONEY") if not selling else tr("TRADE_NOTHING_TO_SELL"))
	_fill_trade()


# --- base building (Phase 5): one panel, no spreadsheet
func open_build(ctl: ManorController) -> void:
	_manor_ctl = ctl
	_fill_build()
	_open(build)


func _fill_build() -> void:
	var m: ManorDefinition = _manor_ctl.manor
	var body := _clear_body(build)
	body.get_node("Title").text = tr(m.display_name_key)
	var info := Label.new()
	info.text = tr("BUILD_LEVEL") % [tr(m.display_name_key), Manors.development_level(m.id), m.structures.size()] + "   ·   " + tr("UI_BALANCE") % Trading.format_money(Trading.balance(m.era_id), m.era_id)
	body.add_child(info)
	var parcel := Label.new()
	parcel.text = "Katastritunnus / cadastral unit: " + m.cadastral_parcel_id
	parcel.add_theme_font_size_override("font_size", 13)
	body.add_child(parcel)
	for sid in m.structures:
		var st: StructureDefinition = Manors.structures[sid]
		var row := PanelContainer.new()
		var vb := VBoxContainer.new()
		row.add_child(vb)
		var h := HBoxContainer.new()
		vb.add_child(h)
		var n := Label.new()
		n.text = tr(st.display_name_key)
		n.add_theme_font_size_override("font_size", 18)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(n)
		var why := Manors.can_build(m, st)
		var b := Button.new()
		b.text = tr("BUILD_ALREADY") if why == "BUILD_ALREADY" else tr("BUILD_PROMPT")
		b.disabled = why != ""
		b.pressed.connect(func():
			Manors.build(m, st)
			_fill_build())
		h.add_child(b)
		var d := Label.new()
		var cost := []
		for item in st.cost_items:
			cost.append("%d × %s" % [int(st.cost_items[item]), tr(GameState.item(item).display_name_key)])
		cost.append(Trading.format_money(st.cost_money, m.era_id))
		d.text = tr(st.description_key) + "\n" + tr("BUILD_COST") % ", ".join(cost) + (("   ·   " + tr(why) % tr(Manors.structures[st.requires].display_name_key)) if why == "BUILD_REQUIRES" else ("   ·   " + tr(why) if why != "" and why != "BUILD_ALREADY" else ""))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.add_theme_font_size_override("font_size", 14)
		vb.add_child(d)
		body.add_child(row)
	var closeb := Button.new()
	closeb.text = tr("UI_CLOSE")
	closeb.pressed.connect(_close)
	body.add_child(closeb)


# --- debug map (temporary): everything in the current era, click to teleport
const DEBUG_COLORS := {
	"NPC": Color(1.0, 0.8, 0.2), "Pickup": Color(0.4, 1.0, 0.4), "Examinable": Color(1, 1, 1),
	"StoryPoint": Color(1.0, 0.55, 0.2), "FarmPlot": Color(0.7, 0.45, 0.2), "SeedBin": Color(0.9, 0.6, 0.3),
	"TradePost": Color(0.3, 0.9, 1.0), "ManorController": Color(1.0, 0.4, 0.9), "Animal": Color(0.8, 0.8, 0.5),
	"register": Color(1.0, 0.25, 0.25),
}


func _fill_debug_map() -> void:
	var body := _clear_body(debug_map)
	body.get_node("Title").text = tr("UI_DEBUG_MAP") + "   ·   " + GameState.current_era + "   ·   " + tr("UI_CHAPTER") % GameState.chapter
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	body.add_child(row)
	for era in GameState.eras_in_order():
		var b := Button.new()
		b.text = era.year_label
		b.disabled = era.id == GameState.current_era
		b.pressed.connect(func():
			GameState.register_unlocked = true
			await GameState.switch_era(era.id)
			_fill_debug_map())
		row.add_child(b)
	var bc := Button.new()
	bc.text = tr("UI_CHAPTER") % (GameState.chapter + 1) + " →"
	bc.pressed.connect(func():
		GameState.register_unlocked = true
		GameState.end_chapter()
		_fill_debug_map())
	row.add_child(bc)
	var ba := Button.new()
	ba.text = "+ artifacts"
	ba.pressed.connect(func():
		for id in ["register_page", "ploughshare", "manor_key", "aino_letter"]:
			if not Inventory.has(id):
				Inventory.add(id))
	row.add_child(ba)
	var bf := Button.new()
	bf.text = "+ all flags"
	bf.pressed.connect(func():
		for cp in GameState.consequence_points.values():
			TimelineState.set_flag(cp.flag_name, true)
		_fill_debug_map())
	row.add_child(bf)
	var bm := Button.new()
	bm.text = "+ money/seed"
	bm.pressed.connect(func():
		Trading.add_money(GameState.current_era, 500)
		for c in Farming.crops_for_era(GameState.current_era):
			Inventory.add(c.seed_item_id))
	row.add_child(bm)
	var be := Button.new()
	be.text = "+ 50 000 €"
	be.pressed.connect(func():
		await Ledger.debug_grant(50000)
		_fill_debug_map())
	row.add_child(be)
	var bn := Button.new()
	bn.text = tr("UI_LEDGER_MONTH") + " →"
	bn.pressed.connect(func():
		Ledger.debug_advance_month()
		_fill_debug_map())
	row.add_child(bn)
	var hint := Label.new()
	hint.text = tr("UI_DEBUG_MAP_HINT")
	hint.add_theme_font_size_override("font_size", 13)
	row.add_child(hint)
	var stack := Control.new()
	stack.custom_minimum_size = Vector2(700, 700)
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(stack)
	var bg := TextureRect.new()
	var newest := GameState.eras_in_order()
	bg.texture = newest[-1].texture() if not newest.is_empty() else null
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.modulate = Color(0.75, 0.75, 0.75)
	stack.add_child(bg)
	_debug_bg = bg
	_debug_bg_tile = Vector2i.ZERO
	_debug_canvas = Control.new()
	_debug_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_debug_canvas.draw.connect(_draw_debug_map.bind(_debug_canvas))
	_debug_canvas.gui_input.connect(_debug_map_input)
	stack.add_child(_debug_canvas)


func _map_frame(c: Control) -> Array:
	var side := minf(c.size.x, c.size.y)
	return [(c.size - Vector2(side, side)) * 0.5, side]


## Draws on the canvas that emitted `draw` (bound at connect time): when the panel is rebuilt, the
## old canvas still gets one last draw while `_debug_canvas` already points at the new one.
func _draw_debug_map(c: Control) -> void:
	if not is_instance_valid(c) or c != _debug_canvas:
		return
	var f := _map_frame(c)
	var origin: Vector2 = f[0]
	var side: float = f[1]
	var font := ThemeDB.fallback_font
	# the map shows the 1024 m tile the player stands in: the site's tile or a streamed neighbour
	var loc := Vector2i.ZERO
	var pack := Sites.active
	if world.streamer:
		loc = world.streamer.tile_of(player.global_position)
		pack = str(world.streamer.tiles.get(loc, {}).get("pack", ""))
	var off := Vector2(loc.x, loc.y) * 1024.0
	if loc != _debug_bg_tile and is_instance_valid(_debug_bg):
		_debug_bg.texture = _tile_texture(loc, pack)
		_debug_bg_tile = loc
	var layer: Node = world.get_node("EraLayers").get_node_or_null(GameState.current_era)
	if layer and loc == Vector2i.ZERO:
		for n in layer.find_children("*", "Interactable", true, false):
			if not n.visible or not n.is_visible_in_tree():
				continue
			var kind := "Examinable"
			for k in DEBUG_COLORS:
				if n.get_class() == k or (n.get_script() and n.get_script().get_global_name() == k):
					kind = k
			if n.name == "RegisterBook":
				kind = "register"
			var p: Vector2 = origin + (Vector2(n.global_position.x, n.global_position.z) - off) / 1024.0 * side
			var col: Color = DEBUG_COLORS.get(kind, Color.WHITE)
			c.draw_circle(p, 5, col)
			c.draw_circle(p, 5, Color.BLACK, false, 1.0)
			var text: String = n.label() if n.label() != "" else n.name
			c.draw_string(font, p + Vector2(7, 4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.BLACK)
			c.draw_string(font, p + Vector2(6, 3), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
	# the player and heading
	var pp := origin + (Vector2(player.global_position.x, player.global_position.z) - off) / 1024.0 * side
	var fwd := -player.global_transform.basis.z
	c.draw_line(pp, pp + Vector2(fwd.x, fwd.z) * 18, Color.WHITE, 2.0)
	c.draw_circle(pp, 6, Color.WHITE)
	c.draw_circle(pp, 6, Color.BLACK, false, 1.5)
	# north arrow and scale
	c.draw_string(font, origin + Vector2(side - 24, 18), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, GOLD)
	c.draw_line(origin + Vector2(side - 18, 40), origin + Vector2(side - 18, 22), GOLD, 2.0)
	c.draw_line(origin + Vector2(10, side - 10), origin + Vector2(10 + side * 100.0 / 1024.0, side - 10), Color.WHITE, 2.0)
	c.draw_string(font, origin + Vector2(10, side - 14), "100 m", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
	var tile_text := "tile %d,%d  %s" % [loc.x, loc.y, pack if pack != "" else "(not loaded)"]
	c.draw_string(font, origin + Vector2(11, 19), tile_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.BLACK)
	c.draw_string(font, origin + Vector2(10, 18), tile_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, GOLD)


## Background of the debug map for a tile: the era drape of the site's own tile, the orthophoto of a
## streamed neighbour (read from its tile directory once), nothing while a tile is still loading.
func _tile_texture(loc: Vector2i, pack: String) -> Texture2D:
	if loc == Vector2i.ZERO:
		var newest := GameState.eras_in_order()
		return newest[-1].texture() if not newest.is_empty() else null
	if pack == "":
		return null
	if _tile_ortho == null:
		_tile_ortho = {}   # members added by a hot reload start as null on the live instance
	if not _tile_ortho.has(pack):
		var img := Image.load_from_file(Sites.tile_dir_of(pack) + "/ortho.jpg")
		_tile_ortho[pack] = ImageTexture.create_from_image(img) if img else null
	return _tile_ortho[pack]


func _debug_map_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var f := _map_frame(_debug_canvas)
		var local: Vector2 = (event.position - f[0]) / f[1] * 1024.0
		if local.x < 0 or local.y < 0 or local.x > 1024 or local.y > 1024:
			return
		if world.streamer:
			local += Vector2(_debug_bg_tile.x, _debug_bg_tile.y) * 1024.0
		player.velocity = Vector3.ZERO
		player.global_position = Vector3(local.x, 200.0, local.y)
		world._snap(player, 1.0)
		_debug_canvas.queue_redraw()


## Debug hook for verification runs: open a panel by name.
func debug_open(which: String) -> void:
	match which:
		"register": _toggle(register, _fill_register)
		"journal": _toggle(journal, _fill_journal)
		"inventory": _toggle(inventory, _fill_inventory)
		"map": _toggle(debug_map, _fill_debug_map)
		"ledger": _toggle(ledger_panel, ledger_panel.fill)
		"town":
			ledger_panel.tabs.current_tab = 4
			_toggle(ledger_panel, ledger_panel.fill)
		"news": _toggle(news_panel, news_panel.fill)
		"menu": _toggle(pause, _fill_pause)
		"trade", "build":
			var layer: Node = world.get_node("EraLayers").get_node_or_null(GameState.current_era)
			if layer:
				var n: Node = layer.find_child("TradePost", true, false) if which == "trade" else _debug_build_node(layer)
				if n:
					n.interact(player)


## The manor the debug "build" hook opens: the manifest's debug.build_node, else the first one.
func _debug_build_node(layer: Node) -> Node:
	var bn: String = str(Sites.get_value("debug", {}).get("build_node", ""))
	var n: Node = layer.find_child(bn, true, false) if bn != "" else null
	if n == null:
		var all := layer.find_children("*", "ManorController", true, false)
		n = all[0] if not all.is_empty() else null
	return n


func _update_map_blend() -> void:
	# slider 0..N-1 across the eras in order; each upper layer fades in over the ones below
	var v: float = map_slider.value
	var order := GameState.eras_in_order()
	for i in order.size():
		var r: TextureRect = map_rects.get(order[i].id)
		if r:
			r.modulate.a = 1.0 if i == 0 else clampf(v - (i - 1), 0.0, 1.0)
	map_markers.queue_redraw()


func _draw_markers(c: Control) -> void:
	var size := c.size
	var side := minf(size.x, size.y)
	var origin := (size - Vector2(side, side)) * 0.5
	for id in _locations:
		if not Journal.visited.has(id):
			continue
		var p: Vector2 = origin + _locations[id] / 1024.0 * side
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
## Ending tier from the site manifest "ending": count the "counted_flags" that are set, note the
## optional "bonus_flag", pick the first tier whose min_kept (and bonus, if required) is met.
func _show_ending() -> void:
	var rules: Dictionary = Sites.get_value("ending", {})
	var counted: Array = rules.get("counted_flags", [])
	var kept := 0
	for f in counted:
		if TimelineState.has_flag(str(f)):
			kept += 1
	var bonus_flag := str(rules.get("bonus_flag", ""))
	var bonus := bonus_flag != "" and TimelineState.has_flag(bonus_flag)
	var key := ""
	for tier in rules.get("tiers", []):
		if kept >= int(tier.get("min_kept", 0)) and (bonus or not bool(tier.get("bonus", false))):
			key = str(tier.get("key", ""))
			break
	var body := _clear_body(ending)
	body.get_node("Title").text = tr(key + "_TITLE") if key != "" else ""
	var t := Label.new()
	t.text = tr(key) if key != "" else ""
	if bonus and kept < counted.size() and rules.has("partial_key"):
		t.text += "\n\n" + tr(str(rules.partial_key))
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(700, 0)
	t.add_theme_font_size_override("font_size", 19)
	body.add_child(t)
	var kept_l := Label.new()
	kept_l.text = tr("ENDING_KEPT") % [kept, counted.size()]
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
