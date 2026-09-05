# Interiors you can walk into. Every real building gets a BuildingDoor; the first time the player steps
# in, an interior is generated from the footprint: a floor slab per storey, inner walls with window
# openings on the exterior's rhythm and a gap at the door, a ceiling, a ramp between storeys, a warm
# light and furniture by use (Kenney Furniture Kit models when vendored, coloured boxes otherwise).
# While inside, the exterior mesh and collider hide, so the openings look out at the real street.
class_name Interiors
extends Node3D

const KIT := "res://assets/vendor/kenney_furniture_kit/glb/"
const WALL := 0.25          # inner wall inset from the footprint
const SLAB := 0.12
const MAX_FLOORS := 4
const PLANT_IDS := [5, 6, 7, 8, 9]   # TerrainBuilder.RULES bushes, grass, clover; trees (0..4) are measured and never touched
const ROOM_AREA := {"home": 28.0, "office": 45.0, "shop": 120.0, "workshop": 120.0}   # split rooms while larger than this
const MIN_ROOM := 9.0
const MAX_DEPTH := 3
const DOOR_W := 0.95
const DOOR_END := 0.6        # a doorway keeps this far from a wall's ends
const CLEAR := 1.2           # furniture keeps this far from doorways and the ramp

static var instance: Interiors

var world: Node3D
var inside: FootprintBuilding = null
var _interiors: Dictionary = {}     # building instance id -> Node3D
var _doors: Array = []
var _kit_cache: Dictionary = {}


func setup(w: Node3D) -> void:
	world = w
	instance = self
	EventBus.era_changed.connect(func(_e): call_deferred("attach_doors"))
	if w.streamer:
		w.streamer.tile_ready.connect(func(_loc: Vector2i, root: Node3D): call_deferred("attach_doors", root))
		w.streamer.tile_unloaded.connect(_on_tile_unloaded)
	call_deferred("attach_doors")


func _exit_tree() -> void:
	if instance == self:
		instance = null


## One door per real building of the origin layer, or of a streamed tile's root when given
## (outbuildings and huts excluded).
func attach_doors(scope: Node = null) -> void:
	var layer: Node = scope if scope else (world.get_node("EraLayers").get_node_or_null(GameState.current_era) if world else null)
	if layer == null or not is_instance_valid(layer):
		return
	var n := 0
	for b in layer.find_children("*", "FootprintBuilding", true, false):
		if b.has_meta("door") or b.kind == "outbuilding" or b.height < 2.4 or _area(b.polygon) < 18.0:
			continue
		var f: Dictionary = b.door_frame()
		if f.is_empty():
			continue
		var door := BuildingDoor.new()
		door.name = "Door"
		b.add_child(door)
		door.setup(b, f)
		b.set_meta("door", true)
		_doors.append(door)
		n += 1
	if n > 0:
		print("[interiors] %d doors" % n)


## A tile leaves: forget its doors and interiors; step out if the player was inside one of them.
func _on_tile_unloaded(loc: Vector2i) -> void:
	var root: Node = world.streamer.tiles.get(loc, {}).get("root") if world and world.streamer else null
	if root == null:
		return
	if inside and is_instance_valid(inside) and root.is_ancestor_of(inside):
		exit()
	_doors = _doors.filter(func(d): return is_instance_valid(d) and not root.is_ancestor_of(d))
	for id in _interiors.keys():
		var n = _interiors[id]
		if not is_instance_valid(n) or root.is_ancestor_of(n):
			_interiors.erase(id)


func _process(_delta: float) -> void:
	if inside == null or world == null:
		return
	if not is_instance_valid(inside):
		inside = null
		return
	var player: Node3D = world.get_node_or_null("Player")
	if player == null:
		return
	var local := inside.to_local(player.global_position)
	if not Geometry2D.is_point_in_polygon(Vector2(local.x, local.z), _grow(inside.polygon, 1.2)):
		exit()   # walked out through the door gap


func toggle(b: FootprintBuilding, player: Node3D) -> void:
	if inside == b:
		exit(player)
	else:
		enter(b, player)


func enter(b: FootprintBuilding, player: Node3D) -> void:
	if inside and inside != b:
		exit(player)
	var root := _interior_for(b)
	if root == null:
		return
	b.set_exterior_visible(false)
	root.visible = true
	_set_colliders(root, true)
	inside = b
	var f: Dictionary = b.door_frame()
	var n: Vector3 = f.n
	var spot: Vector3 = b.to_global(f.pos - n.normalized() * 1.4 + Vector3.UP * (float(root.get_meta("floor0")) + 0.2))
	if player and player.has_method("set_pose"):
		player.set_pose(spot, atan2(-n.x, -n.z) + PI, 0.0)
	EventBus.notice.emit(tr("NOTICE_ENTERED") % _door_label(b))


func exit(player: Node3D = null) -> void:
	if inside == null:
		return
	var b := inside
	inside = null
	if not is_instance_valid(b):
		return
	var root: Node3D = _interiors.get(b.get_instance_id())
	if root:
		root.visible = false
		_set_colliders(root, false)
	b.set_exterior_visible(true)
	if player and player.has_method("set_pose"):
		var f: Dictionary = b.door_frame()
		var n: Vector3 = f.n
		var spot: Vector3 = b.to_global(f.pos + n.normalized() * 1.2 + Vector3.UP * 0.3)
		player.set_pose(spot, atan2(-n.x, -n.z), 0.0)


