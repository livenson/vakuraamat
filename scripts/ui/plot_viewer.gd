# One year of a plot, large. The strip in the book is 150 px a picture, which is enough to see that
# the land changed and not enough to see how; clicking a year opens it here at the size of the page,
# refetched from the WMS at that size rather than magnified, and the arrow keys or the years along
# the bottom step between campaigns without closing it.
class_name PlotViewer
extends Control

const BIG := 900          # what is asked of the WMS for the large view
const MARGIN := 40.0

var _shots: Array = []    # [{label, texture}] as the strip has them, oldest first
var _outline := PackedVector2Array()
var _square := Rect2()
var _pack := ""
var _tunnus := ""
var _at := 0
var _picture: TextureRect
var _caption: Label
var _years: HBoxContainer


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP     # the book behind it must not take the clicks


func open_at(shots: Array, index: int, outline: PackedVector2Array, square: Rect2, pack: String, tunnus: String) -> void:
	_shots = shots
	_outline = outline
	_square = square
	_pack = pack
	_tunnus = tunnus
	_at = clampi(index, 0, shots.size() - 1)
	var dim := ColorRect.new()
	dim.color = Color(0.09, 0.08, 0.06, 0.86)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	_picture = TextureRect.new()
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_SCALE
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# as large a square as fits the screen once the caption and the years have their room
	var screen := get_viewport_rect().size
	var side: float = maxf(240.0, minf(screen.x - MARGIN * 2.0, screen.y - MARGIN * 2.0 - 90.0))
	_picture.custom_minimum_size = Vector2(side, side)
	box.add_child(_picture)
	_picture.add_child(PlotThumb.make_outline(_outline))   # the same outline the strip draws
	_caption = BookTheme.label("", "HeadLabel", box)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_years = HBoxContainer.new()
	_years.alignment = BoxContainer.ALIGNMENT_CENTER
	_years.add_theme_constant_override("separation", 8)
	box.add_child(_years)
	_show(_at)


func _show(index: int) -> void:
	_at = index
	var shot: Dictionary = _shots[_at]
	_picture.texture = shot.texture
	_caption.text = str(shot.label)
	for c in _years.get_children():
		c.queue_free()
	for i in _shots.size():
		var b := Button.new()
		b.flat = true
		b.text = str(_shots[i].label)
		b.disabled = i == _at
		var to := i
		b.pressed.connect(func(): _show(to))
		_years.add_child(b)
	_load_big(shot)


## Ask the WMS for this year at the large size and swap it in when it lands. The thumbnail is shown
## meanwhile, so the view is never empty; "today" comes from the tile's own photograph, which is
## already as sharp as it gets.
func _load_big(shot: Dictionary) -> void:
	if bool(shot.get("big", false)):
		return
	if bool(shot.get("local", false)):
		# the tile's own photograph: re-crop it from the orthophoto at the large size rather than
		# letting the strip's thumbnail be scaled up, which is why today used to be the soft one
		var own: Texture2D = PlotHistory.current_large(_pack, _square, BIG)
		if own != null:
			shot["texture"] = own
			shot["big"] = true
			if is_instance_valid(_picture):
				_picture.texture = own
		return
	var label: String = str(shot.label)
	var tex: Texture2D = await PlotHistory.fetch_large(_pack, _tunnus, label, _square, BIG)
	if tex == null or not is_instance_valid(self) or _at >= _shots.size():
		return
	shot["texture"] = tex
	shot["big"] = true
	if str(_shots[_at].label) == label:
		_picture.texture = tex


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		queue_free()
		accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	if event.keycode == KEY_ESCAPE:
		queue_free()
	elif event.keycode == KEY_LEFT and _at > 0:
		_show(_at - 1)
	elif event.keycode == KEY_RIGHT and _at < _shots.size() - 1:
		_show(_at + 1)
	else:
		return
	get_viewport().set_input_as_handled()
