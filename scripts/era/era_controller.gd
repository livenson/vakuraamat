# Root of a layer scene: the pack's props, buildings, parcels, roads and traffic. Children are
# authored at y 0 and snapped to the ground on first activation; window panes light up at night.
class_name EraController
extends Node3D

# The heavy groups: their members (a real building builds its mesh and collision, a parcel kit its
# pieces) enter the tree a few milliseconds a frame instead of all in one, so the layer can stand
# and be walked in while the town fills in around the player.
const STAGGERED := ["Buildings", "Parcels"]
const FILL_BUDGET_USEC := 8000          # a tile filling while the player walks: keep the frame smooth
const ARRIVAL_BUDGET_USEC := 30000      # the layer the player is standing in: fill it fast (30 fps for a few seconds)

signal filled   # every staggered member is in the tree

@export var era_id := ""

var _snapped := false
var _window_mats: Array[StandardMaterial3D] = []
var _windows_lit := false


func activate() -> void:
	visible = true
	if not _snapped:
		_snap_children()
		_collect_windows()
		_snapped = true
	process_mode = Node.PROCESS_MODE_INHERIT


func deactivate() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED


## Pull the heavy groups' members out before the scene enters the tree, so the layer's own _ready
## costs a few milliseconds; fill_pending puts them back. Returns the pending [group, member] pairs.
func detach_heavy() -> Array:
	var pending: Array = []
	for group in get_children():
		if group.name in STAGGERED:
			for m in group.get_children():
				group.remove_child(m)
				# A detached member still points at the scene root as its owner, and adding it back
				# warns that the owner is no longer its ancestor. Nothing reads owner at runtime
				# (it is for packing a scene, which never happens here), so drop it.
				m.owner = null
				pending.append([group, m])
	return pending


## Put the pending members back over the following frames, the ones nearest `near` (a global
## position) first, each snapped onto the terrain as it enters. The rest are freed if the layer
## goes away meanwhile. Emits `filled` when the last one is in.
func fill_pending(pending: Array, near: Vector3, budget := FILL_BUDGET_USEC) -> void:
	var origin := to_local(near)
	pending.sort_custom(func(a, b): return _near_sq(a[1], origin) < _near_sq(b[1], origin))
	var terrain: Terrain3D = GameState.world.terrain if GameState.world else null
	var t0 := Time.get_ticks_usec()
	for i in pending.size():
		if not is_inside_tree():
			for j in range(i, pending.size()):
				pending[j][1].free()   # the layer was unloaded meanwhile
			return
		var t_m := Time.get_ticks_usec()
		pending[i][0].add_child(pending[i][1])
		if _snapped and terrain:
			_snap_one(pending[i][1], terrain)
		if Time.get_ticks_usec() - t_m > 25000:
			PerfLog.mark("slow member %s/%s %d ms" % [pending[i][0].name, pending[i][1].name, (Time.get_ticks_usec() - t_m) / 1000])
		if Time.get_ticks_usec() - t0 > budget:
			await get_tree().process_frame
			t0 = Time.get_ticks_usec()
	if is_inside_tree():
		PerfLog.mark("era %s filled (%d members)" % [era_id, pending.size()])
		filled.emit()


func _near_sq(m: Node, origin: Vector3) -> float:
	return (m.position - origin).length_squared() if m is Node3D else INF


## Children are authored at y = 0 with their origin at the base; drop them onto the terrain.
func _snap_children() -> void:
	var terrain: Terrain3D = GameState.world.terrain if GameState.world else null
	if terrain == null:
		return
	# container groups (the village massing, the real footprints, the parcel kits) stay at y 0 and
	# their children snap one by one; kits that place their pieces on the ground carry no_snap
	var containers := ["Village", "Buildings", "Parcels"]
	_snap_list(get_children().filter(func(c): return not (c.name in containers)), terrain)
	for c in get_children():
		if c is Node3D and c.get_child_count() > 0 and c.name in containers:
			_snap_list(c.get_children(), terrain)


func _snap_list(nodes: Array, terrain: Terrain3D) -> void:
	for c in nodes:
		_snap_one(c, terrain)


func _snap_one(c: Node, terrain: Terrain3D) -> void:
	if not (c is Node3D) or c.has_meta("no_snap"):
		return
	var h := terrain.data.get_height(c.global_position)
	if c.has_meta("footprint"):
		# buildings: sit on the lowest corner so nothing hangs in the air; the skirt fills the rest.
		# A real footprint uses its own outline (the bounding box of an L-shape reaches ground
		# outside the walls and sank the house); massing uses the box corners.
		var corners: Array = []
		var fb: Node = c.get_node_or_null("Footprint")   # the real building under its group
		if fb is Node3D and "polygon" in fb and fb.polygon.size() >= 3:
			for p in fb.polygon:
				corners.append(fb.to_global(Vector3(p.x, 0.0, p.y)))
		else:
			var fp: Vector2 = c.get_meta("footprint")
			var basis: Basis = c.global_transform.basis
			for sx in [-0.5, 0.5]:
				for sz in [-0.5, 0.5]:
					corners.append(c.global_position + basis * Vector3(sx * fp.x, 0, sz * fp.y))
		for corner in corners:
			var hc := terrain.data.get_height(corner)
			if not is_nan(hc):
				h = hc if is_nan(h) else minf(h, hc)
	if not is_nan(h):
		c.global_position.y = h + float(c.get_meta("lift", 0.0))


## Window panes: reflective glass by day, warm glow after dark (called by the world with the hour).
var windows_collected := false


func _collect_windows() -> void:
	windows_collected = true
	for mi in find_children("*", "MeshInstance3D", true, false):
		register_windows(mi)


## A mesh's "Window" surfaces get the lit material; buildings built after the collection (their
## geometry comes from a worker thread) call this when their mesh stands.
func register_windows(mi: MeshInstance3D) -> void:
	if mi.mesh == null:
		return
	for si in mi.mesh.get_surface_count():
		var m: Material = mi.mesh.surface_get_material(si)
		if m is StandardMaterial3D and m.resource_name == "Window":
			var w: StandardMaterial3D = m.duplicate()   # keeps the glass look (FootprintBuilding._window_material)
			w.emission_enabled = true
			w.emission = Color(1.0, 0.72, 0.4)
			w.emission_energy_multiplier = _window_mats[0].emission_energy_multiplier if not _window_mats.is_empty() else 0.0
			mi.set_surface_override_material(si, w)
			_window_mats.append(w)


static var current_hour := 12.0


func set_hour(hour: float) -> void:
	current_hour = hour
	for b in get_tree().get_nodes_in_group("neon_open"):
		b.set_open_hour(hour)
	var lit := hour < 6.5 or hour > 18.5
	if lit == _windows_lit:
		return
	_windows_lit = lit
	for w in _window_mats:
		w.emission_energy_multiplier = 2.5 if lit else 0.0
	for rn in find_children("*", "RoadNetwork", true, false):
		rn.set_lit(lit)