func _set_colliders(root: Node3D, on: bool) -> void:
	for c in root.get_children():
		if c is StaticBody3D:
			c.collision_layer = 1 if on else 0


# ---------------------------------------------------------------- generation

func _interior_for(b: FootprintBuilding) -> Node3D:
	var id := b.get_instance_id()
	if _interiors.has(id) and is_instance_valid(_interiors[id]):
		return _interiors[id]
	var root := _build(b)
	if root:
		_interiors[id] = root
	return root


func _build(b: FootprintBuilding) -> Node3D:
	var poly: PackedVector2Array = _shrink(b.polygon, WALL)
	if poly.size() < 3:
		return null
	var f: Dictionary = b.door_frame()
	var st: Dictionary = b.storeys()
	var n_floors: int = mini(int(st.floors), MAX_FLOORS)
	var fh: float = float(st.floor_height)
	# the floor sits above the highest ground inside the footprint (the exterior stands on the lowest corner)
	var floor0 := 0.15
	if world.terrain and world.terrain.data:
		var base_y := b.global_position.y
		for p in b.polygon:
			var h: float = world.terrain.data.get_height(b.to_global(Vector3(p.x, 0, p.y)))
			if not is_nan(h):
				floor0 = maxf(floor0, h - base_y + 0.15)
	floor0 = minf(floor0, fh - 2.2)
	var root := Node3D.new()
	root.name = "Interior_%d" % b.building_id
	root.set_meta("floor0", floor0)
	root.visible = false
	b.add_child(root)
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.93, 0.9, 0.84)
	wall_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.55, 0.42, 0.28) if b.kind == "dwelling" else Color(0.6, 0.6, 0.58)
	floor_mat.roughness = 0.7
	var ceil_mat := StandardMaterial3D.new()
	ceil_mat.albedo_color = Color(0.82, 0.8, 0.76)
	var door_u := 0.0
	var door_edge := -1
	var door_pos: Vector3 = f.pos
	for i in poly.size():
		var a := poly[i]
		var c := poly[(i + 1) % poly.size()]
		var d := _dist_to_segment(Vector2(door_pos.x, door_pos.z), a, c)
		if door_edge < 0 or d < door_u:
			door_u = d
			door_edge = i
	_clear_plants(b)
	var tenants: Array = Tenants.of(Sites.pack_of(b), b.tunnus)
	var use := _use_of(b, tenants)
	var door_pt := Vector2(door_pos.x, door_pos.z)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("rooms_%d" % b.building_id)   # the same plan on every storey: rooms stack
	var walls: Array = []
	var rooms: Array = _partition(poly, use, rng, walls, door_pt)
	var doorways: Array = _place_doorways(walls, rng)
	_attach_doorways(rooms, doorways)
	_assign_roles(rooms, use, door_pt, false)
	var ramp_room: Dictionary = rooms[0]
	for r in rooms:
		if _area(r.poly) > _area(ramp_room.poly):
			ramp_room = r
	var ramp_edge := _ramp_edge(ramp_room.poly, door_pt, ramp_room.doorways)
	var landing := _ramp_landing(ramp_room.poly, ramp_edge, fh)
	var upper: Array = []
	for r in rooms:
		upper.append({"poly": r.poly, "role": "", "doorways": r.doorways})
	_assign_roles(upper, use, landing.get_center(), true)
	root.set_meta("splits", _split_count(walls))
	root.set_meta("doorways", doorways)
	root.set_meta("rooms", rooms.size())
	for k in n_floors:
		var y0 := floor0 + k * fh
		var y1 := y0 + fh
		var top := k == n_floors - 1
		_slab(root, poly, y0, floor_mat, true, [] if k == 0 else [landing])
		_slab(root, poly, y1 - SLAB, ceil_mat, false, [] if top or n_floors == 1 else [landing])
		for i in poly.size():
			var a := poly[i]
			var c := poly[(i + 1) % poly.size()]
			var gap := -1.0
			if k == 0 and i == door_edge:
				gap = _project_u(door_pt, a, c)
			_wall(root, a, c, y0, y1, wall_mat, b.kind, gap, float(f.width) + 0.3)
		_partition_walls(root, walls, y0, y1, wall_mat, b.kind)
		if not top:
			_ramp(root, ramp_room.poly, ramp_edge, y0, fh, wall_mat)
		var storey_rooms: Array = rooms if k == 0 else upper
		for idx in storey_rooms.size():
			var room: Dictionary = storey_rooms[idx]
			for spot in _lamp_spots(room.poly):
				var light := OmniLight3D.new()
				light.position = Vector3(spot.x, y0 + minf(2.2, fh - 0.6), spot.y)
				light.light_color = Color(1.0, 0.9, 0.75)
				light.light_energy = 4.0
				light.light_specular = 0.2
				light.omni_range = 12.0
				light.omni_attenuation = 1.0
				light.shadow_enabled = false
				root.add_child(light)
			var avoid: Array = room.doorways.duplicate()
			var skip: Array = []
			if k == 0:
				avoid.append(door_pt)
			if room.poly == ramp_room.poly:
				var rr := _ramp_rect(ramp_room.poly, ramp_edge, fh)
				if not top:
					skip.append(ramp_edge)
					avoid.append(rr[0])
				if k > 0 or not top:
					avoid.append(landing.get_center())
			_furnish(root, room.poly, y0, str(room.role), "%d_%d_%d" % [b.building_id, k, idx], skip, avoid)
	return root


