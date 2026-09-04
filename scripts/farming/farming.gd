# Autoload "Farming": crop registry, the game clock in hours, and per-plot state so plots
# persist across era switches and saves. Isolated by design: nothing in scripts/farming
# references the timeline, consequence or artifact systems.
extends Node

const CROP_DIR := "res://data/crops/"

var crops: Dictionary = {}          # id -> CropDefinition
var plots: Dictionary = {}          # plot_key -> {crop, planted_at}
var game_hours: float = 0.0         # accumulated from the world clock
var _last_time := -1.0


func _ready() -> void:
	var d := DirAccess.open(CROP_DIR)
	if d:
		for f in d.get_files():
			f = f.trim_suffix(".remap")
			if f.ends_with(".tres"):
				var c: CropDefinition = load(CROP_DIR + f)
				crops[c.id] = c


## Called by the world every frame with Sky3D's current_time (0..24) to keep a running clock.
func tick_clock(current_time: float) -> void:
	if _last_time < 0.0:
		_last_time = current_time
		return
	var dt := current_time - _last_time
	if dt < -12.0:
		dt += 24.0        # wrapped past midnight
	if dt > 0.0 and dt < 12.0:
		game_hours += dt
	_last_time = current_time


func crops_for_era(era_id: String) -> Array:
	var out := []
	for c in crops.values():
		if era_id in c.eras:
			out.append(c)
	return out


func crop_for_seed(seed_item_id: String) -> CropDefinition:
	for c in crops.values():
		if c.seed_item_id == seed_item_id:
			return c
	return null


func plot_state(key: String) -> Dictionary:
	return plots.get(key, {})


func plant(key: String, crop_id: String) -> void:
	plots[key] = {"crop": crop_id, "planted_at": game_hours}
	SaveManager.mark_dirty()


func clear(key: String) -> void:
	plots.erase(key)
	SaveManager.mark_dirty()


func progress(key: String) -> float:
	var st := plot_state(key)
	if st.is_empty():
		return 0.0
	var crop: CropDefinition = crops.get(st.crop)
	if crop == null:
		return 0.0
	return clampf((game_hours - float(st.planted_at)) / crop.growth_time_hours, 0.0, 1.0)


func to_dict() -> Dictionary:
	return {"plots": plots.duplicate(true), "game_hours": game_hours}


func from_dict(d: Dictionary) -> void:
	plots = d.get("plots", {}).duplicate(true)
	game_hours = float(d.get("game_hours", 0.0))
