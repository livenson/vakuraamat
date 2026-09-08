# "This plot over the years": one picture of a plot per orthophoto campaign, oldest first, the tile's
# own photograph last, each with the plot's boundary on it and each opening large when clicked.
#
# The book's plot page shows it, and so does a building's register sheet (E on a wall) - a building
# stands on a plot, and what the land was doing before it was built is the same question in both
# places. Fills itself: the caller adds it and walks away.
class_name PlotStrip
extends VBoxContainer

var _world: Node3D
var _tunnus := ""


## True when the plot can be shown at all: the tile has to be georeferenced and the plot has to be
## one of this pack's, so the caller can leave the heading out rather than print an empty section.
static func can_show(world: Node3D, tunnus: String) -> bool:
	return not _polygon_of(world, tunnus).is_empty()


static func _polygon_of(world: Node3D, tunnus: String) -> PackedVector2Array:
	var poly := PackedVector2Array()
	var georef: TerrainGeoref = world.georef if world and "georef" in world else null
	if georef == null or not georef.is_valid() or tunnus == "":
		return poly
	for u in Parcels.units():
		if str(u.get("tunnus", "")) == tunnus:
			for c in u.polygon:
				poly.append(Vector2(float(c[0]), float(c[1])))
			break
	return poly


func setup(world: Node3D, tunnus: String, heading: bool = true) -> void:
	_world = world
	_tunnus = tunnus
	add_theme_constant_override("separation", 6)
	var poly := _polygon_of(world, tunnus)
	var georef: TerrainGeoref = world.georef
	var square := PlotHistory.square_for(poly, georef)
	if square.size.x <= 0.0:
		return
	if heading:
		var head := BookTheme.label(tr("UI_BOOK_OVER_THE_YEARS"), "DetailLabel", self)
		head.add_theme_color_override("font_color", BookTheme.BLUE)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	var outline := PlotHistory.outline_in(poly, square, georef)
	var all: Array = []          # what the viewer steps through, in the order they are shown
	var now := PlotHistory.current(square, georef, Sites.tile_dir())
	if now != null:
		all.append({"label": tr("UI_BOOK_TODAY"), "texture": now, "local": true})
	var pending := PlotThumb.new()
	row.add_child(pending)
	pending.setup_pending("…")
	var shots: Array = await PlotHistory.fetch(Sites.active, tunnus, square)
	if not is_instance_valid(row) or not is_instance_valid(pending):
		return   # the page was rebuilt or closed while the pictures were fetched
	pending.queue_free()
	all = shots + all            # oldest first, the tile's own photograph last
	for i in all.size():
		var t := PlotThumb.new()
		row.add_child(t)
		t.setup(str(all[i].label), all[i].texture, outline)
		var at := i
		t.picked.connect(func(): _enlarge(all, at, outline, square))


## Checks: open the nth picture large, as clicking it does (--open=plot:<tunnus>#<n>).
func enlarge(index: int) -> void:
	for row in find_children("*", "HBoxContainer", true, false):
		var thumbs: Array = row.get_children().filter(func(c): return c is PlotThumb)
		if index < thumbs.size():
			thumbs[index].picked.emit()
			return


## One year at the size of the page, laid over the whole screen rather than over the panel that
## opened it, so the picture is as large as it can be.
func _enlarge(shots: Array, index: int, outline: PackedVector2Array, square: Rect2) -> void:
	var layer: Node = get_parent()
	while layer and not (layer is CanvasLayer):
		layer = layer.get_parent()
	var v := PlotViewer.new()
	(layer if layer else self).add_child(v)
	v.open_at(shots, index, outline, square, Sites.active, _tunnus)
