# The door of a real building: E outside steps in (the interior is generated on first entry, the
# exterior hides), E inside steps out. Label: the tenant, else the address.
class_name BuildingDoor
extends Interactable

var building: FootprintBuilding
var frame: Dictionary = {}


func setup(b: FootprintBuilding, f: Dictionary) -> void:
	building = b
	frame = f
	prompt_key = "UI_PROMPT_ENTER"
	var t: Vector3 = f.t
	var n: Vector3 = f.n
	position = f.pos + Vector3.UP * (float(f.height) / 2.0)
	basis = Basis(t.normalized(), Vector3.UP, n.normalized())
	for side in [1.0, -1.0]:
		var body := StaticBody3D.new()
		body.collision_layer = 2
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(float(f.width) + 0.4, float(f.height), 0.5)
		shape.shape = box
		shape.position = Vector3(0, 0, side * 0.35)
		body.add_child(shape)
		add_child(body)


func label() -> String:
	if building == null:
		return ""
	var names: Array = Ledger.tenants_of(building.tunnus).filter(func(x): return x.status == "R").map(func(x): return str(x.name)) if building.tunnus != "" else []
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
		bits.append(str(building.year))
	var st := building.storeys()
	bits.append(tr("UI_FLOORS") % int(st.floors))
	return " · ".join(bits)


func interact(player: Node3D) -> void:
	if Interiors.instance:
		Interiors.instance.toggle(building, player)
