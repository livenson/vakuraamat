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
		"version": 3,
		"site": Sites.active,
		"saved_at": Time.get_datetime_string_from_system(),
		"game": GameState.to_dict(),
		"ledger": Ledger.to_dict(),
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
	if int(data.get("version", 0)) < 3:
		push_warning("save %s is from the historical game (version %s); starting fresh" % [slot, data.get("version")])
		return false
	var site := str(data.get("site", Sites.active))
	if site != Sites.active and Sites.available.has(site):
		Sites.select(site)   # registries reload; the menu normally does this before the world loads
	Ledger.from_dict(data.get("ledger", {}))
	await GameState.from_dict(data.get("game", {}))   # last: loads the layer, moves the player
	dirty = false
	return true


## Site id recorded in a save, "" if none.
func saved_site(slot: String = AUTOSAVE) -> String:
	if not has_save(slot):
		return ""
	var data = JSON.parse_string(FileAccess.get_file_as_string(slot_path(slot)))
	return str(data.get("site", "")) if typeof(data) == TYPE_DICTIONARY else ""


func autosave() -> void:
	save(AUTOSAVE)
