# Autoload "PerfLog": a performance record of every session, in release builds too, so a freeze
# the player felt can be read afterwards (user://logs/perf.log, truncated at start;
# `python3 tools/dev.py perf` prints the spikes). Every second: one line of counters and where
# the player was. Every frame longer than SPIKE_MS: a SPIKE line with the marks other systems
# left during that frame (PerfLog.mark("tile load x") from the tile streamer, the era switch,
# the terrain builder, the interiors), so the line names what ran while the game stood still.
extends Node

const PATH := "user://logs/perf.log"
const SPIKE_MS := 100.0

var enabled := true
var _file: FileAccess
var _last_usec := 0
var _sec_frames := 0
var _sec_sum := 0.0
var _sec_max := 0.0
var _sec_start := 0.0
var _marks: Array[String] = []        # marks left during the frame now running
var _prev_marks: Array[String] = []   # marks of the frame that just ended


func _ready() -> void:
	process_priority = -1000   # first in the frame: the delta measured here spans the whole previous frame
	enabled = not ("--no-perf-log" in OS.get_cmdline_user_args())
	if not enabled:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://logs"))
	_file = FileAccess.open(PATH, FileAccess.WRITE)
	if _file == null:
		enabled = false
		return
	_file.store_line("# %s  %s  %s  site %s" % [Time.get_datetime_string_from_system(), OS.get_name(), "debug" if OS.is_debug_build() else "release", Sites.active])
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
	_sec_frames += 1
	_sec_sum += ms
	_sec_max = maxf(_sec_max, ms)
	if ms >= SPIKE_MS:
		_file.store_line("%s SPIKE %.0f ms | %s | %s" % [_stamp(), ms, _where(), ", ".join(_prev_marks) if not _prev_marks.is_empty() else "no marks"])
		_file.flush()
	elif not _prev_marks.is_empty():
		_file.store_line("%s mark %.0f ms | %s" % [_stamp(), ms, ", ".join(_prev_marks)])
	var t := now / 1e6
	if t - _sec_start >= 1.0:
		var P := Performance
		_file.store_line("%s fps %3d | %5.1f/%6.1f ms | proc %5.1f phys %4.1f | dc %4d obj %5d nodes %5d | mem %4.0f/%5.0f MB | %s" % [
			_stamp(), _sec_frames, _sec_sum / maxi(_sec_frames, 1), _sec_max,
			P.get_monitor(P.TIME_PROCESS) * 1000.0, P.get_monitor(P.TIME_PHYSICS_PROCESS) * 1000.0,
			int(P.get_monitor(P.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(P.get_monitor(P.RENDER_TOTAL_OBJECTS_IN_FRAME)), int(P.get_monitor(P.OBJECT_NODE_COUNT)),
			P.get_monitor(P.MEMORY_STATIC) / 1048576.0, P.get_monitor(P.RENDER_VIDEO_MEM_USED) / 1048576.0, _where()])
		_file.flush()
		_sec_start = t
		_sec_frames = 0
		_sec_sum = 0.0
		_sec_max = 0.0


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
