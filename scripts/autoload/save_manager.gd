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
		"version": 2,
		"site": Sites.active,
		"saved_at": Time.get_datetime_string_from_system(),
		"timeline": TimelineState.to_dict(),
		"game": GameState.to_dict(),
		"inventory": Inventory.to_dict(),
		"journal": Journal.to_dict(),
		"narrative": Narrative.to_dict(),
		"farming": Farming.to_dict(),
		"hunting": Hunting.to_dict(),
		"trading": Trading.to_dict(),
		"manors": Manors.to_dict(),
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
	var site := str(data.get("site", Sites.active))
	if site != Sites.active and Sites.available.has(site):
		Sites.select(site)   # registries reload; the menu normally does this before the world loads
	TimelineState.from_dict(data.get("timeline", {}))
	Inventory.from_dict(data.get("inventory", {}))
	Journal.from_dict(data.get("journal", {}))
	Narrative.from_dict(data.get("narrative", {}))
	Farming.from_dict(data.get("farming", {}))
	Hunting.from_dict(data.get("hunting", {}))
	Trading.from_dict(data.get("trading", {}))
	Manors.from_dict(data.get("manors", {}))
	await GameState.from_dict(data.get("game", {}))   # last: switches era, moves the player
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
