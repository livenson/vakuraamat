# One ambient traveller on the road graph: a walker, a cyclist, a car or a horse cart. No physics:
# it follows the edge polyline at its lane offset, sits on the terrain, slows behind the agent ahead
# and picks another edge at each node. TrafficSystem spawns and removes them around the player.
class_name TrafficAgent
extends Node3D

const FIGURES := ["res://assets/models/figures/figure_stand.glb", "res://assets/models/figures/figure_holding.glb"]
const CLOTHES := [Color(0.45, 0.5, 0.62), Color(0.7, 0.35, 0.3), Color(0.33, 0.36, 0.5), Color(0.28, 0.28, 0.3), Color(0.55, 0.45, 0.3), Color(0.8, 0.75, 0.6), Color(0.2, 0.45, 0.35)]
const CAR_PAINT := [Color(0.85, 0.85, 0.87), Color(0.15, 0.15, 0.17), Color(0.5, 0.52, 0.55), Color(0.55, 0.12, 0.12), Color(0.15, 0.25, 0.5), Color(0.75, 0.6, 0.2)]
const LANES := {"walker": "side", "bike": "edge", "car": "lane", "cart": "lane"}   # where on the road

var kind := "walker"
var speed := 1.4
var graph: RoadGraph
var edge: Dictionary = {}
var s := 0.0
var forward := true
var lateral := 0.0               # metres to the right of the travel direction
var allowed: Array = []
var rng := RandomNumberGenerator.new()
var _body: Node3D
var _rider: HumanFigure = null   # the cyclist's figure (pedals with the speed)
var _year := 2026
var _wheels: Array[Node3D] = []
var _t := 0.0
var _speed_now := 0.0
var _terrain: Terrain3D


func setup(g: RoadGraph, k: String, e: Dictionary, start_s: float, fwd: bool, seed_value: int, year: int) -> void:
	_year = year
	graph = g
	kind = k
	edge = e
	s = start_s
	forward = fwd
	rng.seed = seed_value
	speed = {"walker": rng.randf_range(1.1, 1.7), "bike": rng.randf_range(4.0, 6.0), "car": rng.randf_range(7.0, 12.0), "cart": rng.randf_range(1.6, 2.4)}[kind]
	allowed = {"walker": ["path", "trail", "street", "road"], "bike": ["path", "street", "road", "trail"], "car": ["street", "road"], "cart": ["road", "street", "trail"]}[kind]
	_terrain = GameState.world.terrain if GameState.world else null
	_lateral_for_edge()
	match kind:
		"walker":
			_body = _make_walker()
		"bike":
			_body = build_bike(true, rng, CLOTHES[rng.randi() % CLOTHES.size()])
			for r in _body.find_children("*", "HumanFigure", true, false):
				_rider = r
		"car":
			_body = _make_car(year)
		"cart":
			_body = _make_cart()
	add_child(_body)
	_place(0.0)


func _lateral_for_edge() -> void:
	var w: float = maxf(float(edge.width), 2.0)
	match LANES[kind]:
		"side":
			lateral = w / 2.0 + 0.6 if edge.kind in ["street", "road"] else rng.randf_range(-w / 4.0, w / 4.0)
		"edge":
			lateral = w / 2.0 - 0.6 if edge.kind in ["street", "road"] else rng.randf_range(-w / 4.0, w / 4.0)
		"lane":
			lateral = w / 4.0   # right-hand traffic


## Distance to the next agent ahead on this edge going the same way, or INF.
func gap_ahead(others: Array) -> float:
	var best := INF
	for o in others:
		if o == self or o.edge.id != edge.id or o.forward != forward:
			continue
		var d: float = (o.s - s) if forward else (s - o.s)
		if d > 0.0 and d < best:
			best = d
	return best


func advance(delta: float, others: Array) -> void:
	var gap := gap_ahead(others)
	var want := speed
	var min_gap: float = {"walker": 1.5, "bike": 4.0, "car": 9.0, "cart": 5.0}[kind]
	if gap < min_gap:
		want = 0.0
	elif gap < min_gap * 2.5:
		want = speed * (gap - min_gap) / (min_gap * 1.5)
	_speed_now = lerpf(_speed_now, want, minf(1.0, delta * 3.0))
	s += _speed_now * delta * (1.0 if forward else -1.0)
	if s > edge.length or s < 0.0:
		var nxt := graph.next_edge(edge, forward, allowed, rng)
		if nxt.is_empty():
			queue_free()
			return
		edge = nxt.edge
		forward = nxt.forward
		s = 0.0 if forward else edge.length
		_lateral_for_edge()
	_t += delta
	_place(delta)


