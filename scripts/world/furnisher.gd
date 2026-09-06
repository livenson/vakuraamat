# The furniture of a generated room: pieces (Kenney and Poly Pizza models scaled to life size),
# plans by room role (anchored groups, wall runs, islands, grids, corners), placement that keeps
# out of doorways and other pieces, and a short simulated-annealing pass after Merrell et al. 2011
# and Yu et al. 2011 that resolves what the plans leave open. Interiors owns one Furnisher.
class_name Furnisher
extends RefCounted

const KIT := "res://assets/vendor/kenney_furniture_kit/glb/"
const KIT2 := "res://assets/vendor/polypizza/"   # bathroom pieces (Kenney CC0 via Poly Pizza)
const CLEAR := 1.2           # furniture keeps this far from doorways and the ramp

var _kit_cache: Dictionary = {}
var _kit_size: Dictionary = {}   # model -> AABB of the kit model as exported

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
	"toilet": [Vector3(0.4, 0.8, 0.7), Color(0.95, 0.95, 0.95)], "bathtub": [Vector3(1.7, 0.6, 0.75), Color(0.95, 0.95, 0.95)],
	"sink": [Vector3(0.5, 0.85, 0.45), Color(0.95, 0.95, 0.95)], "mirror": [Vector3(0.5, 0.6, 0.05), Color(0.8, 0.85, 0.9)],
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
	"bathroom": [
		{"kind": "anchor", "piece": "sink", "stack": "mirror"},
		{"kind": "run", "pieces": ["toilet"], "max": 1},
		{"kind": "run", "pieces": ["bathtub"], "max": 1, "walls": 2},
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
func furnish(root: Node3D, poly: PackedVector2Array, y0: float, role: String, seed_key: String, skip_edges: Array, avoid: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_key)
	var room := {"root": root, "poly": poly, "y0": y0, "avoid": avoid, "walls": [], "placed": [], "anchor": {}, "items": []}
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
	_anneal(room, rng)


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
	return {"at": w.a + w.dir * u + w.inward * (size.z * 0.5 + 0.08), "dir": w.dir, "inward": w.inward, "y": w.get("y", 0.0), "wall": w}


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
	if name == "cardboardBoxClosed":
		var box := Carryable.new()
		box.setup(node, size, 4.0)
		node = box
	var y: float = spot.get("y", room.y0) if spot.has("y") and spot.y != 0.0 else room.y0
	node.position = Vector3(at.x, y, at.y)
	var dir: Vector2 = spot.dir
	node.rotation.y = -atan2(dir.y, dir.x) + PI + (PI if bool(spot.get("facing_back", false)) else 0.0)   # back to the wall
	if bool(spot.get("facing_back", false)):
		node.set_meta("facing_back", true)
	node.set_meta("piece", true)
	node.set_meta("model", name)
	room.root.add_child(node)
	if size.y > 0.05:
		room.placed.append([at, r])
	var item := {"node": node, "name": name, "size": size, "at": at, "dir": dir, "y": y, "r": r,
		"wall": spot.get("wall", null), "grouped": bool(spot.get("grouped", false)), "children": []}
	if item.grouped and not room.items.is_empty():
		var host: Dictionary = room.items[room.items.size() - 1]
		while host.grouped and host.has("host"):
			host = host.host
		item["host"] = host
		item["offset"] = at - host.at
		host.children.append(item)
	room.items.append(item)
	return true


## A short simulated-annealing pass over the room (after Merrell et al. 2011 and Yu et al. 2011,
## reduced to what the plans leave open): wall pieces slide along their wall, free pieces shift and
## turn, grouped pieces follow their host; the cost is overlap, leaving the room, and crowding a
## doorway. About a hundred proposals per room.
func _anneal(room: Dictionary, rng: RandomNumberGenerator) -> void:
	var movable: Array = room.items.filter(func(it): return not it.grouped and it.size.y > 0.05)
	if movable.size() < 2:
		return
	var poly: PackedVector2Array = room.poly
	var steps := 40 * movable.size()
	for step in steps:
		var temp := 0.5 * (1.0 - float(step) / steps) + 0.02
		var it: Dictionary = movable[rng.randi() % movable.size()]
		var old_at: Vector2 = it.at
		var old_dir: Vector2 = it.dir
		var new_at := old_at
		var new_dir := old_dir
		if it.wall != null:
			var w: Dictionary = it.wall
			var u: float = (old_at - w.a).dot(w.dir) + rng.randf_range(-0.5, 0.5)
			u = clampf(u, it.size.x * 0.5 + 0.2, w.length - it.size.x * 0.5 - 0.2)
			new_at = w.a + w.dir * u + w.inward * (it.size.z * 0.5 + 0.08)
		else:
			new_at = old_at + Vector2(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6))
			if rng.randf() < 0.15:
				new_dir = Vector2(-old_dir.y, old_dir.x)
		var before := _cost(room, it, old_at, old_dir)
		var after := _cost(room, it, new_at, new_dir)
		if after < before or rng.randf() < exp((before - after) / temp):
			_move(it, new_at, new_dir)
	for it in room.items:
		var n: Node3D = it.node
		n.position = Vector3(it.at.x, it.y, it.at.y)
		var d: Vector2 = it.dir
		n.rotation.y = -atan2(d.y, d.x) + PI + (PI if n.has_meta("facing_back") else 0.0)


