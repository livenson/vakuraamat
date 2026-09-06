# One ambient traveller on the road graph: a walker, a cyclist, a car or a horse cart. No physics:
# it follows the edge polyline at its lane offset, sits on the terrain, slows behind the agent ahead
# and picks another edge at each node. TrafficSystem spawns and removes them around the player.
class_name TrafficAgent
extends Node3D

const FIGURES := ["res://assets/models/figures/figure_stand.glb", "res://assets/models/figures/figure_holding.glb"]
const CLOTHES := [Color(0.45, 0.5, 0.62), Color(0.7, 0.35, 0.3), Color(0.33, 0.36, 0.5), Color(0.28, 0.28, 0.3), Color(0.55, 0.45, 0.3), Color(0.8, 0.75, 0.6), Color(0.2, 0.45, 0.35)]
const CAR_PAINT := [Color(0.85, 0.85, 0.87), Color(0.15, 0.15, 0.17), Color(0.5, 0.52, 0.55), Color(0.55, 0.12, 0.12), Color(0.15, 0.25, 0.5), Color(0.75, 0.6, 0.2)]
const LANES := {"walker": "side", "bike": "edge", "car": "lane", "cart": "lane", "dog": "side", "cat": "side"}   # where on the road

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
	speed = {"walker": rng.randf_range(1.1, 1.7), "bike": rng.randf_range(4.0, 6.0), "car": rng.randf_range(7.0, 12.0), "cart": rng.randf_range(1.6, 2.4),
		"dog": rng.randf_range(1.2, 2.2), "cat": rng.randf_range(0.5, 0.9)}[kind]
	allowed = {"walker": ["path", "trail", "street", "road"], "bike": ["path", "street", "road", "trail"], "car": ["street", "road"], "cart": ["road", "street", "trail"],
		"dog": ["path", "trail", "street"], "cat": ["path", "trail"]}[kind]
	_terrain = GameState.world.terrain if GameState.world else null
	_lateral_for_edge()
	match kind:
		"walker":
			_body = _make_walker()
		"dog", "cat":
			_body = _make_animal(kind)
		"bike":
			_body = build_bike(true, rng, CLOTHES[rng.randi() % CLOTHES.size()])
			for r in _body.find_children("*", "HumanFigure", true, false):
				_rider = r
			for w in _body.find_children("Wheel", "", true, false):
				_wheels.append(w)
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
	var min_gap: float = {"walker": 1.5, "bike": 4.0, "car": 9.0, "cart": 5.0, "dog": 1.2, "cat": 1.0}[kind]
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
	elif (kind == "dog" or kind == "cat") and _body:
		var trot := _speed_now / maxf(speed, 0.1)
		_body.position.y = absf(sin(_t * 9.0)) * 0.03 * trot   # a trot: quick small bounces
		_body.rotation.x = sin(_t * 9.0) * 0.04 * trot
	for w in _wheels:
		w.rotate_object_local(Vector3.RIGHT, -_speed_now * delta / 0.32)   # roughly a 0.3 m wheel radius
	if kind == "cyclist" and _rider:
		_rider.pedal_phase += _speed_now * delta * TAU / 4.5   # one crank turn per 4.5 m
		if _body.has_meta("crank"):
			var crank: Node3D = _body.get_meta("crank")
			crank.rotation.x = -_rider.pedal_phase


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


## A dog (pug or beagle, 0.4 m at the shoulder) or a cat (0.3 m): Poly Pizza models, see THIRD_PARTY.md.
func _make_animal(which: String) -> Node3D:
	var names: Array = ["pug", "beagle"] if which == "dog" else ["cat"]
	var path := "res://assets/vendor/polypizza/%s.glb" % names[rng.randi() % names.size()]
	if not ResourceLoader.exists(path):
		return _make_walker()
	var model: Node3D = (load(path) as PackedScene).instantiate()
	var b: AABB = Interiors._bounds(model)
	var k := (0.42 if which == "dog" else 0.3) / maxf(b.size.y, 0.001)
	var holder := Node3D.new()
	model.scale = Vector3.ONE * k
	model.position = Vector3(-(b.position.x + b.size.x * 0.5) * k, -b.position.y * k, -(b.position.z + b.size.z * 0.5) * k)
	var turn := Node3D.new()
	turn.rotation.y = PI if b.size.z >= b.size.x else PI / 2.0   # the long axis along local Z, nose towards -Z
	turn.add_child(model)
	holder.add_child(turn)
	return holder


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


