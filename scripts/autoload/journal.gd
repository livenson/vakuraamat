# The ledger: one plain-language entry per consequence, appended when its flag flips.
# Also tracks visited locations for the map tab. Text comes from translation keys on
# the ConsequencePoint so both languages work.
extends Node

var entries: Array[Dictionary] = []      # {cp_id, flag, value, text_key, era_from, era_to, game_time}
var visited: Dictionary = {}             # location_id -> true


func _ready() -> void:
	EventBus.flag_changed.connect(_on_flag_changed)
	EventBus.location_visited.connect(func(id: String): visited[id] = true)


func _on_flag_changed(flag_name: String, value: Variant) -> void:
	var cp: ConsequencePoint = GameState.consequence_for_flag(flag_name)
	if cp == null:
		return
	# A reverted flag removes its entry; a set flag appends one (once).
	if not value:
		entries = entries.filter(func(e): return e.flag != flag_name)
		return
	for e in entries:
		if e.flag == flag_name:
			return
	var entry := {
		"cp_id": cp.id, "flag": flag_name, "value": value,
		"text_key": cp.effect_description_key, "era_from": cp.trigger_era,
		"era_to": ",".join(cp.affected_eras), "game_time": GameState.clock_string(),
	}
	entries.append(entry)
	EventBus.journal_entry_added.emit(entry)


func to_dict() -> Dictionary:
	return {"entries": entries.duplicate(true), "visited": visited.duplicate()}


func from_dict(d: Dictionary) -> void:
	entries.assign(d.get("entries", []))
	visited = d.get("visited", {}).duplicate()
