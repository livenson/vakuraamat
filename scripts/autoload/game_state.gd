# Registry of eras, consequence points and items, plus the current era, chapter and the
# orchestration of era switching and chapter commits. Autoload "GameState".
# The world scene registers itself here so switches can be applied to it.
extends Node

const ERA_DIR := "res://data/eras/"
const CP_DIR := "res://data/consequence_points/"
const ITEM_DIR := "res://data/items/"

var eras: Dictionary = {}                 # id -> EraDefinition
var consequence_points: Dictionary = {}   # id -> ConsequencePoint
var items: Dictionary = {}                # id -> ItemBase
var _cp_by_flag: Dictionary = {}

var current_era: String = ""
var chapter: int = 0                      # 0 prologue, 1..3 chapters, 4 epilogue
var visited_eras: Dictionary = {}         # era_id -> true
var register_unlocked: bool = false
var world: Node = null                    # the World scene, if running


func _ready() -> void:
	_load_dir(ERA_DIR, eras)
	_load_dir(CP_DIR, consequence_points)
	_load_dir(ITEM_DIR, items)
	for cp in consequence_points.values():
		_cp_by_flag[cp.flag_name] = cp
	print("[GameState] %d eras, %d consequence points, %d items" % [eras.size(), consequence_points.size(), items.size()])


func _load_dir(dir: String, into: Dictionary) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".tres") or f.ends_with(".res"):
			var r: Resource = load(dir + f)
			if r and "id" in r:
				into[r.id] = r


func era(id: String) -> EraDefinition:
	return eras.get(id)


func eras_in_order() -> Array:
	var list := eras.values()
	list.sort_custom(func(a, b): return a.order < b.order)
	return list


func item(id: String) -> ItemBase:
	return items.get(id)


func consequence(id: String) -> ConsequencePoint:
	return consequence_points.get(id)


func consequence_for_flag(flag_name: String) -> ConsequencePoint:
	return _cp_by_flag.get(flag_name)


## The one place a consequence flag is set. Returns false if the point is unknown.
func trigger_consequence(cp_id: String) -> bool:
	var cp := consequence(cp_id)
	if cp == null:
		push_error("unknown consequence point %s" % cp_id)
		return false
	TimelineState.set_flag(cp.flag_name, true)
	EventBus.consequence_triggered.emit(cp_id)
	# Soft nudge to witness (design doc 2.5 step 4).
	var targets := cp.affected_eras.map(func(e): return era(e).year_label if era(e) else e)
	EventBus.notice.emit(tr("NOTICE_REGISTER_NEW_LINE") % ", ".join(targets))
	return true


## Deliver an artifact to its target: consumes the item and triggers its consequence.
func deliver_artifact(item_id: String, target_id: String) -> bool:
	var it := item(item_id)
	if not (it is ArtifactItem) or it.valid_delivery_target != target_id or not Inventory.has(item_id):
		return false
	Inventory.remove(item_id)
	return trigger_consequence(it.linked_consequence_point_id)


func switch_era(era_id: String) -> void:
	if not eras.has(era_id) or era_id == current_era:
		return
	var from := current_era
	EventBus.era_change_started.emit(from, era_id)
	current_era = era_id
	var first_visit: bool = not visited_eras.has(era_id)
	visited_eras[era_id] = true
	if world:
		await world.apply_era(era(era_id), first_visit)
	EventBus.era_changed.emit(era_id)
	_check_chapter_rules()
	SaveManager.autosave()


func unlock_register() -> void:
	if register_unlocked:
		return
	register_unlocked = true
	EventBus.register_opened.emit()
	if chapter == 0:
		end_chapter()   # prologue commits when the book is first opened


## Ends the current chapter: commits pending flags and autosaves (design doc 2.6).
func end_chapter() -> void:
	TimelineState.commit()
	EventBus.chapter_committed.emit(chapter)
	chapter += 1
	EventBus.chapter_changed.emit(chapter)
	SaveManager.autosave()


func _check_chapter_rules() -> void:
	# Chapter 1 ends once all three eras have been visited at least once.
	if chapter == 1 and visited_eras.size() >= eras.size():
		end_chapter()


func clock_string() -> String:
	if world and world.has_method("clock_string"):
		return world.clock_string()
	return ""


func to_dict() -> Dictionary:
	var d := {
		"current_era": current_era, "chapter": chapter, "visited_eras": visited_eras.duplicate(),
		"register_unlocked": register_unlocked,
	}
	if world and world.has_method("to_dict"):
		d["world"] = world.to_dict()
	return d


func from_dict(d: Dictionary) -> void:
	chapter = int(d.get("chapter", 0))
	visited_eras = d.get("visited_eras", {}).duplicate()
	register_unlocked = bool(d.get("register_unlocked", false))
	var era_id: String = d.get("current_era", "")
	if world and world.has_method("from_dict"):
		world.from_dict(d.get("world", {}))
	if era_id != "":
		current_era = ""
		await switch_era(era_id)
