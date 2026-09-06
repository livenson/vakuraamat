#!/usr/bin/env python3
"""Bus stops for a tile from OpenStreetMap (Overpass: highway=bus_stop nodes), snapped to the ETAK roads.

    python3 tools/pipeline/fetch_stops.py --site kvissentali [--root <workspace>]

Writes sites/<site>/stops.json: {"attribution", "source", "fetched", "stops": [{id, name, x, z, yaw, side,
road_kind, road_name, refs}]} in local metres (x east from the tile's west edge, z south from its north edge).
Each stop is moved onto the nearest road segment's edge: `yaw` is the heading (radians, Godot's -Z forward,
clockwise-positive about Y) a shelter faces to look across that road, `side` +1/-1 which side of the
segment it stands on. WGS84 <-> L-EST97 goes through GDAL's gdaltransform (the pipeline needs GDAL anyway).
Estonia's national stop feed (peatus.ee GTFS) is offline in 2026 and the Tallinn feed covers Harju only, so
OSM is the source; its ODbL licence asks for "© OpenStreetMap contributors" (THIRD_PARTY.md).
"""
import argparse, json, math, os, subprocess, sys, time, urllib.parse, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OVERPASS = ["https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter"]
UA = {"User-Agent": "vakuraamat-pipeline/0.1 (open-source game; polite, cached)"}
ATTRIBUTION = "Bussipeatused: © OpenStreetMap contributors (ODbL)"
KINDS = {"street": 1.0, "road": 1.0, "path": 0.0, "trail": 0.0}   # roads a stop may snap to (weight 0 = never)


def log(msg):
    print(f"[fetch_stops] {msg}", flush=True)


def transform(points, s_srs, t_srs):
    """[(a, b)] through gdaltransform; returns [(x, y)]."""
    if not points:
        return []
    inp = "\n".join(f"{a} {b}" for a, b in points) + "\n"
    out = subprocess.run(["gdaltransform", "-s_srs", s_srs, "-t_srs", t_srs], input=inp, capture_output=True, text=True, check=True).stdout
    return [tuple(float(v) for v in line.split()[:2]) for line in out.strip().splitlines()]


def overpass(south, west, north, east):
    q = f'[out:json][timeout:25];node["highway"="bus_stop"]({south:.6f},{west:.6f},{north:.6f},{east:.6f});out body;'
    last = None
    for url in OVERPASS:
        try:
            req = urllib.request.Request(url, data=urllib.parse.urlencode({"data": q}).encode(), headers=UA)
            return json.load(urllib.request.urlopen(req, timeout=35)).get("elements", [])   # the public servers queue slots for ~30 s
        except Exception as e:  # noqa: BLE001 - try the mirror
            last = e
    raise RuntimeError(f"Overpass unavailable: {last}")


def nearest_segment(p, roads):
    """(score, foot point, segment direction, road, distance) of the closest road segment to local point p."""
    best = (math.inf, None, None, None, math.inf)
    for r in roads:
        if KINDS.get(r.get("kind", "road"), 0.0) <= 0.0:
            continue
        pts = r.get("points", [])
        for i in range(len(pts) - 1):
            ax, az = pts[i][0], pts[i][1]; bx, bz = pts[i + 1][0], pts[i + 1][1]
            dx, dz = bx - ax, bz - az
            l2 = dx * dx + dz * dz
            if l2 < 1e-6:
                continue
            t = max(0.0, min(1.0, ((p[0] - ax) * dx + (p[1] - az) * dz) / l2))
            fx, fz = ax + dx * t, az + dz * t
            d = math.hypot(p[0] - fx, p[1] - fz)
            score = d / max(float(r.get("width", 3.0)), 1.0)   # a wide street beats the driveway beside the stop
            if score < best[0]:
                best = (score, (fx, fz), (dx / math.sqrt(l2), dz / math.sqrt(l2)), r, d)
    return best


def fetch(site, root=ROOT):
    site_dir = os.path.join(root, "sites", site)
    m = json.load(open(os.path.join(site_dir, "site.json")))
    tdir = os.path.join(root, "assets/terrain", m["terrain"]["tile"])
    meta = json.load(open(os.path.join(tdir, "terrain_meta.json")))
    xmin, ymin, xmax, ymax = meta["xmin"], meta["ymin"], meta["xmax"], meta["ymax"]
    corners = transform([(xmin, ymin), (xmax, ymin), (xmin, ymax), (xmax, ymax)], "EPSG:3301", "EPSG:4326")
    lons = [c[0] for c in corners]; lats = [c[1] for c in corners]
    try:
        nodes = overpass(min(lats), min(lons), max(lats), max(lons))
    except Exception as e:  # noqa: BLE001
        log(str(e))
        return []
    roads_path = os.path.join(site_dir, "roads.json")
    roads = json.load(open(roads_path)).get("roads", []) if os.path.exists(roads_path) else []
    xy = transform([(n["lon"], n["lat"]) for n in nodes], "EPSG:4326", "EPSG:3301")
    out = []
    for n, (x, y) in zip(nodes, xy):
        if not (xmin <= x <= xmax and ymin <= y <= ymax):
            continue
        lx, lz = x - xmin, ymax - y
        tags = n.get("tags", {})
        stop = {"id": f"osm{n['id']}", "name": tags.get("name") or "", "x": round(lx, 1), "z": round(lz, 1), "yaw": 0.0, "side": 1,
                "road_kind": None, "road_name": None, "refs": tags.get("route_ref") or ""}
        _, foot, direction, road, d = nearest_segment((lx, lz), roads)
        if road is not None and d < 25.0:
            # stand on the roadside the stop was mapped on, the shelter looking across the road
            nx, nz = -direction[1], direction[0]              # the segment's left normal (in x/z)
            side = 1 if (lx - foot[0]) * nx + (lz - foot[1]) * nz >= 0 else -1
            half = max(float(road.get("width", 3.0)), 1.2) / 2.0
            sx, sz = foot[0] + nx * side * (half + 1.6), foot[1] + nz * side * (half + 1.6)
            to_road = (-nx * side, -nz * side)               # from the shelter towards the road
            stop.update({"x": round(sx, 1), "z": round(sz, 1), "yaw": round(math.atan2(-to_road[0], -to_road[1]), 3), "side": side,
                         "road_kind": road.get("kind"), "road_name": road.get("name")})
        out.append(stop)
    json.dump({"attribution": ATTRIBUTION, "source": "OpenStreetMap via Overpass", "fetched": time.strftime("%Y-%m-%d"), "stops": out},
              open(os.path.join(site_dir, "stops.json"), "w"), ensure_ascii=False)
    log(f"wrote sites/{site}/stops.json: {len(out)} stops ({sum(1 for s in out if s['road_kind'])} on a road)")
    return out


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--site", required=True)
    ap.add_argument("--root", default=ROOT)
    a = ap.parse_args()
    sys.exit(0 if fetch(a.site, root=a.root) is not None else 1)
