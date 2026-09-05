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
			if _lines[t].get_meta("color", Color.WHITE) == color:
				continue
			_lines[t].queue_free()   # the colour changed (bought, bid, sold): rebuild, my plots carry posts
			_lines.erase(t)
		var mi := outline(wanted[t][0], world.terrain, color, LIFT)
		if mi:
			mi.set_meta("color", color)
			add_child(mi)
			_lines[t] = mi
			if color == GOLD:
				_posts(mi, wanted[t][0], world.terrain)


## My plots stand out from the street: a gold ribbon along the boundary and a post with a pennant at
## every corner, children of the outline so they come and go with it.
static func _posts(parent: Node3D, u: Dictionary, terrain: Node) -> void:
	var poly: Array = u.get("polygon", [])
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.14, 1.3, 0.14)
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.9, 0.88, 0.8)
	var flag_mesh := BoxMesh.new()
	flag_mesh.size = Vector3(0.5, 0.3, 0.03)
	var flag_mat := StandardMaterial3D.new()
	flag_mat.albedo_color = GOLD
	flag_mat.emission_enabled = true
	flag_mat.emission = GOLD
	flag_mat.emission_energy_multiplier = 0.4
	var ribbon := ImmediateMesh.new()
	ribbon.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n := poly.size()
	for i in n + 1:
		var c: Array = poly[i % n]
		var prev: Array = poly[(i - 1 + n) % n]
		var next: Array = poly[(i + 1) % n]
		var p := Vector2(float(c[0]), float(c[1]))
		var bis := ((Vector2(float(prev[0]), float(prev[1])) - p).normalized() + (Vector2(float(next[0]), float(next[1])) - p).normalized()).normalized()
		if bis.length() < 0.1:
			bis = (Vector2(float(next[0]), float(next[1])) - p).normalized().orthogonal()
		for side in [-0.18, 0.18]:
			var q: Vector2 = p + bis * float(side)
			var v := Vector3(q.x, 0, q.y)
			v.y = terrain.data.get_height(v) + LIFT - 0.05
			ribbon.surface_add_vertex(v)
		if i < n:
			var post := MeshInstance3D.new()
			post.mesh = post_mesh
			post.material_override = post_mat
			var at := Vector3(p.x, 0, p.y)
			at.y = terrain.data.get_height(at)
			post.position = at + Vector3(0, 0.65, 0)
			parent.add_child(post)
			var flag := MeshInstance3D.new()
			flag.mesh = flag_mesh
			flag.material_override = flag_mat
			flag.position = at + Vector3(0.25, 1.15, 0)
			parent.add_child(flag)
	ribbon.surface_end()
	var band := MeshInstance3D.new()
	band.mesh = ribbon
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(GOLD, 0.55)
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	band.material_override = bm
	parent.add_child(band)


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
