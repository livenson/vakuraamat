#!/usr/bin/env python3
"""Bus departures for a tile from the Estonian public transport register's GTFS feed.

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
    """The rows of one GTFS table. `want` keeps only the named columns, which matters for
    stop_times.txt: it is 217 MB and the whole point is never to hold it in memory."""
    with zf.open(name) as raw:
        for row in csv.DictReader(io.TextIOWrapper(raw, encoding="utf-8-sig", newline="")):
            yield {k: row[k] for k in want} if want else row


def day_of(service_id, calendar):
    """weekday / saturday / sunday for a service, from the days it runs on."""
    c = calendar.get(service_id)
    if not c:
        return "weekday"
    if any(c[d] == "1" for d in ("monday", "tuesday", "wednesday", "thursday", "friday")):
        return "weekday"
    return "saturday" if c["saturday"] == "1" else "sunday" if c["sunday"] == "1" else "weekday"


def fetch(site, root=ROOT, refresh=False, max_age_days=7):
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
