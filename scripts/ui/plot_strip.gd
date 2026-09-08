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


## True when the plot can be shown at all: the tile has to be georeferenced and the plot has to be on
## a tile that is standing, so the caller can leave the heading out rather than print an empty section.
static func can_show(world: Node3D, tunnus: String) -> bool:
	return not _polygon_of(world, tunnus).is_empty()


static func _polygon_of(world: Node3D, tunnus: String) -> PackedVector2Array:
	var poly := PackedVector2Array()
	var georef: TerrainGeoref = world.georef if world and "georef" in world else null
	if georef == null or not georef.is_valid() or tunnus == "":
		return poly
	# any standing tile, not just the one the pack was opened on: a building three streets over sits
	# on a neighbour's plot, and its land has a history too. Parcels.by_tunnus hands back the boundary
	# already in world metres, which is the frame the georef converts from.
	var u := Parcels.by_tunnus(tunnus)
	for c in u.get("polygon", []):
		poly.append(Vector2(float(c[0]), float(c[1])))
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
	# the plot may belong to a streamed neighbour: its own tile carries the photograph of today
	var pack: String = str(Parcels.by_tunnus(tunnus).get("pack", "")) if tunnus != "" else ""
	if pack == "":
		pack = Sites.active
	var own := TerrainGeoref.load_dir(Sites.tile_dir_of(pack))
	var now := PlotHistory.current(square, own, Sites.tile_dir_of(pack))
	if now != null:
		all.append({"label": tr("UI_BOOK_TODAY"), "texture": now, "local": true})
	# one waiting slot per campaign, named, so the strip has its shape and its years straight away:
	# the older pictures come from a national service and take a second or two the first time
	for e in PlotHistory.EPOCHS:
		var wait := PlotThumb.new()
		row.add_child(wait)
		wait.setup_pending(str(e.label), tr("UI_BOOK_LOADING"))
	var shots: Array = await PlotHistory.fetch(pack, tunnus, square)
	if not is_instance_valid(row):
		return   # the page was rebuilt or closed while the pictures were fetched
	for c in row.get_children():
		c.queue_free()
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
