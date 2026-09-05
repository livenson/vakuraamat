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
const PLANT_IDS := [5, 6, 7, 8, 9]
## Interior paint per building: [outer walls, inner walls]. Contemporary schemes: an off-white with a
## muted accent (sage, dusty blue, clay, warm grey, ochre, deep green).
const PAINTS := [
	[Color(0.94, 0.92, 0.87), Color(0.72, 0.76, 0.66)], [Color(0.93, 0.93, 0.9), Color(0.6, 0.68, 0.74)],
	[Color(0.95, 0.91, 0.84), Color(0.78, 0.6, 0.5)], [Color(0.9, 0.9, 0.88), Color(0.62, 0.6, 0.57)],
	[Color(0.96, 0.94, 0.88), Color(0.82, 0.7, 0.45)], [Color(0.92, 0.93, 0.9), Color(0.36, 0.48, 0.42)],
	[Color(0.95, 0.93, 0.9), Color(0.85, 0.82, 0.75)], [Color(0.9, 0.92, 0.93), Color(0.45, 0.5, 0.6)],
]   # TerrainBuilder.RULES bushes, grass, clover; trees (0..4) are measured and never touched
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
var _kit_size: Dictionary = {}   # model -> AABB of the kit model as exported


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
	var pieces := 0
	for c in root.find_children("*", "Node3D", true, false):
		if c.has_meta("piece"):
			pieces += 1
	print("[interiors] inside %s: %d rooms, %d pieces" % [_door_label(b), root.find_children("Partition_*", "MeshInstance3D", false, false).size() + 1, pieces])
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
	var paint: Array = PAINTS[hash("paint_%d" % b.building_id) % PAINTS.size()]
	wall_mat.albedo_color = paint[0]
	wall_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var accent_mat := StandardMaterial3D.new()
	accent_mat.albedo_color = paint[1]
	accent_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
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
	var hole := _ramp_hole(ramp_room.poly, ramp_edge, fh)
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
		_slab(root, poly, y0, floor_mat, true, [] if k == 0 else [hole])
		_slab(root, poly, y1 - SLAB, ceil_mat, false, [] if top or n_floors == 1 else [hole])
		for i in poly.size():
			var a := poly[i]
			var c := poly[(i + 1) % poly.size()]
			var gap := -1.0
			if k == 0 and i == door_edge:
				gap = _project_u(door_pt, a, c)
			_wall(root, a, c, y0, y1, wall_mat, b.kind, gap, float(f.width) + 0.3)
		_partition_walls(root, walls, y0, y1, accent_mat, b.kind)
		if not top:
			_ramp(root, ramp_room.poly, ramp_edge, y0, fh, wall_mat)
		var storey_rooms: Array = rooms if k == 0 else upper
		for idx in storey_rooms.size():
			var room: Dictionary = storey_rooms[idx]
			for spot in _lamp_spots(room.poly):
				var light := OmniLight3D.new()
				light.position = Vector3(spot.x, y0 + minf(2.2, fh - 0.6), spot.y)
				light.light_color = Color(1.0, 0.95, 0.88)
				var room_area: float = absf(_area(room.poly))
				light.light_energy = clampf(room_area / 12.0, 1.2, 4.0)   # a small room needs a small lamp, or the walls blow out
				light.light_specular = 0.2
				light.omni_range = clampf(sqrt(room_area) * 1.5, 5.0, 12.0)
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
	var cut := 0.0
	var have_cut := false
	# a cut near the middle of the longer side, else the shorter, else off-centre: a door in the
	# middle of both sides must still leave a room plan
	var sets: Array = [[rng.randf_range(0.42, 0.58), rng.randf_range(0.42, 0.58)], [0.32, 0.68]] if not once_only else [[0.25, 0.75]]
	for options in sets:
		for attempt in 2:
			var span: float = rect.size.x if vertical else rect.size.y
			var lo_edge: float = rect.position.x if vertical else rect.position.y
			var door_c: float = door_pt.x if vertical else door_pt.y
			var best_d := -1.0
			for t in options:
				var c: float = lo_edge + span * t
				var d := absf(c - door_c)
				if d > best_d:
					best_d = d
					cut = c
			if best_d >= 1.5:
				have_cut = true
				break
			vertical = not vertical
		if have_cut:
			break
	if not have_cut:
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


