# Every script in the project must compile (with the autoloads present, as in the game):
#   godot --headless --path . res://tools/godot/parse_test.tscn
# A parse error in a script no other test instances (the main menu, once) reaches players as a grey
# screen. Loads each .gd under res://scripts and res://tools/godot; Godot logs the failing script.
extends Node


func _ready() -> void:
	var bad: Array[String] = []
	var n := 0
	for root in ["res://scripts", "res://tools/godot"]:
		for p in _scripts(root):
			n += 1
			var s = ResourceLoader.load(p, "GDScript", ResourceLoader.CACHE_MODE_REUSE)
			if s == null or not (s is GDScript) or not s.can_instantiate():
				bad.append(p)
	if bad.is_empty():
		print("[parse] PASSED: %d scripts compile" % n)
	else:
		print("[parse] FAILED: %s" % ", ".join(bad))
	get_tree().quit(0 if bad.is_empty() else 1)


func _scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		var p := dir.path_join(f)
		if d.current_is_dir():
			if not f.begins_with("."):
				out.append_array(_scripts(p))
		elif f.ends_with(".gd"):
			out.append(p)
		f = d.get_next()
	return out
