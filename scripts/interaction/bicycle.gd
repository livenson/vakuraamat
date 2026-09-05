# A parked bicycle. E mounts it: the walker becomes a rider (faster, momentum, lower camera), the
# bike frame shows under the camera; E again (looking at nothing) dismounts and leaves it here.
class_name Bicycle
extends Interactable

var _mesh: Node3D


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


func hover_text() -> String:
	return tr("EX_BICYCLE")


func interact(player: Node3D) -> void:
	if player.has_method("mount"):
		player.mount(self)
