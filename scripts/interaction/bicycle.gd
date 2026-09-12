# A parked bicycle. E mounts it: the walker becomes a rider (faster, momentum, lower camera), the
# bike frame shows under the camera; E again (looking at nothing) dismounts and leaves it here.
# A pug keeps the bike company, trotting a loop around it and stopping once a lap to look at it;
# it is hidden with the bike while the player rides and is back wherever the bike is left.
class_name Bicycle
extends Interactable

const PUG := "res://assets/vendor/polypizza/pug.glb"
const PUG_LOOP := Vector2(1.4, 1.9)   # the loop's half-widths across and along the bike, metres
const PUG_SPEED := 1.0                # metres per second along the loop
const PUG_REST := 2.5                 # seconds the pug stands still once a lap

var _mesh: Node3D
var _pug: Node3D
var _pug_body: Node3D                 # the model inside _pug, which bounces while it trots
var _angle := 0.0                     # where on the loop the pug is, radians
var _rest := 0.0
var _t := 0.0


func _ready() -> void:
	prompt_key = "UI_PROMPT_RIDE"
	label_key = "ITEM_BICYCLE"
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	_mesh = TrafficAgent.build_bike(false, rng, Color.WHITE)
	_mesh.rotation.y = 0.3
	add_child(_mesh)
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 1.2, 2.0)
	shape.shape = box
	shape.position = Vector3(0, 0.6, 0)
	body.add_child(shape)
	add_child(body)
	_pug_body = TrafficAgent.animal(PUG, 0.42)
	if _pug_body != null:
		_pug = Node3D.new()
		_pug.name = "Pug"
		_pug.add_child(_pug_body)
		add_child(_pug)
		_angle = rng.randf() * TAU


func _process(delta: float) -> void:
	if _pug == null or not is_visible_in_tree():
		return
	_t += delta
	var trot := 1.0
	if _rest > 0.0:
		_rest -= delta
		trot = 0.0
	else:
		var before := _angle
		# the same pace on the loop's long and short sides: the step in angle over the local radius
		var r := PUG_LOOP * Vector2(sin(_angle), cos(_angle))
		_angle = fmod(_angle + PUG_SPEED * delta / maxf(r.length(), 0.5), TAU)
		if _angle < before:
			_rest = PUG_REST   # a lap done: stop and look at the bike
	var turn := Basis(Vector3.UP, _mesh.rotation.y)   # the loop follows the bike, not the node
	var at := turn * Vector3(cos(_angle) * PUG_LOOP.x, 0.0, sin(_angle) * PUG_LOOP.y)
	var ahead := turn * Vector3(-sin(_angle) * PUG_LOOP.x, 0.0, cos(_angle) * PUG_LOOP.y)
	var face := -at if _rest > 0.0 else ahead
	var ground := _ground_y(to_global(at))
	_pug.position = Vector3(at.x, ground - global_position.y if not is_nan(ground) else 0.0, at.z)
	_pug.rotation.y = atan2(-face.x, -face.z)   # the model's nose is -Z
	_pug_body.position.y = absf(sin(_t * 9.0)) * 0.03 * trot   # a trot: quick small bounces
	_pug_body.rotation.x = sin(_t * 9.0) * 0.04 * trot


## The terrain under a point, NaN where there is none (a test scene without a world).
func _ground_y(p: Vector3) -> float:
	var terrain: Node = GameState.world.terrain if GameState.world else null
	if terrain == null:
		return NAN
	var h: float = terrain.data.get_height(p)
	return h if not is_nan(h) else NAN


func hover_text() -> String:
	return tr("EX_BICYCLE")


func interact(player: Node3D) -> void:
	if player.has_method("mount"):
		player.mount(self)
