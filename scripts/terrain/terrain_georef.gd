# Georeferencing helper: converts between Godot world space and EPSG:3301 (L-EST97)
# using the terrain_meta.json written by tools/pipeline/fetch_tile.py.
# The tile's north-west corner is Godot (0, y, 0); +X = east, +Z = south.
class_name TerrainGeoref
extends RefCounted

var meta: Dictionary = {}


static func load_tile(tile: String) -> TerrainGeoref:
	return load_dir("res://assets/terrain/%s" % tile)


static func load_dir(tile_dir: String) -> TerrainGeoref:
	var g := TerrainGeoref.new()
	var text := FileAccess.get_file_as_string(tile_dir + "/terrain_meta.json")
	if not text.is_empty():
		g.meta = JSON.parse_string(text)
	return g


func is_valid() -> bool:
	return meta.has("xmin") and meta.has("ymax")


## Godot world position -> (easting, northing) in metres, EPSG:3301.
func world_to_lest97(p: Vector3) -> Vector2:
	return Vector2(float(meta.xmin) + p.x, float(meta.ymax) - p.z)


## (easting, northing) EPSG:3301 -> Godot world XZ (y left at 0; snap to terrain separately).
func lest97_to_world(e: float, n: float) -> Vector3:
	return Vector3(e - float(meta.xmin), 0.0, float(meta.ymax) - n)


func tile_size_m() -> float:
	return float(meta.get("size_m", 0))
