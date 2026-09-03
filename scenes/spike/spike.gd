# Phase 0 technical spike: one real 1 km² Maa-amet tile as walkable Terrain3D
# ground, an orthophoto draped on it, one Blender-authored prop, a first-person
# walker and an FPS counter. No game systems live here.
#
# Verification mode (used by tools/verify_spike.sh):
#   godot --path . -- --screenshot=/abs/path.png [--frames=120]
#   -> saves a frame after the given number of frames (FPS averaged after frame 30) and quits.
extends Node3D

var screenshot_frame := 120

@onready var terrain: Terrain3D = $Terrain3D
@onready var player: CharacterBody3D = $Player
@onready var stone: Node3D = $BoundaryStone
@onready var sky: Sky3D = $Sky3D

@export var tile := "palupera"

var _spawn := Vector3.ZERO
var _screenshot_path := ""
var _frames := 0
var _fps_samples: Array[float] = []


func _ready() -> void:
	terrain.set_camera(player.get_node("Camera3D"))
	_apply_orthophoto()
	_configure_sky()
	# Terrain3D loads its region data in its own _ready (children first), so heights are available now.
	_snap_to_ground(player, 1.0)
	_snap_to_ground(stone, 0.0)
	_spawn = player.global_position
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--screenshot="):
			_screenshot_path = a.trim_prefix("--screenshot=")
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif a.begins_with("--frames="):
			screenshot_frame = int(a.trim_prefix("--frames="))
		elif a == "--no-fog":
			sky.fog_enabled = false
		elif a.begins_with("--spawn="):  # x,z[,yaw_deg] in tile metres, for verification runs
			var parts := a.trim_prefix("--spawn=").split(",")
			player.global_position = Vector3(float(parts[0]), 200.0, float(parts[1]))
			if parts.size() > 2:
				player.rotation.y = deg_to_rad(float(parts[2]))
			_snap_to_ground(player, 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("teleport"):
		var cam: Camera3D = player.camera
		var hit := _terrain_hit(cam.global_position, -cam.global_transform.basis.z)
		if hit.is_finite():
			_teleport_to(hit)
	elif event.is_action_pressed("teleport_home"):
		_teleport_to(_spawn)


func _teleport_to(p: Vector3) -> void:
	player.velocity = Vector3.ZERO
	player.global_position = p + Vector3.UP * 1.0
	if not player.flying:
		_snap_to_ground(player, 1.0)


## Ray-march the terrain heightfield (works anywhere on the tile, unlike the dynamic
## collision shapes, which only exist near the player). Returns Vector3.INF on a miss.
func _terrain_hit(from: Vector3, dir: Vector3, max_dist := 3000.0) -> Vector3:
	var step := 1.0
	var prev := from
	var d := step
	while d < max_dist:
		var p := from + dir * d
		var h := terrain.data.get_height(p)
		if is_nan(h):
			if not is_nan(terrain.data.get_height(prev)):
				return Vector3.INF  # walked off the tile edge
		elif p.y <= h:
			# refine between prev (above) and p (below)
			var lo := prev
			var hi := p
			for i in 8:
				var mid := (lo + hi) * 0.5
				if mid.y <= terrain.data.get_height(mid):
					hi = mid
				else:
					lo = mid
			return Vector3(hi.x, terrain.data.get_height(hi), hi.z)
		prev = p
		d += step
	return Vector3.INF


## Sky3D day/night cycle with the sun computed for the real site (Palupera, EPSG:4326 58.116 N 26.334 E).
func _configure_sky() -> void:
	var tod := sky.tod
	tod.latitude = deg_to_rad(58.1158)
	tod.longitude = deg_to_rad(26.3341)
	tod.utc = 3.0  # Estonian summer time
	tod.year = 2026
	tod.month = 9
	tod.day = 3
	tod.current_time = 10.5  # 10:30, low-ish September sun from the south-east
	tod.minutes_per_day = 30.0  # one full day-night cycle in 30 real minutes
	tod.game_time_enabled = true
	sky.fog_enabled = true


## World-aligned orthophoto drape via the shader override (see assets/terrain/ortho_drape.gdshader).
func _apply_orthophoto() -> void:
	var georef := TerrainGeoref.load_tile(tile)
	var mat := terrain.material
	if not georef.is_valid() or not mat.shader_override_enabled:
		return
	mat.set_shader_param("ortho_texture", load("res://assets/terrain/%s/%s" % [tile, georef.meta.texture]))
	mat.set_shader_param("ortho_origin", Vector2.ZERO)  # tile's north-west corner is world (0, 0)
	mat.set_shader_param("ortho_extent", georef.tile_size_m())
	mat.set_shader_param("ortho_strength", 1.0)


func _snap_to_ground(node: Node3D, lift: float) -> void:
	var h := terrain.data.get_height(node.global_position)
	if is_nan(h):
		push_warning("%s is outside the terrain tile" % node.name)
		return
	node.global_position.y = h + lift


func _process(_delta: float) -> void:
	if _screenshot_path.is_empty():
		return
	_frames += 1
	if _frames > 30:
		_fps_samples.append(Engine.get_frames_per_second())
	if _frames == screenshot_frame:
		var img := get_viewport().get_texture().get_image()
		img.save_png(_screenshot_path)
		var avg := 0.0
		for f in _fps_samples:
			avg += f
		avg /= maxf(1.0, _fps_samples.size())
		print("[spike] screenshot -> %s  avg fps %.0f  player %s  ground %.2f m" % [
			_screenshot_path, avg, player.global_position, terrain.data.get_height(player.global_position)])
		get_tree().quit()
