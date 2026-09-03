# Keeps a small population of animals alive around the player, placed on land-cover
# classes each species prefers (read from the Terrain3D control map). Put one under an
# era layer; it only runs while that layer is active.
class_name HuntingSpawner
extends Node3D

@export var era_id := ""
@export var max_animals := 8
@export var spawn_radius := 120.0
@export var despawn_radius := 220.0
@export var check_interval := 2.0

var _timer := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = hash(era_id)


func _physics_process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0 or GameState.world == null or GameState.current_era != era_id:
		return
	_timer = check_interval
	var player: Node3D = GameState.world.player
	var alive := 0
	for a in get_children():
		if a is Animal:
			if a.global_position.distance_to(player.global_position) > despawn_radius:
				a.queue_free()
			else:
				alive += 1
	if alive < max_animals:
		_try_spawn(player.global_position)


func _try_spawn(center: Vector3) -> void:
	var species := Hunting.for_era(era_id)
	if species.is_empty():
		return
	var terrain: Terrain3D = GameState.world.terrain
	var def: AnimalDefinition = species[_rng.randi() % species.size()]
	for attempt in 12:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(spawn_radius * 0.4, spawn_radius)
		var p := center + Vector3(cos(a) * r, 0, sin(a) * r)
		var h := terrain.data.get_height(p)
		if is_nan(h):
			continue
		var ctrl: int = terrain.data.get_control(p)
		var cls := Terrain3DUtil.get_base(ctrl)
		if not (cls in def.spawn_classes):
			continue
		for i in def.group_size:
			var an := Animal.new()
			an.setup(def, era_id)
			add_child(an)
			an.global_position = Vector3(p.x + _rng.randf_range(-3, 3), h, p.z + _rng.randf_range(-3, 3))
		return
