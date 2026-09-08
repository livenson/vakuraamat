# Window mode switching, and what the window costs while it is open. Autoload "WindowMode". F11, or
# Cmd+Ctrl+F on macOS where F11 is taken by the system, (action "fullscreen") toggles between
# a window and borderless fullscreen; the choice is remembered in user://settings.cfg and
# `--fullscreen` / `--windowed` on the command line override it for one run.
#
# The frame cap is here for the same reason: a still camera costs what a moving one does, because
# the renderer re-encodes every draw call of the scene each frame whether anything moved or not. So
# the game never draws faster than the screen can show, and a window the player has clicked away
# from falls to a trickle instead of burning a core behind their browser. Tools that count frames
# (`--screenshot=`, `--frames=`) and headless runs keep the engine's own uncapped loop.
extends Node

signal changed(fullscreen: bool)

const SETTINGS_PATH := "user://settings.cfg"
const FPS_UNFOCUSED := 10
const FPS_FALLBACK := 60   # when the platform will not say what the screen does

var _caps := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_caps = DisplayServer.get_name() != "headless"
	for a in args:
		if a.begins_with("--screenshot=") or a.begins_with("--frames="):
			_caps = false
	if _caps:
		_cap(true)
	if "--fullscreen" in args:
		set_fullscreen(true, false)
	elif "--windowed" in args:
		set_fullscreen(false, false)
	elif _saved_preference():
		set_fullscreen(true, false)


func _notification(what: int) -> void:
	if not _caps:
		return
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_cap(false)
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			_cap(true)


## Cap the frame rate: the screen's own rate while the player is here, a trickle while they are not.
func _cap(focused: bool) -> void:
	var to := _screen_hz() if focused else FPS_UNFOCUSED
	if Engine.max_fps == to:
		return
	Engine.max_fps = to
	print("[window] max_fps %d (%s)" % [to, "focused" if focused else "unfocused"])


func _screen_hz() -> int:
	var hz := DisplayServer.screen_get_refresh_rate(DisplayServer.window_get_current_screen())
	return int(round(hz)) if hz > 0.0 else FPS_FALLBACK


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
