# Sits under the player's camera: ray-picks Interactables, drives the HUD prompt and
# fires interact() on the "interact" action. Disabled while a UI panel is open.
class_name Interactor
extends RayCast3D

signal target_changed(target: Interactable)

var target: Interactable = null
var blocked := false
var carrying: Node = null   # the Carryable held (E puts it down)


func _ready() -> void:
	enabled = true
	target_position = Vector3(0, 0, -4.5)
	collision_mask = 2
	collide_with_areas = true


func _physics_process(_delta: float) -> void:
	var t: Interactable = null
	if not blocked and is_colliding():
		var c := get_collider()
		while c and not (c is Interactable):
			c = c.get_parent()
		t = c as Interactable
	if t != target:
		target = t
		target_changed.emit(target)


func _unhandled_input(event: InputEvent) -> void:
	if blocked:
		return
	if not event.is_action_pressed("interact"):
		return
	if carrying and is_instance_valid(carrying):
		carrying.drop()
		get_viewport().set_input_as_handled()
		return
	if target == null:
		return
	target.interact(get_parent().get_parent())
	get_viewport().set_input_as_handled()
