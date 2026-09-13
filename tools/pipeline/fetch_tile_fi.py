#!/usr/bin/env python3
"""Finnish ground for a tile on the game's L-EST97 grid (docs/finland-plan.md, step 1).

Everything comes without a key from the Funet mirror of CSC's Paituli service, which republishes the
National Land Survey's (Maanmittauslaitos, NLS) open data as plain files with range requests; the
NLS's own APIs all want a personal key. Inside Helsinki the city's open data is finer and replaces
the national layers where it reaches:

    heightmap.r32   NLS 2 m ground model (a VRT over 6 x 6 km GeoTIFF sheets, windows cut over HTTP),
                    bilinear to 1 m; in Helsinki the city's 1 m model from 2021 (WCS) where it has data
    canopy.r32      the highest laser return per metre above that ground (NLS 0.5 p laser points, LAZ,
                    3 x 3 km sheets). The old sheets have no building class, so roofs are in it as in
                    Maa-amet's nDSM, and the building footprints mask them out at scatter time
    ortho.jpg       the newest NLS orthophoto (0.5 m, JPEG2000 6 x 6 km sheets, windows over HTTP); in
                    Helsinki the city's newest 5 cm photograph (WMS) laid over it where it covers
    terrain_meta.json

Heights are N2000 (EVRF2007 normal heights like EH2000 and LAS-2000,5). The open laser product is
thin, about 0.5 points a square metre, and old: Helsinki's newest open sheet is from 2008. The dense
5 p scans are sold under their own licence, not open data.

    python3 tools/pipeline/fetch_tile.py --name helsinki_senaatintori --center 552890 6670790
"""
import datetime as dt
import io
import json
import os
import shutil
import sys
import urllib.parse
import urllib.request

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import geo  # noqa: E402
import paths  # noqa: E402

MIRROR = "https://www.nic.funet.fi/index/geodata/"
DEM_VRT = MIRROR + "mml/dem2m/dem2m_direct.vrt"                       # 2 m ground, 6 x 6 km sheets
LASER_INDEX = MIRROR + "mml/laserkeilaus/2008_latest/2008_latest"      # the newest open scan per 3 x 3 km sheet
ORTHO_INDEX = MIRROR + "mml/orto/normal_color_3067/ortho_all"          # every open orthophoto year per 6 x 6 km sheet
HEL = "https://kartta.hel.fi/ws/geoserver/avoindata/"
HEL_DEM = "avoindata__Korkeusmalli_2021_1m"
HEL_ORTHO = "avoindata:Ortoilmakuva_2025_5cm"
HELSINKI = "091"          # the municipality code the city's own layers cover
TM35 = 3067               # ETRS-TM35FIN, the NLS grid
GK25 = 3879               # ETRS-GK25, Helsinki's own grid (its WCS takes subsets only in this)
LEST97 = 3301
NOISE = (7,)              # low noise; birds and clouds (1.8 km over Helsinki) are cut by the canopy's ceiling
CANOPY_MAX = 60.0         # metres above ground: Finland's tallest trees are under 50
VEG_R = 3                 # the square the split-pulse share is counted over: (2r+1) metres a side
VEG_SHARE = 0.3           # the share of split pulses among the high returns that makes it foliage, not a roof
UA = {"User-Agent": "vakuraamat-pipeline/0.1 (open-source game; polite, cached)"}
ATTRIBUTION = "Map data: Maanmittauslaitos (National Land Survey of Finland) {month}, CC BY 4.0"
HEL_ATTRIBUTION = "Helsingin kaupunki, kaupunkimittauspalvelut (CC BY 4.0)"
LICENSE = "CC BY 4.0 (NLS open data licence; Helsinki Region Infoshare)"


def log(msg):
    print(f"[fetch_tile_fi] {msg}", flush=True)


def _download(url, dest, label=None, span=None):
    import fetch_tile   # its download reports progress lines the tile service shows
    return fetch_tile.download(url, dest, label=label, span=span)


