# The land itself, over thirty years: one small aerial photograph of a plot per campaign. A plot that
# was forest in 1998 and a car park now says something its land value does not, so the book shows
# the plot's own square in each of them.
#
# Where the campaigns come from is the country's (assets/data/countries/<id>.json, "photos"). Either
# a WMS - Estonia's `ajalooline`, with a layer list per campaign, and its `fotokaart` for today, asked
# for one plot's square and so answering from whatever finer flight covers it - where every picture is
# one request kept in user://cache/plots, so a plot is fetched once and never again. A campaign that
# did not fly over the square answers with a blank white one, which is what `_has_ground` is for;
# that is remembered too. Or, where the older flights are only files (Latvia's LĢIA cycles), the
# pipeline cuts them over the tile and they are cropped like today's photograph, no request at all.
class_name PlotHistory
extends RefCounted

# Godot's HTTPRequest cannot read this endpoint over TLS: a GetMap comes back RESULT_CONNECTION_ERROR
# every time, while the same URL over plain http, the same host's other paths over https, and curl
# over either all answer normally (checked 2026-09-08 on 4.7.2; not gzip, not the certificate chain,
# which is the same one geoportaal.maaamet.ee serves and Godot accepts). The map imagery is public
# open data and the request carries nothing private, so the fallback is to ask again unencrypted
# rather than to lose the layer. Try https first, in case a later engine fixes it.
static var _scheme_ok := ""   # remembered for the session once one of them answers
static var _busy: Dictionary = {}   # base path -> true while that picture is being fetched
static var _answered := false       # did the last _fetch_image get any picture back at all?
const PX := 200                  # thumbnail size, and the WMS request size
const PAD := 12.0                # metres of context around the plot, so it is not edge to edge
const MIN_SPAN := 60.0           # a tiny plot still gets a legible square



## The square to photograph for a plot: its outline's bounds, padded, made square so the thumbnails
## are not stretched. `poly` is in tile metres; the result is in EPSG:3301.
static func square_for(poly: PackedVector2Array, georef: TerrainGeoref) -> Rect2:
	if poly.is_empty() or georef == null or not georef.is_valid():
		return Rect2()
	var lo := poly[0]
	var hi := poly[0]
	for p in poly:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var centre := (lo + hi) * 0.5
	var span := maxf(maxf(hi.x - lo.x, hi.y - lo.y) + PAD * 2.0, MIN_SPAN)
	var sw := georef.world_to_lest97(Vector3(centre.x - span * 0.5, 0.0, centre.y + span * 0.5))
	return Rect2(sw.x, sw.y, span, span)


## Where the plot's outline falls inside that square, as 0..1 texture coordinates (y down), so the
## thumbnail can be drawn with the plot marked on it.
static func outline_in(poly: PackedVector2Array, square: Rect2, georef: TerrainGeoref) -> PackedVector2Array:
	var out := PackedVector2Array()
	if square.size.x <= 0.0:
		return out
	for p in poly:
		var e := georef.world_to_lest97(Vector3(p.x, 0.0, p.y))
		out.append(Vector2((e.x - square.position.x) / square.size.x,
				1.0 - (e.y - square.position.y) / square.size.y))
	return out


## Where a pack's photographs come from: its country's "photos".
static func _photos(pack: String) -> Dictionary:
	return Countries.of_pack(pack).get("photos", {})


## The campaigns a pack's plots are shown in, oldest first. From the WMS: {label, layers}, the layers
## tried in order (Estonia's flights are split by purpose - asulad settlements, aero the main flight,
## mets forestry - and which covers a square is not knowable in advance). From the tile:
## {label, texture}, the files terrain_meta.json lists as "history".
static func epochs(pack: String) -> Array:
	var photos := _photos(pack)
	if bool(photos.get("from_tile", false)):
		return TerrainGeoref.load_dir(Sites.tile_dir_of(pack if pack != "" else Sites.active)).meta.get("history", [])
	return photos.get("epochs", [])


