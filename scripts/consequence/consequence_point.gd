# One scripted, deliberately authored butterfly effect. Exactly one flag.
class_name ConsequencePoint
extends Resource

@export var id: String
@export var flag_name: String
@export var trigger_era: String
@export var affected_eras: Array[String] = []
@export var trigger_description_key: String   # journal/codex: what caused it
@export var effect_description_key: String    # ledger line: what changed
@export var journal_icon: Texture2D
