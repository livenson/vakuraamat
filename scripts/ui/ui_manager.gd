# All in-game UI, built in code: HUD (place, clock), notices, the vakuraamat book
# (BookPanel, Tab), the journal, the K codes overlay, the debug map,
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
var legend_card: PanelContainer     # the ground layer's key, while one is showing
var _notice_tween: Tween


var journal: PanelContainer
var debug_map: PanelContainer
var sheet_panel: PanelContainer     # a readable's page (notice board, register extract)
var pause: PanelContainer
var report_panel: PanelContainer
var codes_label: Label            # K: cadastral number, building codes, road, registry links
var book: BookPanel              # Tab: what the registers say about this place
var _guide: Dictionary = {}      # {tunnus, pos, label}: the plot the HUD arrow points at
var _focus: Dictionary = {}      # {tunnus, address, parcels, buildings}: the plot lit in every view
var find_bar: FindBar            # /: find an address, a company or a street in the town
var codes_on := false
var _codes_lines: MeshInstance3D = null
var _debug_canvas: Control
var _debug_bg: TextureRect
var _debug_bg_tile := Vector2i(9999, 9999)
var _tile_ortho: Dictionary = {}      # pack id -> ImageTexture of its orthophoto (debug map background)
var _map_layers: Dictionary = {}      # pack id -> {streets, numbers} read from roads.json and buildings.json
var _map_layout: Dictionary = {}      # the last label layout of the debug map (see _lay_out_map)
var _map_hover := Vector2(-1, -1)     # mouse position over the debug map canvas
var _map_hover_plot := ""             # checks: hold the slip over this plot (--open=hover:<tunnus>)
var _hover_key := ""                  # the place the slip is about, so it is written once, not per frame
var _hover_lines: Array = []          # [text, size, colour] of the slip under the mouse
var _map_mode := "off"                # company layer of the debug map: off, sector, size, health, age, owners (MapPalette.MODES)
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
	sheet_panel = _build_panel("")
	sheet_panel.custom_minimum_size = Vector2(940, 660)   # room for the plot's strip of years under the sheet
	pause = _build_panel("UI_MENU")
	report_panel = _build_panel("UI_REPORT_TITLE")
	report_panel.custom_minimum_size = Vector2(640, 0)
	book = BookPanel.new()
	add_child(book)
	book.setup(world)
	_center_panel(book)
	book.show_parcel.connect(func(t):
		var marks: Node = world.get_node_or_null("ParcelMarks")
		if marks:
			marks.flash(t))
	book.guide.connect(guide_to)
	book.teleport.connect(teleport_to)
	book.focus.connect(focus_parcel)
	find_bar = FindBar.new()
	add_child(find_bar)
	find_bar.setup()
	find_bar.visible = false
	# near the top rather than the middle: the world stays visible under it while you type
	find_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	find_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	find_bar.grow_vertical = Control.GROW_DIRECTION_END
	find_bar.offset_top += 110
	find_bar.offset_bottom += 110
	find_bar.guide.connect(func(tunnus: String, pos: Vector2, label: String):
		_close()
		if tunnus != "":
			guide_to(tunnus)
		else:
			guide_to_point(pos, label))
	find_bar.go.connect(func(_t: String, pos: Vector2, label: String):
		_close()
		jump_to_point(pos, label))
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
	var p := Parcels.by_tunnus(tunnus)
	if p.is_empty():
		return
	var pos := Vector3(float(p.x), 0.0, float(p.z))
	if world.terrain and world.terrain.data:
		pos.y = world.terrain.data.get_height(pos)
	_guide = {"tunnus": tunnus, "pos": pos + Vector3(0, 1.5, 0), "label": str(p.address)}
	_close()
	show_notice(tr("NOTICE_GUIDE_SET") % str(p.address))


## Light one plot and everything the registers tie it to, in the book, on the map and on the ground
## (again on the same plot: clear it). What was resolved is kept here rather than looked up again:
## the HUD line is rebuilt every frame and Parcels.by_tunnus walks the standing tiles.
func focus_parcel(tunnus: String) -> void:
	if _focus == null:
		_focus = {}
	if tunnus == "" or _focus.get("tunnus", "") == tunnus:
		var had := not _focus.is_empty()
		_focus = {}
		EventBus.parcel_focused.emit("")
		if had:
			show_notice(tr("UI_FOCUS_CLEARED"))
		return
	var l := Links.of(tunnus)
	if l.pack == "":
		return   # not on a tile standing right now
	var linked: Array = l.parcels.map(func(s): return str(s.tunnus))
	_focus = {"tunnus": tunnus, "address": str(l.address) if str(l.address) != "" else tunnus,
		"links": linked, "buildings": l.buildings.size()}
	EventBus.parcel_focused.emit(tunnus)
	show_notice(tr("UI_FOCUS_ON") % _focus.address)


## The layer both views share. The map draws it as fills, circles or lines; the ground takes the
## ones that are a colour per plot, so choosing a layer on the map and closing it leaves the town
## colour-coded around you.
func set_map_mode(which: String) -> void:
	if which.begins_with("focus:"):   # the one-sector layer with its sector: focus:trade
		MapPalette.focus_sector = which.trim_prefix("focus:")
		which = "focus"
	_map_mode = which
	var views: Node = world.get_node_or_null("InfoViews") if world else null
	if views:
		views.set_mode(_map_mode)
	_refresh_legend()


