# The land itself, over thirty years: one small aerial photograph of a plot per campaign, from the
# orthophotos Maa-amet has flown since 1993 (the `ajalooline` WMS the terrain pipeline already
# talks to). A plot that was forest in 1998 and a car park now says something its land value does
# not, so the book shows the plot's own square in each of them.
#
# The newest picture costs nothing: it is a crop of the tile's own ortho.jpg. The older ones are one
# WMS request each, kept in user://cache/plots so a plot is fetched once and never again. A campaign
# that did not fly over this square answers with a blank white square, which is what `_has_ground`
# is for; that is remembered too, so an uncovered plot is not asked about twice.
class_name PlotHistory
extends RefCounted

const WMS := "https://kaart.maaamet.ee/wms/ajalooline"
# The nationwide latest orthophoto, the same service and layer the terrain pipeline asks for the
# tile's own texture (tools/pipeline/fetch_tile.py). Asked here for one plot's square instead of a
# whole square kilometre, so it answers from whatever flight covers that square - in a city that is
# a finer one than the 25 cm nationwide flight the tile texture is made of.
const WMS_CURRENT := "https://kaart.maaamet.ee/wms/fotokaart"
const CURRENT_LAYER := "EESTIFOTO"

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

# The campaigns to show, oldest first. Each names the layers to try in order: the national flights
# are split by purpose (asulad = settlements, aero = the year's main flight, mets = forestry) and
# which of them covers a given square is not knowable in advance, so they are tried until one comes
# back with something on it.
const EPOCHS := [
	{"label": "1993-2000", "layers": ["of1993-2000_10k"]},
	{"label": "2005", "layers": ["of2005", "of2005"]},
	{"label": "2010", "layers": ["of2010aero", "of2010mets"]},
	{"label": "2015", "layers": ["of2015asulad", "of2015aero", "of2015mets"]},
	{"label": "2020", "layers": ["of2020asulad", "of2020aero", "of2020mets"]},
]


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


## The newest picture, cropped out of the tile's own orthophoto - no request, and it is by
## definition the one that matches the world the player is standing in. Null if the tile has none.
## `px` is what the crop is scaled to; the older years are re-requested from the service at the
## large view's size, so this one is asked for the same size or it alone stays a blurry thumbnail.
## The orthophoto is 25 cm to the pixel, so a plot's square usually has the detail to answer.
static func current(square: Rect2, georef: TerrainGeoref, tile_dir: String, px: int = PX) -> Texture2D:
	var path := tile_dir + "/ortho.jpg"
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
	for e in EPOCHS:
		var base := "%s/%s_%s" % [dir, tunnus.replace(":", "_"), e.label]
		# The book refills while pictures are in flight, so a second pass must wait for the first
		# rather than skip the epoch: skipping would show fewer pictures than are already on disk.
		while _busy.has(base):
			await (Engine.get_main_loop() as SceneTree).process_frame
		var tex: Texture2D = _load(base + ".jpg")       # a picture we already have always wins
		if tex == null and not FileAccess.file_exists(base + ".none"):
			_busy[base] = true
			tex = await _fetch_one(e.layers, square, base)
			_busy.erase(base)
		if tex != null:
			out.append({"label": e.label, "texture": tex})
	return out


static func _fetch_one(layers: Array, square: Rect2, base: String) -> Texture2D:
	var img := await _fetch_image(layers, square, base, PX)
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
	if tunnus != "" and not _busy.has(base):
		_busy[base] = true
		var img := await _fetch_image([CURRENT_LAYER], square, base, px, WMS_CURRENT)
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
	for e in EPOCHS:
		if str(e.label) == label:
			epoch = e
			break
	if epoch.is_empty() or _busy.has(base):
		return null
	_busy[base] = true
	var img := await _fetch_image(epoch.layers, square, base, px)
	_busy.erase(base)
	if img == null:
		return null
	DirAccess.rename_absolute(ProjectSettings.globalize_path(base + ".part"),
			ProjectSettings.globalize_path(base + ".jpg"))
	return ImageTexture.create_from_image(img)


## The first of `layers` that answers with a picture that has ground on it, at `px` square. Sets
## `_answered` to whether anything answered at all, so the caller can tell "no coverage here" from
## "the service could not be reached".
static func _fetch_image(layers: Array, square: Rect2, base: String, px: int, wms: String = WMS) -> Image:
	_answered = false
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
