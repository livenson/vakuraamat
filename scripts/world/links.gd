# What one cadastral unit is tied to, read out of the pack files that are already there: the
# companies registered on it (tenants.json), the buildings that stand on it (buildings.json, whose
# rows name their unit in `cadastral`), and the other units whose companies share an owner with its
# own (the Business Register's people files, kept as hashes).
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


## Everything one unit is linked to. Every key is always present; an unknown unit answers empty.
##   {tunnus, pack, at: Vector3, address, companies: Array, parcels: Array, buildings: Array}
## A `parcels` row is {tunnus, pack, address, at: Vector3, shared: int} - `shared` counts the owners
## the two units' companies have in common, never which.
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
	out.address = str(u.get("address", ""))
	out.at = Vector3(float(u.get("x", 0.0)), 0.0, float(u.get("z", 0.0)))
	out.companies = Tenants.of(pack, tunnus)
	out.parcels = _siblings(pack, tunnus)
	out.buildings = _buildings_on(pack, tunnus, _offset_of(pack))
	return out


static func forget() -> void:
	_owners.clear()
	_blds.clear()


## The other units whose companies share an owner with this one's, nearest first. Only units on a
## tile standing right now can be pointed at, so the rest are left out.
static func _siblings(pack: String, tunnus: String) -> Array:
	var index := _owner_index(pack)
	var mine: Array = []
	for t in Tenants.of(pack, tunnus):
		for h in t.get("owners", []):
			if not mine.has(str(h)):
				mine.append(str(h))
	var shared := {}
	for h in mine:
		for other in index.get(h, []):
			if str(other) != tunnus:
				shared[str(other)] = int(shared.get(str(other), 0)) + 1
	var out: Array = []
	for other in shared:
		var v := Parcels.by_tunnus(str(other))
		if v.is_empty():
			continue   # its tile is not standing: nothing to point at
		out.append({"tunnus": str(other), "pack": str(v.get("pack", pack)),
			"address": str(v.get("address", "")),
			"at": Vector3(float(v.get("x", 0.0)), 0.0, float(v.get("z", 0.0))),
			"shared": int(shared[other])})
	return out


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


## The buildings standing on a unit, in world metres. buildings.json is in the pack's own tile
## metres, so the tile's offset is added the way Parcels.all does it.
static func _buildings_on(pack: String, tunnus: String, offset: Vector3) -> Array:
	var path := Sites.path_in(pack if pack != "" else Sites.active, "buildings.json")
	if not _blds.has(path):
		var by_tunnus := {}
		if FileAccess.file_exists(path):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
			var rows: Array = parsed.get("buildings", []) if typeof(parsed) == TYPE_DICTIONARY else []
			for b in rows:
				for c in b.get("cadastral", []):
					by_tunnus.get_or_add(str(c), []).append(b)
		_blds[path] = by_tunnus
	var out: Array = []
	for b in _blds[path].get(tunnus, []):
		var poly: Array = []
		for q in b.get("polygon", []):
			poly.append([float(q[0]) + offset.x, float(q[1]) + offset.z])
		out.append({"id": str(b.get("id", "")), "ehr": str(b.get("ehr", "")),
			"address": str(b.get("address", "")), "polygon": poly,
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
