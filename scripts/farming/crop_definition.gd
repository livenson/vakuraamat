# One crop. Growth is measured in game hours from the shared clock; stages are shown
# by scaling the plot's stalk meshes. Farming is era-local and never touches the timeline.
class_name CropDefinition
extends Resource

@export var id: String
@export var display_name_key: String
@export var seed_item_id: String
@export var yield_item_id: String
@export var yield_quantity: int = 3
@export var growth_time_hours: float = 6.0      # game hours from planting to ready
@export var stalk_color: Color = Color(0.35, 0.6, 0.2)
@export var ripe_color: Color = Color(0.85, 0.7, 0.3)
@export var stalk_height: float = 0.9
@export var eras: Array[String] = []             # eras where this crop can be planted
