# Autoload "Reporter": in-game issue reports for the development loop. F8 grabs the frame, then a
# note is typed; capture() writes user://reports/<id>.json + .png + a save slot and appends one line
# to user://reports/feed.log, which the developer's tools (or Claude Code's Monitor) tail. The JSON
# carries everything needed to come back to the exact spot: `--report=<file>` on the world scene.
extends Node

signal reported(path: String)

const DIR := "user://reports/"
const FEED := "user://reports/feed.log"
const MAX_ERRORS := 40

var recent_errors: Array[String] = []
var _frame: Image = null
var _logger: ErrorLog = null


## Keeps the last engine errors and warnings so a report can quote them.
class ErrorLog:
	extends Logger
	var sink: Callable

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, _error_type: int, _script_backtraces: Array) -> void:
		sink.call("%s:%d  %s  %s" % [file, line, code, rationale])

	func _log_message(message: String, error: bool) -> void:
		if error:
			sink.call(message.strip_edges())


func _ready() -> void:
	_logger = ErrorLog.new()
	_logger.sink = _remember
	OS.add_logger(_logger)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))


func _remember(line: String) -> void:
	if line == "" or (not recent_errors.is_empty() and recent_errors[-1] == line):
		return
	recent_errors.append(line)
	if recent_errors.size() > MAX_ERRORS:
		recent_errors.pop_front()


## Grab the frame before any panel opens over it.
func snapshot(world: Node) -> void:
	_frame = world.get_viewport().get_texture().get_image()


## Write the report. Returns the JSON path ("" on failure).
func capture(note: String, world: Node) -> String:
	if world == null:
		return ""
	var ts := Time.get_datetime_string_from_system(false, false).replace(":", "-")
	var id := "report_" + ts
	var base := DIR + id
	if _frame == null:
		snapshot(world)
	var shot := ""
	if _frame != null:   # headless runs render nothing
		_frame.save_png(base + ".png")
		shot = ProjectSettings.globalize_path(base + ".png")
	_frame = null
	SaveManager.save(id)
	var player: Node3D = world.player
	var cam: Camera3D = player.camera
	var interactor: Interactor = cam.get_node_or_null("Interactor")
	var layer: Node = world.get_node("EraLayers").get_node_or_null(GameState.current_era)
	var pos := player.global_position
	var report := {
		"id": id, "time": Time.get_datetime_string_from_system(), "note": note,
		"site": Sites.active, "era": GameState.current_era, "chapter": GameState.chapter,
		"position": [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), snappedf(pos.z, 0.01)],
		"yaw_deg": snappedf(rad_to_deg(player.rotation.y), 0.1), "pitch_deg": snappedf(rad_to_deg(cam.rotation.x), 0.1),
		"target": _describe(interactor.target if interactor else null, pos),
		"nearby": _nearby(layer, pos), "buildings_nearby": _buildings_nearby(layer, pos),
		"flags": TimelineState.flags.keys(), "artifacts": Inventory.artifacts.duplicate(),
		"errors": recent_errors.duplicate(), "screenshot": shot,
		"save_slot": id, "locale": TranslationServer.get_locale(), "fps": Engine.get_frames_per_second(),
		"replay": "godot --path %s res://scenes/world/world.tscn -- --report=%s" % [ProjectSettings.globalize_path("res://"), ProjectSettings.globalize_path(base + ".json")],
	}
	var f := FileAccess.open(base + ".json", FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	var feed := FileAccess.open(FEED, FileAccess.READ_WRITE if FileAccess.file_exists(FEED) else FileAccess.WRITE)
	feed.seek_end()
	feed.store_line("%s | %s %s | at %.0f,%.0f yaw %.0f | %s | %s | %s" % [report.time, Sites.active, GameState.current_era, pos.x, pos.z, report.yaw_deg,
			report.target.get("label", "-"), note.replace("\n", " "), ProjectSettings.globalize_path(base + ".json")])
	feed.close()
	print("[Reporter] %s" % ProjectSettings.globalize_path(base + ".json"))
	reported.emit(ProjectSettings.globalize_path(base + ".json"))
	return ProjectSettings.globalize_path(base + ".json")


func _describe(n: Node, from: Vector3) -> Dictionary:
	if n == null:
		return {}
	var d := {"path": str(n.get_path()), "name": n.name, "class": n.get_class(), "script": n.get_script().resource_path if n.get_script() else ""}
	if n is Interactable:
		d["label"] = n.label()
		d["hover"] = n.hover_text()
	if n is Node3D:
		var p: Vector3 = n.global_position
		d["position"] = [snappedf(p.x, 0.1), snappedf(p.y, 0.1), snappedf(p.z, 0.1)]
		d["distance"] = snappedf(from.distance_to(p), 0.1)
	for prop in ["npc_id", "knot", "item_id", "text_key", "location_id", "flag", "era_id", "manor_id", "building_id"]:
		if prop in n:
			d[prop] = n.get(prop)
	return d


func _nearby(layer: Node, from: Vector3, radius := 15.0) -> Array:
	var out := []
	if layer == null:
		return out
	for n in layer.find_children("*", "Interactable", true, false):
		if n.is_visible_in_tree() and n.global_position.distance_to(from) <= radius:
			out.append(_describe(n, from))
	out.sort_custom(func(a, b): return a.get("distance", 0) < b.get("distance", 0))
	return out.slice(0, 12)


func _buildings_nearby(layer: Node, from: Vector3, radius := 25.0) -> Array:
	var out := []
	if layer == null:
		return out
	var table := {}
	var text := FileAccess.get_file_as_string(Sites.path("buildings.json"))
	var parsed = JSON.parse_string(text) if text != "" else null
	if typeof(parsed) == TYPE_DICTIONARY:
		for b in parsed.get("buildings", []):
			table[int(b.id)] = b
	for n in layer.find_children("*", "FootprintBuilding", true, false):
		if not n.is_visible_in_tree() or n.global_position.distance_to(from) > radius:
			continue
		var b: Dictionary = table.get(n.building_id, {})
		out.append({"building_id": n.building_id, "distance": snappedf(from.distance_to(n.global_position), 0.1), "name": b.get("name"), "year": b.get("year"),
				"address": b.get("address"), "materials": b.get("materials", {}), "height": n.height, "lod2": b.get("lod2") != null})
	out.sort_custom(func(a, b): return a.distance < b.distance)
	return out.slice(0, 8)
