# Autoload "PerfLog": a performance record of every session, in release builds too, so a freeze
# the player felt can be read afterwards (user://logs/perf.log, truncated at start;
# `python3 tools/dev.py perf` prints the spikes). Every second: one line of counters and where
# the player was. Every frame longer than SPIKE_MS: a SPIKE line with the marks other systems
# left during that frame (PerfLog.mark("tile load x") from the tile streamer, the era switch,
# the terrain builder, the interiors), so the line names what ran while the game stood still.
extends Node

const PATH := "user://logs/perf.log"
const PREV := "user://logs/perf.prev.log"   # the previous session (a crashed one survives the relaunch)
const SPIKE_MS := 100.0
const ROLL_BYTES := 16 * 1024 * 1024        # a long session rolls into perf.prev.log and starts afresh

var enabled := true
var _file: FileAccess
var _last_usec := 0
var _sec_frames := 0
var _sec_sum := 0.0
var _sec_max := 0.0
var _sec_start := 0.0
var _marks: Array[String] = []        # marks left during the frame now running
var _prev_marks: Array[String] = []   # marks of the frame that just ended
# pipeline compilations (4.4+ monitors) at the start of the last frame: a SPIKE names the ones it
# paid for, so a shader compiled on first sight shows as "compiled draw 3" instead of "no marks"
const PIPELINES := {"canvas": Performance.PIPELINE_COMPILATIONS_CANVAS, "mesh": Performance.PIPELINE_COMPILATIONS_MESH,
	"surface": Performance.PIPELINE_COMPILATIONS_SURFACE, "draw": Performance.PIPELINE_COMPILATIONS_DRAW,
	"specialization": Performance.PIPELINE_COMPILATIONS_SPECIALIZATION}
var _pipelines: Dictionary = {}


func _ready() -> void:
	process_priority = -1000   # first in the frame: the delta measured here spans the whole previous frame
	# headless runs (tests, tools) share the user directory with the player's game: they must not truncate its log
	enabled = DisplayServer.get_name() != "headless" and not ("--no-perf-log" in OS.get_cmdline_user_args())
	if not enabled:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://logs"))
	_open(true)
	if not enabled:
		return
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


## Start a fresh file, the current one becoming perf.prev.log; `session` marks a new run's header.
func _open(session: bool) -> void:
	if _file:
		_file.close()
		_file = null
	if FileAccess.file_exists(PATH):
		if FileAccess.file_exists(PREV):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(PREV))
		DirAccess.rename_absolute(ProjectSettings.globalize_path(PATH), ProjectSettings.globalize_path(PREV))
	_file = FileAccess.open(PATH, FileAccess.WRITE)
	if _file == null:
		enabled = false
		return
	_file.store_line("# %s  %s  %s  site %s%s" % [Time.get_datetime_string_from_system(), OS.get_name(), "debug" if OS.is_debug_build() else "release", Sites.active, "" if session else "  (continued: the earlier part is perf.prev.log)"])
	_file.store_line("# every second: fps | frame ms avg/max | process/physics ms | draw calls, objects, nodes | static/video MB | position, mode | marks")
	_file.flush()
	_last_usec = Time.get_ticks_usec()
	_sec_start = _last_usec / 1e6


## Leave a note in the frame now running; it is written with the SPIKE line if this frame is
## one, and with the second's line otherwise.
func mark(text: String) -> void:
	if enabled and _marks.size() < 40:
		_marks.append(text)


func _process(_delta: float) -> void:
	if not enabled:
		return
	var now := Time.get_ticks_usec()
	var ms := (now - _last_usec) / 1000.0
	_last_usec = now
	_prev_marks = _marks
	_marks = []
	for k: String in PIPELINES:
		var n := int(Performance.get_monitor(PIPELINES[k]))
		if n > int(_pipelines.get(k, n)):
			_prev_marks.append("compiled %s %d" % [k, n - int(_pipelines[k])])
		_pipelines[k] = n
	_sec_frames += 1
	_sec_sum += ms
	_sec_max = maxf(_sec_max, ms)
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var mem := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	# a frame the cap made long is not a spike: unfocused, the window runs at 10 FPS (100 ms frames)
	var capped := Engine.max_fps > 0 and ms <= 1000.0 / Engine.max_fps + 15.0
	if ms >= SPIKE_MS and not capped:
		_file.store_line("%s SPIKE %.0f ms | %s | %s | %s" % [_stamp(), ms, _where(), ", ".join(_prev_marks) if not _prev_marks.is_empty() else "no marks", _anatomy(nodes, mem)])
		_file.flush()
	elif not _prev_marks.is_empty():
		_file.store_line("%s mark %.0f ms | %s" % [_stamp(), ms, ", ".join(_prev_marks)])
	_last_nodes = nodes
	_last_mem = mem
	var t := now / 1e6
	if t - _sec_start >= 1.0:
		var perf := Performance
		_file.store_line("%s fps %3d | %5.1f/%6.1f ms | proc %5.1f phys %4.1f | dc %4d obj %5d nodes %5d | mem %4.0f/%5.0f MB | %s" % [
			_stamp(), _sec_frames, _sec_sum / maxi(_sec_frames, 1), _sec_max,
			perf.get_monitor(perf.TIME_PROCESS) * 1000.0, perf.get_monitor(perf.TIME_PHYSICS_PROCESS) * 1000.0,
			int(perf.get_monitor(perf.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(perf.get_monitor(perf.RENDER_TOTAL_OBJECTS_IN_FRAME)), int(perf.get_monitor(perf.OBJECT_NODE_COUNT)),
			perf.get_monitor(perf.MEMORY_STATIC) / 1048576.0, perf.get_monitor(perf.RENDER_VIDEO_MEM_USED) / 1048576.0, _where()])
		_file.flush()
		_sec_start = t
		_sec_frames = 0
		_sec_sum = 0.0
		_sec_max = 0.0
		if _file.get_position() > ROLL_BYTES:
			_open(false)


var _last_nodes := 0
var _last_mem := 0.0


## What arrived in a long frame, so one without marks still says where to look: the nodes and
## static MB it added (a load or an instantiation), and the renderer's CPU time of a recent frame
## (the render thread runs a frame or two behind; hundreds of ms there is pipelines compiling).
## Nothing grown and a small render time means the frame was spent waiting: the GPU, the driver,
## a lock, the OS. (Performance's process and physics times are not refreshed every frame, so
## they are left out rather than misread.)
func _anatomy(nodes: int, mem: float) -> String:
	var render := RenderingServer.get_frame_setup_time_cpu()
	var vp := get_viewport()
	if vp:
		render += RenderingServer.viewport_get_measured_render_time_cpu(vp.get_viewport_rid())
	return "nodes %+d, mem %+.0f MB, render cpu %.0f ms" % [nodes - _last_nodes, mem - _last_mem, render]


func _stamp() -> String:
	return Time.get_time_string_from_system()


## Player position and mode, and the tile streamer's state, when a world is up.
func _where() -> String:
	var w: Node = GameState.world
	if w == null or not is_instance_valid(w) or w.player == null:
		return "menu"
	var p: Vector3 = w.player.global_position
	var mode := "fly" if w.player.get("flying") else "walk"
	var s := ""
	if w.get("streamer") and w.streamer.has_method("loading_status"):
		s = str(w.streamer.loading_status())
	return "%.0f,%.0f,%.0f %s%s" % [p.x, p.y, p.z, mode, (" | " + s) if s != "" else ""]
