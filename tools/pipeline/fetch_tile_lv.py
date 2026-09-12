#!/usr/bin/env python3
"""Latvian ground for a tile on the game's L-EST97 grid (docs/latvia-plan.md, step 1).

LĢIA publishes no fine ground model, only the classified laser points (LAS 1.2, 1 x 1 km sheets in
LKS-92, EPSG:3059). This module downloads the sheets under a tile, moves the points onto the
L-EST97 grid and writes the files the Estonian fetch writes:

    heightmap.r32   the ground and the water surface (classes 2 and 14) averaged per metre, holes under buildings filled
    canopy.r32      the highest vegetation return per metre above that ground, 0 = nothing. Only the
                    vegetation classes: Maa-amet's nDSM mixes in the roofs, which the building register
                    masks out later; here the points are classified, so a roof never becomes a tree
    ortho.jpg       the 6th-cycle orthophoto (2016-18, 25 cm), windows read over HTTP and warped
    terrain_meta.json

Heights stay as the points carry them (LAS-2000,5). Like EH2000 it realises EVRF2007 normal heights,
so the two agree to a few centimetres at the border.

Sheet names follow LĢIA's nomenclature, checked against the headers of randomly chosen files:
R C q1 q2 - r c - r c, where R, C are the 100 km row and column (x = 200 000 + C * 100 000,
y = (R - 1) * 100 000), q1 and q2 the 50 km and 25 km quarters (1 SW, 2 SE, 3 NW, 4 NE), then the
5 km and 1 km row and column counted from the south-west, 1-based. Orthophoto sheets are 2.5 km:
the 5 km sheet's name and _q for its quarter.

    python3 tools/pipeline/fetch_tile.py --name riga_vecpilseta --center 506700 6311800
"""
import datetime as dt
import json
import os
import shutil
import sys
import urllib.request

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import geo  # noqa: E402
import paths  # noqa: E402

BUCKET = "https://s3.storage.pub.lvdc.gov.lv/lgia-opendata/"
LAS_INDEX = BUCKET + "las/LGIA_OpenData_las_saites.txt"
ORTHO_INDEX = BUCKET + "ortofoto_rgb_v6/LGIA_OpenData_Ortofoto_rgb_v6_saites.txt"
LKS92 = 3059
LEST97 = 3301
# LĢIA's own classes, read from where the points lie in Rīga (the agency publishes no list): 2 ground,
# 3-5 vegetation, 6 buildings, 7 noise, 9 bridge decks, 11 piers and moored boats, 14 the water
# surface. ASPRS would put water in 9; here 9 is 10 m above the river.
GROUND = (2, 14)         # ground, water surface
VEGETATION = (3, 4, 5)   # low, medium, high vegetation
BUILDING = 6
WATER = 14
NOISE = (7, 18)          # low and high noise
ATTRIBUTION = "Map data: Latvijas Ģeotelpiskās informācijas aģentūra (LĢIA), {year}, CC BY 4.0"
LICENSE = "CC BY 4.0 (LĢIA open data licence)"
ORTHO_SHEET_M = 2500.0


def log(msg):
    print(f"[fetch_tile_lv] {msg}", flush=True)