# ---------------------------------------------------------------- rooms

## Rooms of a storey: a deterministic BSP of the inset polygon. Fills `walls` with the partition segments
## ({a, c, door_u: -1, split}); shops and workshops only split off a back room.
func _partition(poly: PackedVector2Array, use: String, rng: RandomNumberGenerator, walls: Array, door_pt: Vector2, depth: int = 0) -> Array:
	var limit: float = ROOM_AREA.get(use, 45.0)
	var once_only := use in ["shop", "workshop"]
	var leaf := [{"poly": poly, "role": "", "doorways": []}]
	if depth >= MAX_DEPTH or _area(poly) <= limit or (once_only and depth >= 1):
		return leaf
	var rect := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		rect = rect.expand(p)
	# cut across the longer axis, else the shorter; the cut keeps 1.5 m from the exterior door's coordinate
	var vertical := rect.size.x >= rect.size.y
	var cut := -1.0
	for attempt in 2:
		var span: float = rect.size.x if vertical else rect.size.y
		var lo_edge: float = rect.position.x if vertical else rect.position.y
		var door_c: float = door_pt.x if vertical else door_pt.y
		var options: Array = [rng.randf_range(0.42, 0.58), rng.randf_range(0.42, 0.58)] if not once_only else [0.25, 0.75]
		var best_d := -1.0
		for t in options:
			var c: float = lo_edge + span * t
			var d := absf(c - door_c)
			if d > best_d:
				best_d = d
				cut = c
		if best_d >= 1.5:
			break
		cut = -1.0
		vertical = not vertical
	if cut < 0.0:
		return leaf
	var pad := 5.0
	var half: PackedVector2Array
	if vertical:
		half = PackedVector2Array([Vector2(rect.position.x - pad, rect.position.y - pad), Vector2(cut, rect.position.y - pad), Vector2(cut, rect.end.y + pad), Vector2(rect.position.x - pad, rect.end.y + pad)])
	else:
		half = PackedVector2Array([Vector2(rect.position.x - pad, rect.position.y - pad), Vector2(rect.end.x + pad, rect.position.y - pad), Vector2(rect.end.x + pad, cut), Vector2(rect.position.x - pad, cut)])
	var lo := _largest(Geometry2D.intersect_polygons(poly, half))
	var hi := _largest(Geometry2D.clip_polygons(poly, half))
	if lo.size() < 3 or hi.size() < 3 or _area(lo) < MIN_ROOM or _area(hi) < MIN_ROOM:
		return leaf
	var split_id := _split_count(walls)
	var found := false
	for i in lo.size():
		var a := lo[i]
		var c := lo[(i + 1) % lo.size()]
		var on_line: bool = absf((a.x if vertical else a.y) - cut) < 0.02 and absf((c.x if vertical else c.y) - cut) < 0.02
		if not on_line or a.distance_to(c) < 0.5:
			continue
		var mid := (a + c) / 2.0 + (Vector2(0.05, 0) if vertical else Vector2(0, 0.05))
		if not Geometry2D.is_point_in_polygon(mid, hi):
			continue   # borders a discarded fragment: stays open, an alcove
		walls.append({"a": a, "c": c, "door_u": -1.0, "split": split_id})
		found = true
	if not found:
		return leaf
	return _partition(lo, use, rng, walls, door_pt, depth + 1) + _partition(hi, use, rng, walls, door_pt, depth + 1)


static func _split_count(walls: Array) -> int:
	var n := -1
	for w in walls:
		n = maxi(n, int(w.split))
	return n + 1


static func _largest(pieces: Array) -> PackedVector2Array:
	var best := PackedVector2Array()
	for p in pieces:
		if p.size() >= 3 and _area(p) > _area(best):
			best = p
	return best


## One doorway per split, placed after every split is known: on the split's longest segment, in the middle
## of its largest stretch free of other wall ends. A split too short for a door is dropped (stays open).
func _place_doorways(walls: Array, rng: RandomNumberGenerator) -> Array:
	var doorways: Array = []
	for split_id in _split_count(walls):
		var seg: Dictionary = {}
		for w in walls:
			if int(w.split) == split_id and (seg.is_empty() or w.a.distance_to(w.c) > seg.a.distance_to(seg.c)):
				seg = w
		if seg.is_empty():
			continue
		var a: Vector2 = seg.a
		var c: Vector2 = seg.c
		var length := a.distance_to(c)
		var dir := (c - a) / length
		var cuts := [0.0, length]
		for w in walls:
			if w == seg:
				continue
			for pt in [w.a, w.c]:
				if _dist_to_segment(pt, a, c) < 0.05:
					var u: float = (pt - a).dot(dir)
					if u > 0.0 and u < length:
						cuts.append(u)
		cuts.sort()
		var u0 := 0.0
		var u1 := 0.0
		for i in range(cuts.size() - 1):
			if cuts[i + 1] - cuts[i] > u1 - u0:
				u0 = cuts[i]
				u1 = cuts[i + 1]
		if u1 - u0 < DOOR_W + 2.0 * DOOR_END:
			for w in walls.duplicate():
				if int(w.split) == split_id:
					walls.erase(w)
			continue
		var door_u := clampf((u0 + u1) / 2.0 + rng.randf_range(-0.6, 0.6), u0 + DOOR_END + DOOR_W / 2.0, u1 - DOOR_END - DOOR_W / 2.0)
		seg.door_u = door_u
		doorways.append(a + dir * door_u)
	return doorways


