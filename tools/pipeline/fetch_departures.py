#!/usr/bin/env python3
"""Bus departures for a tile from GTFS feeds: Estonia's public transport register, and in Latvia the
national bus network (ATD) and Rīgas satiksme (buses and trolleybuses; trams and trains have no
vehicle in the game yet, so their routes are left out).

    python3 tools/pipeline/fetch_departures.py --site kvissentali [--root <workspace>] [--refresh]

Writes sites/<site>/departures.json: {"attribution", "source", "fetched", "feed_version", "stops",
"routes"} in local metres (x east from the tile's west edge, z south from its north edge, the same
frame as stops.json and roads.json). Each route is one line in one direction:
{line, headsign, long_name, shape: [[x, z], ...], calls: [stop id, ...], departures: {weekday|
saturday|sunday: ["HH:MM", ...]}}, where the stop ids are the pack's own OSM ids from stops.json.

Kept deliberately apart from stops.json: that file is derived from OpenStreetMap and carries ODbL's
share-alike, and mixing the two sources in one file would spread it to this one (THIRD_PARTY.md).

Two things about the feed that are easy to get wrong:
  * stops.txt has columns named lest_x and lest_y that hold the NORTHING and the EASTING, in that
    order. Read them as x and y and every stop lands outside the tile.
  * shapes.txt carries lat/lon only, so route geometry goes through pyproj like everything else.
The national file covers the whole country in one 52 MB zip, cached for a week under data_raw/gtfs.
The Latvian feeds use stop_lat/stop_lon; ATD's pads every column name and value with a space, so rows
are stripped; Rīgas satiksme publishes a new zip every month, looked up through data.gov.lv's API.
"""
import argparse, csv, io, json, math, os, sys, time, urllib.request, zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paths  # noqa: E402

ROOT = paths.ROOT
# The register's own feed. Its official direct download moved to a page that serves an application
# shell; this mirror carries the same file, and feed_info.txt names the publisher to credit.
FEED = "https://eu-gtfs.remix.com/estonia_unified_gtfs.zip"
UA = {"User-Agent": "vakuraamat-pipeline/0.1 (open-source digital twin; polite, cached)"}
ATTRIBUTION = "Ühistranspordiregistri avaandmed: Regionaal- ja Põllumajandusministeerium (peatus.ee)"
# Latvia's feeds (CC0), docs/latvia-plan.md step 5
LV_FEEDS = [
    {"id": "lv_atd", "url": "https://www.atd.lv/sites/default/files/GTFS/gtfs-latvia-lv.zip",
     "attribution": "Autotransporta direkcija (ATD), reģionālo autobusu GTFS (CC0)"},
    {"id": "lv_rigas_satiksme", "ckan": "marsrutu-saraksti-rigas-satiksme-sabiedriskajam-transportam",
     "attribution": "Rīgas satiksme, maršrutu saraksti GTFS (CC0)"},
]
LV_ROUTE_TYPES = {"3", "11", "700", "701", "702", "704", "711", "715", "800"}   # buses and trolleybuses
MATCH_M = 25.0        # how far a GTFS stop may sit from the pack's OSM stop and still be the same one
MARGIN_M = 40.0       # route geometry kept this far outside the tile, so a bus enters and leaves off-screen


def log(msg):
    print(f"[fetch_departures] {msg}", flush=True)


