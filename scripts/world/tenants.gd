# Registered companies at a cadastral unit of any installed pack: the origin pack answers from the
# Ledger (its rows carry arrears and the town's live state), a streamed neighbour from that pack's
# tenants.json (exact matches only, the rule LocalLedger applies). Cached per file like Parcels.units.
class_name Tenants
extends RefCounted

static var _cache: Dictionary = {}   # tenants.json path -> {tunnus: Array of rows}


static func of(pack: String, tunnus: String) -> Array:
	if tunnus == "":
		return []
	if pack == "" or pack == Sites.active:
		return Ledger.tenants_of(tunnus)
	var path := Sites.path_in(pack, "tenants.json")
	if not _cache.has(path):
		var by_tunnus := {}
		if FileAccess.file_exists(path):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
			if typeof(parsed) == TYPE_DICTIONARY:
				for t in parsed.get("tenants", []):
					if t.get("match") == "exact" and t.get("tunnus") != null:
						by_tunnus.get_or_add(str(t.tunnus), []).append(t)
		_cache[path] = by_tunnus
	return _cache[path].get(tunnus, [])


## Names of the active companies (status R), the rule the door label and the name plates share.
static func active_names(pack: String, tunnus: String) -> Array:
	return of(pack, tunnus).filter(func(t): return str(t.get("status", "")) == "R").map(func(t): return str(t.name))
