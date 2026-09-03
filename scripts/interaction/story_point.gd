# A place (not a person) that starts a piece of the era's story: the contested well.
class_name StoryPoint
extends Examinable

@export var knot := ""
@export var speaker_key := ""


func _ready() -> void:
	prompt_key = "UI_PROMPT_USE"


func interact(_player: Node3D) -> void:
	if location_id != "":
		EventBus.location_visited.emit(location_id)
	Narrative.default_speaker = speaker_key
	Narrative.start(knot, location_id)
