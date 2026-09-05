# Streams the land around the active site so the player never reaches the end of the map.
# The world is a grid of tiles (one Terrain3D region each, `size` metres) with the active pack's
# tile at (0,0); +x east, +y (grid) south, matching Godot XZ. When the player comes within
# `prefetch` metres of a neighbouring tile its pack is taken from user://sites if installed, else
# requested from the tile service (Locator.fetch_pack), installed and loaded:
#   - the terrain region at the grid offset (region data built from the tile inputs on first use and
#     cached as the tile's own terrain3d_00_00.res, so the same pack also works as an origin),
#   - the current era's ambient nodes (buildings, roads, parcels, traffic, village) under an offset
#     root carrying the pack id (Sites.pack_of resolves data files through it); story nodes of
#     neighbour packs are dropped,
#   - the pack's ponds.
# Until a tile is ready the player is held at the edge with a notice. Tiles more than one step from
# the player's tile are unloaded. Pack ids are derived from the tile centre (t<E>_<N>), so a tile
# generated for one origin is reused by every origin on the same grid.
class_name TileStreamer
extends Node3D

const AMBIENT := ["Buildings", "Roads", "Parcels", "Traffic", "Village"]
const RETRY_S := 90.0
const NOTICE_GAP_S := 4.0

var enabled := true
var prefetch := 300.0
var world: Node3D
var size := 1024.0
var centre := Vector2.ZERO          # origin tile centre, EPSG:3301
var tiles: Dictionary = {}          # Vector2i -> {state, pack, root, retry_at}; states: ready queued fetching loading unavailable
var _queue: Array[Vector2i] = []
var _busy := false
var _timer := 0.0
var _last_inside := Vector3.INF
var _hold := Vector3.INF
var _notice_at := -100.0


static func pack_id(cx: float, cy: float) -> String:
	return "t%d_%d" % [roundi(cx), roundi(cy)]


func setup(w: Node3D) -> void:
	world = w
	if w.georef and w.georef.tile_size_m() > 0.0:
		size = w.georef.tile_size_m()
	var c: Array = Sites.terrain().get("center", [0, 0])
	centre = Vector2(float(c[0]), float(c[1]))
	tiles[Vector2i.ZERO] = {"state": "ready", "pack": Sites.active, "root": null}
	for a in OS.get_cmdline_user_args():
		if a == "--no-stream":
			enabled = false


func pack_for(loc: Vector2i) -> String:
	return pack_id(centre.x + loc.x * size, centre.y - loc.y * size)


func tile_of(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / size), floori(pos.z / size))


func offset_of(loc: Vector2i) -> Vector3:
	return Vector3(loc.x * size, 0.0, loc.y * size)


func state_of(loc: Vector2i) -> String:
	return str(tiles.get(loc, {}).get("state", "none"))


func is_ready(loc: Vector2i) -> bool:
	return state_of(loc) == "ready"


## True where ground exists (the origin tile or a loaded neighbour).
func contains(pos: Vector3) -> bool:
	return is_ready(tile_of(pos))


## The pack under a world position: {id, offset, loc}, or {} off the loaded map.
func pack_at(pos: Vector3) -> Dictionary:
	var loc := tile_of(pos)
	if not is_ready(loc):
		return {}
	return {"id": tiles[loc].pack, "offset": offset_of(loc), "loc": loc}


func _process(delta: float) -> void:
	if not enabled or world == null or world.player == null:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.5
	_update(world.player.global_position)


## Request every neighbour within reach of `pos`; drop tiles left far behind.
func _update(pos: Vector3) -> void:
	var here := tile_of(pos)
	var p2 := Vector2(pos.x, pos.z)
	var now := Time.get_ticks_msec() / 1000.0
	for dj in range(-1, 2):
		for di in range(-1, 2):
			var loc := here + Vector2i(di, dj)
			if loc == Vector2i.ZERO:
				continue
			var st := state_of(loc)
			if st in ["ready", "queued", "fetching", "loading"]:
				continue
			if st == "unavailable" and now < float(tiles[loc].get("retry_at", 0.0)):
				continue
			var half := Vector2(size, size) * 0.5
			var d := ((Vector2(loc.x, loc.y) * size + half) - p2).abs() - half
			if Vector2(maxf(d.x, 0.0), maxf(d.y, 0.0)).length() <= prefetch:
				_ensure(loc)
	for loc in tiles.keys():
		if loc != Vector2i.ZERO and is_ready(loc) and maxi(absi(loc.x - here.x), absi(loc.y - here.y)) > 1:
			_unload(loc)


func _ensure(loc: Vector2i) -> void:
	var pack := pack_for(loc)
	Sites.scan()
	if Sites.available.has(pack):
		tiles[loc] = {"state": "loading", "pack": pack, "root": null}
		_load(loc)
	else:
		tiles[loc] = {"state": "queued", "pack": pack, "root": null}
		_queue.append(loc)
		_pump()


## One service job at a time: the pipeline fetches national data and is heavy.
func _pump() -> void:
	if _busy or _queue.is_empty():
		return
	_busy = true
	var loc: Vector2i = _queue.pop_front()
	if tiles.has(loc) and tiles[loc].state == "queued":
		var pack: String = tiles[loc].pack
		tiles[loc].state = "fetching"
		var cx := centre.x + loc.x * size
		var cy := centre.y - loc.y * size
		var years: Array = []
		for e in GameState.eras_in_order():
			years.append(str(e.id).rsplit("_", true, 1)[-1])
		var eras := ",".join(years) if not years.is_empty() else "1798,1938,2026"
		print("[Tiles] fetching %s for tile %s (%d, %d)" % [pack, loc, cx, cy])
		var r: Dictionary = await Locator.fetch_pack(pack, "Tile %d %d" % [cx, cy], cx, cy, int(size), eras)
		if tiles.has(loc) and tiles[loc].state == "fetching":
			if r.get("ok", false):
				tiles[loc].state = "loading"
				await _load(loc)
			else:
				_fail(loc, str(r.get("error", "")))
	_busy = false
	_pump()