## The layer's name as the button, the notice and both legends say it; the one-sector layer names
## its sector.
func _mode_title() -> String:
	var t := tr("UI_MAP_MODE_" + _map_mode.to_upper())
	return t + ": " + tr("SECTOR_" + MapPalette.focus_sector.to_upper()) if _map_mode == "focus" else t


## The key to the layer on the ground: one row per class, the same colours and the same words the
## map's own legend uses. Hidden whenever the ground is showing nothing.
func _refresh_legend() -> void:
	if legend_card == null:
		return
	for c in legend_card.get_children():
		c.queue_free()
	legend_card.visible = _map_mode in InfoViews.FILLS
	if not legend_card.visible:
		return
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	legend_card.add_child(box)
	BookTheme.label(_mode_title(), "DetailLabel", box)
	for item in MapPalette.legend(_map_mode):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		box.add_child(row)
		var swatch := ColorRect.new()
		swatch.color = item[1]
		swatch.custom_minimum_size = Vector2(11, 11)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)
		BookTheme.label(tr(str(item[0])), "DetailLabel", row)


## Jump to a plot: the game's teleport, the same as T and a click on the map.
func teleport_to(tunnus: String) -> void:
	var p := Parcels.by_tunnus(tunnus)
	if p.is_empty():
		return
	_close()
	player.set_pose(Vector3(float(p.x), 200.0, float(p.z)), player.rotation.y, 0.0)
	world._snap(player, 1.0)
	if _guide.get("tunnus", "") == tunnus:
		_guide = {}
	show_notice(tr("NOTICE_TELEPORT") % [int(p.x), int(p.z)])


## Point the arrow at a place that is not one of the town's plots - a street, or a building whose
## plot the cadastre does not carry - so the find bar can offer those too.
func guide_to_point(at: Vector2, label: String) -> void:
	var pos := Vector3(at.x, 0.0, at.y)
	if world.terrain and world.terrain.data:
		pos.y = world.terrain.data.get_height(pos)
	_guide = {"tunnus": "", "pos": pos + Vector3(0, 1.5, 0), "label": label}
	show_notice(tr("NOTICE_GUIDE_SET") % label)


## Jump to a place by position, the same as teleport_to does by plot.
func jump_to_point(at: Vector2, label: String) -> void:
	player.set_pose(Vector3(at.x, 200.0, at.y), player.rotation.y, 0.0)
	world._snap(player, 1.0)
	_guide = {}
	show_notice(tr("NOTICE_TELEPORT_TO") % label)


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
	# the ground layer's key, on the right so it never sits under the crosshair's readout
	legend_card = PanelContainer.new()
	legend_card.add_theme_stylebox_override("panel", BookTheme.page_box(true, 10))
	legend_card.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	legend_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	legend_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	legend_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	legend_card.visible = false
	hud.add_child(legend_card)
	hover_label = _label(hud, 18)
	_below_crosshair(hover_label, 620, 40)
	hover_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt_label = _label(hud, 18)
	_below_crosshair(prompt_label, 400, 120)
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


## A HUD line centred under the crosshair: anchors at the screen centre, `width` wide, `dy` below.
func _below_crosshair(l: Label, width: float, dy: float) -> void:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_CENTER)
	l.offset_left = -width * 0.5
	l.offset_right = width * 0.5
	l.offset_top = dy
	l.offset_bottom = dy + 28
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.grow_vertical = Control.GROW_DIRECTION_END


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
	era_label.text = "%s      %s" % [Sites.display_name(Sites.active), world.clock_string().left(5)]
	var obj := _objective()
	if obj != "":
		era_label.text += "\n" + obj
	if _focus != null and not _focus.is_empty():
		era_label.text += "\n" + tr("UI_FOCUS_ON") % str(_focus.address)
	if world.streamer and world.streamer.has_method("loading_status"):
		var busy: String = world.streamer.loading_status()
		if busy != "":
			era_label.text += "\n" + tr("UI_LOADING_TILE") % busy
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
	if notice_card and notice_card.get_parent():
		notice_card.get_parent().move_child(notice_card, -1)   # above any open panel
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
	if event.is_action_pressed("book"):
		_toggle(book, book.fill)
	elif event.is_action_pressed("find"):
		if _open_panel == find_bar:
			_close()
		else:
			_close()
			find_bar.open_at(Vector2(player.global_position.x, player.global_position.z))
			_open(find_bar)
	elif event.is_action_pressed("plot_here"):
		_plot_here()
	elif event.is_action_pressed("journal"):
		_toggle(journal, _fill_journal)
	elif event.is_action_pressed("debug_map"):
		_toggle(debug_map, _fill_debug_map)
	elif event.is_action_pressed("info_view"):
		# step through the layers the ground can show, without opening the map for it
		var fills: Array = ["off"] + InfoViews.FILLS
		var at := fills.find(_map_mode)
		set_map_mode(str(fills[(at + 1) % fills.size()] if at >= 0 else fills[1]))
		show_notice(tr("UI_MAP_MODE") + ": " + _mode_title())
	elif event.is_action_pressed("language"):
		show_notice(Lang.cycle())
		_refresh_era_label()
		if _open_panel:
			var p := _open_panel
			_close()
			_toggle(p, _filler_for(p))


