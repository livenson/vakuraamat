# The door of a real building: E outside steps in (the interior is generated on first entry, the
# exterior hides), E inside steps out. Label: the tenant, else the address.
class_name BuildingDoor
extends Interactable

var building: FootprintBuilding
var frame: Dictionary = {}
var leaf: SwingDoor


func setup(b: FootprintBuilding, f: Dictionary) -> void:
	building = b
	frame = f
	prompt_key = "UI_PROMPT_ENTER"
	var t: Vector3 = f.t
	var n: Vector3 = f.n
	position = f.pos + Vector3.UP * (float(f.height) / 2.0)
	basis = Basis(t.normalized(), Vector3.UP, n.normalized())
	# one body, a box each side of the wall (the ray finds the door from the street and from inside)
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	var box := BoxShape3D.new()
	box.size = Vector3(float(f.width) + 0.4, float(f.height), 0.5)
	for side in [1.0, -1.0]:
		var shape := CollisionShape3D.new()
		shape.shape = box
		shape.position = Vector3(0, 0, side * 0.35)
		body.add_child(shape)
	add_child(body)
	leaf = SwingDoor.new()
	leaf.name = "Leaf"
	leaf.setup(float(f.width), float(f.height), _leaf_material(b.kind == "dwelling"))
	leaf.position.z += 0.09   # just proud of the wall's own door quad
	add_child(leaf)


static var _mats: Dictionary = {}


static func release() -> void:
	_mats.clear()


## Wood for a dwelling, painted steel for everything else: two materials shared by every door.
static func _leaf_material(dwelling: bool) -> StandardMaterial3D:
	if not _mats.has(dwelling):
		var mat := StandardMaterial3D.new()
		if dwelling:
			mat.albedo_color = Color(0.32, 0.2, 0.12)
			mat.roughness = 0.6
		else:
			mat.albedo_color = Color(0.25, 0.28, 0.3)
			mat.metallic = 0.4
			mat.roughness = 0.35
		_mats[dwelling] = mat
	return _mats[dwelling]


func label() -> String:
	if building == null:
		return ""
	var names: Array = Tenants.active_names(Sites.pack_of(building), building.tunnus)
	if not names.is_empty():
		return str(names[0])
	return building.address if building.address != "" else tr("UI_BUILDING")


func prompt() -> String:
	var inside: bool = Interiors.instance != null and Interiors.instance.inside == building
	return tr("UI_PROMPT_LEAVE") if inside else tr("UI_PROMPT_ENTER")


func hover_text() -> String:
	if building == null:
		return ""
	var bits := []
	if building.purpose != "":
		bits.append(building.purpose)
	if building.year > 0:
		bits.append(tr("UI_IN_USE_SINCE") % building.year)
	var st := building.storeys()
	bits.append(tr("UI_FLOORS") % int(st.floors))
	return " · ".join(bits)


func interact(player: Node3D) -> void:
	if leaf and not leaf.is_open:
		leaf.open(player.global_position)
		await get_tree().create_timer(0.35).timeout
	if Interiors.instance and is_instance_valid(building):
		Interiors.instance.toggle(building, player)