func _fail(loc: Vector2i, why: String) -> void:
	if not tiles.has(loc):
		return
	tiles[loc].state = "unavailable"
	tiles[loc].retry_at = Time.get_ticks_msec() / 1000.0 + RETRY_S
	print("[Tiles] tile %s unavailable: %s" % [loc, why])


## Region (cached or built from inputs), water and the current era's ambient nodes.
func _load(loc: Vector2i) -> void:
	var t: Dictionary = tiles[loc]
	var pack: String = t.pack
	var tile_dir := Sites.tile_dir_of(pack)
	var terrain: Terrain3D = world.terrain
	if not terrain.data.has_region(loc):
		if TerrainBuilder.has_region_data(tile_dir):
			var r: Terrain3DRegion = ResourceLoader.load(tile_dir + "/data/terrain3d_00_00.res", "", ResourceLoader.CACHE_MODE_IGNORE)
			if r:
				r.set_location(loc)
				terrain.data.add_region(r, true)
		elif TerrainBuilder.has_inputs(tile_dir):
			var b := TerrainBuilder.new()
			b.yielding = true
			b.tree = get_tree()
			b.yield_rows = 8
			var layout := _layout_of(pack)
			if await b.import(terrain, tile_dir, layout, -1.0, loc):
				await b.scatter(terrain, tile_dir, layout.get("exclusions", []) + TerrainBuilder.water_exclusions(Sites.path_in(pack, str(Sites.manifest_for(pack).get("water", "")))), 1798, [], loc)
		if not tiles.has(loc) or tiles[loc] != t:
			return   # unloaded meanwhile
		if not terrain.data.has_region(loc):
			_fail(loc, "no terrain data in " + tile_dir)
			return
		terrain.data.calc_height_range(true)
	var root := Node3D.new()
	root.name = "Tile_%d_%d" % [loc.x, loc.y]
	root.position = offset_of(loc)
	root.set_meta("pack_id", pack)
	add_child(root)
	t.root = root
	world.place_water(pack, root)
	_set_tile_era(loc, GameState.current_era)
	t.state = "ready"
	print("[Tiles] %s ready at %s" % [pack, loc])
	if _hold != Vector3.INF and tile_of(_hold) == loc:
		world._snap(world.player, 1.0)
		_hold = Vector3.INF
		EventBus.notice.emit(tr("NOTICE_TILE_READY"))


func _layout_of(pack: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(Sites.path_in(pack, "layout.json"))
	var parsed = JSON.parse_string(text) if text != "" else null
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


## The era's ambient nodes from the pack's generated scene; story nodes are dropped before _ready.
func _set_tile_era(loc: Vector2i, era_id: String) -> void:
	var t: Dictionary = tiles.get(loc, {})
	var root: Node3D = t.get("root")
	if root == null:
		return
	var old: Node = root.get_node_or_null("Era")
	if old:
		root.remove_child(old)
		old.queue_free()
	if era_id == "":
		return
	var path := Sites.path_in(t.pack, "scenes/%s.tscn" % era_id)
	if not ResourceLoader.exists(path):
		return
	var scene: PackedScene = ResourceLoader.load(path, "PackedScene")
	if scene == null:
		return
	var node: Node3D = scene.instantiate()
	for c in node.get_children():
		if not (c.name in AMBIENT):
			node.remove_child(c)
			c.free()
	node.name = "Era"
	root.add_child(node)
	if node is EraController:
		node.activate()


## World.apply_era: every loaded tile follows the era.
func set_era(era_id: String) -> void:
	for loc in tiles:
		if loc != Vector2i.ZERO and is_ready(loc):
			_set_tile_era(loc, era_id)


func set_hour(hour: float) -> void:
	for loc in tiles:
		var root: Node3D = tiles[loc].get("root")
		if root:
			var era: Node = root.get_node_or_null("Era")
			if era and era.has_method("set_hour"):
				era.set_hour(hour)


func _unload(loc: Vector2i) -> void:
	var t: Dictionary = tiles[loc]
	if t.get("root"):
		t.root.queue_free()
	world.terrain.data.remove_regionl(loc, true)
	tiles.erase(loc)
	print("[Tiles] %s unloaded from %s" % [t.pack, loc])


## Called every frame by the world: keep the player on loaded ground. Stepping over an edge puts
## them back a step; arriving off-map (replay, teleport) holds them in place until the tile loads.
func guard(player: CharacterBody3D) -> void:
	var pos := player.global_position
	if contains(pos):
		_last_inside = pos
		_hold = Vector3.INF
		return
	if enabled:
		_update(pos)
	if _last_inside != Vector3.INF:
		player.global_position = Vector3(_last_inside.x, pos.y, _last_inside.z)
	else:
		if _hold == Vector3.INF:
			_hold = pos
		player.global_position = _hold
	player.velocity = Vector3.ZERO
	var now := Time.get_ticks_msec() / 1000.0
	if now - _notice_at >= NOTICE_GAP_S:
		_notice_at = now
		var st := state_of(tile_of(pos))
		EventBus.notice.emit(tr("NOTICE_EDGE_PENDING") if enabled and st != "unavailable" else tr("NOTICE_EDGE_NONE"))
