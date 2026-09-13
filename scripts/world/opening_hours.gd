# OpenStreetMap's opening_hours, the part of its syntax shops actually use: "24/7", day ranges and
# lists ("Mo-Fr", "Mo,We,Fr"), several time ranges a day ("08:00-12:00,13:00-17:00"), hours past
# midnight ("Fr,Sa 11:00-02:00"), "off" and "closed", later rules overriding earlier ones for the days
# they name. Holidays (PH, SH) are ignored; a rule with months, weeks or sunrise is skipped, and a text
# with nothing readable left parses to [] (the caller then says nothing about the hours).
class_name OpeningHours
extends RefCounted

const DAYS := ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
const _MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
static var _parsed: Dictionary = {}   # text -> Array, shared: the same chain's hours recur


## Seven lists (Monday first) of Vector2(open, close) in hours; a close past midnight is above 24.
## [] when the text says nothing this reader understands.
static func parse(text: String) -> Array:
	if _parsed.has(text):
		return _parsed[text]
	var week: Array = []
	for i in 7:
		week.append([])
	var any := false
	var clean := text.strip_edges()
	var quoted := RegEx.create_from_string("\"[^\"]*\"")
	clean = quoted.sub(clean, "", true)   # comments
	for rule_raw in clean.replace("||", ";").split(";", false):
		var rule := rule_raw.strip_edges()
		if rule == "":
			continue
		if rule == "24/7":
			for d in 7:
				week[d] = [Vector2(0, 24)]
			any = true
			continue
		if _unreadable(rule):
			continue
		var days := _days(rule)
		if days.is_empty():
			continue   # a holiday-only rule, or a selector this reader does not know
		var rest := _after_days(rule)
		var spans: Array = []
		if rest == "" or rest == "off" or rest == "closed":
			spans = []
		elif rest == "24/7" or rest == "00:00-24:00":
			spans = [Vector2(0, 24)]
		else:
			for piece in rest.split(",", false):
				var span := _span(piece.strip_edges())
				if span.x < 0.0:
					spans = []
					days = []
					break
				spans.append(span)
		if days.is_empty():
			continue
		for d in days:
			week[d] = spans
		any = true
	var out: Array = week if any else []
	_parsed[text] = out
	return out


## Whether a parsed week is open on `weekday` (0 = Monday) at `hour` (0-24): today's spans, and
## yesterday's that ran past midnight.
static func is_open(week: Array, weekday: int, hour: float) -> bool:
	if week.size() != 7:
		return false
	for s: Vector2 in week[weekday % 7]:
		if hour >= s.x and hour < s.y:
			return true
	for s: Vector2 in week[(weekday + 6) % 7]:
		if s.y > 24.0 and hour + 24.0 < s.y:
			return true
	return false


## "09:00-18:00" (several joined by ", ") for one day of a parsed week, "" when closed that day.
static func day_text(week: Array, weekday: int) -> String:
	if week.size() != 7:
		return ""
	var bits: Array[String] = []
	for s: Vector2 in week[weekday % 7]:
		bits.append("%s-%s" % [_hhmm(s.x), _hhmm(s.y)])
	return ", ".join(bits)


## The weekday (0 = Monday) of the pack's own date: the day its photograph was taken, the date the
## timetables are read for (Departures.today), Monday when the pack has none.
static func weekday(pack: String) -> int:
	var t: Dictionary = Sites.manifest_for(pack).get("terrain", {}) if pack != "" else Sites.manifest.get("terrain", {})
	var date: Array = t.get("date", []) if typeof(t) == TYPE_DICTIONARY else []
	if date.size() < 3:
		return 0
	var when := Time.get_datetime_dict_from_unix_time(Time.get_unix_time_from_datetime_dict(
		{"year": int(date[0]), "month": int(date[1]), "day": int(date[2]), "hour": 12, "minute": 0, "second": 0}))
	return (int(when.get("weekday", Time.WEEKDAY_MONDAY)) + 6) % 7   # Godot counts from Sunday


static func _unreadable(rule: String) -> bool:
	if "sunrise" in rule or "sunset" in rule or "dawn" in rule or "dusk" in rule or "week" in rule or "[" in rule:
		return true
	for m in _MONTHS:
		if rule.begins_with(m) or (" " + m) in rule:
			return true
	return false


## The weekday indices a rule's day selector names; every day when it names none but has times.
static func _days(rule: String) -> Array:
	var head := rule.split(" ", false)[0] if " " in rule else rule
	if not (head.substr(0, 2) in DAYS or head.begins_with("PH") or head.begins_with("SH")):
		return [0, 1, 2, 3, 4, 5, 6] if _span(head.split(",")[0]).x >= 0.0 or head in ["off", "closed"] else []
	var out: Array = []
	for part in head.split(",", false):
		if part in ["PH", "SH"]:
			continue
		var ends := part.split("-")
		var a := DAYS.find(ends[0])
		var b := DAYS.find(ends[ends.size() - 1])
		if a < 0 or b < 0:
			return []
		var d := a
		while true:
			if not out.has(d):
				out.append(d)
			if d == b:
				break
			d = (d + 1) % 7
	return out


static func _after_days(rule: String) -> String:
	var head := rule.split(" ", false)[0]
	if head.substr(0, 2) in DAYS or head.begins_with("PH") or head.begins_with("SH"):
		return rule.substr(head.length()).strip_edges()
	return rule


## "HH:MM-HH:MM" as Vector2(open, close) in hours, the close above 24 past midnight; x < 0 unread.
static func _span(piece: String) -> Vector2:
	var ends := piece.replace("+", "").split("-")
	if ends.size() != 2:
		return Vector2(-1, -1)
	var a := _hours(ends[0])
	var b := _hours(ends[1])
	if a < 0.0 or b < 0.0:
		return Vector2(-1, -1)
	if b <= a:
		b += 24.0
	return Vector2(a, b)


static func _hours(t: String) -> float:
	var hm := t.strip_edges().split(":")
	if hm.size() != 2 or not hm[0].is_valid_int() or not hm[1].is_valid_int():
		return -1.0
	return int(hm[0]) + int(hm[1]) / 60.0


static func _hhmm(h: float) -> String:
	var m := int(round(h * 60.0)) % (24 * 60) if h < 24.0 or h > 24.0 else 24 * 60
	return "%02d:%02d" % [m / 60, m % 60]
