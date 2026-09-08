# Reads a window out of a float32 GeoTIFF, in engine, with no pipeline behind it.
#
# Enough of TIFF for the national elevation data and nothing more: one sample per pixel, 32-bit
# IEEE float, little-endian, no predictor, tiled or stripped, stored raw or deflated. That is what
# Maa-amet's DTM and nDSM sheets are (`gdalinfo`: SampleFormat 3, BitsPerSample 32, Predictor 1,
# Compression 8 tiled 512x512 for the DTM, Compression 1 stripped for the nDSM), and they arrive
# already in EPSG:3301, the coordinates the game itself uses, so a window is arithmetic on the
# geotransform rather than a reprojection.
#
# A tile only ever needs its own square kilometre: of a 5x5 km 1 m sheet (5000x5000 px, 100 tiles,
# ~75 MB) that is nine tiles. Only those are read and inflated.
#
#     var w := GeoTiff.read_window("res://...54754_dtm_1m.tif", Rect2(657088, 6476638, 1024, 1024))
#     w.data[y * w.width + x]      # metres, row 0 = the north edge; w.nodata where the sheet has none
class_name GeoTiff
extends RefCounted

# The tags this reader looks at; everything else in the file is skipped.
const T_WIDTH := 256
const T_HEIGHT := 257
const T_BITS := 258
const T_COMPRESSION := 259
const T_SAMPLES := 277
const T_STRIP_OFFSETS := 273
const T_ROWS_PER_STRIP := 278
const T_STRIP_COUNTS := 279
const T_PREDICTOR := 317
const T_TILE_WIDTH := 322
const T_TILE_HEIGHT := 323
const T_TILE_OFFSETS := 324
const T_TILE_COUNTS := 325
const T_SAMPLE_FORMAT := 339
const T_PIXEL_SCALE := 33550    # GeoTIFF: (x, y, z) metres per pixel
const T_TIEPOINT := 33922       # GeoTIFF: raster (i, j, k) -> world (x, y, z)
const T_NODATA := 42113         # GDAL: the no-data value, as text

const COMPRESSION_NONE := 1
const COMPRESSION_DEFLATE := 8   # a zlib stream; Godot's COMPRESSION_DEFLATE takes it whole

const TYPE_SIZE := {1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 11: 4, 12: 8}


