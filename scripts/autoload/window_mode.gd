# Window mode switching. Autoload "WindowMode". F11 (action "fullscreen") toggles between
# a window and borderless fullscreen; `--fullscreen` on the command line starts that way.
extends Node


func _ready() -> void:
	if "--fullscreen" in OS.get_cmdline_user_args():
		set_fullscreen(true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("fullscreen"):
		set_fullscreen(not is_fullscreen())
		get_viewport().set_input_as_handled()


func is_fullscreen() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


func set_fullscreen(on: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)
