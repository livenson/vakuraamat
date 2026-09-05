#!/usr/bin/env python3
"""Derives a site's buildings and still-water files from the fetched terrain tile.

    python3 tools/pipeline/extract_features.py --site kvissentali [--dry-run]

Inputs (assets/terrain/<tile>/): heightmap.r32, canopy.r32, ortho.jpg, terrain_meta.json.
Outputs (sites/<site>/, names from site.json "buildings" / "water"):
    buildings_*.json  [{x, z, w, d, h, color}]  objects >= 2.5 m tall that are not green in the
                      orthophoto (roofs), as bounding boxes in tile metres; the 2026 village massing
    water_*.json      [{area, x, z, w, d, level, color}]  flat, dark, treeless patches of the laser DTM
Both are starting points for the author: delete, merge or move entries by hand.
Needs numpy and the GDAL command line (gdal_translate) for the JPEG.
"""
import argparse, json, math, os, subprocess, sys, tempfile
from collections import deque

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def log(msg):
    print(f"[extract_features] {msg}", flush=True)


def load_ortho(path, size):
    """Orthophoto resampled to one texel per metre as float RGB in 0..1 (via GDAL, band-sequential)."""
    with tempfile.TemporaryDirectory() as td:
        raw = os.path.join(td, "ortho.raw")
        subprocess.run(["gdal_translate", "-q", "-of", "ENVI", "-co", "INTERLEAVE=BIP", "-ot", "Byte", "-outsize", str(size), str(size), "-r", "average", path, raw], check=True)
        data = np.fromfile(raw, dtype=np.uint8)
    if data.size != 3 * size * size:
        sys.exit(f"unexpected orthophoto raw size {data.size}")
    return data.reshape(size, size, 3).astype(np.float32) / 255.0   # BIP: r, g, b per pixel


