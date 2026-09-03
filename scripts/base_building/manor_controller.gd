# Lives in an era layer at the manor's position. Shows what has been built, offers the
# build menu when interacted with, and spawns structures as they are built.
class_name ManorController
extends Interactable

@export var manor_id := ""

var manor: ManorDefinition
var _built_nodes: Dictionary = {}


func _ready() -> void:
	manor = Manors.manors.get(manor_id)
	prompt_key = "BUILD_PROMPT"
	label_key = manor.display_name_key if manor else ""
	EventBus.flag_changed.connect(func(_f, _v): _refresh())
	Manors.structure_built.connect(func(mid, _sid): if mid == manor_id: _refresh())
	_refresh()


func _process(_delta: float) -> void:
	if manor and Manors.built_at(manor.id).size() != _built_nodes.size():
		_refresh()


func _refresh() -> void:
	if manor == null:
		return
	for sid in Manors.built_at(manor.id):
		if not _built_nodes.has(sid):
			_spawn(Manors.structures[sid])


func _spawn(s: StructureDefinition) -> void:
	var box := CSGBox3D.new()
	box.size = s.size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = s.color
	mat.roughness = 0.9
	box.material = mat
	box.position = Vector3(s.offset.x, s.size.y / 2, s.offset.y)
	add_child(box)
	var roof := CSGBox3D.new()
	roof.size = Vector3(s.size.x + 0.6, 0.3, s.size.z + 0.6)
	var rm := StandardMaterial3D.new()
	rm.albedo_color = s.color.darkened(0.35)
	roof.material = rm
	roof.position = Vector3(s.offset.x, s.size.y + 0.15, s.offset.y)
	add_child(roof)
	_built_nodes[s.id] = box


func hover_text() -> String:
	if manor == null:
		return ""
	if not Manors.is_unlocked(manor):
		return tr("BUILD_LOCKED")
	return tr("BUILD_LEVEL") % [tr(manor.display_name_key), Manors.development_level(manor.id), manor.structures.size()]


func interact(_player: Node3D) -> void:
	if manor == null or not Manors.is_unlocked(manor):
		EventBus.notice.emit(tr("BUILD_LOCKED"))
		return
	if GameState.world and GameState.world.ui.has_method("open_build"):
		GameState.world.ui.open_build(self)
