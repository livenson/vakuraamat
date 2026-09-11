# Roads from ETAK (sites/<id>/roads.json) as ribbons laid on the terrain: asphalt with a pale kerb for
# streets, light paving for pedestrian and cycle paths (kergliiklustee), gravel for other roads and
# trails. Heights are sampled every few metres so the ribbon follows the ground; a small lift keeps it
# above the drape. One mesh per kind. Hover text and the codes overlay read `nearest()`.
class_name RoadNetwork
extends Node3D

@export var source := "roads.json"     # inside the active pack
@export var lift := 0.08
const STEP := 3.0
const STYLE := {
	"street": {"color": Color(0.16, 0.16, 0.17), "kerb": Color(0.7, 0.68, 0.63), "rough": 0.95},
	"road": {"color": Color(0.48, 0.44, 0.36), "kerb": null, "rough": 1.0},
	"path": {"color": Color(0.62, 0.6, 0.56), "kerb": Color(0.5, 0.48, 0.45), "rough": 0.95},
	"trail": {"color": Color(0.42, 0.36, 0.26), "kerb": null, "rough": 1.0},
}

var roads: Array = []
var _lamps: Array[OmniLight3D] = []   # street lights, on after dark (set_lit)
const LAMP_SPACING := 32.0
const LAMP_HEIGHT := 6.0


func _ready() -> void:
	var text := FileAccess.get_file_as_string(Sites.path_in(Sites.pack_of(self), source))
	var parsed = JSON.parse_string(text) if text != "" else null
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	roads = parsed.get("roads", [])   # nearest() and the codes overlay read these from the start
	var terrain: Terrain3D = GameState.world.terrain if GameState.world else null
	if terrain == null:
		return
	_build(terrain)   # not awaited: the pieces arrive over the next frames


const ARRIVING := "arriving"   # nodes still building what they show; the world's loading screen waits for them
const BUILD_BUDGET_USEC := 8000
var _slice_start := 0


## Past the frame's budget, wait for the next frame. False when the network left the tree meanwhile.
func _breathe() -> bool:
	if Time.get_ticks_usec() - _slice_start > BUILD_BUDGET_USEC:
		await get_tree().process_frame
		_slice_start = Time.get_ticks_usec()
	return is_inside_tree()


## The ribbons, the street lights, the bus stops and the billboards, a few milliseconds a frame: a
## city tile's 687 roads with their 600 lamps and 30 shelters were a second in one frame (debug build),
## the loading screen standing still and a streamed tile's arrival a hitch.
func _build(terrain: Terrain3D) -> void:
	add_to_group(ARRIVING)
	var t0 := Time.get_ticks_usec()
	_slice_start = t0
	var tools := {}   # "<kind>" and "<kind>_kerb" -> SurfaceTool; one plain material each
	for r in roads:
		if not await _breathe():
			return
		var kind := str(r.get("kind", "road"))
		var style: Dictionary = STYLE.get(kind, STYLE.road)
		for key in [kind, kind + "_kerb"]:
			if not tools.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[key] = st
		var pts := _resample(r.points)
		var half: float = maxf(float(r.get("width", 3.0)), 1.2) / 2.0
		_ribbon(tools[kind], pts, half, terrain, lift, 0.0)
		if style.kerb != null:
			for side_sign in [-1.0, 1.0]:
				_ribbon(tools[kind + "_kerb"], pts, 0.18, terrain, lift + 0.05, side_sign * (half + 0.18))
	for key in tools:
		var st: SurfaceTool = tools[key]
		var mesh: ArrayMesh = st.commit()
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var kind: String = str(key).trim_suffix("_kerb")
		var style: Dictionary = STYLE.get(kind, STYLE.road)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = style.kerb if key.ends_with("_kerb") else style.color
		mat.roughness = style.rough
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.name = "Roads_" + key
		add_child(mi)
	var lit: bool = await _street_lights(terrain)
	if not lit:
		return
	var stops: bool = await _bus_stops(terrain)
	if not stops:
		return
	_billboards(terrain)
	remove_from_group(ARRIVING)
	PerfLog.mark("roads %d built over %d ms" % [roads.size(), (Time.get_ticks_usec() - t0) / 1000])


