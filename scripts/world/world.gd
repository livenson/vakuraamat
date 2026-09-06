# The one world scene: shared terrain + sky, the player, and one EraLayer per era.
# Era switching keeps the player where they stand and swaps texture, props and NPCs.
# Which ground, spawn, sky and water: the active site pack (Sites.manifest).
extends Node3D

const FADE_TIME := 1.2

@onready var terrain: Terrain3D = $Terrain3D
@onready var sky: Sky3D = $Sky3D
@onready var player: CharacterBody3D = $Player
@onready var layers: Node3D = $EraLayers
@onready var ui: CanvasLayer = $UI
@onready var fade: ColorRect = $UI/Fade

var georef: TerrainGeoref
var streamer: TileStreamer          # neighbouring tiles around this pack's tile (endless map)
var _water_mat: ShaderMaterial
var _screenshot_path := ""
var _fx := ["sdfgi", "ssao", "ssil", "fog", "glow", "grade"]   # --fx=a,b,c limits the effects (measurement)
var _screenshot_frame := 240
var _frames := 0
var _ready_done := false            # screenshots and the clock wait for the terrain build
var _era_nodes: Dictionary = {}     # era_id -> EraController
var _spawn := Vector3(512, 0, 512)  # from the site manifest "start.spawn" (tile metres)


