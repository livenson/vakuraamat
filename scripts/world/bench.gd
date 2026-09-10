# A fixed route for before/after performance numbers (--bench): once the layer stands, turn
# once on the spot at street level, then fly north at survey height across the next tiles, then
# quit. Frame pacing is uncapped (no vsync, no frame cap) so the numbers are the game's own
# cost, not the screen's. The summary goes to stdout and user://logs/bench.json; PerfLog keeps
# its per-second lines and SPIKE marks as usual, each phase marked in them.
class_name Bench
extends Node

const TURN_S := 12.0          # street level: one full turn
const FLY_S := 40.0           # survey flight
const FLY_HEIGHT := 120.0     # metres above the ground at the start of the flight
const FLY_SPEED := 50.0       # m/s north (-Z): 2 km, two tile edges from a pack's centre

var _world: Node
var _phase := ""
var _t := 0.0
var _start := Vector3.ZERO
var _yaw := 0.0
var _frames: Dictionary = {}  # phase -> Array of frame ms
var _phys: Dictionary = {}    # phase -> Array of physics ms (per second samples)
var _dc: Dictionary = {}      # phase -> Array of draw calls (per frame)
var _last_usec := 0


## --bench-off=traffic,details,doors,tcol switches a system off for a bisecting run: ambient
## traffic, the buildings' small props (chimney, panels, well), the doors, Terrain3D's collision.
static func is_off(system: String) -> bool:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--bench-off="):
			return system in a.trim_prefix("--bench-off=").split(",")
	return false


func setup(world: Node) -> void:
	_world = world
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	world.player.input_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_off("tcol"):
		world.terrain.collision_mode = 0
	if world.filling:
		await world.era_filled
	await get_tree().create_timer(3.0).timeout   # the fade and the first traffic burst settle
	_start = world.player.global_position
	_yaw = world.player.rotation.y
	_begin("turn")


func _begin(phase: String) -> void:
	_phase = phase
	_t = 0.0
	_frames[phase] = []
	_phys[phase] = []
	_dc[phase] = []
	_last_usec = Time.get_ticks_usec()
	PerfLog.mark("bench " + phase)
	if phase == "fly":
		_world.player.flying = true
		_start.y += FLY_HEIGHT


func _process(delta: float) -> void:
	if _phase == "":
		return
	var now := Time.get_ticks_usec()
	_frames[_phase].append((now - _last_usec) / 1000.0)
	_last_usec = now
	_dc[_phase].append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_phys[_phase].append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	_t += delta
	var p: CharacterBody3D = _world.player
	if _phase == "turn":
		p.set_pose(p.global_position, _yaw + TAU * _t / TURN_S, 0.0)
		if _t >= TURN_S:
			_begin("fly")
	elif _phase == "fly":
		p.velocity = Vector3.ZERO
		p.set_pose(_start + Vector3(0, 0, -FLY_SPEED * _t), 0.0, deg_to_rad(-20.0))
		if _t >= FLY_S:
			_finish()


func _finish() -> void:
	_phase = ""
	var out := {"site": Sites.active, "build": "debug" if OS.is_debug_build() else "release",
		"time": Time.get_datetime_string_from_system(), "args": " ".join(OS.get_cmdline_user_args())}
	for phase: String in _frames:
		out[phase] = _summary(_frames[phase], _phys[phase], _dc[phase])
		print("[bench] %s %s" % [phase, JSON.stringify(out[phase])])
	var f := FileAccess.open("user://logs/bench.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	get_tree().quit()


static func _summary(ms: Array, phys: Array, dc: Array) -> Dictionary:
	var s := ms.duplicate()
	s.sort()
	var n := s.size()
	var total := 0.0
	for v: float in s:
		total += v
	var d := dc.duplicate()
	d.sort()
	var ph := phys.duplicate()
	ph.sort()
	return {"frames": n, "fps_avg": snappedf(n / (total / 1000.0), 0.1),
		"ms_p50": snappedf(s[n / 2], 0.1), "ms_p99": snappedf(s[mini(n - 1, n * 99 / 100)], 0.1),
		"ms_max": snappedf(s[-1], 0.1), "over_50ms": s.filter(func(v): return v > 50.0).size(),
		"over_100ms": s.filter(func(v): return v > 100.0).size(),
		"phys_p50": snappedf(ph[n / 2], 0.1), "phys_max": snappedf(ph[-1], 0.1),
		"dc_p50": int(d[n / 2]), "dc_max": int(d[-1])}