def _progress(frac, text):
    import fetch_tile
    fetch_tile.progress(frac, text)


def _get(url, timeout=120):
    return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=timeout).read()


# ------------------------------------------------------------------------------------------ grids
def box_in(bbox, epsg, margin=5.0):
    """An L-EST97 box as the box around it on another grid (TM35 turns against L-EST97 by about a
    degree in the south, so the box grows by a few metres a side)."""
    xmin, ymin, xmax, ymax = bbox
    edge = [(xmin + (xmax - xmin) * t, y) for t in np.linspace(0, 1, 9) for y in (ymin, ymax)]
    edge += [(x, ymin + (ymax - ymin) * t) for t in np.linspace(0, 1, 9) for x in (xmin, xmax)]
    pts = geo.transform_points(edge, LEST97, epsg)
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    return min(xs) - margin, min(ys) - margin, max(xs) + margin, max(ys) + margin


def _warp(data, src_transform, src_epsg, bbox, px, resampling, src_nodata=None, dst_nodata=np.nan, dtype=np.float32):
    """One band onto the tile's L-EST97 grid, px x px, rows north to south."""
    from rasterio.crs import CRS
    from rasterio.transform import from_origin
    from rasterio.warp import reproject
    xmin, ymin, xmax, ymax = bbox
    out = np.full((px, px), dst_nodata, dtype)
    reproject(data, out, src_transform=src_transform, src_crs=CRS.from_epsg(src_epsg), src_nodata=src_nodata,
              dst_transform=from_origin(xmin, ymax, (xmax - xmin) / px, (ymax - ymin) / px), dst_crs=CRS.from_epsg(LEST97),
              dst_nodata=dst_nodata, resampling=resampling)
    return out


def _gdal_env():
    import rasterio
    return rasterio.Env(GDAL_DISABLE_READDIR_ON_OPEN="EMPTY_DIR", GDAL_HTTP_MAX_RETRY="3", GDAL_HTTP_RETRY_DELAY="2",
                        CPL_VSIL_CURL_ALLOWED_EXTENSIONS=".vrt,.tif,.jp2", GDAL_NUM_THREADS="ALL_CPUS")


# ------------------------------------------------------------------------------------------ sheet indexes
def _index(url_stem, name):
    """A mirror's sheet index (a shapefile, cached under data_raw/fi/index): its path on disk."""
    d = paths.raw("fi", "index")
    shp = os.path.join(d, name + ".shp")
    if not os.path.exists(shp):
        for ext in ("shx", "dbf", "prj", "cpg", "shp"):   # the .shp last: its presence means complete
            try:
                _download(f"{url_stem}.{ext}", os.path.join(d, f"{name}.{ext}"))
            except Exception as e:  # noqa: BLE001 - the laser index publishes no .shx; GDAL rebuilds it
                if ext == "shp":
                    raise
                log(f"{name}.{ext}: {e}")
    return shp


def sheets(url_stem, name, box_tm35):
    """[(sheet, year, path under the mirror)] of an index's sheets touching a TM35 box. The labels read
    "L4133D1 (2008)"; the paths are relative to the mirror's geodata folder."""
    import pyogrio
    pyogrio.set_gdal_config_options({"SHAPE_RESTORE_SHX": "YES"})
    out = []
    for p, _g in geo.features(_index(url_stem, name), bbox=box_tm35):
        label = str(p.get("label") or "")
        sheet, _, year = label.partition(" (")
        if p.get("path") and year[:4].isdigit():
            out.append((sheet, int(year[:4]), str(p["path"])))
    return sorted(set(out))


def laser_sheets(box_tm35):
    return sheets(LASER_INDEX, "laser_2008_latest", box_tm35)


