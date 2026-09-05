# Autoload "DevChannel": the developer's way into a running game (debug builds only). Commands are
# JSON lines appended to user://dev/commands.jsonl (tools/dev.py writes them); results go to
# user://dev/results.log. Hot reload where Godot allows it, restart at the same spot where it does not.
#   {"reload": ["res://scripts/ui/ui_manager.gd", "res://sites/x/scenes/era_2026.tscn", "res://sites/x/strings.csv"]}
#   {"restart": true}   {"teleport": [x, z, yaw_deg]}   {"era": "era_1938"}   {"screenshot": "/abs.png"}
#   {"report": "note"}  {"note": "printed to the log"}  {"quit": true}
extends Node

const DIR := "user://dev/"
const CMD := "user://dev/commands.jsonl"
const RESULTS := "user://dev/results.log"

var enabled := false
var _offset := 0
var _timer: Timer


func _ready() -> void:
	enabled = OS.is_debug_build() or "--dev" in OS.get_cmdline_user_args()
	if not enabled:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	if FileAccess.file_exists(CMD):
		var f := FileAccess.open(CMD, FileAccess.READ)
		_offset = f.get_length()   # commands from before this run are stale
		f.close()
	_timer = Timer.new()
	_timer.wait_time = 0.5
	_timer.autostart = true
	_timer.timeout.connect(_poll)
	add_child(_timer)
	print("[DevChannel] listening on %s" % ProjectSettings.globalize_path(CMD))


func _poll() -> void:
	if not FileAccess.file_exists(CMD):
		return
	var f := FileAccess.open(CMD, FileAccess.READ)
	if f.get_length() <= _offset:
		return
	f.seek(_offset)
	var chunk := f.get_buffer(f.get_length() - _offset).get_string_from_utf8()
	_offset = f.get_length()
	f.close()
	for line in chunk.split("\n", false):
		var cmd = JSON.parse_string(line)
		if typeof(cmd) == TYPE_DICTIONARY:
			execute(cmd)
		else:
			_result("bad json: " + line)


## Run one command; results are logged and returned.
func execute(cmd: Dictionary) -> Array:
	var out: Array = []
	var world: Node = GameState.world
	if cmd.has("note"):
		print("[DevChannel] note: ", cmd.note)
		out.append("note ok")
	if cmd.has("reload"):
		for p in cmd.reload:
			out.append(reload_path(str(p)))
	if cmd.has("teleport") and world:
		var t: Array = cmd.teleport
		world.player.set_pose(Vector3(float(t[0]), 200.0, float(t[1])), deg_to_rad(float(t[2])) if t.size() > 2 else world.player.rotation.y, float(t[3]) if t.size() > 3 else 0.0)
		world._snap(world.player, 1.0)
		out.append("teleport ok %s" % [world.player.global_position])
	if cmd.has("era"):
		await GameState.switch_era(str(cmd.era))
		out.append("era %s" % GameState.current_era)
	if cmd.has("screenshot") and world:
		await RenderingServer.frame_post_draw
		world.get_viewport().get_texture().get_image().save_png(str(cmd.screenshot))
		out.append("screenshot " + str(cmd.screenshot))
	if cmd.has("codes") and world:
		world.ui._toggle_codes()
		out.append("codes %s" % ("on" if world.ui.codes_on else "off"))
	if cmd.has("report") and world:
		out.append("report " + Reporter.capture(str(cmd.report), world))
	if cmd.has("quit"):
		_result("quit")
		get_tree().quit()
		return out
	if cmd.has("restart"):
		out.append("restart")
		_result(" ; ".join(out))
		if world:
			world.restart_here()
		else:
			get_tree().quit()
		return out
	_result(" ; ".join(out) if not out.is_empty() else "nothing to do: " + JSON.stringify(cmd))
	return out


## Reload one resource in the running game. Scripts re-read their source and keep instance state;
## era scenes are re-instanced in place; pack data reloads the registries; other resources are
## replaced in the cache (shaders, textures take effect at once).
func reload_path(p: String) -> String:
	if not (p.begins_with("res://") or p.begins_with("user://")):
		p = "res://" + p.trim_prefix("./")
	var result := ""
	var ext := p.get_extension()
	var world: Node = GameState.world
	if not FileAccess.file_exists(p):
		result = "%s: missing" % p
	elif ext == "gd":
		var s = load(p)
		if s is GDScript:
			s.source_code = FileAccess.get_file_as_string(p)
			var err: int = s.reload(true)
			result = "%s: %s" % [p, "reloaded" if err == OK else "error %d (restart needed)" % err]
		else:
			result = "%s: not a GDScript" % p
	elif ext == "tscn":
		ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_REPLACE)
		result = "%s: cache replaced" % p
		for era in GameState.eras.values():
			if era.scene_path == p and world:
				world.reload_era_layer(era.id)
				result = "%s: era layer %s re-instanced" % [p, era.id]
	elif p.begins_with(Sites.path("")) or p.begins_with("res://sites/") or p.begins_with(Sites.USER_ROOT):
		Sites.reload_active()
		Narrative.reset_players()
		if world:
			world.reload_era_layer(GameState.current_era)
		result = "%s: pack reloaded (registries, strings, stories; current era layer re-instanced)" % p
	else:
		ResourceLoader.load(p, "", ResourceLoader.CACHE_MODE_REPLACE)
		result = "%s: cache replaced" % p
	return result


func _result(text: String) -> void:
	var line := "%s  %s" % [Time.get_datetime_string_from_system(), text]
	print("[DevChannel] " + text)
	var f := FileAccess.open(RESULTS, FileAccess.READ_WRITE if FileAccess.file_exists(RESULTS) else FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line(line)
		f.close()
