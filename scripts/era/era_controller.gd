# Root of an era's layer scene: props, NPCs, pickups for one era. Activation refreshes
# every Conditional child from TimelineState (no simulation, just flag reads).
class_name EraController
extends Node3D

@export var era_id := ""

var _snapped := false


func activate() -> void:
	visible = true
	if not _snapped:
		_snap_children()
		_snapped = true
	process_mode = Node.PROCESS_MODE_INHERIT
	for c in find_children("*", "Conditional", true, false):
		c.refresh()
	for c in find_children("*", "Pickup", true, false):
		c.visible = not TimelineState.has_flag(c.taken_flag())


func deactivate() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED


## Children are authored at y = 0 with their origin at the base; drop them onto the terrain.
func _snap_children() -> void:
	var terrain: Terrain3D = GameState.world.terrain if GameState.world else null
	if terrain == null:
		return
	_snap_list(get_children(), terrain)
	# one level deeper for container groups (e.g. the village massing)
	for c in get_children():
		if c is Node3D and c.get_child_count() > 0 and c.name == "Village":
			_snap_list(c.get_children(), terrain)


func _snap_list(nodes: Array, terrain: Terrain3D) -> void:
	for c in nodes:
		if c is Node3D:
			var h := terrain.data.get_height(c.global_position)
			if c.has_meta("footprint"):
				# buildings: sit on the lowest corner so nothing hangs in the air; the skirt fills the rest
				var fp: Vector2 = c.get_meta("footprint")
				var basis: Basis = c.global_transform.basis
				for sx in [-0.5, 0.5]:
					for sz in [-0.5, 0.5]:
						var corner: Vector3 = c.global_position + basis * Vector3(sx * fp.x, 0, sz * fp.y)
						var hc := terrain.data.get_height(corner)
						if not is_nan(hc):
							h = hc if is_nan(h) else minf(h, hc)
			if not is_nan(h):
				c.global_position.y = h + float(c.get_meta("lift", 0.0))
