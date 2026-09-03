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
	for c in get_children():
		if c is Node3D:
			var h := terrain.data.get_height(c.global_position)
			if not is_nan(h):
				c.global_position.y = h + float(c.get_meta("lift", 0.0))
