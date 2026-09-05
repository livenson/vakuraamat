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
			var box := CSGBox3D.new()
			box.size = d.size
			box.position.y = d.size.y * 0.5
			var m := StandardMaterial3D.new()
			m.albedo_color = d.color
			box.material = m
			root.add_child(box)
			var roof := CSGBox3D.new()
			roof.size = Vector3(d.size.x + 0.6, 0.3, d.size.z + 0.6)
			roof.position.y = d.size.y + 0.15
			var rm := StandardMaterial3D.new()
			rm.albedo_color = d.color.darkened(0.45)
			roof.material = rm
			root.add_child(roof)
			add_child(root)
			_built[id] = root
	for id in _built.keys():
		if not seen.has(id):
			_built[id].queue_free()
			_built.erase(id)


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
		n += 1
	return true
