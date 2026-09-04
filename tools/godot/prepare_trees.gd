# Turns the generated tree glbs into game meshes: foliage as alpha-scissor (no sorting,
# writes depth, works in impostor bakes), bark double-sided off, saved as binary meshes.
#   godot --headless --path . -s res://tools/godot/prepare_trees.gd
extends SceneTree

const TREES := ["birch", "pine", "spruce"]
const DIR := "res://assets/models/trees/"


func _init() -> void:
	for name in TREES:
		var scene: Node = load(DIR + name + ".glb").instantiate()
		var src: MeshInstance3D = scene.find_children("*", "MeshInstance3D", true, false)[0]
		var mesh := ArrayMesh.new()
		for si in src.mesh.get_surface_count():
			mesh.add_surface_from_arrays(src.mesh.surface_get_primitive_type(si), src.mesh.surface_get_arrays(si))
			var sname: String = src.mesh.surface_get_name(si)
			mesh.surface_set_name(si, sname)
			var m: StandardMaterial3D = src.mesh.surface_get_material(si).duplicate()
			if sname == "Foliage":
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				m.alpha_scissor_threshold = 0.45
				m.cull_mode = BaseMaterial3D.CULL_DISABLED
				m.backlight_enabled = true
				m.backlight = Color(0.35, 0.4, 0.2)
				m.roughness = 0.85
			else:
				m.cull_mode = BaseMaterial3D.CULL_BACK
			mesh.surface_set_material(si, m)
		var path: String = DIR + name + "_mesh.res"
		ResourceSaver.save(mesh, path, ResourceSaver.FLAG_CHANGE_PATH)
		print("[prepare_trees] %s: %d surfaces, aabb %s" % [name, mesh.get_surface_count(), mesh.get_aabb()])
		scene.free()
	quit()
