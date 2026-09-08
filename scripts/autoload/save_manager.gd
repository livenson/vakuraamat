# Where you were, in user://saves/. There is no game state to keep - every building, plot and
# company is read from the pack's files - so a save is only the place, the spot you stood on, the
# way you faced and the time of day, and "Resume" puts you back there. One autosave slot plus
# manual ones. Flat JSON per the Godot docs; numbers come back as floats, so consumers cast.
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
		"version": 4,
		"site": Sites.active,
		"saved_at": Time.get_datetime_string_from_system(),
		"game": GameState.to_dict(),
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
	if int(data.get("version", 0)) < 4:
		push_warning("save %s is from before the game was removed (version %s); starting fresh" % [slot, data.get("version")])
		return false
	var site := str(data.get("site", Sites.active))
	if site != Sites.active:
		if GameState.world != null:
			# A running world has this site's ground: switching packs under it would put the saved
			# game's layers on another location's terrain. The menu selects the site before loading.
			push_warning("save %s is from site %s, not %s: not loaded" % [slot, site, Sites.active])
			return false
		if Sites.available.has(site):
			Sites.select(site)   # registries reload
	await GameState.from_dict(data.get("game", {}))   # loads the layer, moves the player
	dirty = false
	return true


## Site id recorded in a save, "" if none.
func saved_site(slot: String = AUTOSAVE) -> String:
	if not has_save(slot):
		return ""
	var data = JSON.parse_string(FileAccess.get_file_as_string(slot_path(slot)))
	return str(data.get("site", "")) if typeof(data) == TYPE_DICTIONARY else ""


## What a save holds, without loading it: the place, when it was written, and where you stood.
func summary(slot: String = AUTOSAVE) -> Dictionary:
	if not has_save(slot):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(slot_path(slot)))
	if typeof(data) != TYPE_DICTIONARY or int(data.get("version", 0)) < 4:
		return {}
	var world: Dictionary = data.get("game", {}).get("world", {})
	return {"site": str(data.get("site", "")), "saved_at": str(data.get("saved_at", "")),
		"pos": world.get("player_pos", []), "time_of_day": float(world.get("time_of_day", 10.0))}


func autosave() -> void:
	save(AUTOSAVE)