## A readable's page: the title as the head, the text as prose; any panel key closes it.
## A readable's page. With `tunnus`, the sheet is a building's, and it also carries the plot it
## stands on: the land over the years and a way into the book's plot page, because a building's own
## register line does not say what the ground under it was doing before it was built.
func show_sheet(title: String, text: String, tunnus: String = "") -> void:
	var body := _clear_body(sheet_panel)
	body.get_node("Title").text = title
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_SHRINK_BEGIN   # the strip keeps its height; the page scrolls
	page.add_theme_constant_override("separation", 8)
	scroll.add_child(page)
	var prose := BookTheme.label(text, "ProseLabel", page)
	prose.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prose.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if tunnus != "" and PlotStrip.can_show(world, tunnus):
		var strip := PlotStrip.new()
		page.add_child(strip)
		strip.setup(world, tunnus)
		var open_book := Button.new()
		open_book.text = tr("UI_SHEET_OPEN_PLOT")
		open_book.pressed.connect(func():
			_close()
			book.open_parcel(tunnus)
			_open(book))
		var row := HBoxContainer.new()
		row.add_child(open_book)
		page.add_child(row)
	var hint := BookTheme.label(tr("UI_SHEET_CLOSE"), "DetailLabel", body)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if _open_panel and _open_panel != sheet_panel:
		_close()
	_open(sheet_panel)


func _filler_for(p: Control) -> Callable:
	var fillers := {book: book.fill, report_panel: _fill_report, debug_map: _fill_debug_map, pause: _fill_pause}
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
		for k in links:   # every register and map link the place has, whichever country's
			if str(links[k]).begins_with("http"):
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
		if u.get("land_value") != null:
			lines.append("   %s: %s   %s: %s" % [tr("UI_CODES_OWNER"), str(u.get("ownership", "")),
				tr("UI_BOOK_COL_VALUE"), BookTheme.money(int(u.land_value))])
		var rows := Tenants.of(Sites.pack_of(layer), str(u.tunnus))
		if not rows.is_empty():
			lines.append("   " + tr("UI_CODES_TENANT") + ":")
			for t in rows:
				lines.append("      " + Tenants.headline(t) + ("   " + Tenants.facts(t) if Tenants.facts(t) != "" else ""))
	var links := Reporter.links_for(pos, interactor.target, layer)
	if links.has("etak_id"):
		lines.append(tr("UI_CODES_BUILDING") + ": #%d   %s" % [int(links.etak_id), str(links.get("ehr", links.get("building_code", "")))])
	var road := Reporter._nearest_road(layer, pos)
	if not road.is_empty():
		lines.append(tr("UI_CODES_ROAD") + ": %s %s %s m %s (%.0f m)" % [str(road.get("name", "") if road.get("name") else ""), str(road.get("type", "")), str(road.get("width", "")), str(road.get("surface", "") if road.get("surface") else ""), float(road.get("distance", 0))])
	if interactor.target:
		lines.append(tr("UI_CODES_TARGET") + ": %s  %s" % [interactor.target.name, str(interactor.target.get_path())])
	codes_label.text = "\n".join(lines)
	_draw_parcel(u)


## B: open the book at the plot under the player's feet.
func _plot_here() -> void:
	if _open_panel and _open_panel != book:
		return
	var u := Parcels.at(player.global_position)
	if u.is_empty():
		show_notice(tr("UI_NO_PLOT_HERE"))
		return
	book.open_parcel(u.tunnus)
	if _open_panel != book:
		_open(book)


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
		Lang.cycle()
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
	body.get_node("Title").text = tr("UI_DEBUG_MAP") + "   ·   " + Sites.active
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	body.add_child(row)
	var bm := Button.new()
	bm.text = tr("UI_MAP_MODE") + ": " + tr("UI_MAP_MODE_" + _map_mode.to_upper())   # the sector has its own button
	bm.pressed.connect(func():
		set_map_mode(MapPalette.MODES[(MapPalette.MODES.find(_map_mode) + 1) % MapPalette.MODES.size()])
		_fill_debug_map())
	row.add_child(bm)
	if _map_mode == "focus":
		var bs := Button.new()
		bs.text = tr("UI_MAP_FOCUS_PICK") % tr("SECTOR_" + MapPalette.focus_sector.to_upper())
		bs.pressed.connect(func():
			set_map_mode("focus:" + MapPalette.next_sector())
			_fill_debug_map())
		row.add_child(bs)
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
## Labels are laid out once per tile and player move (`_lay_out_map`): every point gets a dot,
## a label only where it does not overlap one already placed; the point under the mouse always
## shows its label.
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
	var pp := origin + (Vector2(player.global_position.x, player.global_position.z) - off) / 1024.0 * side
	if _map_layout.is_empty() or _map_layout.loc != loc or _map_layout.pack != pack or _map_layout.side != side \
			or _map_layout.origin != origin or pp.distance_to(_map_layout.at) > side * 0.06:
		_lay_out_map(origin, side, loc, pack, pp)
	if _map_mode != "off":
		_draw_company_layer(c, origin, side, pack)
	_draw_focus_layer(c, origin, side, pack)
	for d in _map_layout.dots:
		c.draw_circle(d.pos, 4, d.col)
		c.draw_circle(d.pos, 4, Color.BLACK, false, 1.0)
	for l in _map_layout.labels:
		if l.angle != 0.0:
			c.draw_set_transform(l.pos, l.angle)
			c.draw_string(font, Vector2(-l.w * 0.5 + 1, 1 + l.dy), l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.size, Color(0, 0, 0, 0.8))
			c.draw_string(font, Vector2(-l.w * 0.5, l.dy), l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.size, l.col)
			c.draw_set_transform(Vector2.ZERO)
		else:
			c.draw_string(font, l.pos + Vector2(1, 1), l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.size, Color(0, 0, 0, 0.8))
			c.draw_string(font, l.pos, l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.size, l.col)
	if _map_mode != "off":
		_draw_company_legend(c, origin, side, font)
	# what is under the mouse, on a slip of paper, on top of everything
	_draw_hover_card(c, origin, side, pack, font)
	# the player and heading
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