## Every doorway lies on an edge of exactly two rooms; record it on both.
static func _attach_doorways(rooms: Array, doorways: Array) -> void:
	for room in rooms:
		var poly: PackedVector2Array = room.poly
		for d in doorways:
			for i in poly.size():
				if _dist_to_segment(d, poly[i], poly[(i + 1) % poly.size()]) < 0.05:
					room.doorways.append(d)
					break


const ROLES := {
	"home": ["living", "kitchen", "bedroom", "bedroom", "bedroom"], "office": ["reception", "office", "office", "office", "office"],
	"shop": ["salesroom", "back", "back", "back", "back"], "workshop": ["workshop", "store", "store", "store", "store"],
}
const UPPER_ROLES := {"home": ["hall", "bedroom", "bedroom", "bedroom", "bedroom"], "office": ["office", "office", "office", "office", "office"],
	"shop": ["office", "office", "office", "office", "office"], "workshop": ["office", "office", "office", "office", "office"]}


## Roles by use: the room touching `entry` (the exterior door downstairs, the ramp landing upstairs) comes first,
## the rest by size.
func _assign_roles(rooms: Array, use: String, entry: Vector2, upper: bool) -> void:
	var order: Array = rooms.duplicate()
	var best: Dictionary = order[0]
	var best_d := INF
	for r in order:
		var poly: PackedVector2Array = r.poly
		for i in poly.size():
			var d := _dist_to_segment(entry, poly[i], poly[(i + 1) % poly.size()])
			if d < best_d:
				best_d = d
				best = r
	order.erase(best)
	order.sort_custom(func(x, y): return _area(x.poly) > _area(y.poly))
	order.push_front(best)
	var names: Array = (UPPER_ROLES if upper else ROLES).get(use, ROLES.office)
	for i in order.size():
		order[i].role = names[mini(i, names.size() - 1)]


## The ramp hugs the longest edge of its room that is away from the door and the doorways.
func _ramp_edge(poly: PackedVector2Array, door_pt: Vector2, doorways: Array) -> int:
	var best := 0
	var best_len := -1.0
	var fallback := 0
	var fallback_len := -1.0
	for i in poly.size():
		var a := poly[i]
		var c := poly[(i + 1) % poly.size()]
		var length := a.distance_to(c)
		if length > fallback_len:
			fallback_len = length
			fallback = i
		var clear := _dist_to_segment(door_pt, a, c) > 1.5
		for d in doorways:
			if _dist_to_segment(d, a, c) <= 1.5:
				clear = false
		if clear and length > best_len:
			best_len = length
			best = i
	return best if best_len >= 3.0 else fallback


## Partition walls of one storey with their doorways and a lintel over each opening.
func _partition_walls(root: Node3D, walls: Array, y0: float, y1: float, mat: Material, kind: String) -> void:
	for w in walls:
		var mi := _wall(root, w.a, w.c, y0, y1, mat, kind, float(w.door_u), DOOR_W, false)
		if mi:
			mi.name = "Partition_%d" % int(w.split)
		if float(w.door_u) >= 0.0:
			_lintel(root, w.a, w.c, float(w.door_u), y0 + (2.1 if kind == "dwelling" else 2.4))


## A thin box over a doorway so the opening reads as a door, not a missing wall.
func _lintel(root: Node3D, a: Vector2, c: Vector2, u: float, y: float) -> void:
	var dir := (c - a).normalized()
	var at := a + dir * u
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(DOOR_W + 0.3, 0.1, 0.12)
	mi.mesh = box
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(0.86, 0.8, 0.7)
	trim.emission_enabled = true
	trim.emission = Color(0.86, 0.8, 0.7)
	trim.emission_energy_multiplier = 0.25
	mi.material_override = trim
	mi.position = Vector3(at.x, y + 0.05, at.y)
	mi.rotation.y = -atan2(dir.y, dir.x)
	root.add_child(mi)


func _use_of(b: FootprintBuilding, tenants: Array) -> String:
	var active := tenants.filter(func(t): return t.status == "R")
	var p := b.purpose.to_lower()
	if "kauplus" in p or "kaubandus" in p or "toitlustus" in p or "teenindus" in p:
		return "shop"
	if not active.is_empty():
		return "shop" if b.kind != "dwelling" else "office"
	if "tööstus" in p or "ladu" in p or "tootmis" in p or "garaaž" in p:
		return "workshop"
	if b.kind == "dwelling" or "elamu" in p or "korter" in p:
		return "home"
	return "office"