const POSTER_RECT := Rect2(0.793, 0.674, 0.198, 0.317)   # the second advert panel in the town shelter's atlas (UV space)
const POSTER_REACH := 300.0
# The timetable panel, the one shelter_board.py bakes SÕIDUPLAAN onto. Same atlas, same reverse face.
const BOARD_RECT := Rect2(0.581, 0.674, 0.200, 0.317)

## The advert panel of a town shelter shows the nearest registered companies: a poster is rendered
## in a viewport and painted over the panel's part of the shelter's texture (a copy per shelter).
## No company within reach: the baked timetable stays.
func _poster(model: Node3D, at: Vector2) -> void:
	var pack := Sites.pack_of(self)
	var found: Array = []   # [distance, name]
	for u in Parcels.units(pack):
		var d := Vector2(float(u.get("x", 0.0)), float(u.get("z", 0.0))).distance_to(at)
		if d > POSTER_REACH:
			continue
		for n in Tenants.active_names(pack, str(u.get("tunnus", ""))):
			found.append([d, n])
	if found.is_empty():
		return
	found.sort_custom(func(a, b): return a[0] < b[0])
	var names: Array[String] = []
	for f in found:
		if not names.has(f[1]):
			names.append(f[1])
		if names.size() == 2:
			break
	var mi: MeshInstance3D = model.find_children("*", "MeshInstance3D", true, false)[0] if not model.find_children("*", "MeshInstance3D", true, false).is_empty() else null
	if mi == null or mi.mesh == null or mi.mesh.get_surface_count() == 0:
		return
	var mat: Material = mi.mesh.surface_get_material(0)
	if not (mat is BaseMaterial3D) or (mat as BaseMaterial3D).albedo_texture == null:
		return
	var atlas: Image = (mat as BaseMaterial3D).albedo_texture.get_image()
	if atlas == null:
		return
	atlas = atlas.duplicate()
	if atlas.is_compressed():
		atlas.decompress()
	atlas.convert(Image.FORMAT_RGBA8)
	var px := Rect2i(int(POSTER_RECT.position.x * atlas.get_width()), int(POSTER_RECT.position.y * atlas.get_height()),
		int(POSTER_RECT.size.x * atlas.get_width()), int(POSTER_RECT.size.y * atlas.get_height()))
	var poster: Image = await _render_poster(names, px.size)
	if poster == null:
		return
	poster.convert(Image.FORMAT_RGBA8)   # the viewport hands back RGB8; blit_rect wants matching formats
	poster.flip_x()   # the second panel is the board's reverse face: its UVs run right to left
	if poster.get_size() != px.size:
		poster.resize(px.size.x, px.size.y)
	atlas.blit_rect(poster, Rect2i(Vector2i.ZERO, px.size), px.position)
	var own: BaseMaterial3D = mat.duplicate()
	own.albedo_texture = ImageTexture.create_from_image(atlas)
	if is_instance_valid(mi):
		mi.set_surface_override_material(0, own)


## A poster image: a colour drawn from the first line, the lines in white, the place below.
func _render_poster(names: Array[String], size: Vector2i, pack: String = "") -> Image:
	var vp := SubViewport.new()
	vp.size = size
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.transparent_bg = false
	var bg := ColorRect.new()
	var hue := float(hash(names[0]) % 360) / 360.0
	bg.color = Color.from_hsv(hue, 0.55, 0.55)
	bg.size = size
	vp.add_child(bg)
	var band := ColorRect.new()
	band.color = Color(1, 1, 1, 0.9)
	band.position = Vector2(0, size.y * 0.76)
	band.size = Vector2(size.x, size.y * 0.24)
	vp.add_child(band)
	var box := VBoxContainer.new()
	box.position = Vector2(size.x * 0.08, size.y * 0.08)
	box.size = Vector2(size.x * 0.84, size.y * 0.64)
	box.add_theme_constant_override("separation", int(size.y * 0.04))
	vp.add_child(box)
	for i in names.size():
		var l := Label.new()
		l.text = names[i]
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_font_size_override("font_size", int(size.y * (0.085 if i == 0 else 0.06)))
		l.add_theme_color_override("font_color", Color.WHITE)
		box.add_child(l)
	var place := Label.new()
	place.text = Sites.display_name(pack if pack != "" else Sites.pack_of(self))
	place.position = Vector2(size.x * 0.08, size.y * 0.8)
	place.size = Vector2(size.x * 0.84, size.y * 0.16)
	place.add_theme_font_size_override("font_size", int(size.y * 0.05))
	place.add_theme_color_override("font_color", Color(0.15, 0.15, 0.2))
	vp.add_child(place)
	add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = vp.get_texture().get_image()
	vp.queue_free()
	return img


