# Visual check of the tree scenes: the full models in a row, their LOD stand-ins behind them.
#   godot --path . res://tools/godot/tree_preview.tscn -- --screenshot=/abs/out.png
extends Node3D

const SCENES := ["tree_pine", "tree_spruce", "tree_birch", "tree_juniper", "tree_juniper_dead"]
var _path := ""
var _frame := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--screenshot="):
			_path = a.trim_prefix("--screenshot=")
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.62, 0.7)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.75, 0.8)
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = PlaneMesh.new()
	floor_mesh.mesh.size = Vector2(80, 40)
	add_child(floor_mesh)
	for i in SCENES.size():
		var full := "res://assets/vegetation/%s.tscn" % SCENES[i]
		var lod := "res://assets/models/trees/%s_lod.tscn" % SCENES[i].trim_prefix("tree_")
		for pair in [[full, 0.0], [lod, -12.0]]:
			if ResourceLoader.exists(pair[0]):
				var n: Node3D = load(pair[0]).instantiate()
				n.position = Vector3(-24 + i * 12, 0, pair[1])
				add_child(n)
				print("[tree_preview] %s ok" % pair[0])
			else:
				print("[tree_preview] %s missing" % pair[0])
	var cam := Camera3D.new()
	cam.position = Vector3(0, 9, 34)
	cam.look_at_from_position(cam.position, Vector3(0, 6, -4))
	cam.fov = 60
	add_child(cam)
	cam.current = true


func _process(_d: float) -> void:
	if _path == "":
		return
	_frame += 1
	if _frame == 60:
		get_viewport().get_texture().get_image().save_png(_path)
		print("[tree_preview] shot -> ", _path)
		get_tree().quit()
