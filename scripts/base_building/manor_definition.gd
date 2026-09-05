# A real, cadastrally mapped place the player can develop. The parcel id is the Land
# Board's cadastral unit number (kataster:ky_kehtiv "tunnus"), looked up at the position.
class_name ManorDefinition
extends Resource

@export var id: String
@export var display_name_key: String
@export var era_id: String
@export var cadastral_parcel_id: String
@export var location_terrain_tile: String = ""      # optional note; the site manifest names the tile
@export var position: Vector2                      # tile metres (x east, z south)
@export var unlock_condition_flag: String = ""     # optional TimelineState flag gating access (read only)
@export var structures: Array[String] = []         # StructureDefinition ids buildable here
