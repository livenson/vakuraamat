# Something you can pick up and carry: the body floats towards a point in front of the camera and
# drops when it gets stuck too far behind. After Cogito's carryable component (Philip Drobar, MIT;
# see THIRD_PARTY.md). The rigid body is this node's child "Body"; the interactor holds one at a time.
class_name Carryable
extends Interactable

signal carry_state_changed(carried: bool)

@export var pull := 10.0          # how hard the body is drawn to the carry point
@export var drop_distance := 1.8  # let go when the body lags this far behind
@export var carry_offset := Vector3(0.0, -0.25, -1.5)   # in the camera's frame

var body: RigidBody3D
var carried := false
var _camera: Camera3D
var _holder: Node   # the Interactor carrying it


## Wrap `model` in a rigid body with a box of `size` (metres) on the world and interact layers.
func setup(model: Node3D, size: Vector3, mass := 4.0) -> void:
	prompt_key = "UI_PROMPT_CARRY"
	body = RigidBody3D.new()
	body.name = "Body"
	body.mass = mass
	body.collision_layer = 1 | 2
	body.collision_mask = 1
	body.continuous_cd = true
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = Vector3(0, size.y * 0.5, 0)
	body.add_child(shape)
	body.add_child(model)
	add_child(body)


func prompt() -> String:
	return tr("UI_PROMPT_DROP" if carried else "UI_PROMPT_CARRY")


func interact(player: Node3D) -> void:
	if carried:
		drop()
		return
	var interactor: Node = player.find_child("Interactor", true, false)
	if interactor and "carrying" in interactor:
		if interactor.carrying and is_instance_valid(interactor.carrying):
			interactor.carrying.drop()
		interactor.carrying = self
		_holder = interactor
	_camera = player.find_child("Camera3D", true, false) as Camera3D
	body.lock_rotation = true
	body.gravity_scale = 0.0
	carried = true
	carry_state_changed.emit(true)


func drop() -> void:
	if not carried:
		return
	carried = false
	body.lock_rotation = false
	body.gravity_scale = 1.0
	if _holder and "carrying" in _holder and _holder.carrying == self:
		_holder.carrying = null
	_holder = null
	carry_state_changed.emit(false)


func _physics_process(_delta: float) -> void:
	if not carried or _camera == null or not is_instance_valid(_camera):
		return
	var target: Vector3 = _camera.global_transform * carry_offset
	var to := target - body.global_position
	if to.length() > drop_distance:
		drop()
		return
	body.linear_velocity = to * pull


func _exit_tree() -> void:
	drop()
