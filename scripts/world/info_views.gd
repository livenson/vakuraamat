# The debug map's layers, laid on the ground you are standing on. Choosing "sector" or "health" on
# the map and closing it leaves the town colour-coded around you: every cadastral unit takes the
# colour its dominant company gives it, exactly as the map paints it, because both ask the same
# MapPalette.
#
# It is one image, not geometry. The unit polygons are drawn once into a SubViewport, the result is
# handed to the terrain's drape shader as a second world-aligned layer, and the shader mixes it over
# the orthophoto. That means no draw calls, no triangles to fit to the hills, and a view that follows
# the ground exactly - the same trick the orthophoto already uses, with its own origin so it can
# cover a streamed neighbour while the photograph still belongs to the site's own tile.
#
# "size" and "owners" are not fills: on the map they are circles and lines between plots. They leave
# the ground alone here, which is why the mode list this answers to is shorter than the map's.
class_name InfoViews
extends Node3D

const FILLS := ["sector", "mix", "focus", "health", "age"]   # the map's modes that are a colour per unit
const RES := 1024                            # one pixel a metre on a 1 km tile
const FADE := 0.35
const STRENGTH := 0.55       # how far the layer covers the ground: enough to read, not enough to hide it

var world: Node3D
var mode := "off"

var _baked: Dictionary = {}      # "<pack>|<mode>" -> ImageTexture
var _tile := Vector2i(9999, 9999)
var _mix := 0.0                  # what the shader is showing, so the fade always starts where it is
var _busy := false               # a bake is a frame long; the tile check must not stack them
var _tween: Tween


func setup(w: Node3D) -> void:
	world = w
	if world.streamer:
		# walking into a neighbour changes which tile the layer has to cover
		world.streamer.tile_ready.connect(func(_loc: Vector2i, _root: Node3D): _refresh())
	EventBus.era_changed.connect(func(_id: String): _refresh())


## Show one of the map's layers on the ground, or "off" for none. Anything the ground cannot say -
## the sizes, the owner lines - simply turns it off.
func set_mode(which: String) -> void:
	mode = which if which in FILLS else "off"
	_refresh()


func _process(_delta: float) -> void:
	if mode == "off" or world.streamer == null:
		return
	var here: Vector2i = world.streamer.tile_of(world.player.global_position)
	if here != _tile:
		_refresh()


## Paint the tile the player is standing on, and fade the layer in or out.
func _refresh() -> void:
	if _baked == null:
		_baked = {}   # a hot reload leaves a new member null until the instance is rebuilt
	if _busy:
		return
	var mat = world.terrain.material if world.terrain else null   # Terrain3DMaterial
	if mat == null:
		return
	if mode == "off":
		_fade(0.0)
		return
	var loc: Vector2i = world.streamer.tile_of(world.player.global_position) if world.streamer else Vector2i.ZERO
	var pack := Sites.active
	if world.streamer:
		pack = str(world.streamer.tiles.get(loc, {}).get("pack", ""))
	if pack == "":
		_fade(0.0)   # standing over a tile that is still coming in
		return
	_tile = loc
	_busy = true
	var tex := await _texture(pack)
	_busy = false
	if tex == null or mode == "off":
		return
	var size: float = world.georef.tile_size_m() if world.georef else 1024.0
	mat.set_shader_param("info_texture", tex)
	mat.set_shader_param("info_origin", Vector2(loc.x, loc.y) * size)
	mat.set_shader_param("info_extent", size)
	_fade(STRENGTH)


## The layer as a picture of one tile: every unit of that pack filled with its colour, drawn once and
## kept. Polygons go through a SubViewport rather than pixel by pixel - the graphics card fills a few
## hundred of them in a frame, where GDScript would take a second per layer.
func _texture(pack: String) -> Texture2D:
	var key := "%s|%s" % [pack, mode + (":" + MapPalette.focus_sector if mode == "focus" else "")]
	if _baked.has(key):
		return _baked[key]
	var units := Parcels.units(pack)
	if units.is_empty():
		return null
	var rows := _rows_by_tunnus(pack)
	var vp := SubViewport.new()
	vp.size = Vector2i(RES, RES)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	add_child(vp)
	var size: float = world.georef.tile_size_m() if world.georef else 1024.0
	var k := float(RES) / size
	for u in units:
		var ring: Array = u.get("polygon", [])
		if ring.size() < 3:
			continue
		var poly := PackedVector2Array()
		for q in ring:
			poly.append(Vector2(float(q[0]), float(q[1])) * k)
		# opaque in the picture, because a viewport's transparent pixels come back premultiplied and
		# a half-alpha fill would arrive darkened as well as faint. How far the colour covers the
		# ground is STRENGTH, applied once in the shader.
		for piece in _fills(rows.get(str(u.get("tunnus", "")), []), poly, k):
			var c: Color = piece[1]
			var p := Polygon2D.new()
			p.polygon = piece[0]
			p.color = Color(c.r, c.g, c.b, 1.0)
			vp.add_child(p)
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.is_empty():
		return null
	var tex := ImageTexture.create_from_image(img)
	_baked[key] = tex
	return tex


## What one unit is painted with in the current mode, the same as the map paints it: [[polygon,
## colour], ...]. The mixed layer stripes it by its sectors' shares, the one-sector layer shades it by
## that sector's share, the others colour it by the company MapPalette.pick chooses. Nothing when the
## layer has nothing to say about the unit, so the real ground stands.
func _fills(rows: Array, poly: PackedVector2Array, k: float) -> Array:
	match mode:
		"mix":
			return MapPalette.stripes(poly, MapPalette.shares(rows), MapPalette.STRIPE_M * k)
		"focus":
			var share: float = MapPalette.shares(rows).get(MapPalette.focus_sector, 0.0)
			return [[poly, MapPalette.focus_colour(share)]] if share > 0.0 else []
	var dom := MapPalette.pick(mode, rows)
	return [] if dom.is_empty() else [[poly, MapPalette.colour(mode, dom)]]


## Every unit's companies (tenants.json, exact matches), by cadastral number.
func _rows_by_tunnus(pack: String) -> Dictionary:
	var rows := {}
	var path := Sites.path_in(pack, "tenants.json")
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			for t in parsed.get("tenants", []):
				if t.get("match") == "exact" and t.get("tunnus") != null:
					rows.get_or_add(str(t.tunnus), []).append(t)
	return rows


func _fade(to: float) -> void:
	var mat = world.terrain.material if world.terrain else null   # Terrain3DMaterial
	if mat == null:
		return
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(func(v: float):
		_mix = v
		mat.set_shader_param("info_mix", v), _mix, to, FADE)
