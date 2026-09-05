# Stands a converted vegetation mesh upright: finds its longest axis, points the denser (crown) end
# up (+Y), rotates vertices, normals and tangents accordingly and puts the base at y = 0. Saves in place.
#   godot --headless --path . -s res://tools/godot/fix_mesh_up.gd -- res://assets/vegetation/tree_juniper_mesh.res ...
extends SceneTree

func _init() -> void:
	for p in OS.get_cmdline_user_args():
		if p.begins_with("res://"):
			_fix(p)
	quit()


func _fix(path: String) -> void:
	var mesh: ArrayMesh = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	var aabb := mesh.get_aabb()
	var ext := aabb.size
	var axis := 0
	if ext.y >= ext.x and ext.y >= ext.z:
		axis = 1
	elif ext.z >= ext.x and ext.z >= ext.y:
		axis = 2
	if axis == 1:
		print("[fix_mesh_up] %s already tallest along Y (%s)" % [path.get_file(), ext])
		return
	# which end is the crown: more vertices on that side of the AABB centre along the long axis
	var mid := aabb.get_center()[axis]
	var hi := 0
	var lo := 0
	for s in mesh.get_surface_count():
		for v in mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			if v[axis] > mid:
				hi += 1
			else:
				lo += 1
	var sign := 1.0 if hi >= lo else -1.0
	var from := Vector3.ZERO
	from[axis] = sign
	var rot := Quaternion(from, Vector3.UP)
	var basis := Basis(rot)
	var out := ArrayMesh.new()
	var min_y := INF
	var surfaces := []
	for s in mesh.get_surface_count():
		var arr: Array = mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for i in verts.size():
			verts[i] = basis * verts[i]
			min_y = minf(min_y, verts[i].y)
		arr[Mesh.ARRAY_VERTEX] = verts
		if arr[Mesh.ARRAY_NORMAL] != null:
			var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			for i in nrm.size():
				nrm[i] = basis * nrm[i]
			arr[Mesh.ARRAY_NORMAL] = nrm
		if arr[Mesh.ARRAY_TANGENT] != null:
			var tan: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT]
			for i in range(0, tan.size(), 4):
				var t := basis * Vector3(tan[i], tan[i + 1], tan[i + 2])
				tan[i] = t.x
				tan[i + 1] = t.y
				tan[i + 2] = t.z
			arr[Mesh.ARRAY_TANGENT] = tan
		surfaces.append([arr, mesh.surface_get_primitive_type(s), mesh.surface_get_material(s), mesh.surface_get_name(s)])
	for sd in surfaces:
		var arr: Array = sd[0]
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for i in verts.size():
			verts[i].y -= min_y
		arr[Mesh.ARRAY_VERTEX] = verts
		out.add_surface_from_arrays(sd[1], arr)
		var idx := out.get_surface_count() - 1
		out.surface_set_material(idx, sd[2])
		out.surface_set_name(idx, sd[3])
	out.take_over_path(path)
	var err := ResourceSaver.save(out, path)
	print("[fix_mesh_up] %s: axis %d sign %.0f -> up, base lifted %.2f, %d surfaces, saved %d, new aabb %s" % [path.get_file(), axis, sign, -min_y, out.get_surface_count(), err, out.get_aabb().size])