## Floor or ceiling: the inset polygon triangulated, with holes where the ramp lands (skipped triangles).
func _slab(root: Node3D, poly: PackedVector2Array, y: float, mat: Material, up: bool, holes: Array) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris := Geometry2D.triangulate_polygon(poly)
	var shape_pts := PackedVector3Array()
	for i in range(0, tris.size(), 3):
		var p0 := poly[tris[i]]
		var p1 := poly[tris[i + 1]]
		var p2 := poly[tris[i + 2]]
		var c := (p0 + p1 + p2) / 3.0
		var skip := false
		for h in holes:
			if h.has_point(c):
				skip = true
		if skip:
			continue
		var v0 := Vector3(p0.x, y, p0.y)
		var v1 := Vector3(p1.x, y, p1.y)
		var v2 := Vector3(p2.x, y, p2.y)
		var normal := Vector3.UP if up else Vector3.DOWN
		# the footprint's winding varies: orient each triangle so its front face (clockwise in Godot) is the side we draw
		if ((v1 - v0).cross(v2 - v0).y < 0.0) != up:
			var tmp := v1
			v1 = v2
			v2 = tmp
		for v in [v0, v1, v2]:
			st.set_normal(normal)
			st.set_uv(Vector2(v.x, v.z) * 0.5)
			st.add_vertex(v)
		shape_pts.append_array([v0, v1, v2])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED   # the hidden roof no longer blocks the sun
	root.add_child(mi)
	if up:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		var cs := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(shape_pts)
		cs.shape = shape
		body.add_child(cs)
		root.add_child(body)


## One inner wall between two floor heights: solid below the sill and above the lintel, piers between
## window openings, and the door gap on the ground floor. Faces inward, double-sided.
func _wall(root: Node3D, a: Vector2, c: Vector2, y0: float, y1: float, mat: Material, kind: String, door_u: float, door_w: float, windows: bool = true) -> MeshInstance3D:
	var length := a.distance_to(c)
	if length < 0.3:
		return null
	var dir := (c - a) / length
	var sill := y0 + (0.9 if kind == "dwelling" else 1.3)
	var win_h := minf(1.35, (y1 - y0) * 0.45) if kind == "dwelling" else 0.6
	var lintel := sill + win_h
	var win_w := 1.1 if kind == "dwelling" else 0.8
	var spacing := 2.8 if kind == "dwelling" else 5.0
	var openings := []   # [u0, u1, ylo, yhi]
	if windows and length >= 2.4:
		var cols := maxi(1, int((length - 1.6) / spacing))
		var step := length / (cols + 1)
		for k in cols:
			var u := step * (k + 1)
			if door_u >= 0.0 and absf(u - door_u) < (win_w + door_w) / 2.0:
				continue
			openings.append([u - win_w / 2.0, u + win_w / 2.0, sill, lintel])
	if door_u >= 0.0:
		openings.append([maxf(0.0, door_u - door_w / 2.0), minf(length, door_u + door_w / 2.0), y0 - 0.01, y0 + (2.1 if kind == "dwelling" else 2.4)])
	openings.sort_custom(func(p, q): return p[0] < q[0])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var quad := func(u0: float, u1: float, ylo: float, yhi: float):
		if u1 - u0 < 0.01 or yhi - ylo < 0.01:
			return
		var p0 := a + dir * u0
		var p1 := a + dir * u1
		var v := [Vector3(p0.x, ylo, p0.y), Vector3(p1.x, ylo, p1.y), Vector3(p1.x, yhi, p1.y), Vector3(p0.x, yhi, p0.y)]
		for tri in [[0, 1, 2], [0, 2, 3]]:
			for idx in tri:
				st.set_uv(Vector2((u0 if idx in [0, 3] else u1) * 0.4, (ylo if idx < 2 else yhi) * 0.4))
				st.add_vertex(v[idx])
			faces.append_array([v[tri[0]], v[tri[1]], v[tri[2]]])
	# vertical strips between openings, plus the bands above and below each opening
	var u := 0.0
	for o in openings:
		quad.call(u, o[0], y0, y1)
		quad.call(o[0], o[1], y0, o[2])
		quad.call(o[0], o[1], o[3], y1)
		u = o[1]
	quad.call(u, length, y0, y1)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	root.add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	cs.shape = shape
	body.add_child(cs)
	root.add_child(body)
	return mi


## The ramp runs along the inner side of `edge` from its start; the landing square above its top end is left
## open in the ceiling and the next floor.
func _ramp_rect(poly: PackedVector2Array, edge: int, fh: float) -> Array:
	var a := poly[edge]
	var c := poly[(edge + 1) % poly.size()]
	var dir := (c - a).normalized()
	var inward := Vector2(-dir.y, dir.x)
	if not Geometry2D.is_point_in_polygon(a + dir * 0.5 + inward * 0.5, poly):
		inward = -inward
	var run := minf(a.distance_to(c) - 1.0, fh / tan(deg_to_rad(33.0)))
	return [a + dir * 0.5 + inward * 0.6, dir, inward, run]