## The newest picture, cropped out of the tile's own orthophoto - no request, and it is by
## definition the one that matches the world the player is standing in. Null if the tile has none.
## `px` is what the crop is scaled to; the older years are re-requested from the service at the
## large view's size, so this one is asked for the same size or it alone stays a blurry thumbnail.
## The orthophoto is 25 cm to the pixel, so a plot's square usually has the detail to answer.
## `file` names another photograph of the same tile: a Latvian tile's older cycles lie beside it.
static func current(square: Rect2, georef: TerrainGeoref, tile_dir: String, px: int = PX, file: String = "ortho.jpg") -> Texture2D:
	var path := tile_dir + "/" + file
	if not FileAccess.file_exists(path) or not georef.is_valid():
		return null
	var img := Image.new()
	if img.load_jpg_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		return null
	var size := georef.tile_size_m()
	if size <= 0.0:
		return null
	var per_m := img.get_width() / size
	var nw := georef.lest97_to_world(square.position.x, square.position.y + square.size.y)
	var region := Rect2i(int(round(nw.x * per_m)), int(round(nw.z * per_m)),
			int(round(square.size.x * per_m)), int(round(square.size.y * per_m)))
	region = region.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if region.size.x < 8 or region.size.y < 8:
		return null
	var crop := img.get_region(region)
	crop.resize(px, px, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(crop)


## Every campaign that covers the plot, oldest first: [{label, texture}]. Fetches what is not
## already cached, one request at a time so the book does not open a dozen sockets.
static func fetch(pack: String, tunnus: String, square: Rect2) -> Array:
	var out: Array = []
	var dir := "user://cache/plots/%s" % pack
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	for e in epochs(pack):
		if e.has("texture"):   # the tile's own photograph of that year: a crop, nothing to fetch
			var tile := Sites.tile_dir_of(pack)
			var own := current(square, TerrainGeoref.load_dir(tile), tile, PX, str(e.texture))
			if own != null:
				out.append({"label": str(e.label), "texture": own})
			continue
		var base := "%s/%s_%s" % [dir, tunnus.replace(":", "_"), e.label]
		# The book refills while pictures are in flight, so a second pass must wait for the first
		# rather than skip the epoch: skipping would show fewer pictures than are already on disk.
		while _busy.has(base):
			await (Engine.get_main_loop() as SceneTree).process_frame
		var tex: Texture2D = _load(base + ".jpg")       # a picture we already have always wins
		if tex == null and not FileAccess.file_exists(base + ".none"):
			_busy[base] = true
			tex = await _fetch_one(e.layers, square, base, str(_photos(pack).get("wms", "")))
			_busy.erase(base)
		if tex != null:
			out.append({"label": e.label, "texture": tex})
	return out


static func _fetch_one(layers: Array, square: Rect2, base: String, wms: String) -> Texture2D:
	var img := await _fetch_image(layers, square, base, PX, wms)
	if img != null:
		DirAccess.rename_absolute(ProjectSettings.globalize_path(base + ".part"),
				ProjectSettings.globalize_path(base + ".jpg"))
		return ImageTexture.create_from_image(img)
	# Only remember "nothing here" when the service actually answered and the square came back
	# blank. A refused connection is not an answer: marking it would leave a plot opened once while
	# offline with no history for good.
	if _answered:
		var f := FileAccess.open(base + ".none", FileAccess.WRITE)
		if f:
			f.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(base + ".part"))
	return null


## The tile's own photograph of a plot at the large view's size. The tile is the one the plot sits
## on, which for a streamed neighbour is not the one the player entered from the menu.
static func current_large(pack: String, square: Rect2, px: int) -> Texture2D:
	var dir := Sites.tile_dir_of(pack if pack != "" else Sites.active)
	return current(square, TerrainGeoref.load_dir(dir), dir, px)


## Today at the large view's size, asked for as its own picture rather than magnified out of the
## tile's texture. That texture is 4096 px over a square kilometre - 25 cm to the pixel - so a small
## plot's square is a couple of hundred pixels in it and no amount of enlarging puts detail back;
## this is why today stayed soft while every older year sharpened. Requested directly, the service
## renders the square from the sharpest flight it has for it. Falls back to the crop, which is what
## the strip's thumbnail uses anyway and is plenty at that size, when the service cannot be reached.
static func fetch_current_large(pack: String, tunnus: String, square: Rect2, px: int) -> Texture2D:
	var dir := "user://cache/plots/%s" % pack
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var base := "%s/%s_today@%d" % [dir, tunnus.replace(":", "_"), px]
	var tex := _load(base + ".jpg")
	if tex != null:
		return tex
	var photos := _photos(pack)
	if str(photos.get("current_wms", "")) == "":
		return current_large(pack, square, px)   # no national photograph service to ask: the tile's own
	if tunnus != "" and not _busy.has(base):
		_busy[base] = true
		var img := await _fetch_image([str(photos.get("current_layer", ""))], square, base, px, str(photos.current_wms))
		_busy.erase(base)
		if img != null:
			DirAccess.rename_absolute(ProjectSettings.globalize_path(base + ".part"),
					ProjectSettings.globalize_path(base + ".jpg"))
			return ImageTexture.create_from_image(img)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(base + ".part"))
	return current_large(pack, square, px)