## The stop's sheet (E): what the register says calls here, the whole day's times per line, and
## which bus is next by the world's clock.
func _stop_sheet(st: Dictionary, pack: String) -> String:
	var lines: Array[String] = [tr("UI_BUS_STOP")]
	if st.get("road_name"):
		lines.append(str(st.road_name))
	var stop_id := str(st.get("id", ""))
	var serving := Departures.at_stop(pack, stop_id)
	if serving.is_empty():
		# no timetable in the pack: the OSM route_ref is all there is, and it is usually empty
		var refs := str(st.get("refs", ""))
		lines.append(tr("UI_BUS_LINES") % refs if refs != "" else tr("UI_BUS_NO_SERVICE"))
		return "\n".join(lines)
	var hour: float = GameState.world.sky.tod.current_time if GameState.world and GameState.world.sky and GameState.world.sky.tod else 12.0
	var next := Departures.next_from(pack, stop_id, hour, 4)
	if not next.is_empty():
		lines.append("")
		lines.append(tr("UI_BUS_NEXT"))
		for n in next:
			lines.append("   %s  %s  %s  (%s)" % [n.line, n.time, n.headsign, tr("UI_BUS_IN_MIN") % int(n.minutes)])
	var day := Departures.today(pack)
	for r in serving:
		var times: Array = Departures.times_of(r, day)
		if times.is_empty():
			continue
		lines.append("")
		lines.append("%s  %s" % [str(r.line), str(r.headsign)])
		for row in _by_hour(times):
			lines.append("   " + row)
	return "\n".join(lines)


## "06   05  25  45" per hour, the way a stop's board prints a day.
static func _by_hour(times: Array) -> Array[String]:
	var hours: Dictionary = {}
	for t in times:
		var bits := str(t).split(":")
		if bits.size() == 2:
			hours.get_or_add(bits[0], []).append(bits[1])
	var out: Array[String] = []
	for h in hours.keys():
		out.append("%s   %s" % [h, "  ".join(hours[h])])
	out.sort()
	return out


## The register's timetable painted over the panel shelter_board.py baked. Same per-shelter copy as
## the advert poster: the pixels and the material are duplicated so the shared atlas is untouched.
func _timetable(model: Node3D, stop_id: String, pack: String) -> void:
	var serving := Departures.at_stop(pack, stop_id)
	if serving.is_empty():
		return   # nothing real to say: the baked board stays
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	var mi: MeshInstance3D = meshes[0] if not meshes.is_empty() else null
	if mi == null or mi.mesh == null or mi.mesh.get_surface_count() == 0:
		return
	var mat: Material = mi.get_surface_override_material(0)
	if mat == null:
		mat = mi.mesh.surface_get_material(0)
	if not (mat is BaseMaterial3D) or (mat as BaseMaterial3D).albedo_texture == null:
		return
	var atlas: Image = (mat as BaseMaterial3D).albedo_texture.get_image()
	if atlas == null:
		return
	atlas = atlas.duplicate()
	if atlas.is_compressed():
		atlas.decompress()
	atlas.convert(Image.FORMAT_RGBA8)
	var px := Rect2i(int(BOARD_RECT.position.x * atlas.get_width()), int(BOARD_RECT.position.y * atlas.get_height()),
		int(BOARD_RECT.size.x * atlas.get_width()), int(BOARD_RECT.size.y * atlas.get_height()))
	var board: Image = await _render_timetable(serving, Departures.today(pack), px.size)
	if board == null or not is_instance_valid(mi):
		return
	board.convert(Image.FORMAT_RGBA8)
	board.flip_x()   # this panel is the board's reverse face, as the poster's is
	if board.get_size() != px.size:
		board.resize(px.size.x, px.size.y)
	atlas.blit_rect(board, Rect2i(Vector2i.ZERO, px.size), px.position)
	var own: BaseMaterial3D = mat.duplicate()
	own.albedo_texture = ImageTexture.create_from_image(atlas)
	mi.set_surface_override_material(0, own)


