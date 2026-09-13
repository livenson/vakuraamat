# Sports pitches from OpenStreetMap (tools/pipeline/fetch_pitches.py writes pitches.json: each pitch's
# centre, long axis, size and sport). The orthophoto already carries the markings; this adds what
# stands on them - a goal at each short end of a football pitch (full size on a full pitch, smaller on
# a small one), a net across a tennis or volleyball court, a backboard and hoop at each end of a
# basketball court. Built from shared unit boxes, cylinders and a torus, no assets (playtest
# 2026-09-13, Rovaniemi: "this looks like a football pitch, can you detect from data and add it?").
class_name Pitches
extends Node3D

const VIEW_RANGE := 300.0
static var _meshes: Dictionary = {}   # "box" | "cyl" | "ring" -> Mesh, shared between tiles
static var _mats: Dictionary = {}     # "white" | "net" | "ring" -> StandardMaterial3D


## Released with the world, like the other session caches.
static func release() -> void:
	_meshes.clear()
	_mats.clear()


## Put the equipment on every pitch of `pack` under `root`, standing on the ground of `terrain`.
static func place(pack: String, root: Node3D, terrain: Terrain3D) -> void:
	var path := Sites.path_in(pack, "pitches.json")
	if not FileAccess.file_exists(path):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var node := Pitches.new()
	node.name = "Pitches"
	root.add_child(node)
	var offset := root.position   # a streamed tile's root sits at its tile offset; the pieces stay local
	for p in parsed.get("pitches", []):
		var sport := str(p.get("sport")) if p.get("sport") != null else ""
		var h := deg_to_rad(float(p.get("heading", 0.0)))
		var c := Vector3(float(p.get("x", 0.0)), 0.0, float(p.get("z", 0.0)))
		var along := Vector3(sin(h), 0.0, -cos(h))   # the long side: 0 = north (-z), clockwise
		var across := Vector3(cos(h), 0.0, sin(h))
		var length := float(p.get("length", 0.0))
		var width := float(p.get("width", 0.0))
		match sport:
			"soccer", "multi":
				# full size (7.32 x 2.44 m) on a full pitch, a 5 m goal on a school field, 3 m on a yard
				var gw := 7.32 if length >= 90.0 else (5.0 if length >= 50.0 or sport == "soccer" and length >= 40.0 else 3.0)
				var gh := 2.44 if gw > 7.0 else 2.0
				for s in [-1.0, 1.0]:
					_goal(node, terrain, offset, c + along * s * (length * 0.5 - 0.4), along * -s, across, gw, gh)
			"tennis":
				_net(node, terrain, offset, c, across, minf(width - 2.0, 12.8), 1.07, 0.9)
			"volleyball", "beachvolleyball":
				_net(node, terrain, offset, c, across, minf(width - 1.0, 9.5), 2.43, 1.0)
			"basketball":
				for s in [-1.0, 1.0]:
					_hoop(node, terrain, offset, c + along * s * (length * 0.5), along * -s, across)


## A goal: two posts and a crossbar on the line, the frame running back `depth` metres behind it.
## `inward` points onto the pitch.
static func _goal(parent: Node3D, terrain: Terrain3D, offset: Vector3, line: Vector3, inward: Vector3, across: Vector3, w: float, h: float) -> void:
	var y := _ground(terrain, offset, line)
	var back := -inward * minf(2.0, w * 0.25)
	var up := Vector3.UP
	var l := line + Vector3(0, y, 0) - across * w * 0.5
	var r := line + Vector3(0, y, 0) + across * w * 0.5
	_rod(parent, l, l + up * h, 0.06)
	_rod(parent, r, r + up * h, 0.06)
	_rod(parent, l + up * h, r + up * h, 0.06)
	_rod(parent, l + up * h, l + back, 0.04)        # the stays down to the back of the net frame
	_rod(parent, r + up * h, r + back, 0.04)
	_rod(parent, l + back, r + back, 0.04)
	_rod(parent, l, l + back, 0.04)
	_rod(parent, r, r + back, 0.04)