## The focused plot and what it is linked to, drawn in every layer mode including "off": the plot
## itself filled and outlined, the plots sharing an owner outlined, and a line to each of them.
func _draw_focus_layer(c: Control, origin: Vector2, side: float, pack: String) -> void:
	if _focus == null or _focus.is_empty():
		return
	var k := side / 1024.0
	var linked: Array = _focus.get("links", [])
	var mine := Vector2.ZERO
	var others: Array[Vector2] = []
	for pr in _map_layer(pack).get("parcels", []):
		var is_focus: bool = str(pr.tunnus) == str(_focus.tunnus)
		if not is_focus and not (str(pr.tunnus) in linked):
			continue
		var pts := PackedVector2Array()
		for q in pr.poly:
			pts.append(origin + Vector2(float(q[0]), float(q[1])) * k)
		if pts.size() < 3:
			continue
		pts.append(pts[0])
		# a town plot is thirty pixels across on a map of a square kilometre, so the mark has to be
		# heavier than the boundary it draws: a dark backing stroke, then the blue over it
		if is_focus:
			mine = origin + Vector2(pr.at) * k
			c.draw_colored_polygon(pts, Color(BookTheme.BLUE, 0.45))
			c.draw_polyline(pts, Color(BookTheme.INK, 0.8), 4.0)
			c.draw_polyline(pts, Color(BookTheme.PAGE_LIGHT, 0.95), 2.0)
		else:
			others.append(origin + Vector2(pr.at) * k)
			c.draw_colored_polygon(pts, Color(BookTheme.BLUE, 0.22))
			c.draw_polyline(pts, Color(BookTheme.INK, 0.7), 3.0)
			c.draw_polyline(pts, Color(BookTheme.BLUE.lightened(0.4), 0.95), 1.5)
	if mine == Vector2.ZERO:
		return
	for o in others:
		c.draw_line(mine, o, Color(BookTheme.INK, 0.7), 4.0)
		c.draw_line(mine, o, Color(BookTheme.PAGE_LIGHT, 0.9), 2.0)
		c.draw_circle(o, 5.0, Color(BookTheme.BLUE, 0.95))
		c.draw_circle(o, 5.0, BookTheme.PAGE_LIGHT, false, 1.5)
	c.draw_circle(mine, 7.0, Color(BookTheme.BLUE, 0.95))
	c.draw_circle(mine, 7.0, BookTheme.PAGE_LIGHT, false, 2.0)


