# One aerial photograph of a plot in the book, with the plot's own outline drawn on it and the year
# under it. The outline is what makes the strip about this plot rather than about a square of town:
# without it the eye has nothing to hold on to as the ground changes from picture to picture.
class_name PlotThumb
extends VBoxContainer

const SIZE := 150   # five campaigns and today have to sit across one page of the book


func setup(label: String, tex: Texture2D, outline: PackedVector2Array) -> void:
	var frame := TextureRect.new()
	frame.texture = tex
	frame.custom_minimum_size = Vector2(SIZE, SIZE)
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(frame)
	if outline.size() >= 3:
		var mark := _Outline.new()
		mark.poly = outline
		mark.set_anchors_preset(Control.PRESET_FULL_RECT)
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(mark)
	var year := BookTheme.label(label, "DetailLabel", self)
	year.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


## A placeholder of the same size, so the strip keeps its shape while the pictures arrive.
func setup_pending(label: String) -> void:
	var box := ColorRect.new()
	box.color = Color(0, 0, 0, 0.06)
	box.custom_minimum_size = Vector2(SIZE, SIZE)
	add_child(box)
	var l := BookTheme.label(label, "DetailLabel", self)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


## The plot's boundary over the photograph: a dark line under a bright one, so it reads on both a
## sunlit field and a dark roof.
class _Outline:
	extends Control

	var poly := PackedVector2Array()

	func _draw() -> void:
		var pts := PackedVector2Array()
		for p in poly:
			pts.append(Vector2(p.x * size.x, p.y * size.y))
		if pts.size() >= 3:
			pts.append(pts[0])
			draw_polyline(pts, Color(0.0, 0.0, 0.0, 0.55), 3.0, true)
			draw_polyline(pts, Color(1.0, 0.85, 0.35, 0.95), 1.5, true)
