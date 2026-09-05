# Something to read: E opens a sheet of the book with a title and a text (a notice board, a
# register extract, a lease). After Cogito's readable component (Philip Drobar, MIT; see THIRD_PARTY.md).
class_name Readable
extends Interactable

var title := ""
var text := ""


## A reachable board: a box collider of `size` on the interact layer, centred on this node.
func setup(p_title: String, p_text: String, size: Vector3) -> void:
	title = p_title
	text = p_text
	prompt_key = "UI_PROMPT_READ"
	label_key = ""
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)


func label() -> String:
	return title


func interact(_player: Node3D) -> void:
	var world: Node = GameState.world
	if world and "ui" in world and world.ui and world.ui.has_method("show_sheet"):
		world.ui.show_sheet(title, text)