def download(url, path, max_age_days=7, refresh=False):
    """Fetch `url` to `path` unless a fresh copy (by the sidecar meta) exists. Returns the date."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    meta_path = path + ".meta.json"
    if os.path.exists(path) and os.path.exists(meta_path) and not refresh:
        meta = json.load(open(meta_path))
        age = (time.time() - time.mktime(time.strptime(meta["downloaded"], "%Y-%m-%d"))) / 86400
        if age < max_age_days:
            return meta["downloaded"]
    if os.path.exists(path) and not os.path.exists(meta_path) and not refresh:
        if time.time() - os.path.getmtime(path) < max_age_days * 86400:
            day = time.strftime("%Y-%m-%d", time.localtime(os.path.getmtime(path)))
            json.dump({"downloaded": day, "size": os.path.getsize(path)}, open(meta_path, "w"))
            return day
    log(f"downloading {url}")
    r = urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=900)
    with open(path + ".part", "wb") as f:
        while True:
            chunk = r.read(1 << 20)
            if not chunk:
                break
            f.write(chunk)
    os.replace(path + ".part", path)
    today = time.strftime("%Y-%m-%d")
    json.dump({"downloaded": today, "size": os.path.getsize(path), "last_modified": r.headers.get("Last-Modified")},
              open(meta_path, "w"))
    return today


def rows(zf, name, want=None):
    """The rows of one GTFS table, names and values stripped (ATD writes "stop_id, stop_code, ...").
    `want` keeps only the named columns, which matters for stop_times.txt: it is 217 MB and the
    whole point is never to hold it in memory. A table the feed lacks yields nothing."""
    if name not in zf.namelist():
        return
    with zf.open(name) as raw:
        rd = csv.reader(io.TextIOWrapper(raw, encoding="utf-8-sig", newline=""))
        head = [h.strip().lstrip("\ufeff") for h in next(rd, [])]
        pick = [head.index(k) for k in want if k in head] if want else range(len(head))
        keys = [head[i] for i in pick]
        for r in rd:
            if len(r) >= len(head):
                yield {k: r[i].strip() for k, i in zip(keys, pick)}


def feed_url(feed):
    """A feed's download: its fixed URL, or the newest monthly zip of its data.gov.lv dataset."""
    if feed.get("url"):
        return feed["url"]
    import re
    q = "https://data.gov.lv/dati/api/3/action/package_show?id=" + feed["ckan"]
    res = json.load(urllib.request.urlopen(urllib.request.Request(q, headers=UA), timeout=60))["result"]["resources"]
    dated = []
    for r in res:
        m = re.search(r"(\d\d)_(\d{4})", r["url"])
        if m and r["url"].endswith(".zip"):
            dated.append(((int(m.group(2)), int(m.group(1))), r["url"]))
    return max(dated)[1]


def day_of(service_id, calendar):
    """weekday / saturday / sunday for a service, from the days it runs on."""
    c = calendar.get(service_id)
    if not c:
        return "weekday"
    if any(c[d] == "1" for d in ("monday", "tuesday", "wednesday", "thursday", "friday")):
        return "weekday"
    return "saturday" if c["saturday"] == "1" else "sunday" if c["sunday"] == "1" else "weekday"


def fetch(site, root=ROOT, refresh=False, max_age_days=7):
    """A pack's timetables, from its country's feeds (sources.py: the adapter's departures)."""
    import sources
    m = json.load(open(os.path.join(root, "sites", site, "site.json")))
    return sources.by_id(m.get("country")).departures(site, root, refresh, max_age_days)


