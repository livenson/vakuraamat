# Turns the tree glbs into game meshes: foliage as alpha-scissor (no sorting, writes depth, works in
# impostor bakes), bark double-sided off, saved as binary meshes. A `<name>_src.glb` beside the
# generated `<name>.glb` wins: a vendored model (Sketchfab, see THIRD_PARTY.md) whose mesh instances
# are merged with their node transforms into two surfaces, Bark and Foliage (any surface whose
# material carries an albedo texture with alpha, or is named like foliage, is foliage).
#   godot --headless --path . -s res://tools/godot/prepare_trees.gd [-- --only=spruce]
extends SceneTree

const TREES := ["birch", "pine", "spruce"]
const DIR := "res://assets/models/trees/"


func _init() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
	for name in TREES:
		if only != "" and name != only:
			continue
		var mesh: ArrayMesh
		if ResourceLoader.exists(DIR + name + "_src.glb"):
			mesh = _merge(load(DIR + name + "_src.glb").instantiate())
		else:
			mesh = _from_generated(load(DIR + name + ".glb").instantiate())
		var path: String = DIR + name + "_mesh.res"
		ResourceSaver.save(mesh, path, ResourceSaver.FLAG_CHANGE_PATH)
		print("[prepare_trees] %s: %d surfaces, aabb %s" % [name, mesh.get_surface_count(), mesh.get_aabb()])
	quit()


func _foliage_material(m: StandardMaterial3D) -> StandardMaterial3D:
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.45
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.backlight_enabled = true
	m.backlight = Color(0.35, 0.4, 0.2)
	m.roughness = 0.85
	return m


## The Blender Sapling export: one mesh instance, surfaces named Bark and Foliage.
func _from_generated(scene: Node) -> ArrayMesh:
	var src: MeshInstance3D = scene.find_children("*", "MeshInstance3D", true, false)[0]
	var mesh := ArrayMesh.new()
	for si in src.mesh.get_surface_count():
		mesh.add_surface_from_arrays(src.mesh.surface_get_primitive_type(si), src.mesh.surface_get_arrays(si))
		var sname: String = src.mesh.surface_get_name(si)
		mesh.surface_set_name(si, sname)
		var m: StandardMaterial3D = src.mesh.surface_get_material(si).duplicate()
		if sname == "Foliage":
			_foliage_material(m)
		else:
			m.cull_mode = BaseMaterial3D.CULL_BACK
		mesh.surface_set_material(si, m)
	scene.free()
	return mesh


## Keep only the foliage triangles within half a trunk-height of the trunk axis (Sketchfab packs
## sometimes leave a spare branch or a second small tree beside the model).
func _prune(arrays: Array, trunk: AABB) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var centre := Vector2(trunk.get_center().x, trunk.get_center().z)
	var reach := maxf(trunk.size.y, 1.0) * 0.5
	var keep := PackedInt32Array()
	var tris := idx.size() / 3 if idx.size() > 0 else verts.size() / 3
	for t in tris:
		var c := Vector3.ZERO
		for k in 3:
			c += verts[idx[t * 3 + k] if idx.size() > 0 else t * 3 + k]
		c /= 3.0
		if Vector2(c.x, c.z).distance_to(centre) <= reach:
			for k in 3:
				keep.append(idx[t * 3 + k] if idx.size() > 0 else t * 3 + k)
	print("[prepare_trees] pruned %d of %d foliage triangles beyond %.1f m of the trunk" % [tris - keep.size() / 3, tris, reach])
	arrays[Mesh.ARRAY_INDEX] = keep
	return arrays


## A vendored model: every mesh instance merged with its transforms, bark and foliage each one surface.
func _merge(scene: Node3D) -> ArrayMesh:
	var bark := SurfaceTool.new()
	var leaf := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	leaf.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bark_mat: StandardMaterial3D = null
	var leaf_mat: StandardMaterial3D = null
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var t: Transform3D = mi.transform
		var p: Node = mi.get_parent()
		while p and p != scene:
			t = p.transform * t
			p = p.get_parent()
		for si in mi.mesh.get_surface_count():
			var m: Material = mi.get_surface_override_material(si)
			if m == null:
				m = mi.mesh.surface_get_material(si)
			var sname: String = (mi.mesh.surface_get_name(si) + " " + (m.resource_name if m else "")).to_lower()
			var is_leaf: bool = ("foliage" in sname or "leaf" in sname or "leaves" in sname or "needle" in sname or "albedo" in sname or "spruce" in sname
				or (m is BaseMaterial3D and (m as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED))
			if is_leaf:
				leaf.append_from(mi.mesh, si, t)
				if leaf_mat == null and m is StandardMaterial3D:
					leaf_mat = _foliage_material(m.duplicate())
					leaf_mat.albedo_color = leaf_mat.albedo_color * Color(1.35, 1.4, 1.25)   # the pack's needles are painted for a darker scene
			else:
				bark.append_from(mi.mesh, si, t)
				if bark_mat == null and m is StandardMaterial3D:
					bark_mat = m.duplicate()
					bark_mat.cull_mode = BaseMaterial3D.CULL_BACK
	var mesh := ArrayMesh.new()
	var b := bark.commit()
	if b.get_surface_count() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b.surface_get_arrays(0))
		mesh.surface_set_name(mesh.get_surface_count() - 1, "Bark")
		if bark_mat:
			mesh.surface_set_material(mesh.get_surface_count() - 1, bark_mat)
	var l := leaf.commit()
	if l.get_surface_count() > 0:
		var arrays: Array = l.surface_get_arrays(0)
		if b.get_surface_count() > 0:
			arrays = _prune(arrays, b.get_aabb())   # stray pieces exported beside the tree are dropped
			var tmp := ArrayMesh.new()
			tmp.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var st := SurfaceTool.new()
			st.create_from(tmp, 0)
			st.deindex()   # expands by the kept indices: unreferenced vertices leave the bounds
			st.index()
			arrays = st.commit().surface_get_arrays(0)
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_name(mesh.get_surface_count() - 1, "Foliage")
		if leaf_mat:
			mesh.surface_set_material(mesh.get_surface_count() - 1, leaf_mat)
	scene.free()
	return mesh
