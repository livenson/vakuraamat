# Improvements on owned parcels: one box (from the StructureDefinition's size, offset and colour) per
# improvement row in the Ledger, at the parcel centroid, snapped to the ground. Rebuilt on parcel changes.
class_name ParcelBuilder
extends Node3D

var world: Node3D
var _defs: Dictionary = {}
var _built: Dictionary = {}    # improvement id -> Node3D


func setup(w: Node3D) -> void:
	world = w
	Sites.load_dir(Sites.data_dir("structures"), _defs)
	Ledger.parcel_changed.connect(func(_t): refresh())
	refresh()


func refresh() -> void:
	if world == null or world.terrain == null or world.terrain.data == null:
		return
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