## Floor or ceiling: the inset polygon, minus the stair notches (polygons that reach past the wall, so
## the cut leaves plain polygons), triangulated.
func _slab(root: Node3D, poly: PackedVector2Array, y: float, mat: Material, up: bool, holes: Array) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pieces: Array = [poly]
	for h in holes:
		var cut: Array = []
		for piece in pieces:
			for out in Geometry2D.clip_polygons(piece, h):
				if out.size() >= 3 and not Geometry2D.is_polygon_clockwise(out) == Geometry2D.is_polygon_clockwise(piece):
					continue   # an island hole the notch failed to open to the edge: keep the piece whole below
				if out.size() >= 3:
					cut.append(out)
		pieces = cut if not cut.is_empty() else pieces
	var shape_pts := PackedVector3Array()
	var flat: Array = []   # [p0, p1, p2] per triangle
	for piece in pieces:
		var tris := Geometry2D.triangulate_polygon(piece)
		for i in range(0, tris.size(), 3):
			flat.append([piece[tris[i]], piece[tris[i + 1]], piece[tris[i + 2]]])
	for tri in flat:
		var p0: Vector2 = tri[0]
		var p1: Vector2 = tri[1]
		var p2: Vector2 = tri[2]
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


## Painted casing round a window opening ([u0, u1, ylo, yhi] along the wall from `a`) and a sill
## board below it, centred on the wall plane.
func _casing(root: Node3D, a: Vector2, dir: Vector2, o: Array) -> void:
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(0.93, 0.91, 0.86)
	var yaw := -atan2(dir.y, dir.x)
	var w: float = o[1] - o[0]
	var h: float = o[3] - o[2]
	for part in [[Vector3(0.07, h + 0.14, 0.08), Vector2(o[0] - 0.035, (o[2] + o[3]) * 0.5)], [Vector3(0.07, h + 0.14, 0.08), Vector2(o[1] + 0.035, (o[2] + o[3]) * 0.5)],
			[Vector3(w + 0.14, 0.07, 0.08), Vector2((o[0] + o[1]) * 0.5, o[3] + 0.035)], [Vector3(w + 0.2, 0.04, 0.2), Vector2((o[0] + o[1]) * 0.5, o[2] - 0.02)]]:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = part[0] as Vector3
		mi.mesh = box
		mi.material_override = trim
		var off: Vector2 = part[1]
		var at: Vector2 = a + dir * off.x
		mi.position = Vector3(at.x, off.y, at.y)
		mi.rotation.y = yaw
		root.add_child(mi)


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
		if o[2] > y0 + 0.2:
			_casing(root, a, dir, o)
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


## The opening in the floor above the stair: over its upper 2.2 m of run, from beyond the wall to
## 0.7 m past the stair's free side, so the climber has headroom and steps off onto solid floor.
func _ramp_hole(poly: PackedVector2Array, edge: int, fh: float) -> PackedVector2Array:
	var r := _ramp_rect(poly, edge, fh)
	var start: Vector2 = r[0]
	var dir: Vector2 = r[1]
	var inward: Vector2 = r[2]
	var run: float = r[3]
	var end := start + dir * run
	return PackedVector2Array([end - dir * 2.2 - inward * 1.0, end - inward * 1.0, end + inward * 1.8, end - dir * 2.2 + inward * 1.8])


## The stair: steps as solid blocks over a walkable slope (the collider), a closed side, a handrail
## on posts along the free side.
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
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.5, 0.38, 0.26)
	var steps := maxi(3, int(round(fh / 0.18)))
	var tread := run / steps
	var rise := fh / steps
	var yaw := -atan2(dir.y, dir.x)
	for i in steps:
		var top := y0 + (i + 1) * rise
		var block := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(tread, top - y0, w)
		block.mesh = bm
		block.material_override = m
		var centre := start + dir * ((i + 0.5) * tread) + inward * (w * 0.5)
		block.position = Vector3(centre.x, y0 + (top - y0) * 0.5, centre.y)
		block.rotation.y = yaw
		root.add_child(block)
	for i in range(0, int(run / 1.0) + 1):
		var u := minf(i * 1.0 + 0.1, run - 0.1)
		var post := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.05, 0.95, 0.05)
		post.mesh = pm
		post.material_override = mat
		var at := start + dir * u + inward * (w + 0.05)
		post.position = Vector3(at.x, y0 + fh * (u / run) + 0.475, at.y)
		root.add_child(post)
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