func _place(delta: float) -> void:
	var d := graph.dir_at(edge, s, forward)
	var right := Vector2(-d.y, d.x)
	var p := graph.point_at(edge, s) + right * lateral
	var parent := get_parent() as Node3D
	var gp := parent.to_global(Vector3(p.x, 0.0, p.y)) if parent else Vector3(p.x, 0.0, p.y)
	var h: float = _terrain.data.get_height(gp) if _terrain else 0.0
	if is_nan(h):
		h = global_position.y
	global_position = Vector3(gp.x, h + 0.1, gp.z)
	if d.length_squared() > 0.0:
		rotation.y = atan2(-d.x, -d.y)
	if kind == "walker" and _body:
		if _body is HumanFigure:
			_body.set_walking(_speed_now > 0.05, _speed_now / 1.4)
		else:
			_body.position.y = absf(sin(_t * 6.0)) * 0.05 * (_speed_now / maxf(speed, 0.1))
			_body.rotation.z = sin(_t * 6.0) * 0.03
	for w in _wheels:
		w.rotate_object_local(Vector3.RIGHT, -_speed_now * delta / 0.32)   # roughly a 0.3 m wheel radius
	if kind == "cyclist" and _rider:
		_rider.pedal_phase += _speed_now * delta * TAU / 4.5   # one crank turn per 4.5 m


# ---------------------------------------------------------------- bodies
func _clothes(fig: Node, col: Color) -> void:
	for mi in fig.find_children("*", "MeshInstance3D", true, false):
		for si in mi.mesh.get_surface_count():
			var m: Material = mi.mesh.surface_get_material(si)
			if m and m.resource_name == "Clothes":
				var mat := StandardMaterial3D.new()
				mat.albedo_color = col
				mat.roughness = 0.9
				mi.set_surface_override_material(si, mat)


func _make_walker() -> Node3D:
	if HumanFigure.available():
		return HumanFigure.make(rng, _year)
	var fig: Node3D = load(FIGURES[rng.randi() % FIGURES.size()]).instantiate()
	var k := rng.randf_range(0.9, 1.05)
	fig.scale = Vector3(k, k, k)
	_clothes(fig, CLOTHES[rng.randi() % CLOTHES.size()])
	return fig


static func _box(parent: Node3D, size: Vector3, pos: Vector3, col: Color, rough := 0.7) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.size = size
	b.position = pos
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = 0.2 if rough < 0.6 else 0.0
	b.material = m
	parent.add_child(b)
	return b


static func _wheel(parent: Node3D, radius: float, width: float, pos: Vector3) -> CSGCylinder3D:
	var c := CSGCylinder3D.new()
	c.radius = radius
	c.height = width
	c.sides = 14
	c.position = pos
	c.rotation.z = PI / 2.0
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.1, 0.1, 0.1)
	m.roughness = 0.9
	c.material = m
	parent.add_child(c)
	return c


## A bicycle, with or without a rider. Also used for the player's parked bike.
static func build_bike(with_rider: bool, r: RandomNumberGenerator, clothes: Color) -> Node3D:
	var root := Node3D.new()
	var paint: Color = [Color(0.1, 0.1, 0.12), Color(0.6, 0.1, 0.1), Color(0.15, 0.3, 0.55), Color(0.8, 0.8, 0.8)][r.randi() % 4]
	_wheel(root, 0.34, 0.04, Vector3(0, 0.34, 0.55))
	_wheel(root, 0.34, 0.04, Vector3(0, 0.34, -0.55))
	_box(root, Vector3(0.04, 0.04, 1.1), Vector3(0, 0.62, 0), paint, 0.4)          # top tube
	_box(root, Vector3(0.04, 0.5, 0.04), Vector3(0, 0.62, 0.45), paint, 0.4)        # head tube
	_box(root, Vector3(0.04, 0.5, 0.04), Vector3(0, 0.62, -0.35), paint, 0.4)       # seat tube
	_box(root, Vector3(0.45, 0.03, 0.03), Vector3(0, 0.95, 0.5), Color(0.2, 0.2, 0.2), 0.5)   # handlebar
	_box(root, Vector3(0.18, 0.05, 0.25), Vector3(0, 0.92, -0.35), Color(0.15, 0.1, 0.08))   # saddle
	root.rotation.y = PI   # built with the handlebar at +Z; agents and the mounted player face -Z
	if with_rider and HumanFigure.available():
		var rider := HumanFigure.make(r, 2026)
		rider.pose = "pedal"
		rider.position = Vector3(0, 0.1, -0.42)   # hips over the saddle once the legs fold forward and the lean is on
		rider.rotation.y = 0.0                   # HumanFigure already faces the frame's front (+Z here)
		rider.rotation.x = 0.3                   # leaning onto the handlebar (pitch about the feet)
		root.add_child(rider)
	elif with_rider:
		var fig: Node3D = load(FIGURES[0]).instantiate()
		fig.position = Vector3(0, 0.5, -0.3)
		fig.scale = Vector3(0.95, 0.95, 0.95)
		root.add_child(fig)
		for mi in fig.find_children("*", "MeshInstance3D", true, false):
			for si in mi.mesh.get_surface_count():
				var m: Material = mi.mesh.surface_get_material(si)
				if m and m.resource_name == "Clothes":
					var mat := StandardMaterial3D.new()
					mat.albedo_color = clothes
					mi.set_surface_override_material(si, mat)
	return root