func _ramp_landing(poly: PackedVector2Array, edge: int, fh: float) -> Rect2:
	var r := _ramp_rect(poly, edge, fh)
	var start: Vector2 = r[0]
	var dir: Vector2 = r[1]
	var inward: Vector2 = r[2]
	var run: float = r[3]
	var end := start + dir * run
	var corners := [end - dir * 1.4, end + dir * 0.4, end + dir * 0.4 + inward * 1.2, end - dir * 1.4 + inward * 1.2]
	var rect := Rect2(corners[0], Vector2.ZERO)
	for cpt in corners:
		rect = rect.expand(cpt)
	return rect


func _ramp(root: Node3D, poly: PackedVector2Array, edge: int, y0: float, fh: float, mat: Material) -> void:
	var r := _ramp_rect(poly, edge, fh)
	var start: Vector2 = r[0]
	var dir: Vector2 = r[1]
	var inward: Vector2 = r[2]
	var run: float = r[3]
	if run < 2.0:
		return
	var w := 1.1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var lo0 := start
	var lo1 := start + inward * w
	var hi0 := start + dir * run
	var hi1 := hi0 + inward * w
	var v := [Vector3(lo0.x, y0, lo0.y), Vector3(lo1.x, y0, lo1.y), Vector3(hi1.x, y0 + fh, hi1.y), Vector3(hi0.x, y0 + fh, hi0.y)]
	for tri in [[0, 1, 2], [0, 2, 3], [0, 2, 1], [0, 3, 2]]:
		for idx in tri:
			st.set_uv(Vector2(v[idx].x, v[idx].z) * 0.5)
			st.add_vertex(v[idx])
	for tri in [[0, 1, 2], [0, 2, 3]]:
		faces.append_array([v[tri[0]], v[tri[1]], v[tri[2]]])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.5, 0.38, 0.26)
	mi.material_override = m
	root.add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	cs.shape = shape
	body.add_child(cs)
	root.add_child(body)
	var rail := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(run, 0.08, 0.06)
	rail.mesh = box
	rail.material_override = mat
	var mid := (lo1 + hi1) / 2.0 + inward * 0.05
	rail.position = Vector3(mid.x, y0 + fh / 2.0 + 0.95, mid.y)
	rail.rotation.y = -atan2(dir.y, dir.x)
	rail.rotation.z = atan(fh / run)
	root.add_child(rail)


# ---------------------------------------------------------------- furniture

