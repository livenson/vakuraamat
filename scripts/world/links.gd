# What one cadastral unit is tied to, read out of the pack files that are already there: the
# companies registered on it (tenants.json), the buildings that stand on it (buildings.json, whose
# rows name their unit in `cadastral`), and the other units tied to it by any of three rules the
# registers carry - the companies on both share an owner, both units belong to the same registered
# immovable, or one building stands on both.
#
# The hashes never leave this file. `of()` returns counts and cadastral numbers - the register's
# owners are natural persons and the pack stores them only as ids so that a link can be drawn
# without naming anybody.
#
# Cached per file like Tenants and Parcels; positions come from Parcels.by_tunnus, which is already
# in world metres for every tile standing right now, so a sibling on an unloaded tile simply drops
# out of the answer.
class_name Links
extends RefCounted

static var _owners: Dictionary = {}   # tenants.json path -> {owner hash: Array of tunnus}
static var _blds: Dictionary = {}     # buildings.json path -> {tunnus: Array of rows}
static var _registry: Dictionary = {}  # parcels.json path -> {kinnistu number: Array of tunnus}


## A pack's text field as shown: "" for a missing one. The Latvian cadastre writes `null` where a
## unit has no address, and str(null) is "<null>" - which the book printed as a plot's name.
static func text_of(v: Variant) -> String:
	return "" if v == null else str(v)


## Everything one unit is linked to. Every key is always present; an unknown unit answers empty.
##   {tunnus, pack, at: Vector3, address, companies: Array, parcels: Array, buildings: Array}
## A `parcels` row is {tunnus, pack, address, at: Vector3, kinds: Array, shared: int}: `kinds` names
## why the two are tied ("owner", "registry", "building") and `shared` counts the owners their
## companies have in common, never which.
static func of(tunnus: String) -> Dictionary:
	var out := {"tunnus": tunnus, "pack": "", "at": Vector3.ZERO, "address": "",
		"companies": [], "parcels": [], "buildings": []}
	if tunnus == "":
		return out
	var u := Parcels.by_tunnus(tunnus)
	if u.is_empty():
		return out
	var pack := str(u.get("pack", Sites.active))
	out.pack = pack
	out.address = text_of(u.get("address"))
	out.at = Vector3(float(u.get("x", 0.0)), 0.0, float(u.get("z", 0.0)))
	out.companies = Tenants.of(pack, tunnus)
	out.parcels = _siblings(pack, tunnus)
	out.buildings = _buildings_on(pack, tunnus, _offset_of(pack))
	return out


static func forget() -> void:
	_owners.clear()
	_blds.clear()
	_registry.clear()


## The other units this one is tied to, by any of three rules the registers actually carry:
##   "owner"    - the companies on both share an owner (the Business Register's people files)
##   "registry" - both units are part of the same registered immovable (the same kinnistu number)
##   "building" - one building stands on both (its `cadastral` names them together)
## A unit tied by more than one rule appears once, carrying every reason. Only units on a tile
## standing right now can be pointed at, so the rest are left out.
static func _siblings(pack: String, tunnus: String) -> Array:
	var why := {}      # other tunnus -> {kind: true}
	var shared := {}   # and, for the owner rule, how many owners the two have in common
	var mine: Array = []
	for t in Tenants.of(pack, tunnus):
		for h in t.get("owners", []):
			if not mine.has(str(h)):
				mine.append(str(h))
	var owners := _owner_index(pack)
	for h in mine:
		for other in owners.get(h, []):
			if str(other) != tunnus:
				why.get_or_add(str(other), {})["owner"] = true
				shared[str(other)] = int(shared.get(str(other), 0)) + 1
	var u := Parcels.by_tunnus(tunnus)
	for other in _registry_index(pack).get(_kinnistu(u), []):
		if str(other) != tunnus:
			why.get_or_add(str(other), {})["registry"] = true
	for b in _blds_of(pack).get(tunnus, []):
		for c in b.get("cadastral", []):
			if str(c) != tunnus:
				why.get_or_add(str(c), {})["building"] = true
	var out: Array = []
	for other in why:
		var v := Parcels.by_tunnus(str(other))
		if v.is_empty():
			continue   # its tile is not standing: nothing to point at
		out.append({"tunnus": str(other), "pack": str(v.get("pack", pack)),
			"address": text_of(v.get("address")),
			"at": Vector3(float(v.get("x", 0.0)), 0.0, float(v.get("z", 0.0))),
			"kinds": why[other].keys(),
			"shared": int(shared.get(other, 0))})
	return out


