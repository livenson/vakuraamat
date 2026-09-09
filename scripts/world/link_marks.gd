# The focused plot drawn on the ground, and what the registers tie it to drawn in the air: its own
# boundary bright, the boundaries of the plots whose companies share an owner and of the buildings
# standing on it fainter, and a band arcing from the plot to each of them.
#
# Two meshes, never more: every boundary in one surface and every ribbon in another, because this
# game is short of draw calls, not of vertices. Nothing focused means no mesh at all, not a hidden
# one.
#
# A direct child of World, so EraController never snaps it and every height is baked into a vertex.
class_name LinkMarks
extends Node3D

const LINK_LIFT := 0.25      # the curtain's foot, clear of the grass
const CURTAIN := 2.2         # how high the focused plot's boundary glows
const SEGMENTS := 24         # samples along one arc
const BAND := 2.2            # how tall a ribbon stands, in metres
const TETHER_BAND := 0.9
const RANGE := 700.0

var world: Node3D
var _tunnus := ""
var _outlines: MeshInstance3D
var _ribbons: MeshInstance3D
var _ribbon_mat: ShaderMaterial


func setup(w: Node3D) -> void:
	world = w
	EventBus.parcel_focused.connect(_on_focused)
	EventBus.era_changed.connect(func(_id: String): _later())
	if world.streamer:
		# a tile arriving or leaving changes what can be pointed at; unloading frees the tile right
		# after the signal, so never rebuild inside the handler
		world.streamer.tile_ready.connect(func(_loc: Vector2i, _root: Node3D): _later())
		world.streamer.tile_unloaded.connect(func(_loc: Vector2i): _later())


func _on_focused(tunnus: String) -> void:
	_tunnus = tunnus
	_rebuild()


func _later() -> void:
	if _tunnus != "":
		call_deferred("_rebuild")


func _rebuild() -> void:
	for m in [_outlines, _ribbons]:
		if is_instance_valid(m):
			m.queue_free()
	_outlines = null
	_ribbons = null
	if _tunnus == "" or world == null or world.terrain == null:
		return
	var l := Links.of(_tunnus)
	if l.pack == "":
		return
	var here := Parcels.by_tunnus(_tunnus)
	if here.is_empty():
		return
	_draw_outlines(l, here)
	_draw_ribbons(l)


## The boundaries: this plot, the plots it is linked to, and the footprints of its buildings. Not a
## hairline - a low curtain of light standing on the boundary, opaque at the grass and fading out at
## the top, because a one-pixel line is gone from a hundred metres up and this mark has to be read
## from the survey view as well as from the pavement.
func _draw_outlines(l: Dictionary, here: Dictionary) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var drawn := _curtain(st, here.get("polygon", []), BookTheme.BLUE, CURTAIN)
	for s in l.parcels:
		var u := Parcels.by_tunnus(str(s.tunnus))
		if not u.is_empty():
			drawn = _curtain(st, u.get("polygon", []), BookTheme.BLUE.lightened(0.25), CURTAIN * 0.75) or drawn
	for b in l.buildings:
		drawn = _curtain(st, b.polygon, BookTheme.BLUE.lightened(0.4), CURTAIN * 0.45) or drawn
	if not drawn:
		return
	_outlines = MeshInstance3D.new()
	_outlines.name = "Outlines"
	_outlines.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED   # a boundary is read from both of its sides
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_outlines.material_override = m
	_outlines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_outlines.visibility_range_end = RANGE
	_outlines.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(_outlines)


## The links themselves: one band per linked plot and one, shorter and quieter, per building.
func _draw_ribbons(l: Dictionary) -> void:
	var from: Vector3 = l.at
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for s in l.parcels:
		any = _band(st, from, s.at, BAND, Color(BookTheme.BLUE, 0.95)) or any
	for b in l.buildings:
		any = _band(st, from, b.at, TETHER_BAND, Color(BookTheme.BLUE.lightened(0.15), 0.8)) or any
	if not any:
		return
	if _ribbon_mat == null:
		_ribbon_mat = ShaderMaterial.new()
		_ribbon_mat.shader = load("res://assets/shaders/link_ribbon.gdshader")
	_ribbons = MeshInstance3D.new()
	_ribbons.name = "Ribbons"
	_ribbons.mesh = st.commit()
	_ribbons.material_override = _ribbon_mat
	_ribbons.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ribbons.visibility_range_end = RANGE
	_ribbons.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(_ribbons)