## Move a piece and its grouped children with it (their offsets turn with the host).
static func _move(it: Dictionary, at: Vector2, dir: Vector2) -> void:
	var turn := dir.angle() - (it.dir as Vector2).angle()
	it.at = at
	it.dir = dir
	for c in it.children:
		c.offset = (c.offset as Vector2).rotated(turn)
		c.at = at + c.offset
		c.dir = (c.dir as Vector2).rotated(turn)


## The cost of one piece at a pose: overlaps with the others (circles), corners outside the room,
## crowding a doorway; its grouped children count too.
func _cost(room: Dictionary, it: Dictionary, at: Vector2, dir: Vector2) -> float:
	var poly: PackedVector2Array = room.poly
	var turn := dir.angle() - (it.dir as Vector2).angle()
	var probes: Array = [[at, it.r]]
	for c in it.children:
		probes.append([at + (c.offset as Vector2).rotated(turn), c.r])
	var cost := 0.0
	for pr in probes:
		var p: Vector2 = pr[0]
		var r: float = pr[1]
		for other in room.items:
			if other == it or other.get("host") == it or other.size.y <= 0.05:
				continue
			var gap: float = p.distance_to(other.at) - (r + other.r + 0.15)
			if gap < 0.0:
				cost += gap * gap * 4.0
		if not Geometry2D.is_point_in_polygon(p, poly):
			cost += 6.0
		else:
			var d := INF
			for k in poly.size():
				d = minf(d, _dist_to_segment(p, poly[k], poly[(k + 1) % poly.size()]))
			if d < r * 0.7:
				cost += (r * 0.7 - d) * 3.0   # a corner through the wall
		for a in room.avoid:
			var da: float = p.distance_to(a) - (r + CLEAR)
			if da < 0.0:
				cost += da * da * 3.0
	return cost


static func _centroid(poly: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	return c / maxf(poly.size(), 1)


## A Kenney Furniture Kit model when vendored (`assets/vendor/kenney_furniture_kit/glb/<name>.glb`), else a box.
func _piece(model: String, size: Vector3, color: Color) -> Node3D:
	var path := KIT + model + ".glb"
	if not ResourceLoader.exists(path):
		path = KIT2 + model + ".glb"
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
			# centred on its footprint and standing on the floor: the exports put the origin anywhere
			n.position = Vector3(-(bounds.position.x + bounds.size.x * 0.5) * k, -bounds.position.y * k, -(bounds.position.z + bounds.size.z * 0.5) * k)
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


static func _dist_to_segment(p: Vector2, a: Vector2, c: Vector2) -> float:
	var u := _project_u(p, a, c)
	return p.distance_to(a + (c - a).normalized() * u)



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
