# Finding somewhere without opening the book: a line at the top of the screen, results under it as
# you type, Enter to be pointed at it and Shift+Enter to jump there.
#
# Pointing is the default and jumping is the shifted one on purpose: this is a game about walking a
# square kilometre, and teleporting everywhere by reflex would be a shame.
class_name FindBar
extends PanelContainer

signal guide(tunnus: String, pos: Vector2, label: String)
signal go(tunnus: String, pos: Vector2, label: String)

const MAX_SHOWN := 8

var _edit: LineEdit
var _list: VBoxContainer
var _hint: Label
var _results: Array = []
var _at := 0
var _near := Vector2.ZERO


func setup() -> void:
	theme = BookTheme.theme()
	custom_minimum_size = Vector2(560, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	add_child(v)
	_edit = LineEdit.new()
	_edit.placeholder_text = tr("UI_FIND_PLACEHOLDER")
	_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit.text_changed.connect(_on_typed)
	# the arrows and Enter belong to the result list, not to the caret: a LineEdit accepts both in its
	# own gui_input (Enter becomes text_submitted), so _unhandled_key_input never saw them and nothing
	# could be chosen. Taking them here, before the LineEdit does, is what makes the bar answer.
	_edit.gui_input.connect(_on_edit_input)
	v.add_child(_edit)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	v.add_child(_list)
	_hint = BookTheme.label(tr("UI_FIND_HINT"), "DetailLabel", v)


## Open on a fresh query, with the player's position for ranking what is near.
func open_at(near: Vector2) -> void:
	_near = near
	_edit.text = ""
	_on_typed("")
	_edit.call_deferred("grab_focus")


## Checks: type a query without a keyboard (--open=find:<text>).
func debug_type(text: String) -> void:
	_edit.text = text
	_on_typed(text)


## Checks: choose the first result without a keyboard (--open=goto:<text>), the regression this
## bar needed - typing always worked, choosing did not.
func debug_pick(jump: bool) -> void:
	_pick(jump)


func _on_typed(text: String) -> void:
	_results = PlaceSearch.find(text, _near, MAX_SHOWN)
	_at = 0
	_redraw()


func _redraw() -> void:
	for c in _list.get_children():
		c.queue_free()
	if _results.is_empty():
		_hint.text = tr("UI_FIND_NOTHING") if _edit.text.strip_edges().length() >= 2 else tr("UI_FIND_HINT")
		return
	_hint.text = tr("UI_FIND_HINT")
	for i in _results.size():
		var r: Dictionary = _results[i]
		# each result is a row you can click as well as arrow onto: it reads like a list of places,
		# so the mouse expects it to answer
		var row := Button.new()
		row.theme_type_variation = "RowButton"
		row.custom_minimum_size = Vector2(0, 26)
		BookTheme.hand(row)
		var at := i
		row.pressed.connect(func():
			_at = at
			_pick(Input.is_key_pressed(KEY_SHIFT)))
		_list.add_child(row)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		line.offset_left = 8
		line.offset_right = -8
		row.add_child(line)
		var mark := BookTheme.label("›" if i == _at else " ", "DetailLabel", line)
		mark.custom_minimum_size = Vector2(14, 0)
		var name := BookTheme.label(str(r.label), "ProseLabel", line)
		name.custom_minimum_size = Vector2(230, 0)
		if i == _at:
			name.add_theme_color_override("font_color", BookTheme.BLUE)
		BookTheme.label(tr("UI_FIND_KIND_" + str(r.kind).to_upper()), "DetailLabel", line)
		var detail := BookTheme.label(str(r.detail), "DetailLabel", line)
		detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		detail.clip_text = true
		BookTheme.label("%d m" % int(_near.distance_to(r.pos)), "DetailLabel", line)


## The line's own keys, taken before the LineEdit reads them.
func _on_edit_input(event: InputEvent) -> void:
	if _step(event):
		_edit.accept_event()


## Arrows walk the results, Enter picks one; true when the event was ours. Shared by the line and by
## the panel, so the bar still answers when focus has wandered off the LineEdit.
func _step(event: InputEvent) -> bool:
	if not (event is InputEventKey and event.pressed) or not visible:
		return false
	match event.keycode:
		KEY_DOWN:
			_at = mini(_at + 1, maxi(0, _results.size() - 1))
			_redraw()
		KEY_UP:
			_at = maxi(_at - 1, 0)
			_redraw()
		KEY_ENTER, KEY_KP_ENTER:
			_pick(event.shift_pressed)
		_:
			return false
	return true


func _unhandled_key_input(event: InputEvent) -> void:
	if _step(event):
		get_viewport().set_input_as_handled()


func _pick(jump: bool) -> void:
	if _at >= _results.size():
		return
	var r: Dictionary = _results[_at]
	if jump:
		go.emit(str(r.tunnus), r.pos, str(r.label))
	else:
		guide.emit(str(r.tunnus), r.pos, str(r.label))
