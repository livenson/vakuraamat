# Finding somewhere in the town by typing part of its name: a plot's address or cadastral number, a
# building, a company that rents there, or a street. Used by the book's plot list (as a filter) and
# by the find bar in the world (/), so both match the same way.
#
# The town is one square kilometre - a few hundred plots, a couple of hundred buildings, a couple of
# hundred companies - so there is no index and no need for one: every query walks the lists.
class_name PlaceSearch
extends RefCounted

# The register writes a street both ways ("Aeru tn" and "Aeru tänav" are the same street in one
# pack), so a query for either has to find both. Longest first: the replacement runs in order.
const STREET_WORDS := [
	[" tänav", " tn"], [" maantee", " mnt"], [" puiestee", " pst"], [" põik", " pk"],
	[" tee", " tee"], [" allee", " all"],
]
const FOLD := {"õ": "o", "ä": "a", "ö": "o", "ü": "u", "š": "s", "ž": "z"}
const LIMIT := 40


## Lowercased, without Estonian diacritics, with the street words in their short form: what both
## the query and the things being searched are compared as.
static func fold(text: String) -> String:
	# padded, so a street word is found at the start of a query too: "tänav 1" has to fold the same
	# way as the "tänav" inside "Aeru tänav 1", or one would not answer the other
	var s := " " + fold_plain(text).strip_edges() + " "
	for pair in STREET_WORDS:
		s = s.replace(fold_plain(pair[0]) + " ", fold_plain(pair[1]) + " ")
	return s.strip_edges()


static func fold_plain(text: String) -> String:
	var s := text.to_lower()
	for ch in FOLD:
		s = s.replace(ch, FOLD[ch])
	return s


## How well `haystack` answers `needle`: 0 no match, 2 contains it, 3 starts with it, 4 is it.
## "Aeru tn 1" also answers to a search for "Aeru", which is the point: the list narrows as you type.
static func score(haystack: String, needle: String) -> int:
	if needle == "":
		return 1
	var h := fold(haystack)
	var n := fold(needle)
	if h == n:
		return 4
	if h.begins_with(n):
		return 3
	return 2 if n in h else 0


## Everything in the town that answers `query`, best first: [{kind, label, detail, tunnus, pos}].
## `kind` is one of plot, building, company, street. `near` breaks ties, so what is close is offered
## before what is far.
static func find(query: String, near: Vector2, limit: int = LIMIT) -> Array:
	var q := query.strip_edges()
	if q.length() < 2:
		return []
	var out: Array = []
	_plots(q, out)
	_buildings(q, out)
	_companies(q, out)
	_streets(q, out)
	out.sort_custom(func(a, b):
		if a.score != b.score:
			return a.score > b.score
		var da: float = near.distance_to(a.pos)
		var db: float = near.distance_to(b.pos)
		if is_equal_approx(da, db):
			return str(a.label) < str(b.label)
		return da < db)
	# The town's own plots outscore everything, and a short list would be nothing but plots: give
	# each kind its best answer first, then fill the rest in score order. Searching "Aeru" should
	# offer the street and any company on it, not only the eight nearest houses.
	var picked: Array = []
	var seen: Dictionary = {}
	for r in out:
		if not seen.has(r.kind):
			seen[r.kind] = true
			picked.append(r)
	for r in out:
		if picked.size() >= limit:
			break
		if not (r in picked):
			picked.append(r)
	return picked.slice(0, limit)


static func _plots(q: String, out: Array) -> void:
	for p in Parcels.all():
		var address := _text(p, "address")
		var s: int = maxi(score(address, q), score(_text(p, "tunnus"), q))
		if s > 0:
			out.append({"kind": "plot", "score": s + 1,   # the town's own plots come first
					"label": address if address != "" else str(p.tunnus),
					"detail": "%s · %d m²" % [str(p.tunnus), int(_num(p, "area"))],
					"tunnus": str(p.tunnus), "pos": Vector2(float(p.x), float(p.z))})


static func _buildings(q: String, out: Array) -> void:
	for b in pack_list("buildings.json", "buildings"):
		# buildings.json carries nulls, not missing keys, for what the register does not know
		# (71 of Kvissentali's 211 buildings have no year), and Dictionary.get only substitutes
		# the default when the key is absent: everything here goes through _text and _num.
		var address := _text(b, "address")
		if address == "":
			continue
		var s := score(address, q)
		if s > 0:
			var bits: Array[String] = []
			if _text(b, "purpose") != "":
				bits.append(_text(b, "purpose"))
			if _num(b, "year") > 0:
				bits.append(TranslationServer.translate("UI_IN_USE_SINCE") % int(_num(b, "year")))
			out.append({"kind": "building", "score": s, "label": address,
					"detail": " · ".join(bits), "tunnus": _text(b, "tunnus"),
					"pos": Vector2(_num(b, "x"), _num(b, "z"))})


## Companies are searched by name; where they are is the plot they are registered at.
static func _companies(q: String, out: Array) -> void:
	var at: Dictionary = {}     # tunnus -> plot position
	for p in Parcels.all():
		at[str(p.tunnus)] = Vector2(float(p.x), float(p.z))
	for t in pack_list("tenants.json", "tenants"):
		if str(t.get("status", "")) != "R" or t.get("tunnus") == null:
			continue
		var s := score(_text(t, "name"), q)
		if s > 0 and at.has(str(t.tunnus)):
			out.append({"kind": "company", "score": s, "label": _text(t, "name"),
					"detail": _text(t, "address"), "tunnus": str(t.tunnus), "pos": at[str(t.tunnus)]})


## A street is not a thing in the data: it is the plots that share the part of an address before the
## house number. Its place is the middle of them, which is close enough to walk to.
static func _streets(q: String, out: Array) -> void:
	var sums: Dictionary = {}
	var counts: Dictionary = {}
	for p in Parcels.all():
		var street := _street_of(_text(p, "address"))
		if street == "":
			continue
		sums[street] = sums.get(street, Vector2.ZERO) + Vector2(float(p.x), float(p.z))
		counts[street] = int(counts.get(street, 0)) + 1
	for street in sums:
		var s := score(street, q)
		if s > 0:
			out.append({"kind": "street", "score": s, "label": street,
					"detail": TranslationServer.translate("UI_FIND_PLOTS_ON") % int(counts[street]), "tunnus": "",
					"pos": sums[street] / float(counts[street])})


## "Aeru tn 12-3" -> "Aeru tn": everything before the first part that starts with a digit.
static func _street_of(address: String) -> String:
	var words := address.split(" ", false)
	var kept: Array[String] = []
	for w in words:
		if w.length() > 0 and w[0] >= "0" and w[0] <= "9":
			break
		kept.append(w)
	return " ".join(kept) if kept.size() < words.size() and not kept.is_empty() else ""


## A field as text, and as a number: the pack files use null for "the register does not say".
static func _text(d: Dictionary, key: String) -> String:
	var v = d.get(key)
	return "" if v == null else str(v)


static func _num(d: Dictionary, key: String) -> float:
	var v = d.get(key)
	return 0.0 if v == null else float(v)


static var _cache: Dictionary = {}


static func forget() -> void:
	_cache.clear()


## A list out of the active pack's json, cached like Parcels.units does. Shared with the book.
static func pack_list(file: String, key: String) -> Array:
	var path := Sites.path(file)
	if not _cache.has(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		if typeof(parsed) == TYPE_DICTIONARY:
			_cache[path] = parsed.get(key, [])
		elif typeof(parsed) == TYPE_ARRAY:
			_cache[path] = parsed
		else:
			_cache[path] = []
	return _cache[path]