func _ready() -> void:
	GameState.world = self
	var tile_dir := Sites.tile_dir()
	fade.color.a = 1.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--screenshot="):
			player.input_enabled = false   # deterministic captures: no mouse motion while the ground builds
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if (terrain.data == null or terrain.data.region_locations.is_empty()) and TerrainBuilder.has_inputs(tile_dir):
		await _build_terrain(tile_dir)   # downloaded tile: inputs present, region data not yet built
	if terrain.data == null or terrain.data.region_locations.is_empty():
		push_error("no terrain data for tile %s - run make tile SITE=%s" % [Sites.tile(), Sites.active])
	georef = TerrainGeoref.load_dir(tile_dir)
	var start: Dictionary = Sites.get_value("start", {})
	var sp: Array = start.get("spawn", [512, 512])
	_spawn = Vector3(float(sp[0]), 0.0, float(sp[1]))
	terrain.set_camera(player.camera)
	_configure_sky()
	_apply_orthophoto()
	place_water(Sites.active, self)
	streamer = TileStreamer.new()
	streamer.name = "Tiles"
	add_child(streamer)
	streamer.setup(self)
	fade.color.a = 1.0
	await get_tree().process_frame
	var report := _report_from_args()
	if not report.is_empty() and SaveManager.has_save(str(report.get("save_slot", ""))):
		GameState.pending_load = false
		await SaveManager.load_slot(str(report.save_slot))
	elif GameState.pending_load and SaveManager.has_save():
		GameState.pending_load = false
		await SaveManager.load_slot()
	if not GameState.current_era:
		# New game (or the scene run directly): fresh state, prologue in 2026.
		GameState.reset()
		player.global_position = _spawn
		player.rotation.y = deg_to_rad(float(start.get("yaw_deg", 180.0)))
		_snap(player, 1.0)
		var order := GameState.eras_in_order()
		var first_era: String = str(start.get("era", order[-1].id if not order.is_empty() else ""))
		await GameState.switch_era(first_era)
	if not report.is_empty():
		var p: Array = report.get("position", [])
		if p.size() == 3:
			player.set_pose(Vector3(float(p[0]), float(p[1]), float(p[2])), deg_to_rad(float(report.get("yaw_deg", 0.0))), deg_to_rad(float(report.get("pitch_deg", 0.0))))
		if not GameState.current_era:
			await GameState.switch_era(str(report.get("era", "")))
		print("[world] replaying report %s" % report.get("id", ""))
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 0.0, FADE_TIME)
	_ready_done = true
	Ledger.start(Sites.active)
	var marks := ParcelMarks.new()
	marks.name = "ParcelMarks"
	add_child(marks)
	marks.setup(self)
	var builder := ParcelBuilder.new()
	builder.name = "ParcelBuilder"
	add_child(builder)
	builder.setup(self)
	var figures := PresenceFigures.new()
	figures.name = "PresenceFigures"
	add_child(figures)
	figures.setup(self)
	var interiors := Interiors.new()
	interiors.name = "Interiors"
	add_child(interiors)
	interiors.setup(self)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--screenshot="):
			_screenshot_path = a.trim_prefix("--screenshot=")
			# deterministic captures: no stray mouse motion, no movement
			player.input_enabled = false
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif a.begins_with("--frames="):
			_screenshot_frame = int(a.trim_prefix("--frames="))
		elif a.begins_with("--spawn="):
			# x,z[,yaw[,height[,pitch]]]: a height keeps the player in the air (with --fly), else snapped to the ground
			var parts := a.trim_prefix("--spawn=").split(",")
			player.global_position = Vector3(float(parts[0]), 200.0, float(parts[1]))
			if parts.size() > 2:
				player.rotation.y = deg_to_rad(float(parts[2]))
			if parts.size() > 3:
				player.global_position.y = float(parts[3])
			else:
				_snap(player, 1.0)
			if parts.size() > 4:
				player.set_pose(player.global_position, player.rotation.y, deg_to_rad(float(parts[4])))
		elif a == "--fly":
			player.flying = true
		elif a.begins_with("--own="):
			# verification runs: buy a plot (and build on it: --own=<tunnus>+<structure>) once the ground stands
			var bits := a.trim_prefix("--own=").split("+")
			get_tree().create_timer(1.5).timeout.connect(func():
				if Ledger.parcel(bits[0]).is_empty():
					Ledger.reset_local(Sites.active)   # a direct world run has no book yet
				await Ledger.debug_grant(1000000)
				var err: String = await Ledger.buy(bits[0])
				if bits.size() > 1 and err == "":
					err = await Ledger.build(bits[0], bits[1])
				print("[world] --own %s: %s" % [a, "ok" if err == "" else err]))
		elif a.begins_with("--hour="):
			if sky and sky.tod:
				sky.tod.current_time = float(a.trim_prefix("--hour="))
		elif a.begins_with("--fx="):
			_fx = Array(a.trim_prefix("--fx=").split(",", false))
			_configure_environment()
		elif a.begins_with("--enter="):
			get_tree().create_timer(2.5).timeout.connect(enter_building.bind(a.trim_prefix("--enter=")))
		elif a == "--leave":
			# checks: after --enter, step back out and turn to face the door from the street
			get_tree().create_timer(4.0).timeout.connect(func():
				var ins: Node = get_node_or_null("Interiors")
				if ins and ins.inside:
					ins.exit(player)
					player.set_pose(player.global_position, player.rotation.y + PI, 0.0))
		elif a.begins_with("--open="):
			get_tree().create_timer(2.0).timeout.connect(ui.debug_open.bind(a.trim_prefix("--open=")))


## The report named by --report=, for the first world of this process only: a world entered later
## from the menu (another location) must not inherit the report's save and position.
func _report_from_args() -> Dictionary:
	if GameState.report_replayed:
		return {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--report="):
			GameState.report_replayed = true
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(a.trim_prefix("--report=")))
			if typeof(parsed) != TYPE_DICTIONARY:
				push_error("cannot read report " + a)
				return {}
			var site := str(parsed.get("site", Sites.active))
			if site != Sites.active:
				push_warning("report %s is from site %s, not %s: not replayed" % [parsed.get("id", ""), site, Sites.active])
				return {}
			return parsed
	return {}


