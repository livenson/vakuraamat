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
	if site != Sites.active:
		if GameState.world != null:
			# A running world has this site's ground: switching packs under it would put the saved
			# game's layers on another location's terrain. The menu selects the site before loading.
			push_warning("save %s is from site %s, not %s: not loaded" % [slot, site, Sites.active])
			return false
		if Sites.available.has(site):
			Sites.select(site)   # registries reload
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


## What a save holds, without loading it: site, when, the month, the cash (offline books) and the town.
func summary(slot: String = AUTOSAVE) -> Dictionary:
	if not has_save(slot):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(slot_path(slot)))
	if typeof(data) != TYPE_DICTIONARY or int(data.get("version", 0)) < 3:
		return {}
	var ledger: Dictionary = data.get("ledger", {})
	var local: Dictionary = ledger.get("local", {})
	var players: Dictionary = local.get("players", {})
	var me: Dictionary = players.get(str(int(local.get("me_id", 1))), {})
	return {"site": str(data.get("site", "")), "saved_at": str(data.get("saved_at", "")), "month": int(local.get("month", 0)),
		"cash": int(me.get("cash", 0)) if not me.is_empty() else -1, "town": str(ledger.get("town", "")), "backend": str(ledger.get("backend", "local")),
		"owned": local.get("parcels", {}).keys()}


func autosave() -> void:
	save(AUTOSAVE)
