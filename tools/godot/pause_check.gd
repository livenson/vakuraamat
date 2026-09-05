extends Node
# Live check of the Esc menu: Esc opens it, Esc closes it, "save and main menu" returns to the menu.
var f := 0
var world: Node
func _ready() -> void:
	if get_tree().current_scene != self: return   # the watcher copy
	get_tree().root.add_child.call_deferred(self.duplicate())   # watcher that outlives the scene change
	get_tree().change_scene_to_file.call_deferred("res://scenes/world/world.tscn")
func _esc() -> void:
	var ev := InputEventKey.new(); ev.keycode = KEY_ESCAPE; ev.pressed = true
	Input.parse_input_event(ev)
func _process(_d: float) -> void:
	if get_tree().current_scene == self: return
	f += 1
	var scene := get_tree().current_scene
	if f == 150:
		_esc()
	if f == 160:
		var ui = scene.get_node("UI")
		print("[pause] after Esc: pause visible=", ui.pause.visible, " mouse=", Input.mouse_mode, " player input=", ui.player.input_enabled)
		_esc()
	if f == 170:
		var ui = scene.get_node("UI")
		print("[pause] after 2nd Esc: pause visible=", ui.pause.visible, " mouse=", Input.mouse_mode, " player input=", ui.player.input_enabled)
		_esc()
	if f == 180:
		var ui = scene.get_node("UI")
		for b in ui.pause.get_node("Body").get_children():
			if b is Button and b.text == tr("UI_SAVE_MENU"): b.pressed.emit()
	if f == 200:
		print("[pause] scene now: ", scene.scene_file_path, " has_save=", SaveManager.has_save(), " GameState.world=", GameState.world)
		get_tree().quit()
