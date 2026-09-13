#!/usr/bin/env python3
"""OpenStreetMap under one tile, fetched once and shared: the roads (fetch_roads_lv), the bus stops
(fetch_stops), the sports pitches (fetch_pitches) and the street layers, shops and rails (fetch_osm)
each read what they need from one Overpass answer instead of sending a query of their own.

    elements(site, root, budget) -> [Overpass elements]  (out body geom: tags, nodes, geometry)

The four queries used to overlap on the same box and were sent separately, and the public servers
answer a busy run with 504, a timeout or 429: of a day's 18 tile-service jobs, the OpenStreetMap stages
took 1,090 of 1,207 staged seconds and 52 requests failed (2026-09-13); one refresh ran out of time and
kept its old roads. The answer is cached on disk under the raw directory (paths.raw("overpass")),
keyed by the query, which carries the box, for TTL_DAYS; a job retried or refreshed within that reads
it. One request goes out at a time from this process, and a second stage asking for the same tile
waits for the first instead of sending its own. When the servers do not answer within the budget, a
cached answer older than the TTL is used rather than none. The cache is ODbL data and stays in the raw
directory, which is never shipped.
"""
import hashlib, json, os, sys, threading, time, urllib.parse, urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paths  # noqa: E402

MIRRORS = ["https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter"]
UA = {"User-Agent": "vakuraamat-pipeline/0.1 (open-source game; polite, cached)"}
MARGIN_M = 40.0          # the widest any reader needs (roads cut at 40 m past the tile's edge)
TTL_DAYS = 7
POI_AMENITY = "restaurant|cafe|bar|pub|fast_food|pharmacy|bank|ice_cream|nightclub|biergarten|food_court|fuel|car_wash|marketplace|cinema|theatre|dentist|doctors|clinic|veterinary"
_NET = threading.Lock()                  # one Overpass request at a time from this process
_TILES: dict = {}                        # site -> threading.Lock: one fetch per tile, the others wait


def log(msg):
    print(f"[osm_tile] {msg}", flush=True)


def query(bb):
    """Everything any reader takes, in one union: `bb` is "south,west,north,east"."""
    return f"""[out:json][timeout:170];
(
  way["highway"]({bb});
  node["highway"~"^(bus_stop|street_lamp|traffic_signals|crossing)$"]({bb});
  way["leisure"="pitch"]({bb});
  node["amenity"~"^(bench|waste_basket|bicycle_parking)$"]({bb});
  node["barrier"]({bb});
  way["barrier"]({bb});
  node["natural"="tree"]({bb});
  way["natural"="tree_row"]({bb});
  way["landuse"="flowerbed"]({bb});
  way["man_made"="pier"]({bb});
  way["amenity"~"^(parking|parking_space)$"]({bb});
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


def boxes(site, root=paths.ROOT):
    """The tile's box with MARGIN_M round it: (L-EST97 xmin, ymin, xmax, ymax) and (south, west, north,
    east) in WGS84."""
    import geo
    m = json.load(open(os.path.join(root, "sites", site, "site.json")))
    meta = json.load(open(os.path.join(root, "assets/terrain", m["terrain"]["tile"], "terrain_meta.json")))
    box = (meta["xmin"] - MARGIN_M, meta["ymin"] - MARGIN_M, meta["xmax"] + MARGIN_M, meta["ymax"] + MARGIN_M)
    c = geo.transform_points([(box[0], box[1]), (box[2], box[1]), (box[0], box[3]), (box[2], box[3])], 3301, 4326)
    lons, lats = [p[0] for p in c], [p[1] for p in c]
    return box, (min(lats), min(lons), max(lats), max(lons))


def bbox(site, root=paths.ROOT):
    """The tile's box in WGS84 with MARGIN_M round it, as Overpass wants it: "south,west,north,east"."""
    return "%.6f,%.6f,%.6f,%.6f" % boxes(site, root)[1]


def _cache_path(q):
    return os.path.join(paths.raw("overpass"), hashlib.sha1(q.encode()).hexdigest()[:20] + ".json")


def _store(path, d):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path + ".part", "w") as f:
        json.dump(d, f)
    os.replace(path + ".part", path)


def elements(site, root=paths.ROOT, budget=170.0):
    """The tile's OpenStreetMap elements: from the cache while it is fresh, else from Overpass (the
    mirrors in turn until `budget` seconds are spent), else a stale cached answer. Raises when there is
    neither an answer nor a cache."""
    q = query(bbox(site, root))
    path = _cache_path(q)
    lock = _TILES.setdefault(site, threading.Lock())
    with lock:
        if os.path.exists(path) and time.time() - os.path.getmtime(path) < TTL_DAYS * 86400:
            return json.load(open(path)).get("elements", [])
        t0 = time.time()
        try:
            import osm_extract   # the country extract on disk, cut with osmium-tool, when there is one
            local = osm_extract.tile_elements(*boxes(site, root))
        except Exception as e:  # noqa: BLE001 - Overpass answers instead
            log(f"{site}: the extract could not be cut ({e})")
            local = None
        if local is not None:
            _store(path, {"elements": local, "source": "Geofabrik extract"})
            log(f"{site}: {len(local)} elements from the country extract in {time.time() - t0:.0f} s")
            return local
        last, i = None, 0
        while budget - (time.time() - t0) > 20:
            url = MIRRORS[i % len(MIRRORS)]
            try:
                with _NET:
                    req = urllib.request.Request(url, data=urllib.parse.urlencode({"data": q}).encode(), headers=UA)
                    d = json.load(urllib.request.urlopen(req, timeout=min(175.0, budget - (time.time() - t0))))
                _store(path, d)
                log(f"{site}: {len(d.get('elements', []))} elements from {url.split('/')[2]} in {time.time() - t0:.0f} s")
                return d.get("elements", [])
            except Exception as e:  # noqa: BLE001 - the mirror, then another round
                last = e
                log(f"{site}: {url.split('/')[2]}: {e}")
            i += 1
            if i % len(MIRRORS) == 0:
                time.sleep(8)
        if os.path.exists(path):
            log(f"{site}: Overpass unavailable ({last}); the cached answer of {time.strftime('%Y-%m-%d', time.localtime(os.path.getmtime(path)))}")
            return json.load(open(path)).get("elements", [])
        raise RuntimeError(f"Overpass unavailable: {last}")
