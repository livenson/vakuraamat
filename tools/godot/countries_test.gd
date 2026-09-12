# The country descriptors (assets/data/countries/<id>.json) are what the runtime knows about a country:
# every one must parse, name files and strings that exist, and tell its building codes and its packs
# apart from the others'. Pinned with the two shipped countries' own examples.
#   godot --headless --path . res://tools/godot/countries_test.tscn
extends Node

var _failed := false


func _check(cond: bool, msg: String) -> void:
	if not cond and not _failed:
		_failed = true
		print("[countries] FAILED: ", msg)
		get_tree().quit(1)


func _ready() -> void:
	var all := Countries.all()
	_check(all.has("ee") and all.has("lv"), "descriptors read: %s" % str(all.keys()))
	for id in all:
		var c: Dictionary = all[id]
		_check(FileAccess.file_exists(str(c.get("outline", ""))), "%s: outline %s is missing" % [id, c.get("outline")])
		_check(c.get("coverage", []).size() == 4, "%s: coverage is not a box" % id)
		_check(str(c.get("refine", "")) in ["ground", "flag"], "%s: refine is '%s'" % [id, c.get("refine")])
		var bc: Dictionary = c.get("building_code", {})
		for key in [bc.get("register_key", ""), bc.get("code_key", ""), c.get("name_key", "")]:
			_check(str(key) != "" and tr(str(key)) != str(key), "%s: no string for '%s'" % [id, key])
		var photos: Dictionary = c.get("photos", {})
		_check(bool(photos.get("from_tile", false)) or (str(photos.get("wms", "")) != "" and not photos.get("epochs", []).is_empty()),
				"%s: photos neither from the tile nor from a WMS with campaigns" % id)
	# building codes: Estonia's EHR (9 digits) and Latvia's cadastral designation (14)
	_check(Countries.for_building_code("101036528", {}).get("id") == "ee", "a 9-digit EHR code is not Estonian")
	_check(Countries.for_building_code("01000090065001", {}).get("id") == "lv", "a 14-digit designation is not Latvian")
	_check(Countries.for_building_code("", {"id": "x"}).get("id") == "x", "an empty code does not fall back to the pack's country")
	# packs: Latvian by their manifest, Estonian by default (older manifests carry no country)
	_check(Countries.of_pack("riga_vecpilseta").get("id") == "lv", "Rīga is not Latvian")
	_check(Countries.of_pack("pirita").get("id") == "ee", "Pirita is not Estonian")
	_check(Locator.in_coverage(506400, 6311650) and Locator.in_coverage(542000, 6589000), "Rīga or Tallinn not covered")
	_check(not Locator.in_coverage(100000, 100000), "a point far outside every country is covered")
	_check(Countries.fill("p={x},{y}", {"x": 1, "y": 2}) == "p=1,2", "fill")
	# plot links: an Estonian plot keeps its pack's own, a Latvian one gets its property's Lursoft card
	# (by the property number: one property spans several plots), also on an Estonian border tile
	var lursoft := "https://www.lursoft.lv/real-estate-properties/property/"
	_check(Countries.parcel_link({"tunnus": "01000090065", "property": "01000090065", "link": null, "pack": "riga_vecpilseta"}) == lursoft + "01000090065",
			"Torņa iela 4 has no Lursoft link")
	_check(Countries.parcel_link({"tunnus": "01000010010", "property": "01000010067", "pack": "riga_vecpilseta"}) == lursoft + "01000010067",
			"a plot does not link to its property's card")
	_check(Countries.parcel_link({"tunnus": "79514:036:0090", "link": "https://xgis.example/p", "pack": "kvissentali"}) == "https://xgis.example/p",
			"an Estonian plot lost its own link")
	_check(Countries.parcel_link({"tunnus": "94010010935", "property": "94019001557", "pack": "kvissentali"}) == lursoft + "94019001557",
			"a Latvian plot on an Estonian pack is not linked as Latvian")
	# the history strip: Rīga's years are the tile's own files, Estonia's are WMS campaigns
	var riga := PlotHistory.epochs("riga_vecpilseta")
	_check(riga.size() >= 3 and riga.all(func(e): return e.has("texture")), "Rīga's history: %s" % str(riga))
	var pirita := PlotHistory.epochs("pirita")
	_check(pirita.size() == 5 and pirita.all(func(e): return e.has("layers")), "Pirita's history: %s" % str(pirita))
	if not _failed:
		print("[countries] PASSED: %d countries; building codes, packs, coverage and photo sources resolve" % all.size())
		get_tree().quit(0)
