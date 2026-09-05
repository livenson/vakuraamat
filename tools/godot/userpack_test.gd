# Headless check of runtime (user://) packs: zips the Palupera pack and tile inputs the way the tile
# service does, installs it through Locator as "palupera_copy", selects it, and checks that the
# registry, CSV translations, tile directory and textures resolve. Cleans up after itself.
#   godot --headless --path . res://tools/godot/userpack_test.tscn
extends Node

const ID := "palupera_copy"
var _failed := false


func _check(cond: bool, msg: String) -> void:
	if not cond and not _failed:
		_failed = true
		print("[userpack] FAILED: ", msg)
		_cleanup()
		get_tree().quit(1)


func _ready() -> void:
	await get_tree().process_frame
	var zip_path := "user://cache/userpack_test.zip"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://cache"))
	var z := ZIPPacker.new()
	_check(z.open(zip_path) == OK, "cannot create zip")
	var n := _add_dir(z, "res://sites/palupera", "site/")
	for f in ["terrain_meta.json", "heightmap.r32", "canopy.r32", "ortho.jpg"]:
		z.start_file("tile/" + f)
		z.write_file(FileAccess.get_file_as_bytes("res://assets/terrain/palupera/" + f))
		z.close_file()
		n += 1
	z.close()
	print("[userpack] zipped %d files" % n)
	# the copy must not collide with the shipped tile: point it at its own tile name
	_check(Locator.install_zip(zip_path, ID), "install failed")
	var mpath := Sites.USER_ROOT + ID + "/site.json"
	var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(mpath))
	m["id"] = ID
	m["name_key"] = "SITE_PALUPERA_COPY"
	m["terrain"]["tile"] = "palupera"   # installed under user://tiles/palupera; shipped res tile wins in tile_dir()
	var f := FileAccess.open(mpath, FileAccess.WRITE)
	f.store_string(JSON.stringify(m, "  "))
	f.close()
	var sf := FileAccess.open(Sites.USER_ROOT + ID + "/strings.csv", FileAccess.READ_WRITE)
	sf.seek_end()
	sf.store_string('SITE_PALUPERA_COPY,"Palupera, koopia","Palupera, copy"\n')
	sf.close()
	Sites.scan()
	_check(Sites.available.has(ID), "user pack not listed: %s" % [Sites.available])
	Sites.select(ID, false)
	_check(Sites.active == ID and Sites.is_user_pack(ID), "select failed")
	_check(Sites.path("layout.json").begins_with("user://sites/"), "path() not under user://: " + Sites.path("layout.json"))
	_check(tr("SITE_PALUPERA_COPY") == "Palupera, copy" or tr("SITE_PALUPERA_COPY") == "Palupera, koopia", "CSV translation missing: " + tr("SITE_PALUPERA_COPY"))
	_check(tr("ERA_2026_NAME") != "ERA_2026_NAME", "pack CSV strings not loaded")
	_check(GameState.eras.size() == 1, "registries did not load from user://")
	_check(Sites.tile_dir() == "res://assets/terrain/palupera", "tile_dir should prefer the shipped tile: " + Sites.tile_dir())
	for era in GameState.eras_in_order():
		_check(ResourceLoader.exists(era.scene_path) or FileAccess.file_exists(era.scene_path), "%s scene missing under user://" % era.id)
		var node: Node = load(era.scene_path).instantiate()
		_check(node is EraController, "%s scene from user:// did not load" % era.id)
		node.free()
	# texture by path (what the service writes for runtime packs)
	var e := EraDefinition.new()
	e.id = "x"
	e.terrain_texture_path = "user://tiles/palupera/ortho.jpg"
	_check(e.texture() != null and e.texture().get_width() > 0, "texture by user:// path failed")
	# terrain builder inputs recognised for the copied tile
	_check(TerrainBuilder.has_inputs("user://tiles/palupera") and not TerrainBuilder.has_region_data("user://tiles/palupera"), "builder input detection")
	Sites.select("palupera", false)
	_cleanup()
	if not _failed:
		print("[userpack] PASSED")
	get_tree().quit()


func _add_dir(z: ZIPPacker, dir: String, prefix: String) -> int:
	var n := 0
	var d := DirAccess.open(dir)
	for f in d.get_files():
		if f.ends_with(".import") or f.ends_with(".translation") or f.ends_with(".uid"):
			continue
		z.start_file(prefix + f)
		z.write_file(FileAccess.get_file_as_bytes(dir + "/" + f))
		z.close_file()
		n += 1
	for sub in d.get_directories():
		n += _add_dir(z, dir + "/" + sub, prefix + sub + "/")
	return n


func _cleanup() -> void:
	for root in [Sites.USER_ROOT + ID, Sites.USER_TILES + "palupera"]:
		_rm(ProjectSettings.globalize_path(root))
	Sites.scan()


func _rm(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path + "/" + f)
	for d in DirAccess.get_directories_at(path):
		_rm(path + "/" + d)
	DirAccess.remove_absolute(path)
