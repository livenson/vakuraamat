# Visual check of the bicycle with its rider: side and three-quarter views.
#   godot --path . res://tools/godot/bike_preview.tscn -- --screenshot=/abs/out.png [--frames=60]
extends Node3D

var _path := ""
var _frame := 0
var _at := 60


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--screenshot="):
			_path = a.trim_prefix("--screenshot=")
		elif a.begins_with("--frames="):
			_at = int(a.trim_prefix("--frames="))
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.62, 0.7)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.75, 0.8)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = PlaneMesh.new()
	floor_mesh.mesh.size = Vector2(12, 6)
	add_child(floor_mesh)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	# four bikes seen from the side, riding towards -X on screen; a red block marks the riding direction
	for i in 4:
		rng.seed = 3 + i
		var pivot := Node3D.new()
		pivot.position = Vector3(-4.5 + i * 3.0, 0, 0)
		pivot.rotation.y = PI / 2.0   # agents ride towards -Z; turned so the camera sees the side
		add_child(pivot)
		pivot.add_child(TrafficAgent.build_bike(true, rng, Color(0.7, 0.75, 0.9)))
		var mark := MeshInstance3D.new()
		mark.mesh = BoxMesh.new()
		mark.mesh.size = Vector3(0.15, 0.15, 0.15)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.9, 0.1, 0.1)
		mark.material_override = mat
		mark.position = Vector3(0, 1.4, -0.9)   # in front of the bike
		pivot.add_child(mark)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.6, 6.0)
	cam.look_at_from_position(cam.position, Vector3(0, 0.8, 0))
	cam.fov = 55
	add_child(cam)
	cam.current = true


func _process(_delta: float) -> void:
	if _path == "":
		return
	_frame += 1
	if _frame == _at:
		get_viewport().get_texture().get_image().save_png(_path)
		print("[bike_preview] shot -> ", _path)
		get_tree().quit()
