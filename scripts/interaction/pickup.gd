# An item lying in the world. Taking it adds it to the inventory and hides the node;
# the "taken" state is a plain TimelineState flag so it persists and saves.
class_name Pickup
extends Interactable

@export var item_id := ""
@export var era_id := ""             # era this pickup exists in (for the flag name)
@export var examine_key := ""


func _ready() -> void:
	prompt_key = "UI_PROMPT_TAKE"
	var item := GameState.item(item_id)
	if item:
		label_key = item.display_name_key
	if TimelineState.has_flag(taken_flag()):
		visible = false
		set_process(false)
		_disable_collision()


func taken_flag() -> String:
	return "picked_%s_%s" % [item_id, era_id]


func hover_text() -> String:
	return tr(examine_key) if examine_key != "" else ""


func interact(_player: Node3D) -> void:
	if not visible:
		return
	Inventory.add(item_id)
	TimelineState.set_flag(taken_flag(), true)
	var item := GameState.item(item_id)
	if item is ArtifactItem:
		EventBus.notice.emit(tr("NOTICE_ARTIFACT_TAKEN") % tr(item.display_name_key))
	else:
		EventBus.notice.emit(tr(item.display_name_key))
	visible = false
	_disable_collision()


func _disable_collision() -> void:
	for c in find_children("*", "CollisionShape3D", true, false):
		c.set_deferred("disabled", true)
