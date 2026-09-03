# One huntable species. Spawn placement is driven by the land-cover classes in the
# terrain control map (from the Maa-amet orthophoto + nDSM), not by hand-placed points.
class_name AnimalDefinition
extends Resource

@export var id: String
@export var display_name_key: String
@export var body_color: Color = Color(0.5, 0.4, 0.3)
@export var body_size: Vector3 = Vector3(0.4, 0.4, 0.8)   # capsule-ish body extents
@export var spawn_classes: Array[int] = [2]              # control-map ids: 0 meadow 1 field 2 canopy 4 soil
@export var yield_item_id: String
@export var flee_behavior: bool = true
@export var flee_distance: float = 18.0
@export var speed: float = 3.5
@export var hunt_range: float = 7.0
@export var group_size: int = 1
@export var eras: Array[String] = []