## Dev hot reload: drop an era layer and, if it is the current one, instance it again from disk
## with the player left where they stand.
func reload_era_layer(era_id: String) -> void:
	var old: Node = _era_nodes.get(era_id)
	if old:
		layers.remove_child(old)
		old.queue_free()
		_era_nodes.erase(era_id)
	if era_id != GameState.current_era:
		return
	var era: EraDefinition = GameState.era(era_id)
	if era == null:
		return
	var node: EraController = load(era.scene_path).instantiate()
	layers.add_child(node)
	_era_nodes[era_id] = node
	node.activate()
	_set_drape(era)
	_snap(player, 1.0)


## Dev restart at this exact spot: write a report (with a save) and relaunch the world scene on it.
func restart_here() -> void:
	var path := Reporter.capture("restart", self)
	var args := ["--path", ProjectSettings.globalize_path("res://"), "res://scenes/world/world.tscn", "--", "--report=" + path]
	for a in OS.get_cmdline_user_args():
		if a in ["--windowed", "--fullscreen", "--dev"]:
			args.append(a)
	OS.create_process(OS.get_executable_path(), args)
	get_tree().quit()


func _exit_tree() -> void:
	if GameState.world == self:
		GameState.world = null


func _process(_delta: float) -> void:
	if _ready_done:
		Ledger.move(player.global_position, player.rotation.y)
	if not _ready_done:
		return
	if sky and sky.tod:
		var current: EraController = _era_nodes.get(GameState.current_era)
		if current:
			current.set_hour(sky.tod.current_time)
		if streamer:
			streamer.set_hour(sky.tod.current_time)
	if streamer:
		streamer.guard(player)
	if _screenshot_path.is_empty():
		return
	_frames += 1
	if _frames == _screenshot_frame:
		get_viewport().get_texture().get_image().save_png(_screenshot_path)
		print("[world] screenshot -> %s  fps %d  era %s  player %s" % [_screenshot_path, Engine.get_frames_per_second(), GameState.current_era, player.global_position])
		get_tree().quit()


## Called by GameState.switch_era. Fades through the book, swaps the era layer, keeps position.
func apply_era(era: EraDefinition, first_visit: bool) -> void:
	var was_visible: bool = fade.color.a < 0.5
	if was_visible:
		var tw := create_tween()
		tw.tween_property(fade, "color:a", 1.0, FADE_TIME * 0.5)
		await tw.finished
	for id in _era_nodes:
		_era_nodes[id].deactivate()
	var node: EraController = _era_nodes.get(era.id)
	if node == null:
		node = load(era.scene_path).instantiate()
		layers.add_child(node)
		_era_nodes[era.id] = node
	node.activate()
	if streamer:
		streamer.set_era(era.id)
	_push_out_of_buildings(node)
	_set_drape(era)
	if first_visit and sky.tod:
		sky.tod.current_time = era.default_time_of_day
	_snap(player, 1.0)
	if was_visible:
		var tw2 := create_tween()
		tw2.tween_property(fade, "color:a", 0.0, FADE_TIME * 0.5)
		await tw2.finished


func _set_drape(era: EraDefinition) -> void:
	var mat := terrain.material
	var tex := era.texture()
	if tex:
		mat.set_shader_param("ortho_texture", tex)
	mat.set_shader_param("ortho_strength", era.texture_strength)
	mat.set_shader_param("ortho_tint", era.ground_tint)


func _apply_orthophoto() -> void:
	var mat := terrain.material
	mat.set_shader_param("ortho_origin", Vector2.ZERO)
	mat.set_shader_param("ortho_extent", georef.tile_size_m())


## The terrain tile named by the site. Assigned before Terrain3D enters the tree (the World
## node enters first), so the region data and ground assets load exactly as if baked in the scene.
func _enter_tree() -> void:
	var dir := Sites.tile_dir()
	var t3d: Terrain3D = get_node("Terrain3D")
	var assets_path := dir + "/terrain_assets.tres"
	if ResourceLoader.exists(assets_path):
		t3d.assets = load(assets_path)
	if TerrainBuilder.has_inputs(dir) and not TerrainBuilder.has_region_data(dir):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir + "/data"))   # Terrain3D needs it to create its data object
	t3d.data_directory = dir + "/data"