## A timetable image in the shape an Estonian stop prints one: a blue head, then each line with its
## destination and the hours it leaves, minutes across.
func _render_timetable(serving: Array, day: String, size: Vector2i) -> Image:
	var vp := SubViewport.new()
	vp.size = size
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.transparent_bg = false
	var bg := ColorRect.new()
	bg.color = Color(0.925, 0.925, 0.902)
	bg.size = size
	vp.add_child(bg)
	var head := ColorRect.new()
	head.color = Color(0.078, 0.235, 0.471)
	head.size = Vector2(size.x, size.y * 0.12)
	vp.add_child(head)
	var title := Label.new()
	title.text = tr("UI_BUS_TIMETABLE").to_upper()
	title.position = Vector2(size.x * 0.06, size.y * 0.015)
	title.add_theme_font_size_override("font_size", int(size.y * 0.062))
	title.add_theme_color_override("font_color", Color.WHITE)
	vp.add_child(title)
	# lay the rows out first: a terminus carries two whole days of times, so the type is sized to
	# what there is rather than the list cut off at the bottom edge of the panel
	var rows: Array = []
	for r in serving:
		var times: Array = Departures.times_of(r, day)
		if times.is_empty():
			continue
		rows.append({"head": true, "line": str(r.line), "dest": str(r.headsign)})
		for line in _by_hour(times):
			rows.append({"head": false, "text": line})
	if rows.is_empty():
		rows.append({"head": false, "text": tr("UI_BUS_NO_SERVICE")})
	var box := VBoxContainer.new()
	box.position = Vector2(size.x * 0.05, size.y * 0.15)
	box.size = Vector2(size.x * 0.9, size.y * 0.83)
	var step := minf(size.y * 0.048, size.y * 0.83 / maxf(rows.size(), 1.0))
	box.add_theme_constant_override("separation", int(maxf(step * 0.12, 1.0)))
	vp.add_child(box)
	for row in rows:
		if row.head:
			var head_row := HBoxContainer.new()
			head_row.add_theme_constant_override("separation", int(size.x * 0.03))
			box.add_child(head_row)
			var badge := Label.new()
			badge.text = " %s " % row.line
			badge.add_theme_font_size_override("font_size", int(step * 0.88))
			badge.add_theme_color_override("font_color", Color.WHITE)
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.078, 0.235, 0.471)
			badge.add_theme_stylebox_override("normal", sb)
			head_row.add_child(badge)
			var dest := Label.new()
			dest.text = row.dest
			dest.add_theme_font_size_override("font_size", int(step * 0.88))
			dest.add_theme_color_override("font_color", Color(0.16, 0.16, 0.16))
			head_row.add_child(dest)
		else:
			var l := Label.new()
			l.text = row.text
			l.add_theme_font_size_override("font_size", int(step * 0.72))
			l.add_theme_color_override("font_color", Color(0.35, 0.35, 0.35))
			box.add_child(l)
	add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = vp.get_texture().get_image()
	vp.queue_free()
	return img


const BILLBOARD_MODEL := "res://assets/vendor/sketchfab/billboard.glb"   # jeffkolada, CC BY
const BILLBOARD_SPACING := 400.0


