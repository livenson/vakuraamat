# A fixed route for before/after performance numbers (--bench): once the layer stands, turn
# once on the spot at street level, walk at the nearest building for a few seconds (a check that
# floors and walls still hold the player: the walk's distance, how near the wall it stopped and
# the height above the ground are in the summary), then fly north at survey height across the
# next tiles, then quit. Frame pacing is uncapped (no vsync, no frame cap) so the numbers are the game's own
# cost, not the screen's. The summary goes to stdout and user://logs/bench.json; PerfLog keeps
# its per-second lines and SPIKE marks as usual, each phase marked in them.
class_name Bench
extends Node

const TURN_S := 12.0          # street level: one full turn
const WALK_S := 10.0          # street level: towards the nearest building's wall
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
var _walk: Dictionary = {}    # the walk's check: from, to, the building's centre



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
	if phase == "walk":
		var p: CharacterBody3D = _world.player
		var target := _nearest_building(p.global_position)
		_walk = {"from": p.global_position, "centre": target}
		p.set_pose(p.global_position, atan2(-(target.x - p.global_position.x), -(target.z - p.global_position.z)), 0.0)
		p.input_enabled = true
		Input.action_press("move_forward")
	if phase == "fly":
		_census()
		# where the walk ended, for a look: user://logs/bench_walk.png
		_world.get_viewport().get_texture().get_image().save_png("user://logs/bench_walk.png")
		Input.action_release("move_forward")
		_world.player.input_enabled = false
		_walk["to"] = _world.player.global_position
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
			_begin("walk")
	elif _phase == "walk":
		if _t >= WALK_S:
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
	if _walk.has("to"):
		var from: Vector3 = _walk.from
		var to: Vector3 = _walk.to
		var c: Vector3 = _walk.centre
		var ground: float = _world.terrain.data.get_height(to)
		out.walk["moved_m"] = snappedf(Vector2(to.x - from.x, to.z - from.z).length(), 0.1)
		out.walk["to_centre_m"] = snappedf(Vector2(c.x - to.x, c.z - to.z).length(), 0.1)
		out.walk["above_ground_m"] = snappedf(to.y - ground, 0.01)
	for phase: String in out:
		if out[phase] is Dictionary:
			print("[bench] %s %s" % [phase, JSON.stringify(out[phase])])
	var f := FileAccess.open("user://logs/bench.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	get_tree().quit()


## What draws: every visible GeometryInstance3D in the tree grouped by the nearest ancestor with a
## script (or a named container), with how many cast shadows and how many have no visibility range.
## Printed as [census] lines, largest groups first: where the draw calls come from.
func _census() -> void:
	var groups: Dictionary = {}
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n is GeometryInstance3D) or not (n as Node3D).is_visible_in_tree():
			continue
		var g := n as GeometryInstance3D
		var owner_name := _owner_label(g)
		var key := "%s/%s" % [owner_name, g.get_class()]
		if not groups.has(key):
			groups[key] = [0, 0, 0, 0]   # count, surfaces, shadow casters, without a range
		var e: Array = groups[key]
		e[0] += 1
		if g is MeshInstance3D and (g as MeshInstance3D).mesh:
			e[1] += (g as MeshInstance3D).mesh.get_surface_count()
		elif g is MultiMeshInstance3D:
			e[1] += 1
		if g.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			e[2] += 1
		if g.visibility_range_end <= 0.0:
			e[3] += 1
	var keys := groups.keys()
	keys.sort_custom(func(a, b): return groups[a][1] > groups[b][1])
	for k in keys.slice(0, 30):
		var e: Array = groups[k]
		print("[census] %-48s nodes %6d surfaces %6d shadows %6d no-range %6d" % [k, e[0], e[1], e[2], e[3]])


static func _owner_label(n: Node) -> String:
	var p: Node = n.get_parent()
	while p:
		var s: Script = p.get_script()
		if s and s.get_global_name() != "":
			return String(s.get_global_name())
		if p.name in ["Buildings", "Parcels", "Village", "Traffic", "Roads"]:
			return String(p.name)
		p = p.get_parent()
	return "?"


## The centre of the nearest built building, at street height.
static func _nearest_building(from: Vector3) -> Vector3:
	var best := from + Vector3(0, 0, -20)
	var best_d := INF
	for id: int in FootprintBuilding.standing:
		var b: FootprintBuilding = FootprintBuilding.standing[id]
		if not b.is_built or b.polygon.is_empty():
			continue
		var mid := Vector2.ZERO
		for q in b.polygon:
			mid += q
		var c := b.to_global(Vector3(mid.x / b.polygon.size(), 0.0, mid.y / b.polygon.size()))
		var d := Vector2(c.x - from.x, c.z - from.z).length()
		if d < best_d:
			best_d = d
			best = c
	return best


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
