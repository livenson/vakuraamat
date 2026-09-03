# A seed store at the farm: hands out one packet of era-appropriate seed per interaction.
# Placeholder supply until trading (Phase 4) sells seed.
class_name SeedBin
extends Interactable

@export var era_id := ""
@export var seed_item_ids: Array[String] = []
var _next := 0


func _ready() -> void:
	prompt_key = "UI_PROMPT_TAKE"
	label_key = "FARM_SEED_BIN"


func hover_text() -> String:
	return tr("FARM_SEED_BIN_TEXT")


func interact(_player: Node3D) -> void:
	if seed_item_ids.is_empty():
		return
	var id: String = seed_item_ids[_next % seed_item_ids.size()]
	_next += 1
	Inventory.add(id)
	EventBus.notice.emit(tr(GameState.item(id).display_name_key))
