# All in-game UI, built in code: HUD (place, month, clock, cash), notices, the vakuraamat book
# (LedgerPanel, Tab), the town feed (NewsPanel, N), the journal, the K codes overlay, the debug map,
# the pause menu and F8 reports. Opening any panel frees the mouse and blocks gameplay input.
extends CanvasLayer

const GOLD := Color(0.85, 0.68, 0.25)
const PAPER := Color(0.93, 0.88, 0.76)
const INK := Color(0.16, 0.12, 0.08)

var world: Node3D
var player: CharacterBody3D
var interactor: Interactor

var hud: Control
var prompt_label: Label
var hover_label: Label
var notice_label: Label
var notice_card: PanelContainer
var compass: Control
var marker: Control
var era_label: Label
var keys_label: Label
var _notice_tween: Tween


var journal: PanelContainer
var debug_map: PanelContainer
var pause: PanelContainer
var report_panel: PanelContainer
var codes_label: Label            # K: cadastral number, building codes, road, registry links
var ledger_panel: LedgerPanel    # Tab: the town's book
var _guide: Dictionary = {}      # {tunnus, pos, label}: the plot the HUD arrow points at
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
	world = get_parent()
	player = world.get_node("Player")
	interactor = player.get_node("Camera3D/Interactor")
	interactor.target_changed.connect(_on_target_changed)
	_build_hud()
	journal = _build_panel("UI_JOURNAL")
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
	ledger_panel.guide.connect(guide_to)
	ledger_panel.teleport.connect(teleport_to)
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
	Ledger.event_added.connect(_on_ledger_event)
	pause.custom_minimum_size = Vector2(600, 0)
	debug_map.custom_minimum_size = Vector2(1180, 840)
	_center_panel(debug_map)
	move_child($Fade, get_child_count() - 1)
	EventBus.notice.connect(show_notice)
	EventBus.era_changed.connect(func(_e): _refresh_era_label())
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


## Point the HUD arrow at a plot (again on the same plot: clear it).
func guide_to(tunnus: String) -> void:
	if _guide.get("tunnus", "") == tunnus:
		_guide = {}
		return
	var p := Ledger.parcel(tunnus)
	if p.is_empty():
		return
	var pos := Vector3(float(p.x), 0.0, float(p.z))
	if world.terrain and world.terrain.data:
		pos.y = world.terrain.data.get_height(pos)
	_guide = {"tunnus": tunnus, "pos": pos + Vector3(0, 1.5, 0), "label": str(p.address)}
	_close()
	show_notice(tr("NOTICE_GUIDE_SET") % str(p.address))


## Jump to a plot: the game's teleport, the same as T and a click on the map.
func teleport_to(tunnus: String) -> void:
	var p := Ledger.parcel(tunnus)
	if p.is_empty():
		return
	_close()
	player.set_pose(Vector3(float(p.x), 200.0, float(p.z)), player.rotation.y, 0.0)
	world._snap(player, 1.0)
	if _guide.get("tunnus", "") == tunnus:
		_guide = {}
	show_notice(tr("NOTICE_TELEPORT") % [int(p.x), int(p.z)])


## World position the HUD arrow points at (the guided plot), or null.
func _objective_target() -> Variant:
	if _guide.is_empty():
		return null
	if player.global_position.distance_to(_guide.pos) < 12.0:
		show_notice(tr("NOTICE_GUIDE_ARRIVED") % str(_guide.label))
		_guide = {}
		return null
	return _guide.pos


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
	var font := BookTheme.font("plex_medium")
	if on_screen:
		var d := 9.0
		var diamond := PackedVector2Array([p + Vector2(0, -d), p + Vector2(d, 0), p + Vector2(0, d), p + Vector2(-d, 0)])
		marker.draw_colored_polygon(diamond, BookTheme.BLUE)
		diamond.append(diamond[0])
		marker.draw_polyline(diamond, BookTheme.PAGE_LIGHT, 1.5, true)
		marker.draw_string(font, p + Vector2(-29, -13), "%d m" % int(dist), HORIZONTAL_ALIGNMENT_CENTER, 60, 14, BookTheme.INK)
		marker.draw_string(font, p + Vector2(-30, -14), "%d m" % int(dist), HORIZONTAL_ALIGNMENT_CENTER, 60, 14, BookTheme.PAGE_LIGHT)
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
		marker.draw_colored_polygon(PackedVector2Array([tip, left, right]), BookTheme.BLUE)
		marker.draw_string(font, q - dir * 26 + Vector2(-29, 6), "%d m" % int(dist), HORIZONTAL_ALIGNMENT_CENTER, 60, 14, BookTheme.INK)
		marker.draw_string(font, q - dir * 26 + Vector2(-30, 5), "%d m" % int(dist), HORIZONTAL_ALIGNMENT_CENTER, 60, 14, BookTheme.PAGE_LIGHT)


