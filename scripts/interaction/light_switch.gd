# A switch on a lamp: E turns the lights it drives off and on, and the fixture's glow with them.
# After Cogito's switch (Philip Drobar, MIT; see THIRD_PARTY.md): nodes shown or hidden by state.
class_name LightSwitch
extends Interactable

signal switched(is_on: bool)

var is_on := true
var lights: Array[Node3D] = []            # hidden while off
var glow_mats: Array[StandardMaterial3D] = []   # emission off while off
var _glow: Array[float] = []


## A reachable fixture: a small collision sphere on the interact layer around `radius`.
func setup(radius := 0.3) -> void:
	label_key = "UI_LAMP"
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = radius
	shape.shape = s
	body.add_child(shape)
	add_child(body)
	for m in glow_mats:
		_glow.append(m.emission_energy_multiplier)


func prompt() -> String:
	return tr("UI_PROMPT_SWITCH_OFF" if is_on else "UI_PROMPT_SWITCH_ON")


func interact(_player: Node3D) -> void:
	set_on(not is_on)


func set_on(on: bool) -> void:
	is_on = on
	for l in lights:
		if is_instance_valid(l):
			l.visible = on
	for i in glow_mats.size():
		glow_mats[i].emission_energy_multiplier = (_glow[i] if i < _glow.size() else 1.0) if on else 0.0
	switched.emit(on)