## Roadside billboards on the roads (not the streets): one every BILLBOARD_SPACING metres, facing
## the traffic, each with a poster of one of the tile's biggest employers (round-robin).
func _billboards(terrain: Terrain3D) -> void:
	if not ResourceLoader.exists(BILLBOARD_MODEL):
		return
	var pack := Sites.pack_of(self)
	var firms: Array = []
	for u in Parcels.units(pack):
		for t in Tenants.of(pack, str(u.get("tunnus", ""))):
			if str(t.get("status", "")) == "R" and t.get("employees") != null and int(t.employees) >= 3:
				firms.append(t)
	if firms.is_empty():
		return
	firms.sort_custom(func(a, b): return int(a.employees) > int(b.employees))
	firms = firms.slice(0, 6)
	var scene: PackedScene = load(BILLBOARD_MODEL)
	var probe: Node3D = scene.instantiate()
	var b: AABB = Interiors._bounds(probe)
	probe.free()
	var k := 6.0 / maxf(b.size.x, 0.01)   # a 6 m wide board
	var i := 0
	var along := BILLBOARD_SPACING * 0.5
	var acc := 0.0
	for r in roads:
		if str(r.get("kind", "road")) != "road":
			continue
		var pts := _resample(r.points)
		var half: float = maxf(float(r.get("width", 3.0)), 1.2) / 2.0
		for j in range(1, pts.size()):
			var a: Vector2 = pts[j - 1]
			var c: Vector2 = pts[j]
			var seg := a.distance_to(c)
			while acc + seg >= along:
				var tt := (along - acc) / maxf(seg, 0.001)
				var dir := (c - a).normalized()
				var side := 1.0 if i % 2 == 0 else -1.0
				var at := a.lerp(c, tt) + Vector2(-dir.y, dir.x) * side * (half + 6.0)
				var h: float = terrain.data.get_height(to_global(Vector3(at.x, 0.0, at.y)))
				if not is_nan(h):
					var model: Node3D = scene.instantiate()
					model.scale = Vector3.ONE * k
					model.position = Vector3(-(b.position.x + b.size.x * 0.5) * k, -b.position.y * k, -(b.position.z + b.size.z * 0.5) * k)
					var holder := Node3D.new()
					holder.name = "Billboard_%d" % i
					holder.position = Vector3(at.x, h - global_position.y, at.y)
					# the panel faces +Z: turn it to look back along the road at the traffic coming this way
					var face := -dir if side > 0.0 else dir
					holder.rotation.y = atan2(face.x, face.y) + (PI * 0.25 * side)
					holder.add_child(model)
					add_child(holder)
					_poster_panel(model, firms[i % firms.size()], pack)
					i += 1
				along += BILLBOARD_SPACING
			acc += seg
	if i > 0:
		var first: Node3D = get_node("Billboard_0")
		print("[roads] %d billboards for %d firms, first at %s yaw %.0f" % [i, firms.size(), first.position, rad_to_deg(first.rotation.y)])


## The poster: the model's own panel repainted. The board ships with a template texture (a colour
## grid reading "Billboard 48' x 14'"), which is what stood by the road; the panel is its own mesh
## with its own material ("billboard-grid"), so overriding that surface puts the firm exactly where
## the template was, at the panel's own mapping. A quad hung in front of the board instead of this
## missed it: the model's panel does not face the holder's +Z, which is why the placement carries a
## 45 degree correction.
func _poster_panel(model: Node3D, firm: Dictionary, pack: String) -> void:
	var panel: MeshInstance3D = null
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or mi.mesh.get_surface_count() == 0:
			continue
		var m: Material = mi.mesh.surface_get_material(0)
		if m and str(m.resource_name).begins_with("billboard-grid"):
			panel = mi
			break
	if panel == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.85, 0.85)   # until the poster is drawn, a blank board, not the grid
	mat.roughness = 0.85
	panel.set_surface_override_material(0, mat)
	var lines: Array[String] = [str(firm.get("name", ""))]
	if firm.get("emtak") and firm.emtak.get("text"):
		lines.append(str(firm.emtak.text))
	elif firm.get("sector"):
		lines.append(tr("SECTOR_" + str(firm.sector).to_upper()))
	_paint_poster.call_deferred(mat, lines, Vector2i(1024, 300), pack)   # the panel is 18.2 x 5.3, near 3.4:1


