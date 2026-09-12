# Colours and classes of the map's company layer: a parcel takes the colour of its dominant tenant
# in the chosen mode. Sectors are the game's EMTAK groups (tools/pipeline/emtak.py); health comes
# from the register status, the Tax Board quarters and the report deadline (register_extra.py).
class_name MapPalette
extends RefCounted

const MODES := ["off", "sector", "size", "health", "age", "owners"]

const SECTOR_COLORS := {
	"farm": Color(0.45, 0.72, 0.25), "industry": Color(0.55, 0.55, 0.6), "construction": Color(0.85, 0.6, 0.2),
	"trade": Color(0.95, 0.35, 0.3), "transport": Color(0.6, 0.45, 0.3), "hospitality": Color(0.95, 0.55, 0.65),
	"media": Color(0.3, 0.55, 0.95), "finance": Color(0.25, 0.35, 0.75), "property": Color(0.7, 0.55, 0.85),
	"services": Color(0.35, 0.75, 0.8), "public": Color(0.95, 0.85, 0.3), "culture": Color(0.95, 0.7, 0.45),
}
const HEALTH_COLORS := {"sound": Color(0.35, 0.75, 0.35), "watch": Color(0.95, 0.75, 0.2), "distressed": Color(0.85, 0.2, 0.2)}
const AGE_BANDS := [[1990, Color(0.25, 0.3, 0.55)], [2000, Color(0.3, 0.5, 0.7)], [2010, Color(0.4, 0.7, 0.75)], [2020, Color(0.6, 0.85, 0.6)], [9999, Color(0.95, 0.9, 0.45)]]
const NO_TENANT := Color(0.5, 0.5, 0.5, 0.18)


## The parcel's fill in `mode`, from its dominant tenant row (tenants.json shape), or the empty colour.
static func colour(mode: String, t: Dictionary) -> Color:
	if t.is_empty():
		return NO_TENANT
	match mode:
		"sector":
			return SECTOR_COLORS.get(str(t.get("sector", "")), Color(0.7, 0.7, 0.7))
		"health":
			return HEALTH_COLORS.get(str(t.get("health", "")), Color(0.7, 0.7, 0.7))
		"age":
			var year := int(str(t.get("since", "")).left(4)) if str(t.get("since", "")).length() >= 4 else 0
			for band in AGE_BANDS:
				if year < int(band[0]):
					return band[1]
			return AGE_BANDS[-1][1]
		"size", "owners":
			return Color(0.9, 0.9, 0.9)
	return NO_TENANT


## What the mode is measuring, for the foot of its legend: a translation key. Every layer says which
## of a plot's companies decides it (the largest active one; health falls back to the others when
## none is active). "Health" is also the one that reads as something else entirely - the condition of
## the building, or a hospital - so it says whose health and where it comes from.
static func note(mode: String) -> String:
	match mode:
		"sector":
			return "UI_MAP_SECTOR_NOTE"   # which of a plot's companies decides its colour
		"size":
			return "UI_MAP_SIZE_NOTE"
		"health":
			return "UI_MAP_HEALTH_NOTE"
		"age":
			return "UI_MAP_AGE_NOTE"
		"owners":
			return "UI_MAP_OWNERS_NOTE"
	return ""


## Legend entries of a mode: [[label key or text, colour], ...].
static func legend(mode: String) -> Array:
	var out := []
	match mode:
		"sector":
			for k in SECTOR_COLORS:
				out.append(["SECTOR_" + k.to_upper(), SECTOR_COLORS[k]])
		"health":
			for k in HEALTH_COLORS:
				out.append(["HEALTH_" + k.to_upper(), HEALTH_COLORS[k]])
		"age":
			var prev := 1900
			for band in AGE_BANDS:
				var top: int = int(band[0])
				out.append([("%d+" % prev) if top == 9999 else ("%d–%d" % [prev, top - 1]), band[1]])
				prev = top
		"size":
			out.append(["UI_MAP_SIZE_LEGEND", Color(0.9, 0.9, 0.9)])
		"owners":
			out.append(["UI_MAP_OWNERS_LEGEND", Color(1.0, 0.85, 0.3)])
	return out


## The company a parcel is coloured by in `mode`: its largest active company. In the health layer a
## parcel whose companies are all inactive (bankrupt, in liquidation) shows the worst of their verdicts
## instead of nothing - `dominant` skips them, so the legend promised red for them and a plot never
## turned red for its register status. Only then: an Old Town office address holds dozens of firms,
## nearly always one in liquidation, and "the worst verdict wins" painted a third of the town red
## (106 of 344 plots, against 11 with this rule).
static func pick(mode: String, rows: Array) -> Dictionary:
	var best := dominant(rows)
	if mode != "health" or not best.is_empty():
		return best
	var rank := {"distressed": 2, "watch": 1, "sound": 0}
	var best_key := -1.0
	for t in rows:
		var h := str(t.get("health", ""))
		if not rank.has(h):
			continue
		var size := float(t.get("employees", 0) if t.get("employees") != null else 0)
		var key := float(rank[h]) * 1e12 + size * 1e6 + float(t.get("turnover", 0) if t.get("turnover") != null else 0) / 1e6
		if key > best_key:
			best_key = key
			best = t
	return best


## The company that stands for a parcel: the biggest by employees, then by turnover, among the rows
## the register still calls registered. A company struck off does not colour a plot - it would read
## as a business in trouble where the truth is that there is no business, and on a plot with a live
## company beside a struck-off one it took the plot's colour away from the firm actually there.
static func dominant(rows: Array) -> Dictionary:
	var best := {}
	var best_key := -1.0
	for t in rows:
		if str(t.get("status", "R")) != "R":
			continue
		var key := float(t.get("employees", 0) if t.get("employees") != null else 0) * 1000000.0 + float(t.get("turnover", 0) if t.get("turnover") != null else 0)
		if key > best_key or best.is_empty():
			best_key = key
			best = t
	return best
