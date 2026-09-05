# Visual check of vendored models: every glb in a directory in a row, each scaled to `--fit` metres
# along its longest axis, standing on the ground.
#   godot --path . res://tools/godot/model_preview.tscn -- --dir=res://assets/vendor/polypizza/ --fit=2 --screenshot=/abs/out.png
extends Node3D

var _path := ""
var _frame := 0


func _ready() -> void:
	var dir := "res://assets/vendor/polypizza/"
	var fit := 2.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--screenshot="):
			_path = a.trim_prefix("--screenshot=")
		elif a.begins_with("--dir="):
			dir = a.trim_prefix("--dir=")
		elif a.begins_with("--fit="):
			fit = float(a.trim_prefix("--fit="))
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
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = PlaneMesh.new()
	floor_mesh.mesh.size = Vector2(60, 20)
	add_child(floor_mesh)
	var files: Array = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".glb"):
			files.append(f)
	files.sort()
	var x := -(files.size() - 1) * fit * 0.7
	for f in files:
		var n: Node3D = (load(dir + f) as PackedScene).instantiate()
		add_child(n)
		var aabb := _bounds(n)
		var longest := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
		var k := fit / maxf(longest, 0.001)
		n.scale = Vector3.ONE * k
		n.position = Vector3(x - (aabb.position.x + aabb.size.x * 0.5) * k, -aabb.position.y * k, -(aabb.position.z + aabb.size.z * 0.5) * k)
		var label := Label3D.new()
		label.text = f
		label.font_size = 48
		label.pixel_size = 0.01
		label.position = Vector3(x, fit + 0.4, 0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(label)
		print("[model_preview] %s longest %.3f -> scale %.4f" % [f, longest, k])
		x += fit * 1.4
	var cam := Camera3D.new()
	cam.position = Vector3(0, fit * 1.2, files.size() * fit * 0.55 + fit * 2.0)
	cam.look_at_from_position(cam.position, Vector3(0, fit * 0.5, 0))
	cam.fov = 60
	add_child(cam)
	cam.current = true


static func _bounds(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var p: Node = mi
		while p != n and p is Node3D:
			xf = p.transform * xf
			p = p.get_parent()
		var b: AABB = xf * mi.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


func _process(_d: float) -> void:
	if _path == "":
		return
	_frame += 1
	if _frame == 40:
		get_viewport().get_texture().get_image().save_png(_path)
		print("[model_preview] shot -> ", _path)
		get_tree().quit()
