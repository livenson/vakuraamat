# JSON save files in user://saves/. One autosave slot plus manual slots.
# Serialises TimelineState, GameState (era, chapter, time), Inventory, Journal,
# world pickups and narrative variables. Flat JSON per the Godot docs; numbers
# come back as floats, so consumers cast.
extends Node

const SAVE_DIR := "user://saves/"
const AUTOSAVE := "autosave"

var dirty := false


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))


func mark_dirty() -> void:
	dirty = true


func slot_path(slot: String) -> String:
	return SAVE_DIR + slot + ".json"


func has_save(slot: String = AUTOSAVE) -> bool:
	return FileAccess.file_exists(slot_path(slot))


func save(slot: String = AUTOSAVE) -> bool:
	var data := {
		"version": 1,
		"saved_at": Time.get_datetime_string_from_system(),
		"timeline": TimelineState.to_dict(),
		"game": GameState.to_dict(),
		"inventory": Inventory.to_dict(),
		"journal": Journal.to_dict(),
		"narrative": Narrative.to_dict(),
	}
	var f := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if f == null:
		push_error("cannot write save %s" % slot)
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	dirty = false
	return true


func load_slot(slot: String = AUTOSAVE) -> bool:
	if not has_save(slot):
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(slot_path(slot)))
	if typeof(data) != TYPE_DICTIONARY:
		push_error("corrupt save %s" % slot)
		return false
	TimelineState.from_dict(data.get("timeline", {}))
	Inventory.from_dict(data.get("inventory", {}))
	Journal.from_dict(data.get("journal", {}))
	Narrative.from_dict(data.get("narrative", {}))
	await GameState.from_dict(data.get("game", {}))   # last: switches era, moves the player
	dirty = false
	return true


func autosave() -> void:
	save(AUTOSAVE)