def fetch_ee(site, root=ROOT, refresh=False, max_age_days=7):
    """Estonia's national GTFS (the public transport register)."""
    site_dir = os.path.join(root, "sites", site)
    m = json.load(open(os.path.join(site_dir, "site.json")))
    tdir = os.path.join(root, "assets/terrain", m["terrain"]["tile"])
    meta = json.load(open(os.path.join(tdir, "terrain_meta.json")))
    xmin, ymin, xmax, ymax = meta["xmin"], meta["ymin"], meta["xmax"], meta["ymax"]
    stops_path = os.path.join(site_dir, "stops.json")
    if not os.path.exists(stops_path):
        log(f"sites/{site}/stops.json missing (make stops): nothing to hang a timetable on")
        return None
    pack_stops = json.load(open(stops_path)).get("stops", [])

    zip_path = os.path.join(paths.raw("gtfs"), "estonia.zip")
    try:
        download(FEED, zip_path, max_age_days=max_age_days, refresh=refresh)
    except Exception as e:  # noqa: BLE001 - the feed is one optional layer of a pack
        log(f"feed unavailable ({e})")
        return None

    with zipfile.ZipFile(zip_path) as zf:
        feed_version = ""
        for r in rows(zf, "feed_info.txt"):
            feed_version = r.get("feed_version", "")
            break
        # 1. the feed's stops that fall inside the tile, matched to the pack's own OSM stops
        mine, names = {}, {}
        for r in rows(zf, "stops.txt", ("stop_id", "stop_name", "lest_x", "lest_y")):
            try:
                north, east = float(r["lest_x"]), float(r["lest_y"])   # named x/y, hold northing/easting
            except ValueError:
                continue
            lx, lz = east - xmin, ymax - north
            if not (0 <= lx <= xmax - xmin and 0 <= lz <= ymax - ymin):
                continue
            near = min(pack_stops, key=lambda s: math.dist((s["x"], s["z"]), (lx, lz)), default=None)
            if near is None or math.dist((near["x"], near["z"]), (lx, lz)) > MATCH_M:
                continue
            mine[r["stop_id"]] = near["id"]
            names[r["stop_id"]] = r["stop_name"]
        if not mine:
            log(f"no scheduled stop inside {site}'s tile")
            _write(site_dir, site, [], [], feed_version)
            return []
        # 2. the trips calling at them, and when
        calls = {}
        for r in rows(zf, "stop_times.txt", ("trip_id", "stop_id", "departure_time", "stop_sequence")):
            if r["stop_id"] in mine:
                calls.setdefault(r["trip_id"], []).append((int(r["stop_sequence"]), r["stop_id"], r["departure_time"][:5]))
        trips = {r["trip_id"]: r for r in rows(zf, "trips.txt") if r["trip_id"] in calls}
        routes = {r["route_id"]: r for r in rows(zf, "routes.txt")}
        calendar = {r["service_id"]: r for r in rows(zf, "calendar.txt")}
        # 3. one entry per line, direction and route variant
        grouped = {}
        for tid, cs in calls.items():
            t = trips.get(tid)
            if t is None:
                continue
            rt = routes.get(t["route_id"], {})
            key = (rt.get("route_short_name", ""), t.get("trip_headsign", ""), t.get("shape_id", ""))
            g = grouped.setdefault(key, {"long_name": rt.get("route_long_name", ""), "departures": {}, "calls": {}})
            cs.sort()
            g["departures"].setdefault(day_of(t.get("service_id", ""), calendar), set()).add(cs[0][2])
            for seq, sid, _ in cs:
                g["calls"][mine[sid]] = seq
        # 4. the geometry, projected and clipped
        wanted = {k[2] for k in grouped if k[2]}
        pts = {}
        for r in rows(zf, "shapes.txt", ("shape_id", "shape_pt_lat", "shape_pt_lon", "shape_pt_sequence")):
            if r["shape_id"] in wanted:
                pts.setdefault(r["shape_id"], []).append(
                    (int(r["shape_pt_sequence"]), float(r["shape_pt_lat"]), float(r["shape_pt_lon"])))

    import geo
    flat = [(lon, lat) for sid in sorted(pts) for _, lat, lon in sorted(pts[sid])]
    projected = geo.transform_points(flat, "4326", "3301") if flat else []
    at = 0
    shapes = {}
    for sid in sorted(pts):
        n = len(pts[sid])
        poly = []
        for x, y in projected[at:at + n]:
            lx, lz = round(x - xmin, 1), round(ymax - y, 1)
            if -MARGIN_M <= lx <= xmax - xmin + MARGIN_M and -MARGIN_M <= lz <= ymax - ymin + MARGIN_M:
                poly.append([lx, lz])
        shapes[sid] = poly
        at += n

    out_routes = []
    for (line, headsign, shape), g in sorted(grouped.items()):
        poly = shapes.get(shape, [])
        if len(poly) < 2:
            continue   # the variant's geometry does not cross this tile: nothing to drive
        out_routes.append({
            "line": line, "headsign": headsign, "long_name": g["long_name"], "shape": poly,
            "calls": [s for s, _ in sorted(g["calls"].items(), key=lambda kv: kv[1])],
            "departures": {d: sorted(v) for d, v in sorted(g["departures"].items())}})
    out_stops = [{"gtfs_id": g, "stop": s, "name": names[g]} for g, s in sorted(mine.items())]
    _write(site_dir, site, out_stops, out_routes, feed_version)
    return out_routes


