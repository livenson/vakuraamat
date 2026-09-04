# Autoload "Manors": registries plus what has been built where (saved).
extends Node

signal structure_built(manor_id: String, structure_id: String)

const MANOR_DIR := "res://data/manors/"
const STRUCT_DIR := "res://data/structures/"

var manors: Dictionary = {}       # id -> ManorDefinition
var structures: Dictionary = {}   # id -> StructureDefinition
var built: Dictionary = {}        # manor_id -> Array[String] of structure ids


func _ready() -> void:
	for pair in [[MANOR_DIR, manors], [STRUCT_DIR, structures]]:
		var d := DirAccess.open(pair[0])
		if d:
			for f in d.get_files():
				f = f.trim_suffix(".remap")
				if f.ends_with(".tres"):
					var r: Resource = load(pair[0] + f)
					pair[1][r.id] = r


func built_at(manor_id: String) -> Array:
	return built.get(manor_id, [])


func development_level(manor_id: String) -> int:
	return built_at(manor_id).size()


func is_unlocked(m: ManorDefinition) -> bool:
	return m.unlock_condition_flag == "" or TimelineState.has_flag(m.unlock_condition_flag)


func can_build(m: ManorDefinition, s: StructureDefinition) -> String:
	if s.id in built_at(m.id):
		return "BUILD_ALREADY"
	if s.requires != "" and not (s.requires in built_at(m.id)):
		return "BUILD_REQUIRES"
	if Trading.balance(m.era_id) < s.cost_money:
		return "BUILD_NO_MONEY"
	var bag: Array = Inventory.local_items(m.era_id)
	for item in s.cost_items:
		if bag.count(item) < int(s.cost_items[item]):
			return "BUILD_NO_MATERIALS"
	return ""


func build(m: ManorDefinition, s: StructureDefinition) -> bool:
	if can_build(m, s) != "":
		return false
	for item in s.cost_items:
		for i in int(s.cost_items[item]):
			Inventory.remove(item)
	Trading.add_money(m.era_id, -s.cost_money)
	if not built.has(m.id):
		built[m.id] = []
	built[m.id].append(s.id)
	SaveManager.mark_dirty()
	structure_built.emit(m.id, s.id)
	EventBus.notice.emit(tr("BUILD_DONE") % [tr(s.display_name_key), tr(m.display_name_key)])
	return true


func to_dict() -> Dictionary:
	return {"built": built.duplicate(true)}


func from_dict(d: Dictionary) -> void:
	built = d.get("built", {}).duplicate(true)
