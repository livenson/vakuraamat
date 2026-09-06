#!/usr/bin/env python3
"""Measured single trees for a tile from Maa-amet's Geo3D vegetation dataset (LOD0 üksikpuud).

    python3 tools/pipeline/fetch_trees.py --site kvissentali [--root <workspace>]

Every tree detected in the airborne laser point cloud: trunk position, height, crown diameter, type
(Okaspuu = conifer, Lehtpuu = deciduous, from Sentinel-2 NDVI), scan year. Coverage (2026): towns flown
at low altitude in 2020-2024, one GeoPackage per municipality (EHAK code in the file name). Where the
tile has no trees in the dataset the terrain builder keeps its statistical scatter from the nDSM.

Writes assets/terrain/<tile>/trees.json: {"source", "count", "trees": [[x, z, height, crown, type], ...]}
(tile metres, x east, z south; type 1 = conifer, 0 = deciduous). Downloads and the CSV dump of each
municipality are cached in data_raw/trees/.
"""
import argparse, csv, html, json, os, re, shutil, sys, time, urllib.parse, urllib.request, zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fetch_buildings import municipalities  # noqa: E402

UA = {"User-Agent": "vakuraamat-pipeline/0.1 (open-source game; polite, cached)"}
DL_PAGE = "https://geoportaal.maaamet.ee/est/ruumiandmed/geo3d/laadi-3d-andmed-alla-p833.html"
VEG_URL = "https://geoportaal.maaamet.ee/index.php?lang_id=1&plugin_act=otsing&andmetyyp=vegetatsioon&dl=1&f=vegetatsioon-{name}-{code}-gpkg.zip&page_id=833"
ATTRIBUTION = "Üksikpuude mudeli andmekogum (Geo3D): Maa- ja Ruumiamet"


def log(msg):
    print(f"[fetch_trees] {msg}", flush=True)


def municipality_codes(cache_dir):
    """{municipality file name: EHAK code} scraped from the download page (cached)."""
    p = os.path.join(cache_dir, "municipality_codes.json")
    if os.path.exists(p):
        return json.load(open(p))
    page = urllib.request.urlopen(urllib.request.Request(DL_PAGE, headers=UA), timeout=60).read().decode("utf-8", "ignore")
    codes = {}
    for l in re.findall(r'href="([^"]*andmetyyp=vegetatsioon[^"]*)"', page):
        m = re.search(r"f=vegetatsioon-(.+?)-(\d{4})-(gdb|gpkg)\.zip", html.unescape(l))
        if m:
            codes[m.group(1)] = m.group(2)
    os.makedirs(cache_dir, exist_ok=True)
    json.dump(codes, open(p, "w"), indent=1)
    return codes


def points_csv(name, code, cache_dir):
    """Path of the CSV dump (X, Y, puu_id, puutyyp, korgus, puukroon, als_aasta) for a municipality."""
    csv_path = os.path.join(cache_dir, name, "points.csv")
    if os.path.exists(csv_path):
        return csv_path
    zpath = os.path.join(cache_dir, f"vegetatsioon-{name}-{code}-gpkg.zip")
    if not os.path.exists(zpath):
        log(f"downloading trees for {name}")
        with urllib.request.urlopen(urllib.request.Request(VEG_URL.format(name=urllib.parse.quote(name), code=code), headers=UA), timeout=1800) as r, open(zpath + ".part", "wb") as f:
            shutil.copyfileobj(r, f)
        os.replace(zpath + ".part", zpath)
    d = os.path.join(cache_dir, name)
    os.makedirs(d, exist_ok=True)
    with zipfile.ZipFile(zpath) as z:
        z.extractall(d)
    gpkgs = [os.path.join(dp, f) for dp, _, fs in os.walk(d) for f in fs if f.endswith(".gpkg")]
    if not gpkgs:
        return None
    # a bbox filter on this GeoPackage returns nothing (axis-order quirk); dump everything once and filter here
    import geo
    geo.points_to_csv(gpkgs[0], "yksikpuud_keskpunkt", csv_path, None)
    return csv_path


def fetch(site, root=ROOT):
    site_dir = os.path.join(root, "sites", site)
    m = json.load(open(os.path.join(site_dir, "site.json")))
    tile = m["terrain"]["tile"]
    tdir = os.path.join(root, "assets/terrain", tile)
    meta = json.load(open(os.path.join(tdir, "terrain_meta.json")))
    xmin, ymin, xmax, ymax = meta["xmin"], meta["ymin"], meta["xmax"], meta["ymax"]
    import paths
    cache = paths.raw("trees")
    codes = municipality_codes(cache)
    trees = []
    sources = []
    for name in municipalities(xmin, ymin, xmax, ymax):
        fname = name.replace(" ", "_")
        if fname not in codes:
            log(f"{name}: not in the vegetation dataset (towns flown 2020-2024 only)")
            continue
        csv_path = points_csv(fname, codes[fname], cache)
        if not csv_path:
            continue
        n0 = len(trees)
        with open(csv_path, newline="") as f:
            for row in csv.DictReader(f):
                x = float(row["X"]); y = float(row["Y"])
                if xmin <= x < xmax and ymin <= y < ymax:
                    trees.append([round(x - xmin, 2), round(ymax - y, 2), round(float(row["korgus"]), 1), round(float(row["puukroon"]), 1),
                                  1 if row.get("puutyyp", "").startswith("Okas") else 0])
        if len(trees) > n0:
            sources.append(name)
        log(f"{name}: {len(trees) - n0} trees inside the tile")
    out = os.path.join(tdir, "trees.json")
    if trees:
        json.dump({"source": ATTRIBUTION, "municipalities": sources, "fetched": time.strftime("%Y-%m-%d"), "count": len(trees), "trees": trees}, open(out, "w"))
        con = sum(1 for t in trees if t[4])
        log(f"wrote {os.path.relpath(out, root)}: {len(trees)} trees ({con} conifers, {len(trees) - con} deciduous), heights {min(t[2] for t in trees):.0f}..{max(t[2] for t in trees):.0f} m")
    else:
        if os.path.exists(out):
            os.remove(out)
        log("no measured trees for this tile; the statistical scatter stays")
    return trees


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--site", default="palupera")
    ap.add_argument("--root", default=ROOT)
    a = ap.parse_args()
    fetch(a.site, a.root)
