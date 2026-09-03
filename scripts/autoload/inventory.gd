# Two-tier inventory (design doc 2.3). Artifacts travel between eras; era-local items
# live in a per-era bucket and are "left behind" when the player switches era.
extends Node

var artifacts: Array[String] = []              # ArtifactItem ids
var local: Dictionary = {}                      # era_id -> Array[String]


func add(item_id: String) -> void:
	var item := GameState.item(item_id)
	if item == null:
		push_error("unknown item %s" % item_id)
		return
	if item is ArtifactItem:
		if not artifacts.has(item_id):
			artifacts.append(item_id)
		EventBus.item_added.emit(item_id, "")
	else:
		var era: String = GameState.current_era
		if not local.has(era):
			local[era] = []
		local[era].append(item_id)
		EventBus.item_added.emit(item_id, era)
	SaveManager.mark_dirty()


func has(item_id: String) -> bool:
	if artifacts.has(item_id):
		return true
	return local.get(GameState.current_era, []).has(item_id)


func remove(item_id: String) -> bool:
	if artifacts.has(item_id):
		artifacts.erase(item_id)
		EventBus.item_removed.emit(item_id, "")
		SaveManager.mark_dirty()
		return true
	var era: String = GameState.current_era
	if local.get(era, []).has(item_id):
		local[era].erase(item_id)
		EventBus.item_removed.emit(item_id, era)
		SaveManager.mark_dirty()
		return true
	return false


func local_items(era_id: String) -> Array:
	return local.get(era_id, [])


func to_dict() -> Dictionary:
	return {"artifacts": artifacts.duplicate(), "local": local.duplicate(true)}


func from_dict(d: Dictionary) -> void:
	artifacts.assign(d.get("artifacts", []))
	local = d.get("local", {}).duplicate(true)