const SETS := {
	"living": [["loungeSofa", Vector3(2.0, 0.8, 0.9), Color(0.3, 0.4, 0.55)], ["tableCoffee", Vector3(1.0, 0.45, 0.6), Color(0.6, 0.45, 0.3)],
		["televisionModern", Vector3(1.2, 0.8, 0.3), Color(0.15, 0.15, 0.15)], ["cabinetTelevision", Vector3(1.2, 1.1, 0.5), Color(0.5, 0.5, 0.5)],
		["bookcaseClosed", Vector3(1.0, 2.0, 0.4), Color(0.45, 0.32, 0.22)], ["plantSmall1", Vector3(0.4, 0.8, 0.4), Color(0.3, 0.55, 0.3)], ["lampRoundFloor", Vector3(0.4, 1.6, 0.4), Color(0.9, 0.85, 0.7)]],
	"kitchen": [["kitchenCabinet", Vector3(1.0, 0.9, 0.6), Color(0.85, 0.85, 0.8)], ["kitchenStove", Vector3(0.9, 0.9, 0.6), Color(0.7, 0.7, 0.72)],
		["kitchenFridge", Vector3(0.9, 1.9, 0.7), Color(0.85, 0.85, 0.88)], ["kitchenCabinet", Vector3(1.0, 0.9, 0.6), Color(0.85, 0.85, 0.8)],
		["table", Vector3(1.4, 0.75, 0.9), Color(0.6, 0.45, 0.3)], ["chair", Vector3(0.5, 0.9, 0.5), Color(0.5, 0.36, 0.24)], ["chair", Vector3(0.5, 0.9, 0.5), Color(0.5, 0.36, 0.24)]],
	"bedroom": [["bedDouble", Vector3(1.8, 0.6, 2.0), Color(0.75, 0.3, 0.3)], ["cabinetBed", Vector3(1.0, 1.8, 0.6), Color(0.4, 0.4, 0.42)],
		["bookcaseOpen", Vector3(1.0, 2.0, 0.4), Color(0.6, 0.6, 0.58)], ["chair", Vector3(0.5, 0.9, 0.5), Color(0.5, 0.36, 0.24)],
		["plantSmall2", Vector3(0.4, 0.9, 0.4), Color(0.3, 0.55, 0.3)], ["lampRoundFloor", Vector3(0.4, 1.6, 0.4), Color(0.9, 0.85, 0.7)]],
	"hall": [["bookcaseClosed", Vector3(1.0, 2.0, 0.4), Color(0.45, 0.32, 0.22)], ["chair", Vector3(0.5, 0.9, 0.5), Color(0.5, 0.36, 0.24)],
		["plantSmall3", Vector3(0.4, 0.8, 0.4), Color(0.3, 0.55, 0.3)], ["lampRoundFloor", Vector3(0.4, 1.6, 0.4), Color(0.9, 0.85, 0.7)]],
	"reception": [["desk", Vector3(1.6, 0.75, 0.8), Color(0.7, 0.7, 0.68)], ["chairDesk", Vector3(0.6, 1.0, 0.6), Color(0.2, 0.2, 0.22)],
		["loungeSofa", Vector3(2.0, 0.8, 0.9), Color(0.3, 0.4, 0.55)], ["tableCoffee", Vector3(1.0, 0.45, 0.6), Color(0.6, 0.45, 0.3)],
		["bookcaseClosed", Vector3(1.0, 2.0, 0.4), Color(0.45, 0.32, 0.22)], ["plantSmall3", Vector3(0.4, 0.8, 0.4), Color(0.3, 0.55, 0.3)]],
	"office": [["desk", Vector3(1.6, 0.75, 0.8), Color(0.7, 0.7, 0.68)], ["chairDesk", Vector3(0.6, 1.0, 0.6), Color(0.2, 0.2, 0.22)],
		["desk", Vector3(1.6, 0.75, 0.8), Color(0.7, 0.7, 0.68)], ["chairDesk", Vector3(0.6, 1.0, 0.6), Color(0.2, 0.2, 0.22)],
		["bookcaseOpen", Vector3(1.0, 2.0, 0.4), Color(0.6, 0.6, 0.58)], ["cabinetTelevision", Vector3(1.2, 1.1, 0.5), Color(0.5, 0.5, 0.5)], ["plantSmall2", Vector3(0.4, 0.9, 0.4), Color(0.3, 0.55, 0.3)]],
	"salesroom": [["kitchenBar", Vector3(1.8, 1.0, 0.7), Color(0.55, 0.4, 0.3)], ["bookcaseOpen", Vector3(1.0, 2.0, 0.45), Color(0.6, 0.5, 0.4)],
		["bookcaseOpen", Vector3(1.0, 2.0, 0.45), Color(0.6, 0.5, 0.4)], ["bookcaseOpen", Vector3(1.0, 2.0, 0.45), Color(0.6, 0.5, 0.4)],
		["table", Vector3(1.4, 0.75, 0.9), Color(0.6, 0.45, 0.3)], ["plantSmall3", Vector3(0.4, 0.8, 0.4), Color(0.3, 0.55, 0.3)]],
	"back": [["cardboardBoxClosed", Vector3(0.6, 0.6, 0.6), Color(0.7, 0.55, 0.35)], ["cardboardBoxClosed", Vector3(0.6, 0.6, 0.6), Color(0.7, 0.55, 0.35)],
		["bookcaseOpen", Vector3(1.0, 2.0, 0.45), Color(0.6, 0.5, 0.4)], ["table", Vector3(1.4, 0.75, 0.9), Color(0.6, 0.45, 0.3)], ["cardboardBoxClosed", Vector3(0.6, 0.6, 0.6), Color(0.7, 0.55, 0.35)]],
	"workshop": [["table", Vector3(2.0, 0.85, 0.9), Color(0.45, 0.45, 0.42)], ["bench", Vector3(1.4, 0.5, 0.5), Color(0.5, 0.4, 0.3)],
		["cabinetBed", Vector3(1.0, 1.8, 0.6), Color(0.4, 0.4, 0.42)], ["cardboardBoxClosed", Vector3(0.6, 0.6, 0.6), Color(0.7, 0.55, 0.35)], ["bench", Vector3(1.4, 0.5, 0.5), Color(0.5, 0.4, 0.3)]],
	"store": [["cardboardBoxClosed", Vector3(0.6, 0.6, 0.6), Color(0.7, 0.55, 0.35)], ["cardboardBoxClosed", Vector3(0.6, 0.6, 0.6), Color(0.7, 0.55, 0.35)],
		["cabinetBed", Vector3(1.0, 1.8, 0.6), Color(0.4, 0.4, 0.42)], ["bookcaseOpen", Vector3(1.0, 2.0, 0.45), Color(0.6, 0.5, 0.4)], ["cardboardBoxClosed", Vector3(0.6, 0.6, 0.6), Color(0.7, 0.55, 0.35)]],
}


## Pieces of `role` along the walls of one room: a piece per ~4 m of wall. Edges in `skip_edges` and edges
## carrying a doorway or the exterior door get none, and nothing stands within CLEAR of an `avoid` point.
func _furnish(root: Node3D, poly: PackedVector2Array, y0: float, role: String, seed_key: String, skip_edges: Array, avoid: Array) -> void:
	var pieces: Array = SETS.get(role, SETS.office)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_key)
	var idx := 0
	for i in poly.size():
		if i in skip_edges:
			continue
		var a := poly[i]
		var c := poly[(i + 1) % poly.size()]
		var length := a.distance_to(c)
		if length < 2.0:
			continue
		var on_edge := false
		for p in avoid:
			if _dist_to_segment(p, a, c) < 0.1:
				on_edge = true
		if on_edge:
			continue
		var dir := (c - a) / length
		var inward := Vector2(-dir.y, dir.x)
		if not Geometry2D.is_point_in_polygon(a + dir * 0.5 + inward * 0.5, poly):
			inward = -inward
		var slots := maxi(1, int(length / 4.0))
		for s in slots:
			if idx >= pieces.size():
				return
			var piece: Array = pieces[idx]
			idx += 1
			var size: Vector3 = piece[1]
			var u := length * (s + 0.5) / slots
			var at := a + dir * u + inward * (size.z / 2.0 + 0.3)
			if not Geometry2D.is_point_in_polygon(at, poly):
				continue
			var blocked := false
			for p in avoid:
				if at.distance_to(p) < CLEAR:
					blocked = true
			if blocked:
				continue
			var node := _piece(str(piece[0]), size, piece[2])
			node.position = Vector3(at.x, y0, at.y)
			node.rotation.y = -atan2(dir.y, dir.x) + PI   # back to the wall
			node.set_meta("piece", true)
			root.add_child(node)


