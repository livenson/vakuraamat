#!/usr/bin/env python3
"""A tile's street furniture, barriers, single trees, shops and rails from OpenStreetMap, in one
Overpass query. Country-neutral: the tile service runs it for every pack after the registers.

    python3 tools/pipeline/fetch_osm.py --site <id> [--root <workspace>]

Writes, each its own file so ODbL's share-alike stays on it and never reaches the register data
(THIRD_PARTY.md; every file carries "© OpenStreetMap contributors"):

  sites/<site>/street.json   lamps [[x, z]], signals [[x, z]], crossings [{x, z, kind, marked}],
                             furniture [{kind, x, z, dir}] (bench, bin, bike_rack, bollard, block, gate),
                             barriers [{kind, height, points}] (fence, hedge, wall, retaining_wall, city_wall,
                             guard_rail), flowerbeds [[[x, z]...]], piers [{area, width, points}]
  sites/<site>/rail.json     tracks [{id, kind, gauge, embedded, bridge, points}] (tram, rail, light_rail,
                             narrow_gauge), split where two tracks share a node; stops [{kind, name, x, z}]
  sites/<site>/pois.json     pois [{id, key, type, name, brand, opening_hours, website, level, x, z,
                             entrance, building, tenant, vacant}]: shops, cafés, offices, hotels. `building`
                             is the buildings.json id the point stands in (or beside, within 8 m),
                             `tenant` the registry code of the company on that building whose name the
                             point's name or brand matches
  assets/terrain/<tile>/trees_osm.json   {"source", "partial": true, "trees": [[x, z, height, crown, conifer]]}
                             like trees.json, but only the trees someone mapped: the terrain builder
                             places them and keeps its statistical trees around them. Height from the
                             tile's canopy model where it sees the crown, else the tag, else a default

Coordinates are tile metres (x east from the tile's west edge, z south from its north edge).
"""
import argparse, json, math, os, re, sys, time, urllib.parse, urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paths  # noqa: E402

ROOT = paths.ROOT
OVERPASS = ["https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter"]
UA = {"User-Agent": "vakuraamat-pipeline/0.1 (open-source game; polite, cached)"}
CREDIT = "© OpenStreetMap contributors (ODbL)"
MARGIN_M = 30.0          # lines are kept this far past the tile's edge, so a fence or a track does not stop short
POI_AMENITY = "restaurant|cafe|bar|pub|fast_food|pharmacy|bank|ice_cream|nightclub|biergarten|food_court|fuel|car_wash|marketplace|cinema|theatre|dentist|doctors|clinic|veterinary"
BARRIER_WAYS = {"fence", "hedge", "wall", "retaining_wall", "city_wall", "guard_rail", "jersey_barrier"}
BARRIER_NODES = {"bollard": "bollard", "block": "block", "gate": "gate", "lift_gate": "gate", "swing_gate": "gate"}
TRACKS = {"tram", "rail", "light_rail", "narrow_gauge", "subway"}
GAUGE = {"tram": 1435, "light_rail": 1435, "rail": 1520, "narrow_gauge": 750, "subway": 1522}
CONIFERS = {"pinus", "picea", "abies", "larix", "thuja", "juniperus", "taxus", "pseudotsuga", "tsuga", "chamaecyparis"}
LEGAL = {"oü", "ou", "as", "mtü", "fie", "sa", "tü", "uü", "sia", "ps", "ik", "biedrība", "oy", "oyj", "ab", "ky", "tmi", "ry",
         "ltd", "llc", "gmbh", "uab", "aktsiaselts", "osaühing", "osauhing", "filiaal", "branch"}


def log(msg):
    print(f"[fetch_osm] {msg}", flush=True)


def query(bb):
    return f"""[out:json][timeout:120];
(
  node["highway"~"^(street_lamp|traffic_signals|crossing)$"]({bb});
  node["amenity"~"^(bench|waste_basket|bicycle_parking)$"]({bb});
  node["barrier"]({bb});
  way["barrier"]({bb});
  node["natural"="tree"]({bb});
  way["natural"="tree_row"]({bb});
  way["landuse"="flowerbed"]({bb});
  way["man_made"="pier"]({bb});
  way["railway"]({bb});
  node["railway"~"^(tram_stop|halt|station|stop)$"]({bb});
  node["public_transport"="stop_position"]["tram"="yes"]({bb});
  nwr["shop"]({bb});
  nwr["amenity"~"^({POI_AMENITY})$"]({bb});
  nwr["office"]["name"]({bb});
  nwr["craft"]["name"]({bb});
  nwr["tourism"~"^(hotel|hostel|guest_house|motel)$"]({bb});
  nwr["leisure"~"^(fitness_centre|sauna|escape_game|amusement_arcade)$"]["name"]({bb});
  node["entrance"]({bb});
);
out body geom;"""