const CAR_KIT := "res://assets/vendor/kenney_car_kit/glb/"
const CAR_MODELS := ["sedan", "sedan", "sedan-sports", "hatchback-sports", "hatchback-sports", "suv", "suv-luxury", "van", "delivery", "taxi", "truck"]
const CAR_SCALE := 1.4   # the kit's sedan is 2.55 x 1.5 x 1.45 m: at 1.4 it is 3.6 m long and 2 m tall, a cartoon car that still fits the street


## A car from the Kenney Car Kit (CC0) when it is installed, else the box car. Pre-1950 cars are a
## sedan painted near black; later ones keep the kit's colours with a slight tint for variety.
func _make_car(year: int) -> Node3D:
	var name: String = "sedan" if year < 1950 else CAR_MODELS[rng.randi() % CAR_MODELS.size()]
	var path := CAR_KIT + name + ".glb"
	if not ResourceLoader.exists(path):
		return _make_box_car(year)
	var root := Node3D.new()
	var model: Node3D = load(path).instantiate()
	model.rotation.y = PI            # the kit's front is +Z; agents face -Z
	model.scale = Vector3.ONE * CAR_SCALE
	root.add_child(model)
	var tint := Color(0.12, 0.12, 0.13) if year < 1950 else Color(1, 1, 1).lerp(CAR_PAINT[rng.randi() % CAR_PAINT.size()], 0.25)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		if mi.name.begins_with("wheel"):
			_wheels.append(mi)
			continue
		for si in mi.mesh.get_surface_count():
			var m: Material = mi.mesh.surface_get_material(si)
			if m is BaseMaterial3D:
				var c: BaseMaterial3D = m.duplicate()
				c.albedo_color = c.albedo_color * tint
				c.roughness = 0.35
				mi.set_surface_override_material(si, c)
	return root


func _make_box_car(year: int) -> Node3D:
	var root := Node3D.new()
	var paint: Color = CAR_PAINT[rng.randi() % CAR_PAINT.size()] if year >= 1950 else Color(0.08, 0.08, 0.09)
	var glass := Color(0.15, 0.2, 0.25)
	if year < 1950:
		_box(root, Vector3(1.6, 0.6, 3.6), Vector3(0, 0.75, 0), paint, 0.35)
		_box(root, Vector3(1.5, 0.7, 1.7), Vector3(0, 1.35, -0.3), paint, 0.35)
		_box(root, Vector3(1.52, 0.35, 1.72), Vector3(0, 1.4, -0.3), glass, 0.2)
		for wpos in [Vector3(-0.8, 0.4, 1.2), Vector3(0.8, 0.4, 1.2), Vector3(-0.8, 0.4, -1.2), Vector3(0.8, 0.4, -1.2)]:
			_wheels.append(_wheel(root, 0.4, 0.18, wpos))
	else:
		var van := rng.randf() < 0.2
		_box(root, Vector3(1.8, 0.55, 4.3), Vector3(0, 0.6, 0), paint, 0.3)
		_box(root, Vector3(1.7, 0.6, 3.6 if van else 2.2), Vector3(0, 1.15, -0.3 if van else -0.2), paint, 0.3)
		_box(root, Vector3(1.72, 0.32, 3.62 if van else 2.22), Vector3(0, 1.2, -0.3 if van else -0.2), glass, 0.15)
		for wpos in [Vector3(-0.85, 0.32, 1.4), Vector3(0.85, 0.32, 1.4), Vector3(-0.85, 0.32, -1.4), Vector3(0.85, 0.32, -1.4)]:
			_wheels.append(_wheel(root, 0.32, 0.22, wpos))
	return root


func _make_cart() -> Node3D:
	var root := Node3D.new()
	var wood := Color(0.42, 0.3, 0.18)
	_box(root, Vector3(1.4, 0.4, 2.4), Vector3(0, 0.9, -0.6), wood)
	for x in [-0.8, 0.8]:
		_wheels.append(_wheel(root, 0.55, 0.08, Vector3(x, 0.55, -0.6)))
	_box(root, Vector3(0.06, 0.06, 2.2), Vector3(0.3, 0.75, 1.2), wood)   # shafts
	_box(root, Vector3(0.06, 0.06, 2.2), Vector3(-0.3, 0.75, 1.2), wood)
	var horse := Color(0.35, 0.22, 0.14)
	_box(root, Vector3(0.6, 0.65, 1.6), Vector3(0, 1.15, 2.4), horse)     # body
	_box(root, Vector3(0.3, 0.5, 0.5), Vector3(0, 1.7, 3.3), horse)       # neck
	_box(root, Vector3(0.28, 0.28, 0.6), Vector3(0, 1.85, 3.7), horse)    # head
	for lp in [Vector3(-0.2, 0.42, 1.8), Vector3(0.2, 0.42, 1.8), Vector3(-0.2, 0.42, 3.0), Vector3(0.2, 0.42, 3.0)]:
		_box(root, Vector3(0.12, 0.85, 0.12), lp, horse)
	var fig: Node3D = load(FIGURES[0]).instantiate()
	fig.position = Vector3(0, 1.1, 0.2)
	fig.scale = Vector3(0.9, 0.9, 0.9)
	root.add_child(fig)
	_clothes(fig, CLOTHES[rng.randi() % CLOTHES.size()])
	return root