## One arc, as a band standing on edge: read from any direction on the ground, where a flat ribbon
## would be invisible edge-on. It arcs over rather than sagging, and every sample is held clear of
## the terrain, so a link uphill does not run through the hill.
func _band(st: SurfaceTool, a: Vector3, b: Vector3, height: float, color: Color) -> bool:
	var span := Vector2(b.x - a.x, b.z - a.z).length()
	if span < 1.0:
		return false
	var ay := _ground(a)
	var by := _ground(b)
	if is_nan(ay) or is_nan(by):
		return false
	var lift := clampf(span * 0.25, 6.0, 40.0)
	var start := Vector3(a.x, ay + 1.0, a.z)
	var end := Vector3(b.x, by + 1.0, b.z)
	var apex := (start + end) * 0.5 + Vector3.UP * lift
	var pts: Array[Vector3] = []
	for i in SEGMENTS + 1:
		var t := float(i) / float(SEGMENTS)
		var p: Vector3 = start.lerp(apex, t).lerp(apex.lerp(end, t), t)   # quadratic Bézier
		var g := _ground(p)
		if is_nan(g):
			return false
		p.y = maxf(p.y, g + 1.0)
		pts.append(p)
	var run := 0.0
	for i in pts.size() - 1:
		var next_run := run + pts[i].distance_to(pts[i + 1])
		var u0 := float(i) / float(SEGMENTS)
		var u1 := float(i + 1) / float(SEGMENTS)
		_quad(st, pts[i], pts[i + 1], height, color, u0, u1, run / 20.0, next_run / 20.0)
		run = next_run
	return true


## A boundary as a curtain: one upright quad per edge of the ring, bright at the ground and gone by
## the top. Nothing is added when any corner falls off the terrain - one NaN would take the whole
## mesh's bounding box with it, and then none of the marks would draw at all.
func _curtain(st: SurfaceTool, poly: Array, color: Color, height: float) -> bool:
	if poly.size() < 3:
		return false
	var pts: Array[Vector3] = []
	for q in poly:
		var p := Vector3(float(q[0]), 0.0, float(q[1]))
		var h := _ground(p)
		if is_nan(h):
			return false
		p.y = h + LINK_LIFT
		pts.append(p)
	var top := Color(color, 0.0)
	var foot := Color(color, 0.85)
	var up := Vector3.UP * height
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		for corner in [[a, foot], [b, foot], [b + up, top], [a, foot], [b + up, top], [a + up, top]]:
			st.set_color(corner[1])
			st.add_vertex(corner[0])
	return true


## One segment of a band, carrying the colour, the fraction along the arc (UV) and the distance in
## twenty-metre lengths (UV2, which the dashes run on).
## The segment is two quads crossed along the arc, not one: a single upright band disappears when it is
## looked at from directly above, which is exactly where a player goes to see how a place hangs
## together, and a single flat one disappears at eye level.
func _quad(st: SurfaceTool, p0: Vector3, p1: Vector3, height: float, color: Color,
		u0: float, u1: float, d0: float, d1: float) -> void:
	var along := (p1 - p0).normalized()
	var side := along.cross(Vector3.UP).normalized() * height
	for axis in [Vector3.UP * height, side]:
		var corners := [p0, p1, p1 + axis, p0 + axis]
		var us := [Vector2(u0, 0.0), Vector2(u1, 0.0), Vector2(u1, 1.0), Vector2(u0, 1.0)]
		var ds := [Vector2(d0, 0.0), Vector2(d1, 0.0), Vector2(d1, 1.0), Vector2(d0, 1.0)]
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_color(color)
			st.set_uv(us[i])
			st.set_uv2(ds[i])
			st.add_vertex(corners[i])


func _ground(p: Vector3) -> float:
	if world.terrain == null or world.terrain.data == null:
		return NAN
	return world.terrain.data.get_height(Vector3(p.x, 0.0, p.z))
