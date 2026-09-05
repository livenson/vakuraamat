# A person. No rigging: a capsule with a name label. Talking starts the era story at
# the NPC's knot; artifact delivery happens inside the dialogue (ink give_item).
class_name NPC
extends Interactable

@export var npc_id := ""             # e.g. "npc_leida" (matches ArtifactItem.valid_delivery_target)
@export var knot := ""               # ink knot to start
@export var body_color := Color(0.5, 0.4, 0.3)   # clothes colour
@export var height := 1.7
@export var pose := "stand"                       # stand | arms_folded | holding

const FIGURE_HEIGHT := 1.75

@onready var name_label: Label3D = $NameLabel
@onready var mesh: MeshInstance3D = $Body


func _ready() -> void:
	prompt_key = "UI_PROMPT_TALK"
	name_label.text = tr(label_key)
	mesh.visible = false
	if HumanFigure.available():
		# a MakeHuman figure, deterministic per NPC, dressed for the era of the layer it stands in
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(npc_id + label_key)
		var year := 2026
		var layer := get_parent()
		while layer and not (layer is EraController):
			layer = layer.get_parent()
		if layer:
			year = int(str(layer.era_id).rsplit("_", true, 1)[-1])
		var fig := HumanFigure.make(rng, year)
		fig.pose = pose
		add_child(fig)
		var k := height / HumanFigure.HEIGHT
		fig.scale *= k
	else:
		var fig: Node = load("res://assets/models/figures/figure_%s.glb" % pose).instantiate()
		add_child(fig)
		var k := height / FIGURE_HEIGHT
		fig.scale = Vector3(k, k, k)
		for mi in fig.find_children("*", "MeshInstance3D", true, false):
			for si in mi.mesh.get_surface_count():
				var m: Material = mi.mesh.surface_get_material(si)
				if m and m.resource_name == "Clothes":
					var mat := StandardMaterial3D.new()
					mat.albedo_color = body_color
					mat.roughness = 0.9
					mi.set_surface_override_material(si, mat)
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
