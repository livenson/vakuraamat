# Parcel outlines on the ground: gold for my plots, amber where I have an open bid, blue for plots for
# sale near the player. Reads the origin tile's parcels.json polygons and the Ledger's ownership rows.
class_name ParcelMarks
extends Node3D

const GOLD := Color(0.93, 0.78, 0.35)
const AMBER := Color(0.95, 0.55, 0.2)
const BLUE := Color(0.35, 0.6, 0.95, 0.8)
const NEAR := 140.0
const LIFT := 0.35

var world: Node3D
var _lines: Dictionary = {}     # tunnus -> MeshInstance3D
var _flash: MeshInstance3D
var _t := 0.0


func setup(w: Node3D) -> void:
	world = w
	Ledger.parcel_changed.connect(func(_t): refresh())
	Ledger.bids_changed.connect(func(_t): refresh())
	refresh()


func _process(delta: float) -> void:
	_t += delta
	if _t > 1.0:
		_t = 0.0
		refresh()


func refresh() -> void:
	if world == null or world.terrain == null or world.terrain.data == null:
		return
	var player: Node3D = world.get_node_or_null("Player")
	var pos := player.global_position if player else Vector3.ZERO
	var wanted := {}
	var my_bid_plots := {}
	for b in Ledger.my_bids():
		my_bid_plots[b.tunnus] = true
	for u in Parcels.units(Sites.active):
		var row := Ledger.parcel(u.tunnus)
		if row.is_empty():
			continue
		if Ledger.is_mine(u.tunnus):
			wanted[u.tunnus] = [u, GOLD]
		elif my_bid_plots.has(u.tunnus):
			wanted[u.tunnus] = [u, AMBER]
		elif row.for_sale and Vector2(pos.x, pos.z).distance_to(Vector2(float(u.x), float(u.z))) < NEAR:
			wanted[u.tunnus] = [u, BLUE]
	for t in _lines.keys():
		if not wanted.has(t):
			_lines[t].queue_free()
			_lines.erase(t)
	for t in wanted:
		var color: Color = wanted[t][1]
		if _lines.has(t):
			if _lines[t].get_meta("color", Color.WHITE) != color:
				_lines[t].material_override.albedo_color = color
				_lines[t].set_meta("color", color)
			continue
		var mi := outline(wanted[t][0], world.terrain, color, LIFT)
		if mi:
			mi.set_meta("color", color)
			add_child(mi)
			_lines[t] = mi


## Briefly highlight one parcel (news "show", buy confirmation).
func flash(tunnus: String) -> void:
	if _flash:
		_flash.queue_free()
		_flash = null
	for u in Parcels.units(Sites.active):
		if u.tunnus == tunnus:
			_flash = outline(u, world.terrain, Color.WHITE, LIFT + 0.4)
			if _flash:
				add_child(_flash)
				get_tree().create_timer(4.0).timeout.connect(func():
					if _flash:
						_flash.queue_free()
						_flash = null)
			return


## A parcel boundary as an unshaded line strip just above the ground (shared with the K overlay).
static func outline(u: Dictionary, terrain: Node, color: Color, lift: float, offset: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var poly: Array = u.get("polygon", [])
	if poly.size() < 3 or terrain == null or terrain.data == null:
		return null
	var st := ImmediateMesh.new()
	st.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in poly.size() + 1:
		var c: Array = poly[i % poly.size()]
		var p := Vector3(float(c[0]), 0, float(c[1])) + offset
		p.y = terrain.data.get_height(p) + lift
		st.surface_add_vertex(p)
	st.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = st
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if color.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	mi.material_override = m
	return mi
