# What buses call at this place and when: the pack's departures.json, taken from the national
# public transport register's GTFS feed (tools/pipeline/fetch_departures.py). Each route is one line
# in one direction, with the geometry it drives through the tile, the stops it calls at, and the
# departure times for a weekday, a Saturday and a Sunday. Cached per file like Parcels.units.
#
# The times are the register's own, so the timetable on a shelter is the timetable at that shelter.
# A pack whose stops are not served, or whose departures were never fetched, simply has none.
class_name Departures
extends RefCounted

const DAYS := ["weekday", "saturday", "sunday"]

static var _cache: Dictionary = {}   # departures.json path -> parsed dictionary


static func _file(pack: String) -> Dictionary:
	var path := Sites.path_in(pack if pack != "" else Sites.active, "departures.json")
	if not _cache.has(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		_cache[path] = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	return _cache[path]


## Every route of the pack: {line, headsign, long_name, shape, calls, departures}.
static func routes(pack: String = "") -> Array:
	return _file(pack).get("routes", [])


## The routes calling at one stop (the pack's own OSM stop id), in line order.
static func at_stop(pack: String, stop_id: String) -> Array:
	if stop_id == "":
		return []
	var out: Array = routes(pack).filter(func(r): return stop_id in r.get("calls", []))
	out.sort_custom(func(a, b): return _line_key(str(a.get("line", ""))) < _line_key(str(b.get("line", ""))))
	return out


## Which service day the world is on. Nothing tracks the date across midnight, so a place is read on
## a weekday unless its site manifest's terrain date says otherwise - the day the data describes.
static func today(pack: String = "") -> String:
	var t: Dictionary = (Sites.manifest_for(pack) if pack != "" else Sites.manifest).get("terrain", {})
	var date: Array = t.get("date", []) if typeof(t) == TYPE_DICTIONARY else []
	if date.size() < 3:
		return "weekday"
	var when: Dictionary = Time.get_datetime_dict_from_unix_time(Time.get_unix_time_from_datetime_dict(
		{"year": int(date[0]), "month": int(date[1]), "day": int(date[2]), "hour": 12, "minute": 0, "second": 0}))
	var w := int(when.get("weekday", Time.WEEKDAY_MONDAY))
	return "saturday" if w == Time.WEEKDAY_SATURDAY else "sunday" if w == Time.WEEKDAY_SUNDAY else "weekday"


## The day's departures of one route as "HH:MM", falling back to a weekday when the line does not
## run on this one (a Sunday list that does not exist means no service, and stays empty).
static func times_of(route: Dictionary, day: String) -> Array:
	var d: Dictionary = route.get("departures", {})
	return d.get(day, [])


## The next `count` departures from `hour` (a float hour of the day) at a stop, soonest first, as
## [{line, headsign, time, minutes}] where `minutes` is how long until it leaves. Wraps past
## midnight so the last board of the night still shows the first bus of the morning.
static func next_from(pack: String, stop_id: String, hour: float, count: int = 6) -> Array:
	var now := int(round(hour * 60.0))
	var day := today(pack)
	var out: Array = []
	for r in at_stop(pack, stop_id):
		for t in times_of(r, day):
			var m := _minutes(str(t))
			if m < 0:
				continue
			var wait := m - now
			if wait < 0:
				wait += 24 * 60
			out.append({"line": str(r.get("line", "")), "headsign": str(r.get("headsign", "")), "time": str(t), "minutes": wait})
	out.sort_custom(func(a, b): return a.minutes < b.minutes)
	return out.slice(0, count)


static func forget() -> void:
	_cache.clear()


# ---------------------------------------------------------------- internals

static func _minutes(hhmm: String) -> int:
	var bits := hhmm.split(":")
	return int(bits[0]) * 60 + int(bits[1]) if bits.size() == 2 else -1


## Lines sort the way a timetable prints them: 2 before 10, and 25C after 25 but before 438.
static func _line_key(line: String) -> String:
	var digits := ""
	for ch in line:
		if ch >= "0" and ch <= "9":
			digits += ch
		else:
			break
	return "%09d%s" % [int(digits) if digits != "" else 0, line]
