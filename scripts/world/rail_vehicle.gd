# One tram or train on the Rails' graph: it runs along its track at its speed, slows behind the one
# ahead, stops at the tram stops, and takes the straightest way on at every switch (Rails.next_edge).
# Each car sits on the chord between its two ends along the path the front has run, so a train bends
# through a curve instead of swinging out of it. It leaves where the line leaves the tile.
class_name RailVehicle
extends Node3D

const DWELL_S := 25.0         # seconds at a stop, game time (the buses' clock: BusAgent._clock_scale)
const GAP := 12.0             # metres kept behind the vehicle ahead

var rails: Rails
var kind := "tram"
var edge: Dictionary = {}
var s := 0.0
var forward := true
var top_speed := 8.0
var car_len := 27.0
var cars := 1
var _speed := 0.0
var _wait := 0.0
var _served := -1.0           # the stop on this edge already stopped at
var _bodies: Array[Node3D] = []
var _trail: Array[Vector2] = []   # the front's past positions, newest first, about a metre apart


func setup(r: Rails, k: String, e: Dictionary, s0: float, fwd: bool, model: String, length: float, n_cars: int, speed: float) -> bool:
	rails = r
	kind = k
	edge = e
	s = clampf(s0, 0.0, e.length)
	forward = fwd
	car_len = length
	cars = n_cars
	top_speed = speed
	_speed = speed * 0.6
	for i in cars:
		var body := _make_body(model, length)
		if body == null:
			return false
		add_child(body)
		_bodies.append(body)
	# the path behind the front, for the cars that trail it: back along this edge, then straight on
	var back_dir := -rails.graph.dir_at(edge, s, forward)
	var walk := 0.0
	while walk <= cars * car_len + 4.0:
		var at := s - walk if forward else s + walk
		if at >= 0.0 and at <= edge.length:
			_trail.append(rails.graph.point_at(edge, at))
		else:
			var over: float = -at if at < 0.0 else at - float(edge.length)
			var end_p := rails.graph.point_at(edge, clampf(at, 0.0, edge.length))
			_trail.append(end_p + back_dir * over)
		walk += 1.0
	_place()
	return true


func advance(delta: float, others: Array) -> void:
	if _wait > 0.0:
		_wait -= delta
		return
	var want := top_speed
	for o in others:   # the one ahead on this track
		if o == self or not is_instance_valid(o) or o.edge.id != edge.id or o.forward != forward:
			continue
		var d: float = (o.s - s) if forward else (s - o.s)
		if d <= 0.0:
			continue
		var room: float = d - o.cars * o.car_len - GAP
		if room < 0.5:
			want = 0.0
		elif room < 40.0:
			want = minf(want, top_speed * room / 40.0)
	if kind == "tram":
		for st in rails.stops_on.get(edge.id, []):
			if is_equal_approx(float(st), _served):
				continue
			var d: float = (float(st) - s) if forward else (s - float(st))
			if d > 0.0 and d < 30.0:
				want = minf(want, maxf(top_speed * d / 30.0, 0.8))
				if d < 0.8:
					_wait = DWELL_S * BusAgent._clock_scale()
					_served = float(st)
					_speed = 0.0
					return
	_speed = lerpf(_speed, want, minf(1.0, delta * 0.8))
	s += _speed * delta * (1.0 if forward else -1.0)
	if s > edge.length or s < 0.0:
		var over: float = (s - edge.length) if forward else -s
		var nxt := rails.next_edge(edge, forward)
		if nxt.is_empty():
			queue_free()   # the line leaves the tile
			return
		edge = nxt.edge
		forward = nxt.forward
		s = over if forward else edge.length - over
		_served = -1.0
	_place()


func _place() -> void:
	var front := rails.graph.point_at(edge, s)
	if _trail.is_empty() or front.distance_to(_trail[0]) >= 1.0:
		_trail.push_front(front)
		if _trail.size() > int(cars * car_len) + 8:
			_trail.resize(int(cars * car_len) + 8)
	for i in _bodies.size():
		var head := _along(front, i * (car_len + 0.6))
		var tail := _along(front, i * (car_len + 0.6) + car_len)
		var mid := (head + tail) * 0.5
		var dir := (head - tail).normalized()
		var y := rails.rail_height(edge, s, mid) if i == 0 else rails.rail_height({"kind": edge.kind}, 0.0, mid)
		var body := _bodies[i]
		body.position = Vector3(mid.x, y, mid.y)
		if dir.length_squared() > 0.0:
			body.rotation.y = atan2(-dir.x, -dir.y)   # movers face -Z (AGENTS.md)


## The point `dist` metres back along the path the front has run.
func _along(front: Vector2, dist: float) -> Vector2:
	var prev := front
	var left := dist
	for p in _trail:
		var seg := prev.distance_to(p)
		if seg >= left and seg > 0.0:
			return prev.lerp(p, left / seg)
		left -= seg
		prev = p
	if _trail.size() >= 2:
		return prev + (_trail[-1] - _trail[-2]).normalized() * left
	return prev


## The model fitted along its long axis to `length` metres, nose along -Z (the way movers face).
static func _make_body(path: String, length: float) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var model: Node3D = MeshMerge.instance(path)
	var b := Interiors._bounds(model)
	var long_axis := maxf(b.size.x, b.size.z)
	if long_axis <= 0.01:
		return null
	var k := length / long_axis
	model.scale = Vector3.ONE * k
	model.position = Vector3(-(b.position.x + b.size.x * 0.5) * k, -b.position.y * k, -(b.position.z + b.size.z * 0.5) * k)
	var turn := Node3D.new()
	turn.rotation.y = PI / 2.0 if b.size.x > b.size.z else 0.0   # a model lying along X is turned onto Z
	turn.add_child(model)
	# _place sets the heading on the outer node: set on `turn` itself it undid the quarter turn, and the
	# trams ran sideways down the street (playtest 2026-09-13, Helsinki: "trams are driving perpendicular")
	var holder := Node3D.new()
	holder.add_child(turn)
	MeshMerge.set_range(holder, 800.0)
	return holder