def overpass(bb, budget=170.0):
    """Everything under the box in one answer. The mirrors in turn until `budget` seconds are spent
    (the public servers answer 504 or time out when busy), inside the tile service's 180 s."""
    q = query(bb)
    last, t0, i = None, time.time(), 0
    while budget - (time.time() - t0) > 20:
        url = OVERPASS[i % len(OVERPASS)]
        try:
            req = urllib.request.Request(url, data=urllib.parse.urlencode({"data": q}).encode(), headers=UA)
            return json.load(urllib.request.urlopen(req, timeout=min(130.0, budget - (time.time() - t0)))).get("elements", [])
        except Exception as e:  # noqa: BLE001 - the mirror, then another round
            last = e
            log(f"{url.split('/')[2]}: {e}")
        i += 1
        if i % len(OVERPASS) == 0:
            time.sleep(8)
    raise RuntimeError(f"Overpass unavailable: {last}")


def number(v):
    """A tag's number ("2.5", "2,5 m", "3;4" -> the first), or None."""
    if v is None:
        return None
    m = re.match(r"\s*(-?\d+(?:[.,]\d+)?)", str(v))
    return float(m.group(1).replace(",", ".")) if m else None


def norm(name):
    """A company or shop name for comparing: lower case, no quotes or punctuation, no legal form."""
    s = re.sub(r"[\"'„“”«»‚‘’().,&/+-]", " ", str(name or "").lower())
    return [t for t in s.split() if t and t not in LEGAL]


def name_score(cands, tenant):
    """How well any of a point's names fits a company's: 1 when one contains the other (Rimi in
    "Rimi Eesti Food AS"), else the share of words they have in common."""
    tt = norm(tenant)
    ts = " ".join(tt)
    best = 0.0
    for c in cands:
        ct = norm(c)
        cs = " ".join(ct)
        if len(cs) >= 3 and ts and (cs in ts or ts in cs):
            return 1.0
        if ct and tt:
            best = max(best, len(set(ct) & set(tt)) / len(set(ct) | set(tt)))
    return best


def split_at_shared(ways, pos, inside):
    """[(way, [[x, z]...])]: each way cut at every node another kept way uses, and to the stretch that
    lies inside the margin (as fetch_roads_lv does for roads, so a graph can branch there)."""
    uses = {}
    for w in ways:
        for nid in w["nodes"]:
            uses[nid] = uses.get(nid, 0) + 1
    out = []
    for w in ways:
        nodes = w["nodes"]
        cuts = [0] + [k for k in range(1, len(nodes) - 1) if uses.get(nodes[k], 0) >= 2] + [len(nodes) - 1]
        for a, b in zip(cuts, cuts[1:]):
            run = []
            for nid in nodes[a:b + 1]:
                p = pos[nid]
                if inside(p):
                    run.append(list(p))
                elif len(run) >= 2:
                    break
                else:
                    run = []
            if len(run) >= 2:
                out.append((w, run))
    return out