## The same square as one epoch's thumbnail, asked for at `px` instead of PX, for the large view.
## Cached beside the thumbnail; null when it cannot be had, and the caller keeps the small one.
static func fetch_large(pack: String, tunnus: String, label: String, square: Rect2, px: int) -> Texture2D:
	var dir := "user://cache/plots/%s" % pack
	var base := "%s/%s_%s@%d" % [dir, tunnus.replace(":", "_"), label, px]
	var tex := _load(base + ".jpg")
	if tex != null:
		return tex
	var epoch: Dictionary = {}
	for e in epochs(pack):
		if str(e.label) == label:
			epoch = e
			break
	if epoch.has("texture"):
		var tile := Sites.tile_dir_of(pack if pack != "" else Sites.active)
		return current(square, TerrainGeoref.load_dir(tile), tile, px, str(epoch.texture))
	if epoch.is_empty() or _busy.has(base):
		return null
	_busy[base] = true
	var img := await _fetch_image(epoch.layers, square, base, px, str(_photos(pack).get("wms", "")))
	_busy.erase(base)
	if img == null:
		return null
	DirAccess.rename_absolute(ProjectSettings.globalize_path(base + ".part"),
			ProjectSettings.globalize_path(base + ".jpg"))
	return ImageTexture.create_from_image(img)


## The first of `layers` that answers with a picture that has ground on it, at `px` square. Sets
## `_answered` to whether anything answered at all, so the caller can tell "no coverage here" from
## "the service could not be reached".
static func _fetch_image(layers: Array, square: Rect2, base: String, px: int, wms: String) -> Image:
	_answered = false
	if wms == "":
		return null
	for layer in layers:
		var q := {
			"SERVICE": "WMS", "VERSION": "1.3.0", "REQUEST": "GetMap", "LAYERS": layer, "STYLES": "",
			"CRS": "EPSG:3301", "WIDTH": px, "HEIGHT": px, "FORMAT": "image/jpeg",
			# WMS 1.3.0 axis order for EPSG:3301 is northing, easting
			"BBOX": "%f,%f,%f,%f" % [square.position.y, square.position.x,
					square.position.y + square.size.y, square.position.x + square.size.x],
		}
		var img := await _get_image(wms + "?" + _query(q), base + ".part")
		if img == null:
			continue                                   # nothing answered: a transport failure, not an answer
		_answered = true
		if _has_ground(img):
			return img                                 # else a blank square: this campaign missed the plot
	return null


## One GetMap into `dest`, as an Image; null when neither scheme answered or it is not a JPEG.
static func _get_image(url: String, dest: String) -> Image:
	var schemes: Array = [_scheme_ok] if _scheme_ok != "" else ["https", "http"]
	for scheme in schemes:
		var u: String = str(scheme) + url.trim_prefix("https")
		var r: Dictionary = await Locator.http(u, HTTPClient.METHOD_GET, "", dest)
		if not r.ok:
			continue
		var bytes := FileAccess.get_file_as_bytes(dest)
		var img := Image.new()
		if bytes.is_empty() or img.load_jpg_from_buffer(bytes) != OK:
			continue
		_scheme_ok = scheme
		return img
	return null


## Is there a photograph on this square, or did the WMS answer with white? An uncovered request
## comes back almost uniformly white (measured: mean 255, spread 3, against mean 97 spread 43-58
## for a covered one), so a bright, flat image means the campaign did not fly here.
static func _has_ground(img: Image) -> bool:
	var n := 0
	var sum := 0.0
	var sum2 := 0.0
	var step: int = maxi(1, img.get_width() / 24)
	for y in range(0, img.get_height(), step):
		for x in range(0, img.get_width(), step):
			var v := img.get_pixel(x, y).get_luminance() * 255.0
			sum += v
			sum2 += v * v
			n += 1
	if n == 0:
		return false
	var mean := sum / n
	var spread := sqrt(maxf(0.0, sum2 / n - mean * mean))
	return not (mean > 240.0 and spread < 12.0)


static func _load(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	var img := Image.new()
	if img.load_jpg_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		return null
	return ImageTexture.create_from_image(img)


static func _query(q: Dictionary) -> String:
	var parts: Array = []
	for k in q:
		parts.append("%s=%s" % [k, str(q[k]).uri_encode()])
	return "&".join(parts)