## The furniture: kit model -> [size in metres (the model is scaled to this height; rugs to this
## width), colour of the stand-in box].
const PIECES := {
	"loungeSofa": [Vector3(2.0, 0.8, 0.9), Color(0.3, 0.4, 0.55)], "tableCoffee": [Vector3(1.0, 0.45, 0.6), Color(0.6, 0.45, 0.3)],
	"rugRectangle": [Vector3(2.6, 0.01, 1.7), Color(0.55, 0.35, 0.3)],
	"cabinetTelevision": [Vector3(1.4, 0.5, 0.45), Color(0.5, 0.5, 0.5)], "televisionModern": [Vector3(1.1, 0.7, 0.2), Color(0.15, 0.15, 0.15)],
	"bookcaseClosed": [Vector3(1.0, 2.0, 0.4), Color(0.45, 0.32, 0.22)], "bookcaseOpen": [Vector3(1.0, 2.0, 0.45), Color(0.6, 0.5, 0.4)],
	"plantSmall1": [Vector3(0.4, 0.8, 0.4), Color(0.3, 0.55, 0.3)], "plantSmall2": [Vector3(0.4, 0.9, 0.4), Color(0.3, 0.55, 0.3)],
	"plantSmall3": [Vector3(0.4, 0.8, 0.4), Color(0.3, 0.55, 0.3)], "lampRoundFloor": [Vector3(0.4, 1.6, 0.4), Color(0.9, 0.85, 0.7)],
	"kitchenCabinet": [Vector3(1.0, 0.9, 0.6), Color(0.85, 0.85, 0.8)], "kitchenStove": [Vector3(0.9, 0.9, 0.6), Color(0.7, 0.7, 0.72)],
	"kitchenFridge": [Vector3(0.9, 1.9, 0.7), Color(0.85, 0.85, 0.88)], "kitchenBar": [Vector3(1.8, 1.0, 0.7), Color(0.55, 0.4, 0.3)],
	"table": [Vector3(1.4, 0.75, 0.9), Color(0.6, 0.45, 0.3)], "chair": [Vector3(0.5, 0.9, 0.5), Color(0.5, 0.36, 0.24)],
	"bedDouble": [Vector3(1.8, 0.6, 2.0), Color(0.75, 0.3, 0.3)], "cabinetBed": [Vector3(0.5, 0.55, 0.45), Color(0.4, 0.4, 0.42)],
	"desk": [Vector3(1.6, 0.75, 0.8), Color(0.7, 0.7, 0.68)], "chairDesk": [Vector3(0.6, 1.0, 0.6), Color(0.2, 0.2, 0.22)],
	"computerScreen": [Vector3(0.5, 0.4, 0.15), Color(0.1, 0.1, 0.12)],
	"cardboardBoxClosed": [Vector3(0.6, 0.6, 0.6), Color(0.7, 0.55, 0.35)], "bench": [Vector3(1.6, 0.85, 0.7), Color(0.5, 0.4, 0.3)],
}

