# A landscape feature or object with era-aware examine text. Looking at it shows the
# text; pressing interact marks the location visited (for the journal's maps).
class_name Examinable
extends Interactable

@export var text_key := ""
@export var location_id := ""        # LOC_* id for the journal map markers, optional


func hover_text() -> String:
	return tr(text_key) if text_key != "" else ""


func interact(_player: Node3D) -> void:
	if location_id != "":
		EventBus.location_visited.emit(location_id)
	EventBus.notice.emit(hover_text())
