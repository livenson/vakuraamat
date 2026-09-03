# Base for anything the player can point at and use. Put on a StaticBody3D/Area3D with a
# collision shape on the "interact" layer (2). Subclasses override interact()/prompt().
class_name Interactable
extends Node3D

@export var prompt_key := "UI_PROMPT_EXAMINE"
@export var label_key := ""          # shown above the prompt (e.g. NPC name / location)


func prompt() -> String:
	return tr(prompt_key)


func label() -> String:
	return tr(label_key) if label_key != "" else ""


## Called when the player presses interact while looking at this.
func interact(_player: Node3D) -> void:
	pass


## Hover text shown without pressing anything (examine text). Empty = none.
func hover_text() -> String:
	return ""
