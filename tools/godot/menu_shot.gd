# Runs the main menu, grabs a screenshot after a few frames, quits.
extends Node
var frames := 0
var path: String = ""
var wait := 30
func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): path = a.trim_prefix("--out=")
		if a.begins_with("--locale="): TranslationServer.set_locale(a.trim_prefix("--locale="))   # --locale=lv
		if a.begins_with("--wait="): wait = int(a.trim_prefix("--wait="))   # frames before the shot (1: the renderer warm-up's splash)
	var menu: Control = load("res://scenes/ui/main_menu.tscn").instantiate()
	add_child(menu)
	var args := OS.get_cmdline_user_args()
	if "--locations" in args:   # the Locations page; --query=<text> searches it and picks the first place
		menu.call("_build_locations_panel")
		for a in args:
			if a.begins_with("--query="):
				wait = 600
				menu.get("_query").text = a.trim_prefix("--query=")
				menu.call("_search")
				get_tree().create_timer(2.0).timeout.connect(func():
					var results: VBoxContainer = menu.get("_results")
					if results.get_child_count() > 0:
						results.get_child(0).pressed.emit())
	if "--creating" in args or "--failed" in args:   # the progress sheet, mid-job or after a failure
		var sheet: Control = menu.call("_progress_sheet", "Kvissentali, Tartu")
		sheet.get_meta("stage").call("cadastre and roads", 0.58)
		if "--failed" in args:
			sheet.get_meta("fail").call(tr("MENU_SERVICE_DOWN") % "http://127.0.0.1:8765")
func _process(_d: float) -> void:
	frames += 1
	var args := OS.get_cmdline_user_args()
	if frames == wait - 5 and "--bottom" in args:
		for sc in find_children("*", "ScrollContainer", true, false):
			sc.scroll_vertical = 100000
	if frames == wait - 5:   # --scroll=<px> stops part way down the page, --map=<n> lights one mark of the locator
		for a in args:
			if a.begins_with("--scroll="):
				for sc in find_children("*", "ScrollContainer", true, false):
					sc.scroll_vertical = int(a.trim_prefix("--scroll="))
			elif a.begins_with("--map="):
				for m in find_children("*", "EstoniaMap", true, false):
					m.highlight(int(a.trim_prefix("--map=")))
	if frames == wait:
		get_viewport().get_texture().get_image().save_png(path)
		print("[menu] shot -> ", path, " window ", DisplayServer.window_get_size(), " mode ", DisplayServer.window_get_mode())
		get_tree().quit()