## Room plans by role, applied in order. "anchor": the piece centred on the longest free wall, with
## a "front" piece before it, "sides" pieces beside it and a "rug" under the group; "opposite": on
## the wall facing the anchor, with a "stack" piece on top; "run": the pieces repeated along the
## walls (`walls` of them, cycling when "cycle"); "island": a free-standing piece nearest the room's
## centre with "around" chairs; "grid": the piece repeated on a grid aligned with the longest wall
## (rows of desks, shelf aisles, box stacks) with a "front" piece at each; "corners": one piece per
## free corner. `min_area` gates a step by room size, `max` caps its count.
const PLANS := {
	"living": [
		{"kind": "anchor", "piece": "loungeSofa", "front": "tableCoffee", "rug": "rugRectangle"},
		{"kind": "opposite", "piece": "cabinetTelevision", "stack": "televisionModern"},
		{"kind": "run", "pieces": ["bookcaseClosed"], "max": 2},
		{"kind": "corners", "pieces": ["plantSmall1", "lampRoundFloor"]},
		{"kind": "island", "piece": "table", "around": "chair", "min_area": 30.0},
	],
	"kitchen": [
		{"kind": "run", "pieces": ["kitchenCabinet", "kitchenStove", "kitchenCabinet", "kitchenFridge"], "cycle": true, "walls": 2},
		{"kind": "island", "piece": "table", "around": "chair"},
		{"kind": "corners", "pieces": ["plantSmall2"]},
	],
	"bedroom": [
		{"kind": "anchor", "piece": "bedDouble", "sides": "cabinetBed"},
		{"kind": "run", "pieces": ["bookcaseOpen"], "max": 1},
		{"kind": "corners", "pieces": ["plantSmall2", "lampRoundFloor"]},
	],
	"hall": [
		{"kind": "run", "pieces": ["bookcaseClosed", "cabinetBed"], "max": 2},
		{"kind": "island", "piece": "table", "around": "chair", "min_area": 18.0},
		{"kind": "corners", "pieces": ["plantSmall3", "lampRoundFloor"]},
	],
	"reception": [
		{"kind": "anchor", "piece": "desk", "front": "chairDesk", "stack": "computerScreen"},
		{"kind": "opposite", "piece": "loungeSofa", "front": "tableCoffee"},
		{"kind": "run", "pieces": ["bookcaseClosed"], "max": 1},
		{"kind": "corners", "pieces": ["plantSmall3", "plantSmall1"]},
	],
	"office": [
		{"kind": "run", "pieces": ["bookcaseOpen", "cabinetTelevision"], "max": 3},
		{"kind": "grid", "piece": "desk", "front": "chairDesk", "stack": "computerScreen", "pitch": Vector2(2.4, 2.8)},
		{"kind": "corners", "pieces": ["plantSmall2", "plantSmall3"]},
	],
	"salesroom": [
		{"kind": "anchor", "piece": "kitchenBar"},
		{"kind": "run", "pieces": ["bookcaseOpen"], "cycle": true, "walls": 9},
		{"kind": "grid", "piece": "bookcaseOpen", "pitch": Vector2(1.3, 3.0), "min_area": 40.0},
		{"kind": "corners", "pieces": ["plantSmall3"]},
	],
	"back": [
		{"kind": "run", "pieces": ["bookcaseOpen", "cardboardBoxClosed"], "cycle": true, "walls": 2},
		{"kind": "grid", "piece": "cardboardBoxClosed", "pitch": Vector2(1.0, 1.2), "min_area": 20.0},
	],
	"workshop": [
		{"kind": "run", "pieces": ["table", "cabinetBed", "bookcaseOpen"], "cycle": true, "walls": 2},
		{"kind": "grid", "piece": "bench", "pitch": Vector2(2.6, 2.6), "min_area": 25.0},
		{"kind": "corners", "pieces": ["cardboardBoxClosed", "cardboardBoxClosed"]},
	],
	"store": [
		{"kind": "run", "pieces": ["bookcaseOpen", "cabinetBed"], "cycle": true, "walls": 9},
		{"kind": "grid", "piece": "cardboardBoxClosed", "pitch": Vector2(1.0, 1.3), "min_area": 15.0},
	],
}


