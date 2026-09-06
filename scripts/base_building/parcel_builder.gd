# Improvements on owned parcels: one box (from the StructureDefinition's size, offset and colour) per
# improvement row in the Ledger, at the parcel centroid, snapped to the ground. Rebuilt on parcel changes.
class_name ParcelBuilder
extends Node3D

var world: Node3D
var _defs: Dictionary = {}
var _built: Dictionary = {}    # improvement id -> Node3D
var _signed := false


func setup(w: Node3D) -> void:
	world = w
	Sites.load_dir(Sites.data_dir("structures"), _defs)
	Ledger.parcel_changed.connect(func(_t): refresh())
	if w.streamer:
		w.streamer.tile_ready.connect(func(_loc: Vector2i, root: Node3D): _sign_buildings(root))
	refresh()


func refresh() -> void:
	if world == null or world.terrain == null or world.terrain.data == null:
		return
	if not _signed:
		_signed = _sign_buildings()
	var seen := {}
	var blocks := _building_blocks()
	for p in Ledger.parcels():
		for imp in Ledger.improvements_of(p.tunnus):
			var id := int(imp.id)
			seen[id] = true
			var d: StructureDefinition = _defs.get(imp.structure_id)
			if d == null:
				continue
			var at := _free_spot(p, d, blocks, id)
			at.y = world.terrain.data.get_height(at)
			if _built.has(id):
				if _built[id].position.distance_to(at) > 0.5:
					_built[id].position = at
				continue
			var root := Node3D.new()
			root.name = "Improvement_%d" % id
			root.position = at
			_dress(root, d)
			var plate := Label3D.new()
			plate.text = tr(d.display_name_key)
			plate.font_size = 40
			plate.pixel_size = 0.008
			plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			plate.modulate = Color(0.98, 0.92, 0.75)
			plate.outline_modulate = Color(0.1, 0.08, 0.06)
			plate.outline_size = 8
			plate.no_depth_test = false
			plate.position = Vector3(0, d.size.y + 1.0, 0)
			root.add_child(plate)
			add_child(root)
			_built[id] = root
	for id in _built.keys():
		if not seen.has(id):
			_built[id].queue_free()
			_built.erase(id)


## What a structure looks like: a kiosk and a hall are a box with a roof slab; parking a slab with
## painted bays; a solar table rows of tilted dark panels on legs; a playground a sand pit with a frame.
func _dress(root: Node3D, d: StructureDefinition) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = d.color
	match str(d.id):
		"parking":
			var slab := CSGBox3D.new()
			slab.size = Vector3(d.size.x, 0.12, d.size.z)
			slab.position.y = 0.06
			slab.material = m
			root.add_child(slab)
			var paint := StandardMaterial3D.new()
			paint.albedo_color = Color(0.92, 0.92, 0.88)
			var bays := maxi(2, int(d.size.x / 2.5))
			for i in bays + 1:
				var line := CSGBox3D.new()
				line.size = Vector3(0.12, 0.02, d.size.z * 0.8)
				line.position = Vector3(-d.size.x / 2.0 + i * d.size.x / bays, 0.13, 0)
				line.material = paint
				root.add_child(line)
		"solar_table":
			var leg_mat := StandardMaterial3D.new()
			leg_mat.albedo_color = Color(0.5, 0.5, 0.52)
			var rows := maxi(1, int(d.size.z / 2.0))
			for r in rows:
				var panel := CSGBox3D.new()
				panel.size = Vector3(d.size.x, 0.06, 1.7)
				panel.position = Vector3(0, 1.2, -d.size.z / 2.0 + 1.0 + r * 2.0)
				panel.rotation.x = deg_to_rad(-30)
				panel.material = m
				root.add_child(panel)
				for sx in [-d.size.x / 2.0 + 0.5, d.size.x / 2.0 - 0.5]:
					var leg := CSGBox3D.new()
					leg.size = Vector3(0.1, 1.0, 0.1)
					leg.position = Vector3(sx, 0.5, panel.position.z)
					leg.material = leg_mat
					root.add_child(leg)
		"playground":
			var sand := CSGBox3D.new()
			sand.size = Vector3(d.size.x, 0.15, d.size.z)
			sand.position.y = 0.075
			var sm := StandardMaterial3D.new()
			sm.albedo_color = Color(0.85, 0.78, 0.6)
			sand.material = sm
			root.add_child(sand)
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var post := CSGBox3D.new()
					post.size = Vector3(0.12, d.size.y, 0.12)
					post.position = Vector3(sx * 1.2, d.size.y / 2.0, sz * 0.9)
					post.material = m
					root.add_child(post)
			var bar := CSGBox3D.new()
			bar.size = Vector3(2.6, 0.1, 0.1)
			bar.position = Vector3(0, d.size.y, 0.9)
			bar.material = m
			root.add_child(bar)
		_:
			var box := CSGBox3D.new()
			box.size = d.size
			box.position.y = d.size.y * 0.5
			box.material = m
			root.add_child(box)
			var roof := CSGBox3D.new()
			roof.size = Vector3(d.size.x + 0.6, 0.3, d.size.z + 0.6)
			roof.position.y = d.size.y + 0.15
			var rm := StandardMaterial3D.new()
			rm.albedo_color = d.color.darkened(0.45)
			roof.material = rm
			root.add_child(roof)


