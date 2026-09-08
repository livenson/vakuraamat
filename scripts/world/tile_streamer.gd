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

signal tile_ready(loc: Vector2i, root: Node3D)     # after _load, and again when set_era re-instances a tile's Era
signal tile_unloaded(loc: Vector2i)                 # before the root is freed; tiles[loc].root is still valid
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
var _haze: Dictionary = {}          # Vector2i -> MeshInstance3D: a survey haze along a tile still being fetched
var _stage := ""                    # last service stage text (Locator.progress)
var _haze_mat: ShaderMaterial


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
	Locator.progress.connect(func(text: String, _f: float): _stage = text)


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
	_refresh_stale()


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
	if _loading:
		return   # unloads wait for the tile that is arriving; the next tick sees them again
	for loc in tiles.keys():
		if loc != Vector2i.ZERO and is_ready(loc) and maxi(absi(loc.x - here.x), absi(loc.y - here.y)) > 1:
			_unload(loc)
			return   # one region removal per tick


func _ensure(loc: Vector2i) -> void:
	var pack := pack_for(loc)
	Sites.scan()
	if Sites.available.has(pack):
		tiles[loc] = {"state": "loading", "pack": pack, "root": null}
		_load(loc)
	else:
		tiles[loc] = {"state": "queued", "pack": pack, "root": null}
		_queue.append(loc)
		_show_haze(loc)
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
		var eras := ",".join(years) if not years.is_empty() else "2026"
		print("[Tiles] fetching %s for tile %s (%d, %d)" % [pack, loc, cx, cy])
		Locator.job_owner = "stream"   # the background backfill waits: someone is standing at this edge
		var r: Dictionary = await Locator.fetch_pack(pack, "Tile %d %d" % [cx, cy], cx, cy, int(size), eras)
		Locator.job_owner = ""
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
	_hide_haze(loc)
	print("[Tiles] tile %s unavailable: %s" % [loc, why])


## Region (cached or built from inputs), water and the current era's ambient nodes.
## What the streamer is busy with, for the HUD: "1,0 · fetching (cadastre and roads)" or "".
func loading_status() -> String:
	for loc in tiles:
		var st := str(tiles[loc].get("state", ""))
		if st in ["queued", "fetching", "loading"]:
			var detail := _stage if st == "fetching" and _stage != "" else st
			return "%d,%d · %s" % [loc.x, loc.y, detail]
	return ""


## Tiles arrive one at a time, each heavy step in its own frame (Terrain3D's region add and remove
## rebuild the map arrays of every loaded region: 100-600 ms each; two tiles in one frame made a
## five-second stall).
var _loading := false


func _load(loc: Vector2i) -> void:
	while _loading:
		await get_tree().process_frame
		if not tiles.has(loc) or tiles[loc].get("state") != "loading":
			return
	_loading = true
	await _load_now(loc)
	_loading = false


func _load_now(loc: Vector2i) -> void:
	var t: Dictionary = tiles[loc]
	var pack: String = t.pack
	PerfLog.mark("tile load %s at %s" % [pack, loc])
	var tile_dir := Sites.tile_dir_of(pack)
	var terrain: Terrain3D = world.terrain
	if not terrain.data.has_region(loc):
		if TerrainBuilder.has_region_data(tile_dir):
			var t_load := Time.get_ticks_msec()
			var r: Terrain3DRegion = ResourceLoader.load(tile_dir + "/data/terrain3d_00_00.res", "", ResourceLoader.CACHE_MODE_IGNORE)
			PerfLog.mark("region file %d ms" % (Time.get_ticks_msec() - t_load))
			if r:
				r.set_location(loc)
				t_load = Time.get_ticks_msec()
				terrain.data.add_region(r, true)
				PerfLog.mark("add_region %d ms" % (Time.get_ticks_msec() - t_load))
		elif TerrainBuilder.has_inputs(tile_dir):
			var b := TerrainBuilder.new()
			b.yielding = true
			b.tree = get_tree()
			b.yield_rows = 8
			var layout := _layout_of(pack)
			if await b.import(terrain, tile_dir, layout, -1.0, loc):
				var mask := TerrainBuilder.footprint_mask(Sites.path_in(pack, "buildings.json"), terrain.region_size, TerrainBuilder.road_mask(Sites.path_in(pack, "roads.json"), terrain.region_size))
				await b.scatter(terrain, tile_dir, layout.get("exclusions", []) + TerrainBuilder.water_exclusions(Sites.path_in(pack, str(Sites.manifest_for(pack).get("water", "")))), 1798, [], loc, mask)
		await get_tree().process_frame   # the region add had its frame
		if not tiles.has(loc) or tiles[loc] != t:
			return   # unloaded meanwhile
		if not terrain.data.has_region(loc):
			_fail(loc, "no terrain data in " + tile_dir)
			return
		var t_range := Time.get_ticks_msec()
		terrain.data.calc_height_range(true)
		PerfLog.mark("height range %d ms" % (Time.get_ticks_msec() - t_range))
	var probe: float = terrain.data.get_height(offset_of(loc) + Vector3(size * 0.5, 0.0, size * 0.5))
	if is_nan(probe):
		# the region is registered but answers no heights: never place a layer over a void
		terrain.data.remove_region(terrain.data.get_region(loc), true)
		_fail(loc, "region without heights at %s" % loc)
		return
	var root := Node3D.new()
	root.name = "Tile_%d_%d" % [loc.x, loc.y]
	root.position = offset_of(loc)
	root.set_meta("pack_id", pack)
	add_child(root)
	t.root = root
	var t_step := Time.get_ticks_msec()
	world.place_water(pack, root)
	PerfLog.mark("water %d ms" % (Time.get_ticks_msec() - t_step))
	# The ground stands: the player may enter while the buildings and parcels fill in over the next
	# frames; the door pass (tile_ready) waits for them.
	t.state = "ready"
	_hide_haze(loc)
	print("[Tiles] %s ready at %s" % [pack, loc])
	PerfLog.mark("tile ready %s" % pack)
	if _hold != Vector3.INF and tile_of(_hold) == loc:
		world._snap(world.player, 1.0)
		_hold = Vector3.INF
		EventBus.notice.emit(tr("NOTICE_TILE_READY"))
	await get_tree().process_frame   # the pack's ledger and water had theirs; the scene gets its own
	if not tiles.has(loc) or tiles[loc] != t:
		return
	await _set_tile_era(loc, GameState.current_era)
	if not tiles.has(loc) or tiles[loc] != t:
		return   # unloaded while filling
	tile_ready.emit(loc, root)


