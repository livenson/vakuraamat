# The front page's plate: the pack's square kilometre as a sepia print of its orthophoto inside an
# ink frame, with the cadastral units drawn over it in the cadastre's blue and the reader's own plots
# filled. The outlines draw in once when the page opens; nothing else on the page moves.
class_name MapPlate
extends Control

var pack := ""
var owned: Dictionary = {}
var _ortho: Texture2D
var _units: Array = []
var _size_m := 1024.0
var _progress := 0.0


func setup(p_pack: String, p_owned: Array = []) -> void:
	pack = p_pack
	owned.clear()
	for t in p_owned:
		owned[str(t)] = true
	var tile_dir := Sites.tile_dir_of(pack)
	var path := tile_dir + "/ortho.jpg"
	_ortho = null
	if path.begins_with("res://") and ResourceLoader.exists(path):
		_ortho = load(path)
	elif FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img:
			_ortho = ImageTexture.create_from_image(img)
	_units = Parcels.units(pack)
	var t: Dictionary = Sites.manifest_for(pack).get("terrain", {})
	_size_m = float(t.get("size", 1024))
	_progress = 0.0
	var tw := create_tween()
	tw.tween_method(func(v: float):
		_progress = v
		queue_redraw(), 0.0, 1.0, 0.8).set_trans(Tween.TRANS_SINE)
	queue_redraw()


func _draw() -> void:
	var side := minf(size.x, size.y)
	var origin := (size - Vector2(side, side)) * 0.5
	var frame := Rect2(origin, Vector2(side, side))
	var plate := frame.grow(-10)
	if _ortho:
		draw_texture_rect(_ortho, plate, false, Color(0.9, 0.86, 0.78))
		draw_rect(plate, Color(BookTheme.PAGE, 0.42))
	else:
		draw_rect(plate, BookTheme.PAGE_DARK)
	var scale := plate.size.x / _size_m
	var tile := PackedVector2Array([Vector2(0, 0), Vector2(_size_m, 0), Vector2(_size_m, _size_m), Vector2(0, _size_m)])
	var shown := int(ceil(_progress * _units.size()))
	for i in shown:
		var u: Dictionary = _units[i]
		var poly: Array = u.get("polygon", [])
		if poly.size() < 3:
			continue
		var raw := PackedVector2Array()
		for p in poly:
			raw.append(Vector2(float(p[0]), float(p[1])))
		for piece in Geometry2D.intersect_polygons(raw, tile):   # units crossing the tile edge stay inside the plate
			if piece.size() < 3:
				continue
			var pts := PackedVector2Array()
			for p in piece:
				pts.append(plate.position + p * scale)
			if owned.has(str(u.get("tunnus", ""))):
				draw_colored_polygon(pts, Color(BookTheme.BLUE, 0.35))
			pts.append(pts[0])
			draw_polyline(pts, Color(BookTheme.BLUE, 0.85), 1.0, true)
	draw_rect(frame, BookTheme.INK, false, 1.0)
	draw_rect(plate, Color(BookTheme.INK, 0.6), false, 1.0)
	var font := BookTheme.font("plex")
	var t: Dictionary = Sites.manifest_for(pack).get("terrain", {})
	var c: Array = t.get("center", [0, 0])
	var caption := "%s   L-EST97 %d %d   %d m" % [Sites.display_name(pack), int(c[0]), int(c[1]), int(_size_m)]
	draw_string(font, frame.position + Vector2(2, frame.size.y + 18), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, BookTheme.FADED)