## First visit to a downloaded tile: import the heightmap/orthophoto and scatter vegetation
## into the live Terrain3D, saving the region data for next time. Shows progress on the fade.
func _build_terrain(tile_dir: String) -> void:
	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color(0.85, 0.68, 0.25))
	fade.add_child(label)
	var builder := TerrainBuilder.new()
	builder.yielding = true
	builder.tree = get_tree()
	builder.progress.connect(func(stage: String, f: float): label.text = "%s\n%s  %d%%" % [tr("UI_BUILDING_GROUND"), stage, int(f * 100)])
	var layout := Sites.layout()
	var ok: bool = await builder.import(terrain, tile_dir, layout)
	if ok:
		var mask := TerrainBuilder.footprint_mask(Sites.path("buildings.json"), terrain.region_size, TerrainBuilder.road_mask(Sites.path("roads.json"), terrain.region_size))
		await builder.scatter(terrain, tile_dir, layout.get("exclusions", []) + TerrainBuilder.water_exclusions(Sites.path(str(Sites.get_value("water", "")))), 1798, [], Vector2i.ZERO, mask)
	# let Terrain3D rebuild its clipmap and collision around the camera before anyone is placed on it
	terrain.set_camera(player.camera)
	terrain.data.update_maps()
	for i in 3:
		await get_tree().process_frame
	label.queue_free()


func _configure_sky() -> void:
	var tod := sky.tod
	var t: Dictionary = Sites.terrain()
	tod.latitude = deg_to_rad(float(t.get("latitude", 58.1158)))
	tod.longitude = deg_to_rad(float(t.get("longitude", 26.3341)))
	tod.utc = float(t.get("utc_offset", 3.0))
	var date: Array = t.get("date", [2026, 9, 3])
	tod.year = int(date[0])
	tod.month = int(date[1])
	tod.day = int(date[2])
	tod.minutes_per_day = 150.0   # a full day in 2.5 real hours; the slice is ~80 min
	tod.game_time_enabled = true
	_configure_environment()


## Rendering on top of Sky3D's Environment (visual upgrade plan step 1). All Forward+ built-ins.
func _configure_environment() -> void:
	var env: Environment = sky.environment
	if env == null:
		return
	env.sdfgi_enabled = "sdfgi" in _fx
	env.ssao_enabled = "ssao" in _fx
	env.ssil_enabled = "ssil" in _fx
	env.volumetric_fog_enabled = "fog" in _fx
	env.glow_enabled = "glow" in _fx
	env.adjustment_enabled = "grade" in _fx
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = 0.5
	env.sdfgi_use_occlusion = true
	env.sdfgi_bounce_feedback = 0.4
	env.sdfgi_energy = 1.0
	env.ssao_radius = 1.5
	env.ssao_intensity = 1.5
	env.ssil_radius = 4.0
	env.ssil_intensity = 1.0
	env.volumetric_fog_density = 0.004
	env.volumetric_fog_albedo = Color(0.9, 0.92, 0.95)
	env.volumetric_fog_sky_affect = 0.3
	env.volumetric_fog_ambient_inject = 0.2
	env.glow_intensity = 0.35
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.2
	env.adjustment_contrast = 1.05
	env.adjustment_saturation = 1.08
	terrain.gi_mode = GeometryInstance3D.GI_MODE_STATIC


