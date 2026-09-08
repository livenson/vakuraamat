# PlaceSearch matches the way a person typing an address expects: the register's two spellings of a
# street answer each other, Estonian letters fold, and what is found is a plot, a building, a
# company or a street of the active pack (read straight from the pack files, no world running).
#   godot --headless --path . res://tools/godot/search_test.tscn
extends Node

var _failed := false


func _check(cond: bool, msg: String) -> void:
	if not cond and not _failed:
		_failed = true
		print("[search] FAILED: ", msg)
		get_tree().quit(1)


func _ready() -> void:
	Sites.select("kvissentali", false)
	GameState.reset()
	await get_tree().process_frame

	# the register writes a street both ways in one pack: either spelling has to find either
	_check(PlaceSearch.score("Aeru tänav 1", "tänav 1") > 0, "'tänav 1' does not match 'Aeru tänav 1'")
	_check(PlaceSearch.score("Aeru tn 1", "tänav 1") > 0, "'tänav 1' does not match 'Aeru tn 1'")
	_check(PlaceSearch.score("Aeru tänav 1", "tn 1") > 0, "'tn 1' does not match 'Aeru tänav 1'")
	_check(PlaceSearch.score("Kesk maantee 2", "mnt 2") > 0, "'mnt 2' does not match 'Kesk maantee 2'")
	# Estonian letters fold, so a keyboard without them still finds the place
	_check(PlaceSearch.score("Jõe tn 5", "joe") > 0, "'joe' does not match 'Jõe tn 5'")
	_check(PlaceSearch.score("Aruküla tee 30", "arukula") > 0, "'arukula' does not match 'Aruküla tee 30'")
	# and it stays a search, not a wildcard
	_check(PlaceSearch.score("Aeru tn 1", "Hauskari") == 0, "'Hauskari' matched 'Aeru tn 1'")
	# a whole address scores above a prefix, a prefix above a substring
	_check(PlaceSearch.score("Aeru tn 1", "Aeru tn 1") > PlaceSearch.score("Aeru tn 1", "Aeru"), "exact does not beat prefix")
	_check(PlaceSearch.score("Aeru tn 1", "Aeru") > PlaceSearch.score("Aeru tn 1", "ru tn"), "prefix does not beat substring")

	var near := Vector2(512, 512)
	_check(PlaceSearch.find("x", near).is_empty(), "a one-letter query returned results")
	var hits := PlaceSearch.find("Aeru", near)
	_check(hits.size() > 0, "'Aeru' found nothing in Kvissentali")
	var kinds := {}
	for h in hits:
		kinds[h.kind] = true
		_check(str(h.label) != "", "a result with no label")
		_check(h.pos is Vector2, "a result with no position")
	_check(kinds.has("plot"), "'Aeru' found no plot (kinds: %s)" % str(kinds.keys()))
	_check(kinds.has("street"), "'Aeru' found no street (kinds: %s)" % str(kinds.keys()))
	# the best answer for a full address is that plot, not something that merely contains it
	var one := PlaceSearch.find("Aeru tn 3", near)
	_check(not one.is_empty() and str(one[0].kind) == "plot" and "Aeru tn 3" in str(one[0].label),
			"'Aeru tn 3' put %s first" % (str(one[0].label) if not one.is_empty() else "nothing"))
	# a company registered in the town is findable by name, and points at its plot
	var acme := PlaceSearch.find("Cable In", near)
	_check(acme.any(func(h): return str(h.kind) == "company"), "no company found for 'Cable In'")

	if not _failed:
		print("[search] PASSED: %d results for 'Aeru' (%s), street spellings and diacritics fold"
				% [hits.size(), ", ".join(kinds.keys())])
		get_tree().quit(0)
