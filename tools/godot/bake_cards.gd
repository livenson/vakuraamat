# Bakes crop cards: renders every glb in a directory front-on with an orthographic camera onto a
# transparent background and writes a 128x256 RGBA png per model into --out. crops.gd uses a baked
# card when one exists for the kind (potato, maize, legume from the Sketchfab farm plants).
# Needs a window (the dummy renderer cannot render):
#   godot --path . res://tools/godot/bake_cards.tscn -- --dir=res://assets/vendor/_review/plants/ --out=res://assets/textures/crops/
extends Node3D

const SIZE := Vector2i(128, 256)

var _dir := "res://assets/vendor/_review/plants/"
var _out := "res://assets/textures/crops/"
var _queue: Array[String] = []
var _viewport: SubViewport
var _camera: Camera3D
var _holder: Node3D
var _frames := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dir="):
			_dir = a.trim_prefix("--dir=")
		elif a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	for f in DirAccess.get_files_at(_dir):
		if f.ends_with(".glb"):
			_queue.append(f)
	_viewport = SubViewport.new()
	_viewport.size = SIZE
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0, 0, 0, 0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 1.0
	env.environment = e
	_viewport.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 20, 0)
	sun.light_energy = 0.6
	_viewport.add_child(sun)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_viewport.add_child(_camera)
	_holder = Node3D.new()
	_viewport.add_child(_holder)
	_next()


func _next() -> void:
	for c in _holder.get_children():
		c.free()
	if _queue.is_empty():
		print("[bake_cards] done")
		get_tree().quit()
		return
	var f: String = _queue.pop_front()
	var model: Node3D = (load(_dir + f) as PackedScene).instantiate()
	_holder.add_child(model)
	var b: AABB = Interiors._bounds(model)
	var h := maxf(b.size.y, 0.01)
	var w := maxf(maxf(b.size.x, b.size.z), 0.01)
	# the card is 1:2 (width:height); frame the plant so its height fills the card, centred
	_camera.size = h * 1.05
	_camera.position = Vector3(b.position.x + b.size.x * 0.5, b.position.y + h * 0.5, b.position.z + b.size.z * 0.5 + w + h + 2.0)
	_camera.look_at(Vector3(b.position.x + b.size.x * 0.5, b.position.y + h * 0.5, b.position.z + b.size.z * 0.5))
	set_meta("current", f.get_basename())
	_frames = 0


func _process(_d: float) -> void:
	_frames += 1
	if _frames == 6:
		var img := _viewport.get_texture().get_image()
		var path: String = _out + str(get_meta("current")) + ".png"
		img.save_png(path)
		print("[bake_cards] %s <- %s" % [path, get_meta("current")])
		_next()
