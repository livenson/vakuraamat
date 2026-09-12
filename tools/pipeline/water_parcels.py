#!/usr/bin/env python3
"""A tile's rivers and lakes as the cadastre draws them, cleared of what the flights caught on them.

    python3 tools/pipeline/water_parcels.py --site riga_vecpilseta [--raw-dir data_raw]

The orthophoto is the ground's colour, and a river is ground like any other: the cruise ships moored
along Rīga's embankment on the day of the flight were painted on the Daugava (playtest report
2026-09-12T14-26-11), and the laser, flown on another day, had one of them as a bump in the ground
(its deck classed as ground). Neither can tell a hull from the quay beside it; the cadastre can. A
parcel whose every purpose is water land (VEEKOGUDE_MAA: Latvia's 0301 "public waters", Estonia's
veekogude maa) is the water's outline up to the quay. Over such a parcel, when it is open water (most
of it at one level; a stream in its valley is left alone), this
  - paints the orthophoto with the water's own tone (its low frequencies, the boats taken out), the
    edge following the photograph's waterline within EDGE_M of the parcel's;
  - lowers raised blobs at least SHIP_M across to the water level (a ship; the quay's slope along the
    edge is narrower and stays);
  - clears the canopy.
Bridge decks stay: the laser's bridge class, where the tile has one (bridges_path), is cut out first.
Rewrites the tile's ortho.jpg, heightmap.r32 and canopy.r32 in place and notes "water" in
terrain_meta.json; a second run finds nothing left to lower. Needs numpy, Pillow, rasterio, shapely.
"""
import argparse, json, os, sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import geo, paths  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WATER_LAND = "VEEKOGUDE_MAA"
MIN_AREA = 500        # m² of a parcel on the tile: a smaller one is a ditch or a well
OPEN_SHARE = 0.8      # of a parcel's cells within LEVEL_TOL of its level, for it to be open water
LEVEL_TOL = 0.3       # metres
SHIP_M = 5            # the narrowest raised blob that is lowered
EDGE_M = 1            # how far in from the parcel's edge the photograph decides where the water is


def log(msg):
    print(f"[water_parcels] {msg}", flush=True)


def bridges_path(raw_dir, tile):
    """Where a tile's bridge-deck mask is kept between the ground step and this one (not a pack file)."""
    return os.path.join(raw_dir, "bridges", f"{tile}.r32")


def _count(mask, r):
    """How many cells of a (2r+1)^2 square around each cell are set (a summed-area table; no scipy)."""
    m = np.pad(mask.astype(np.int32), r + 1)
    c = m.cumsum(0).cumsum(1)
    k = 2 * r + 1
    return (c[k:, k:] - c[:-k, k:] - c[k:, :-k] + c[:-k, :-k])[: mask.shape[0], : mask.shape[1]]


def dilate(mask, r):
    return _count(mask, r) > 0


def erode(mask, r):
    return ~dilate(~mask, r)   # outside the tile counts as set: water running off the edge stays water


def water_bodies(parcels, heights):
    """[(tunnus, mask, level)] of the open-water parcels on the tile."""
    from rasterio.features import rasterize
    from shapely.geometry import Polygon
    size = heights.shape[0]
    out = []
    for p in parcels:
        purpose = p.get("purpose") or []
        if not purpose or any(x != WATER_LAND for x in purpose):
            continue
        pts = json.loads(p["polygon"]) if isinstance(p.get("polygon"), str) else p.get("polygon") or []
        if len(pts) < 3:
            continue
        m = rasterize([(Polygon(pts).buffer(0), 1)], out_shape=(size, size)).astype(bool)   # tile metres: x = column, z = row
        if m.sum() < MIN_AREA:
            continue
        level = float(np.median(heights[m]))
        if np.mean(np.abs(heights[m] - level) < LEVEL_TOL) < OPEN_SHARE:
            log(f"{p.get('tunnus')}: not open water (a stream in its valley?), left as it is")
            continue
        out.append((p.get("tunnus"), m, level))
    return out


