# Walks a world at one place once its layer has filled in and adds every distinct material it finds
# there to res://assets/materials/runtime_shaders.tres (RuntimeShaders), unless the file has an
# equivalent one already. The export's shader baker then bakes their shaders with the rest.
#   godot --path . res://tools/godot/shader_manifest.tscn -- --site=kvissentali      (make shaders)
# Not --headless: Terrain3D's shader code comes from the renderer.
extends Node

const OUT := "res://assets/materials/runtime_shaders.tres"

var _manifest: RuntimeShaders
var _known := {}   # signature -> true
var _added := 0


func _ready() -> void:
	get_tree().create_timer(300.0).timeout.connect(func():
		print("[shaders] FAILED: watchdog")
		get_tree().quit(2))
	_manifest = load(OUT) as RuntimeShaders if ResourceLoader.exists(OUT) else null
	if _manifest == null:
		_manifest = RuntimeShaders.new()
	for m in _manifest.materials:
		_known[signature(m)] = true
	await get_tree().process_frame
	GameState.reset()
	var world: Node3D = load("res://scenes/world/world.tscn").instantiate()
	add_child(world)
	while not world._ready_done:   # the loading screen lifts once the layer has filled in
		await get_tree().process_frame
	await get_tree().process_frame
	_collect(get_tree().root, Sites.active)
	await get_tree().create_timer(8.0).timeout   # traffic, the parcel and link marks arrive after the curtain
	_collect(get_tree().root, Sites.active)
	var terrain: Terrain3D = world.terrain
	if terrain and terrain.material:
		var code := RenderingServer.shader_get_code(terrain.material.get_shader_rid())
		if code != "":
			var shader := Shader.new()
			shader.code = code
			var m := ShaderMaterial.new()
			m.shader = shader
			_add(m, "%s: Terrain3D" % Sites.active)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	var err := ResourceSaver.save(_manifest, OUT)
	print("[shaders] %s: %d new, %d in %s (save %s)" % [Sites.active, _added, _manifest.materials.size(), OUT, error_string(err)])
	get_tree().quit(0 if err == OK else 1)


func _collect(n: Node, site: String) -> void:
	if n is GeometryInstance3D:
		var what := "%s: %s %s" % [site, n.get_class(), n.name]
		_add(n.material_override, what)
		_add(n.material_overlay, what)
		if n is MeshInstance3D and n.mesh:
			for i in n.mesh.get_surface_count():
				_add(n.get_active_material(i), what)
		elif n is MultiMeshInstance3D and n.multimesh and n.multimesh.mesh:
			for i in n.multimesh.mesh.get_surface_count():
				_add(n.multimesh.mesh.surface_get_material(i), what)
		elif n is Label3D:
			_add(label_material(n), what)
	elif n is WorldEnvironment and n.environment and n.environment.sky:
		_add(n.environment.sky.sky_material, "%s: sky" % site)
	for c in n.get_children():
		_collect(c, site)


## Materials saved in files are baked already; the ones built in code are what this is for. A
## ShaderMaterial built in code around a .gdshader file counts too: the baker reaches shaders through
## materials, and the lake water and Sky3D's fog, made that way, were compiled on the first frame.
## The copy keeps what decides the shader and none of the textures.
func _add(mat: Material, what: String) -> void:
	while mat != null:
		var copy: Material = null
		if mat is ShaderMaterial and mat.resource_path == "":
			if mat.shader:
				copy = ShaderMaterial.new()
				if mat.shader.resource_path.begins_with("res://") and not mat.shader.resource_path.contains("::"):
					copy.shader = mat.shader   # saved as a reference to the file
				else:
					var shader := Shader.new()
					shader.code = mat.shader.code
					copy.shader = shader
		elif mat is BaseMaterial3D and mat.resource_path == "":
			copy = mat.duplicate()
			for p in copy.get_property_list():
				if p.type == TYPE_OBJECT and p.usage & PROPERTY_USAGE_STORAGE:
					copy.set(p.name, null)
		if copy:
			var sig := signature(copy)
			if not _known.has(sig):
				_known[sig] = true
				_manifest.materials.append(copy)
				_manifest.sources.append(what)
				_added += 1
		mat = mat.next_pass


## The material a Label3D draws its glyphs with. Label3D builds it inside the engine
## (BaseMaterial3D::get_material_for_2d, scene/resources/material.cpp in 4.7) where no script can
## reach it, so this is that function over the label's settings (Label3D::_generate_glyph_surfaces).
static func label_material(l: Label3D) -> StandardMaterial3D:
	var transparency := BaseMaterial3D.TRANSPARENCY_ALPHA
	match l.alpha_cut:
		Label3D.ALPHA_CUT_DISCARD: transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		Label3D.ALPHA_CUT_OPAQUE_PREPASS: transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
		Label3D.ALPHA_CUT_HASH: transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
	var font: Font = l.font if l.font else ThemeDB.fallback_font
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL if l.shaded else BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = transparency
	m.cull_mode = BaseMaterial3D.CULL_DISABLED if l.double_sided else BaseMaterial3D.CULL_BACK
	m.vertex_color_is_srgb = true
	m.vertex_color_use_as_albedo = true
	m.albedo_texture_msdf = bool(font.get("multichannel_signed_distance_field")) if font else false
	m.no_depth_test = l.no_depth_test
	m.fixed_size = l.fixed_size
	m.texture_repeat = false
	m.alpha_antialiasing_mode = l.alpha_antialiasing_mode
	m.texture_filter = l.texture_filter
	if l.billboard != BaseMaterial3D.BILLBOARD_DISABLED:
		m.billboard_keep_scale = true
		m.billboard_mode = l.billboard
	return m


## What decides a material's shader: a ShaderMaterial's code, a BaseMaterial3D's features, flags
## and modes (its booleans and enums; colours, amounts and textures are parameters of one shader).
static func signature(mat: Material) -> String:
	if mat is ShaderMaterial:
		return "shader:" + (mat.shader.code if mat.shader else "")
	if not (mat is BaseMaterial3D):
		return ""
	var parts: PackedStringArray = [mat.get_class()]
	for p in mat.get_property_list():
		if p.usage & PROPERTY_USAGE_STORAGE and (p.type == TYPE_BOOL or p.type == TYPE_INT) and p.name != "render_priority":
			parts.append("%s=%s" % [p.name, mat.get(p.name)])
	return ",".join(parts)
