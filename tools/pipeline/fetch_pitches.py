#!/usr/bin/env python3
"""Sports pitches for a tile from OpenStreetMap (leisure=pitch), for the game to put their goals, nets
and hoops on: the orthophoto already carries the markings, but not a goal you can walk up to
(playtest 2026-09-13, Rovaniemi: "this looks like a football pitch, can you detect from data and add
it?"). Country-neutral: the tile service runs it for every pack.

    python3 tools/pipeline/fetch_pitches.py --site <id> [--root <workspace>]

Writes sites/<site>/pitches.json: {"attribution", "source", "fetched", "pitches": [{id, sport,
surface, name, x, z, length, width, heading, polygon [[x, z]...]}]} in tile metres. `heading` is the
long side's direction in degrees (0 = north, clockwise), `length` and `width` the outline's minimum
rotated rectangle. ODbL: the file carries "© OpenStreetMap contributors", like stops.json.
"""
import argparse, json, math, os, sys, time, urllib.parse, urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paths  # noqa: E402

ROOT = paths.ROOT
OVERPASS = ["https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter"]
UA = {"User-Agent": "vakuraamat-pipeline/0.1 (open-source game; polite, cached)"}
ATTRIBUTION = "Pitches: © OpenStreetMap contributors (ODbL)"


def log(msg):
    print(f"[fetch_pitches] {msg}", flush=True)


def overpass(south, west, north, east, budget=110.0):
    """The pitch outlines under the box. The mirrors in turn until `budget` seconds are spent (the
    public servers answer 504 or time out when busy), inside the tile service's 120 s for the stage."""
    q = f'[out:json][timeout:25];way["leisure"="pitch"]({south:.6f},{west:.6f},{north:.6f},{east:.6f});out body geom;'
    last, t0, i = None, time.time(), 0
    while budget - (time.time() - t0) > 15:
        url = OVERPASS[i % len(OVERPASS)]
        try:
            req = urllib.request.Request(url, data=urllib.parse.urlencode({"data": q}).encode(), headers=UA)
            return json.load(urllib.request.urlopen(req, timeout=min(35.0, budget - (time.time() - t0)))).get("elements", [])
        except Exception as e:  # noqa: BLE001 - the mirror, then another round
            last = e
            log(f"{url.split('/')[2]}: {e}")
        i += 1
        if i % len(OVERPASS) == 0:
            time.sleep(5)
    raise RuntimeError(f"Overpass unavailable: {last}")


def rectangle(pts):
    """(centre x, centre z, length, width, heading in degrees) of a ring's minimum rotated rectangle;
    heading is the long side's direction, 0 = north (-z), clockwise."""
    from shapely.geometry import Polygon
    r = Polygon(pts).minimum_rotated_rectangle
    c = list(r.exterior.coords)[:4]
    sides = [(c[i], c[(i + 1) % 4]) for i in range(2)]
    lens = [math.dist(a, b) for a, b in sides]
    (a, b) = sides[0] if lens[0] >= lens[1] else sides[1]
    dx, dz = b[0] - a[0], b[1] - a[1]
    heading = math.degrees(math.atan2(dx, -dz)) % 180.0   # a pitch has no front: 0..180
    cx, cz = r.centroid.x, r.centroid.y
    return cx, cz, max(lens), min(lens), heading


def fetch(site, root=ROOT):
    import geo
    site_dir = os.path.join(root, "sites", site)
    m = json.load(open(os.path.join(site_dir, "site.json")))
    meta = json.load(open(os.path.join(root, "assets/terrain", m["terrain"]["tile"], "terrain_meta.json")))
    xmin, ymin, xmax, ymax = meta["xmin"], meta["ymin"], meta["xmax"], meta["ymax"]
    corners = geo.transform_points([(xmin, ymin), (xmax, ymin), (xmin, ymax), (xmax, ymax)], 3301, 4326)
    lons = [c[0] for c in corners]; lats = [c[1] for c in corners]
    try:
        ways = overpass(min(lats), min(lons), max(lats), max(lons))
    except Exception as e:  # noqa: BLE001 - an optional layer
        log(str(e))
        return None
    out = []
    for w in ways:
        g = w.get("geometry") or []
        if len(g) < 4:
            continue
        xy = geo.transform_points([(p["lon"], p["lat"]) for p in g], 4326, 3301)
        pts = [(x - xmin, ymax - y) for x, y in xy]
        cx, cz, length, width, heading = rectangle(pts)
        if not (0 <= cx <= xmax - xmin and 0 <= cz <= ymax - ymin) or length < 8:
            continue
        tags = w.get("tags", {})
        out.append({"id": f"osm{w['id']}", "sport": (tags.get("sport") or "").split(";")[0].strip() or None,
                    "surface": tags.get("surface"), "name": tags.get("name"),
                    "x": round(cx, 1), "z": round(cz, 1), "length": round(length, 1), "width": round(width, 1),
                    "heading": round(heading, 1), "polygon": [[round(x, 1), round(z, 1)] for x, z in pts]})
    json.dump({"attribution": ATTRIBUTION, "source": "OpenStreetMap via Overpass (leisure=pitch)", "fetched": time.strftime("%Y-%m-%d"),
               "pitches": out}, open(os.path.join(site_dir, "pitches.json"), "w"), ensure_ascii=False)
    sports = {}
    for p in out:
        sports[p["sport"]] = sports.get(p["sport"], 0) + 1
    log(f"wrote sites/{site}/pitches.json: {len(out)} pitches {sports}")
    return out


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--site", required=True)
    ap.add_argument("--root", default=ROOT)
    a = ap.parse_args()
    sys.exit(0 if fetch(a.site, root=a.root) is not None else 1)
