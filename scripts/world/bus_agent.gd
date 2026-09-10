# One bus running one trip through the tile. Unlike the ambient traffic it has somewhere to be: it
# follows its route's own polyline from the register's geometry, pulls in at each stop it calls at,
# waits, and goes on. It is never despawned for being far away - it leaves when its route leaves the
# tile, which is what a real bus does.
#
# The polyline is wrapped in a one-edge dictionary of the shape RoadGraph.build makes, because
# RoadGraph.point_at() and dir_at() only ever read `pts`, `cum` and `length`: the arclength walk and
# the heading come free, without the route having to exist in the road graph at all.
class_name BusAgent
extends Node3D

const SPEED := 9.0            # m/s on the open road, about 32 km/h through a suburb
const DWELL_S := 12.0         # seconds at a stop, in game time: a few real seconds at 150 min a day
const STOP_REACH := 18.0      # how near the polyline passes a stop before it counts as calling there
const LANE := 1.4             # metres right of the centre line, the side an Estonian bus drives on

var route: Dictionary = {}
var s := 0.0                  # metres along the route
var done := false

var _edge: Dictionary = {}
var _terrain: Terrain3D = null
var _body: Node3D = null
var _wheels: Array[Node3D] = []
var _calls: Array = []        # [{s, id}] where the route passes each stop it serves, in order
var _next_call := 0
var _wait := 0.0
var _speed_now := 0.0


func setup(r: Dictionary, stops: Array, start_s: float = 0.0) -> void:
	route = r
	var pts := PackedVector2Array()
	for p in r.get("shape", []):
		pts.append(Vector2(float(p[0]), float(p[1])))
	if pts.size() < 2:
		done = true
		return
	var cum := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		cum.append(cum[i - 1] + pts[i - 1].distance_to(pts[i]))
	_edge = {"pts": pts, "cum": cum, "length": cum[-1]}
	s = clampf(start_s, 0.0, _edge.length)
	_terrain = GameState.world.terrain if GameState.world else null
	# where along the line each of its stops lies: the nearest point on the polyline to the shelter
	for id in r.get("calls", []):
		var stop: Dictionary = {}
		for st in stops:
			if str(st.get("id", "")) == str(id):
				stop = st
				break
		if stop.is_empty():
			continue
		var at := Vector2(float(stop.x), float(stop.z))
		var best := -1.0
		var best_d := STOP_REACH
		var step := 2.0
		var walk := 0.0
		while walk <= _edge.length:
			var d := _point(walk).distance_to(at)
			if d < best_d:
				best_d = d
				best = walk
			walk += step
		if best >= 0.0:
			_calls.append({"s": best, "id": str(id)})
	_calls.sort_custom(func(a, b): return a.s < b.s)
	while _next_call < _calls.size() and _calls[_next_call].s < s:
		_next_call += 1
	_body = _make_body()
	if _body:
		MeshMerge.set_range(_body, 800.0)   # a 12 m bus still reads from the air; beyond this it does not
		add_child(_body)
	_place(0.0)


func advance(delta: float) -> void:
	if done or _edge.is_empty():
		return
	if _wait > 0.0:
		_wait -= delta
		_speed_now = lerpf(_speed_now, 0.0, minf(1.0, delta * 4.0))
		_place(delta)
		return
	var want := SPEED
	if _next_call < _calls.size():
		var to_stop: float = _calls[_next_call].s - s
		if to_stop < 25.0:
			want = SPEED * clampf(to_stop / 25.0, 0.06, 1.0)   # ease in rather than stop dead
		if to_stop <= 1.0:
			_wait = DWELL_S * _clock_scale()
			_next_call += 1
			want = 0.0
	_speed_now = lerpf(_speed_now, want, minf(1.0, delta * 2.0))
	s += _speed_now * delta
	if s >= _edge.length:
		done = true
		queue_free()
		return
	_place(delta)


## The stop the bus is standing at, "" while it is moving. The board and the sheet do not use this
## yet; it is what a "the 8 is here" notice would read.
func at_stop() -> String:
	return str(_calls[_next_call - 1].id) if _wait > 0.0 and _next_call > 0 else ""


# ---------------------------------------------------------------- internals

func _point(at: float) -> Vector2:
	var cum: PackedFloat32Array = _edge.cum
	var pts: PackedVector2Array = _edge.pts
	at = clampf(at, 0.0, _edge.length)
	var i := 1
	while i < cum.size() - 1 and cum[i] < at:
		i += 1
	var seg := cum[i] - cum[i - 1]
	var t := 0.0 if seg <= 0.0 else (at - cum[i - 1]) / seg
	return pts[i - 1].lerp(pts[i], t)


func _dir(at: float) -> Vector2:
	var d := _point(minf(at + 1.0, _edge.length)) - _point(maxf(at - 1.0, 0.0))
	if d.length_squared() < 0.0001:
		d = _edge.pts[-1] - _edge.pts[0]
	return d.normalized()


## In-game seconds per real second: the dwell is a timetable quantity, not a wall-clock one.
static func _clock_scale() -> float:
	var w: Node = GameState.world
	var per_day: float = w.sky.tod.minutes_per_day if w and w.sky and w.sky.tod else 150.0
	return maxf(per_day, 1.0) * 60.0 / 86400.0


func _place(delta: float) -> void:
	var d := _dir(s)
	var right := Vector2(-d.y, d.x)
	var p := _point(s) + right * LANE
	var parent := get_parent() as Node3D
	var gp := parent.to_global(Vector3(p.x, 0.0, p.y)) if parent else Vector3(p.x, 0.0, p.y)
	var h: float = _terrain.data.get_height(gp) if _terrain else 0.0
	var streamer = GameState.world.streamer if GameState.world else null
	if is_nan(h) or (streamer and not streamer.contains(gp)):
		h = global_position.y - 0.1   # off the built ground: hold the height rather than fall through
	global_position = Vector3(gp.x, h + 0.1, gp.z)
	if d.length_squared() > 0.0:
		rotation.y = atan2(-d.x, -d.y)
	for w in _wheels:
		w.rotate_object_local(Vector3.RIGHT, -_speed_now * delta / 0.5)   # a bus wheel is about a metre across


const MODEL := "res://assets/vendor/sketchfab/bus_city.glb"   # mcstr0517, CC BY (THIRD_PARTY.md)
const LENGTH_M := 12.0


func _make_body() -> Node3D:
	if not ResourceLoader.exists(MODEL):
		return null
	var model: Node3D = MeshMerge.instance(MODEL)   # 536 parts drawn as one mesh per material
	var b := Interiors._bounds(model)
	var long_axis := maxf(b.size.x, b.size.z)
	if long_axis <= 0.01:
		return model
	var k := LENGTH_M / long_axis
	model.scale = Vector3.ONE * k
	model.position = Vector3(-(b.position.x + b.size.x * 0.5) * k, -b.position.y * k, -(b.position.z + b.size.z * 0.5) * k)
	var turn := Node3D.new()
	# this one was exported nose along -Z, which is the way movers face, so it is not turned round;
	# the quarter turn is there only in case a replacement model lies across X instead (AGENTS.md)
	turn.rotation.y = PI / 2.0 if b.size.x > b.size.z else 0.0
	turn.add_child(model)
	return turn
