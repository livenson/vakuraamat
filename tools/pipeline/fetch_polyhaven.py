#!/usr/bin/env python3
"""Fetches CC0 PBR textures from Poly Haven (https://polyhaven.com, API https://api.polyhaven.com)
and packs them the way the game wants them:

    terrain  -> assets/terrain/textures/<name>_alb_ht.png   colour RGB + displacement in alpha
                assets/terrain/textures/<name>_nrm_rgh.png  OpenGL normal RGB + roughness in alpha
    building -> assets/textures/buildings/<name>_color.jpg, <name>_normal.jpg (OpenGL normal)

The sets below map the game's material names to Poly Haven asset slugs. Downloads are cached under
data_raw/polyhaven/<slug>/ so re-running only re-packs. Every fetched asset is recorded in
assets/textures/POLYHAVEN.json (slug, resolution, date, licence) for THIRD_PARTY.md.

    python3 tools/pipeline/fetch_polyhaven.py                # all sets, 1k
    python3 tools/pipeline/fetch_polyhaven.py --set terrain --res 2k
    python3 tools/pipeline/fetch_polyhaven.py --list        # what would be fetched
"""
import argparse
import datetime
import json
import os
import sys
import urllib.request

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CACHE = os.path.join(ROOT, "data_raw", "polyhaven")
API = "https://api.polyhaven.com/files/"
UA = {"User-Agent": "vakuraamat-pipeline/1.0 (+https://github.com/ilja/vakuraamat)"}

# game name -> Poly Haven slug
SETS = {
    "terrain": {
        "meadow": "aerial_grass_rock",        # rough grass with stones
        "field": "leafy_grass",               # lush, even green
        "forest_floor": "brown_mud_leaves_01",  # leaf litter and soil
        "gravel": "gravel_floor",             # yard and road gravel
        "soil": "aerial_mud_1",               # bare ploughed ground
    },
    "buildings": {
        "plaster": "plastered_wall",
        "brick": "red_brick_03",
        "concrete": "painted_concrete",
        "panel": "concrete_wall_006",         # prefab panel blocks
        "woodsiding": "wood_planks_grey",     # weathered boards
        "logs": "old_planks_02",              # log and plank walls
        "rooftiles": "roof_tiles_14",
        "metalroof": "corrugated_iron_02",
        "thatch": "reed_roof_03",
        "rock": "brick_wall_006",             # fieldstone stands in: rough stone wall
    },
}
TERRAIN_DIR = os.path.join(ROOT, "assets", "terrain", "textures")
BUILDING_DIR = os.path.join(ROOT, "assets", "textures", "buildings")
RECORD = os.path.join(ROOT, "assets", "textures", "POLYHAVEN.json")


def log(msg):
    print(f"[polyhaven] {msg}", flush=True)


def fetch_json(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
        return json.load(r)


def download(url, dest):
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        return dest
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=180) as r, open(dest + ".part", "wb") as f:
        while True:
            chunk = r.read(1 << 16)
            if not chunk:
                break
            f.write(chunk)
    os.replace(dest + ".part", dest)
    return dest


def fetch_maps(slug, res):
    """Downloads Diffuse, nor_gl, Rough and Displacement (jpg) at `res`; returns {map: path}."""
    files = fetch_json(API + slug)
    out = {}
    for key in ("Diffuse", "nor_gl", "Rough", "Displacement"):
        entry = files.get(key, {}).get(res)
        if not entry:
            continue
        fmt = "jpg" if "jpg" in entry else next(iter(entry))
        url = entry[fmt]["url"]
        dest = os.path.join(CACHE, slug, f"{slug}_{key}_{res}.{fmt}")
        download(url, dest)
        out[key] = dest
    if "Diffuse" not in out or "nor_gl" not in out:
        raise RuntimeError(f"{slug}: no diffuse/normal at {res}")
    return out


def to_gray(path, size):
    return np.asarray(Image.open(path).convert("L").resize(size, Image.LANCZOS), dtype=np.uint8)


def pack_terrain(name, maps):
    diff = Image.open(maps["Diffuse"]).convert("RGB")
    size = diff.size
    height = to_gray(maps["Displacement"], size) if "Displacement" in maps else np.full(size[::-1], 128, np.uint8)
    rough = to_gray(maps["Rough"], size) if "Rough" in maps else np.full(size[::-1], 200, np.uint8)
    alb = np.dstack([np.asarray(diff, dtype=np.uint8), height])
    nrm = np.dstack([np.asarray(Image.open(maps["nor_gl"]).convert("RGB").resize(size, Image.LANCZOS), dtype=np.uint8), rough])
    os.makedirs(TERRAIN_DIR, exist_ok=True)
    Image.fromarray(alb, "RGBA").save(os.path.join(TERRAIN_DIR, f"{name}_alb_ht.png"), optimize=True)
    Image.fromarray(nrm, "RGBA").save(os.path.join(TERRAIN_DIR, f"{name}_nrm_rgh.png"), optimize=True)


def pack_building(name, maps):
    os.makedirs(BUILDING_DIR, exist_ok=True)
    Image.open(maps["Diffuse"]).convert("RGB").save(os.path.join(BUILDING_DIR, f"{name}_color.jpg"), quality=88)
    Image.open(maps["nor_gl"]).convert("RGB").save(os.path.join(BUILDING_DIR, f"{name}_normal.jpg"), quality=90)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--set", choices=sorted(SETS), action="append", help="which set(s); default all")
    ap.add_argument("--res", default="1k", choices=["1k", "2k", "4k"])
    ap.add_argument("--list", action="store_true")
    a = ap.parse_args()
    sets = a.set or sorted(SETS)
    record = json.load(open(RECORD)) if os.path.exists(RECORD) else {}
    for s in sets:
        for name, slug in SETS[s].items():
            if a.list:
                print(f"{s:10s} {name:14s} <- {slug}")
                continue
            log(f"{s}/{name} <- {slug} @ {a.res}")
            try:
                maps = fetch_maps(slug, a.res)
            except Exception as e:  # noqa: BLE001 - report and continue with the rest
                log(f"  failed: {e}")
                continue
            (pack_terrain if s == "terrain" else pack_building)(name, maps)
            record[f"{s}/{name}"] = {"slug": slug, "url": f"https://polyhaven.com/a/{slug}", "resolution": a.res,
                                     "licence": "CC0 1.0", "fetched": datetime.date.today().isoformat()}
    if not a.list:
        os.makedirs(os.path.dirname(RECORD), exist_ok=True)
        json.dump(record, open(RECORD, "w"), indent=1, sort_keys=True)
        log(f"{len(record)} textures recorded in {os.path.relpath(RECORD, ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
