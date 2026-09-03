# A wild animal: wanders, flees the player, can be taken with a chance that falls off
# with distance. Body is a coloured capsule (no rigging); built in code from the species.
class_name Animal
extends Interactable

var species: AnimalDefinition
var era_id := ""
var _state := "WANDER"
var _target := Vector3.ZERO
var _timer := 0.0
var _body: MeshInstance3D
var _alert_until := 0.0

@onready var _terrain: Terrain3D = GameState.world.terrain if GameState.world else null


func setup(def: AnimalDefinition, era: String) -> void:
	species = def
	era_id = era
	label_key = def.display_name_key
	prompt_key = "HUNT_PROMPT"


func _ready() -> void:
	_body = MeshInstance3D.new()
	var m := CapsuleMesh.new()
	m.radius = species.body_size.x
	m.height = species.body_size.z
	_body.mesh = m
	_body.rotation.x = PI / 2
	_body.position.y = species.body_size.y
	var mat := StandardMaterial3D.new()
	mat.albedo_color = species.body_color
	mat.roughness = 0.95
	_body.material_override = mat
	add_child(_body)
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = species.body_size.x * 0.7
	hm.height = species.body_size.x * 1.4
	head.mesh = hm
	head.material_override = mat
	head.position = Vector3(0, species.body_size.y + species.body_size.x * 0.5, -species.body_size.z * 0.55)
	add_child(head)
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = maxf(species.body_size.z, 0.6)
	shape.shape = s
	shape.position.y = species.body_size.y
	body.add_child(shape)
	add_child(body)
	_pick_target()


func _pick_target() -> void:
	var a := randf() * TAU
	_target = global_position + Vector3(cos(a), 0, sin(a)) * randf_range(4.0, 14.0)
	_timer = randf_range(2.0, 6.0)


func _physics_process(delta: float) -> void:
	var player: Node3D = GameState.world.player if GameState.world else null
	if player and species.flee_behavior:
		var d := global_position.distance_to(player.global_position)
		if d < species.flee_distance:
			_state = "FLEE"
			var away := (global_position - player.global_position)
			away.y = 0
			_target = global_position + away.normalized() * 25.0
			_alert_until = 3.0
	_alert_until -= delta
	if _alert_until <= 0.0 and _state == "FLEE":
		_state = "WANDER"
		_pick_target()
	_timer -= delta
	if _state == "WANDER" and _timer <= 0.0:
		_pick_target()
	var speed := species.speed * (2.2 if _state == "FLEE" else 0.6)
	var to := _target - global_position
	to.y = 0
	if to.length() > 0.5:
		var step := to.normalized() * speed * delta
		global_position += step
		look_at(global_position + to.normalized(), Vector3.UP)
	if _terrain:
		var h := _terrain.data.get_height(global_position)
		if not is_nan(h):
			global_position.y = h


func hover_text() -> String:
	return tr("HUNT_HINT") % [tr(species.display_name_key), int(hunt_chance(GameState.world.player) * 100)]


func hunt_chance(player: Node3D) -> float:
	var d := global_position.distance_to(player.global_position)
	var base := clampf(1.0 - d / species.hunt_range, 0.0, 1.0)
	return base * (0.55 if _state == "FLEE" else 1.0)


func interact(player: Node3D) -> void:
	var c := hunt_chance(player)
	if randf() < c:
		Inventory.add(species.yield_item_id)
		Hunting.record(era_id)
		EventBus.notice.emit(tr("HUNT_SUCCESS") % tr(GameState.item(species.yield_item_id).display_name_key))
		queue_free()
	else:
		EventBus.notice.emit(tr("HUNT_MISS") % tr(species.display_name_key))
		_state = "FLEE"
		_alert_until = 5.0
		var away := (global_position - player.global_position)
		away.y = 0
		_target = global_position + away.normalized() * 40.0
