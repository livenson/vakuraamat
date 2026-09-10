# Far view of a layer's buildings: every CELL-square of the layer is one merged mesh (one surface
# per material: walls by facade, roofs, lit windows; the sills and casings are left out, nobody
# sees them from there) that stands in for its buildings beyond NEAR metres. Each building's own
# mesh names its cell as visibility parent, so Godot swaps the two by the cell's distance: near,
# the real buildings (outlines, doors, interiors, the register); far, a handful of draw calls per
# cell instead of four per building. A city tile's 1300 buildings were 5000 draw calls from the air.
# Cells rebuild a moment after their last building stands (the meshes arrive from worker threads),
# one cell per frame. One node per layer, "FarBuildings" under the EraController.
class_name BuildingChunks
extends Node3D

const CELL := 128.0
const NEAR := 350.0       # metres from a cell's centre inside which its real buildings draw
const SETTLE_S := 0.75    # wait this long after a cell's last change before merging it
# Occlusion: each cell also carries its buildings' walls as an occluder (Godot's CPU occlusion
# culling then skips what stands behind them: at street level most of the town).
const OCC_MIN_HEIGHT := 3.0
const OCC_BOTTOM := 0.5
const OCC_TOP := 0.7


## The occluder of `b`'s cell on or off: stepping inside a building must not hide the street
## seen through its windows.
static func set_occluding(b: FootprintBuilding, on: bool) -> void:
	var far := of(b)
	if far == null:
		return
	var lp := far.to_local(b.global_position)
	var cell := Vector2i(floori(lp.x / CELL), floori(lp.z / CELL))
	var oi = far._cells.get(cell, {}).get("occ")
	if oi and is_instance_valid(oi):
		oi.visible = on

var _cells: Dictionary = {}          # Vector2i -> {mi, members: {instance id -> building}, at: seconds}
var _dirty: Array[Vector2i] = []
var _tasks: Array[int] = []          # merges on the worker pool: each must be waited for, done or not


## The layer's far-view node for building `b`, made on first use; null outside a layer.
static func of(b: Node) -> BuildingChunks:
	var p := b.get_parent()
	while p and not (p is EraController):
		p = p.get_parent()
	if p == null:
		return null
	var c: Node = p.get_node_or_null("FarBuildings")
	if c == null:
		c = BuildingChunks.new()
		c.name = "FarBuildings"
		p.add_child(c)
	return c as BuildingChunks


## A building's mesh stands: take it into its cell.
func add(b: FootprintBuilding) -> void:
	var lp := to_local(b.global_position)
	var cell := Vector2i(floori(lp.x / CELL), floori(lp.z / CELL))
	if not _cells.has(cell):
		_cells[cell] = {"mi": null, "members": {}, "at": 0.0}
	_cells[cell].members[b.get_instance_id()] = b
	_cells[cell].at = Time.get_ticks_msec() / 1000.0 + SETTLE_S
	if not cell in _dirty:
		_dirty.append(cell)
	set_process(true)


func _ready() -> void:
	set_process(not _dirty.is_empty())


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for i in _dirty.size():
		var cell: Vector2i = _dirty[i]
		if float(_cells[cell].at) <= now:
			_dirty.remove_at(i)
			_rebuild(cell)
			return   # one cell a frame
	if _dirty.is_empty():
		set_process(false)


## Gather the cell's building surfaces (their CPU arrays, kept by each building) on the main
## thread, merge them on a worker, and put the mesh up back on the main thread.
func _rebuild(cell: Vector2i) -> void:
	var e: Dictionary = _cells[cell]
	if e.get("busy", false):
		e.at = Time.get_ticks_msec() / 1000.0 + SETTLE_S   # a merge is out: redo after it
		_dirty.append(cell)
		return
	var inv := global_transform.affine_inverse()
	var parts: Array = []   # [Transform3D, Material, arrays]
	var walls: Array = []   # [Transform3D, footprint, height]: the occluder's walls
	var members: Array = []
	for id: int in e.members.keys():
		var b = e.members[id]
		if not is_instance_valid(b):
			e.members.erase(id)
			continue
		var fb := b as FootprintBuilding
		var mi: MeshInstance3D = fb.far_mesh_node()
		if mi == null:
			continue
		var xf := inv * mi.global_transform
		for pair in fb.far_arrays():
			parts.append([xf, pair[0], pair[1]])
		if fb.height >= OCC_MIN_HEIGHT and fb.polygon.size() >= 3:
			walls.append([inv * fb.global_transform, fb.polygon, fb.height])
		members.append(weakref(fb))
	e.busy = true
	var me: WeakRef = weakref(self)
	_reap()
	_tasks.append(WorkerThreadPool.add_task(func():
		var merged: Array = BuildingChunks._merge(parts)
		var occ: Array = BuildingChunks._occluder(walls)
		var node = me.get_ref()
		if node:
			node.call_deferred("_put", cell, merged, members, occ), false, "far buildings"))