## What the register says about the place under the mouse, as a slip of paper: whatever the nearest
## point is called, then the plot it stands on - its use, its size, its 2022 value, the companies
## registered on it and what it is linked to. Hovering bare ground answers with the plot too, which
## is the whole point: the coloured shapes on this map used to say nothing at all.
##
## The map redraws every frame, so the text is built only when the plot under the mouse changes.
func _draw_hover_card(c: Control, origin: Vector2, side: float, pack: String, font: Font) -> void:
	if _map_hover_plot != "":
		for pr in _map_layer(pack).get("parcels", []):
			if str(pr.tunnus) == _map_hover_plot:
				_map_hover = origin + Vector2(pr.at) * (side / 1024.0)
				break
	if _map_hover.x < 0:
		return
	var near: Dictionary = {}
	var best := 12.0
	for d in _map_layout.dots:
		var dist: float = d.pos.distance_to(_map_hover)
		if dist < best:
			best = dist
			near = d
	var at := (_map_hover - origin) / (side / 1024.0)   # tile metres
	var tunnus := ""
	for pr in _map_layer(pack).get("parcels", []):
		var poly := PackedVector2Array()
		for q in pr.poly:
			poly.append(Vector2(float(q[0]), float(q[1])))
		if poly.size() >= 3 and Geometry2D.is_point_in_polygon(at, poly):
			tunnus = str(pr.tunnus)
			break
	var title := str(near.get("text", "")) if not near.is_empty() else ""
	var key := "%s|%s" % [title, tunnus]
	if key == "|":
		return
	if _hover_key != key:
		_hover_key = key
		_hover_lines = _hover_card_lines(title, tunnus, pack)
	if _hover_lines.is_empty():
		return
	var w := 0.0
	for line in _hover_lines:
		w = maxf(w, font.get_string_size(str(line[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(line[1])).x)
	var anchor: Vector2 = near.pos if not near.is_empty() else _map_hover
	var size := Vector2(w + 16, 8.0 + _hover_lines.size() * 16.0)
	var pos := anchor + Vector2(12, -12)
	if pos.x + size.x > origin.x + side:
		pos.x = anchor.x - size.x - 12
	if pos.y + size.y > origin.y + side:
		pos.y = origin.y + side - size.y
	var box := Rect2(pos, size)
	c.draw_rect(box, Color(BookTheme.PAGE, 0.96))
	c.draw_rect(box, BookTheme.INK, false, 1.0)
	var y := pos.y + 16.0
	for line in _hover_lines:
		c.draw_string(font, Vector2(pos.x + 8, y), str(line[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(line[1]), line[2])
		y += 16.0


## The lines of the slip: [text, size, colour]. Nothing a register does not carry is written, so a
## plot with no companies simply has fewer lines.
func _hover_card_lines(title: String, tunnus: String, pack: String) -> Array:
	var out: Array = []
	if title != "":
		out.append([title, 14, BookTheme.INK])
	if tunnus == "":
		return out
	var u := Parcels.by_tunnus(tunnus)
	if u.is_empty():
		for pr in _map_layer(pack).get("parcels", []):
			if str(pr.tunnus) == tunnus:
				out.append([tunnus, 12, BookTheme.FADED])
				return out
		return out
	var address := str(u.get("address", ""))
	if address != "" and address != title:
		out.append([address, 13 if title == "" else 12, BookTheme.INK if title == "" else BookTheme.FADED])
	var purpose := tr("PURPOSE_" + Parcels.purpose_of(u))
	out.append(["%s, %d m²" % [purpose if not purpose.begins_with("PURPOSE_") else "", int(u.get("area", 0))], 12, BookTheme.FADED])
	var value = u.get("land_value")
	if value != null and float(value) > 0:
		out.append([tr("UI_BOOK_COL_VALUE") + ": " + BookTheme.money(int(float(value))), 12, BookTheme.FADED])
	var rows := Tenants.of(pack, tunnus)
	for t in rows.slice(0, 3):
		var bits := str(t.get("name", ""))
		var emp = t.get("employees")
		if emp != null and int(emp) > 0:
			bits += "   " + tr("UI_EMPLOYEES") % int(emp)
		out.append([bits, 12, BookTheme.RUBRIC if str(t.get("health", "")) == "distressed" else BookTheme.INK])
	if rows.size() > 3:
		out.append([tr("UI_MORE_COMPANIES") % (rows.size() - 3), 11, BookTheme.FADED])
	var l := Links.of(tunnus)
	if not l.buildings.is_empty():
		out.append([tr("UI_LINK_BUILDINGS") % l.buildings.size(), 11, BookTheme.FADED])
	if not l.parcels.is_empty():
		out.append([tr("UI_LINK_PLOTS") % l.parcels.size(), 11, BookTheme.BLUE])
	return out


## The company layer: parcels filled by their dominant tenant (sector, health, founding age), dots
## sized by employees, or lines between parcels whose companies share an owner; with a legend.
func _draw_company_layer(c: Control, origin: Vector2, side: float, pack: String) -> void:
	var k := side / 1024.0
	var layer := _map_layer(pack)
	var parcels: Array = layer.get("parcels", [])
	for pr in parcels:
		# the company this layer shows: the worst verdict in the health layer, the largest active one else
		var tenant: Dictionary = MapPalette.pick(_map_mode, pr.get("rows", [])) if pr.has("rows") else pr.tenant
		if _map_mode in ["mix", "focus"]:
			_draw_share_fill(c, origin, k, pr)
			continue
		var col: Color = MapPalette.colour(_map_mode, tenant)
		if _map_mode in ["size", "owners"] and tenant.is_empty():
			continue
		if _map_mode == "size":
			var n := float(tenant.get("employees", 0) if tenant.get("employees") != null else 0)
			if n <= 0.0:
				continue
			var r := clampf(3.0 + sqrt(n) * 2.2, 3.0, 40.0) * k * (1024.0 / 700.0)
			c.draw_circle(origin + Vector2(pr.at) * k, r, Color(0.3, 0.6, 1.0, 0.45))
			c.draw_circle(origin + Vector2(pr.at) * k, r, Color(0.15, 0.3, 0.6), false, 1.0)
			continue
		if _map_mode == "owners":
			continue
		col.a = 0.38 if not tenant.is_empty() else col.a
		for piece in pr.get("polys", []):
			var pts := PackedVector2Array()
			for q in piece:
				pts.append(origin + q * k)
			c.draw_colored_polygon(pts, col)
			c.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(col.r, col.g, col.b, 0.8), 1.0)
	if _map_mode == "owners":
		var by_hash := {}
		for pr in parcels:
			for h in pr.get("owners", []):
				by_hash.get_or_add(str(h), []).append(pr)
		var drawn := {}
		for h in by_hash:
			var group: Array = by_hash[h]
			for i in group.size():
				for j in range(i + 1, group.size()):
					var key := str(group[i].tunnus) + "|" + str(group[j].tunnus)
					if drawn.has(key) or group[i].tunnus == group[j].tunnus:
						continue
					drawn[key] = true
					c.draw_line(origin + Vector2(group[i].at) * k, origin + Vector2(group[j].at) * k, Color(1.0, 0.85, 0.3, 0.8), 1.5)
		for pr in parcels:
			if not pr.get("owners", []).is_empty():
				c.draw_circle(origin + Vector2(pr.at) * k, 3.0, Color(1.0, 0.85, 0.3))


## A plot in the two layers that show all of its companies rather than the largest: striped by its
## sectors' shares ("mix") or shaded by the chosen sector's share ("focus"). The shares and the
## stripes are worked out once per plot, in tile metres, and kept on the cached parcel.
func _draw_share_fill(c: Control, origin: Vector2, k: float, pr: Dictionary) -> void:
	var polys: Array = pr.get("polys", [])
	if polys.is_empty():
		return
	if not pr.has("shares"):
		pr["shares"] = MapPalette.shares(pr.get("rows", []))
	var parts: Dictionary = pr.shares
	var pieces: Array = []
	if _map_mode == "mix" and not parts.is_empty():
		if not pr.has("stripes"):
			var cut: Array = []
			for poly in polys:
				cut.append_array(MapPalette.stripes(poly, parts, MapPalette.STRIPE_M))
			pr["stripes"] = cut
		pieces = pr.stripes
	else:
		var share := float(parts.get(MapPalette.focus_sector, 0.0))
		var fill: Color = MapPalette.focus_colour(share) if _map_mode == "focus" and share > 0.0 else MapPalette.NO_TENANT
		for poly in polys:
			pieces.append([poly, fill])
	for piece in pieces:
		var pts := PackedVector2Array()
		for q in piece[0]:
			pts.append(origin + q * k)
		var col: Color = piece[1]
		if col != MapPalette.NO_TENANT:
			col.a = 0.55   # stronger than the one-colour layers' 0.38: a stripe is thin
		var tris: PackedInt32Array = piece[2] if piece.size() > 2 else PackedInt32Array()
		if not tris.is_empty():
			# the stripe's own triangles (MapPalette.stripes): the canvas does not triangulate again
			var cols := PackedColorArray()
			cols.resize(pts.size())
			cols.fill(col)
			RenderingServer.canvas_item_add_triangle_array(c.get_canvas_item(), tris, pts, cols)
		elif pts.size() >= 3:
			c.draw_colored_polygon(pts, col)
	for poly in polys:
		var outline := PackedVector2Array()
		for q in poly:
			outline.append(origin + q * k)
		outline.append(outline[0])
		c.draw_polyline(outline, Color(0.1, 0.1, 0.1, 0.45), 1.0)


## The company layer's legend: one line per class and the layer's note. Drawn after the dots and the
## street labels, so a legend that has to sit inside the map is not written over.
func _draw_company_legend(c: Control, origin: Vector2, side: float, font: Font) -> void:
	# legend: one line per class, in the page beside the map. The map is square and the panel is not,
	# so there is a margin either side of it; putting the legend there stops it covering the plots it
	# is explaining. Only if that margin is too narrow does it sit inside, bottom right, as it used to.
	var items: Array = MapPalette.legend(_map_mode)
	var title := _mode_title()
	var w := 150.0
	for it in items:
		w = maxf(w, font.get_string_size(tr(str(it[0])), HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 30.0)
	var note := tr(MapPalette.note(_map_mode)) if MapPalette.note(_map_mode) != "" else ""
	var note_h := 0.0
	if note != "":
		w = maxf(w, 240.0 if note.length() > 160 else 190.0)   # the health note runs to four sentences
		note_h = 6.0 + font.get_multiline_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, w - 12.0, 10).y
	var h := 20.0 + items.size() * 15.0 + note_h
	var margin := c.size.x - (origin.x + side)
	var box := Rect2(origin + Vector2(side + 10, 0), Vector2(w, h)) if margin >= w + 14 \
		else Rect2(origin + Vector2(side - w - 8, side - h - 24), Vector2(w, h))
	c.draw_rect(box, Color(BookTheme.PAGE, 0.92))
	c.draw_rect(box, BookTheme.INK, false, 1.0)
	c.draw_string(font, box.position + Vector2(6, 14), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, BookTheme.INK)
	for i in items.size():
		var y := box.position.y + 26 + i * 15
		c.draw_rect(Rect2(box.position.x + 6, y - 9, 10, 10), items[i][1])
		c.draw_string(font, Vector2(box.position.x + 20, y), tr(str(items[i][0])), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, BookTheme.INK)
	if note != "":
		var ny := box.position.y + 26 + items.size() * 15 + 4
		c.draw_multiline_string(font, Vector2(box.position.x + 6, ny), note, HORIZONTAL_ALIGNMENT_LEFT, w - 12.0, 10, -1, BookTheme.FADED)


## Lay the map's text out without overlaps: street names along their longest stretch first, then
## house numbers, then the points' labels nearest the player first, each kept only if its box is
## free. Dots are kept for every point (the hover readout names them).
func _lay_out_map(origin: Vector2, side: float, loc: Vector2i, pack: String, pp: Vector2) -> void:
	var font := ThemeDB.fallback_font
	var off := Vector2(loc.x, loc.y) * 1024.0
	var k := side / 1024.0
	var taken: Array[Rect2] = []
	var labels: Array = []
	var dots: Array = []
	var layer := _map_layer(pack)
	var frame := Rect2(origin, Vector2(side, side))
	for st in layer.get("streets", []):
		var w := font.get_string_size(st.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var pos: Vector2 = origin + Vector2(st.at) * k
		if not frame.grow(-w * 0.5).has_point(pos):
			continue   # the name would run off the plate: the stretch is at the tile's edge
		var ext := Vector2(absf(w * cos(st.angle)) + absf(12 * sin(st.angle)), absf(w * sin(st.angle)) + absf(12 * cos(st.angle)))
		if _map_take(taken, Rect2(pos - ext * 0.5, ext)):
			labels.append({"pos": pos, "text": st.name, "col": Color(1, 1, 1), "size": 12, "angle": st.angle, "w": w, "dy": -4})
	for hn in layer.get("numbers", []):
		var w := font.get_string_size(hn.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
		var pos: Vector2 = origin + Vector2(hn.at) * k - Vector2(w * 0.5, -3)
		if not frame.has_point(pos):
			continue
		if _map_take(taken, Rect2(pos + Vector2(0, -8), Vector2(w, 9))):
			labels.append({"pos": pos, "text": hn.text, "col": Color(1, 0.96, 0.8), "size": 9, "angle": 0.0, "w": w, "dy": 0})
	var era_layer: Node = world.get_node("EraLayers").get_node_or_null(GameState.current_era)
	if era_layer and loc == Vector2i.ZERO:
		for n in era_layer.find_children("*", "Interactable", true, false):
			if not n.visible or not n.is_visible_in_tree():
				continue
			var kind := "Examinable"
			for kk in DEBUG_COLORS:
				if n.get_class() == kk or (n.get_script() and n.get_script().get_global_name() == kk):
					kind = kk
			var p: Vector2 = origin + (Vector2(n.global_position.x, n.global_position.z) - off) * k
			if not Rect2(origin, Vector2(side, side)).grow(6).has_point(p):
				continue   # a neighbour tile's point
			var text: String = n.label() if n.label() != "" else n.name
			dots.append({"pos": p, "text": text, "col": DEBUG_COLORS.get(kind, Color.WHITE)})
	dots = dots.filter(func(d): return d.pos.is_finite())   # an agent mid-teleport has no place on the map
	dots.sort_custom(func(a, b): return a.pos.distance_squared_to(pp) < b.pos.distance_squared_to(pp))
	for d in dots:
		var w := font.get_string_size(d.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		var pos: Vector2 = d.pos + Vector2(7, 4)
		if _map_take(taken, Rect2(pos + Vector2(-1, -10), Vector2(w + 2, 12))):
			labels.append({"pos": pos, "text": d.text, "col": d.col, "size": 11, "angle": 0.0, "w": w, "dy": 0})
	_map_layout = {"loc": loc, "pack": pack, "side": side, "origin": origin, "at": pp, "dots": dots, "labels": labels}


## Claim `r` on the map if it overlaps nothing claimed before.
func _map_take(taken: Array[Rect2], r: Rect2) -> bool:
	for t in taken:
		if t.intersects(r):
			return false
	taken.append(r)
	return true


## Street names and house numbers of a pack's tile, from its roads.json and buildings.json (read
## once): each named street labelled once, at the middle of its longest stretch, along it; each
## addressed building's number at its centre. Positions in tile metres.
func _map_layer(pack: String) -> Dictionary:
	if _map_layers == null:
		_map_layers = {}
	if pack == "":
		return {}
	if _map_layers.has(pack):
		return _map_layers[pack]
	var streets: Array = []
	var longest: Dictionary = {}   # name -> {len, pts}
	var rd = JSON.parse_string(FileAccess.get_file_as_string(Sites.path_in(pack, "roads.json")))
	if typeof(rd) == TYPE_DICTIONARY:
		for r in rd.get("roads", []):
			var name := str(r.get("name", ""))
			var pts: Array = r.get("points", [])
			if name == "" or name == "<null>" or pts.size() < 2:
				continue
			var length := 0.0
			for i in range(1, pts.size()):
				length += Vector2(pts[i - 1][0], pts[i - 1][1]).distance_to(Vector2(pts[i][0], pts[i][1]))
			if length > float(longest.get(name, {}).get("len", 0.0)):
				longest[name] = {"len": length, "pts": pts}
		for name in longest:
			var pts: Array = longest[name].pts
			var half: float = longest[name].len * 0.5
			for i in range(1, pts.size()):
				var a := Vector2(pts[i - 1][0], pts[i - 1][1])
				var b := Vector2(pts[i][0], pts[i][1])
				var seg := a.distance_to(b)
				if half <= seg or i == pts.size() - 1:
					var angle := (b - a).angle()
					if angle > PI * 0.5 or angle < -PI * 0.5:
						angle += PI   # never upside down
					streets.append({"name": name, "at": a.lerp(b, clampf(half / maxf(seg, 0.01), 0.0, 1.0)), "angle": angle})
					break
				half -= seg
	var numbers: Array = []
	var bd = JSON.parse_string(FileAccess.get_file_as_string(Sites.path_in(pack, "buildings.json")))
	var blds: Array = bd.get("buildings", []) if typeof(bd) == TYPE_DICTIONARY else (bd if typeof(bd) == TYPE_ARRAY else [])
	var re := RegEx.create_from_string("(\\d+[a-zA-Z]?(?:/\\d+)?)$")
	for b in blds:
		var addrs: Array = b.get("addresses", [])
		if addrs.is_empty():
			continue
		var m := re.search(str(addrs[0]).strip_edges())
		if m:
			numbers.append({"text": m.get_string(1), "at": Vector2(float(b.get("x", 0.0)), float(b.get("z", 0.0)))})
	# parcels with their dominant company (tenants.json, exact matches), for the company layer
	var by_tunnus := {}
	var tpath := Sites.path_in(pack, "tenants.json")
	if FileAccess.file_exists(tpath):
		var td = JSON.parse_string(FileAccess.get_file_as_string(tpath))
		if typeof(td) == TYPE_DICTIONARY:
			for t in td.get("tenants", []):
				if t.get("match") == "exact" and t.get("tunnus") != null:
					by_tunnus.get_or_add(str(t.tunnus), []).append(t)
	var parcels: Array = []
	for u in Parcels.units(pack):
		var poly: Array = u.get("polygon", [])
		if poly.size() < 3:
			continue
		var rows: Array = by_tunnus.get(str(u.get("tunnus", "")), [])
		var dom: Dictionary = MapPalette.dominant(rows)
		var owners := {}
		for t in rows:
			for h in t.get("owners", []):
				owners[str(h)] = true
		# what the layer fills, clipped to the tile: a unit that runs on past the edge (a street, the
		# river) was painted over the page around the map
		var ring := PackedVector2Array()
		for q in poly:
			ring.append(Vector2(float(q[0]), float(q[1])))
		var polys: Array = Geometry2D.intersect_polygons(ring,
				PackedVector2Array([Vector2.ZERO, Vector2(1024, 0), Vector2(1024, 1024), Vector2(0, 1024)]))
		parcels.append({"tunnus": str(u.get("tunnus", "")), "poly": poly, "polys": polys, "at": Vector2(float(u.get("x", 0.0)), float(u.get("z", 0.0))),
			"tenant": dom, "rows": rows, "owners": owners.keys()})
	_map_layers[pack] = {"streets": streets, "numbers": numbers, "parcels": parcels}
	return _map_layers[pack]


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
	if event is InputEventMouseMotion:
		_map_hover = event.position
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		# the plot under the cursor becomes the focused one; bare ground clears the focus
		var f := _map_frame(_debug_canvas)
		var at: Vector2 = (event.position - f[0]) / f[1] * 1024.0
		var pack := str(world.streamer.tiles.get(_debug_bg_tile, {}).get("pack", Sites.active)) if world.streamer else Sites.active
		var hit := ""
		for pr in _map_layer(pack).get("parcels", []):
			var poly := PackedVector2Array()
			for q in pr.poly:
				poly.append(Vector2(float(q[0]), float(q[1])))
			if poly.size() >= 3 and Geometry2D.is_point_in_polygon(at, poly):
				hit = str(pr.tunnus)
				break
		focus_parcel(hit if hit != "" and hit != str(_focus.get("tunnus", "")) else "")
		_debug_canvas.queue_redraw()
		return
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
## The forms that carry an argument after the colon. True when `which` was one of them. A cadastral
## number has colons of its own, so the argument is everything after the first one.
func _debug_open_with_argument(which: String) -> bool:
	if not which.contains(":"):
		return false   # "map" on its own is the plain map, not the map in mode ""
	var head := which.get_slice(":", 0)
	var arg := which.substr(head.length() + 1)
	match head:
		"map":   # the map in a company mode: --open=map:sector|size|health|age|owners
			set_map_mode(arg)
			_toggle(debug_map, _fill_debug_map)
		"hover":   # the map with the slip held over one plot: --open=hover:<tunnus>
			_map_hover_plot = arg
			_toggle(debug_map, _fill_debug_map)
		"focus":   # light a plot and its links, opening nothing: --open=focus:<tunnus>
			focus_parcel(arg)
		"find":   # the find bar with a query typed in: --open=find:<text>
			find_bar.open_at(Vector2(player.global_position.x, player.global_position.z))
			_open(find_bar)
			find_bar.debug_type(arg)
		"goto":   # the find bar, and the first result chosen: --open=goto:<text>
			find_bar.open_at(Vector2(player.global_position.x, player.global_position.z))
			_open(find_bar)
			find_bar.debug_type(arg)
			get_tree().create_timer(1.0).timeout.connect(func(): find_bar.debug_pick(false))
		"plots":   # the book's plot list, filtered: --open=plots:<text>
			book.tabs.current_tab = 0
			book.debug_filter(arg)
			_open(book)
		"plot":   # the book open on one plot: --open=plot:<tunnus>[#<year index>]
			var at := arg.split("#")   # #0 also opens the plot's oldest photograph large, for checks
			book.open_parcel(at[0])
			_open(book)
			if at.size() > 1:
				get_tree().create_timer(4.0).timeout.connect(func(): book.debug_enlarge(int(at[1])))
		"companies":   # the company list sorted by one column: --open=companies:<name|sector|employees|turnover|address>
			book.tabs.current_tab = 2
			book.debug_sort_companies(arg)
			_open(book)
		_:
			return false
	return true


func debug_open(which: String) -> void:
	if _debug_open_with_argument(which):
		return
	match which:
		"journal": _toggle(journal, _fill_journal)
		"map": _toggle(debug_map, _fill_debug_map)
		"book": _toggle(book, book.fill)
		"place":
			book.tabs.current_tab = 3
			_toggle(book, book.fill)
		"companies":
			book.tabs.current_tab = 2
			_toggle(book, book.fill)
		"menu": _toggle(pause, _fill_pause)


# --- journal (J): the codex, what this place is and where its facts come from
func _fill_journal() -> void:
	var body := _clear_body(journal)
	body.get_node("Title").text = tr("UI_JOURNAL")
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	var cbox := VBoxContainer.new()
	cbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cbox.add_theme_constant_override("separation", 8)
	scroll.add_child(cbox)
	for k in Sites.get_value("codex", []):
		BookTheme.label(tr(str(k) + "_TITLE"), "SubheadLabel", cbox)
		var l := BookTheme.label(tr(str(k)), "ProseLabel", cbox)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(700, 0)

