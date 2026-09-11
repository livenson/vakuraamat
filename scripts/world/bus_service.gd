# The buses of the timetable. For every route through this tile it asks, a few times a second, which
# departures should have a bus on the road right now, and makes sure exactly those exist.
#
# Asking rather than counting is the point. The clock jumps often - `--hour=`, entering a layer,
# loading a save, and midnight every 150 real minutes - and anything that accumulated elapsed time
# would drift or double-spawn across every one of those. Recomputing from the clock also means
# arriving in the world at 14:02 puts the 13:58 bus where it would be by now, instead of an empty
# road until the next departure.
#
# A bus drives at a bus's speed, not at the clock's: a day passes in 150 real minutes here, so the
# 570 m through Kvissentali takes about a real minute, which is some ten game minutes rather than the
# two a real 8 would take. The departure time is honoured; the journey is slower than life. Driving
# it at game speed would put an 86 m/s bus through the suburb.
class_name BusService
extends Node3D

const TICK_S := 0.5
const ARRIVAL_BUDGET_USEC := 6000   # the first sync after arrival spawned 50 buses in one frame (0.5 s, debug build)

var pack := ""
var _stops: Array = []
var _running: Dictionary = {}   # "<route index>@<HH:MM>" -> BusAgent
var _timer := 0.0


func _ready() -> void:
	pack = Sites.pack_of(self)
	var path := Sites.path_in(pack, "stops.json")
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			_stops = parsed.get("stops", [])
	var n := Departures.routes(pack).size()
	if n > 0:
		print("[buses] %s: %d routes on the timetable" % [pack, n])
		HumanFigure.warm([BusAgent.MODEL])   # read on a loader thread, not by the first bus's frame


func _physics_process(delta: float) -> void:
	if not is_visible_in_tree() or GameState.world == null:
		return
	for key in _running:
		if not is_instance_valid(_running[key]):
			continue   # checked before the typed assignment: assigning a freed instance is the error
		var bus: BusAgent = _running[key]
		bus.advance(delta)
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = TICK_S
	_sync()


## Make the buses on the road match the ones the timetable says should be, and no others.
func _sync() -> void:
	var routes := Departures.routes(pack)
	if routes.is_empty():
		return
	var w: Node = GameState.world
	var hour: float = w.sky.tod.current_time if w and w.sky and w.sky.tod else 12.0
	var now := hour * 60.0
	var day := Departures.today(pack)
	var live := {}
	var t0 := Time.get_ticks_usec()
	var spawned := 0
	var more := false
	for i in routes.size():
		var r: Dictionary = routes[i]
		var length := _length_of(r)
		if length <= 0.0:
			continue
		# how long a trip is on the road here, in minutes of the world's clock
		var window := length / BusAgent.SPEED * _game_minutes_per_real_second()
		for t in Departures.times_of(r, day):
			var dep := _minutes(str(t))
			if dep < 0:
				continue
			var since := now - dep
			if since < 0.0:
				since += 24 * 60.0     # it left before midnight and is still going
			if since > window:
				continue
			var key := "%d@%s" % [i, t]
			live[key] = true
			if not _running.has(key) or not is_instance_valid(_running[key]):
				if spawned > 0 and Time.get_ticks_usec() - t0 > ARRIVAL_BUDGET_USEC:
					more = true   # the rest next physics frame; live keeps counting, so nothing running is dropped
					continue
				var bus := BusAgent.new()
				add_child(bus)
				bus.setup(r, _stops, since / _game_minutes_per_real_second() * BusAgent.SPEED)
				if bus.done:
					bus.queue_free()
					continue
				_running[key] = bus
				spawned += 1
				print("[buses] %s %s left at %s, %.0f m along" % [r.get("line", ""), r.get("headsign", ""), t, bus.s])
	if spawned > 0 and Time.get_ticks_usec() - t0 > 4000:
		PerfLog.mark("buses %d new in %d ms" % [spawned, (Time.get_ticks_usec() - t0) / 1000])
	if more:
		_timer = 0.0
	for key in _running.keys():
		if not is_instance_valid(_running[key]):
			_running.erase(key)
			continue
		var bus: BusAgent = _running[key]
		if not live.has(key) or bus.done:
			bus.queue_free()
			_running.erase(key)


# ---------------------------------------------------------------- internals

static func _game_minutes_per_real_second() -> float:
	var w: Node = GameState.world
	var per_day: float = w.sky.tod.minutes_per_day if w and w.sky and w.sky.tod else 150.0
	return 24.0 * 60.0 / (maxf(per_day, 1.0) * 60.0)


static func _length_of(r: Dictionary) -> float:
	var shape: Array = r.get("shape", [])
	var total := 0.0
	for i in range(1, shape.size()):
		total += Vector2(float(shape[i - 1][0]), float(shape[i - 1][1])).distance_to(Vector2(float(shape[i][0]), float(shape[i][1])))
	return total


static func _minutes(hhmm: String) -> int:
	var bits := hhmm.split(":")
	return int(bits[0]) * 60 + int(bits[1]) if bits.size() == 2 else -1