## The real buildings as ground rectangles: [global transform, half extent] per footprint group.
func _building_blocks() -> Array:
	var out: Array = []
	var layer: Node = world.get_node("EraLayers").get_node_or_null(GameState.current_era) if world.has_node("EraLayers") else null
	if layer == null:
		return out
	for g in layer.find_children("*", "Node3D", true, false):
		if g.has_meta("footprint"):
			var fp: Vector2 = g.get_meta("footprint")
			out.append([g.global_transform, Vector2(fp.x, fp.y) * 0.5 + Vector2(1.0, 1.0)])
	return out


## Where a structure stands on its plot: the free spot (outside every building, off other
## improvements, inside the cadastral polygon by half the structure's size) nearest the plot's
## centre; the plot's centre offset when the polygon is unknown.
func _free_spot(p: Dictionary, d: StructureDefinition, blocks: Array, id: int) -> Vector3:
	var fallback := Vector3(float(p.x) + d.offset.x, 0, float(p.z) + d.offset.y)
	var poly := PackedVector2Array()
	for u in Parcels.units(Sites.active):
		if u.tunnus == p.tunnus:
			for c in u.polygon:
				poly.append(Vector2(float(c[0]), float(c[1])))
			break
	if poly.size() < 3:
		return fallback
	var half := maxf(d.size.x, d.size.z) * 0.5 + 0.6
	var centre := Vector2(float(p.x), float(p.z))
	var rect := Rect2(poly[0], Vector2.ZERO)
	for v in poly:
		rect = rect.expand(v)
	var best := Vector2.INF
	var best_d := INF
	var x := rect.position.x + 1.0
	while x < rect.end.x:
		var z := rect.position.y + 1.0
		while z < rect.end.y:
			var at := Vector2(x, z)
			z += 1.5
			if not Geometry2D.is_point_in_polygon(at, poly):
				continue
			var ok := true
			for k in 4:   # the structure's corners stay inside the plot
				var corner := at + Vector2(half if k % 2 == 0 else -half, half if k < 2 else -half)
				if not Geometry2D.is_point_in_polygon(corner, poly):
					ok = false
			for b in blocks:
				var xf: Transform3D = b[0]
				var ext: Vector2 = b[1]
				var local: Vector3 = xf.affine_inverse() * Vector3(at.x, xf.origin.y, at.y)
				if absf(local.x) < ext.x + half and absf(local.z) < ext.y + half:
					ok = false
			for other in _built:
				if other != id and Vector2(_built[other].position.x, _built[other].position.z).distance_to(at) < half * 2.0 + 1.0:
					ok = false
			if ok and at.distance_to(centre) < best_d:
				best_d = at.distance_to(centre)
				best = at
		x += 1.5
	if best == Vector2.INF:
		return fallback
	return Vector3(best.x, 0, best.y)


## Tenant name plates on the real buildings of the origin layer, or of a streamed tile's root when given
## (the register links each building to its cadastral unit). Returns false until the layer is loaded.
func _sign_buildings(scope: Node = null) -> bool:
	var layer: Node = scope if scope else world.get_node("EraLayers").get_node_or_null(GameState.current_era)
	if layer == null or not is_instance_valid(layer):
		return false
	var n := 0
	for b in layer.find_children("*", "FootprintBuilding", true, false):
		if b.tunnus == "" or b.kind == "outbuilding":
			continue
		var names: Array = Tenants.active_names(Sites.pack_of(b), b.tunnus)
		if names.is_empty():
			continue
		b.set_sign("\n".join(names.slice(0, 2)) + ("\n+%d" % (names.size() - 2) if names.size() > 2 else ""))
		if not b.has_node("Props"):
			var props := Node3D.new()
			props.name = "Props"
			b.add_child(props)
			b.set_props(Tenants.of(Sites.pack_of(b), b.tunnus).filter(func(t): return str(t.get("status", "")) == "R"))
		n += 1
	return true