func _draw_compass() -> void:
	var c := compass
	var w := c.size.x
	var h := c.size.y
	var heading := _heading_deg()
	var px_per_deg := w / 120.0            # the tape shows 120 degrees
	c.draw_rect(Rect2(0, 0, w, h), Color(BookTheme.PAGE, 0.88))
	c.draw_rect(Rect2(0, 0, w, h), BookTheme.INK, false, 1.0)
	var font := BookTheme.font("plex")
	for d in range(-180, 181, 15):
		var rel := fmod(d - heading + 540.0, 360.0) - 180.0
		if absf(rel) > 60.0:
			continue
		var x := w / 2 + rel * px_per_deg
		var deg := int(fmod(d + 360.0, 360.0))
		var big := deg % 90 == 0
		c.draw_line(Vector2(x, h - 6), Vector2(x, h - (14 if big else 10)), Color(BookTheme.INK, 0.8), 1.0)
		if big:
			var name: String = ["N", "E", "S", "W"][deg / 90]
			c.draw_string(font, Vector2(x - 6, 15), name, HORIZONTAL_ALIGNMENT_CENTER, 12, 15, BookTheme.RUBRIC if name == "N" else BookTheme.INK)
		elif deg % 45 == 0:
			c.draw_string(font, Vector2(x - 12, 15), str(deg), HORIZONTAL_ALIGNMENT_CENTER, 24, 10, BookTheme.FADED)
	c.draw_line(Vector2(w / 2, 2), Vector2(w / 2, h - 2), BookTheme.BLUE, 2.0)
	c.draw_string(font, Vector2(w / 2 + 6, h - 8), "%d°" % int(round(heading)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, BookTheme.BLUE)


# ---------------------------------------------------------------- building
func _build_hud() -> void:
	hud = Control.new()
	hud.theme = BookTheme.theme()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)
	# the running head: a page chip with the place, the month, the clock and the cash
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", BookTheme.page_box(true, 10))
	chip.position = Vector2(16, 12)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(chip)
	era_label = Label.new()
	era_label.add_theme_font_size_override("font_size", 15)
	era_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(era_label)
	keys_label = _label(hud, 13)
	keys_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 16)
	keys_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	keys_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	keys_label.custom_minimum_size = Vector2(820, 0)
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
	# notices: a page card with a rubric edge, faded after a moment
	notice_card = PanelContainer.new()
	var card := BookTheme.page_box(true, 12)
	card.border_color = BookTheme.RUBRIC
	card.border_width_left = 4
	notice_card.add_theme_stylebox_override("panel", card)
	notice_card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	notice_card.offset_left = -360
	notice_card.offset_right = 360
	notice_card.offset_top = 64
	notice_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	notice_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notice_card.modulate.a = 0.0
	hud.add_child(notice_card)
	notice_label = Label.new()
	notice_label.add_theme_font_size_override("font_size", 16)
	notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notice_card.add_child(notice_label)
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
	dot.color = Color(BookTheme.PAGE_LIGHT, 0.8)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(dot)