## If the player stands where this era has a solid building (e.g. inside the 2026 ruin when the
## 1798 manor appears), step out through the nearest wall instead of being ejected by physics.
func _push_out_of_buildings(layer: Node) -> void:
	var pos := player.global_position
	for body in layer.find_children("*", "StaticBody3D", true, false):
		var group: Node = body.get_parent()
		if not (group is Node3D) or not group.has_meta("footprint"):
			continue
		var shape: CollisionShape3D = body.get_node_or_null("Shape")
		if shape == null or not (shape.shape is BoxShape3D):
			continue
		var half: Vector3 = shape.shape.size * 0.5
		var local: Vector3 = shape.global_transform.affine_inverse() * pos
		if absf(local.x) < half.x and absf(local.z) < half.z and local.y > -half.y and local.y < half.y + 2.0:
			var margin := 1.5
			var dx := half.x - absf(local.x)
			var dz := half.z - absf(local.z)
			if dx < dz:
				local.x = signf(local.x) * (half.x + margin) if local.x != 0.0 else half.x + margin
			else:
				local.z = signf(local.z) * (half.z + margin) if local.z != 0.0 else half.z + margin
			player.global_position = shape.global_transform * local
			player.velocity = Vector3.ZERO
			_snap(player, 1.0)
			return


## Still water from a pack's water file (flat patches in the laser DTM): the same ponds in every era.
## `root` is the world for the active pack, a streamed tile's offset root for a neighbour. Each pond
## carves its basin into the terrain and keeps its fish (Pond).
func place_water(pack: String, root: Node3D) -> void:
	Crops.place(pack, root, terrain)   # farmed fields (fields_2026.json) get their crops with the water
	var rel := str(Sites.manifest_for(pack).get("water", ""))
	if rel == "" or not FileAccess.file_exists(Sites.path_in(pack, rel)):
		return
	var ponds: Array = JSON.parse_string(FileAccess.get_file_as_string(Sites.path_in(pack, rel)))
	if _water_mat == null:
		_water_mat = ShaderMaterial.new()
		_water_mat.shader = load("res://assets/shaders/lake.gdshader")
		_water_mat.set_shader_parameter("normalmap_a", load("res://assets/textures/water/Water_N_A.png"))
		_water_mat.set_shader_parameter("foam_sampler", load("res://assets/textures/water/Foam.png"))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("boats_" + pack)
	_place_moored(pack, root)
	for p in ponds:
		var pond := Pond.new()
		pond.name = "Pond"
		pond.setup(p, _water_mat)
		root.add_child(pond)
		pond.carve(terrain)
		_moor_boats(p, root, rng)


const BOATS := {"rowboat": 4.0, "canoe": 4.6, "boat": 5.0, "sailboat": 6.5}   # model -> length in metres


## Boats where the orthophoto shows them: the feature pass writes boats_2026.json ([{x, z, length,
## heading}] for bright hulls beside dark water); each gets a model by its length, at its heading.
func _place_moored(pack: String, root: Node3D) -> void:
	var path := Sites.path_in(pack, "boats_2026.json")
	if not FileAccess.file_exists(path):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_ARRAY:
		return
	for b in parsed:
		var length := float(b.get("length", 4.0))
		var name := "canoe" if length < 4.0 else ("rowboat" if length < 5.5 else ("boat" if length < 7.5 else "sailboat"))
		var hull := _boat(name, clampf(length, 3.0, 9.0))
		if hull == null:
			continue
		var at := Vector3(float(b.x), 0.0, float(b.z))
		var h: float = terrain.data.get_height(at)
		hull.position = Vector3(at.x, (h if not is_nan(h) else 0.0) + 0.05, at.z)
		hull.rotation.y = deg_to_rad(float(b.get("heading", 0.0)))
		root.add_child(hull)


