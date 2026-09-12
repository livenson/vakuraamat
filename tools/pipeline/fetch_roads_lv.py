#!/usr/bin/env python3
"""Roads, streets, paths and trails for a Latvian tile from OpenStreetMap (docs/latvia-plan.md, step 5).
Latvia's own street register (VZD `Ielas`) names the centrelines but gives no class or width, so the
lines come from OpenStreetMap through Overpass, into the same roads.json the ETAK fetch writes.

    python3 tools/pipeline/fetch_roads_lv.py --site riga_vecpilseta

Writes sites/<site>/roads.json: {"attribution", "source", "fetched", "roads": [{id, kind, type, width,
surface, name, traffic, points [[x, z]...]}]} in tile metres. The game's kinds:
  street  paved roads cars use (motorway .. residential, living streets, service roads)
  road    unpaved roads (gravel, dirt, compacted)
  path    footways, cycleways, steps and pedestrian streets (the Old Town's lanes: no cars)
  trail   tracks
The road graph (scripts/world/road_graph.gd) joins edges only at their ends, and an OpenStreetMap way
often runs through a crossing without ending there, so every way is split at each node another way
shares. Lines are cut where they leave the tile by more than 40 m. ODbL: the file carries
"© OpenStreetMap contributors" like stops.json.
"""
import argparse, json, os, sys, time, urllib.parse, urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import geo  # noqa: E402
import paths  # noqa: E402

OVERPASS = ["https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter"]
UA = {"User-Agent": "vakuraamat-pipeline/0.1 (open-source game; polite, cached)"}
ATTRIBUTION = "Ceļi un ielas: © OpenStreetMap contributors (ODbL)"
MARGIN_M = 40.0
SKIP = {"construction", "proposed", "planned", "platform", "corridor", "raceway", "bus_stop", "elevator", "abandoned", "razed",
        "disused", "rest_area", "services", "emergency_bay"}
PATHS = {"footway", "cycleway", "path", "steps", "pedestrian", "bridleway"}
UNPAVED = {"gravel", "unpaved", "compacted", "dirt", "ground", "fine_gravel", "grass", "sand", "earth", "mud", "pebblestone", "woodchips"}
WIDTH = {"motorway": 14.0, "trunk": 12.0, "primary": 12.0, "secondary": 10.0, "tertiary": 8.0, "unclassified": 6.0, "residential": 6.0,
         "living_street": 5.0, "service": 3.5, "road": 6.0, "pedestrian": 6.0, "footway": 2.0, "cycleway": 2.0, "path": 1.5,
         "steps": 2.0, "bridleway": 2.0, "track": 3.0}


def log(msg):
    print(f"[fetch_roads_lv] {msg}", flush=True)


def overpass(south, west, north, east):
    q = f'[out:json][timeout:90];way["highway"]({south:.6f},{west:.6f},{north:.6f},{east:.6f});out body geom;'
    last = None
    for url in OVERPASS:
        try:
            req = urllib.request.Request(url, data=urllib.parse.urlencode({"data": q}).encode(), headers=UA)
            return json.load(urllib.request.urlopen(req, timeout=120)).get("elements", [])
        except Exception as e:  # noqa: BLE001 - try the mirror
            last = e
    raise RuntimeError(f"Overpass unavailable: {last}")


def kind_of(tags):
    hw = tags.get("highway", "")
    if hw in PATHS:
        return "path"
    if hw == "track":
        return "trail"
    return "road" if tags.get("surface") in UNPAVED else "street"


def width_of(tags):
    hw = tags.get("highway", "")
    try:
        w = float(str(tags.get("width", "")).replace(",", ".").split()[0])
        if 0.5 < w < 60:
            return w
    except (ValueError, IndexError):
        pass
    try:
        lanes = int(str(tags.get("lanes", "")).split(";")[0])
        if 0 < lanes < 12:
            return lanes * 3.2
    except ValueError:
        pass
    return WIDTH.get(hw, WIDTH.get(hw.replace("_link", ""), 6.0) if hw.endswith("_link") else 4.0)


def fetch(site, root=paths.ROOT):
    site_dir = os.path.join(root, "sites", site)
    m = json.load(open(os.path.join(site_dir, "site.json")))
    meta = json.load(open(os.path.join(root, "assets/terrain", m["terrain"]["tile"], "terrain_meta.json")))
    xmin, ymin, xmax, ymax = meta["xmin"], meta["ymin"], meta["xmax"], meta["ymax"]
    corners = geo.transform_points([(xmin - MARGIN_M, ymin - MARGIN_M), (xmax + MARGIN_M, ymin - MARGIN_M),
                                    (xmin - MARGIN_M, ymax + MARGIN_M), (xmax + MARGIN_M, ymax + MARGIN_M)], 3301, 4326)
    lons, lats = [c[0] for c in corners], [c[1] for c in corners]
    ways = [w for w in overpass(min(lats), min(lons), max(lats), max(lons))
            if w.get("type") == "way" and w.get("geometry") and w.get("tags", {}).get("highway") not in SKIP
            and w.get("tags", {}).get("area") != "yes"]
    # every node's tile position, and how many ways use it (a crossing is a node two ways share)
    uses, pos = {}, {}
    flat = [(g["lon"], g["lat"]) for w in ways for g in w["geometry"]]
    xy = geo.transform_points(flat, 4326, 3301) if flat else []
    i = 0
    for w in ways:
        for nid, (x, y) in zip(w["nodes"], xy[i:i + len(w["geometry"])]):
            pos[nid] = (round(x - xmin, 1), round(ymax - y, 1))
            uses[nid] = uses.get(nid, 0) + 1
        i += len(w["geometry"])
        for nid in set(w["nodes"][1:-1]) & {w["nodes"][0], w["nodes"][-1]}:
            uses[nid] += 1   # a way that loops back onto itself meets itself there

    size_x, size_z = xmax - xmin, ymax - ymin

    def inside(p):
        return -MARGIN_M <= p[0] <= size_x + MARGIN_M and -MARGIN_M <= p[1] <= size_z + MARGIN_M

    out = []
    for w in ways:
        tags = w.get("tags", {})
        nodes = w["nodes"]
        cuts = [0] + [k for k in range(1, len(nodes) - 1) if uses.get(nodes[k], 0) >= 2] + [len(nodes) - 1]
        part = 0
        for a, b in zip(cuts, cuts[1:]):
            run = []
            for nid in nodes[a:b + 1]:
                p = pos[nid]
                if inside(p):
                    run.append(list(p))
                elif len(run) >= 2:
                    break      # the rest of this piece lies outside the margin
                else:
                    run = []
            if len(run) < 2:
                continue
            out.append({"id": w["id"] * 1000 + part, "kind": kind_of(tags), "type": tags.get("highway"), "width": round(width_of(tags), 1),
                        "surface": tags.get("surface"), "name": tags.get("name"), "traffic": tags.get("access") or tags.get("motor_vehicle"),
                        "points": run})
            part += 1
    json.dump({"attribution": ATTRIBUTION, "source": "OpenStreetMap via Overpass", "fetched": time.strftime("%Y-%m-%d"), "roads": out},
              open(os.path.join(site_dir, "roads.json"), "w"), ensure_ascii=False)
    kinds = {}
    for r in out:
        kinds[r["kind"]] = kinds.get(r["kind"], 0) + 1
    log(f"wrote sites/{site}/roads.json: {len(out)} segments from {len(ways)} ways {kinds}")
    return out


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--site", required=True)
    ap.add_argument("--root", default=paths.ROOT)
    a = ap.parse_args()
    fetch(a.site, a.root)
