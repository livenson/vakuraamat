# Autoload "Hunting": species registry and per-era tally. Era-local by design: nothing in
# scripts/hunting references the timeline, consequence or artifact systems.
extends Node

const DIR := "res://data/animals/"

var animals: Dictionary = {}       # id -> AnimalDefinition
var taken: Dictionary = {}         # era_id -> count (flavour + save)


func _ready() -> void:
	var d := DirAccess.open(DIR)
	if d:
		for f in d.get_files():
			f = f.trim_suffix(".remap")
			if f.ends_with(".tres"):
				var a: AnimalDefinition = load(DIR + f)
				animals[a.id] = a


func for_era(era_id: String) -> Array:
	var out := []
	for a in animals.values():
		if era_id in a.eras:
			out.append(a)
	return out


func record(era_id: String) -> void:
	taken[era_id] = int(taken.get(era_id, 0)) + 1
	SaveManager.mark_dirty()


func to_dict() -> Dictionary:
	return {"taken": taken.duplicate()}


func from_dict(d: Dictionary) -> void:
	taken = d.get("taken", {}).duplicate()