## A net across the court's middle: a post at each end, the net a thin dark band under a white tape.
static func _net(parent: Node3D, terrain: Terrain3D, offset: Vector3, c: Vector3, across: Vector3, length: float, top: float, band: float) -> void:
	if length < 2.0:
		return
	var y := _ground(terrain, offset, c)
	var mid := c + Vector3(0, y, 0)
	for s in [-1.0, 1.0]:
		var foot: Vector3 = mid + across * s * length * 0.5
		_rod(parent, foot, foot + Vector3.UP * (top + 0.05), 0.04)
	var along := across.cross(Vector3.UP).normalized()
	_box(parent, mid + Vector3.UP * (top - band * 0.5), across * length, Vector3.UP * band, along * 0.02, "net")
	_box(parent, mid + Vector3.UP * (top - 0.03), across * length, Vector3.UP * 0.06, along * 0.025, "white")


## A basketball hoop at a court's end: a pole behind the baseline, an arm over it, the backboard 1.2 m
## inside the line and the ring 3.05 m up in front of it. `inward` points onto the court.
static func _hoop(parent: Node3D, terrain: Terrain3D, offset: Vector3, line: Vector3, inward: Vector3, across: Vector3) -> void:
	var y := _ground(terrain, offset, line)
	var pole := line - inward * 0.3 + Vector3(0, y, 0)
	var board := line + inward * 1.2 + Vector3(0, y + 3.4, 0)
	_rod(parent, pole, pole + Vector3.UP * 3.5, 0.07)
	_rod(parent, pole + Vector3.UP * 3.4, board - inward * 0.05, 0.05)
	_box(parent, board, across * 1.8, Vector3.UP * 1.05, inward * 0.04, "white")
	var mi := _piece(parent, "ring", "ring")
	mi.position = board + inward * 0.38 + Vector3.DOWN * 0.35


static func _ground(terrain: Terrain3D, offset: Vector3, local: Vector3) -> float:
	var h := terrain.data.get_height(offset + local)
	return 0.0 if is_nan(h) else h


## A round bar from `a` to `b` (local metres), `r` thick.
static func _rod(parent: Node3D, a: Vector3, b: Vector3, r: float) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.01:
		return
	var y := d / l
	var x := y.cross(Vector3.FORWARD) if absf(y.dot(Vector3.FORWARD)) < 0.99 else y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	var mi := _piece(parent, "cyl", "white")
	mi.transform = Transform3D(Basis(x * r * 2.0, y * l, z * r * 2.0), (a + b) * 0.5)


## A box centred at `centre` whose sides are the three given vectors (lengths and directions).
static func _box(parent: Node3D, centre: Vector3, sx: Vector3, sy: Vector3, sz: Vector3, mat: String) -> void:
	var mi := _piece(parent, "box", mat)
	mi.transform = Transform3D(Basis(sx, sy, sz), centre)


static func _piece(parent: Node3D, mesh: String, mat: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh(mesh)
	mi.material_override = _mat(mat)
	mi.visibility_range_end = VIEW_RANGE
	parent.add_child(mi)
	return mi


static func _mesh(key: String) -> Mesh:
	if not _meshes.has(key):
		match key:
			"box":
				_meshes[key] = BoxMesh.new()   # 1 x 1 x 1, scaled by the transform
			"cyl":
				var c := CylinderMesh.new()
				c.top_radius = 0.5
				c.bottom_radius = 0.5
				c.height = 1.0
				c.radial_segments = 8
				c.rings = 1
				_meshes[key] = c
			"ring":
				var t := TorusMesh.new()
				t.inner_radius = 0.21
				t.outer_radius = 0.24
				t.rings = 16
				t.ring_segments = 6
				_meshes[key] = t
	return _meshes[key]


static func _mat(key: String) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		match key:
			"white":
				m.albedo_color = Color(0.93, 0.93, 0.9)
				m.roughness = 0.5
			"net":
				m.albedo_color = Color(0.12, 0.12, 0.13)
				m.roughness = 0.9
			"ring":
				m.albedo_color = Color(0.88, 0.36, 0.12)
				m.metallic = 0.4
				m.roughness = 0.5
		_mats[key] = m
	return _mats[key]
