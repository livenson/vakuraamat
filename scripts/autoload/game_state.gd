# Autoload "GameState": the era registry (one present-day layer per pack), the current layer, the
# running world and the new-game / continue orchestration. Economic state lives in Ledger.
extends Node

var eras: Dictionary = {}                 # id -> EraDefinition (one per pack today)
var current_era: String = ""
var world: Node = null                    # the World scene, if running
var pending_load := false                 # main menu asked for "Continue"
var report_replayed := false              # the --report= argument is honoured by the first world only
var menu_open_locations := false          # pause menu asked the main menu to open the Locations panel


## Fresh game state (new game from the menu).
func reset() -> void:
	current_era = ""
	pending_load = false
	Ledger.reset_local(Sites.active)


func _ready() -> void:
	Sites.site_changed.connect(func(_id): reload())
	reload()


## (Re)load the registries from the active site pack.
func reload() -> void:
	eras.clear()
	Sites.load_dir(Sites.data_dir("eras"), eras)
	print("[GameState] site %s: %d layer(s)" % [Sites.active, eras.size()])


func era(id: String) -> EraDefinition:
	return eras.get(id)


func eras_in_order() -> Array:
	var list := eras.values()
	list.sort_custom(func(a, b): return a.order < b.order)
	return list


## Load a layer (the pack's single present-day scene) into the world.
func switch_era(era_id: String) -> void:
	if not eras.has(era_id) or era_id == current_era:
		return
	var from := current_era
	EventBus.era_change_started.emit(from, era_id)
	current_era = era_id
	if world:
		await world.apply_era(era(era_id), true)
	EventBus.era_changed.emit(era_id)
	SaveManager.autosave()


func clock_string() -> String:
	if world and world.has_method("clock_string"):
		return world.clock_string()
	return ""


func to_dict() -> Dictionary:
	var d := {"current_era": current_era}
	if world and world.has_method("to_dict"):
		d["world"] = world.to_dict()
	return d


func from_dict(d: Dictionary) -> void:
	var era_id: String = d.get("current_era", "")
	if world and world.has_method("from_dict"):
		world.from_dict(d.get("world", {}))
	if era_id != "":
		current_era = ""
		await switch_era(era_id)
