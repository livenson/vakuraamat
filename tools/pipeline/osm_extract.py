#!/usr/bin/env python3
"""OpenStreetMap from the country extracts on disk instead of the public Overpass servers (the caching
analysis, 2026-09-13: the OSM stages took 90% of every tile-service job and a day's jobs saw 52 failed
Overpass requests). Geofabrik publishes a daily .osm.pbf of each country; the pipeline downloads the
ones it needs into data_raw/osm once, and a new one after REFRESH_DAYS in the background (the old file
serving meanwhile, up to MAX_AGE_DAYS). A tile's box is cut out of it with osmium-tool (the `osmium`
command, complete ways) and read into the shape of an Overpass `out body geom` answer, filtered to what
osm_tile's union query asks for, so the readers do not know where it came from. A tile on a border is
cut from each country's extract and merged.

    python3 tools/pipeline/osm_extract.py --site pirita      # the tile's elements, counted

osmium-tool is not bundled with the frozen tile-service sidecar: without it, or while a country's first
download is still running, tile_elements returns None and osm_tile asks Overpass as before. The extracts
and the cuts are ODbL data and stay in the raw directory, which is never shipped.
"""
import argparse, os, shutil, subprocess, sys, threading, time, urllib.request
import xml.etree.ElementTree as ET

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paths  # noqa: E402

GEOFABRIK = {"ee": "estonia", "lv": "latvia", "fi": "finland"}   # the countries' ids in sources.py
URL = "https://download.geofabrik.de/europe/{}-latest.osm.pbf"
UA = {"User-Agent": "vakuraamat-pipeline/0.1 (open-source game; polite, cached)"}
REFRESH_DAYS = 7      # a newer extract is fetched in the background after this
MAX_AGE_DAYS = 30     # an extract older than this is not used; Overpass answers instead
POI_AMENITY = {"restaurant", "cafe", "bar", "pub", "fast_food", "pharmacy", "bank", "ice_cream", "nightclub", "biergarten", "food_court",
               "fuel", "car_wash", "marketplace", "cinema", "theatre", "dentist", "doctors", "clinic", "veterinary"}
_downloading: set = set()
_lock = threading.Lock()


def log(msg):
    print(f"[osm_extract] {msg}", flush=True)


def available():
    return shutil.which("osmium") is not None


def pbf_path(cid):
    return os.path.join(paths.raw("osm"), f"{GEOFABRIK[cid]}-latest.osm.pbf")


def _download(cid):
    path = pbf_path(cid)
    try:
        t0 = time.time()
        req = urllib.request.Request(URL.format(GEOFABRIK[cid]), headers=UA)
        with urllib.request.urlopen(req, timeout=120) as r, open(path + ".part", "wb") as f:
            shutil.copyfileobj(r, f, 1 << 20)
        os.replace(path + ".part", path)
        log(f"{GEOFABRIK[cid]}: extract downloaded ({os.path.getsize(path) / 1e6:.0f} MB, {time.time() - t0:.0f} s)")
    except Exception as e:  # noqa: BLE001 - Overpass answers until it is in
        log(f"{GEOFABRIK[cid]}: download failed ({e})")
    finally:
        with _lock:
            _downloading.discard(cid)


def ensure(cid):
    """The country's extract when one young enough is on disk, else None; a download starts in the
    background when there is none or it is older than REFRESH_DAYS."""
    path = pbf_path(cid)
    age = (time.time() - os.path.getmtime(path)) / 86400 if os.path.exists(path) else None
    if age is None or age > REFRESH_DAYS:
        with _lock:
            if cid not in _downloading:
                _downloading.add(cid)
                log(f"{GEOFABRIK[cid]}: fetching the extract in the background")
                threading.Thread(target=_download, args=(cid,), daemon=True).start()
    return path if age is not None and age <= MAX_AGE_DAYS else None


def countries(box):
    """The countries whose data the box (L-EST97 xmin, ymin, xmax, ymax) reaches into, by sources.py's
    own coverage test at its corners and middle."""
    import sources
    xmin, ymin, xmax, ymax = box
    pts = [(xmin, ymin), (xmax, ymin), (xmin, ymax), (xmax, ymax), ((xmin + xmax) / 2, (ymin + ymax) / 2)]
    out = []
    for s in sources.SOURCES:
        if s.id in GEOFABRIK and any(s.covers(x, y) for x, y in pts):
            out.append(s.id)
    return out


