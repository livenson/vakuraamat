# A person. No rigging: a capsule with a name label. Talking starts the era story at
# the NPC's knot; artifact delivery happens inside the dialogue (ink give_item).
class_name NPC
extends Interactable

@export var npc_id := ""             # e.g. "npc_leida" (matches ArtifactItem.valid_delivery_target)
@export var knot := ""               # ink knot to start
@export var body_color := Color(0.5, 0.4, 0.3)
@export var height := 1.7

@onready var name_label: Label3D = $NameLabel
@onready var mesh: MeshInstance3D = $Body


func _ready() -> void:
	prompt_key = "UI_PROMPT_TALK"
	name_label.text = tr(label_key)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = body_color
	mat.roughness = 0.9
	mesh.material_override = mat
	mesh.scale = Vector3(1, height / 1.8, 1)
	mesh.position.y = height / 2.0
	name_label.position.y = height + 0.35


func interact(_player: Node3D) -> void:
	if knot == "":
		return
	Narrative.default_speaker = label_key
	Narrative.start(knot, npc_id)


## Face the player while talking.
func look_at_player(p: Node3D) -> void:
	var target := p.global_position
	target.y = global_position.y
	if target.distance_to(global_position) > 0.1:
		look_at(target, Vector3.UP)
		rotate_y(PI)