def fetch(site, root=ROOT):
    import geo
    import numpy as np
    from shapely.geometry import Point, Polygon
    site_dir = os.path.join(root, "sites", site)
    m = json.load(open(os.path.join(site_dir, "site.json")))
    tile = m["terrain"]["tile"]
    tdir = os.path.join(root, "assets/terrain", tile)
    meta = json.load(open(os.path.join(tdir, "terrain_meta.json")))
    xmin, ymin, xmax, ymax = meta["xmin"], meta["ymin"], meta["xmax"], meta["ymax"]
    size_x, size_z = xmax - xmin, ymax - ymin
    corners = geo.transform_points([(xmin - MARGIN_M, ymin - MARGIN_M), (xmax + MARGIN_M, ymin - MARGIN_M),
                                    (xmin - MARGIN_M, ymax + MARGIN_M), (xmax + MARGIN_M, ymax + MARGIN_M)], 3301, 4326)
    lons, lats = [c[0] for c in corners], [c[1] for c in corners]
    bb = f"{min(lats):.6f},{min(lons):.6f},{max(lats):.6f},{max(lons):.6f}"
    try:
        els = overpass(bb)
    except Exception as e:  # noqa: BLE001 - an optional layer: the pack goes without it
        log(str(e))
        return None

    # every coordinate to tile metres in one transform
    flat, spans = [], []
    for e in els:
        if e["type"] == "node":
            pts = [(e["lon"], e["lat"])]
        elif e.get("geometry"):
            pts = [(g["lon"], g["lat"]) for g in e["geometry"] if g]
        elif e.get("bounds"):
            b = e["bounds"]
            pts = [((b["minlon"] + b["maxlon"]) / 2, (b["minlat"] + b["maxlat"]) / 2)]
        else:
            pts = []
        spans.append((len(flat), len(pts)))
        flat.extend(pts)
    xy = geo.transform_points(flat, 4326, 3301) if flat else []
    tile_pts = [(round(x - xmin, 2), round(ymax - y, 2)) for x, y in xy]
    node_pos = {}
    for e, (s, n) in zip(els, spans):
        e["_pts"] = tile_pts[s:s + n]
        if e["type"] == "way" and len(e.get("nodes", [])) == n:
            for nid, p in zip(e["nodes"], e["_pts"]):
                node_pos[nid] = p

    def on_tile(p, margin=0.0):
        return -margin <= p[0] <= size_x + margin and -margin <= p[1] <= size_z + margin

    def r1(p):
        return [round(p[0], 1), round(p[1], 1)]

    street = {"lamps": [], "signals": [], "crossings": [], "furniture": [], "barriers": [], "flowerbeds": [], "piers": []}
    tracks, stops, pois, entrances, trees, rows = [], [], [], [], [], []
    for e in els:
        t = e.get("tags", {})
        pts = e.get("_pts") or []
        if not pts:
            continue
        if e["type"] == "node":
            p = pts[0]
            if not on_tile(p):
                continue
            hw = t.get("highway")
            if hw == "street_lamp":
                street["lamps"].append(r1(p))
            elif hw == "traffic_signals":
                street["signals"].append(r1(p))
            elif hw == "crossing":
                kind = t.get("crossing") or ("traffic_signals" if t.get("crossing_ref") == "tiger" else None)
                marks = t.get("crossing:markings")
                marked = (marks not in (None, "no")) if marks is not None else kind in ("traffic_signals", "marked", "zebra", "uncontrolled")
                street["crossings"].append({"x": r1(p)[0], "z": r1(p)[1], "kind": kind, "marked": bool(marked)})
            am = t.get("amenity")
            if am in ("bench", "waste_basket", "bicycle_parking"):
                kind = {"bench": "bench", "waste_basket": "bin", "bicycle_parking": "bike_rack"}[am]
                street["furniture"].append({"kind": kind, "x": r1(p)[0], "z": r1(p)[1], "dir": number(t.get("direction")),
                                            "capacity": number(t.get("capacity")) if kind == "bike_rack" else None})
            if t.get("barrier") in BARRIER_NODES:
                street["furniture"].append({"kind": BARRIER_NODES[t["barrier"]], "x": r1(p)[0], "z": r1(p)[1], "dir": None, "capacity": None})
            if t.get("natural") == "tree":
                trees.append((p, t))
            rw = t.get("railway")
            if rw == "tram_stop" or (t.get("public_transport") == "stop_position" and t.get("tram") == "yes"):
                stops.append({"kind": "tram", "name": t.get("name"), "x": r1(p)[0], "z": r1(p)[1]})
            elif rw in ("halt", "station", "stop") and t.get("tram") != "yes" and t.get("subway") != "yes":
                stops.append({"kind": "train", "name": t.get("name"), "x": r1(p)[0], "z": r1(p)[1]})
            if "entrance" in t:
                entrances.append((p, t.get("entrance")))
        if e["type"] == "way":
            closed = len(e.get("nodes", [])) > 3 and e["nodes"][0] == e["nodes"][-1]
            if t.get("barrier") in BARRIER_WAYS and any(on_tile(q, MARGIN_M) for q in pts):
                street["barriers"].append({"kind": t["barrier"], "height": number(t.get("height")), "material": t.get("material"),
                                           "points": [r1(q) for q in pts]})
            if t.get("landuse") == "flowerbed" and closed and any(on_tile(q) for q in pts):
                street["flowerbeds"].append([r1(q) for q in pts[:-1]])
            if t.get("man_made") == "pier" and any(on_tile(q, MARGIN_M) for q in pts):
                area = closed and t.get("area") != "no"
                street["piers"].append({"area": area, "width": number(t.get("width")) or 2.5, "points": [r1(q) for q in (pts[:-1] if area else pts)]})
            if t.get("natural") == "tree_row":
                rows.append(pts)
            if t.get("railway") in TRACKS and t.get("tunnel") not in ("yes", "building_passage") and (number(t.get("layer")) or 0) >= 0:
                tracks.append(e)
        # shops, cafés, offices (a node, or a building or area carrying the tags)
        key = next((k for k in ("shop", "amenity", "office", "craft", "tourism", "leisure") if k in t), None)
        if key and (key != "amenity" or re.match(f"^({POI_AMENITY})$", t[key])) and (key != "leisure" or t.get("name")):
            c = pts[0] if len(pts) == 1 else (sum(q[0] for q in pts) / len(pts), sum(q[1] for q in pts) / len(pts))
            if on_tile(c):
                pois.append({"id": f"osm{e['type'][0]}{e['id']}", "key": key, "type": t[key], "name": t.get("name"), "brand": t.get("brand"),
                             "operator": t.get("operator"), "opening_hours": t.get("opening_hours"), "website": t.get("website") or t.get("contact:website"),
                             "level": t.get("level"), "x": round(c[0], 1), "z": round(c[1], 1), "entrance": None, "building": None, "tenant": None,
                             "vacant": t.get(key) == "vacant" or "disused:shop" in t})

    # --- rails: tracks split where they meet, so trams can take a branch -------------------------
    kept = [w for w in tracks if all(n in node_pos for n in w.get("nodes", []))]
    rail_out = []
    for w, run in split_at_shared(kept, node_pos, lambda p: on_tile(p, MARGIN_M)):
        t = w.get("tags", {})
        kind = t["railway"]
        embedded = t.get("embedded") in ("yes", "partial") or t.get("embedded_rails") is not None
        if kind == "tram" and t.get("embedded") != "no":
            embedded = True   # a tram track runs in the street unless the map says it has its own bed
        rail_out.append({"id": f"osm{w['id']}_{len(rail_out)}", "kind": kind, "gauge": int(number(str(t.get("gauge", "")).split(";")[0]) or GAUGE[kind]),
                         "embedded": embedded, "bridge": t.get("bridge") not in (None, "no"), "name": t.get("name"),
                         "points": [r1(q) for q in run]})
    seen = []
    for s in stops:   # a stop mapped as a platform node and a stop position: once
        if not any(o["kind"] == s["kind"] and math.dist((o["x"], o["z"]), (s["x"], s["z"])) < 15 and o["name"] == s["name"] for o in seen):
            seen.append(s)
    stops = seen

    # --- trees: height from the canopy model where it sees the crown ------------------------------
    canopy = None
    if meta.get("canopy"):
        cpath = os.path.join(tdir, meta["canopy"]["file"])
        if os.path.exists(cpath):
            n = int(meta["size_px"])
            canopy = np.fromfile(cpath, "<f4").reshape(n, n)
    px = float(meta.get("size_m", size_x)) / float(meta.get("size_px", 1024))

    def canopy_at(p, r=2.0):
        if canopy is None:
            return 0.0
        n = canopy.shape[0]
        c0, r0 = int(p[0] / px), int(p[1] / px)
        k = max(1, int(r / px))
        win = canopy[max(r0 - k, 0):min(r0 + k + 1, n), max(c0 - k, 0):min(c0 + k + 1, n)]
        return float(win.max()) if win.size else 0.0

    tree_rows = []
    for p, t in trees:
        tree_rows.append((p, t))
    for pts in rows:   # a mapped row of trees: one every 8 m along it
        for a, b in zip(pts, pts[1:]):
            d = math.dist(a, b)
            for k in range(max(1, int(d / 8.0))):
                q = (a[0] + (b[0] - a[0]) * k * 8.0 / max(d, 0.01), a[1] + (b[1] - a[1]) * k * 8.0 / max(d, 0.01))
                if on_tile(q):
                    tree_rows.append((q, {}))
    tree_out = []
    for p, t in tree_rows:
        genus = str(t.get("genus", "")).lower()
        conifer = t.get("leaf_type") == "needleleaved" or genus in CONIFERS or str(t.get("species", "")).split(" ")[0].lower() in CONIFERS
        seen_h = canopy_at(p)
        h = seen_h if seen_h >= 3.0 else (number(t.get("height")) or (12.0 if conifer else 9.0))
        crown = number(t.get("diameter_crown")) or max(3.0, h * 0.55)
        tree_out.append([round(p[0], 1), round(p[1], 1), round(h, 1), round(crown, 1), 1 if conifer else 0])

    # --- shops: the building each stands in, its door, the company the names agree on -------------
    bpath = os.path.join(site_dir, "buildings.json")
    blds = json.load(open(bpath)).get("buildings", []) if os.path.exists(bpath) else []
    polys = []
    for b in blds:
        poly = b.get("polygon") or []
        if len(poly) >= 3:
            try:
                polys.append((b, Polygon(poly).buffer(0)))
            except Exception:  # noqa: BLE001 - a broken ring
                pass
    tpath = os.path.join(site_dir, "tenants.json")
    tenants = [r for r in (json.load(open(tpath)).get("tenants", []) if os.path.exists(tpath) else []) if r.get("match") == "exact"]
    by_bld, by_unit = {}, {}
    for r in tenants:
        if r.get("building_id") is not None:
            by_bld.setdefault(str(r["building_id"]), []).append(r)
        if r.get("tunnus"):
            by_unit.setdefault(str(r["tunnus"]), []).append(r)
    matched = 0
    for poi in pois:
        pt = Point(poi["x"], poi["z"])
        home, best_d = None, 8.0
        for b, poly in polys:
            if poly.contains(pt):
                home, best_d = b, 0.0
                break
            d = poly.distance(pt)
            if d < best_d:
                home, best_d = b, d
        if home is not None:
            poi["building"] = home["id"]
        doors = sorted(((math.dist(q, (poi["x"], poi["z"])), q, kind) for q, kind in entrances), key=lambda x: (x[0], x[2] != "main"))
        if doors and doors[0][0] <= 25.0:
            poi["entrance"] = r1(doors[0][1])
        if home is None:
            continue
        cands = [c for c in (poi["name"], poi["brand"], poi["operator"]) if c]
        rows_here = list(by_bld.get(str(home["id"]), []))
        for unit in home.get("cadastral") or []:
            rows_here += [r for r in by_unit.get(str(unit), []) if r not in rows_here]
        best, score = None, 0.5
        for r in rows_here:
            s = name_score(cands, r.get("name", ""))
            if s >= score and (best is None or s > score):
                best, score = r, s
        if best is not None:
            poi["tenant"] = best.get("registry_code")
            matched += 1
        poi.pop("operator", None)
    for poi in pois:
        poi.pop("operator", None)

    stamp = {"source": "OpenStreetMap via Overpass", "fetched": time.strftime("%Y-%m-%d")}
    json.dump({"attribution": f"Street furniture, barriers: {CREDIT}", **stamp, **street},
              open(os.path.join(site_dir, "street.json"), "w"), ensure_ascii=False)
    json.dump({"attribution": f"Rails: {CREDIT}", **stamp, "tracks": rail_out, "stops": stops},
              open(os.path.join(site_dir, "rail.json"), "w"), ensure_ascii=False)
    json.dump({"attribution": f"Shops and opening hours: {CREDIT}", **stamp, "pois": pois},
              open(os.path.join(site_dir, "pois.json"), "w"), ensure_ascii=False)
    json.dump({"source": f"Single trees: {CREDIT}; heights from the tile's canopy model where it sees the crown", "fetched": stamp["fetched"],
               "partial": True, "count": len(tree_out), "trees": tree_out}, open(os.path.join(tdir, "trees_osm.json"), "w"))
    log(f"{site}: {len(street['lamps'])} lamps, {len(street['signals'])} signals, {len(street['crossings'])} crossings, "
        f"{len(street['furniture'])} furniture, {len(street['barriers'])} barriers, {len(street['flowerbeds'])} flowerbeds, {len(street['piers'])} piers; "
        f"{len(rail_out)} track pieces, {len(stops)} stops; {len(pois)} shops and offices ({matched} matched to a company); {len(tree_out)} trees")
    return {"street": street, "tracks": rail_out, "pois": pois, "trees": tree_out}


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--site", required=True)
    ap.add_argument("--root", default=ROOT)
    a = ap.parse_args()
    sys.exit(0 if fetch(a.site, root=a.root) is not None else 1)