def fetch_lv(site, root=ROOT, refresh=False, max_age_days=7):
    """The Latvian feeds, each read like the Estonian one and merged: the stops matched to the pack's
    OpenStreetMap stops, one route per line, direction and variant, buses and trolleybuses only."""
    import geo
    site_dir = os.path.join(root, "sites", site)
    m = json.load(open(os.path.join(site_dir, "site.json")))
    meta = json.load(open(os.path.join(root, "assets/terrain", m["terrain"]["tile"], "terrain_meta.json")))
    xmin, ymin, xmax, ymax = meta["xmin"], meta["ymin"], meta["xmax"], meta["ymax"]
    stops_path = os.path.join(site_dir, "stops.json")
    if not os.path.exists(stops_path):
        log(f"sites/{site}/stops.json missing (make stops): nothing to hang a timetable on")
        return None
    pack_stops = json.load(open(stops_path)).get("stops", [])
    all_stops, all_routes, versions, credits = [], [], [], []
    for feed in LV_FEEDS:
        zip_path = os.path.join(paths.raw("gtfs"), feed["id"] + ".zip")
        try:
            download(feed_url(feed), zip_path, max_age_days=max_age_days, refresh=refresh)
        except Exception as e:  # noqa: BLE001 - one feed missing leaves the others
            log(f"{feed['id']} unavailable ({e})")
            continue
        with zipfile.ZipFile(zip_path) as zf:
            for r in rows(zf, "feed_info.txt"):
                versions.append(f"{feed['id']} {r.get('feed_version', '')}".strip())
                break
            raw = [r for r in rows(zf, "stops.txt", ("stop_id", "stop_name", "stop_lat", "stop_lon"))
                   if r["stop_lat"] and r["stop_lon"]]
            xy = geo.transform_points([(float(r["stop_lon"]), float(r["stop_lat"])) for r in raw], "4326", "3301") if raw else []
            mine, names = {}, {}
            for r, (x, y) in zip(raw, xy):
                lx, lz = x - xmin, ymax - y
                if not (0 <= lx <= xmax - xmin and 0 <= lz <= ymax - ymin):
                    continue
                near = min(pack_stops, key=lambda s: math.dist((s["x"], s["z"]), (lx, lz)), default=None)
                if near is None or math.dist((near["x"], near["z"]), (lx, lz)) > MATCH_M:
                    continue
                mine[r["stop_id"]] = near["id"]
                names[r["stop_id"]] = r["stop_name"]
            if not mine:
                log(f"{feed['id']}: no scheduled stop inside {site}'s tile")
                continue
            routes = {r["route_id"]: r for r in rows(zf, "routes.txt")}
            calls = {}
            for r in rows(zf, "stop_times.txt", ("trip_id", "stop_id", "departure_time", "stop_sequence")):
                if r["stop_id"] in mine:
                    calls.setdefault(r["trip_id"], []).append((int(r["stop_sequence"]), r["stop_id"], r["departure_time"][:5]))
            trips = {r["trip_id"]: r for r in rows(zf, "trips.txt") if r["trip_id"] in calls
                     and routes.get(r["route_id"], {}).get("route_type", "3") in LV_ROUTE_TYPES}
            calendar = {r["service_id"]: r for r in rows(zf, "calendar.txt")}
            grouped = {}
            for tid, cs in calls.items():
                t = trips.get(tid)
                if t is None:
                    continue
                rt = routes.get(t["route_id"], {})
                key = (rt.get("route_short_name", ""), t.get("trip_headsign", ""), t.get("shape_id", ""))
                g = grouped.setdefault(key, {"long_name": rt.get("route_long_name", ""), "departures": {}, "calls": {}})
                cs.sort()
                g["departures"].setdefault(day_of(t.get("service_id", ""), calendar), set()).add(cs[0][2])
                for seq, sid, _ in cs:
                    g["calls"][mine[sid]] = seq
            wanted = {k[2] for k in grouped if k[2]}
            pts = {}
            for r in rows(zf, "shapes.txt", ("shape_id", "shape_pt_lat", "shape_pt_lon", "shape_pt_sequence")):
                if r["shape_id"] in wanted:
                    pts.setdefault(r["shape_id"], []).append((int(r["shape_pt_sequence"]), float(r["shape_pt_lat"]), float(r["shape_pt_lon"])))
        flat = [(lon, lat) for sid in sorted(pts) for _, lat, lon in sorted(pts[sid])]
        projected = geo.transform_points(flat, "4326", "3301") if flat else []
        at, shapes = 0, {}
        for sid in sorted(pts):
            n = len(pts[sid])
            shapes[sid] = [[round(x - xmin, 1), round(ymax - y, 1)] for x, y in projected[at:at + n]
                           if -MARGIN_M <= x - xmin <= xmax - xmin + MARGIN_M and -MARGIN_M <= ymax - y <= ymax - ymin + MARGIN_M]
            at += n
        used = 0
        for (line, headsign, shape), g in sorted(grouped.items()):
            poly = shapes.get(shape, [])
            if len(poly) < 2:
                continue
            all_routes.append({"line": line, "headsign": headsign, "long_name": g["long_name"], "shape": poly,
                               "calls": [s for s, _ in sorted(g["calls"].items(), key=lambda kv: kv[1])],
                               "departures": {d: sorted(v) for d, v in sorted(g["departures"].items())}})
            used += 1
        all_stops += [{"gtfs_id": f"{feed['id']}:{g}", "stop": s, "name": names[g]} for g, s in sorted(mine.items())]
        if used:
            credits.append(feed["attribution"])
    json.dump({"attribution": "; ".join(credits), "source": "GTFS: " + ", ".join(f["id"] for f in LV_FEEDS), "fetched": time.strftime("%Y-%m-%d"),
               "feed_version": "; ".join(versions), "stops": all_stops, "routes": all_routes},
              open(os.path.join(site_dir, "departures.json"), "w"), ensure_ascii=False, indent=0)
    lines = sorted({r["line"] for r in all_routes}, key=lambda s: (len(s), s))
    total = sum(len(t) for r in all_routes for t in r["departures"].values())
    log(f"wrote sites/{site}/departures.json: {len(all_stops)} stops, {len(all_routes)} routes "
        f"({', '.join(lines) if lines else 'no line'}), {total} departures")
    return all_routes


def _write(site_dir, site, stops, routes, feed_version):
    json.dump({"attribution": ATTRIBUTION, "source": "GTFS: " + FEED, "fetched": time.strftime("%Y-%m-%d"),
               "feed_version": feed_version, "stops": stops, "routes": routes},
              open(os.path.join(site_dir, "departures.json"), "w"), ensure_ascii=False, indent=0)
    lines = sorted({r["line"] for r in routes}, key=lambda s: (len(s), s))
    total = sum(len(t) for r in routes for t in r["departures"].values())
    log(f"wrote sites/{site}/departures.json: {len(stops)} stops, {len(routes)} routes "
        f"({', '.join(lines) if lines else 'no line'}), {total} departures")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--site", required=True)
    ap.add_argument("--root", default=ROOT)
    ap.add_argument("--refresh", action="store_true", help="download the feed again even if the cached copy is fresh")
    ap.add_argument("--max-age-days", type=int, default=7)
    a = ap.parse_args()
    sys.exit(0 if fetch(a.site, root=a.root, refresh=a.refresh, max_age_days=a.max_age_days) is not None else 1)
