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
	# a Latvian row names the year of each figure: the turnover is the last annual report's, the taxes
	# the last year VID has in full, and the two need not be the same year
	if t.get("turnover") != null and int(t.turnover) > 0:
		bits.append(TranslationServer.translate("UI_TURNOVER") % BookTheme.money(int(t.turnover)) + _year(t, "turnover_year"))
	if t.get("taxes") != null and int(t.taxes) > 0:
		bits.append(TranslationServer.translate("UI_TAXES") % BookTheme.money(int(t.taxes)) + _year(t, "taxes_year"))
	if t.get("board_size") != null:
		bits.append(TranslationServer.translate("UI_BOARD") % int(t.board_size))
	if t.get("owner_managed") == true:
		bits.append(TranslationServer.translate("UI_OWNER_MANAGED"))
	if t.get("capital") != null and float(t.capital) >= 2500.0:
		bits.append(TranslationServer.translate("UI_CAPITAL") % BookTheme.money(int(t.capital)))
	if t.get("health") and str(t.health) != "sound":
		var verdict := TranslationServer.translate("HEALTH_" + str(t.health).to_upper())
		var why := health_reason(t)
		bits.append(verdict + (": " + why if why != "" else ""))
	return " · ".join(bits)


## " (2024)" when the row names the year of a figure (Latvian packs), else "".
static func _year(t: Dictionary, key: String) -> String:
	return " (%d)" % int(t[key]) if t.get(key) != null else ""


## Why a company is on watch or in distress. Packs built since 2026-09-11 carry the pipeline's own
## reason with its figures (health_why, tools/pipeline/register_extra.py); older ones are read by the
## same rules from the row's fields, where the eight quarters a pack keeps may be too few to name the
## two years compared - then the rule itself is the answer, being the only one left. A yellow plot
## with a bare "watch" left the player to guess whether it was the taxes, the report or the register.
static func health_reason(t: Dictionary) -> String:
	var say := func(key: String) -> String: return TranslationServer.translate(key)
	var health := str(t.get("health", ""))
	var why = t.get("health_why")
	var rule := str(why.get("rule", "")) if typeof(why) == TYPE_DICTIONARY else ""
	if rule == "":
		if health == "distressed":
			rule = "status" if str(t.get("status", "")) in ["N", "L"] else "zero_taxes"
		elif health == "watch":
			rule = "report" if t.get("report_overdue") == true else "turnover"
	match rule:
		"status":
			return say.call("HEALTH_WHY_STATUS") % str(t.get("status_text", t.get("status", "")))
		"zero_taxes":
			return say.call("HEALTH_WHY_ZERO_TAXES")
		"report":
			return say.call("HEALTH_WHY_REPORT")
		"turnover":
			var years := _turnover_years(why, t)
			if years.is_empty():
				return say.call("HEALTH_WHY_TURNOVER_RULE")
			return say.call("HEALTH_WHY_TURNOVER") % [BookTheme.money(int(years[1])), BookTheme.money(int(years[3])), int(years[0]), int(years[2])]
	return ""


## [year, turnover, year, turnover] of the two years a turnover watch compared: from the pipeline's
## reason, or the last two years whose four quarters the row still has; [] when it has not.
static func _turnover_years(why, t: Dictionary) -> Array:
	if typeof(why) == TYPE_DICTIONARY and why.get("from") is Array and why.get("to") is Array:
		return [why.from[0], why.from[1], why.to[0], why.to[1]]
	var years := {}
	for q in t.get("quarters", []):
		if q is Array and q.size() >= 3 and q[2] != null:
			years[int(q[0])] = years.get(int(q[0]), []) + [float(q[2])]
	var full: Array = years.keys().filter(func(y): return years[y].size() == 4)
	full.sort()
	if full.size() < 2:
		return []
	var sum := func(qs: Array) -> float: return qs.reduce(func(s, v): return s + v, 0.0)
	return [full[-2], sum.call(years[full[-2]]), full[-1], sum.call(years[full[-1]])]


## Names of the active companies (status R), the rule the door label and the name plates share.
static func active_names(pack: String, tunnus: String) -> Array:
	return of(pack, tunnus).filter(func(t): return str(t.get("status", "")) == "R").map(func(t): return str(t.name))
