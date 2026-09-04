# Bakes billboard impostors for tree models: renders each model from 8 yaw angles at two
# elevations into a 4x4 atlas (albedo + alpha), then writes an LOD scene with the full mesh
# as LOD0 and an impostor quad as LOD1 for Terrain3D's instancer.
# Needs a window (the dummy renderer cannot render):
#   godot --path . res://tools/godot/bake_impostors.tscn
extends Node

const TREES := ["birch", "pine", "spruce"]
const FRAME := 512
const YAWS := 8
const ELEVATIONS := [0.0, 30.0]
const OUT := "res://assets/models/trees/"


func _ready() -> void:
	await get_tree().process_frame
	for name in TREES:
		await _bake(name)
	print("[bake] done")
	get_tree().quit()


func _bake(name: String) -> void:
	var scene := MeshInstance3D.new()
	scene.mesh = load(OUT + name + "_mesh.res")
	var aabb := _aabb(scene)
	var height := aabb.size.y
	var radius := maxf(aabb.size.x, aabb.size.z) * 0.5
	var extent := maxf(height, radius * 2.0) * 0.52
	var vp := SubViewport.new()
	vp.size = Vector2i(FRAME, FRAME)
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var world := Node3D.new()
	vp.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0, 0, 0, 0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.8, 0.8)
	e.ambient_light_energy = 1.0
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 0.9
	sun.shadow_enabled = false
	world.add_child(sun)
	world.add_child(scene)
	scene.position = Vector3(0, -aabb.position.y - height / 2.0, 0)   # centre vertically
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = extent * 2.0
	cam.near = 0.1
	cam.far = 200.0
	world.add_child(cam)
	var atlas := Image.create_empty(FRAME * 4, FRAME * 4, false, Image.FORMAT_RGBA8)
	var frame_i := 0
	for elev in ELEVATIONS:
		for y in YAWS:
			var yaw := TAU * y / YAWS
			var el := deg_to_rad(elev)
			var dir := Vector3(sin(yaw) * cos(el), sin(el), cos(yaw) * cos(el))
			cam.position = dir * 60.0
			cam.look_at(Vector3.ZERO, Vector3.UP)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var img := vp.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			atlas.blit_rect(img, Rect2i(0, 0, FRAME, FRAME), Vector2i((frame_i % 4) * FRAME, (frame_i / 4) * FRAME))
			frame_i += 1
	var atlas_path := OUT + name + "_impostor.png"
	atlas.save_png(atlas_path)
	vp.queue_free()
	_write_lod_scene(name, height, radius, aabb)
	print("[bake] %s: height %.1f radius %.1f -> %s" % [name, height, radius, atlas_path])


func _aabb(n: Node) -> AABB:
	if n is MeshInstance3D:
		return n.get_aabb()
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var a: AABB = mi.transform * mi.get_aabb()
		box = a if first else box.merge(a)
		first = false
	return box


## LOD scene: LOD0 = the glb mesh; LOD1 = a quad with the impostor shader.
func _write_lod_scene(name: String, height: float, radius: float, aabb: AABB) -> void:
	var extent := maxf(height, radius * 2.0) * 0.52
	var txt := """[gd_scene load_steps=5 format=3]

[ext_resource type="ArrayMesh" path="%s%s_mesh.res" id="1"]
[ext_resource type="Shader" path="res://assets/shaders/impostor.gdshader" id="2"]
[ext_resource type="Texture2D" path="%s%s_impostor.png" id="3"]

[sub_resource type="ShaderMaterial" id="mat"]
shader = ExtResource("2")
shader_parameter/atlas = ExtResource("3")
shader_parameter/yaws = 8
shader_parameter/elevations = 2

[sub_resource type="QuadMesh" id="quad"]
size = Vector2(%.3f, %.3f)
material = SubResource("mat")

[node name="%s" type="Node3D"]

[node name="LOD0" type="MeshInstance3D" parent="."]
mesh = ExtResource("1")

[node name="LOD1" type="MeshInstance3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, %.3f, 0)
mesh = SubResource("quad")
cast_shadow = 1
""" % [OUT, name, OUT, name, extent * 2.0, extent * 2.0, name, aabb.position.y + height / 2.0]
	var f := FileAccess.open(OUT + name + "_lod.tscn", FileAccess.WRITE)
	f.store_string(txt)
	f.close()
