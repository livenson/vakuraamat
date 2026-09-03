# Builds clean instancer-ready scenes from the vendored Forest Vegetation sample pack
# (assets/vendor/forest_vegetation, MIT, Renard Noir): one MeshInstance3D named LOD0 per
# model, with the pack's .tres materials assigned by surface name, mesh saved as binary.
#   godot --headless --path . -s res://tools/godot/prepare_vegetation.gd
extends SceneTree

const SRC := "res://assets/vendor/forest_vegetation/"
const OUT := "res://assets/vegetation/"
const MODELS := {
	"tree_juniper": "Tree_Juniper_Regular", "tree_juniper_dead": "Tree_Juniper_Dead",
	"bush_jello": "Plant_JelloBush_Slim", "bush_brush": "Plant_Simple_Brush_Regular",
	"grass_tuft": "UG_Grass_Regular_", "mouse_ears": "UG_Mouse_Ears", "clover": "UG_Simple_Clovers",
}
const MATS := {
	"Trunk Branch": "Bark", "Forage1": "Foliage1", "Plant JelloBush": "JelloBush", "Plant1": "SimpleBrush",
	"Grassy Vegetation1": "CloverMouseEars", "plantitas1diff": "GrassyVegetation",  # the pack's two .tres files reference each other's textures
}


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for out_name in MODELS:
		var scene: Node = load(SRC + "Models/" + MODELS[out_name] + ".fbx").instantiate()
		var src: MeshInstance3D = scene.find_children("*", "MeshInstance3D", true, false)[0]
		var mesh: ArrayMesh = ArrayMesh.new()
		for si in src.mesh.get_surface_count():
			mesh.add_surface_from_arrays(src.mesh.surface_get_primitive_type(si), src.mesh.surface_get_arrays(si))
			var sname: String = src.mesh.surface_get_name(si)
			mesh.surface_set_name(si, sname)
			var assigned := false
			for key in MATS:
				if sname.begins_with(key):
					mesh.surface_set_material(si, load(SRC + "Materials/" + MATS[key] + ".tres"))
					assigned = true
			if not assigned:
				push_warning("%s surface '%s' has no material mapping" % [out_name, sname])
		var mesh_path: String = OUT + out_name + "_mesh.res"
		ResourceSaver.save(mesh, mesh_path, ResourceSaver.FLAG_CHANGE_PATH)
		var root := MeshInstance3D.new()
		root.name = "LOD0"
		root.mesh = load(mesh_path)
		var ps := PackedScene.new()
		ps.pack(root)
		ResourceSaver.save(ps, OUT + out_name + ".tscn")
		print("[prepare_vegetation] %-18s surfaces=%d aabb=%s" % [out_name, mesh.get_surface_count(), mesh.get_aabb().size])
		scene.free()
		root.free()
	quit()