## Furnish a room by its role's plan (PLANS). Walls carrying a doorway or the exterior door take no
## furniture, nothing stands within CLEAR of an `avoid` point, and pieces keep out of each other.
func _furnish(root: Node3D, poly: PackedVector2Array, y0: float, role: String, seed_key: String, skip_edges: Array, avoid: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_key)
	var room := {"root": root, "poly": poly, "y0": y0, "avoid": avoid, "walls": [], "placed": [], "anchor": {}}
	for i in poly.size():
		if i in skip_edges:
			continue
		var a := poly[i]
		var c := poly[(i + 1) % poly.size()]
		var length := a.distance_to(c)
		if length < 1.6:
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
		room.walls.append({"a": a, "dir": dir, "inward": inward, "length": length, "taken": []})
	if room.walls.is_empty():
		return
	room.walls.sort_custom(func(x, y): return x.length > y.length)
	var area: float = absf(_area(poly))
	for step in PLANS.get(role, PLANS.office):
		if area < float(step.get("min_area", 0.0)):
			continue
		match str(step.kind):
			"anchor":
				_plan_anchor(room, step)
			"opposite":
				_plan_opposite(room, step)
			"run":
				_plan_run(room, step)
			"island":
				_plan_grid(room, step, true)
			"grid":
				_plan_grid(room, step, false)
			"corners":
				_plan_corners(room, step)


## The piece centred on the longest wall with room for it, its front piece, side pieces and rug.
func _plan_anchor(room: Dictionary, step: Dictionary) -> void:
	var size: Vector3 = PIECES[step.piece][0]
	for w in room.walls:
		var spot := _fit(w, size, w.length * 0.5)
		if spot.is_empty() or not _place(room, str(step.piece), spot):
			continue
		room.anchor = {"at": spot.at, "inward": w.inward, "dir": w.dir, "size": size, "y": room.y0}
		if step.has("stack"):
			_place(room, str(step.stack), {"at": spot.at, "dir": w.dir, "y": room.y0 + size.y, "grouped": true})
		if step.has("front"):
			var fs: Vector3 = PIECES[step.front][0]
			_place(room, str(step.front), {"at": spot.at + w.inward * ((size.z + fs.z) * 0.5 + 0.35), "dir": w.dir, "y": room.y0, "grouped": true, "facing_back": step.front == "chairDesk"})
		if step.has("sides"):
			var ss: Vector3 = PIECES[step.sides][0]
			for sgn in [-1.0, 1.0]:
				var side_spot := _fit(w, ss, w.length * 0.5 + sgn * ((size.x + ss.x) * 0.5 + 0.15))
				if not side_spot.is_empty():
					_place(room, str(step.sides), side_spot)
		if step.has("rug"):
			var rs: Vector3 = PIECES[step.rug][0]
			_place(room, str(step.rug), {"at": spot.at + w.inward * (size.z * 0.5 + rs.z * 0.5 - 0.2), "dir": w.dir, "y": room.y0 + 0.005, "grouped": true})
		return


## The piece on the wall facing the anchor, across from it; a stacked piece on top.
func _plan_opposite(room: Dictionary, step: Dictionary) -> void:
	if room.anchor.is_empty():
		_plan_run(room, {"pieces": [step.piece], "max": 1})
		return
	var size: Vector3 = PIECES[step.piece][0]
	var best: Dictionary = {}
	var best_d := INF
	for w in room.walls:
		if w.inward.dot(room.anchor.inward) > -0.5:
			continue
		var d: float = absf((room.anchor.at - w.a).dot(w.inward))
		if d < best_d:
			best_d = d
			best = w
	if best.is_empty():
		return
	var spot := _fit(best, size, (room.anchor.at - best.a).dot(best.dir))
	if spot.is_empty() or not _place(room, str(step.piece), spot):
		return
	if step.has("stack"):
		_place(room, str(step.stack), {"at": spot.at, "dir": best.dir, "y": room.y0 + size.y, "grouped": true})
	if step.has("front"):
		var fs: Vector3 = PIECES[step.front][0]
		_place(room, str(step.front), {"at": spot.at + best.inward * ((size.z + fs.z) * 0.5 + 0.35), "dir": best.dir, "y": room.y0, "grouped": true})


