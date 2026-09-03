# The one world scene: shared terrain + sky, the player, and one EraLayer per era.
# Era switching keeps the player where they stand and swaps texture, props and NPCs.
extends Node3D

const TILE := "palupera"
const FADE_TIME := 1.2

@onready var terrain: Terrain3D = $Terrain3D
@onready var sky: Sky3D = $Sky3D
@onready var player: CharacterBody3D = $Player
@onready var layers: Node3D = $EraLayers
@onready var ui: CanvasLayer = $UI
@onready var fade: ColorRect = $UI/Fade

var georef: TerrainGeoref
var _screenshot_path := ""
var _screenshot_frame := 240
var _frames := 0
var _era_nodes: Dictionary = {}     # era_id -> EraController
var _spawn := Vector3(508, 0, 513)  # north of the ruin, 2026 prologue start (data/site_layout.json spawn_2026)


func _ready() -> void:
	GameState.world = self
	georef = TerrainGeoref.load_tile(TILE)
	terrain.set_camera(player.camera)
	_configure_sky()
	_apply_orthophoto()
	fade.color.a = 1.0
	await get_tree().process_frame
	if GameState.pending_load and SaveManager.has_save():
		GameState.pending_load = false
		await SaveManager.load_slot()
	if not GameState.current_era:
		# New game: prologue in 2026.
		player.global_position = _spawn
		player.rotation.y = PI   # face south, toward the ruin
		_snap(player, 1.0)
		await GameState.switch_era("era_2026")
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 0.0, FADE_TIME)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--screenshot="):
			_screenshot_path = a.trim_prefix("--screenshot=")
		elif a.begins_with("--frames="):
			_screenshot_frame = int(a.trim_prefix("--frames="))
		elif a.begins_with("--spawn="):
			var parts := a.trim_prefix("--spawn=").split(",")
			player.global_position = Vector3(float(parts[0]), 200.0, float(parts[1]))
			if parts.size() > 2:
				player.rotation.y = deg_to_rad(float(parts[2]))
			_snap(player, 1.0)
		elif a.begins_with("--era="):
			GameState.register_unlocked = true
			GameState.switch_era(a.trim_prefix("--era="))
		elif a.begins_with("--open="):
			GameState.register_unlocked = true
			get_tree().create_timer(2.0).timeout.connect(ui.debug_open.bind(a.trim_prefix("--open=")))


func _process(_delta: float) -> void:
	if sky and sky.tod:
		Farming.tick_clock(sky.tod.current_time)
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
	if era.terrain_texture:
		mat.set_shader_param("ortho_texture", era.terrain_texture)
	mat.set_shader_param("ortho_strength", era.texture_strength)
	mat.set_shader_param("ortho_tint", era.ground_tint)


func _apply_orthophoto() -> void:
	var mat := terrain.material
	mat.set_shader_param("ortho_origin", Vector2.ZERO)
	mat.set_shader_param("ortho_extent", georef.tile_size_m())


func _configure_sky() -> void:
	var tod := sky.tod
	tod.latitude = deg_to_rad(58.1158)
	tod.longitude = deg_to_rad(26.3341)
	tod.utc = 3.0
	tod.year = 2026
	tod.month = 9
	tod.day = 3
	tod.minutes_per_day = 30.0
	tod.game_time_enabled = true


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
