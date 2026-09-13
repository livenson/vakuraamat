# A pack's JSON files, parsed once per session and shared by everything that reads them: the roads
# (RoadNetwork, the shared RoadGraph, the map), the bus stops (the shelters, the buses), the companies
# (Tenants, Links, the map's and the K overlay's company layers), the farmed fields (ParcelKit, Crops).
# Each used to parse its own copy, so a tile's roads.json went through JSON.parse three times.
#
# What comes back is the one parsed copy: treat the Dictionary or Array as read-only, and copy
# (`duplicate(true)`) before changing anything in it, or every other reader sees the change.
# Dropped whole by GameState.forget_caches() and per pack when a streamed tile leaves (World).
class_name PackFiles
extends RefCounted

static var _cache: Dictionary = {}   # file path -> parsed JSON, or null for a missing or unreadable file


## The parsed contents of `rel` in `pack` ("" is the active pack): a Dictionary or an Array, null
## when the file is missing or is not JSON (remembered too, so a missing file is not asked again).
static func json(pack: String, rel: String) -> Variant:
	var path := Sites.path_in(pack if pack != "" else Sites.active, rel)
	if not _cache.has(path):
		var text := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
		_cache[path] = JSON.parse_string(text) if text != "" else null
	return _cache[path]


static func forget() -> void:
	_cache.clear()


## Drop one pack's files: a streamed tile left, and its files are read again if it comes back.
static func forget_pack(pack: String) -> void:
	if pack == "":
		return
	var prefix := Sites.path_in(pack, "")
	for path in _cache.keys():
		if str(path).begins_with(prefix):
			_cache.erase(path)
