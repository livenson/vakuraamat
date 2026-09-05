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
	for p in Ledger.parcels():
		for imp in Ledger.improvements_of(p.tunnus):
			var id := int(imp.id)
			seen[id] = true
			if _built.has(id):
				continue
			var d: StructureDefinition = _defs.get(imp.structure_id)
			if d == null:
				continue
			var at := Vector3(float(p.x) + d.offset.x, 0, float(p.z) + d.offset.y)
			at.y = world.terrain.data.get_height(at)
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
