# Sits under the player's camera: ray-picks Interactables, drives the HUD prompt and
# fires interact() on the "interact" action. Disabled while a UI panel is open.
class_name Interactor
extends RayCast3D

signal target_changed(target: Interactable)

const REACH_WALK := 4.5    # an arm and a step: doors, props, the wall beside you
const REACH_FLY := 120.0   # a survey from the air: any wall or roof under the crosshair

var target: Interactable = null
var blocked := false
var carrying: Node = null   # the Carryable held (E puts it down)
var _lit: FootprintBuilding = null   # the building outlined for the current target


func _ready() -> void:
	enabled = true
	target_position = Vector3(0, 0, -REACH_WALK)
	collision_mask = 1 | 2   # interactables, and the walls of real buildings (BuildingInfo)
	collide_with_areas = true


func _physics_process(_delta: float) -> void:
	if target != null and not is_instance_valid(target):
		target = null   # a reloaded layer freed it
		target_changed.emit(null)
	var player: Node = get_parent().get_parent() if get_parent() else null
	var flying: bool = player != null and bool(player.get("flying"))
	target_position.z = -(REACH_FLY if flying else REACH_WALK)
	var t: Interactable = null
	if not blocked and is_colliding():
		var c := get_collider()
		var hit: Node = c
		while c and not (c is Interactable):
			c = c.get_parent()
		t = c as Interactable
		if t == null:
			t = _building_info(hit)
		elif flying and not (t is BuildingInfo) and _building_of(t) != null and get_collision_point().distance_to(global_position) > REACH_WALK:
			t = _building_info(hit)   # from the air a door or a sign is the building, not a thing to open
	if t != target:
		target = t
		target_changed.emit(target)
		_outline(_building_of(t))


## The real building an interactable belongs to (its info, its door, a prop by the door), or null.
static func _building_of(t: Node) -> FootprintBuilding:
	if t == null:
		return null
	if t is BuildingInfo:
		return t.building
	var n: Node = t
	while n and not (n is FootprintBuilding):
		n = n.get_parent()
	return n as FootprintBuilding


func _outline(b: FootprintBuilding) -> void:
	if b == _lit:
		return
	if _lit and is_instance_valid(_lit):
		_lit.set_highlight(false)
	_lit = b
	if b:
		b.set_highlight(true)


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