def ortho_sheets(box_tm35):
    """{year: [(sheet, path)]} of the colour orthophotos touching a TM35 box, full resolution only
    (the index also lists a few 10 m overview mosaics)."""
    out = {}
    for sheet, year, path in sheets(ORTHO_INDEX, "ortho_all", box_tm35):
        if "/02m/" in path:
            out.setdefault(year, []).append((sheet, path))
    return out


def has_data(x3301, y3301):
    """Whether the NLS has an orthophoto sheet under an L-EST97 point: the adapter's test for "in Finland"
    beside the outline (which is generalised to 300 m and misses the outer skerries)."""
    (x, y), = geo.transform_points([(x3301, y3301)], LEST97, TM35)
    return bool(ortho_sheets((x - 1, y - 1, x + 1, y + 1)))


# ------------------------------------------------------------------------------------------ Helsinki
_municipalities = None


def municipality_at(bbox):
    """The municipality codes an L-EST97 box touches, from Statistics Finland's division (the file
    fetch_outline.py caches), e.g. {"091"} for central Helsinki."""
    global _municipalities
    if _municipalities is None:
        import shapely
        from pyproj import Transformer
        from shapely.ops import transform
        path = os.path.join(paths.raw("fi"), "kunta4500k.json")
        if not os.path.exists(path):
            import fetch_outline
            fetch_outline.finland()
        t = Transformer.from_crs("EPSG:3067", "EPSG:3301", always_xy=True)
        _municipalities = [(str(f["properties"]["kunta"]), transform(t.transform, shapely.geometry.shape(f["geometry"])))
                           for f in json.load(open(path))["features"]]
    from shapely.geometry import box
    b = box(*bbox)
    return {k for k, g in _municipalities if g.intersects(b)}


def in_helsinki(bbox):
    try:
        return HELSINKI in municipality_at(bbox)
    except Exception as e:  # noqa: BLE001 - without the division the national layers are used everywhere
        log(f"municipality division unavailable ({e}); national layers only")
        return False


def helsinki_ground(bbox, size):
    """The city's 1 m ground model (2021) over the tile, NaN where the city has none, or None."""
    import rasterio
    from rasterio.enums import Resampling
    x0, y0, x1, y1 = box_in(bbox, GK25, margin=10.0)
    q = urllib.parse.urlencode({"service": "WCS", "version": "2.0.1", "request": "GetCoverage", "coverageId": HEL_DEM,
                                "format": "image/tiff"}) + f"&subset=E({x0:.0f},{x1:.0f})&subset=N({y0:.0f},{y1:.0f})"
    blob = _get(HEL + "wcs?" + q, timeout=180)
    with rasterio.MemoryFile(blob) as mf, mf.open() as src:
        data = src.read(1).astype(np.float32)
        nodata = src.nodata if src.nodata is not None else -32767.0
        out = _warp(data, src.transform, GK25, bbox, size, Resampling.bilinear, src_nodata=nodata)
    out[out < -100] = np.nan
    return out


def helsinki_ortho(bbox, px):
    """The city's newest photograph over the tile as RGBA (4, px, px); alpha 0 outside the city."""
    from PIL import Image
    from rasterio.enums import Resampling
    from rasterio.transform import from_bounds
    x0, y0, x1, y1 = box_in(bbox, TM35, margin=10.0)
    n = 4096
    q = urllib.parse.urlencode({"service": "WMS", "version": "1.3.0", "request": "GetMap", "layers": HEL_ORTHO, "styles": "",
                                "crs": "EPSG:3067", "bbox": f"{x0:.0f},{y0:.0f},{x1:.0f},{y1:.0f}", "width": n, "height": n,
                                "format": "image/png", "transparent": "true"})
    im = np.asarray(Image.open(io.BytesIO(_get(HEL + "wms?" + q, timeout=300))).convert("RGBA"))
    t = from_bounds(x0, y0, x1, y1, n, n)
    return np.stack([_warp(np.ascontiguousarray(im[:, :, b]), t, TM35, bbox, px, Resampling.cubic, dst_nodata=0, dtype=np.uint8)
                     for b in range(4)])


