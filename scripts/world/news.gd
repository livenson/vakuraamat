# What is being said about this place: the pack's news.json, written by tools/news_feeder.py from
# the regional press (ERR, Postimees) and Ametlikud Teadaanded, filtered to the tile's streets,
# settlements and registered companies. Newest first, as the file is. Cached per file like
# Parcels.units. A pack whose news was never fetched simply has none.
class_name News
extends RefCounted

static var _cache: Dictionary = {}   # news.json path -> Array of items


## The pack's items, newest first. `url` is served as `link`, which is what the panel reads.
static func all(pack: String = "") -> Array:
	var path := Sites.path_in(pack if pack != "" else Sites.active, "news.json")
	if not _cache.has(path):
		var out: Array = []
		if FileAccess.file_exists(path):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
			if typeof(parsed) == TYPE_DICTIONARY:
				for r in parsed.get("events", []):
					out.append({"id": str(r.get("id", "")), "kind": str(r.get("kind", "news")),
						"source": str(r.get("source", "")), "title": str(r.get("title", "")),
						"link": str(r.get("url", "")), "published": str(r.get("published", "")),
						"area": str(r.get("area", "")), "tunnus": str(r.get("tunnus", ""))})
		_cache[path] = out
	return _cache[path]


## Who the items are credited to, as the file writes it (a string, a list, or a dictionary of
## source to credit). The book's place page flattens it with the other files' attributions.
static func attribution(pack: String = "") -> Variant:
	var path := Sites.path_in(pack if pack != "" else Sites.active, "news.json")
	if not FileAccess.file_exists(path):
		return []
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed.get("attribution", []) if typeof(parsed) == TYPE_DICTIONARY else []


static func forget() -> void:
	_cache.clear()
