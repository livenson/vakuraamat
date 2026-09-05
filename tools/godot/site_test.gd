# Headless check of every site pack under res://sites: the registries load through Sites, every
# era scene instantiates as an EraController, translations resolve, the compiled ink exists,
# the start era and artifact/consequence links are consistent. Runs before the story tests.
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
			_check(FileAccess.file_exists(era.narrative_story), "%s: %s story %s missing (make ink)" % [site, era.id, era.narrative_story])
			if FileAccess.file_exists("res://assets/terrain/%s/terrain_meta.json" % Sites.tile()):
				_check(era.texture() != null, "%s: %s has no terrain texture (make era-maps)" % [site, era.id])
			_check(tr(era.currency_key) != era.currency_key, "%s: %s currency key untranslated" % [site, era.id])
		for cp in GameState.consequence_points.values():
			_check(GameState.era(cp.trigger_era) != null, "%s: %s trigger era unknown" % [site, cp.id])
			for e in cp.affected_eras:
				_check(GameState.era(e) != null, "%s: %s affected era %s unknown" % [site, cp.id, e])
		for it in GameState.items.values():
			if it is ArtifactItem:
				_check(GameState.consequence(it.linked_consequence_point_id) != null, "%s: artifact %s links an unknown consequence" % [site, it.id])
		for g in Trading.goods:
			_check(GameState.item(g.item_id) != null and GameState.era(g.era_id) != null, "%s: trade good %s/%s dangling" % [site, g.era_id, g.item_id])
		for m in Manors.manors.values():
			for sid in m.structures:
				_check(Manors.structures.has(sid), "%s: manor %s lists unknown structure %s" % [site, m.id, sid])
		# the ink story of the start era must load
		var lines := []
		var cb := func(t, _s, _tags): lines.append(t)
		Narrative.line.connect(cb)
		var player: Node = await Narrative._player_for(str(start.get("era", "")))
		Narrative.line.disconnect(cb)
		_check(player != null, "%s: ink story for the start era did not load" % site)
		print("[site] %s ok: %d eras, %d consequence points, %d items, %d trade goods, %d manors" % [site, eras.size(), GameState.consequence_points.size(), GameState.items.size(), Trading.goods.size(), Manors.manors.size()])
	Sites.select(original, false)
	if not _failed:
		print("[site] PASSED")
	get_tree().quit()
