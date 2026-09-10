# Many small meshes into one: every static MeshInstance3D under a root becomes a surface of one
# ArrayMesh, one surface per material, so a model draws in as many calls as it has materials instead
# of as many as it has parts (the city bus was 536 meshes, a procedural bicycle about 50).
# Parts that move (wheels, a crank) are named in `keep`: they stay separate nodes and are merged
# within themselves. Skinned meshes (figures) and anything that is not a MeshInstance3D are left
# alone. Works on a tree that is not in the scene: transforms are composed from the local ones.
class_name MeshMerge
extends RefCounted


# Merged copies of vendored models, one per path: built on first use, handed out as duplicates
# that share the merged meshes (and so batch with each other).
static var _templates: Dictionary = {}
const COPY := Node.DUPLICATE_SIGNALS | Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS   # not USE_INSTANTIATION: that re-reads the unmerged scene


## A merged instance of the scene at `path` (see flatten; `keep` as there).
static func instance(path: String, keep: Callable = func(_n): return false) -> Node3D:
	if not _templates.has(path):
		var t: Node3D = HumanFigure.scene(path).instantiate()
		flatten(t, keep)
		_templates[path] = t
	return copy(_templates[path])


## A copy of a merged template (a node not in the tree) sharing its meshes.
static func copy(template: Node3D) -> Node3D:
	template.scene_file_path = ""
	return template.duplicate(COPY)


## Merge `root`'s static meshes in place. `keep(node) -> bool` marks subtrees that must stay
## separate (each is merged within itself).
static func flatten(root: Node3D, keep: Callable = func(_n): return false) -> void:
	var parts: Array = []      # [MeshInstance3D, Transform3D relative to root]
	var kept: Array[Node3D] = []
	_collect(root, Transform3D.IDENTITY, root, keep, parts, kept)
	if parts.size() > 1:
		var shadows := false
		for p in parts:
			shadows = shadows or (p[0] as MeshInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mesh := _bake(parts)
		for p in parts:
			var mi: MeshInstance3D = p[0]
			if mi.get_child_count() == 0:
				mi.get_parent().remove_child(mi)
				mi.free()
			else:
				mi.mesh = null   # it carries other nodes: keep it as a plain transform
		var merged := MeshInstance3D.new()
		merged.name = "Merged"
		merged.mesh = mesh
		if not shadows:
			merged.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(merged)
	for k in kept:
		flatten(k, keep)


## Every static mesh of the scene at `path` baked into one ArrayMesh in the scene root's space
## (one surface per material), for MultiMesh instancing. Cached per path.
static var _baked: Dictionary = {}


static func baked(path: String) -> ArrayMesh:
	if not _baked.has(path):
		var t: Node3D = HumanFigure.scene(path).instantiate()
		var parts: Array = []
		var kept: Array[Node3D] = []
		_collect(t, Transform3D.IDENTITY, t, func(_n): return false, parts, kept)
		_baked[path] = _bake(parts)
		t.free()
	return _baked[path]


## Hide every GeometryInstance3D under `root` beyond `end` metres from the camera (no fade: the
## cheap mode). Existing shorter ranges are kept.
static func set_range(root: Node, end: float) -> void:
	if root is GeometryInstance3D:
		var g := root as GeometryInstance3D
		if g.visibility_range_end <= 0.0 or g.visibility_range_end > end:
			g.visibility_range_end = end
	for c in root.get_children():
		set_range(c, end)


static func _bake(parts: Array) -> ArrayMesh:
	var by_mat: Dictionary = {}   # material (or null) -> SurfaceTool
	var order: Array = []
	for p in parts:
		var mi: MeshInstance3D = p[0]
		for si in mi.mesh.get_surface_count():
			if mi.mesh is ArrayMesh and (mi.mesh as ArrayMesh).surface_get_primitive_type(si) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var mat: Material = mi.get_active_material(si)
			if not by_mat.has(mat):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				by_mat[mat] = st
				order.append(mat)
			(by_mat[mat] as SurfaceTool).append_from(mi.mesh, si, p[1])
	var mesh := ArrayMesh.new()
	for mat in order:
		(by_mat[mat] as SurfaceTool).commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	return mesh


static func _collect(n: Node, xf: Transform3D, root: Node3D, keep: Callable, parts: Array, kept: Array[Node3D]) -> void:
	for c in n.get_children():
		if c is Node3D and keep.call(c):
			kept.append(c)
			continue
		var cxf: Transform3D = xf * (c as Node3D).transform if c is Node3D else xf
		if c is MeshInstance3D and (c as MeshInstance3D).mesh and (c as MeshInstance3D).skin == null:
			parts.append([c, cxf])
		if not (c is Skeleton3D) and not (c is HumanFigure):
			_collect(c, cxf, root, keep, parts, kept)