func _paint_poster(mat: StandardMaterial3D, lines: Array[String], size: Vector2i, pack: String) -> void:
	var img: Image = await _render_poster(lines, size, pack)
	if img and is_instance_valid(mat):
		mat.albedo_texture = ImageTexture.create_from_image(img)
		mat.albedo_color = Color(1, 1, 1)


const STOP_MODELS := {"rural": "res://assets/vendor/sketchfab/bus_stop_rural.glb", "town": "res://assets/vendor/sketchfab/bus_stop_town.glb"}   # Ottto3ds, CC BY


## Bus shelters where OpenStreetMap has a stop (tools/pipeline/fetch_stops.py writes stops.json with
## each stop moved to the roadside and its heading): the Soviet-era shelter on roads, the small
## modern one on streets; the timetable board is readable (E) with the stop's name and lines.
func _bus_stops(terrain: Terrain3D) -> bool:
	var pack := Sites.pack_of(self)
	var path := Sites.path_in(pack, "stops.json")
	if not FileAccess.file_exists(path):
		return true
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return true
	var scenes := {}
	var bounds := {}
	for key in STOP_MODELS:
		if ResourceLoader.exists(STOP_MODELS[key]):
			scenes[key] = load(STOP_MODELS[key])
			var probe: Node3D = scenes[key].instantiate()
			bounds[key] = Interiors._bounds(probe)   # the open front faces +Z
			probe.free()
	if scenes.is_empty():
		return true
	for st in parsed.get("stops", []):
		if not await _breathe():
			return false
		var kind: String = "town" if str(st.get("road_kind", "")) == "street" else "rural"
		if not scenes.has(kind):
			kind = scenes.keys()[0]
		var at := Vector2(float(st.get("x", 0.0)), float(st.get("z", 0.0)))
		var gp := to_global(Vector3(at.x, 0.0, at.y))
		var h: float = terrain.data.get_height(gp)
		if is_nan(h):
			continue
		var b: AABB = bounds[kind]
		var k := (3.4 if kind == "town" else 3.0) / maxf(b.size.x, 0.01)
		var model: Node3D = scenes[kind].instantiate()
		model.scale = Vector3.ONE * k
		model.position = Vector3(-(b.position.x + b.size.x * 0.5) * k, -b.position.y * k, -(b.position.z + b.size.z * 0.5) * k)
		var holder := Node3D.new()
		holder.name = "Stop_" + str(st.get("id", ""))
		holder.position = Vector3(at.x, h - global_position.y, at.y)
		holder.rotation.y = float(st.get("yaw", 0.0))
		holder.add_child(model)
		if kind == "town":
			_poster(model, at)   # the shelter's advert panel: the nearest registered companies
		var body := StaticBody3D.new()
		body.collision_layer = 1
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(b.size.x * k, b.size.y * k, b.size.z * k * 0.5)
		shape.shape = box
		shape.position = Vector3(0, box.size.y * 0.5, -b.size.z * k * 0.25)   # the back half: the front stays open to stand in
		body.add_child(shape)
		holder.add_child(body)
		var board := Readable.new()
		var name := str(st.get("name", ""))
		board.setup(name if name != "" else tr("UI_BUS_STOP"), _stop_sheet(st, pack), Vector3(b.size.x * k, b.size.y * k, b.size.z * k))
		board.position = Vector3(0, b.size.y * k * 0.5, 0)
		holder.add_child(board)
		add_child(holder)
		if kind == "town":
			_timetable(model, str(st.get("id", "")), pack)   # the register's own times over the baked board
	return true


## Lamp posts along the streets (asphalt with a kerb): one every LAMP_SPACING metres on the right
## side, alternating sides on long streets. Dark by day; set_lit turns the lamps on.
const LAMP_MODEL := "res://assets/vendor/sketchfab/street_lamp.glb"   # pinokio21, CC BY (THIRD_PARTY.md)


