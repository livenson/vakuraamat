extends SceneTree
func _init() -> void:
	var b := FootprintBuilding.new()
	b.polygon = PackedVector2Array([Vector2(-2, -2), Vector2(2, -2), Vector2(2, 2), Vector2(-2, 2)])
	b.height = 4.0
	get_root().add_child(b)
	await process_frame
	var mi: MeshInstance3D = b.get_child(0)
	var arr := mi.mesh.surface_get_arrays(0)
	print("verts ", arr[Mesh.ARRAY_VERTEX].size(), " colors ", arr[Mesh.ARRAY_COLOR], " normals0 ", arr[Mesh.ARRAY_NORMAL][0] if arr[Mesh.ARRAY_NORMAL] else null)
	print("format has color: ", mi.mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_COLOR)
	quit()
