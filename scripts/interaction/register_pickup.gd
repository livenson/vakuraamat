# The vakuraamat itself, found in the start era. Taking it ends the prologue and
# unlocks era switching. Hidden once found (flag register_found).
extends Interactable

@export var text_key := "EX_REGISTER"   # hover text; the site's scenes.json "register" node sets it


func _ready() -> void:
	prompt_key = "UI_PROMPT_TAKE"
	label_key = "ITEM_REGISTER"
	if TimelineState.has_flag("register_found"):
		_hide()


func hover_text() -> String:
	return tr(text_key)


func interact(_player: Node3D) -> void:
	TimelineState.set_flag("register_found", true)
	GameState.unlock_register()
	EventBus.notice.emit(tr("NOTICE_REGISTER_FOUND"))
	_hide()


func _hide() -> void:
	visible = false
	for c in find_children("*", "CollisionShape3D", true, false):
		c.set_deferred("disabled", true)