## HUD text over the world: page colour with an ink shadow.
func _label(parent: Control, size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", BookTheme.PAGE_LIGHT)
	l.add_theme_color_override("font_shadow_color", Color(BookTheme.INK, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _center_panel(p: Control) -> void:
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH


func _build_panel(title_key: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme = BookTheme.theme()
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
	t.theme_type_variation = "HeadLabel"
	t.text = tr(title_key) if title_key != "" else ""
	v.add_child(t)
	return p


# ---------------------------------------------------------------- HUD
func _objective() -> String:
	return tr("NOTICE_GUIDE_SET") % str(_guide.label) if not _guide.is_empty() else ""


func _refresh_era_label() -> void:
	var era := GameState.era(GameState.current_era)
	if era == null:
		era_label.text = ""
		return
	var badge := ("      " + tr("UI_ONLINE_BADGE")) if Ledger.online else ""
	era_label.text = "%s      %s      %s      %s%s" % [Sites.display_name(Sites.active), Ledger.date_string(), world.clock_string().left(5), Ledger.format_money(Ledger.cash()), badge]
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
	prompt_label.text = ("%s      " % lbl if lbl != "" else "") + "E  " + t.prompt()
	hover_label.text = t.hover_text()


func show_notice(text: String) -> void:
	if text.is_empty():
		return
	notice_label.text = text
	if _notice_tween:
		_notice_tween.kill()
	notice_card.modulate.a = 1.0
	_notice_tween = create_tween()
	_notice_tween.tween_interval(3.5 + text.length() * 0.03)
	_notice_tween.tween_property(notice_card, "modulate:a", 0.0, 1.0)


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
	var fillers := {ledger_panel: ledger_panel.fill, news_panel: news_panel.fill, report_panel: _fill_report, debug_map: _fill_debug_map, pause: _fill_pause}
	return fillers.get(p, _fill_journal)


func _toggle(p: PanelContainer, fill: Callable) -> void:
	if _open_panel == p:
		_close()
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
	b.add_theme_font_size_override("font_size", 17)
	b.custom_minimum_size = Vector2(0, 42)
	b.pressed.connect(cb)
	body.add_child(b)
	return b


# --- debug map (temporary): everything in the current era, click to teleport
const DEBUG_COLORS := {
	"Examinable": Color(1, 1, 1), "Bicycle": Color(0.3, 0.9, 1.0),
}


func _fill_debug_map() -> void:
	var body := _clear_body(debug_map)
	body.get_node("Title").text = tr("UI_DEBUG_MAP") + "   ·   " + Sites.active + "   ·   " + Ledger.date_string()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	body.add_child(row)
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
		"journal": _toggle(journal, _fill_journal)
		"map": _toggle(debug_map, _fill_debug_map)
		"ledger": _toggle(ledger_panel, ledger_panel.fill)
		"town":
			ledger_panel.tabs.current_tab = 4
			_toggle(ledger_panel, ledger_panel.fill)
		"news": _toggle(news_panel, news_panel.fill)
		"menu": _toggle(pause, _fill_pause)


# --- journal (J): my own ledger lines and the codex
func _fill_journal() -> void:
	var body := _clear_body(journal)
	body.get_node("Title").text = tr("UI_JOURNAL")
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(tabs)
	var scroll := ScrollContainer.new()
	scroll.name = tr("UI_LEDGER")
	tabs.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)
	var mine := Ledger.events(200, true)
	if mine.is_empty():
		BookTheme.label(tr("UI_LEDGER_EMPTY"), "ProseLabel", box)
	var grid := GridContainer.new()
	grid.columns = 3
	box.add_child(grid)
	for e in mine:
		BookTheme.label(Ledger.date_for(int(e.month)), "DetailLabel", grid)
		var l := BookTheme.label(str(e.title), "", grid)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var amount := int(e.amount)
		var a := BookTheme.label(("%+s" % BookTheme.money(amount)) if amount > 0 else (BookTheme.money(amount) if amount < 0 else ""), "", grid)
		a.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		a.custom_minimum_size = Vector2(120, 0)
		if amount != 0:
			a.add_theme_color_override("font_color", BookTheme.GREEN if amount > 0 else BookTheme.RUBRIC)
	var codex := ScrollContainer.new()
	codex.name = tr("UI_CODEX")
	tabs.add_child(codex)
	var cbox := VBoxContainer.new()
	cbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cbox.add_theme_constant_override("separation", 8)
	codex.add_child(cbox)
	for k in Sites.get_value("codex", []):
		BookTheme.label(tr(str(k) + "_TITLE"), "SubheadLabel", cbox)
		var l := BookTheme.label(tr(str(k)), "ProseLabel", cbox)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(700, 0)


## Offers on my plots and sales of them become notices; everything else waits in the feed.
func _on_ledger_event(e: Dictionary) -> void:
	var tunnus := str(e.get("tunnus", ""))
	if tunnus == "" or not Ledger.is_mine(tunnus):
		return
	if str(e.kind) == "bid" and int(e.actor_id) != Ledger.me_id():
		show_notice(tr("NOTICE_BID_RECEIVED") % [Ledger.parcel(tunnus).get("address", tunnus), int(e.amount)])
