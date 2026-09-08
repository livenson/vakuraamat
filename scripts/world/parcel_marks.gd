# Parcel boundaries drawn on the ground. Nothing is marked by default - the K overlay draws the unit
# you stand on - but the book, the find bar and the news feed ask for one to be lit up when they
# send you to it. Reads the origin tile's parcels.json polygons.
class_name ParcelMarks
extends Node3D

const LIFT := 0.35

var world: Node3D
var _flash: MeshInstance3D


func setup(w: Node3D) -> void:
	world = w


## Briefly light up one parcel: where the book, the find bar or a news item has just sent you.
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
