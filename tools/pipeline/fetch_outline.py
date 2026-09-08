#!/usr/bin/env python3
"""Estonia's outline for the menu's locator map: where a suggested place actually is.

    python3 tools/pipeline/fetch_outline.py [--tolerance 700] [--min-island 10] [--no-lakes]

Takes the county polygons from Maa-amet's administrative division download (maakond_shp.zip,
cached in data_raw/haldus/), unions them into the coastline, simplifies it to the tolerance a
300-pixel map can show (one pixel is about a kilometre, so 700 m of detail is already invisible)
and drops islands under --min-island km². Peipsi needs nothing: the border runs down the middle of
it, so no county covers the lake and the union's own edge is already its shore. Võrtsjärv is inside
a county, so it comes from the ETAK standing-water layer, which holds it in map-sheet pieces that
are unioned back together.

Writes assets/data/estonia.json: {"attribution", "source", "fetched", "bounds": [xmin, ymin, xmax,
ymax], "land": [[[x, y], ...], ...], "lakes": [...]} in L-EST97 metres, rounded to whole metres and
largest ring first. Re-run it only when the outline should follow a new administrative division;
the file is small and committed.
"""
import argparse, datetime, json, os, sys, urllib.parse, urllib.request, zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import geo   # noqa: E402
import paths   # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
COUNTIES = "https://geoportaal.maaamet.ee/docs/haldus_asustus/maakond_shp.zip"
WFS = "https://gsavalik.envir.ee/geoserver/etak/wfs"
LAKES = ["Võrtsjärv"]
ATTRIBUTION = "Haldusjaotus ja siseveekogud: Maa- ja Ruumiamet, Eesti topograafia andmekogu"
UA = {"User-Agent": "vakuraamat-pipeline/0.1 (open-source game; polite, cached)"}


def log(msg):
    print(f"[fetch_outline] {msg}", flush=True)


def counties():
    """The county polygons (shapely), downloading and caching the shapefile."""
    d = paths.raw("haldus")
    zip_path = os.path.join(d, "maakond_shp.zip")
    if not os.path.exists(zip_path):
        log(f"downloading {COUNTIES}")
        req = urllib.request.Request(COUNTIES, headers=UA)
        with urllib.request.urlopen(req, timeout=180) as r, open(zip_path, "wb") as f:
            f.write(r.read())
    shp = os.path.join(d, "maakond.shp")
    if not os.path.exists(shp):
        with zipfile.ZipFile(zip_path) as z:
            z.extractall(d)
    return [g for _p, g in geo.features(shp) if g is not None]


def lake(name):
    """One named standing water body (ETAK WFS), its map-sheet pieces unioned, or None."""
    import shapely
    from shapely.ops import unary_union
    q = urllib.parse.urlencode({
        "service": "WFS", "version": "2.0.0", "request": "GetFeature", "typeNames": "etak:e_202_seisuveekogu_a",
        "srsName": "EPSG:3301", "outputFormat": "application/json", "count": 200, "CQL_FILTER": f"nimetus='{name}'"})
    log(f"{name}: asking the ETAK water layer")
    req = urllib.request.Request(f"{WFS}?{q}", headers=UA)
    with urllib.request.urlopen(req, timeout=180) as r:
        fc = json.load(r)
    parts = [shapely.geometry.shape(f["geometry"]) for f in fc.get("features", [])]
    return unary_union(parts) if parts else None


def rings(geom, tolerance, min_area):
    """Exterior rings of a (multi)polygon, simplified, big ones first: [[(x, y), ...], ...]."""
    import shapely
    out = []
    parts = list(geom.geoms) if hasattr(geom, "geoms") else [geom]
    for p in parts:
        if p.area < min_area:
            continue
        s = p.simplify(tolerance, preserve_topology=True)
        if s.is_empty or not isinstance(s, shapely.geometry.Polygon):
            continue
        out.append((p.area, [(round(x), round(y)) for x, y in s.exterior.coords]))
    out.sort(key=lambda a: -a[0])
    return [r for _a, r in out]


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--tolerance", type=float, default=700.0, help="simplification in metres (default 700)")
    ap.add_argument("--min-island", type=float, default=10.0, help="smallest island kept, km² (default 10)")
    ap.add_argument("--no-lakes", action="store_true", help="coastline only")
    ap.add_argument("--out", default=os.path.join(ROOT, "assets", "data", "estonia.json"))
    a = ap.parse_args(argv)
    from shapely.ops import unary_union
    land = unary_union(counties())
    log(f"{len(list(land.geoms)) if hasattr(land, 'geoms') else 1} land parts, bounds {tuple(round(v) for v in land.bounds)}")
    out = {
        "attribution": ATTRIBUTION,
        "source": COUNTIES,
        "fetched": datetime.date.today().isoformat(),
        "bounds": [round(v) for v in land.bounds],
        "land": rings(land, a.tolerance, a.min_island * 1e6),
        "lakes": [],
    }
    if not a.no_lakes:
        for name in LAKES:
            g = lake(name)
            if g is None:
                log(f"{name}: nothing came back, left off the map")
                continue
            out["lakes"] += rings(g, a.tolerance, 20e6)
            log(f"{name}: {round(g.area / 1e6)} km²")
    with open(a.out, "w") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
    log(f"{a.out}: {len(out['land'])} land rings, {len(out['lakes'])} lakes, "
        f"{sum(len(r) for r in out['land'] + out['lakes'])} points, {os.path.getsize(a.out) // 1024} kB")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