func _layout_of(pack: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(Sites.path_in(pack, "layout.json"))
	var parsed = JSON.parse_string(text) if text != "" else null
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


## A pack's scene carries the buildings and parcels that straddle its edge (40-70 per city tile);
## the neighbour carries the same ones. Each belongs to the tile that holds its origin, so a
## scene shows only those: two exteriors of one house left its windows opaque from inside.
static func trim_to_tile(era_node: Node, tile_size: float) -> int:
	var dropped := 0
	for group_name in EraController.STAGGERED:
		var group: Node = era_node.get_node_or_null(group_name)
		if group == null:
			continue
		for m in group.get_children():
			if m is Node3D:
				var p: Vector3 = m.position
				if p.x < 0.0 or p.x >= tile_size or p.z < 0.0 or p.z >= tile_size:
					group.remove_child(m)
					m.free()
					dropped += 1
	return dropped


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
	var scene: PackedScene = await _era_scene(root, str(t.pack), era_id)
	if scene != null:
		await _fill_era(root, scene)


## The pack's era scene, a text file with hundreds of nodes: parsed on a loader thread and polled
## here. Null when the pack has no such era, or the tile went away while the scene parsed.
func _era_scene(root: Node3D, pack: String, era_id: String) -> PackedScene:
	var path := Sites.path_in(pack, "scenes/%s.tscn" % era_id)
	if not ResourceLoader.exists(path):
		return null
	var t_scene := Time.get_ticks_msec()
	var scene: PackedScene = null
	if ResourceLoader.has_cached(path):
		scene = ResourceLoader.load(path, "PackedScene")
	elif ResourceLoader.load_threaded_request(path, "PackedScene") == OK:
		while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await get_tree().process_frame
		if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED:
			scene = ResourceLoader.load_threaded_get(path)
		if not is_instance_valid(root) or not root.is_inside_tree() or root.get_node_or_null("Era") != null:
			scene = null   # unloaded, or another era arrived, while the scene parsed
	if scene != null:
		PerfLog.mark("tile era scene %s: parsed in %d ms" % [path.get_file(), Time.get_ticks_msec() - t_scene])
	return scene


## The era's ambient nodes under the tile root; story nodes are dropped before _ready. The heavy
## groups enter empty and their members are added back a few milliseconds a frame
## (EraController.fill_pending), so a city tile (hundreds of buildings, each building its mesh and
## collision in _ready) no longer costs one two-second frame and a stalled GPU fence.
func _fill_era(root: Node3D, scene: PackedScene) -> void:
	var t_scene := Time.get_ticks_msec()
	var node: Node3D = scene.instantiate()
	PerfLog.mark("instantiate %d ms" % (Time.get_ticks_msec() - t_scene))
	for c in node.get_children():
		if not (c.name in AMBIENT):
			node.remove_child(c)
			c.free()
	node.name = "Era"
	trim_to_tile(node, size)
	var pending: Array = node.detach_heavy() if node is EraController else []
	root.add_child(node)
	if node is EraController:
		node.activate()   # the empty groups snap in no time; the members snap as they arrive
		var player: Node3D = world.get_node_or_null("Player") if world else null
		await node.fill_pending(pending, player.global_position if player else root.global_position)


func set_era(era_id: String) -> void:
	for loc in tiles:
		if loc != Vector2i.ZERO and is_ready(loc):
			_set_tile_era(loc, era_id)
			tile_ready.emit(loc, tiles[loc].root)


func set_hour(hour: float) -> void:
	for loc in tiles:
		var root: Node3D = tiles[loc].get("root")
		if root:
			var era: Node = root.get_node_or_null("Era")
			if era and era.has_method("set_hour"):
				era.set_hour(hour)


## A translucent, slowly breathing wall of haze standing on the tile being surveyed, so the wait is
## visible from the edge; removed when the tile is ready or given up.
func _show_haze(loc: Vector2i) -> void:
	if _haze == null:
		_haze = {}   # a member added by a hot reload starts as null on the live instance
	if _haze.has(loc) or world == null:
		return
	if _haze_mat == null:
		_haze_mat = ShaderMaterial.new()
		_haze_mat.shader = load("res://assets/shaders/survey_haze.gdshader")
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(size, 90.0, size)
	mi.mesh = box
	mi.material_override = _haze_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var centre := offset_of(loc) + Vector3(size * 0.5, 0.0, size * 0.5)
	var h: float = world.terrain.data.get_height(world.player.global_position)
	centre.y = (h if not is_nan(h) else 50.0) + 30.0
	mi.position = centre
	add_child(mi)
	_haze[loc] = mi


func _hide_haze(loc: Vector2i) -> void:
	if _haze != null and _haze.has(loc):
		_haze[loc].queue_free()
		_haze.erase(loc)


var _refreshing := false


## A tile whose pack an older pipeline built is loaded first and rebuilt afterwards - the place is
## complete either way, and holding the player at the edge for a rebuild they did not ask for would
## be a worse trade than a minute of the map's older colours. One at a time, behind the fetch queue.
func _refresh_stale() -> void:
	if _refreshing or _loading or _busy or not _queue.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	for loc in tiles:
		if loc == Vector2i.ZERO or not is_ready(loc) or not Sites.is_stale(str(tiles[loc].pack)):
			continue
		if now >= float(tiles[loc].get("refresh_at", 0.0)):
			_refreshing = true
			await refresh_tile(loc)
			_refreshing = false
			return


## Rebuild a standing tile's pack in place and swap the result in. A refresh rewrites the pack's
## register files and leaves user://tiles alone, so no Terrain3D region is added or removed: the
## swap costs a scene re-instance rather than the second-long region churn of an unload, and the
## ground the player can see never blinks.
##
## The tile stays usable for the whole fetch and is marked "loading" only for the moment of the
## swap. Even that moment is refused while the player is standing in the tile - guard() would put
## them back at its edge and hold them there - or is inside a room that the era scene owns.
## Returns true when the swap happened.
func refresh_tile(loc: Vector2i) -> bool:
	if loc == Vector2i.ZERO or not is_ready(loc) or world == null:
		return false   # the origin tile is the active pack: the menu refreshes that one on the way in
	if not _may_swap(loc):
		return false
	var t: Dictionary = tiles[loc]
	var pack: String = t.pack
	print("[Tiles] refreshing %s at %s" % [pack, loc])
	var held := Locator.job_owner
	Locator.job_owner = "stream"
	var r: Dictionary = await Locator.refresh_pack(pack)
	Locator.job_owner = held   # the backfill may be the one that asked for this
	if not tiles.has(loc) or tiles[loc] != t:
		return false   # unloaded while the service worked
	if not r.get("ok", false):
		t.refresh_at = Time.get_ticks_msec() / 1000.0 + RETRY_S
		print("[Tiles] %s not refreshed: %s" % [pack, str(r.get("error", ""))])
		return false
	if not _may_swap(loc):
		# the files on disk are new; the tile in front of them is not. The next tick tries again.
		return false
	# Everything hanging off the old root came out of files that have just been rewritten. _load
	# skips the region (it is still registered) and rebuilds the water and the era from the new ones.
	t.state = "loading"
	tile_unloaded.emit(loc)
	if t.get("root"):
		t.root.queue_free()
		t.root = null
	await _load(loc)
	return is_ready(loc)


## Whether a tile can be pulled down and rebuilt without the player noticing from the inside.
func _may_swap(loc: Vector2i) -> bool:
	if Interiors.instance and Interiors.instance.inside:
		return false   # the room around them is an instance of the scene about to be replaced
	var player: Node3D = world.player
	return player == null or tile_of(player.global_position) != loc


func _unload(loc: Vector2i) -> void:
	var t: Dictionary = tiles[loc]
	PerfLog.mark("tile unload %s" % t.pack)
	tile_unloaded.emit(loc)
	if t.get("root"):
		t.root.queue_free()
	var t_rm := Time.get_ticks_msec()
	world.terrain.data.remove_regionl(loc, true)
	PerfLog.mark("remove_region %d ms" % (Time.get_ticks_msec() - t_rm))
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
		if enabled and st != "unavailable":
			EventBus.notice.emit(tr("NOTICE_EDGE_PENDING") + ("  (%s)" % _stage if _stage != "" and st == "fetching" else ""))
		else:
			EventBus.notice.emit(tr("NOTICE_EDGE_NONE"))