# ------------------------------------------------------------------------------------------ ground
def national_ground(bbox, size):
    """The NLS 2 m ground model over the tile, bilinear to 1 m; NaN where there is none (the open sea)."""
    import rasterio
    from rasterio.enums import Resampling
    from rasterio.windows import Window, from_bounds
    with _gdal_env(), rasterio.open("/vsicurl/" + DEM_VRT) as src:
        w = from_bounds(*box_in(bbox, TM35, margin=10.0), transform=src.transform).round_offsets().round_lengths()
        w = w.intersection(Window(0, 0, src.width, src.height))
        data = src.read(1, window=w).astype(np.float32)
        return _warp(data, src.window_transform(w), TM35, bbox, size, Resampling.bilinear, src_nodata=src.nodata)


def fetch_ground(bbox, size, out_dir, raw_dir, tile):
    """heightmap.r32 from the national model, the city's where it has one; the canopy from the laser.
    Returns the meta fields."""
    _progress(0.08, "ground model, 2 m (Maanmittauslaitos)")
    heights = national_ground(bbox, size)
    sources = ["NLS 2 m"]
    res = 2
    if in_helsinki(bbox):
        _progress(0.14, "ground model, 1 m (Helsinki 2021)")
        try:
            city = helsinki_ground(bbox, size)
            got = np.isfinite(city)
            heights = np.where(got, city, heights)
            sources.append(f"Helsinki 1 m 2021 on {got.mean():.0%}")
            res = 1 if got.mean() > 0.9 else 2
        except Exception as e:  # noqa: BLE001 - the national model stands on its own
            log(f"Helsinki's ground model unavailable ({e}); the national one only")
    sea = ~np.isfinite(heights)
    if sea.any():   # outside the model is the open sea, at N2000's zero
        heights[sea] = 0.0
        log(f"no ground model on {sea.mean():.0%} of the tile (the sea): set to 0 m")
    import fetch_tile_lv   # the seam blending is the same problem in every country
    near = fetch_tile_lv.adjacent_tiles(bbox, size, out_dir)
    if near:
        heights = fetch_tile_lv.blend_edges(heights, near)
        log(f"ground bent over {fetch_tile_lv.BLEND_M} m to meet the tiles already built on the {', '.join(s for s, _ in near)}")
    geo.write_r32(heights, os.path.join(out_dir, "heightmap.r32"))
    laser = fetch_canopy(bbox, size, heights, out_dir, raw_dir, tile)
    zmin, zmax = float(heights.min()), float(heights.max())
    log(f"ground {zmin:.2f}..{zmax:.2f} m ({', '.join(sources)})")
    return {"z_min": round(zmin, 3), "z_max": round(zmax, 3), "dtm_res_m": res, "ground_sources": sources, **laser}


def surface_path(raw_dir, tile):
    """The highest return above the ground per metre, kept for the buildings step (not a pack file)."""
    return os.path.join(raw_dir, "fi", f"{tile}_surface.r32")


def _fill_gaps(top):
    """Cells with no return (0.5 points a square metre leaves about half of them empty) take the highest
    of their eight neighbours, so a crown is solid instead of a sieve."""
    out = top.copy()
    empty = ~np.isfinite(top)
    pad = np.pad(np.where(np.isfinite(top), top, -np.inf), 1, constant_values=-np.inf)
    h, w = top.shape
    best = np.full(top.shape, -np.inf, np.float32)
    for dy in (0, 1, 2):
        for dx in (0, 1, 2):
            if dy != 1 or dx != 1:
                best = np.maximum(best, pad[dy:dy + h, dx:dx + w])
    out[empty] = best[empty]
    return np.where(np.isfinite(out), out, np.nan)