## Pieces packed along the walls: `walls` walls (1), the list cycled to fill each when "cycle".
func _plan_run(room: Dictionary, step: Dictionary) -> void:
	var names: Array = step.pieces
	var cap := int(step.get("max", 99))
	var cycle := bool(step.get("cycle", false))
	var count := 0
	var used_walls := 0
	var idx := 0
	for w in room.walls:
		if used_walls >= int(step.get("walls", 1)) or count >= cap:
			break
		var placed_here := 0
		while count < cap and (cycle or idx < names.size()):
			var name := str(names[idx % names.size()])
			var spot := _fit(w, PIECES[name][0])
			if spot.is_empty():
				break
			if _place(room, name, spot):
				count += 1
				placed_here += 1
			idx += 1
		if placed_here > 0:
			used_walls += 1


## Free-standing pieces on a grid aligned with the longest wall; `single` keeps the one nearest the
## room's centre (a dining table) and puts the "around" chairs at its four sides.
func _plan_grid(room: Dictionary, step: Dictionary, single: bool) -> void:
	var size: Vector3 = PIECES[step.piece][0]
	var w: Dictionary = room.walls[0]
	var inner := _grow(room.poly, -1.1)
	if inner.size() < 3:
		return
	var pitch: Vector2 = step.get("pitch", Vector2(size.x + 1.4, size.z + 1.6))
	var rect_u := [INF, -INF]
	var rect_v := [INF, -INF]
	for p in room.poly:
		var d: Vector2 = p - w.a
		rect_u = [minf(rect_u[0], d.dot(w.dir)), maxf(rect_u[1], d.dot(w.dir))]
		rect_v = [minf(rect_v[0], d.dot(w.inward)), maxf(rect_v[1], d.dot(w.inward))]
	var centre := _centroid(room.poly)
	var spots: Array = []
	var u: float = rect_u[0] + pitch.x * 0.5
	while u < rect_u[1]:
		var v: float = rect_v[0] + size.z * 0.5 + 1.8   # a lane along the anchor wall for its furniture
		while v < rect_v[1]:
			var at: Vector2 = w.a + w.dir * u + w.inward * v
			if Geometry2D.is_point_in_polygon(at, inner):
				spots.append(at)
			v += pitch.y
		u += pitch.x
	if single:
		spots.sort_custom(func(x, y): return x.distance_squared_to(centre) < y.distance_squared_to(centre))
	var cap := 1 if single else int(step.get("max", 99))
	var count := 0
	for at in spots:
		if count >= cap:
			break
		var spot := {"at": at, "dir": w.dir, "y": room.y0, "clear": CLEAR + maxf(size.x, size.z) * 0.5 + 0.8}   # a free-standing piece leaves the way in
		if not _place(room, str(step.piece), spot):
			continue
		count += 1
		if step.has("stack"):
			_place(room, str(step.stack), {"at": at, "dir": w.dir, "y": room.y0 + size.y, "grouped": true})
		if step.has("front"):
			var fs: Vector3 = PIECES[step.front][0]
			_place(room, str(step.front), {"at": at - w.inward * ((size.z + fs.z) * 0.5 + 0.1), "dir": w.dir, "y": room.y0, "grouped": true})
		if step.has("around"):
			var cs: Vector3 = PIECES[step.around][0]
			for off in [w.inward, -w.inward, w.dir, -w.dir]:
				var gap: float = (size.z if off.is_equal_approx(w.inward) or off.is_equal_approx(-w.inward) else size.x) * 0.5 + cs.z * 0.5 + 0.1
				# a piece's front is the inward side of its "wall" direction: face the table from the outside
				_place(room, str(step.around), {"at": at + off * gap, "dir": Vector2(-off.y, off.x), "y": room.y0, "grouped": true})


## One piece per free corner (0.5 m off both walls), skipping corners near a doorway.
func _plan_corners(room: Dictionary, step: Dictionary) -> void:
	var poly: PackedVector2Array = room.poly
	var idx := 0
	var names: Array = step.pieces
	for i in poly.size():
		if idx >= names.size():
			return
		var p := poly[i]
		var prev := poly[(i - 1 + poly.size()) % poly.size()]
		var next := poly[(i + 1) % poly.size()]
		var bis := ((prev - p).normalized() + (next - p).normalized()).normalized()
		var at := p + bis * 0.7
		if not Geometry2D.is_point_in_polygon(at, poly):
			continue
		var facing := (next - p).normalized()
		if _place(room, str(names[idx]), {"at": at, "dir": facing, "y": room.y0}):
			idx += 1


