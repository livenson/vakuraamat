# Ambient traffic for an era layer: walkers, cyclists, cars (or carts in older years) on the road graph
# around the player. Density follows the era, the time of day and the amount of street nearby; nothing
# here touches game state. Placed by the "traffic" node of scenes.json.
class_name TrafficSystem
extends Node3D

@export var year := 2026
@export var density := 1.0            # agents per 100 m of nearby road at midday
@export var max_agents := 40
@export var spawn_min := 35.0
@export var spawn_max := 220.0
@export var despawn := 320.0

var graph: RoadGraph
var agents: Array[TrafficAgent] = []
var _timer := 0.0
var _first := true
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	graph = RoadGraph.from_pack()
	_rng.seed = hash(Sites.active) + year


## Share of each kind by era year.
func mix() -> Dictionary:
	if year < 1900:
		return {"walker": 0.7, "cart": 0.3}
	if year < 1950:
		return {"walker": 0.5, "bike": 0.3, "car": 0.08, "cart": 0.12}
	return {"walker": 0.35, "bike": 0.25, "car": 0.4}


## 0.15 at night, 1 by day, 1.4 in the commute peaks.
func time_factor() -> float:
	var world: Node = GameState.world
	var hour: float = world.sky.tod.current_time if world and world.sky and world.sky.tod else 12.0
	if hour < 5.5 or hour > 22.5:
		return 0.15
	if (hour >= 7.0 and hour <= 9.0) or (hour >= 16.0 and hour <= 19.0):
		return 1.4
	if hour < 7.0 or hour > 20.0:
		return 0.5
	return 1.0


func _physics_process(delta: float) -> void:
	if GameState.world == null or graph == null or graph.edges.is_empty() or not is_visible_in_tree():
		return
	var player: Node3D = GameState.world.player
	for a in agents:
		if is_instance_valid(a):
			a.advance(delta, agents)
	agents = agents.filter(func(a): return is_instance_valid(a))
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 1.0
	var centre := Vector2(player.global_position.x, player.global_position.z)
	for a in agents:
		if a.global_position.distance_to(player.global_position) > despawn:
			a.queue_free()
	agents = agents.filter(func(a): return is_instance_valid(a) and not a.is_queued_for_deletion())
	var near := graph.edges_near(centre, 0.0, spawn_max, ["street", "road", "path", "trail"])
	var metres := 0.0
	for id in near:
		metres += graph.edges[id].length
	var target := mini(max_agents, int(metres / 100.0 * density * time_factor()))
	# fill the whole target on the first tick (arrival, era switch), then trickle in
	var burst := target - agents.size() if _first else 3
	_first = false
	for _i in range(mini(burst, target - agents.size())):
		_spawn(centre)


func _spawn(centre: Vector2) -> void:
	var m := mix()
	var roll := _rng.randf()
	var kind := "walker"
	var acc := 0.0
	for k in m:
		acc += m[k]
		if roll <= acc:
			kind = k
			break
	var kinds: Array = {"walker": ["path", "trail", "street", "road"], "bike": ["path", "street", "road"], "car": ["street", "road"], "cart": ["road", "street", "trail"]}[kind]
	var candidates := graph.edges_near(centre, spawn_min, spawn_max, kinds)
	if candidates.is_empty():
		return
	var e: Dictionary = graph.edges[candidates[_rng.randi() % candidates.size()]]
	var a := TrafficAgent.new()
	add_child(a)
	a.setup(graph, kind, e, _rng.randf() * e.length, _rng.randf() < 0.5, _rng.randi(), year)
	agents.append(a)
