# A door leaf on a hinge: opens away from whoever pushes it, closes by itself after a while.
# The swing and auto-close follow Cogito's rotating door (Philip Drobar, MIT; see THIRD_PARTY.md),
# reduced to what a generated building needs: no locks, keys or animations.
class_name SwingDoor
extends Node3D

signal state_changed(is_open: bool)

@export var open_angle := 95.0        # degrees the leaf swings
@export var speed := 3.5              # radians per second towards the target
@export var auto_close := 5.0         # seconds open before it closes by itself; 0 keeps it open

var is_open := false
var _target := 0.0
var _timer: Timer


## The leaf: `width` x `height`, hinged on its left jamb, in the door frame's own axes (X along the
## wall, Y up, Z outward). Built as a child "Leaf" mesh under this hinge node. A city tile has
## hundreds of doors: they share one unit box (scaled per door) and one low-poly knob, so they
## instance together, and both disappear beyond a street's width, where the wall's own door quad
## is all anyone can see.
const LEAF_RANGE := 90.0
const KNOB_RANGE := 25.0
static var _unit_box: BoxMesh
static var _knob_mesh: SphereMesh
static var _knob_mat: StandardMaterial3D


func setup(width: float, height: float, mat: Material, thickness := 0.06) -> void:
	if _unit_box == null:
		_unit_box = BoxMesh.new()
		_knob_mesh = SphereMesh.new()
		_knob_mesh.radius = 0.035
		_knob_mesh.height = 0.07
		_knob_mesh.radial_segments = 8   # the default 64 x 32 is 4000 triangles for a doorknob
		_knob_mesh.rings = 4
		_knob_mat = StandardMaterial3D.new()
		_knob_mat.albedo_color = Color(0.75, 0.7, 0.45)
		_knob_mat.metallic = 0.8
		_knob_mat.roughness = 0.3
	position = Vector3(-width * 0.5, -height * 0.5, 0.0)   # the hinge at the jamb, on the threshold
	var leaf := MeshInstance3D.new()
	leaf.name = "Leaf"
	leaf.mesh = _unit_box
	leaf.scale = Vector3(width - 0.04, height - 0.03, thickness)
	leaf.material_override = mat
	leaf.position = Vector3(width * 0.5, height * 0.5, 0.0)
	leaf.visibility_range_end = LEAF_RANGE
	add_child(leaf)
	var knob := MeshInstance3D.new()
	knob.mesh = _knob_mesh
	knob.material_override = _knob_mat
	knob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	knob.visibility_range_end = KNOB_RANGE
	knob.position = Vector3(width - 0.12, height * 0.5, thickness * 0.5 + 0.03)
	add_child(knob)


func _ready() -> void:
	set_physics_process(false)   # a shut door does nothing per tick; open() and close() wake it


## Swing open away from `pusher` (a global position); a second call while open closes it.
func toggle(pusher: Vector3) -> void:
	if is_open:
		close()
	else:
		open(pusher)


func open(pusher: Vector3) -> void:
	var local := to_local(pusher)
	var away := -1.0 if local.z > 0.0 else 1.0   # the pusher stands outward (+Z): swing inward
	_target = deg_to_rad(open_angle) * away
	is_open = true
	set_physics_process(true)
	state_changed.emit(true)
	if auto_close > 0.0:
		if _timer == null:
			_timer = Timer.new()
			_timer.one_shot = true
			_timer.timeout.connect(close)
			add_child(_timer)
		_timer.start(auto_close)


func close() -> void:
	_target = 0.0
	is_open = false
	set_physics_process(true)
	state_changed.emit(false)


func _physics_process(delta: float) -> void:
	if absf(rotation.y - _target) > 0.001:
		rotation.y = move_toward(rotation.y, _target, speed * delta)
	else:
		set_physics_process(false)