def fetch_canopy(bbox, size, heights, out_dir, raw_dir, tile):
    """canopy.r32 from the laser sheets under the tile. Returns {"canopy", "laser"} for the meta."""
    try:
        import laspy
    except ImportError:
        log("laspy is not installed (tools/service/requirements.txt): no canopy")
        return {"canopy": None, "laser": None}
    from pyproj import Transformer
    box = box_in(bbox, TM35, margin=0.0)
    got = laser_sheets(box)
    if not got:
        log("no NLS laser sheet under the tile: no canopy")
        return {"canopy": None, "laser": None}
    d = os.path.join(raw_dir or paths.raw_root(), "fi", "laser")
    os.makedirs(d, exist_ok=True)
    to_lest = Transformer.from_crs(f"EPSG:{TM35}", f"EPSG:{LEST97}", always_xy=True)
    xmin, ymin, xmax, ymax = bbox
    n = size * size
    top = np.full(n, -np.inf, np.float32)
    hits = np.zeros(n, np.int32)
    high = np.zeros(n, np.int32)     # returns more than 2 m above the ground
    split = np.zeros(n, np.int32)    # of those, the ones from a pulse that came back more than once
    ground = heights.ravel()
    for i, (sheet, year, path) in enumerate(got):
        f0, f1 = 0.2 + 0.3 * i / len(got), 0.2 + 0.3 * (i + 1) / len(got)
        dest = os.path.join(d, sheet + ".laz")
        text = f"laser points, sheet {sheet} ({year}, {i + 1}/{len(got)})"
        _progress(f0, text + (", cached" if os.path.exists(dest) else ""))
        _download(MIRROR + path, dest, label=text, span=(f0, f1))
        kept = 0
        with laspy.open(dest) as f:
            for pts in f.chunk_iterator(2_000_000):
                cls = np.asarray(pts.classification)
                x, y = to_lest.transform(np.asarray(pts.x), np.asarray(pts.y))   # the old sheets carry no CRS: TM35 by the index
                x, y, z = np.asarray(x), np.asarray(y), np.asarray(pts.z, np.float32)
                inside = (x >= xmin) & (x < xmax) & (y > ymin) & (y <= ymax) & ~np.isin(cls, NOISE)
                cell = (np.clip((ymax - y[inside]).astype(np.int64), 0, size - 1) * size
                        + np.clip((x[inside] - xmin).astype(np.int64), 0, size - 1))
                zz = z[inside]
                np.maximum.at(top, cell, zz)
                hits += np.bincount(cell, minlength=n).astype(np.int32)
                up = zz - ground[cell] > 2.0
                many = np.asarray(pts.number_of_returns)[inside] > 1
                high += np.bincount(cell[up], minlength=n).astype(np.int32)
                split += np.bincount(cell[up & many], minlength=n).astype(np.int32)
                kept += int(inside.sum())
        log(f"{sheet} ({year}): {kept:,} points on the tile")
    top = np.where(np.isfinite(top), top, np.nan).reshape(size, size)
    above = _fill_gaps(_fill_gaps(top)) - heights   # twice: at half a point a square metre one pass left crowns a sieve
    surface = np.where((above > 0.3) & (above < CANOPY_MAX), above, 0.0).astype(np.float32)
    os.makedirs(os.path.dirname(surface_path(raw_dir or paths.raw_root(), tile)), exist_ok=True)
    geo.write_r32(surface, surface_path(raw_dir or paths.raw_root(), tile))
    # Trees from roofs: the old sheets have no building class, but a pulse through foliage comes back
    # more than once and off a roof once. Counted over a 7 m square, since a metre holds half a point.
    import fetch_tile_lv
    share = (fetch_tile_lv._box_count(split.reshape(size, size), VEG_R)
             / np.maximum(fetch_tile_lv._box_count(high.reshape(size, size), VEG_R), 1))
    canopy = np.where(share >= VEG_SHARE, surface, 0.0).astype(np.float32)
    geo.write_r32(canopy, os.path.join(out_dir, "canopy.r32"))
    covered = float((hits > 0).mean())
    years = sorted({y for _s, y, _p in got})
    log(f"canopy up to {canopy.max():.1f} m on {(canopy > 2).mean():.0%} of the tile (surface above 2 m on {(surface > 2).mean():.0%}); "
        f"returns on {covered:.0%} of the metres ({float(hits.sum()) / n:.2f} a square metre)")
    return {
        "canopy": {"file": "canopy.r32",
                   "source": f"NLS laser points {'/'.join(map(str, years))}, highest return above the ground where at least "
                             f"{VEG_SHARE:.0%} of the high returns nearby came from split pulses (foliage), gaps filled from the neighbours",
                   "max_height": round(float(canopy.max()), 2),
                   "format": "float32 little-endian, row-major, row 0 = north; metres above ground; 0 = nothing"},
        "laser": {"sheets": [s for s, _y, _p in got], "years": years, "coverage": round(covered, 3),
                  "points_per_m2": round(float(hits.sum()) / n, 2), "urls": [MIRROR + p for _s, _y, p in got]},
    }