def _paint_photo(path, water, inner):
    """The photograph over `water` replaced by the water's own tone: a 15 m blur of its calm pixels,
    anything unlike them (a hull, a wake) taken out first. Full strength over `inner`; in the band
    between, as much as the pixel itself looks like water, so the edge is the photograph's waterline."""
    from PIL import Image, ImageFilter
    img = Image.open(path).convert("RGB")
    size = water.shape[0]
    k = img.width // size
    small = np.asarray(img.resize((size, size), Image.BOX)).astype(np.float32)
    calm_small = inner & (np.linalg.norm(small - np.median(small[inner], axis=0), axis=2) < 40)
    tint = np.median(small[calm_small if calm_small.any() else inner], axis=0)
    a = np.array(img)
    base = a.copy()
    alpha = np.zeros(a.shape[:2], np.float32)
    ones = np.ones((k, k), bool)
    for r0 in range(0, size, 64):   # in bands: a 4096 px photograph in float would be 200 MB a copy
        rows = slice(r0 * k, (r0 + 64) * k)
        w = np.kron(water[r0:r0 + 64], ones)
        dist = np.linalg.norm(a[rows].astype(np.float32) - tint, axis=2)
        alpha[rows] = np.where(np.kron(inner[r0:r0 + 64], ones), 1.0, np.where(w, np.clip((50.0 - dist) / 25.0, 0.0, 1.0), 0.0))
        band = base[rows]
        band[~(w & (dist < 40))] = tint.astype(np.uint8)
    tone = Image.fromarray(base).resize((size, size), Image.BOX).filter(ImageFilter.GaussianBlur(15))
    tone = np.asarray(tone.resize(img.size, Image.BILINEAR))
    alpha = np.asarray(Image.fromarray((alpha * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.5))).astype(np.float32) / 255
    for r0 in range(0, a.shape[0], 256):
        rows = slice(r0, r0 + 256)
        al = alpha[rows][..., None]
        a[rows] = np.round(a[rows] * (1 - al) + tone[rows] * al).astype(np.uint8)
    os.remove(path)
    Image.fromarray(a).save(path, quality=90)


def paint(site, root=ROOT, raw_dir=None):
    """Clear the open water of `site`'s tile (see the module doc). Returns the meta note, or None
    when the tile has no open-water parcel."""
    site_dir = os.path.join(root, "sites", site)
    tile = json.load(open(os.path.join(site_dir, "site.json"))).get("terrain", {}).get("tile", site)
    tdir = os.path.join(root, "assets", "terrain", tile)
    meta_path = os.path.join(tdir, "terrain_meta.json")
    meta = json.load(open(meta_path))
    ppath = os.path.join(site_dir, "parcels.json")
    if not os.path.exists(ppath):
        log(f"{site}: no parcels.json, nothing to go by")
        return None
    size = int(meta["size_px"])
    hpath = os.path.join(tdir, meta.get("heightmap", "heightmap.r32"))
    heights = np.fromfile(hpath, "<f4").reshape(size, size)
    bodies = water_bodies(json.load(open(ppath)).get("parcels", []), heights)
    if not bodies:
        log(f"{site}: no open-water parcel on the tile")
        return None
    bpath = bridges_path(raw_dir or paths.raw_root(), tile)
    deck = dilate(np.fromfile(bpath, "<f4").reshape(size, size) > 0, 1) if os.path.exists(bpath) else np.zeros((size, size), bool)
    water = np.zeros((size, size), bool)
    lowered = np.zeros((size, size), bool)
    r = SHIP_M // 2
    for _, m, level in bodies:
        m = m & ~deck
        water |= m
        high = m & (heights > level + LEVEL_TOL)
        blob = dilate(dilate(erode(high, r), r) & high, 1) & m   # what a SHIP_M square fits in, and its sloped rim
        heights[blob] = np.minimum(heights[blob], level)
        lowered |= blob
    if lowered.any():
        geo.write_r32(heights, hpath)
        meta["z_min"], meta["z_max"] = round(float(heights.min()), 3), round(float(heights.max()), 3)
    if meta.get("canopy"):
        cpath = os.path.join(tdir, meta["canopy"]["file"])
        canopy = np.fromfile(cpath, "<f4").reshape(size, size)
        geo.write_r32(np.where(water, 0.0, canopy).astype(np.float32), cpath)
    _paint_photo(os.path.join(tdir, meta["texture"]), water, erode(water, EDGE_M) | lowered)
    note = {"parcels": [t for t, _, _ in bodies], "share": round(float(water.mean()), 3), "lowered_m2": int(lowered.sum()),
            "bridges": bool(deck.any()), "source": "the cadastre's water-land parcels (tools/pipeline/water_parcels.py)"}
    meta["water"] = note
    with open(meta_path, "w") as f:
        json.dump(meta, f, indent=2, ensure_ascii=False)
    log(f"{site}: open water on {note['share']:.0%} of the tile ({', '.join(note['parcels'])}), {note['lowered_m2']} m² lowered to its level")
    return note


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--site", required=True)
    ap.add_argument("--raw-dir", help="where the ground step left the bridge decks (default: the pipeline's raw directory)")
    a = ap.parse_args(argv)
    paint(a.site, raw_dir=a.raw_dir)


if __name__ == "__main__":
    main()
