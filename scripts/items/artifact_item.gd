# The only kind of item that crosses eras. Each has exactly one scripted delivery.
class_name ArtifactItem
extends ItemBase

@export var can_cross_eras: bool = true
@export var linked_consequence_point_id: String
@export var valid_delivery_target: String    # NPC id or location id
@export var origin_era: String               # where it is found
@export var delivery_era: String             # where it is delivered