## A cylinder from `a` to `b`.
static func _tube(parent: Node3D, a: Vector3, b: Vector3, radius: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = a.distance_to(b)
	cm.radial_segments = 8
	mi.mesh = cm
	mi.material_override = mat
	mi.position = (a + b) * 0.5
	var dir := (b - a).normalized()
	if absf(dir.dot(Vector3.UP)) < 0.999:
		mi.rotation = Basis(Vector3.UP.cross(dir).normalized(), acos(clampf(dir.dot(Vector3.UP), -1.0, 1.0))).get_euler()
	parent.add_child(mi)
	return mi


## A spoked wheel at `axle`, spinning about its local X (the axle): tyre, rim, hub and spokes.
static func _bike_wheel(axle: Vector3, chrome: Material, rubber: Material) -> Node3D:
	var wheel := Node3D.new()
	wheel.name = "Wheel"
	wheel.position = axle
	var tyre := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.305
	tm.outer_radius = 0.345
	tm.rings = 28
	tm.ring_segments = 8
	tyre.mesh = tm
	tyre.material_override = rubber
	tyre.rotation.z = PI / 2.0
	wheel.add_child(tyre)
	var rim := MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = 0.285
	rm.outer_radius = 0.31
	rm.rings = 28
	rm.ring_segments = 6
	rim.mesh = rm
	rim.material_override = chrome
	rim.rotation.z = PI / 2.0
	wheel.add_child(rim)
	var hub := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.03
	hm.bottom_radius = 0.03
	hm.height = 0.1
	hub.mesh = hm
	hub.material_override = chrome
	hub.rotation.z = PI / 2.0
	wheel.add_child(hub)
	for i in 16:
		var ang := i * TAU / 16.0
		var spoke := MeshInstance3D.new()
		var spm := CylinderMesh.new()
		spm.top_radius = 0.0025
		spm.bottom_radius = 0.0025
		spm.height = 0.27
		spm.radial_segments = 4
		spoke.mesh = spm
		spoke.material_override = chrome
		spoke.rotation.x = ang
		spoke.position = Vector3(0.02 if i % 2 == 0 else -0.02, cos(ang) * 0.155, sin(ang) * 0.155)
		wheel.add_child(spoke)
	return wheel


## The crank at the bottom bracket: axle, chainring, two arms and pedals, turned about local X.
static func _bike_crank(bb: Vector3, chrome: Material, rubber: Material) -> Node3D:
	var crank := Node3D.new()
	crank.name = "Crank"
	crank.position = bb
	var axle := MeshInstance3D.new()
	var am := CylinderMesh.new()
	am.top_radius = 0.012
	am.bottom_radius = 0.012
	am.height = 0.2
	axle.mesh = am
	axle.material_override = chrome
	axle.rotation.z = PI / 2.0
	crank.add_child(axle)
	var ring := MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = 0.075
	rm.outer_radius = 0.09
	rm.rings = 24
	rm.ring_segments = 4
	ring.mesh = rm
	ring.material_override = chrome
	ring.rotation.z = PI / 2.0
	ring.position.x = 0.06
	crank.add_child(ring)
	for side in [-1.0, 1.0]:
		var arm := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.02, 0.17, 0.025)
		arm.mesh = bm
		arm.material_override = chrome
		arm.position = Vector3(side * 0.1, side * 0.085, 0)
		crank.add_child(arm)
		var pedal := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.1, 0.02, 0.07)
		pedal.mesh = pm
		pedal.material_override = rubber
		pedal.position = Vector3(side * 0.16, side * 0.17, 0)
		crank.add_child(pedal)
	return crank


