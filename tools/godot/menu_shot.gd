# Runs the main menu, grabs a screenshot after a few frames, quits.
extends Node
var frames := 0
var path: String = ""
func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): path = a.trim_prefix("--out=")
	add_child(load("res://scenes/ui/main_menu.tscn").instantiate())
func _process(_d: float) -> void:
	frames += 1
	if frames == 30:
		get_viewport().get_texture().get_image().save_png(path)
		print("[menu] shot -> ", path, " window ", DisplayServer.window_get_size(), " mode ", DisplayServer.window_get_mode())
		get_tree().quit()