## A stretch of wall `size.x` wide, preferably centred at `along` metres down the wall, else the
## first gap that fits; {} when the wall is full. Reserves the stretch.
func _fit(w: Dictionary, size: Vector3, along: float = -1.0) -> Dictionary:
	var half := size.x * 0.5 + 0.2
	var gaps: Array = []
	var cursor := 0.35
	for t in w.taken:
		if t[0] - cursor >= half * 2.0:
			gaps.append([cursor, t[0]])
		cursor = maxf(cursor, t[1])
	if w.length - 0.35 - cursor >= half * 2.0:
		gaps.append([cursor, w.length - 0.35])
	if gaps.is_empty():
		return {}
	var u := -1.0
	if along >= 0.0:
		for g in gaps:
			if along - half >= g[0] and along + half <= g[1]:
				u = along
			elif along >= g[0] and along <= g[1] and g[1] - g[0] >= half * 2.0:
				u = clampf(along, g[0] + half, g[1] - half)
	if u < 0.0:
		u = gaps[0][0] + half
	w.taken.append([u - half, u + half])
	w.taken.sort_custom(func(x, y): return x[0] < y[0])
	return {"at": w.a + w.dir * u + w.inward * (size.z * 0.5 + 0.3), "dir": w.dir, "inward": w.inward, "y": w.get("y", 0.0)}


## Put a piece down at `spot` ({at, dir, y, grouped}) unless it is outside the room, within CLEAR
## of an avoid point or on top of another piece (grouped pieces only check the avoid points).
func _place(room: Dictionary, name: String, spot: Dictionary) -> bool:
	var size: Vector3 = PIECES[name][0]
	var at: Vector2 = spot.at
	if not Geometry2D.is_point_in_polygon(at, room.poly):
		return false
	var clear: float = float(spot.get("clear", CLEAR))
	for p in room.avoid:
		if at.distance_to(p) < clear:
			return false
	var r := maxf(size.x, size.z) * 0.5
	if not bool(spot.get("grouped", false)):
		for q in room.placed:
			if at.distance_to(q[0]) < r + q[1] + 0.25:
				return false
	var node := _piece(name, size, PIECES[name][1])
	var y: float = spot.get("y", room.y0) if spot.has("y") and spot.y != 0.0 else room.y0
	node.position = Vector3(at.x, y, at.y)
	var dir: Vector2 = spot.dir
	node.rotation.y = -atan2(dir.y, dir.x) + PI + (PI if bool(spot.get("facing_back", false)) else 0.0)   # back to the wall
	node.set_meta("piece", true)
	room.root.add_child(node)
	if size.y > 0.05:
		room.placed.append([at, r])
	return true


static func _centroid(poly: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	return c / maxf(poly.size(), 1)


## A Kenney Furniture Kit model when vendored (`assets/vendor/kenney_furniture_kit/glb/<name>.glb`), else a box.
func _piece(model: String, size: Vector3, color: Color) -> Node3D:
	var path := KIT + model + ".glb"
	if not _kit_cache.has(model):
		_kit_cache[model] = load(path) if ResourceLoader.exists(path) else null
	var scene: PackedScene = _kit_cache[model]
	if scene:
		var n: Node3D = scene.instantiate()
		if not _kit_size.has(model):
			_kit_size[model] = _bounds(n)
		var bounds: AABB = _kit_size[model]
		if bounds.size.y > 0.01:
			var k := size.y / bounds.size.y   # the kit is modelled at about half life size
			if size.y < 0.05 and bounds.size.x > 0.01:
				k = size.x / bounds.size.x   # a rug: by width
			var wrap := Node3D.new()
			n.scale = Vector3(k, k, k)
			n.position.y = -bounds.position.y * k
			wrap.add_child(n)
			return wrap
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


## The bounds of a model's meshes in its own frame (no tree needed).
static func _bounds(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var p: Node = mi
		while p != n and p is Node3D:
			xf = p.transform * xf
			p = p.get_parent()
		var b: AABB = xf * mi.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


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