## A bicycle, with or without a rider. Also used for the player's parked bike. A diamond frame of
## tubes, spoked wheels with tyres and rims, a crank with pedals (meta "crank": the agent turns it
## with the rider's pedalling), gloss paint and chrome. Built with the handlebar at +Z.
static func build_bike(with_rider: bool, r: RandomNumberGenerator, clothes: Color) -> Node3D:
	if not with_rider and ResourceLoader.exists(BIKE_MODEL):
		# the parked bike and the mounted view: the Poly Pizza bicycle (Poly by Google, CC BY 3.0), 1.8 m long
		var holder := Node3D.new()
		var model: Node3D = (load(BIKE_MODEL) as PackedScene).instantiate()
		var b: AABB = Interiors._bounds(model)
		var k := 1.8 / maxf(maxf(b.size.x, b.size.z), 0.001)
		model.scale = Vector3.ONE * k
		model.position = Vector3(-(b.position.x + b.size.x * 0.5) * k, -b.position.y * k, -(b.position.z + b.size.z * 0.5) * k)
		if b.size.x > b.size.z:
			model.rotation.y = PI / 2.0
		holder.add_child(model)
		return holder
	var root := Node3D.new()
	var paint := StandardMaterial3D.new()
	paint.albedo_color = [Color(0.12, 0.12, 0.14), Color(0.62, 0.1, 0.1), Color(0.15, 0.32, 0.6), Color(0.85, 0.85, 0.82), Color(0.2, 0.45, 0.3), Color(0.9, 0.55, 0.15)][r.randi() % 6]
	paint.metallic = 0.35
	paint.roughness = 0.3
	var chrome := StandardMaterial3D.new()
	chrome.albedo_color = Color(0.8, 0.8, 0.82)
	chrome.metallic = 0.9
	chrome.roughness = 0.25
	var rubber := StandardMaterial3D.new()
	rubber.albedo_color = Color(0.06, 0.06, 0.06)
	rubber.roughness = 0.95
	var leather := StandardMaterial3D.new()
	leather.albedo_color = Color(0.16, 0.11, 0.08)
	leather.roughness = 0.7
	# the frame's points (x across, y up, z forward)
	var bb := Vector3(0, 0.29, -0.06)
	var ht := Vector3(0, 0.92, 0.40)
	var hb := Vector3(0, 0.70, 0.46)
	var st := Vector3(0, 0.88, -0.32)
	var ra := Vector3(0, 0.34, -0.53)
	var fa := Vector3(0, 0.34, 0.52)
	_tube(root, ht, st, 0.018, paint)                      # top tube
	_tube(root, hb, bb, 0.02, paint)                       # down tube
	_tube(root, bb, st, 0.018, paint)                      # seat tube
	_tube(root, hb - Vector3(0, 0.02, 0.01), ht + Vector3(0, 0.04, -0.01), 0.024, paint)   # head tube
	for x in [-0.045, 0.045]:
		_tube(root, bb + Vector3(x, 0, 0), ra + Vector3(x, 0, 0), 0.01, paint)     # chain stays
		_tube(root, st + Vector3(x, 0, 0), ra + Vector3(x, 0, 0), 0.01, paint)     # seat stays
		_tube(root, hb + Vector3(x, 0, 0.02), fa + Vector3(x, 0, 0), 0.011, paint)  # fork blades
	_tube(root, st, st + Vector3(0, 0.1, -0.03), 0.014, chrome)                   # seat post
	_tube(root, ht + Vector3(0, 0.04, 0), Vector3(0, 0.99, 0.33), 0.014, chrome)  # stem
	_tube(root, Vector3(-0.28, 0.99, 0.31), Vector3(0.28, 0.99, 0.31), 0.012, chrome)   # handlebar
	for x in [-1.0, 1.0]:
		_tube(root, Vector3(x * 0.28, 0.99, 0.31), Vector3(x * 0.28, 0.99, 0.22), 0.016, rubber)   # grips
	var saddle := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.15, 0.05, 0.27)
	saddle.mesh = sm
	saddle.material_override = leather
	saddle.position = st + Vector3(0, 0.12, -0.06)
	root.add_child(saddle)
	root.add_child(_bike_wheel(fa, chrome, rubber))
	root.add_child(_bike_wheel(ra, chrome, rubber))
	var crank := _bike_crank(bb, chrome, rubber)
	root.add_child(crank)
	root.set_meta("crank", crank)
	root.rotation.y = PI   # built with the handlebar at +Z; agents and the mounted player face -Z
	if with_rider and HumanFigure.available():
		var rider := HumanFigure.make(r, 2026)
		rider.pose = "pedal"
		rider.position = Vector3(0, 0.12, -0.38)  # hips over the saddle once the legs fold forward and the lean is on
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


const BIKE_MODEL := "res://assets/vendor/polypizza/bicycle.glb"
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