# ------------------------------------------------------------------------------------------ sheets
def _parts(x, y):
    R, C = int(y // 100000) + 1, int((x - 200000) // 100000)
    dx, dy = (x - 200000) % 100000, y % 100000
    q1 = 1 + (dx >= 50000) + 2 * (dy >= 50000)
    dx, dy = dx % 50000, dy % 50000
    q2 = 1 + (dx >= 25000) + 2 * (dy >= 25000)
    dx, dy = dx % 25000, dy % 25000
    r5, c5 = int(dy // 5000) + 1, int(dx // 5000) + 1
    return f"{R}{C}{q1}{q2}-{r5}{c5}", dx % 5000, dy % 5000


def las_sheet(x, y):
    """The 1 km laser sheet holding an LKS-92 point, e.g. 4311-32-32."""
    base, dx, dy = _parts(x, y)
    return f"{base}-{int(dy // 1000) + 1}{int(dx // 1000) + 1}"


def ortho_sheet(x, y):
    """The 2.5 km orthophoto sheet holding an LKS-92 point, e.g. 4311-32_3."""
    base, dx, dy = _parts(x, y)
    return f"{base}_{1 + (dx >= 2500) + 2 * (dy >= 2500)}"


def _index(url, name):
    """{sheet name: url} from one of LĢIA's link lists (downloaded once into the cache)."""
    path = os.path.join(paths.raw("lv"), name)
    if not os.path.exists(path):
        _download(url, path)
    out = {}
    for line in open(path, encoding="utf-8", errors="ignore"):
        line = line.strip()
        if line.startswith("http"):
            stem, ext = os.path.splitext(line.rsplit("/", 1)[1])
            out.setdefault(stem, {})[ext.lower()] = line
    return out


def las_index():
    return {k: v[".las"] for k, v in _index(LAS_INDEX, "las_links.txt").items() if ".las" in v}


def ortho_index():
    return {k: v for k, v in _index(ORTHO_INDEX, "ortho_v6_links.txt").items() if ".tif" in v and ".tfw" in v}


def has_laser_sheet(x3301, y3301):
    """Whether LĢIA has a laser sheet under an L-EST97 point: the adapter's test for "in Latvia"."""
    (x, y), = geo.transform_points([(x3301, y3301)], LEST97, LKS92)
    return las_sheet(x, y) in las_index()


def lks_bbox(bbox, margin=5.0):
    """An L-EST97 box as the LKS-92 box around it. The grids turn against each other by at most 0.1
    degree across Latvia (+0.06 at Liepāja, -0.09 at Zilupe; scale 0.9988-0.9997), so with no margin
    the box is within 2 m of the tile's own square."""
    xmin, ymin, xmax, ymax = bbox
    edge = [(xmin + (xmax - xmin) * t, y) for t in np.linspace(0, 1, 9) for y in (ymin, ymax)]
    edge += [(x, ymin + (ymax - ymin) * t) for t in np.linspace(0, 1, 9) for x in (xmin, xmax)]
    pts = geo.transform_points(edge, LEST97, LKS92)
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    return min(xs) - margin, min(ys) - margin, max(xs) + margin, max(ys) + margin


def _sheets_over(box, step, namer):
    xmin, ymin, xmax, ymax = box
    xs = list(np.arange(xmin, xmax, step)) + [xmax]
    ys = list(np.arange(ymin, ymax, step)) + [ymax]
    return sorted({namer(x, y) for x in xs for y in ys})


# ------------------------------------------------------------------------------------------ which sheets
# A laser sheet is a 1 km square and 170-300 MB. A 1024 m tile anywhere touches at least four, but
# most of them only by a strip: a world centred on one sheet (place_center) overhangs it by 12 m a
# side, and a sheet whose share of the tile is that thin is not worth its download - the strip is
# filled from the ground beside it. A new world then downloads one sheet instead of four; its first
# ring of streamed neighbours (36 m onto the next sheet) one or two. Downloading them side by side
# was measured and does not help: 5.4 MB/s on one connection, 5.5 MB/s in total on four.
SKIP_M = 40.0   # a sheet whose share of the tile is narrower than this is not downloaded


def select_sheets(bbox, index, skip_m=SKIP_M):
    """The laser sheets an L-EST97 tile needs: (keep, skip, missing), sheet names. The tile's square on
    the LKS-92 grid is cut by the 1 km sheet grid; a published sheet whose share is narrower than
    `skip_m` on either axis is skipped, unless no wide one is left to fill it from (a tile on the
    coast), when the narrow ones are kept. Unpublished sheets are `missing`: the sea, the border."""
    x0, y0, x1, y1 = lks_bbox(bbox, margin=0.0)
    keep, skip, missing = [], [], []
    for i in range(int(x0 // 1000), int(x1 // 1000) + 1):
        for j in range(int(y0 // 1000), int(y1 // 1000) + 1):
            w = min(x1, (i + 1) * 1000.0) - max(x0, i * 1000.0)
            h = min(y1, (j + 1) * 1000.0) - max(y0, j * 1000.0)
            if w <= 0 or h <= 0:
                continue
            name = las_sheet(i * 1000 + 500, j * 1000 + 500)
            if name not in index:
                missing.append(name)
            elif min(w, h) < skip_m:
                skip.append(name)
            else:
                keep.append(name)
    if not keep and skip:
        keep, skip = skip, []
    return sorted(keep), sorted(skip), sorted(missing)


def skipped_mask(bbox, size, skip):
    """The tile's 1 m cells (rows north to south) that lie on a skipped sheet."""
    out = np.zeros((size, size), bool)
    if not skip:
        return out
    from pyproj import Transformer
    xmin, ymin, xmax, ymax = bbox
    to_lks = Transformer.from_crs(f"EPSG:{LEST97}", f"EPSG:{LKS92}", always_xy=True)
    gx, gy = np.meshgrid(xmin + np.arange(size) + 0.5, ymax - np.arange(size) - 0.5)
    lx, ly = to_lks.transform(gx.ravel(), gy.ravel())
    key = (np.asarray(lx) // 1000).astype(np.int64) * 100000 + (np.asarray(ly) // 1000).astype(np.int64)
    flat = out.ravel()
    for k in np.unique(key):
        i, j = divmod(int(k), 100000)
        if las_sheet(i * 1000 + 500, j * 1000 + 500) in skip:
            flat |= key == k
    return flat.reshape(size, size)


def place_center(x3301, y3301, index=None):
    """Where to centre a new world asked for at an L-EST97 point so that it needs one laser sheet: the
    centre of the LKS-92 sheet holding the point, back on the L-EST97 grid in whole metres. The point
    stays inside the world (a sheet is 1000 m, the world 1024 m). Idempotent - a centre maps to
    itself - and the point unchanged when its sheet is not published."""
    index = las_index() if index is None else index
    (x, y), = geo.transform_points([(x3301, y3301)], LEST97, LKS92)
    if las_sheet(x, y) not in index:
        return x3301, y3301
    (ex, ey), = geo.transform_points([((x // 1000) * 1000 + 500, (y // 1000) * 1000 + 500)], LKS92, LEST97)
    return float(round(ex)), float(round(ey))


# ------------------------------------------------------------------------------------------ downloads
def _download(url, dest, label=None, span=None):
    import fetch_tile   # its download reports progress lines the tile service shows
    return fetch_tile.download(url, dest, label=label, span=span)


def _progress(frac, text):
    import fetch_tile
    fetch_tile.progress(frac, text)


# ------------------------------------------------------------------------------------------ laser points
def read_las(path):
    """(x, y, z, classification) of a LAS 1.0-1.3 file with point formats 0-5, as numpy arrays in the
    file's CRS. Reads the header by hand: no laspy in the sidecar, and the fixed record layout is enough."""
    with open(path, "rb") as f:
        head = f.read(227)
    if head[:4] != b"LASF":
        raise ValueError(f"{path} is not a LAS file")
    offset = int(np.frombuffer(head, "<u4", 1, 96)[0])
    fmt = head[104] & 0x3F
    rec_len = int(np.frombuffer(head, "<u2", 1, 105)[0])
    count = int(np.frombuffer(head, "<u4", 1, 107)[0])
    scale = np.frombuffer(head, "<f8", 3, 131)
    shift = np.frombuffer(head, "<f8", 3, 155)
    if fmt > 5:
        raise ValueError(f"{path}: point format {fmt} is not handled")
    dtype = np.dtype({"names": ["x", "y", "z", "cls"], "formats": ["<i4", "<i4", "<i4", "u1"],
                      "offsets": [0, 4, 8, 15], "itemsize": rec_len})
    pts = np.memmap(path, dtype=dtype, mode="r", offset=offset, shape=(count,))
    x = pts["x"] * scale[0] + shift[0]
    y = pts["y"] * scale[1] + shift[1]
    z = (pts["z"] * scale[2] + shift[2]).astype(np.float32)
    cls = pts["cls"] & 0x1F
    return x, y, z, cls


def grid_points(las_paths, bbox, size):
    """Per metre over an L-EST97 box: (ground, highest return, highest vegetation return, highest
    building return, ground hits, water level or None). Rows run north to south. Empty cells are NaN."""
    from pyproj import Transformer
    to_lest = Transformer.from_crs(f"EPSG:{LKS92}", f"EPSG:{LEST97}", always_xy=True)
    xmin, ymin, xmax, ymax = bbox
    n = size * size
    gsum = np.zeros(n, np.float64)
    gcnt = np.zeros(n, np.int32)
    top = np.full(n, -np.inf, np.float32)
    veg = np.full(n, -np.inf, np.float32)
    roof = np.full(n, -np.inf, np.float32)
    water = []
    for p in las_paths:
        x, y, z, cls = read_las(p)
        ex, ey = to_lest.transform(x, y)
        ex, ey = np.asarray(ex), np.asarray(ey)
        inside = (ex >= xmin) & (ex < xmax) & (ey > ymin) & (ey <= ymax) & ~np.isin(cls, NOISE)
        col = (ex[inside] - xmin).astype(np.int64)
        row = (ymax - ey[inside]).astype(np.int64)
        cell = np.clip(row, 0, size - 1) * size + np.clip(col, 0, size - 1)
        zz, cc = z[inside], cls[inside]
        g = np.isin(cc, GROUND)
        gsum += np.bincount(cell[g], weights=zz[g], minlength=n)
        gcnt += np.bincount(cell[g], minlength=n).astype(np.int32)
        np.maximum.at(top, cell, zz)
        v = np.isin(cc, VEGETATION)
        np.maximum.at(veg, cell[v], zz[v])
        r = cc == BUILDING
        np.maximum.at(roof, cell[r], zz[r])
        water.append(zz[cc == WATER])
        log(f"{os.path.basename(p)}: {int(inside.sum()):,} points on the tile, {int(g.sum()):,} ground")
    ground = np.where(gcnt > 0, gsum / np.maximum(gcnt, 1), np.nan).astype(np.float32).reshape(size, size)
    top = np.where(np.isfinite(top), top, np.nan).reshape(size, size)
    veg = np.where(np.isfinite(veg), veg, np.nan).reshape(size, size)
    roof = np.where(np.isfinite(roof), roof, np.nan).reshape(size, size)
    water = np.concatenate(water) if water else np.zeros(0, np.float32)
    level = float(np.median(water)) if water.size >= 100 else None
    return ground, top, veg, roof, gcnt.reshape(size, size), level


def roofs_path(raw_dir, tile):
    """Where the building-class heights above ground are kept for the cadastre step (not a pack file)."""
    return os.path.join(raw_dir, "lv", f"{tile}_roofs.r32")


def _box_count(mask, r):
    """How many cells of a (2r+1)^2 square around each cell are set (a summed-area table; no scipy)."""
    m = np.pad(mask.astype(np.int32), r + 1)
    c = m.cumsum(0).cumsum(1)
    k = 2 * r + 1
    return (c[k:, k:] - c[:-k, k:] - c[k:, :-k] + c[:-k, :-k])[: mask.shape[0], : mask.shape[1]]


def open_water(no_return, r=8):
    """The cells with no laser return at all that belong to an area wider than 2r+1 metres: open
    water, which swallows the pulse. A morphological opening, so a dark roof or a puddle stays out."""
    k = (2 * r + 1) ** 2
    core = _box_count(no_return, r) == k
    return (_box_count(core, r) > 0) & no_return


def fill_ground(ground):
    """Interpolate across the cells with no ground return (under buildings, dense canopy)."""
    from rasterio.fill import fillnodata
    mask = np.isfinite(ground)
    if not mask.any():
        raise ValueError("no ground points on the tile")
    filled = fillnodata(np.where(mask, ground, 0).astype(np.float32), mask=mask.astype(np.uint8), max_search_distance=300.0)
    left = ~np.isfinite(filled) | ((~mask) & (filled == 0))
    if left.any():   # beyond the search distance: the median ground
        filled[left] = float(np.nanmedian(ground))
    return filled.astype(np.float32), float((~mask).mean())


def fetch_ground(bbox, size, out_dir, raw_dir, tile, span=(0.05, 0.55)):
    """heightmap.r32 and canopy.r32 from the laser sheets under the box. Returns the meta fields."""
    index = las_index()
    sheets, skipped, missing = select_sheets(bbox, index)
    if not sheets:
        sys.exit("no LĢIA laser sheet covers this tile")
    if missing:
        log(f"no laser sheet for {', '.join(missing)} (outside Latvia or not published)")
    if skipped:
        log(f"not downloading {', '.join(skipped)}: under {SKIP_M:.0f} m of the tile each, filled from the ground beside it")
    las_dir = paths.raw("lv", "las") if raw_dir is None else os.path.join(raw_dir, "lv", "las")
    os.makedirs(las_dir, exist_ok=True)
    local = []
    for i, s in enumerate(sheets):
        f0 = span[0] + (span[1] - span[0]) * 0.8 * i / len(sheets)
        f1 = span[0] + (span[1] - span[0]) * 0.8 * (i + 1) / len(sheets)
        text = f"laser points, sheet {s} ({i + 1}/{len(sheets)})"
        dest = os.path.join(las_dir, s + ".las")
        _progress(f0, text + (", cached" if os.path.exists(dest) else ""))
        local.append(_download(index[s], dest, label=text, span=(f0, f1)))
    _progress(span[0] + (span[1] - span[0]) * 0.85, "gridding the ground and the canopy")
    ground, top, veg, roof, hits, level = grid_points(local, bbox, size)
    covered = float(np.isfinite(top).mean())
    # a skipped sheet's strip has no returns either, but it is not water: it stays empty and
    # fill_ground bridges it from the ground beside it (canopy and roofs are 0 there, so a building
    # on it takes the cadastre's storeys for its height)
    skip = skipped_mask(bbox, size, skipped)
    water = open_water(~np.isfinite(top) & ~skip)
    if water.any():
        # the river and the lakes sit at the level of their few water returns, not at a slope
        # interpolated from the banks (which streaks across hundreds of metres)
        level = level if level is not None else float(np.nanpercentile(ground, 2))
        ground[water] = level
        log(f"open water on {water.mean():.0%} of the tile at {level:.2f} m")
    heights, holes = fill_ground(ground)
    canopy = np.nan_to_num(veg - heights, nan=0.0)
    canopy = np.where((canopy > 0.3) & (canopy < 200.0), canopy, 0.0).astype(np.float32)
    geo.write_r32(heights, os.path.join(out_dir, "heightmap.r32"))
    geo.write_r32(canopy, os.path.join(out_dir, "canopy.r32"))
    # the roofs above the ground, for the buildings the cadastre draws (fetch_cadastre_lv.py): the
    # highest building return per metre, 0 where the laser saw no building
    roofs = np.nan_to_num(roof - heights, nan=0.0)
    geo.write_r32(np.where(roofs > 0.5, roofs, 0.0).astype(np.float32), roofs_path(raw_dir or paths.raw_root(), tile))
    zmin, zmax = float(heights.min()), float(heights.max())
    log(f"ground {zmin:.2f}..{zmax:.2f} m, {holes:.0%} of cells filled, points on {covered:.0%} of the tile; canopy up to {canopy.max():.1f} m")
    if covered < 0.5:
        log("warning: less than half the tile has laser points (the border, the sea or a missing sheet)")
    density = float(hits.sum()) / max(1, int((hits > 0).sum()))
    return {
        "z_min": round(zmin, 3), "z_max": round(zmax, 3), "dtm_res_m": 1,
        "canopy": {"file": "canopy.r32", "source": f"LĢIA laser points, highest vegetation return (classes 3-5) above the ground ({', '.join(sheets)})",
                   "max_height": round(float(canopy.max()), 2),
                   "format": "float32 little-endian, row-major, row 0 = north; metres above ground; 0 = nothing"},
        "laser": {"sheets": sheets, "missing": missing, "skipped": skipped, "skipped_share": round(float(skip.mean()), 3),
                  "ground_filled": round(holes, 3), "coverage": round(covered, 3),
                  "ground_pts_per_cell": round(density, 2), "urls": [index[s] for s in sheets]},
    }


# ------------------------------------------------------------------------------------------ orthophoto
def _tfw_transform(url):
    """The sheet's affine transform from its world file (which names the centre of the top-left pixel)."""
    from affine import Affine
    vals = [float(v) for v in urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "vakuraamat-pipeline/0.1"}),
                                                     timeout=60).read().decode().split()]
    a, d, b, e, c, f = vals
    return Affine(a, b, c - a / 2 - b / 2, d, e, f - d / 2 - e / 2)


def _cut(bbox, index, sheets, px, what):
    """The sheets' windows under the box, warped onto the L-EST97 grid: a (3, px, px) array, 0 where
    no sheet reaches. Only the windows are read, as HTTP range requests on the GeoTIFFs."""
    import rasterio
    from rasterio.crs import CRS
    from rasterio.transform import from_origin
    from rasterio.warp import Resampling, reproject
    from rasterio.windows import Window, from_bounds
    xmin, ymin, xmax, ymax = bbox
    box = lks_bbox(bbox, margin=10.0)
    dst = np.zeros((3, px, px), np.uint8)
    dst_t = from_origin(xmin, ymax, (xmax - xmin) / px, (ymax - ymin) / px)
    src_crs, dst_crs = CRS.from_epsg(LKS92), CRS.from_epsg(LEST97)
    with rasterio.Env(GDAL_DISABLE_READDIR_ON_OPEN="EMPTY_DIR", GDAL_HTTP_MAX_RETRY="3", GDAL_HTTP_RETRY_DELAY="2"):
        for s in sheets:
            t = _tfw_transform(index[s][".tfw"])
            with rasterio.open("/vsicurl/" + index[s][".tif"]) as src:
                w = from_bounds(*box, transform=t).round_offsets().round_lengths()
                w = w.intersection(Window(0, 0, src.width, src.height))
                data = src.read([1, 2, 3], window=w)
                wt = rasterio.windows.transform(w, t)
            part = np.zeros_like(dst)
            for b in range(3):
                reproject(data[b], part[b], src_transform=wt, src_crs=src_crs, dst_transform=dst_t, dst_crs=dst_crs,
                          src_nodata=None, dst_nodata=0, resampling=Resampling.bilinear)
            got = part.any(axis=0)
            dst[:, got] = part[:, got]
            log(f"{what} {s}: window {w.width}x{w.height} px")
    return dst


def _save_jpg(dst, out_jpg, quality=90):
    from PIL import Image
    if os.path.exists(out_jpg):
        os.remove(out_jpg)
    Image.fromarray(np.moveaxis(dst, 0, -1)).save(out_jpg, quality=quality)


def fetch_ortho(bbox, out_jpg, px=4096):
    """The 6th-cycle orthophoto over the box, warped onto the L-EST97 grid, as a px x px JPEG."""
    index = ortho_index()
    sheets = [s for s in _sheets_over(lks_bbox(bbox, margin=10.0), ORTHO_SHEET_M, ortho_sheet) if s in index]
    if not sheets:
        sys.exit("no LĢIA orthophoto sheet covers this tile")
    _save_jpg(_cut(bbox, index, sheets, px, "orthophoto"), out_jpg)
    return {"ortho_sheets": sheets, "ortho_urls": [index[s][".tif"] for s in sheets], "ortho_cycle": "LĢIA 6th cycle, 2016-2018, 25 cm"}


# ------------------------------------------------------------------------------------------ the older cycles
# LĢIA's earlier nationwide 1:10 000 flights in the open-data bucket, for the plot page's "over the
# years" strip (Estonia's comes from Maa-amet's historical WMS, which stops at the border). The 1st
# cycle (1994-99) is not in the bucket (403). The 2nd is in whole 5 km sheets (4311-32), the later
# ones in 2.5 km quarters (4311-32_1) like the 6th; the years are LĢIA's, and the files' own dates
# (2006, 2009, 2011, 2014) are when each was finished.
HISTORY = [("2003-05", 2), ("2007-08", 3), ("2010-11", 4), ("2013-15", 5)]
HISTORY_PX = 2048        # half a metre to the pixel over a kilometre: what the 2nd-4th cycles have


def cycle_index(v):
    """{sheet: {".tif", ".tfw"}} of one cycle, both files from the same folder (the 3rd cycle has
    some sheets twice, in a complete folder and a 'nepilns' - incomplete - one)."""
    url = BUCKET + f"ortofoto_rgb_v{v}/LGIA_OpenData_Ortofoto_rgb_v{v}_saites.txt"
    path = os.path.join(paths.raw("lv"), f"ortho_v{v}_links.txt")
    if not os.path.exists(path):
        _download(url, path)
    by_stem = {}
    for line in open(path, encoding="utf-8", errors="ignore"):
        line = line.strip()
        if line.startswith("http"):
            base, ext = os.path.splitext(line)
            by_stem.setdefault(base, {})[ext.lower()] = line
    out = {}
    for base, files in sorted(by_stem.items(), key=lambda kv: "nepilns" in kv[0]):   # complete folders first
        stem = base.rsplit("/", 1)[1]
        if ".tif" in files and ".tfw" in files and stem not in out:
            out[stem] = files
    return out


def add_history(tile_dir, px=HISTORY_PX):
    """Cut each older cycle over a Latvian tile into ortho_<years>.jpg beside its ortho.jpg and list
    them in terrain_meta.json as "history". The cycles are strip-stored TIFFs without overviews, so a
    cut pulls whole rows (tens of MB a cycle): the tile service does it in the refine pass, after the
    place is playable, the four cycles side by side. A cycle that did not fly over the tile is left out."""
    from concurrent.futures import ThreadPoolExecutor
    meta_path = os.path.join(tile_dir, "terrain_meta.json")
    meta = json.load(open(meta_path))
    bbox = (meta["xmin"], meta["ymin"], meta["xmax"], meta["ymax"])
    wanted = _sheets_over(lks_bbox(bbox, margin=10.0), ORTHO_SHEET_M, ortho_sheet)

    def one(entry):
        label, v = entry
        index = cycle_index(v)
        sheets = sorted({n for s in wanted for n in (s, s.split("_")[0]) if n in index})
        if not sheets:
            return None
        dst = _cut(bbox, index, sheets, px, f"cycle {v} ({label})")
        if dst.any(axis=0).mean() < 0.05:
            return None
        name = f"ortho_{label}.jpg"
        _save_jpg(dst, os.path.join(tile_dir, name), quality=85)
        return {"label": label, "texture": name, "cycle": v, "sheets": sheets}

    with ThreadPoolExecutor(max_workers=len(HISTORY)) as pool:
        got = [h for h in pool.map(one, HISTORY) if h]
    meta["history"] = got
    meta.setdefault("source", {})["history"] = [BUCKET + f"ortofoto_rgb_v{v}/" for _, v in HISTORY]
    with open(meta_path, "w") as f:
        json.dump(meta, f, indent=2, ensure_ascii=False)
    log(f"history: {', '.join(h['label'] for h in got) or 'no older cycle covers the tile'}")
    return got


# ------------------------------------------------------------------------------------------ the tile
def build_tile(a, raw_dir, out_dir, bbox):
    """What fetch_tile.main does for Estonia, for a Latvian tile: the ground, the canopy, the
    orthophoto and terrain_meta.json. `a` is fetch_tile's parsed arguments."""
    xmin, ymin, xmax, ymax = bbox
    size = int(xmax - xmin)
    meta_path = os.path.join(out_dir, "terrain_meta.json")
    ground = fetch_ground(bbox, size, out_dir, raw_dir, a.name)
    if a.only_dem:
        meta = json.load(open(meta_path)) if os.path.exists(meta_path) else {}
        meta.update({k: ground[k] for k in ("z_min", "z_max", "dtm_res_m", "canopy")})
        meta.setdefault("source", {}).update({"laser": ground["laser"]})
        json.dump(meta, open(meta_path, "w"), indent=2, ensure_ascii=False)
        return
    px = min(a.texture_px, 4096)
    _progress(0.6, "orthophoto, 25 cm (2016-18)")
    ortho = fetch_ortho(bbox, os.path.join(out_dir, "ortho.jpg"), px)
    if a.no_canopy:
        os.remove(os.path.join(out_dir, "canopy.r32"))
        ground["canopy"] = None
    today = dt.date.today().isoformat()
    meta = {
        "name": a.name,
        "country": "lv",
        "crs": "EPSG:3301",
        "sheet": ground["laser"]["sheets"][0],
        "xmin": xmin, "ymin": ymin, "xmax": xmax, "ymax": ymax,
        "size_m": size,
        "size_px": size,
        "resolution_m": 1.0,
        "dtm_res_m": 1,
        "heightmap": "heightmap.r32",
        "heightmap_format": "float32 little-endian, row-major, row 0 = north edge (ymax), metres LAS-2000,5 (EVRF2007 like EH2000)",
        "z_min": ground["z_min"], "z_max": ground["z_max"],
        "z_scale": a.z_scale,
        "texture": "ortho.jpg",
        "texture_px": px,
        "canopy": ground["canopy"],
        "era_maps": {},
        "world_mapping": "Godot x = easting - xmin; Godot z = ymax - northing (north is -Z); y = height * z_scale; "
                         "L-EST97 grid, the Latvian sources reprojected from LKS-92 (EPSG:3059)",
        "source": {"laser": ground["laser"], "ortho": ortho, "index": [LAS_INDEX, ORTHO_INDEX]},
        "fetched": today,
        "attribution": ATTRIBUTION.format(year=today[:4]),
        "license": LICENSE,
    }
    with open(meta_path, "w") as f:
        json.dump(meta, f, indent=2, ensure_ascii=False)
    shutil.copyfile(meta_path, os.path.join(raw_dir, f"{a.name}_terrain_meta.json"))
    log(f"wrote {out_dir}/{{heightmap.r32, canopy.r32, ortho.jpg, terrain_meta.json}}")
