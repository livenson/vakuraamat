# The locator: Estonia and Latvia at a glance on the Locations page, so a suggested place is a spot on
# the map and not only a name with a coordinate under it. Estonia's coastline is the county division
# unioned and simplified (assets/data/estonia.json), Latvia's its municipalities (assets/data/latvia.json,
# both from tools/pipeline/fetch_outline.py, on the same L-EST97 grid), drawn as an engraved plate
# in the book's ink: land on lighter paper, Peipsi and the gulf as the page itself, Võrtsjärv in the
# cadastre's blue. Every place the page offers is a mark on it; the world you are in is filled.
# Hovering a mark names it, and hovering a row on the page lights that row's mark (`highlight`).
class_name EstoniaMap
extends Control

const OUTLINES := ["res://assets/data/estonia.json", "res://assets/data/latvia.json"]
const PICK_RADIUS := 12.0   # how near the pointer has to come to a mark, in pixels

signal hovered(index: int)   # -1 when the pointer leaves every mark

## [{name, x, y, kind}] in L-EST97; kind is "suggested", "installed" or "current".
var places: Array = []

static var _map: Dictionary = {}
var _bounds := Rect2()
var _plate := Rect2()
var _hover := -1
var _lit := -1              # lit from the page: the row the pointer is on


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(380, 340)   # the two countries together are about as tall as wide
	_load()
	mouse_exited.connect(func():
		if _hover != -1:
			_hover = -1
			hovered.emit(-1)
			queue_redraw())


## The outline files, read once per session and merged: every country's land and lakes on one
## plate, the bounds around them all.
static func _load() -> Dictionary:
	if _map.is_empty():
		var land := []
		var lakes := []
		var b := [INF, INF, -INF, -INF]
		for path in OUTLINES:
			var text := FileAccess.get_file_as_string(path)
			var d = JSON.parse_string(text) if text != "" else null
			if typeof(d) != TYPE_DICTIONARY or d.get("bounds", []).size() != 4:
				continue
			land.append_array(d.get("land", []))
			lakes.append_array(d.get("lakes", []))
			for i in 2:
				b[i] = minf(b[i], float(d.bounds[i]))
				b[i + 2] = maxf(b[i + 2], float(d.bounds[i + 2]))
		if land.is_empty():
			b = [369034, 6377141, 739153, 6634019]
		_map = {"bounds": b, "land": land, "lakes": lakes}
	return _map


## Light the mark of the place at `index` (-1 for none): what a row hover on the page asks for.
func highlight(index: int) -> void:
	if index == _lit:
		return
	_lit = index
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var near := _nearest(event.position)
		if near != _hover:
			_hover = near
			hovered.emit(near)
			queue_redraw()


func _nearest(at: Vector2) -> int:
	var best := -1
	var best_d := PICK_RADIUS
	for i in places.size():
		var d := at.distance_to(_to_px(places[i]))
		if d < best_d:
			best_d = d
			best = i
	return best


## L-EST97 -> a point on the plate; the map keeps its aspect inside whatever room the page gives it.
func _to_px(p: Dictionary) -> Vector2:
	return _plate.position + Vector2(
		(float(p.x) - _bounds.position.x) / _bounds.size.x * _plate.size.x,
		(1.0 - (float(p.y) - _bounds.position.y) / _bounds.size.y) * _plate.size.y)


func _poly(ring: Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for p in ring:
		pts.append(_to_px({"x": p[0], "y": p[1]}))
	return pts


func _draw() -> void:
	var m := _load()
	var b: Array = m.get("bounds", [])
	if b.size() != 4:
		return
	_bounds = Rect2(float(b[0]), float(b[1]), float(b[2]) - float(b[0]), float(b[3]) - float(b[1]))
	# the plate: the map's own aspect, centred in the space the page gave, with room for the frame
	var frame := Rect2(Vector2.ZERO, size).grow(-1)
	var aspect := _bounds.size.x / _bounds.size.y
	var side := Vector2(minf(frame.size.x, frame.size.y * aspect), minf(frame.size.y, frame.size.x / aspect))
	_plate = Rect2(frame.position + (frame.size - side) * 0.5, side).grow(-8)
	draw_rect(frame, BookTheme.PAGE_DARK)
	draw_rect(frame, Color(BookTheme.INK, 0.6), false, 1.0)
	for ring in m.get("land", []):
		var pts := _poly(ring)
		if pts.size() < 3:
			continue
		draw_colored_polygon(pts, BookTheme.PAGE_LIGHT)
		pts.append(pts[0])
		draw_polyline(pts, Color(BookTheme.INK, 0.85), 1.0, true)
	for ring in m.get("lakes", []):
		var pts := _poly(ring)
		if pts.size() >= 3:
			draw_colored_polygon(pts, Color(BookTheme.BLUE, 0.5))
	var font := BookTheme.font("plex")
	var named := _hover if _hover != -1 else _lit
	for i in places.size():
		var p: Dictionary = places[i]
		var at := _to_px(p)
		var kind := str(p.get("kind", "suggested"))
		var color: Color = BookTheme.INK if kind == "installed" else BookTheme.BLUE
		var lit := i == named
		if kind == "current" or lit:
			draw_circle(at, 4.5 if lit else 3.5, color)
			draw_arc(at, 7.0, 0.0, TAU, 24, Color(color, 0.6), 1.0, true)
		elif kind == "installed":
			draw_circle(at, 3.0, color)
		else:
			draw_circle(at, 3.0, Color(BookTheme.PAGE_LIGHT, 0.9))
			draw_arc(at, 3.0, 0.0, TAU, 20, color, 1.4, true)
	if named >= 0 and named < places.size():
		_draw_name(font, str(places[named].get("name", "")), _to_px(places[named]))


## The name of the lit place, on the paper beside its mark and never off the plate's edge.
func _draw_name(font: Font, name: String, at: Vector2) -> void:
	var w := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var pos := at + Vector2(10, 4)
	if pos.x + w > _plate.end.x:
		pos.x = at.x - 10 - w
	pos.y = clampf(pos.y, _plate.position.y + 12, _plate.end.y - 4)
	draw_rect(Rect2(pos + Vector2(-3, -11), Vector2(w + 6, 15)), Color(BookTheme.PAGE, 0.85))
	draw_string(font, pos, name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, BookTheme.INK)
