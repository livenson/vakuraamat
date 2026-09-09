# Registered companies at a cadastral unit of any installed pack, from that pack's tenants.json.
# Only rows the pipeline matched to a unit exactly are kept: a company whose address merely names
# the street is not on any one plot. Cached per file like Parcels.units.
class_name Tenants
extends RefCounted

static var _cache: Dictionary = {}   # tenants.json path -> {tunnus: Array of rows}


static func of(pack: String, tunnus: String) -> Array:
	if tunnus == "":
		return []
	var path := Sites.path_in(pack if pack != "" else Sites.active, "tenants.json")
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


static func forget() -> void:
	_cache.clear()


## A company as one line of its own: what it is called, its legal form, when it was entered in the
## register, and whether the register still calls it registered.
##
## This and `facts` live here rather than in any one panel because the same company is described in
## three places - the book's plot page, the K overlay and a building's register sheet - and they had
## drifted into three different subsets of the same row.
static func headline(t: Dictionary) -> String:
	var bits: Array[String] = [str(t.get("name", ""))]
	if str(t.get("legal_form", "")) != "":
		bits.append(str(t.legal_form))
	if str(t.get("since", "")) != "":
		bits.append("%s %s" % [TranslationServer.translate("UI_SINCE"), str(t.since)])
	var line := ", ".join(bits)
	if str(t.get("status", "")) != "R":
		line += "  (%s)" % TranslationServer.translate("UI_TENANT_INACTIVE")
	return line


## Everything else the register publishes about it: what it does, how many it employs, what it turns
## over and pays, how large its board is, its capital, and whether the figures give cause for concern.
static func facts(t: Dictionary) -> String:
	var bits: Array[String] = []
	if t.get("emtak") and t.emtak.get("text"):
		bits.append(str(t.emtak.text))
	elif t.get("sector"):
		bits.append(TranslationServer.translate("SECTOR_" + str(t.sector).to_upper()))
	if t.get("employees") != null and int(t.employees) > 0:
		bits.append(TranslationServer.translate("UI_EMPLOYEES") % int(t.employees))
	if t.get("turnover") != null and int(t.turnover) > 0:
		bits.append(TranslationServer.translate("UI_TURNOVER") % BookTheme.money(int(t.turnover)))
	if t.get("taxes") != null and int(t.taxes) > 0:
		bits.append(TranslationServer.translate("UI_TAXES") % BookTheme.money(int(t.taxes)))
	if t.get("board_size") != null:
		bits.append(TranslationServer.translate("UI_BOARD") % int(t.board_size))
	if t.get("owner_managed") == true:
		bits.append(TranslationServer.translate("UI_OWNER_MANAGED"))
	if t.get("capital") != null and float(t.capital) >= 2500.0:
		bits.append(TranslationServer.translate("UI_CAPITAL") % BookTheme.money(int(t.capital)))
	if t.get("health") and str(t.health) != "sound":
		bits.append(TranslationServer.translate("HEALTH_" + str(t.health).to_upper()))
	return " · ".join(bits)


## Names of the active companies (status R), the rule the door label and the name plates share.
static func active_names(pack: String, tunnus: String) -> Array:
	return of(pack, tunnus).filter(func(t): return str(t.get("status", "")) == "R").map(func(t): return str(t.name))