## The registered immovable a unit belongs to, or "" when the register names none. `land_registry`
## is a number, except where it carries the word "korteriomand" instead - apartment ownership, which
## is a form and not a property: taking that as a number would tie thirty unrelated flats together.
static func _kinnistu(u: Dictionary) -> String:
	var v := str(u.get("land_registry", "") if u.get("land_registry") != null else "")
	return v if v.is_valid_int() else ""


## Kinnistu number -> the units that make up that one registered immovable. Built once per file.
static func _registry_index(pack: String) -> Dictionary:
	var path := Sites.path_in(pack if pack != "" else Sites.active, "parcels.json")
	if _registry.has(path):
		return _registry[path]
	var index := {}
	for u in Parcels.units(pack):
		var key := _kinnistu(u)
		if key != "":
			index.get_or_add(key, []).append(str(u.get("tunnus", "")))
	_registry[path] = index
	return index


## Owner hash -> the units whose companies that person owns, for one pack. Built once per file.
static func _owner_index(pack: String) -> Dictionary:
	var path := Sites.path_in(pack if pack != "" else Sites.active, "tenants.json")
	if _owners.has(path):
		return _owners[path]
	var index := {}
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			for t in parsed.get("tenants", []):
				if t.get("match") != "exact" or t.get("tunnus") == null:
					continue
				for h in t.get("owners", []):
					var group: Array = index.get_or_add(str(h), [])
					if not group.has(str(t.tunnus)):
						group.append(str(t.tunnus))
	_owners[path] = index
	return index


## Unit -> the register's building rows standing on it, keyed on every entry of `cadastral`, which
## is how a building straddling a boundary ties its two units together. Built once per file.
static func _blds_of(pack: String) -> Dictionary:
	var path := Sites.path_in(pack if pack != "" else Sites.active, "buildings.json")
	if _blds.has(path):
		return _blds[path]
	var by_tunnus := {}
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		var rows: Array = parsed.get("buildings", []) if typeof(parsed) == TYPE_DICTIONARY else []
		for b in rows:
			for c in b.get("cadastral", []):
				by_tunnus.get_or_add(str(c), []).append(b)
	_blds[path] = by_tunnus
	return by_tunnus


## The buildings standing on a unit, in world metres. buildings.json is in the pack's own tile
## metres, so the tile's offset is added the way Parcels.all does it.
static func _buildings_on(pack: String, tunnus: String, offset: Vector3) -> Array:
	var out: Array = []
	for b in _blds_of(pack).get(tunnus, []):
		var poly: Array = []
		for q in b.get("polygon", []):
			poly.append([float(q[0]) + offset.x, float(q[1]) + offset.z])
		out.append({"id": str(b.get("id", "")), "ehr": str(b.get("ehr", "")),
			"address": text_of(b.get("address")), "polygon": poly,
			"at": Vector3(float(b.get("x", 0.0)) + offset.x, 0.0, float(b.get("z", 0.0)) + offset.z)})
	return out


## Where the tile carrying `pack` stands, so a neighbour's buildings are drawn 1024 m out with the
## rest of its tile. The site's own tile is at the origin.
static func _offset_of(pack: String) -> Vector3:
	var world: Node = GameState.world
	if world == null or not ("streamer" in world) or world.streamer == null:
		return Vector3.ZERO
	for loc in world.streamer.tiles:
		if str(world.streamer.tiles[loc].get("pack", "")) == pack:
			return world.streamer.offset_of(loc)
	return Vector3.ZERO
