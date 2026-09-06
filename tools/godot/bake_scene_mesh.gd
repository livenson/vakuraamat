# Flattens a model scene (glb) into one ArrayMesh with every node transform applied, so Terrain3D's
# instancer (which reads mesh instances without their parents' transforms) shows it at its true
# size. Materials are kept per surface; foliage-like surfaces (alpha) get alpha scissor and no cull.
#   godot --headless --path . -s res://tools/godot/bake_scene_mesh.gd -- res://assets/vendor/sketchfab/juniper.glb res://assets/vegetation/tree_juniper_mesh.res
extends SceneTree


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("usage: -- <in.glb> <out_mesh.res>")
		quit(1)
		return
	var scene: Node3D = (load(args[0]) as PackedScene).instantiate()
	var out := ArrayMesh.new()
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var t: Transform3D = mi.transform
		var p: Node = mi.get_parent()
		while p and p != scene:
			t = p.transform * t
			p = p.get_parent()
		for si in mi.mesh.get_surface_count():
			var arrays: Array = mi.mesh.surface_get_arrays(si)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for i in verts.size():
				verts[i] = t * verts[i]
			arrays[Mesh.ARRAY_VERTEX] = verts
			if arrays[Mesh.ARRAY_NORMAL] != null:
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				for i in normals.size():
					normals[i] = (t.basis * normals[i]).normalized()
				arrays[Mesh.ARRAY_NORMAL] = normals
			out.add_surface_from_arrays(mi.mesh.surface_get_primitive_type(si), arrays)
			var m: Material = mi.get_surface_override_material(si)
			if m == null:
				m = mi.mesh.surface_get_material(si)
			if m is BaseMaterial3D:
				var c: BaseMaterial3D = m.duplicate()
				if c.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or c.albedo_texture:
					c.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
					c.alpha_scissor_threshold = 0.45
					c.cull_mode = BaseMaterial3D.CULL_DISABLED
				out.surface_set_material(out.get_surface_count() - 1, c)
	var b := out.get_aabb()
	print("[bake_scene_mesh] %s: %d surfaces, size %s, base y %.2f" % [args[0], out.get_surface_count(), b.size, b.position.y])
	var err := ResourceSaver.save(out, args[1], ResourceSaver.FLAG_COMPRESS)
	print("[bake_scene_mesh] -> %s (%s)" % [args[1], error_string(err)])
	scene.free()
	quit()
