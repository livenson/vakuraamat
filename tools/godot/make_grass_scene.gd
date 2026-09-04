# Builds assets/vegetation/grass_card.tscn: three crossed quads (0/60/120 degrees), 0.9 m wide,
# 0.7 m tall, with the wind shader. Used by scatter_vegetation.gd instead of the pack's tuft.
#   godot --headless --path . -s res://tools/godot/make_grass_scene.gd
extends SceneTree


func _init() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := 0.45
	var h := 0.5
	for k in 3:
		var a := deg_to_rad(60.0 * k)
		var dx := cos(a) * w
		var dz := sin(a) * w
		var p := [Vector3(-dx, 0, -dz), Vector3(dx, 0, dz), Vector3(dx, h, dz), Vector3(-dx, h, -dz)]
		var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP)
			st.set_uv(uv[i])
			st.add_vertex(p[i])
	var mesh := st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/grass_wind.gdshader")
	mat.set_shader_parameter("card", load("res://assets/textures/foliage/grass_blades.png"))
	mesh.surface_set_material(0, mat)
	ResourceSaver.save(mesh, "res://assets/vegetation/grass_card_mesh.res", ResourceSaver.FLAG_CHANGE_PATH)
	var mi := MeshInstance3D.new()
	mi.name = "LOD0"
	mi.mesh = load("res://assets/vegetation/grass_card_mesh.res")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ps := PackedScene.new()
	ps.pack(mi)
	ResourceSaver.save(ps, "res://assets/vegetation/grass_card.tscn")
	print("[grass] scene written")
	quit()
