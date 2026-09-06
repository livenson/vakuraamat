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
	collision_mask = 1 | 2   # interactables, and the walls of real buildings (BuildingInfo)
	collide_with_areas = true


func _physics_process(_delta: float) -> void:
	if target != null and not is_instance_valid(target):
		target = null   # a reloaded layer freed it
		target_changed.emit(null)
	var t: Interactable = null
	if not blocked and is_colliding():
		var c := get_collider()
		var hit: Node = c
		while c and not (c is Interactable):
			c = c.get_parent()
		t = c as Interactable
		if t == null:
			t = _building_info(hit)
	if t != target:
		target = t
		target_changed.emit(target)


## A real building's wall: its BuildingInfo, made on first hover.
static func _building_info(hit: Node) -> Interactable:
	var n: Node = hit
	while n and not (n is FootprintBuilding) and not (n is Node3D and n.has_meta("footprint")):
		n = n.get_parent()
	if n == null:
		return null
	if not (n is FootprintBuilding):
		var fb: Node = n.get_node_or_null("Footprint")
		if fb is FootprintBuilding:
			n = fb
	var info: Node = n.get_node_or_null("Info")
	if info == null:
		info = BuildingInfo.new()
		info.name = "Info"
		n.add_child(info)
		info.setup(n if n is FootprintBuilding else null)
	return info


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