## A boat model with its long axis along local Z, scaled to `length` metres, standing on its origin.
func _boat(name: String, length: float) -> Node3D:
	var path := "res://assets/vendor/polypizza/%s.glb" % name
	if not ResourceLoader.exists(path):
		return null
	var model: Node3D = (load(path) as PackedScene).instantiate()
	var b: AABB = Interiors._bounds(model)
	var longest := maxf(b.size.x, b.size.z)
	if longest < 0.0001:
		return null
	var k := length / longest
	var hull := Node3D.new()
	model.scale = Vector3.ONE * k
	model.position = Vector3(-(b.position.x + b.size.x * 0.5) * k, -b.position.y * k, -(b.position.z + b.size.z * 0.5) * k)
	if b.size.x > b.size.z:
		model.rotation.y = PI / 2.0
	hull.add_child(model)
	return hull

## Boats moored along the long side of a pond or bay (area in m²): one to four small boats, a
## sailboat on big water. Poly Pizza models (see THIRD_PARTY.md), scaled from their bounds.
func _moor_boats(p: Dictionary, root: Node3D, rng: RandomNumberGenerator) -> void:
	var area := float(p.get("area", 0))
	if area < 300.0:
		return
	var n := clampi(int(area / 700.0), 1, 4)
	var w := float(p.w)
	var d := float(p.d)
	var along_x := w >= d
	var length := w if along_x else d
	var names: Array = ["rowboat", "canoe", "boat"]
	for i in n:
		var name: String = names[rng.randi() % names.size()] if not (i == 0 and area >= 2000.0) else "sailboat"
		var hull := _boat(name, BOATS[name])
		if hull == null:
			continue
		var t := (i + 0.5) / n
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var inset := minf(4.0, (d if along_x else w) * 0.3)
		var at := Vector2(float(p.x) - w * 0.5 + length * t, float(p.z) + side * (d * 0.5 - inset)) if along_x \
			else Vector2(float(p.x) + side * (w * 0.5 - inset), float(p.z) - d * 0.5 + length * t)
		hull.position = Vector3(at.x, float(p.get("level", 0.0)) + 0.05, at.y)
		hull.rotation.y = (0.0 if along_x else PI / 2.0) + rng.randf_range(-0.25, 0.25) + (PI if rng.randf() < 0.5 else 0.0)
		root.add_child(hull)


func _snap(node: Node3D, lift: float) -> void:
	var h := terrain.data.get_height(node.global_position)
	if not is_nan(h):
		node.global_position.y = h + lift


func clock_string() -> String:
	return sky.tod.game_time if sky and sky.tod else ""


func to_dict() -> Dictionary:
	return {
		"player_pos": [player.global_position.x, player.global_position.y, player.global_position.z],
		"player_yaw": player.rotation.y,
		"time_of_day": sky.tod.current_time if sky.tod else 10.0,
	}


func from_dict(d: Dictionary) -> void:
	var p: Array = d.get("player_pos", [])
	if p.size() == 3:
		player.global_position = Vector3(p[0], p[1], p[2])
		player.rotation.y = float(d.get("player_yaw", 0.0))
	if sky.tod and d.has("time_of_day"):
		sky.tod.current_time = float(d.time_of_day)


## Step into the first real building of the origin layer or any loaded tile whose address contains
## `needle` (debug: --enter=, dev channel). "<address>@<degrees>" turns the player after stepping in.
func enter_building(needle: String) -> bool:
	var interiors: Interiors = get_node_or_null("Interiors")
	if interiors == null:
		return false
	var turn := 0.0
	if "@" in needle:
		turn = deg_to_rad(float(needle.get_slice("@", 1)))
		needle = needle.get_slice("@", 0)
	var scopes: Array = [$EraLayers.get_node_or_null(GameState.current_era)]
	if streamer:
		for loc in streamer.tiles:
			var root: Node = streamer.tiles[loc].get("root")
			if root:
				scopes.append(root.get_node_or_null("Era"))
	for layer in scopes:
		if layer == null:
			continue
		for b in layer.find_children("*", "FootprintBuilding", true, false):
			if needle.to_lower() in str(b.address).to_lower() and b.get_node_or_null("Door"):
				interiors.enter(b, player)
				if turn != 0.0:
					player.rotation.y += turn
				return true
	return false
