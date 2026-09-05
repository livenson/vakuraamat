# Visual check of the MakeHuman figures: all eight in a row, walking, with a camera in front.
#   godot --path . res://tools/godot/figure_preview.tscn -- --screenshot=/abs/out.png [--frames=120]
extends Node3D

var _path := ""
var _frame := 0
var _at := 120


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
	floor_mesh.mesh.size = Vector2(20, 6)
	add_child(floor_mesh)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var names: Array = HumanFigure.MEN + HumanFigure.WOMEN
	var poses := ["stand", "arms_folded", "holding", "sit"]
	for i in names.size():
		var f := HumanFigure.make(rng, 2026 if i % 2 == 0 else 1938, names[i])
		f.position = Vector3(-7.0 + i * 2.0, 0, 0)
		if i < 4:
			f.set_walking(true, 1.0)
		else:
			f.pose = poses[i - 4]
		add_child(f)
		print("[figure_preview] %s: skeleton %s, %d bones" % [names[i], f.skeleton != null, f.skeleton.get_bone_count() if f.skeleton else 0])
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.4, 7.5)
	cam.fov = 60
	add_child(cam)
	cam.current = true
	# walkers should have a leg forward: advance the gait a bit
	var k := 0
	for f in get_children():
		if f is HumanFigure and f.walking:
			f._phase = 1.2 + k * 0.9
			k += 1


func _process(_delta: float) -> void:
	if _path == "":
		return
	_frame += 1
	if _frame == _at:
		get_viewport().get_texture().get_image().save_png(_path)
		print("[figure_preview] screenshot -> " + _path)
		get_tree().quit()
