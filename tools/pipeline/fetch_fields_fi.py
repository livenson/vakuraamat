#!/usr/bin/env python3
"""Farmed fields for a Finnish tile (docs/finland-plan.md, step 4) from the Finnish Food Authority's
open field-parcel data (Ruokavirasto, INSPIRE WFS, CC BY 4.0, no key): each crop parcel declared for
the year's area aid, its polygon and its crop with the crop's Finnish name.

    python3 tools/pipeline/fetch_fields_fi.py --site <id>

Writes sites/<site>/fields_2026.json in the shape fetch_fields.py writes for Estonia: {"attribution",
"source", "fetched", "year", "fields": [{id, crop, kind, use, area_ha, polygon [[x, z]...]}]} in tile
metres, clipped to the tile. `kind` groups the crop names for the game (scripts/world/crops.gd):
cereal, rape, potato, maize, legume, grass, fallow, other.
"""
import argparse, json, os, sys, time, urllib.parse, urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paths  # noqa: E402

ROOT = paths.ROOT
WFS = "https://inspire.ruokavirasto-awsa.com/geoserver/wfs"
LAYER = "inspire:LandUse.ExistingLandUse.GSAAAgriculturalParcel.{year}"
UA = {"User-Agent": "vakuraamat-pipeline/0.1 (open-source game; polite, cached)"}
ATTRIBUTION = "Kasvulohkot ja viljelykasvit: Ruokavirasto {year} (CC BY 4.0)"
KINDS = [  # substring of the crop's Finnish name (lower case) -> kind; first match wins
    ("kesanto", "fallow"), ("viherkesanto", "fallow"),
    ("nurmi", "grass"), ("laidun", "grass"), ("niitty", "grass"), ("apila", "grass"), ("timotei", "grass"), ("sinimailanen", "grass"),
    ("säilörehu", "grass"), ("kuivaheinä", "grass"), ("heinä", "grass"), ("viherlannoitus", "grass"), ("monimuotoisuus", "grass"),
    ("peruna", "potato"), ("maissi", "maize"),
    ("rypsi", "rape"), ("rapsi", "rape"), ("pellava", "rape"), ("camelina", "rape"), ("kumina", "rape"),
    ("herne", "legume"), ("härkäpapu", "legume"), ("papu", "legume"), ("virna", "legume"), ("lupiini", "legume"), ("soija", "legume"),
    ("ohra", "cereal"), ("vehnä", "cereal"), ("ruis", "cereal"), ("kaura", "cereal"), ("tattari", "cereal"), ("vilja", "cereal"),
    ("spelt", "cereal"), ("hirssi", "cereal"), ("kinoa", "cereal"),
]


def log(msg):
    print(f"[fetch_fields_fi] {msg}", flush=True)


def kind_of(crop):
    s = (crop or "").lower()
    for key, kind in KINDS:
        if key in s:
            return kind
    return "other" if s else "grass"


def _get(url, timeout=180):
    import fetch_cadastre_fi   # certifi's roots
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=timeout, context=fetch_cadastre_fi._tls()) as r:
        return json.load(r)


def parcels(box, year):
    """The year's crop parcels under a TM35 box (GeoJSON features in TM35)."""
    q = urllib.parse.urlencode({"service": "WFS", "version": "2.0.0", "request": "GetFeature", "typeNames": LAYER.format(year=year),
                                "srsName": "urn:ogc:def:crs:EPSG::3067", "outputFormat": "application/json", "count": 10000})
    return _get(f"{WFS}?{q}&bbox={box[0]:.0f},{box[1]:.0f},{box[2]:.0f},{box[3]:.0f},urn:ogc:def:crs:EPSG::3067").get("features", [])


def fetch(site, root=ROOT):
    import fetch_fields
    import fetch_tile_fi
    from pyproj import Transformer
    site_dir = os.path.join(root, "sites", site)
    m = json.load(open(os.path.join(site_dir, "site.json")))
    meta = json.load(open(os.path.join(root, "assets/terrain", m["terrain"]["tile"], "terrain_meta.json")))
    xmin, ymin, xmax, ymax = meta["xmin"], meta["ymin"], meta["xmax"], meta["ymax"]
    box = fetch_tile_fi.box_in((xmin, ymin, xmax, ymax), fetch_tile_fi.TM35, margin=10.0)
    t = Transformer.from_crs("EPSG:3067", "EPSG:3301", always_xy=True)
    feats, year = [], None
    for y in range(int(time.strftime("%Y")), int(time.strftime("%Y")) - 3, -1):   # the newest year published
        try:
            feats = parcels(box, y)
            year = y
            break
        except Exception as e:  # noqa: BLE001 - not published yet: the year before
            log(f"{y}: {str(e)[:80]}")
    if year is None:
        log("Ruokavirasto unavailable")
        return []
    out = []
    for f in feats:
        p = f.get("properties") or {}
        g = f.get("geometry") or {}
        polys = g.get("coordinates", []) if g.get("type") == "MultiPolygon" else [g.get("coordinates", [])]
        for poly in polys:
            if not poly:
                continue
            xs, ys = t.transform([c[0] for c in poly[0]], [c[1] for c in poly[0]])
            ring = [[float(x), float(y)] for x, y in zip(xs, ys)]
            c = fetch_fields.clip(ring, xmin, ymin, xmax, ymax)
            if len(c) >= 3 and fetch_fields.area(c) >= 200:
                crop = p.get("KASVIKOODI_SELITE_FI")
                out.append({"id": f"fi{p.get('PERUSLOHKOTUNNUS')}-{p.get('LOHKONUMERO')}", "crop": crop, "kind": kind_of(crop),
                            "use": p.get("KASVIKOODI"), "area_ha": p.get("PINTA_ALA"), "organic": p.get("LUOMUVILJELY"),
                            "polygon": [[round(x - xmin, 1), round(ymax - y, 1)] for x, y in c]})
    json.dump({"attribution": ATTRIBUTION.format(year=year), "source": WFS + " " + LAYER.format(year=year), "fetched": time.strftime("%Y-%m-%d"),
               "year": year, "fields": out}, open(os.path.join(site_dir, "fields_2026.json"), "w"), ensure_ascii=False)
    kinds = {}
    for u in out:
        kinds[u["kind"]] = kinds.get(u["kind"], 0) + 1
    log(f"wrote sites/{site}/fields_2026.json: {len(out)} fields ({year}) {dict(sorted(kinds.items(), key=lambda kv: -kv[1]))}")
    return out


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--site", required=True)
    ap.add_argument("--root", default=ROOT)
    a = ap.parse_args()
    sys.exit(0 if fetch(a.site, root=a.root) is not None else 1)