## Release the finished merges (a task the pool was never asked about keeps what it captured).
func _reap() -> void:
	for id in _tasks.duplicate():
		if WorkerThreadPool.is_task_completed(id):
			WorkerThreadPool.wait_for_task_completion(id)
			_tasks.erase(id)


func _exit_tree() -> void:
	for id in _tasks:
		WorkerThreadPool.wait_for_task_completion(id)
	_tasks.clear()


## Worker thread: one set of arrays per material, the parts moved into the cell's space.
static func _merge(parts: Array) -> Array:
	var groups: Dictionary = {}   # material -> [verts, normals, uvs]
	var order: Array = []
	for p in parts:
		var xf: Transform3D = p[0]
		var mat: Material = p[1]
		var arr: Array = p[2]
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		if v.is_empty():
			continue
		if not groups.has(mat):
			groups[mat] = [PackedVector3Array(), PackedVector3Array(), PackedVector2Array()]
			order.append(mat)
		var g: Array = groups[mat]
		var gv: PackedVector3Array = g[0]
		var gn: PackedVector3Array = g[1]
		var gu: PackedVector2Array = g[2]
		gv.append_array(xf * v)
		var n = arr[Mesh.ARRAY_NORMAL]
		gn.append_array(Transform3D(xf.basis, Vector3.ZERO) * (n as PackedVector3Array) if n != null else _filled3(v.size(), Vector3.UP))
		var uv = arr[Mesh.ARRAY_TEX_UV]
		if uv != null and (uv as PackedVector2Array).size() == v.size():
			gu.append_array(uv)
		else:
			var z := PackedVector2Array()
			z.resize(v.size())
			gu.append_array(z)
		g[0] = gv   # packed arrays taken out of an Array are copies: put them back
		g[1] = gn
		g[2] = gu
	var out: Array = []
	for mat in order:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = groups[mat][0]
		arrays[Mesh.ARRAY_NORMAL] = groups[mat][1]
		arrays[Mesh.ARRAY_TEX_UV] = groups[mat][2]
		out.append([mat, arrays])
	return out


## Worker thread: the cell's walls as occluder quads, from just above the ground to OCC_TOP of
## each building's height, so an occluder never pokes out of the walls it stands in for.
static func _occluder(walls: Array) -> Array:
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	for w in walls:
		var xf: Transform3D = w[0]
		var poly: PackedVector2Array = w[1]
		var top: float = float(w[2]) * OCC_TOP
		var n := poly.size()
		for i in n:
			var a := poly[i]
			var b := poly[(i + 1) % n]
			if a.distance_squared_to(b) < 1.0:
				continue   # a short wall hides nothing worth the rays
			var base := verts.size()
			verts.append(xf * Vector3(a.x, OCC_BOTTOM, a.y))
			verts.append(xf * Vector3(b.x, OCC_BOTTOM, b.y))
			verts.append(xf * Vector3(b.x, top, b.y))
			verts.append(xf * Vector3(a.x, top, a.y))
			idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	return [verts, idx]


static func _filled3(n: int, v: Vector3) -> PackedVector3Array:
	var a := PackedVector3Array()
	a.resize(n)
	a.fill(v)
	return a


## Main thread: the merged arrays become the cell's mesh, and its buildings hand over to it.
func _put(cell: Vector2i, merged: Array, members: Array, occ: Array = []) -> void:
	var t0 := Time.get_ticks_usec()
	var e: Dictionary = _cells[cell]
	e.busy = false
	var mesh := ArrayMesh.new()
	for pair in merged:
		if (pair[1][Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
			continue
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, pair[1])
		mesh.surface_set_material(mesh.get_surface_count() - 1, pair[0])
	var cmi: MeshInstance3D = e.mi
	if cmi == null:
		cmi = MeshInstance3D.new()
		cmi.name = "Cell_%d_%d" % [cell.x, cell.y]
		cmi.visibility_range_begin = NEAR
		add_child(cmi)
		e.mi = cmi
	cmi.mesh = mesh
	for w in members:
		var fb = w.get_ref()
		if fb and is_instance_valid(fb) and fb.far_mesh_node():
			var mi: MeshInstance3D = fb.far_mesh_node()
			mi.visibility_parent = mi.get_path_to(cmi)
	if occ.size() == 2 and not (occ[0] as PackedVector3Array).is_empty():
		var oi: OccluderInstance3D = e.get("occ")
		if oi == null:
			oi = OccluderInstance3D.new()
			oi.name = "Occ_%d_%d" % [cell.x, cell.y]
			add_child(oi)
			e.occ = oi
		var ao := ArrayOccluder3D.new()
		ao.set_arrays(occ[0], occ[1])
		oi.occluder = ao
	var ctrl := get_parent() as EraController
	if ctrl and ctrl.windows_collected:
		ctrl.register_windows(cmi)   # the new mesh's window surfaces take the lit glass
	var ms := (Time.get_ticks_usec() - t0) / 1000
	if ms > 8:
		PerfLog.mark("far buildings cell %s: %d buildings in %d ms" % [cell, members.size(), ms])
