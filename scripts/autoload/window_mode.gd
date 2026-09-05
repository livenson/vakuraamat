# Window mode switching. Autoload "WindowMode". F11, or Cmd+Ctrl+F on macOS where F11 is taken
# by the system, (action "fullscreen") toggles between
# a window and borderless fullscreen; the choice is remembered in user://settings.cfg and
# `--fullscreen` / `--windowed` on the command line override it for one run.
extends Node

signal changed(fullscreen: bool)

const SETTINGS_PATH := "user://settings.cfg"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--fullscreen" in args:
		set_fullscreen(true, false)
	elif "--windowed" in args:
		set_fullscreen(false, false)
	elif _saved_preference():
		set_fullscreen(true, false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("fullscreen"):
		set_fullscreen(not is_fullscreen())
		get_viewport().set_input_as_handled()


func is_fullscreen() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


func set_fullscreen(on: bool, remember := true) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)
	if remember:
		var cfg := ConfigFile.new()
		cfg.load(SETTINGS_PATH)   # missing file is fine, we overwrite the one key
		cfg.set_value("display", "fullscreen", on)
		cfg.save(SETTINGS_PATH)
	changed.emit(on)


func _saved_preference() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return false
	return bool(cfg.get_value("display", "fullscreen", false))


## Human-readable shortcut for the current platform, for menu labels.
func shortcut_text() -> String:
	return "Cmd+Ctrl+F" if OS.get_name() == "macOS" else "F11"
