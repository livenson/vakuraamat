# Headless check of every site pack under res://sites: the registry loads through Sites, the layer
# scene instantiates as an EraController, translations resolve, and the pack's cadastre and
# companies load.
#   godot --headless --path . res://tools/godot/site_test.tscn
extends Node

var _failed := false


func _check(cond: bool, msg: String) -> void:
	if not cond and not _failed:
		_failed = true
		print("[site] FAILED: ", msg)
		get_tree().quit(1)


func _ready() -> void:
	await get_tree().process_frame
	var original := Sites.active
	_check(not Sites.available.is_empty(), "no site packs under res://sites")
	for site in Sites.available:
		Sites.select(site, false)
		_check(Sites.active == site, "could not select " + site)
		var eras := GameState.eras_in_order()
		_check(not eras.is_empty(), site + ": no eras")
		var start: Dictionary = Sites.get_value("start", {})
		_check(GameState.era(str(start.get("era", ""))) != null, site + ": start.era is not an era")
		var name_key := Sites.name_key(site)
		_check(tr(name_key) != name_key, "%s: name key %s has no translation (is strings.csv imported?)" % [site, name_key])
		for era in eras:
			_check(tr(era.display_name_key) != era.display_name_key, "%s: %s display name untranslated" % [site, era.id])
			_check(ResourceLoader.exists(era.scene_path), "%s: scene %s missing (make scenes)" % [site, era.scene_path])
			if ResourceLoader.exists(era.scene_path):
				var node: Node = load(era.scene_path).instantiate()
				_check(node is EraController and node.era_id == era.id, "%s: %s scene root is not that era's EraController" % [site, era.id])
				node.free()
			if FileAccess.file_exists("res://assets/terrain/%s/terrain_meta.json" % Sites.tile()):
				_check(era.texture() != null, "%s: %s has no terrain texture (make era-maps)" % [site, era.id])
		var units := Parcels.units(site)
		# a shipped pack is a chosen place; a downloaded tile may be mostly sea (Pirita's north-west has 2)
		_check(units.size() > (0 if Sites.is_user_pack(site) else 10), "%s: parcels.json has %d units" % [site, units.size()])
		var companies := 0
		for u in units:
			companies += Tenants.of(site, str(u.get("tunnus", ""))).size()
		print("[site] %s ok: %d layer(s), %d plots, %d companies" % [site, eras.size(), units.size(), companies])
	Sites.select(original, false)
	if not _failed:
		print("[site] PASSED")
	get_tree().quit()