# ------------------------------------------------------------------------------------------ orthophoto
def _cut(bbox, entries, px, what):
    """NLS orthophoto sheets' windows under the box, warped onto the L-EST97 grid: (3, px, px), 0 where
    no sheet reaches. The sheets are JPEG2000 with 1024-px blocks and overviews, read side by side."""
    from concurrent.futures import ThreadPoolExecutor
    import rasterio
    from rasterio.enums import Resampling
    from rasterio.windows import Window, from_bounds
    box = box_in(bbox, TM35, margin=10.0)

    def one(entry):
        sheet, path = entry
        with _gdal_env(), rasterio.open("/vsicurl/" + MIRROR + path) as src:
            w = from_bounds(*box, transform=src.transform).round_offsets().round_lengths().intersection(Window(0, 0, src.width, src.height))
            data = src.read([1, 2, 3], window=w)
            t = src.window_transform(w)
        log(f"{what} {sheet}: window {w.width}x{w.height} px")
        return np.stack([_warp(data[b], t, TM35, bbox, px, Resampling.cubic, dst_nodata=0, dtype=np.uint8) for b in range(3)])

    dst = np.zeros((3, px, px), np.uint8)
    with ThreadPoolExecutor(max_workers=4) as pool:
        for part in pool.map(one, entries):
            got = part.any(axis=0)
            dst[:, got] = part[:, got]
    return dst


def _save_jpg(dst, out_jpg, quality=90):
    from PIL import Image
    if os.path.exists(out_jpg):
        os.remove(out_jpg)
    Image.fromarray(np.moveaxis(dst, 0, -1)).save(out_jpg, quality=quality)


def fetch_ortho(bbox, out_jpg, px=4096):
    """The newest NLS photograph of each sheet under the tile, and in Helsinki the city's over it."""
    years = ortho_sheets(box_in(bbox, TM35, margin=10.0))
    if not years:
        sys.exit("no NLS orthophoto sheet covers this tile")
    newest = {}
    for year in sorted(years):
        for sheet, path in years[year]:
            newest[sheet] = (year, path)
    dst = _cut(bbox, [(s, p) for s, (_y, p) in sorted(newest.items())], px, "orthophoto")
    meta = {"ortho_sheets": sorted(newest), "ortho_years": sorted({y for y, _p in newest.values()}),
            "ortho_urls": [MIRROR + p for _y, p in newest.values()], "ortho_source": "NLS orthophoto, 0.5 m"}
    if in_helsinki(bbox):
        try:
            city = helsinki_ortho(bbox, px)
            lay = city[3] > 127
            dst[:, lay] = city[:3, lay]
            meta.update({"ortho_source": f"Helsinki {HEL_ORTHO.split('_', 1)[1]} on {lay.mean():.0%}, NLS 0.5 m elsewhere",
                         "ortho_wms": HEL + "wms", "ortho_layer": HEL_ORTHO})
            log(f"Helsinki's photograph on {lay.mean():.0%} of the tile")
        except Exception as e:  # noqa: BLE001 - the national photograph stands on its own
            log(f"Helsinki's photograph unavailable ({e}); the national one only")
    _save_jpg(dst, out_jpg)
    return meta