## A Kenney Furniture Kit model when vendored (`assets/vendor/kenney_furniture_kit/glb/<name>.glb`), else a box.
func _piece(model: String, size: Vector3, color: Color) -> Node3D:
	var path := KIT + model + ".glb"
	if not _kit_cache.has(model):
		_kit_cache[model] = load(path) if ResourceLoader.exists(path) else null
	var scene: PackedScene = _kit_cache[model]
	if scene:
		var n: Node3D = scene.instantiate()
		return n
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position.y = size.y / 2.0
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	mi.material_override = m
	var wrap := Node3D.new()
	wrap.add_child(mi)
	return wrap


## Lamp positions: the centroid for small rooms, a 9 m grid of points inside the polygon for halls.
## Baked grass and bushes under the footprint of an older tile, stamped away on the first visit
## (session only; the region file is untouched). Tiles baked with TerrainBuilder.footprint_mask have none.
func _clear_plants(b: FootprintBuilding) -> void:
	var terrain: Terrain3D = world.terrain if world else null
	if terrain == null or terrain.instancer == null or not terrain.instancer.has_method("remove_instances"):
		return
	for spot in _grid_spots(_grow(b.polygon, 0.7), 2.5):
		var at: Vector3 = b.to_global(Vector3(spot.x, 0.0, spot.y))
		var h: float = terrain.data.get_height(at)
		if not is_nan(h):
			at.y = h
		for id in PLANT_IDS:
			terrain.instancer.remove_instances(at, {"asset_id": id, "size": 6.0, "strength": 1.0, "slope": Vector2(0.0, 90.0),
				"modifier_alt": false, "modifier_ctrl": false, "modifier_shift": false, "height_offset": 0.0, "random_height": 0.0,
				"fixed_scale": 1.0, "random_scale": 0.0, "fixed_spin": 0.0, "random_spin": 0.0, "fixed_tilt": 0.0, "random_tilt": 0.0,
				"align_to_normal": false, "vertex_color": Color.WHITE, "random_hue": 0.0, "random_darken": 0.0})


## Points of a `step` grid inside the polygon, starting half a step in from its bounding box.
static func _grid_spots(poly: PackedVector2Array, step: float) -> Array:
	var spots := []
	if poly.size() < 3:
		return spots
	var rect := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		rect = rect.expand(p)
	var x := rect.position.x + step / 2.0
	while x < rect.end.x:
		var z := rect.position.y + step / 2.0
		while z < rect.end.y:
			if Geometry2D.is_point_in_polygon(Vector2(x, z), poly):
				spots.append(Vector2(x, z))
			z += step
		x += step
	return spots


static func _lamp_spots(poly: PackedVector2Array) -> Array:
	if _area(poly) < 90.0:
		return [_centroid(poly)]
	var spots := _grid_spots(poly, 9.0)
	if spots.is_empty():
		spots.append(_centroid(poly))
	return spots


# ---------------------------------------------------------------- geometry helpers

func _door_label(b: FootprintBuilding) -> String:
	var d: Node = b.get_node_or_null("Door")
	return d.label() if d else b.address


static func _area(poly: PackedVector2Array) -> float:
	var s := 0.0
	for i in poly.size():
		var a := poly[i]
		var c := poly[(i + 1) % poly.size()]
		s += a.x * c.y - c.x * a.y
	return absf(s) / 2.0


static func _centroid(poly: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	return c / maxf(poly.size(), 1)


static func _grow(poly: PackedVector2Array, d: float) -> PackedVector2Array:
	var out := Geometry2D.offset_polygon(poly, d, Geometry2D.JOIN_MITER)
	return out[0] if out.size() > 0 else poly


static func _shrink(poly: PackedVector2Array, d: float) -> PackedVector2Array:
	var out := Geometry2D.offset_polygon(poly, -d, Geometry2D.JOIN_MITER)
	var best := PackedVector2Array()
	for p in out:
		if p.size() >= 3 and _area(p) > _area(best):
			best = p
	return best


static func _project_u(p: Vector2, a: Vector2, c: Vector2) -> float:
	var ab := c - a
	return clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0) * ab.length()


static func _dist_to_segment(p: Vector2, a: Vector2, c: Vector2) -> float:
	var u := _project_u(p, a, c)
	return p.distance_to(a + (c - a).normalized() * u)
