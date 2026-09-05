# Other players in the town as simple figures with a name plate, following the presence rows.
class_name PresenceFigures
extends Node3D

var world: Node3D
var _figures: Dictionary = {}   # player_id -> Node3D
var _targets: Dictionary = {}   # player_id -> Vector3


func setup(w: Node3D) -> void:
	world = w
	Ledger.presence_changed.connect(refresh)


func _process(delta: float) -> void:
	for id in _figures:
		var f: Node3D = _figures[id]
		if _targets.has(id):
			f.global_position = f.global_position.lerp(_targets[id], minf(1.0, delta * 6.0))


func refresh() -> void:
	var seen := {}
	var names := {}
	for p in Ledger.players():
		names[int(p.id)] = str(p.name)
	for pr in Ledger.presences():
		var id := int(pr.player_id)
		seen[id] = true
		var pos := Vector3(float(pr.x), 0.0, float(pr.z))
		if world and world.terrain and world.terrain.data:
			pos.y = world.terrain.data.get_height(pos)
		_targets[id] = pos
		if not _figures.has(id):
			var root := Node3D.new()
			root.name = "Player_%d" % id
			var body := MeshInstance3D.new()
			var capsule := CapsuleMesh.new()
			capsule.radius = 0.3
			capsule.height = 1.7
			body.mesh = capsule
			body.position.y = 0.85
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.2, 0.45, 0.85)
			body.material_override = m
			root.add_child(body)
			var plate := Label3D.new()
			plate.text = names.get(id, "?")
			plate.position.y = 2.1
			plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			plate.font_size = 48
			plate.pixel_size = 0.01
			plate.outline_size = 8
			root.add_child(plate)
			root.global_position = pos
			add_child(root)
			_figures[id] = root
		else:
			var plate: Label3D = _figures[id].get_child(1)
			plate.text = names.get(id, plate.text)
		_figures[id].rotation.y = float(pr.yaw)
	for id in _figures.keys():
		if not seen.has(id):
			_figures[id].queue_free()
			_figures.erase(id)
			_targets.erase(id)