# ------------------------------------------------------------------------------------------ the older photographs
# The plot page's "over the years" strip. NLS keeps every open flight since the mid-2000s on the mirror
# (Helsinki 2009, 2014, 2020; Porvoo 2009, 2013, 2018, 2022); Helsinki's own WMS goes back to 1932,
# and inside the city those replace the national years.
HISTORY_MAX = 6
HEL_HISTORY = ["1932", "1943", "1950", "1964", "1976", "1988", "2001", "2009_25cm", "2015_20cm"]
HISTORY_PX = 2048


def _helsinki_epoch(bbox, layer, px):
    from PIL import Image
    from rasterio.enums import Resampling
    from rasterio.transform import from_bounds
    x0, y0, x1, y1 = box_in(bbox, TM35, margin=10.0)
    q = urllib.parse.urlencode({"service": "WMS", "version": "1.3.0", "request": "GetMap", "layers": f"avoindata:Ortoilmakuva_{layer}",
                                "styles": "", "crs": "EPSG:3067", "bbox": f"{x0:.0f},{y0:.0f},{x1:.0f},{y1:.0f}",
                                "width": px, "height": px, "format": "image/png", "transparent": "true"})
    im = np.asarray(Image.open(io.BytesIO(_get(HEL + "wms?" + q, timeout=300))).convert("RGBA"))
    t = from_bounds(x0, y0, x1, y1, px, px)
    rgba = np.stack([_warp(np.ascontiguousarray(im[:, :, b]), t, TM35, bbox, px, Resampling.cubic, dst_nodata=0, dtype=np.uint8)
                     for b in range(4)])
    return rgba[:3] * (rgba[3] > 127)


def add_history(tile_dir):
    """Cut the older photographs over a Finnish tile into ortho_<year>.jpg beside its ortho.jpg and list
    them in terrain_meta.json as "history" (the refine pass, after the place is playable)."""
    from concurrent.futures import ThreadPoolExecutor
    meta_path = os.path.join(tile_dir, "terrain_meta.json")
    meta = json.load(open(meta_path))
    bbox = (meta["xmin"], meta["ymin"], meta["xmax"], meta["ymax"])
    newest = set(meta.get("source", {}).get("ortho", {}).get("ortho_years", []))
    jobs = []
    if in_helsinki(bbox):
        # spread over the whole range, the oldest and the newest included
        n = min(HISTORY_MAX, len(HEL_HISTORY))
        picks = sorted({round(i * (len(HEL_HISTORY) - 1) / max(1, n - 1)) for i in range(n)})
        for layer in [HEL_HISTORY[i] for i in picks]:
            jobs.append((layer.split("_")[0], lambda layer=layer: _helsinki_epoch(bbox, layer, HISTORY_PX), "Helsinki"))
    else:
        years = ortho_sheets(box_in(bbox, TM35, margin=10.0))
        for year in sorted(y for y in years if y not in newest)[-HISTORY_MAX:]:
            jobs.append((str(year), lambda year=year: _cut(bbox, years[year], HISTORY_PX, f"orthophoto {year}"), "NLS"))

    def one(job):
        label, cut, who = job
        try:
            dst = cut()
        except Exception as e:  # noqa: BLE001 - one missing year leaves the others
            log(f"{label}: {e}")
            return None
        if dst.any(axis=0).mean() < 0.05:
            return None
        name = f"ortho_{label}.jpg"
        _save_jpg(dst, os.path.join(tile_dir, name))
        return {"label": label, "texture": name, "source": who}

    with ThreadPoolExecutor(max_workers=4) as pool:
        got = [h for h in pool.map(one, jobs) if h]
    meta["history"] = got
    meta.setdefault("source", {})["history"] = [HEL + "wms" if in_helsinki(bbox) else MIRROR + "mml/orto/normal_color_3067/"]
    with open(meta_path, "w") as f:
        json.dump(meta, f, indent=2, ensure_ascii=False)
    log(f"history: {', '.join(h['label'] for h in got) or 'no older photograph covers the tile'}")
    return got


