# Root of a layer scene: the pack's props, buildings, parcels, roads and traffic. Children are
# authored at y 0 and snapped to the ground on first activation; window panes light up at night.
class_name EraController
extends Node3D

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
		if c is Node3D and not c.has_meta("no_snap"):
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
func _collect_windows() -> void:
	for mi in find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			var m: Material = mi.mesh.surface_get_material(si)
			if m is StandardMaterial3D and m.resource_name == "Window":
				var w: StandardMaterial3D = m.duplicate()
				w.roughness = 0.06
				w.metallic = 0.2
				w.metallic_specular = 0.9
				w.emission_enabled = true
				w.emission = Color(1.0, 0.72, 0.4)
				w.emission_energy_multiplier = 0.0
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
