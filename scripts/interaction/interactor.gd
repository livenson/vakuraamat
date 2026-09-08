# Sits under the player's camera: picks what the crosshair is on, drives the HUD prompt and
# fires interact() on the "interact" action. Disabled while a UI panel is open.
#
# On foot it is a short ray: doors, props, the wall beside you. From the air it is a survey
# instrument, and a ray is the wrong tool - a building three hundred metres off may not have its
# collider yet (the mesh and its trimesh are built by a worker thread and applied a few per frame,
# behind the layer's staggered fill), and a needle-thin ray asks for an aim nobody can hold at that
# range. So while flying the ray only answers for what is within arm's reach, and everything beyond
# is picked geometrically: the nearest building the crosshair falls inside.
class_name Interactor
extends RayCast3D

signal target_changed(target: Interactable)

const REACH_WALK := 4.5    # an arm and a step: doors, props, the wall beside you
const REACH_FLY := 600.0   # a survey from the air: the town below, well short of the camera's 4 km
const CONE_DEG := 2.0      # the floor: a building smaller than this on screen is still pickable
const STICKY_S := 0.25     # keep the last pick this long when the aim slips off it
const SURVEY_REFRESH_S := 0.5   # how often the flown-over buildings are re-collected

var target: Interactable = null
var blocked := false
var carrying: Node = null   # the Carryable held (E puts it down)
var _lit: FootprintBuilding = null   # the building outlined for the current target
var _survey: Array = []             # [FootprintBuilding, centre, radius] of every building standing
var _survey_age := 0.0
var _slipped := 0.0                 # seconds since the pick last found something


func _ready() -> void:
	enabled = true
	target_position = Vector3(0, 0, -REACH_WALK)
	collision_mask = 1 | 2   # interactables, and the walls of real buildings (BuildingInfo)
	collide_with_areas = true


func _physics_process(delta: float) -> void:
	if target != null and not is_instance_valid(target):
		target = null   # a reloaded layer freed it
		target_changed.emit(null)
	var player: Node = get_parent().get_parent() if get_parent() else null
	var flying: bool = player != null and bool(player.get("flying"))
	var t: Interactable = _pick(flying)
	# a moment's wobble at three hundred metres should not drop the building you are reading
	if t == null and target != null and is_instance_valid(target):
		_slipped += delta
		if _slipped < STICKY_S:
			return
	else:
		_slipped = 0.0
	if t != target:
		target = t
		target_changed.emit(target)
		_outline(_building_of(t))


## What the crosshair is on: the ray first, and from the air the cone pick behind it.
func _pick(flying: bool) -> Interactable:
	if blocked:
		return null
	# on foot the ray is the whole story; flying it is only asked about what is within reach, so a
	# door handle or a bus-stop board cannot stand in for the building it is attached to
	target_position.z = -REACH_WALK
	force_raycast_update()
	if is_colliding():
		var hit: Node = get_collider()
		var c: Node = hit
		while c and not (c is Interactable):
			c = c.get_parent()
		var t := c as Interactable
		if t == null:
			t = _building_info(hit)
		if t != null:
			return t
	if not flying:
		return null
	return _survey_pick()


## The building the crosshair is on. Geometric, not physical: it answers for buildings whose
## collider has not been built yet, which at survey range is most of them.
##
## A building is a candidate when the crosshair falls inside it - the angle from the middle of the
## view to its centre is within the angle the building itself subtends - with a small floor so a
## shed a quarter mile off is not impossible to hit. Of the candidates the nearest wins, which is
## what "the one I am looking at" means when a hall stands behind a house.
func _survey_pick() -> Interactable:
	_refresh_survey()
	var cam: Node3D = get_parent()
	if cam == null:
		return null
	var eye := cam.global_position
	var look := -cam.global_transform.basis.z
	var floor_rad := deg_to_rad(CONE_DEG)
	var best: FootprintBuilding = null
	var best_far := INF
	for entry in _survey:
		# the validity check has to come before the typed assignment, not after it: assigning a freed
		# instance to a typed variable is itself the error, and a tile unloading frees its buildings
		# while this list still holds them
		if not is_instance_valid(entry[0]):
			_survey_age = 0.0   # something went away: rebuild on the next tick rather than limp on
			continue
		var b: FootprintBuilding = entry[0]
		var to: Vector3 = entry[1] - eye
		var far := to.length()
		if far > REACH_FLY or far < 0.001 or far >= best_far:
			continue
		var off := acos(clampf(look.dot(to / far), -1.0, 1.0))
		if off <= maxf(float(entry[2]) / far, floor_rad):
			best = b
			best_far = far
	return _building_info(best) if best else null


## Every real building standing right now - the origin layer and each streamed tile - as the centre
## of its footprint at half its height, and the radius that centre needs to cover the whole thing.
## Rebuilt a couple of times a second while flying, which is what it costs to notice a tile that
## has just arrived.
func _refresh_survey() -> void:
	_survey_age -= get_physics_process_delta_time()
	if _survey_age > 0.0 and not _survey.is_empty():
		return
	_survey_age = SURVEY_REFRESH_S
	_survey = []
	var world: Node = GameState.world
	if world == null or not world.has_method("_building_scopes"):
		return
	for layer in world._building_scopes():
		for b in layer.find_children("*", "FootprintBuilding", true, false):
			var m := _measure(b)
			_survey.append([b, m[0], m[1]])


## The centre of a building's footprint at half its height, and the distance from there to its
## furthest corner: a sphere around the building, near enough for aiming at one.
static func _measure(b: FootprintBuilding) -> Array:
	var mid := Vector2.ZERO
	for p in b.polygon:
		mid += p
	if b.polygon.size() > 0:
		mid /= float(b.polygon.size())
	var half := b.height * 0.5
	var radius := half
	for p in b.polygon:
		radius = maxf(radius, (p - mid).length())
	return [b.to_global(Vector3(mid.x, half, mid.y)), radius]


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
