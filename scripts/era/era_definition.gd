# One era of the same real ground. The landform (heightmap) is shared; each era brings
# its own ground texture, default time of day and an EraLayer scene of props and NPCs.
class_name EraDefinition
extends Resource

@export var id: String                    # "era_1798"
@export var display_name_key: String      # translation key
@export var year_label: String            # "1798"
@export var scene_path: String            # EraLayer scene instanced under the world
@export var terrain_texture: Texture2D    # ground drape for this era (ortho / historical map)
@export var texture_strength: float = 1.0 # how much the era texture replaces the detail materials
@export var ground_tint: Color = Color.WHITE
@export var default_time_of_day: float = 10.0   # hours, applied on FIRST entry only
@export var order: int = 0
@export var narrative_story: String       # compiled ink json for this era
@export var currency_key: String = ""     # translation key of the era's money unit (trading)
@export var starting_money: int = 0       # wallet at new game (trading)
@export var terrain_texture_path: String = ""   # runtime packs: image file (user://...) loaded on demand

var _loaded: Texture2D = null


## The ground drape: the imported texture, else the image at terrain_texture_path.
func texture() -> Texture2D:
	if terrain_texture:
		return terrain_texture
	if _loaded == null and terrain_texture_path != "":
		var img := Image.load_from_file(terrain_texture_path)
		if img:
			_loaded = ImageTexture.create_from_image(img)
		else:
			push_warning("era %s: cannot load %s" % [id, terrain_texture_path])
	return _loaded