## What the file says about itself: size, layout, geotransform and no-data value. Empty on anything
## this reader does not handle, having said why.
static func read_header(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("GeoTiff: cannot open %s" % path)
		return {}
	if f.get_length() < 8:
		push_error("GeoTiff: %s is too short to be a TIFF" % path)
		return {}
	var order := f.get_buffer(2).get_string_from_ascii()
	if order != "II":
		# Maa-amet ships little-endian; a big-endian sheet would need every field byte-swapped.
		push_error("GeoTiff: %s is %s (big-endian); this reader only handles little-endian TIFF" % [path, order])
		return {}
	if f.get_16() != 42:
		push_error("GeoTiff: %s has no TIFF magic" % path)
		return {}
	var tags := _read_ifd(f, f.get_32())
	var h := {
		"path": path,
		"width": int(_first(tags, T_WIDTH, 0)),
		"height": int(_first(tags, T_HEIGHT, 0)),
		"bits": int(_first(tags, T_BITS, 0)),
		"samples": int(_first(tags, T_SAMPLES, 1)),
		"sample_format": int(_first(tags, T_SAMPLE_FORMAT, 1)),
		"compression": int(_first(tags, T_COMPRESSION, COMPRESSION_NONE)),
		"predictor": int(_first(tags, T_PREDICTOR, 1)),
		"nodata": float(str(tags.get(T_NODATA, "nan"))) if tags.has(T_NODATA) else NAN,
	}
	if tags.has(T_TILE_OFFSETS):
		h["tiled"] = true
		h["block_w"] = int(_first(tags, T_TILE_WIDTH, 0))
		h["block_h"] = int(_first(tags, T_TILE_HEIGHT, 0))
		h["offsets"] = tags[T_TILE_OFFSETS]
		h["counts"] = tags[T_TILE_COUNTS]
	else:
		h["tiled"] = false
		h["block_w"] = h.width
		h["block_h"] = int(_first(tags, T_ROWS_PER_STRIP, h.height))
		h["offsets"] = tags.get(T_STRIP_OFFSETS, PackedInt64Array())
		h["counts"] = tags.get(T_STRIP_COUNTS, PackedInt64Array())
	var scale: Array = tags.get(T_PIXEL_SCALE, [])
	var tie: Array = tags.get(T_TIEPOINT, [])
	if scale.size() >= 2 and tie.size() >= 6:
		# world x = tie[3] + (px - tie[0]) * sx,  world y = tie[4] - (py - tie[1]) * sy
		h["origin_x"] = float(tie[3]) - float(tie[0]) * float(scale[0])
		h["origin_y"] = float(tie[4]) + float(tie[1]) * float(scale[1])
		h["res_x"] = float(scale[0])
		h["res_y"] = float(scale[1])
	f.close()
	if not _supported(h):
		return {}
	return h


static func _supported(h: Dictionary) -> bool:
	if h.bits != 32 or h.sample_format != 3 or h.samples != 1:
		push_error("GeoTiff: %s is %d-bit format %d with %d sample(s); only single-band 32-bit float is handled"
				% [h.path, h.bits, h.sample_format, h.samples])
		return false
	if h.predictor != 1:
		push_error("GeoTiff: %s uses predictor %d; only unpredicted data is handled" % [h.path, h.predictor])
		return false
	if not (h.compression in [COMPRESSION_NONE, COMPRESSION_DEFLATE]):
		push_error("GeoTiff: %s uses compression %d; only none (1) and deflate (8) are handled" % [h.path, h.compression])
		return false
	if h.offsets.is_empty() or h.offsets.size() != h.counts.size():
		push_error("GeoTiff: %s has no usable block table" % h.path)
		return false
	if not h.has("origin_x"):
		push_error("GeoTiff: %s carries no geotransform (ModelPixelScale / ModelTiepoint)" % h.path)
		return false
	return true


## The heights over `bounds` (a world rectangle: position = its south-west corner, in the sheet's
## own coordinates) on the sheet's own grid. Returns {data: PackedFloat32Array, width, height,
## nodata, res}, row 0 the north edge, or {} when the rectangle does not meet the sheet.
static func read_window(path: String, bounds: Rect2) -> Dictionary:
	var h := read_header(path)
	if h.is_empty():
		return {}
	return read_window_with(h, bounds)


## The same, with a header already read (mosaicking several sheets reads each header once).
static func read_window_with(h: Dictionary, bounds: Rect2) -> Dictionary:
	var px0 := int(round((bounds.position.x - h.origin_x) / h.res_x))
	var py0 := int(round((h.origin_y - (bounds.position.y + bounds.size.y)) / h.res_y))   # north edge
	var w := int(round(bounds.size.x / h.res_x))
	var ht := int(round(bounds.size.y / h.res_y))
	if px0 + w <= 0 or py0 + ht <= 0 or px0 >= h.width or py0 >= h.height:
		return {}
	var f := FileAccess.open(h.path, FileAccess.READ)
	if f == null:
		push_error("GeoTiff: cannot open %s" % h.path)
		return {}
	var nodata: float = h.nodata
	var out := PackedFloat32Array()
	out.resize(w * ht)
	out.fill(nodata)
	var blocks_across := int(ceil(float(h.width) / float(h.block_w)))
	var cache: Dictionary = {}      # block index -> PackedFloat32Array, one band of blocks at a time
	var cached_row := -1
	for y in ht:
		var sy: int = py0 + y
		if sy < 0 or sy >= h.height:
			continue
		var brow: int = sy / int(h.block_h)
		if brow != cached_row:
			cache.clear()
			cached_row = brow
		var row := PackedFloat32Array()
		var x := 0
		while x < w:
			var sx: int = px0 + x
			if sx < 0 or sx >= h.width:
				row.append(nodata)
				x += 1
				continue
			var bcol: int = sx / int(h.block_w)
			var bi: int = (brow * blocks_across + bcol) if h.tiled else brow
			var block: PackedFloat32Array = cache.get(bi, PackedFloat32Array())
			if block.is_empty():
				block = _block(f, h, bi)
				cache[bi] = block
			# how much of this block's row is still wanted
			var in_x: int = sx - bcol * int(h.block_w)
			var take: int = mini(h.block_w - in_x, w - x)
			var stride: int = h.block_w
			var start: int = (sy - brow * h.block_h) * stride + in_x
			if block.size() < start + take:
				row.append_array(_filled(take, nodata))   # a short or unreadable block
			else:
				row.append_array(block.slice(start, start + take))
			x += take
		for i in row.size():
			out[y * w + i] = row[i]
	f.close()
	return {"data": out, "width": w, "height": ht, "nodata": nodata, "res": h.res_x}


## One tile or strip, inflated, as floats. Empty when it cannot be read; the caller fills no-data.
static func _block(f: FileAccess, h: Dictionary, index: int) -> PackedFloat32Array:
	if index < 0 or index >= h.offsets.size():
		return PackedFloat32Array()
	f.seek(int(h.offsets[index]))
	var raw := f.get_buffer(int(h.counts[index]))
	if h.compression == COMPRESSION_DEFLATE:
		# TIFF compression 8 is a zlib stream, header and all: Godot's DEFLATE mode takes it whole.
		var rows: int = int(h.block_h) if h.tiled else mini(int(h.block_h), int(h.height) - index * int(h.block_h))
		raw = raw.decompress(int(h.block_w) * rows * 4, FileAccess.COMPRESSION_DEFLATE)
		if raw.is_empty():
			push_warning("GeoTiff: block %d of %s did not inflate" % [index, h.path])
			return PackedFloat32Array()
	return raw.to_float32_array()


static func _filled(n: int, v: float) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(n)
	a.fill(v)
	return a


## The IFD as {tag: value}: a single number for one-element fields, an Array for several, a String
## for ASCII. Offsets beyond four bytes are followed.
static func _read_ifd(f: FileAccess, offset: int) -> Dictionary:
	var tags: Dictionary = {}
	f.seek(offset)
	var count := f.get_16()
	for i in count:
		var tag := f.get_16()
		var type := f.get_16()
		var n := f.get_32()
		var inline := f.get_buffer(4)
		var next_entry := f.get_position()
		var size: int = int(TYPE_SIZE.get(type, 0)) * n
		if size == 0:
			continue
		var data := inline
		if size > 4:
			f.seek(inline.decode_u32(0))
			data = f.get_buffer(size)
		tags[tag] = _decode(data, type, n)
		f.seek(next_entry)
	return tags


static func _decode(data: PackedByteArray, type: int, n: int) -> Variant:
	match type:
		2:
			return data.get_string_from_ascii()
		3:
			var a := PackedInt64Array()
			for i in n:
				a.append(data.decode_u16(i * 2))
			return a
		4:
			var a := PackedInt64Array()
			for i in n:
				a.append(data.decode_u32(i * 4))
			return a
		12:
			var a: Array = []
			for i in n:
				a.append(data.decode_double(i * 8))
			return a
		11:
			var a: Array = []
			for i in n:
				a.append(data.decode_float(i * 4))
			return a
	return null


static func _first(tags: Dictionary, tag: int, fallback: float) -> float:
	if not tags.has(tag):
		return fallback
	var v = tags[tag]
	if v is PackedInt64Array or v is Array:
		return float(v[0]) if v.size() > 0 else fallback
	return float(v)
