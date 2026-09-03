# Phase 0 HUD: frame rate plus the player's real-world L-EST97 coordinates,
# so terrain/orthophoto alignment can be checked against Maa-amet's map.
extends Label

@export var player_path: NodePath
@export var tile := "palmse"
@export var sky_path: NodePath

var _georef: TerrainGeoref
var _player: Node3D
var _sky: Node


func _ready() -> void:
	_georef = TerrainGeoref.load_tile(tile)
	_player = get_node_or_null(player_path)
	_sky = get_node_or_null(sky_path)


func _process(_delta: float) -> void:
	var lines := PackedStringArray()
	lines.append("FPS %d" % Engine.get_frames_per_second())
	if _player:
		var p := _player.global_position
		lines.append("world  x %.1f  y %.1f  z %.1f" % [p.x, p.y, p.z])
		if _georef.is_valid():
			var c := _georef.world_to_lest97(p)
			lines.append("L-EST97  E %.1f  N %.1f  (sheet %s)" % [c.x, c.y, _georef.meta.get("sheet", "?")])
	if _sky and _sky.get("tod"):
		lines.append("time %s  %s  (%.0f min/day)" % [_sky.tod.game_time, _sky.tod.game_date, _sky.tod.minutes_per_day])
	var mode: String = _player.mode_label() if _player and _player.has_method("mode_label") else ""
	lines.append("WASD move  Shift sprint  Ctrl dash  F fly  Space jump  Esc mouse   [%s]" % mode)
	lines.append("T teleport to where you look   H back to spawn")
	lines.append(str(_georef.meta.get("attribution", "")))
	text = "\n".join(lines)