# ------------------------------------------------------------------------------------------ the tile
def build_tile(a, raw_dir, out_dir, bbox):
    """What fetch_tile.main does for Estonia, for a Finnish tile: the ground, the canopy, the
    orthophoto and terrain_meta.json. `a` is fetch_tile's parsed arguments."""
    xmin, ymin, xmax, ymax = bbox
    size = int(xmax - xmin)
    meta_path = os.path.join(out_dir, "terrain_meta.json")
    ground = fetch_ground(bbox, size, out_dir, raw_dir, a.name)
    if a.only_dem:
        meta = json.load(open(meta_path)) if os.path.exists(meta_path) else {}
        meta.update({k: ground[k] for k in ("z_min", "z_max", "dtm_res_m", "canopy")})
        meta.setdefault("source", {}).update({"laser": ground["laser"], "ground": ground["ground_sources"]})
        json.dump(meta, open(meta_path, "w"), indent=2, ensure_ascii=False)
        return
    px = min(a.texture_px, 4096)
    _progress(0.6, "orthophoto (Maanmittauslaitos, Helsinki)")
    ortho = fetch_ortho(bbox, os.path.join(out_dir, "ortho.jpg"), px)
    if a.no_canopy and ground["canopy"]:
        os.remove(os.path.join(out_dir, "canopy.r32"))
        ground["canopy"] = None
    today = dt.date.today()
    city = "Helsinki" in ortho["ortho_source"] or any("Helsinki" in s for s in ground["ground_sources"])
    meta = {
        "name": a.name,
        "country": "fi",
        "crs": "EPSG:3301",
        "sheet": (ortho["ortho_sheets"] or ["?"])[0],
        "xmin": xmin, "ymin": ymin, "xmax": xmax, "ymax": ymax,
        "size_m": size,
        "size_px": size,
        "resolution_m": 1.0,
        "dtm_res_m": ground["dtm_res_m"],
        "heightmap": "heightmap.r32",
        "heightmap_format": "float32 little-endian, row-major, row 0 = north edge (ymax), metres N2000 (EVRF2007 like EH2000)",
        "z_min": ground["z_min"], "z_max": ground["z_max"],
        "z_scale": a.z_scale,
        "texture": "ortho.jpg",
        "texture_px": px,
        "canopy": ground["canopy"],
        "era_maps": {},
        "world_mapping": "Godot x = easting - xmin; Godot z = ymax - northing (north is -Z); y = height * z_scale; "
                         "L-EST97 grid, the Finnish sources reprojected from ETRS-TM35FIN (EPSG:3067) and ETRS-GK25 (EPSG:3879)",
        "source": {"ground": ground["ground_sources"], "dem": DEM_VRT, "laser": ground["laser"], "ortho": ortho},
        "fetched": today.isoformat(),
        "attribution": ATTRIBUTION.format(month=today.strftime("%m/%Y")) + ("; " + HEL_ATTRIBUTION if city else ""),
        "license": LICENSE,
    }
    with open(meta_path, "w") as f:
        json.dump(meta, f, indent=2, ensure_ascii=False)
    shutil.copyfile(meta_path, os.path.join(raw_dir, f"{a.name}_terrain_meta.json"))
    log(f"wrote {out_dir}/{{heightmap.r32, canopy.r32, ortho.jpg, terrain_meta.json}}")
