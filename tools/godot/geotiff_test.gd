# GeoTiff reads a window out of a float32 GeoTIFF the way the pipeline's rasterio does: the same
# heights, from a tiled deflate sheet and from a stripped uncompressed one, with the no-data value
# where the sheet has none, and nothing outside the sheet.
#   godot --headless --path . res://tools/godot/geotiff_test.tscn
extends Node

const DIR := "res://tools/godot/fixtures/"
var _failed := false


func _check(cond: bool, msg: String) -> void:
	if not cond and not _failed:
		_failed = true
		print("[geotiff] FAILED: ", msg)
		get_tree().quit(1)


func _ready() -> void:
	# the fixtures are 128 x 128 at 1 m from (655000, 6480000); the reference is the 32 x 32 window
	# 40 px east and 48 px south of the north-west corner, written by rasterio
	var want := FileAccess.get_file_as_bytes(DIR + "window_32x32.r32").to_float32_array()
	_check(want.size() == 32 * 32, "reference window is %d floats" % want.size())
	var bounds := Rect2(655040.0, 6480000.0 - 80.0, 32.0, 32.0)
	for name in ["tiled_deflate.tif", "stripped_plain.tif"]:
		var path := ProjectSettings.globalize_path(DIR + name)
		var h := GeoTiff.read_header(path)
		_check(not h.is_empty(), "%s: no header" % name)
		_check(h.width == 128 and h.height == 128, "%s: %dx%d" % [name, h.width, h.height])
		_check(h.nodata == -9999.0, "%s: nodata %f" % [name, h.nodata])
		var w := GeoTiff.read_window_with(h, bounds)
		_check(w.width == 32 and w.height == 32, "%s: window %dx%d" % [name, w.width, w.height])
		var worst := 0.0
		for i in want.size():
			worst = maxf(worst, absf(want[i] - w.data[i]))
		_check(worst == 0.0, "%s: worst difference %f m from the reference" % [name, worst])
	# the no-data hole the fixture carries (x 100..110, y 10..20) comes back as the no-data value
	var hole := GeoTiff.read_window(ProjectSettings.globalize_path(DIR + "tiled_deflate.tif"),
			Rect2(655100.0, 6480000.0 - 20.0, 8.0, 8.0))
	_check(hole.data[0] == -9999.0, "the no-data hole read back as %f" % hole.data[0])
	# a window off the sheet is empty, not a crash
	var away := GeoTiff.read_window(ProjectSettings.globalize_path(DIR + "tiled_deflate.tif"),
			Rect2(600000.0, 6400000.0, 32.0, 32.0))
	_check(away.is_empty(), "a window off the sheet returned %d floats" % (away.data.size() if away.has("data") else -1))
	if not _failed:
		print("[geotiff] PASSED: tiled deflate and stripped plain both match rasterio exactly")
		get_tree().quit(0)
