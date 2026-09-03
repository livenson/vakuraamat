# Something buildable at a manor. Costs are era-local items and money; the result is a
# box placed at an offset from the manor origin. Building never sets timeline flags.
class_name StructureDefinition
extends Resource

@export var id: String
@export var display_name_key: String
@export var description_key: String
@export var cost_items: Dictionary = {}     # item_id -> quantity
@export var cost_money: int = 0
@export var size: Vector3 = Vector3(4, 3, 4)
@export var offset: Vector2 = Vector2(8, 0)  # metres from the manor origin
@export var color: Color = Color(0.5, 0.4, 0.3)
@export var requires: String = ""            # another structure id that must exist first