func _street_lights(terrain: Terrain3D) -> bool:
	var lamp_scene: PackedScene = load(LAMP_MODEL) if ResourceLoader.exists(LAMP_MODEL) else null
	var lamp_bounds := AABB()
	if lamp_scene:
		var probe: Node3D = lamp_scene.instantiate()
		lamp_bounds = Interiors._bounds(probe)   # the arm points to -X in the model, the base sits at y 0
		probe.free()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.06
	pole_mesh.bottom_radius = 0.09
	pole_mesh.height = LAMP_HEIGHT
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.35, 0.36, 0.38)
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.5, 0.18, 0.28)
	var head_mat := StandardMaterial3D.new()
	head_mat.albedo_color = Color(0.9, 0.85, 0.7)
	head_mat.emission_enabled = true
	head_mat.emission = Color(1.0, 0.85, 0.6)
	head_mat.emission_energy_multiplier = 3.0 if _lit else 0.0
	_head_mat = head_mat
	var side := 1.0
	var cells: Dictionary = {}   # Vector2i -> {poles, heads}: transforms, one MultiMesh each per cell
	for r in roads:
		if str(r.get("kind", "road")) != "street":
			continue
		if not await _breathe():
			return false
		var pts := _resample(r.points)
		var half: float = maxf(float(r.get("width", 3.0)), 1.2) / 2.0
		var along := LAMP_SPACING * 0.5
		var acc := 0.0
		for i in range(1, pts.size()):
			var a: Vector2 = pts[i - 1]
			var c: Vector2 = pts[i]
			var seg := a.distance_to(c)
			while acc + seg >= along:
				var t := (along - acc) / maxf(seg, 0.001)
				var dir := (c - a).normalized()
				var at := a.lerp(c, t) + Vector2(-dir.y, dir.x) * side * (half + 0.9)
				var gp := to_global(Vector3(at.x, 0.0, at.y))
				var h: float = terrain.data.get_height(gp)
				if not is_nan(h):
					var base := Vector3(at.x, h - global_position.y, at.y)
					var toward := Vector2(-dir.y, dir.x) * -side   # across the road, from the lamp
					var arm := toward * 0.35   # the head leans over the road
					if lamp_scene and lamp_bounds.size.y > 0.01:
						# the vendored lamp: its height fitted to LAMP_HEIGHT, its -X arm turned over the road
						var k := LAMP_HEIGHT / lamp_bounds.size.y
						var model_xf := Transform3D(Basis.from_scale(Vector3.ONE * k), Vector3(-(lamp_bounds.position.x + lamp_bounds.size.x) * k, -lamp_bounds.position.y * k, -(lamp_bounds.position.z + lamp_bounds.size.z * 0.5) * k))
						var turn_xf := Transform3D(Basis(Vector3.UP, atan2(toward.x, toward.y) + PI / 2.0), base)
						_lamp_cell(cells, at).poles.append(turn_xf * model_xf)
						arm = toward * maxf(lamp_bounds.size.x * k - 0.2, 0.3)
						head_mesh.size = Vector3(0.3, 0.08, 0.2)
					else:
						_lamp_cell(cells, at).poles.append(Transform3D(Basis(), base + Vector3(0, LAMP_HEIGHT / 2.0, 0)))
					# the glowing lamp itself, also over the model's head
					var head_pos := base + Vector3(arm.x, LAMP_HEIGHT - 0.1, arm.y)
					_lamp_cell(cells, at).heads.append(Transform3D(Basis(Vector3.UP, -atan2(dir.y, dir.x)), head_pos))
					var lamp := OmniLight3D.new()
					lamp.position = head_pos - Vector3(0, 0.25, 0)
					lamp.light_color = Color(1.0, 0.82, 0.55)
					lamp.light_energy = 2.2
					lamp.omni_range = 16.0
					lamp.omni_attenuation = 1.2
					lamp.shadow_enabled = false
					lamp.distance_fade_enabled = true   # a street has hundreds: only the near ones light the ground
					lamp.distance_fade_begin = LIGHT_FADE
					lamp.distance_fade_length = 30.0
					lamp.visible = false
					add_child(lamp)
					_lamps.append(lamp)
				along += LAMP_SPACING
				side = -side
			acc += seg
	var pole_draw: Mesh = MeshMerge.baked(LAMP_MODEL) if lamp_scene and lamp_bounds.size.y > 0.01 else pole_mesh
	for cell: Vector2i in cells:
		_lamp_multimesh(pole_draw, null if pole_draw != pole_mesh else pole_mat, cells[cell].poles, POLE_RANGE, true)
		_lamp_multimesh(head_mesh, head_mat, cells[cell].heads, HEAD_RANGE, false)
	return true


