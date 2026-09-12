# The countries the game knows, one descriptor each in assets/data/countries/<id>.json: what the
# runtime needs to tell them apart. The outline on the menu map and the box the tile service may cover;
# the address search; where a plot's older photographs come from (a WMS with a layer list per
# campaign, or the tile's own files the pipeline cut); the register and map links a report carries;
# how a building code looks and what the register sheet calls it; how a refined pack is recognised.
#
# No script names a country. Adding one is a descriptor here and an adapter in
# tools/pipeline/sources.py (docs/adding-a-country.md).
class_name Countries
extends RefCounted

const DIR := "res://assets/data/countries/"
const DEFAULT := "ee"   # packs from before manifests carried a country are all Estonian

static var _all: Dictionary = {}


## Every descriptor by id, read once, in id order.
static func all() -> Dictionary:
	if _all.is_empty():
		var files := Array(DirAccess.get_files_at(DIR))
		files.sort()
		for f in files:
			if not str(f).ends_with(".json"):
				continue
			var d = JSON.parse_string(FileAccess.get_file_as_string(DIR + str(f)))
			if typeof(d) == TYPE_DICTIONARY:
				_all[str(d.get("id", str(f).get_basename()))] = d
	return _all


## One country's descriptor; the default country's for an id nobody describes.
static func by_id(id: String) -> Dictionary:
	return all().get(id, all().get(DEFAULT, {}))


## The country a tile belongs to, from its terrain_meta.json.
static func of_meta(meta: Dictionary) -> Dictionary:
	return by_id(str(meta.get("country", DEFAULT)))


## The country of a pack: its manifest's, else its tile's, else the default.
static func of_pack(pack: String) -> Dictionary:
	var id := pack if pack != "" else Sites.active
	var c := str(Sites.manifest_for(id).get("country", ""))
	if c == "" or c == "<null>":
		return of_meta(TerrainGeoref.load_dir(Sites.tile_dir_of(id)).meta)
	return by_id(c)


## The country whose building codes look like `code`, or `fallback` when none claims it. Told by the
## code rather than the pack because a tile on the border carries buildings of both countries.
static func for_building_code(code: String, fallback: Dictionary) -> Dictionary:
	if code != "":
		for c in all().values():
			var pattern := str(c.get("building_code", {}).get("pattern", ""))
			if pattern != "" and RegEx.create_from_string(pattern).search(code) != null:
				return c
	return fallback


## The country whose plot codes look like `code` (the descriptors' parcel_code patterns: Estonia's
## "79514:036:0090", Latvia's eleven digits), or `fallback` when none claims it.
static func for_parcel_code(code: String, fallback: Dictionary) -> Dictionary:
	if code != "":
		for c in all().values():
			var pattern := str(c.get("parcel_code", ""))
			if pattern != "" and RegEx.create_from_string(pattern).search(code) != null:
				return c
	return fallback


## A plot's page in a public register: the link its pack gives it (Estonia's X-GIS), else its
## country's `parcel_link` filled with its property number ({property}; the plot's own code when it
## has none) and its code ({tunnus}). Latvia's is the property's Lursoft card: one property often
## spans several plots, and the card is the property's. "" when there is neither.
static func parcel_link(unit: Dictionary) -> String:
	if unit.get("link") != null and str(unit.link) != "":
		return str(unit.link)
	var tunnus := str(unit.get("tunnus", ""))
	var template := str(for_parcel_code(tunnus, of_pack(str(unit.get("pack", "")))).get("parcel_link", ""))
	if template == "":
		return ""
	var prop := str(unit.property) if unit.get("property") != null else tunnus
	return fill(template, {"property": prop, "tunnus": tunnus})


## Whether any country's box holds an L-EST97 point: where the tile service may have data. The
## service decides the border exactly.
static func covers(x: float, y: float) -> bool:
	for c in all().values():
		var b: Array = c.get("coverage", [])
		if b.size() == 4 and x > float(b[0]) and x < float(b[2]) and y > float(b[1]) and y < float(b[3]):
			return true
	return false


## The outline files of every country, for the menu map.
static func outlines() -> Array:
	var out := []
	for c in all().values():
		if str(c.get("outline", "")) != "":
			out.append(str(c.outline))
	return out


## A link template filled in: {x} {y} a point on the game's grid, {code} a building code, {q} a query.
static func fill(template: String, values: Dictionary) -> String:
	var out := template
	for k in values:
		out = out.replace("{%s}" % k, str(values[k]))
	return out
