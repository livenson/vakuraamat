# Shops, cafés, offices and hotels OpenStreetMap maps inside a pack's tile (tools/pipeline/fetch_osm.py
# writes pois.json: kind, name, brand, opening hours, the building each stands in and the registry code
# of the company on that building whose name it matches). Read per building; cached per file like
# Tenants, dropped by GameState.reload().
class_name Pois
extends RefCounted

static var _cache: Dictionary = {}   # pois.json path -> {building id (String): Array of rows}

## The amenities that are a place to eat or drink: their sign is the café's, not the shop's.
const HOSPITALITY := ["restaurant", "cafe", "bar", "pub", "fast_food", "ice_cream", "nightclub", "biergarten", "food_court"]


static func of_building(pack: String, building_id: Variant) -> Array:
	if building_id == null or str(building_id) == "":
		return []
	var path := Sites.path_in(pack if pack != "" else Sites.active, "pois.json")
	if not _cache.has(path):
		var by_building := {}
		if FileAccess.file_exists(path):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
			if typeof(parsed) == TYPE_DICTIONARY:
				for p in parsed.get("pois", []):
					if p.get("building") != null:
						by_building.get_or_add(_key(p.building), []).append(p)
		_cache[path] = by_building
	return _cache[path].get(_key(building_id), [])


static func forget() -> void:
	_cache.clear()


## A building id as the file and the scene both write it: JSON reads 585229 back as 585229.0.
static func _key(id: Variant) -> String:
	return str(int(id)) if typeof(id) == TYPE_FLOAT or typeof(id) == TYPE_INT else str(id)


## "trade" for a shop, "hospitality" for a place to eat or drink, "" for the rest (offices, crafts).
static func sector(p: Dictionary) -> String:
	if str(p.get("key", "")) == "shop":
		return "trade"
	if str(p.get("key", "")) == "amenity" and str(p.get("type", "")) in HOSPITALITY:
		return "hospitality"
	return ""


## What a point is called: its name, else its brand.
static func label(p: Dictionary) -> String:
	for k in ["name", "brand"]:
		if p.get(k) != null and str(p[k]).strip_edges() != "":
			return str(p[k])
	return ""


## One line for the building's sheet: the name, what it is, today's hours or that the unit is empty.
static func line(p: Dictionary, weekday: int) -> String:
	if p.get("vacant") == true:
		return TranslationServer.translate("UI_SHOP_VACANT")
	var bits: Array[String] = []
	var name := label(p)
	if name != "":
		bits.append(name)
	bits.append(str(p.get("type", "")).replace("_", " "))
	if p.get("opening_hours") != null:
		var week := OpeningHours.parse(str(p.opening_hours))
		if not week.is_empty():
			var today := OpeningHours.day_text(week, weekday)
			bits.append(TranslationServer.translate("UI_SHOP_HOURS") % today if today != "" else TranslationServer.translate("UI_SHOP_CLOSED_TODAY"))
	return ", ".join(bits)