def wanted(kind, t):
    """Whether osm_tile's union query would return this element (kind: node, way or relation)."""
    hw = t.get("highway")
    if kind == "way" and hw:
        return True
    if kind == "node" and hw in ("bus_stop", "street_lamp", "traffic_signals", "crossing"):
        return True
    if kind == "node" and (t.get("amenity") in ("bench", "waste_basket", "bicycle_parking") or t.get("natural") == "tree"
                           or t.get("railway") in ("tram_stop", "halt", "station", "stop") or "entrance" in t
                           or (t.get("public_transport") == "stop_position" and t.get("tram") == "yes")):
        return True
    if kind in ("node", "way") and "barrier" in t:
        return True
    if kind == "way" and (t.get("leisure") == "pitch" or t.get("natural") == "tree_row" or t.get("landuse") == "flowerbed"
                          or t.get("man_made") == "pier" or t.get("amenity") in ("parking", "parking_space") or "railway" in t):
        return True
    return ("shop" in t or t.get("amenity") in POI_AMENITY or (("office" in t or "craft" in t) and "name" in t)
            or t.get("tourism") in ("hotel", "hostel", "guest_house", "motel")
            or (t.get("leisure") in ("fitness_centre", "sauna", "escape_game", "amusement_arcade") and "name" in t))


def _cut(pbf, ll):
    """The elements of one extract under the box `ll` (south, west, north, east): osmium's cut with
    complete ways, read from its XML into Overpass's shape."""
    south, west, north, east = ll
    out_path = os.path.join(paths.raw("osm", "cuts"), f"cut_{os.getpid()}_{threading.get_ident()}.osm")
    subprocess.run(["osmium", "extract", "-b", f"{west},{south},{east},{north}", "-s", "complete_ways", "--overwrite",
                    "-o", out_path, pbf], check=True, capture_output=True, timeout=600)
    try:
        coords, ways, rels, out = {}, [], [], []
        for _, el in ET.iterparse(out_path, events=("end",)):
            if el.tag not in ("node", "way", "relation"):
                continue
            tags = {t.get("k"): t.get("v") for t in el.findall("tag")}
            eid = int(el.get("id"))
            if el.tag == "node":
                lat, lon = float(el.get("lat")), float(el.get("lon"))
                coords[eid] = (lat, lon)
                # the cut keeps every node of a way crossing the box, some well outside it: a tagged node
                # counts only inside the box, as in Overpass's answer (18 street lamps too many, Pirita)
                if tags and wanted("node", tags) and south <= lat <= north and west <= lon <= east:
                    out.append({"type": "node", "id": eid, "lat": lat, "lon": lon, "tags": tags})
            elif el.tag == "way":
                ways.append((eid, [int(n.get("ref")) for n in el.findall("nd")], tags))
            else:
                rels.append((eid, [(m.get("type"), int(m.get("ref"))) for m in el.findall("member")], tags))
            el.clear()
        way_nodes = {}
        for eid, refs, tags in ways:
            way_nodes[eid] = refs
            if not tags or not wanted("way", tags) or any(r not in coords for r in refs):
                continue
            geom = [{"lat": coords[r][0], "lon": coords[r][1]} for r in refs]
            out.append({"type": "way", "id": eid, "nodes": refs, "geometry": geom, "tags": tags})
        for eid, members, tags in rels:
            if not tags or not wanted("relation", tags):
                continue
            pts = []
            for mtype, ref in members:   # the members the cut holds: the relation's bounds, for its middle
                if mtype == "node" and ref in coords:
                    pts.append(coords[ref])
                elif mtype == "way":
                    pts += [coords[r] for r in way_nodes.get(ref, []) if r in coords]
            if pts:
                lats, lons = [p[0] for p in pts], [p[1] for p in pts]
                out.append({"type": "relation", "id": eid, "tags": tags,
                            "bounds": {"minlat": min(lats), "minlon": min(lons), "maxlat": max(lats), "maxlon": max(lons)}})
        return out
    finally:
        os.remove(out_path)


def tile_elements(box, ll):
    """The elements under a tile's box from the country extracts: `box` in L-EST97 (xmin, ymin, xmax,
    ymax), `ll` the same box in WGS84 (south, west, north, east). None when osmium-tool is missing, the
    box lies outside every country with an extract, or one it needs is not on disk yet."""
    if not available():
        return None
    cids = countries(box)
    if not cids:
        return None
    pbfs = [ensure(c) for c in cids]
    if any(p is None for p in pbfs):
        return None
    seen, out = set(), []
    for pbf in pbfs:
        for e in _cut(pbf, ll):
            key = (e["type"], e["id"])
            if key not in seen:   # a border tile: the same element in both countries' extracts
                seen.add(key)
                out.append(e)
    return out


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--site", required=True)
    ap.add_argument("--root", default=paths.ROOT)
    a = ap.parse_args()
    import osm_tile
    box, ll = osm_tile.boxes(a.site, a.root)
    t0 = time.time()
    els = tile_elements(box, ll)
    if els is None:
        log("no extract to cut (osmium missing, or the country's extract not on disk yet)")
        sys.exit(1)
    kinds = {}
    for e in els:
        kinds[e["type"]] = kinds.get(e["type"], 0) + 1
    log(f"{a.site}: {len(els)} elements {kinds} in {time.time() - t0:.1f} s")
