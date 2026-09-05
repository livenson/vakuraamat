# Runs the main menu, grabs a screenshot after a few frames, quits.
extends Node
var frames := 0
var path: String = ""
func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): path = a.trim_prefix("--out=")
	var menu: Control = load("res://scenes/ui/main_menu.tscn").instantiate()
	add_child(menu)
	var args := OS.get_cmdline_user_args()
	if "--creating" in args or "--failed" in args:   # the progress sheet, mid-job or after a failure
		var sheet: Control = menu.call("_progress_sheet", "Kvissentali, Tartu")
		sheet.get_meta("stage").call("cadastre and roads", 0.58)
		if "--failed" in args:
			sheet.get_meta("fail").call(tr("MENU_SERVICE_DOWN") % "http://127.0.0.1:8765")
func _process(_d: float) -> void:
	frames += 1
	if frames == 30:
		get_viewport().get_texture().get_image().save_png(path)
		print("[menu] shot -> ", path, " window ", DisplayServer.window_get_size(), " mode ", DisplayServer.window_get_mode())
		get_tree().quit()
