# A real building answers to the crosshair on any wall: the hover line says what the register says
# (use, year, storeys), E opens its register sheet (use, materials, tenants, the plot's owner).
# Created by the Interactor on first hover; the door keeps its own Enter prompt.
class_name BuildingInfo
extends Interactable

var building: FootprintBuilding


func setup(b: FootprintBuilding) -> void:
	building = b
	prompt_key = "UI_PROMPT_EXAMINE" if b else ""


func label() -> String:
	if building == null:
		return tr("UI_BUILDING")
	var names: Array = Tenants.active_names(Sites.pack_of(building), building.tunnus)
	if not names.is_empty():
		return str(names[0]) + ("  +%d" % (names.size() - 1) if names.size() > 1 else "")
	return building.address if building.address != "" else tr("UI_BUILDING")


func hover_text() -> String:
	if building == null:
		return tr("UI_NO_REGISTER")   # laser massing: a shape the register does not know
	var bits: Array[String] = []
	if building.purpose != "":
		bits.append(building.purpose)
	if building.year > 0:
		bits.append(str(building.year))
	bits.append(tr("UI_FLOORS") % int(building.storeys().floors))
	return " · ".join(bits)


func prompt() -> String:
	return "" if building == null else tr(prompt_key)


func interact(_player: Node3D) -> void:
	if building == null:
		return
	var world: Node = GameState.world
	if world and "ui" in world and world.ui and world.ui.has_method("show_sheet") and Interiors.instance:
		world.ui.show_sheet(building.address if building.address != "" else tr("UI_BUILDING"), Interiors.register_sheet(building))
