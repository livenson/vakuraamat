# Minimal first-person walker for the Phase 0 terrain spike.
# WASD / arrows to move, Shift to sprint, Ctrl to dash, Space to jump, Esc to release the mouse.
# F toggles fly mode (survey tool): no gravity or collision, moves where the camera looks,
# Shift and Ctrl still scale the speed.
class_name FirstPersonController
extends CharacterBody3D

enum Gait { WALK, SPRINT, DASH }

@export var walk_speed := 4.0
@export var sprint_speed := 9.0
@export var dash_speed := 20.0
@export var fly_speed := 40.0
@export var jump_velocity := 4.5
@export var mouse_sensitivity := 0.0025

@onready var camera: Camera3D = $Camera3D

var flying := false
var input_enabled := true      # false while a UI panel or dialogue is open
var riding: Node3D = null      # the parked Bicycle we sit on, or null
var _pitch := 0.0
var _bike_view: Node3D = null
var _ride_speed := 0.0


func pitch() -> float:
	return _pitch


## Place the walker: position, yaw (radians) and camera pitch (radians). Used by report replay.
func set_pose(pos: Vector3, yaw: float, pitch_rad: float) -> void:
	global_position = pos
	rotation.y = yaw
	_pitch = clampf(pitch_rad, -PI / 2 + 0.05, PI / 2 - 0.05)
	camera.rotation.x = _pitch
	velocity = Vector3.ZERO


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, -PI / 2 + 0.05, PI / 2 - 0.05)
		camera.rotation.x = _pitch
	elif event.is_action_pressed("toggle_mouse"):
		Input.mouse_mode = (Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
				else Input.MOUSE_MODE_CAPTURED)
	elif event.is_action_pressed("toggle_fly"):
		flying = not flying
		velocity = Vector3.ZERO
		EventBus.notice.emit(tr("NOTICE_FLY_ON") if flying else tr("NOTICE_FLY_OFF"))
	elif riding and event.is_action_pressed("interact"):
		dismount()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("teleport"):
		_teleport_to_view()
	elif event.is_action_pressed("teleport_home"):
		var world: Node = GameState.world
		if world and "_spawn" in world:
			set_pose(world._spawn + Vector3(0, 200, 0), rotation.y, _pitch)
			world._snap(self, 1.0)
			flying = false
			EventBus.notice.emit(tr("NOTICE_HOME"))


## T: march the view ray against the heightfield (up to 1500 m) and stand there.
func _teleport_to_view() -> void:
	var world: Node = GameState.world
	if world == null:
		return
	var terrain: Terrain3D = world.terrain
	var origin := camera.global_position
	var dir := -camera.global_transform.basis.z
	var p := origin
	for i in 1500:
		p += dir
		var h := terrain.data.get_height(p)
		if is_nan(h):
			return
		if p.y <= h:
			set_pose(Vector3(p.x, h + 1.0, p.z), rotation.y, _pitch)
			EventBus.notice.emit(tr("NOTICE_TELEPORT") % [int(p.x), int(p.z)])
			return


## Sit on a parked bicycle: it disappears from the ground and its frame shows under the camera.
func mount(bike: Node3D) -> void:
	if riding:
		return
	riding = bike
	bike.visible = false
	for c in bike.find_children("*", "CollisionShape3D", true, false):
		c.set_deferred("disabled", true)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(bike.name)
	_bike_view = TrafficAgent.build_bike(false, rng, Color.WHITE)
	_bike_view.position = Vector3(0, -1.55, -0.35)
	add_child(_bike_view)
	camera.position.y -= 0.25
	flying = false
	_ride_speed = 0.0
	EventBus.notice.emit(tr("NOTICE_BIKE_ON"))


## Step off: the bicycle stands where we are.
func dismount() -> void:
	if riding == null:
		return
	riding.global_position = global_position + global_transform.basis * Vector3(0.8, 0, -0.6)
	riding.rotation.y = rotation.y
	riding.visible = true
	for c in riding.find_children("*", "CollisionShape3D", true, false):
		c.set_deferred("disabled", false)
	riding = null
	if _bike_view:
		_bike_view.queue_free()
		_bike_view = null
	camera.position.y += 0.25
	EventBus.notice.emit(tr("NOTICE_BIKE_OFF"))


func gait() -> Gait:
	if Input.is_action_pressed("dash"):
		return Gait.DASH
	if Input.is_action_pressed("sprint"):
		return Gait.SPRINT
	return Gait.WALK


func current_speed() -> float:
	if flying:
		return fly_speed * {Gait.WALK: 1.0, Gait.SPRINT: 2.5, Gait.DASH: 6.0}[gait()]
	if riding:
		return {Gait.WALK: 6.5, Gait.SPRINT: 10.0, Gait.DASH: 14.0}[gait()]
	return {Gait.WALK: walk_speed, Gait.SPRINT: sprint_speed, Gait.DASH: dash_speed}[gait()]


func mode_label() -> String:
	if flying:
		return "FLY %.0f m/s" % current_speed()
	if riding:
		return "BIKE %.0f m/s" % _ride_speed
	return {Gait.WALK: "walk", Gait.SPRINT: "sprint", Gait.DASH: "dash"}[gait()]


func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if input_enabled else Vector2.ZERO
	if flying:
		# Move along the camera's look direction so pitch gives free vertical travel.
		var dir := (camera.global_transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
		global_position += dir * current_speed() * delta
		return

	if riding:
		# a bicycle keeps rolling: the input steers the target speed, momentum does the rest; no jumping
		var target := (transform.basis * Vector3(input.x * 0.4, 0.0, input.y)).normalized() * current_speed() if input.length() > 0.1 else Vector3.ZERO
		var horizontal := Vector3(velocity.x, 0, velocity.z).lerp(target, minf(1.0, delta * (2.0 if input.y < 0 else 1.2)))
		_ride_speed = horizontal.length()
		velocity.x = horizontal.x
		velocity.z = horizontal.z
		if not is_on_floor():
			velocity.y -= 9.8 * delta
		else:
			velocity.y = 0.0
		move_and_slide()
		return

	if not is_on_floor():
		velocity += get_gravity() * delta
	elif input_enabled and Input.is_action_just_pressed("jump"):   # not while typing a report
		velocity.y = jump_velocity

	var dir := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	var speed := current_speed()
	if dir:
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)
	move_and_slide()
