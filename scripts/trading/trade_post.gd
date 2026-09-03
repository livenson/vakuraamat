# A place to buy and sell this era's goods for this era's money. Opens the trade panel.
class_name TradePost
extends Interactable

@export var era_id := ""
@export var post_name_key := ""
@export var intro_key := ""


func _ready() -> void:
	prompt_key = "TRADE_PROMPT"
	label_key = post_name_key


func hover_text() -> String:
	return tr(intro_key) if intro_key != "" else ""


func interact(_player: Node3D) -> void:
	if GameState.world and GameState.world.ui.has_method("open_trade"):
		GameState.world.ui.open_trade(self)