def components(mask, min_area):
    """8-connected components of a boolean mask -> list of (pixel_index_array)."""
    size = mask.shape[0]
    seen = np.zeros_like(mask, dtype=bool)
    ys, xs = np.nonzero(mask)
    out = []
    for y0, x0 in zip(ys, xs):
        if seen[y0, x0]:
            continue
        q = deque([(y0, x0)]); seen[y0, x0] = True; pix = []
        while q:
            y, x = q.popleft(); pix.append((y, x))
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    ny, nx = y + dy, x + dx
                    if 0 <= ny < size and 0 <= nx < size and mask[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True; q.append((ny, nx))
        if len(pix) >= min_area:
            out.append(np.array(pix))
    return out


def box_fraction(mask, r):
    """Fraction of True in a (2r+1)² window around every pixel (edges clamp), via summed-area table."""
    size = mask.shape[0]
    sat = np.zeros((size + 1, size + 1), dtype=np.int64)
    sat[1:, 1:] = np.cumsum(np.cumsum(mask.astype(np.int64), axis=0), axis=1)
    ys, xs = np.mgrid[0:size, 0:size]
    y0 = np.clip(ys - r, 0, size); y1 = np.clip(ys + r + 1, 0, size); x0 = np.clip(xs - r, 0, size); x1 = np.clip(xs + r + 1, 0, size)
    total = sat[y1, x1] - sat[y0, x1] - sat[y1, x0] + sat[y0, x0]
    return total / ((y1 - y0) * (x1 - x0))


def find_anchors(heights, canopy, ortho, buildings):
    """Named spots for a generated story: register/spawn on open ground near the centre, the landmark at
    the largest building (else the tallest trees), the farm on the widest open ground, the trade post by a
    road, the field on crops or soil. Heuristics; the author moves them afterwards."""
    size = heights.shape[0]
    r, g, b = ortho[..., 0], ortho[..., 1], ortho[..., 2]
    v = ortho.max(axis=2)
    sat = np.where(v > 0, (v - ortho.min(axis=2)) / np.maximum(v, 1e-6), 0)
    green_excess = g - np.maximum(r, b)
    gravel = (v > 0.62) & (sat < 0.22)
    tall = (canopy >= 2.5) if canopy is not None else np.zeros_like(gravel)
    field = (~gravel) & (green_excess > 0.03) & (v > 0.5) & (sat > 0.35) & ~tall
    soil = (~gravel) & (green_excess <= 0.03) & (v >= 0.25) & ~tall
    built = np.zeros_like(gravel)
    for bld in buildings:
        x0 = int(max(bld["x"] - bld["w"] / 2 - 3, 0)); x1 = int(min(bld["x"] + bld["w"] / 2 + 3, size))
        z0 = int(max(bld["z"] - bld["d"] / 2 - 3, 0)); z1 = int(min(bld["z"] + bld["d"] / 2 + 3, size))
        built[z0:z1, x0:x1] = True
    open_ground = ~tall & ~built
    ys, xs = np.mgrid[0:size, 0:size]
    c = size / 2.0
    dist_c = np.hypot(xs - c, ys - c)

    def best(score, mask):
        s = np.where(mask, score, -np.inf)
        i = int(np.argmax(s))
        return [float(i % size), float(i // size)] if np.isfinite(s.flat[i]) else None

    open25 = box_fraction(open_ground & ~gravel, 12)
    register = best(open25 - dist_c / 1500.0, (dist_c <= 150) & open_ground & ~gravel) or [c, c]
    rx, rz = register
    spawn = [rx, rz + 20] if rz + 20 < size and open_ground[int(rz + 20), int(rx)] else [rx, rz - 20]
    dist_r = np.hypot(xs - rx, ys - rz)
    landmark = None
    near = [bld for bld in buildings if math.hypot(bld["x"] - rx, bld["z"] - rz) <= 350 and math.hypot(bld["x"] - rx, bld["z"] - rz) >= 25]
    notable = [bld for bld in near if bld.get("monument") or "mõis" in str(bld.get("name") or "").lower() or "kirik" in str(bld.get("name") or "").lower()]
    if notable:
        big = max(notable, key=lambda bld: bld["w"] * bld["d"])
        landmark = [big["x"], big["z"] + big["d"] / 2 + 8]
    elif near:
        big = max(near, key=lambda bld: bld["w"] * bld["d"])
        landmark = [big["x"], big["z"] + big["d"] / 2 + 8]
    elif canopy is not None:
        landmark = best(canopy, (dist_r <= 250) & (dist_r >= 30))
    landmark = landmark or [rx + 40, rz - 30]
    open60 = box_fraction(open_ground & ~gravel, 30)
    farm = best(open60, (dist_r >= 80) & (dist_r <= 350) & open_ground) or [rx - 60, rz + 40]
    grav15 = box_fraction(gravel, 7)
    trade = best(grav15 - dist_r / 600.0, (dist_r <= 120) & (dist_r >= 12) & (grav15 > 0.15)) or [rx + 30, rz + 30]
    crop60 = box_fraction(field | soil, 30)
    dist_f = np.hypot(xs - farm[0], ys - farm[1])
    fld = best(crop60, (dist_f >= 100) & (dist_r <= 400) & open_ground) or [rx + 80, rz + 90]
    return {k: [round(p[0], 1), round(p[1], 1)] for k, p in
            {"register": register, "spawn": spawn, "landmark": landmark, "farm": farm, "trade": trade, "field": fld}.items()}


def extract(site, dry_run=False, min_building=25, min_pond=80, building_height=2.5, root=ROOT):
    site_dir = os.path.join(root, "sites", site)
    m = json.load(open(os.path.join(site_dir, "site.json")))
    tile = m.get("terrain", {}).get("tile", site)
    tdir = os.path.join(root, "assets/terrain", tile)
    meta = json.load(open(os.path.join(tdir, "terrain_meta.json")))
    size = int(meta["size_px"])
    heights = np.fromfile(os.path.join(tdir, meta["heightmap"]), dtype="<f4").reshape(size, size)
    canopy = None
    if meta.get("canopy"):
        canopy = np.fromfile(os.path.join(tdir, meta["canopy"]["file"]), dtype="<f4").reshape(size, size)
    ortho = load_ortho(os.path.join(tdir, meta["texture"]), size)
    r, g, b = ortho[..., 0], ortho[..., 1], ortho[..., 2]
    v = ortho.max(axis=2)
    green_excess = g - np.maximum(r, b)

    # --- buildings: tall and not vegetation-coloured ------------------------------------------
    buildings = []
    if canopy is None:
        log("no canopy layer: cannot derive buildings")
    else:
        # tall, not green, not deep shadow (shadowed canopy reads grey-black in the orthophoto)
        mask = (canopy >= building_height) & (green_excess <= 0.03) & (v >= 0.28)
        for pix in components(mask, min_building):
            ys, xs = pix[:, 0], pix[:, 1]
            w = int(xs.max() - xs.min() + 1); d = int(ys.max() - ys.min() + 1)
            fill = len(pix) / float(w * d)
            if fill < 0.45 or min(w, d) < 4 or max(w, d) > 120:
                continue   # ragged or sliver: canopy edge, hedge or wall, not a roof
            h = float(np.median(canopy[ys, xs]))
            col = ortho[ys, xs].mean(axis=0)
            buildings.append({"x": round(float(xs.min() + xs.max() + 1) / 2, 1), "z": round(float(ys.min() + ys.max() + 1) / 2, 1),
                              "w": w, "d": d, "h": round(h, 1), "color": [round(float(c), 3) for c in col]})
        buildings.sort(key=lambda b: (b["z"], b["x"]))
        log(f"{len(buildings)} buildings (>= {min_building} m², >= {building_height} m)")

    # --- still water: flat, dark, treeless ---------------------------------------------------
    gy, gx = np.gradient(heights)
    slope = np.hypot(gx, gy)
    flat = (slope < 0.03) & (v < 0.5) & (green_excess < 0.08)
    if canopy is not None:
        flat &= canopy < building_height   # laser returns off water are noisy; only exclude buildings/trees
    ponds = []
    for pix in components(flat, min_pond):
        ys, xs = pix[:, 0], pix[:, 1]
        w = int(xs.max() - xs.min() + 1); d = int(ys.max() - ys.min() + 1)
        if len(pix) / float(w * d) < 0.35:
            continue   # a road or ditch, not a pond
        # water sits below its banks: compare with a 3..8 m ring around the bounding box
        y0, y1 = max(ys.min() - 8, 0), min(ys.max() + 9, size); x0, x1 = max(xs.min() - 8, 0), min(xs.max() + 9, size)
        ring = np.ones((y1 - y0, x1 - x0), dtype=bool)
        ring[max(ys.min() - 3, 0) - y0:min(ys.max() + 4, size) - y0, max(xs.min() - 3, 0) - x0:min(xs.max() + 4, size) - x0] = False
        bank = heights[y0:y1, x0:x1][ring]
        level = float(np.median(heights[ys, xs]))
        if bank.size == 0 or level > float(np.median(bank)) - 0.15:
            continue   # not a depression: a flat dark yard, car park or shadow
        col = ortho[ys, xs].mean(axis=0)
        ponds.append({"area": int(len(pix)), "x": round(float(xs.min() + xs.max() + 1) / 2, 1), "z": round(float(ys.min() + ys.max() + 1) / 2, 1),
                      "w": w, "d": d, "level": round(level, 2), "color": [round(float(c), 2) for c in col]})
    ponds.sort(key=lambda p: -p["area"])
    log(f"{len(ponds)} still-water patches (>= {min_pond} m²)")

    reg_path = os.path.join(site_dir, "buildings.json")
    reg = json.load(open(reg_path)).get("buildings", []) if os.path.exists(reg_path) else []
    anchors = find_anchors(heights, canopy, ortho, reg or buildings)
    log("anchors " + ", ".join(f"{k} ({v[0]:.0f},{v[1]:.0f})" for k, v in anchors.items()))
    bfile = os.path.join(site_dir, m.get("buildings", "buildings_2026.json"))
    wfile = os.path.join(site_dir, m.get("water", "water_2026.json"))
    if dry_run:
        for bld in buildings[:8]:
            log(f"  building {bld}")
        for p in ponds[:8]:
            log(f"  water {p}")
        return buildings, ponds, anchors
    json.dump(buildings, open(bfile, "w"), indent=1)
    json.dump(ponds, open(wfile, "w"), indent=1)
    json.dump(anchors, open(os.path.join(site_dir, "anchors.json"), "w"), indent=1)
    log(f"wrote {os.path.relpath(bfile, root)}, {os.path.relpath(wfile, root)} and anchors.json")
    return buildings, ponds, anchors


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--site", default="palupera")
    ap.add_argument("--dry-run", action="store_true", help="print, write nothing")
    ap.add_argument("--min-building", type=int, default=25, help="smallest roof area in m² (default 25)")
    ap.add_argument("--min-pond", type=int, default=80, help="smallest water patch in m² (default 80)")
    ap.add_argument("--root", default=ROOT, help="project root holding sites/ and assets/terrain/ (default: the repo)")
    a = ap.parse_args()
    extract(a.site, a.dry_run, a.min_building, a.min_pond, root=a.root)