# Street lights drawn as MultiMeshes, one per LAMP_CELL square and part, so a city tile's 600
# lamps are a few dozen draw calls that still cull by cell (they were 1900 nodes, each drawn).
const LAMP_CELL := 128.0
const POLE_RANGE := 450.0    # a pole is a hairline beyond this
const HEAD_RANGE := 900.0    # the lit heads string along the streets at night
const LIGHT_FADE := 110.0    # lights that reach the ground; the heads carry the look beyond


static func _lamp_cell(cells: Dictionary, at: Vector2) -> Dictionary:
	var c := Vector2i(floori(at.x / LAMP_CELL), floori(at.y / LAMP_CELL))
	if not cells.has(c):
		cells[c] = {"poles": [], "heads": []}
	return cells[c]


func _lamp_multimesh(mesh: Mesh, mat: Material, xforms: Array, range_end: float, shadows: bool) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if mat:
		mmi.material_override = mat
	mmi.visibility_range_end = range_end
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


var _head_mat: StandardMaterial3D = null
var _lit := false


## Street lights on or off (the era controller calls this with the windows after dark).
func set_lit(on: bool) -> void:
	_lit = on
	for l in _lamps:
		l.visible = on
	if _head_mat:
		_head_mat.emission_energy_multiplier = 3.0 if on else 0.0


func _resample(points: Array) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in range(points.size() - 1):
		var a := Vector2(float(points[i][0]), float(points[i][1]))
		var b := Vector2(float(points[i + 1][0]), float(points[i + 1][1]))
		var n := maxi(1, int(a.distance_to(b) / STEP))
		for k in n:
			out.append(a.lerp(b, float(k) / n))
	var last: Array = points[points.size() - 1]
	out.append(Vector2(float(last[0]), float(last[1])))
	return out


## A strip `half` wide, `offset` metres to the side of the centre line, `up` above the ground.
func _ribbon(st: SurfaceTool, pts: Array[Vector2], half: float, terrain: Terrain3D, up: float, offset: float) -> void:
	if pts.size() < 2:
		return
	var left: Array[Vector3] = []
	var right: Array[Vector3] = []
	for i in pts.size():
		var dir := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var normal := Vector2(-dir.y, dir.x)
		var p := pts[i] + normal * offset
		var side := normal * half
		for s in [p + side, p - side]:
			var h := terrain.data.get_height(to_global(Vector3(s.x, 0, s.y)))
			if is_nan(h):
				h = 0.0
			(left if s == p + side else right).append(Vector3(s.x, h + up, s.y))
	for i in range(pts.size() - 1):
		var a := left[i]
		var b := right[i]
		var c := right[i + 1]
		var d := left[i + 1]
		for v in [a, b, c, a, c, d]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)


## Nearest road segment to a tile position: {name, kind, type, width, surface, distance}.
func nearest(pos: Vector3, max_dist := 12.0) -> Dictionary:
	var best := {}
	var best_d := max_dist
	var local := to_local(pos)
	var p2 := Vector2(local.x, local.z)
	for r in roads:
		var pts: Array = r.points
		for i in range(pts.size() - 1):
			var a := Vector2(float(pts[i][0]), float(pts[i][1]))
			var b := Vector2(float(pts[i + 1][0]), float(pts[i + 1][1]))
			var d := p2.distance_to(Geometry2D.get_closest_point_to_segment(p2, a, b))
			if d < best_d:
				best_d = d
				best = {"name": r.get("name"), "kind": r.kind, "type": r.get("type"), "width": r.get("width"), "surface": r.get("surface"), "distance": snappedf(d, 0.1), "id": r.get("id")}
	return best
