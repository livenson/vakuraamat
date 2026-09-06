#!/usr/bin/env python3
"""Farmed fields for a tile from PRIA's public field register (WFS on kls.pria.ee): each field's polygon and the
crop declared for this year's area aid (`taotletud_kultuur` on pria_pollud; `kultuur` on the pria_massiivid
field blocks fills the gaps).

    python3 tools/pipeline/fetch_fields.py --site kvissentali [--root <workspace>]

Writes sites/<site>/fields_2026.json: {"attribution", "source", "fetched", "year", "fields": [{id, crop, kind, use,
area_ha, polygon [[x, z]...]}]} in local metres (x east from the tile's west edge, z south from its north edge),
clipped to the tile. `kind` groups the register's crop names for the game (scripts/world/crops.gd plants
them): cereal, rape, potato, maize, legume, grass, fallow, other.
"""
import argparse, json, os, sys, time, urllib.parse, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WFS = "https://kls.pria.ee/geoserver/pria_avalik/wfs"
UA = {"User-Agent": "vakuraamat-pipeline/0.1 (open-source game; polite, cached)"}
ATTRIBUTION = "Põllumassiivide register (põllud, deklareeritud kultuurid): PRIA"
KINDS = [  # substring of the register's crop name (lower case) -> kind; first match wins
    ("kesa", "fallow"), ("mustkesa", "fallow"),
    ("rohttaim", "grass"), ("rohumaa", "grass"), ("heintaim", "grass"), ("ristik", "grass"), ("lutsern", "grass"), ("kõrrelis", "grass"),
    ("karjamaa", "grass"), ("heinamaa", "grass"), ("timut", "grass"), ("raihein", "grass"), ("aruhein", "grass"), ("haljasväetis", "grass"),
    ("kartul", "potato"), ("mais", "maize"),
    ("raps", "rape"), ("rüps", "rape"), ("kaamelina", "rape"), ("tuder", "rape"), ("lina", "rape"),
    ("hernes", "legume"), ("uba", "legume"), ("oad", "legume"), ("vikk", "legume"), ("lupiin", "legume"), ("sojauba", "legume"),
    ("oder", "cereal"), ("nisu", "cereal"), ("rukis", "cereal"), ("kaer", "cereal"), ("tritik", "cereal"), ("spelta", "cereal"),
    ("tatar", "cereal"), ("teravili", "cereal"), ("segavili", "cereal"), ("emmer", "cereal"),
]


def log(msg):
    print(f"[fetch_fields] {msg}", flush=True)


def kind_of(crop, use=""):
    s = (crop or "").lower()
    for key, kind in KINDS:
        if key in s:
            return kind
    u = (use or "").lower()
    if "rohumaa" in u or "karjamaa" in u:
        return "grass"
    return "other" if s else "grass"


def clip(poly, xmin, ymin, xmax, ymax):
    """Sutherland-Hodgman clip of a ring (list of [x, y]) to a rectangle."""
    def inside(p, edge):
        k, v, keep_greater = edge
        return p[k] >= v if keep_greater else p[k] <= v

    def cross(a, b, edge):
        k, v, _ = edge
        t = (v - a[k]) / (b[k] - a[k])
        return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t]

    out = poly
    for edge in ((0, xmin, True), (0, xmax, False), (1, ymin, True), (1, ymax, False)):
        if not out:
            return []
        src, out = out, []
        prev = src[-1]
        for cur in src:
            if inside(cur, edge):
                if not inside(prev, edge):
                    out.append(cross(prev, cur, edge))
                out.append(cur)
            elif inside(prev, edge):
                out.append(cross(prev, cur, edge))
            prev = cur
    return out


def area(poly):
    return abs(sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1] for i in range(len(poly)))) / 2


def inside_poly(pt, poly):
    x, y = pt
    hit = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, yi = poly[i]; xj, yj = poly[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            hit = not hit
        j = i
    return hit


def get(layer, bbox):
    q = {"service": "WFS", "version": "2.0.0", "request": "GetFeature", "typeNames": layer, "srsName": "EPSG:3301",
         "bbox": f"{bbox[0]},{bbox[1]},{bbox[2]},{bbox[3]},EPSG:3301", "outputFormat": "application/json", "count": 5000}
    d = json.load(urllib.request.urlopen(urllib.request.Request(WFS + "?" + urllib.parse.urlencode(q), headers=UA), timeout=180))
    return d.get("features", [])


def rings(f):
    g = f.get("geometry") or {}
    polys = g.get("coordinates", []) if g.get("type") == "MultiPolygon" else [g.get("coordinates", [])]
    return [[c[:2] for c in poly[0]] for poly in polys if poly]


def fetch(site, root=ROOT):
    site_dir = os.path.join(root, "sites", site)
    m = json.load(open(os.path.join(site_dir, "site.json")))
    tdir = os.path.join(root, "assets/terrain", m["terrain"]["tile"])
    meta = json.load(open(os.path.join(tdir, "terrain_meta.json")))
    xmin, ymin, xmax, ymax = meta["xmin"], meta["ymin"], meta["xmax"], meta["ymax"]
    bbox = (xmin, ymin, xmax, ymax)
    try:
        fields = get("pria_avalik:pria_pollud", bbox)
        blocks = get("pria_avalik:pria_massiivid", bbox)
    except Exception as e:  # noqa: BLE001
        log(f"PRIA unavailable: {e}")
        return []
    out, taken, year = [], [], None
    for f in fields:
        p = f.get("properties", {})
        year = p.get("taotlusaasta") or year
        for ring in rings(f):
            taken.append(ring)
            c = clip(ring, xmin, ymin, xmax, ymax)
            if len(c) >= 3 and area(c) >= 200:
                out.append({"id": f"p{p.get('pollu_id')}", "crop": p.get("taotletud_kultuur"), "kind": kind_of(p.get("taotletud_kultuur"), p.get("taotletud_maakasutus")),
                            "use": p.get("taotletud_maakasutus"), "area_ha": p.get("pindala_ha"), "polygon": [[round(x - xmin, 1), round(ymax - y, 1)] for x, y in c]})
    centres = []
    for t in taken:
        centres.append((sum(pt[0] for pt in t) / len(t), sum(pt[1] for pt in t) / len(t)))
    for f in blocks:   # field blocks nobody declared a field on this year: the block's own crop
        p = f.get("properties", {})
        for ring in rings(f):
            cx = sum(pt[0] for pt in ring) / len(ring); cy = sum(pt[1] for pt in ring) / len(ring)
            if any(inside_poly((cx, cy), t) for t in taken) or any(inside_poly(c, ring) for c in centres):
                continue   # a declared field lies on this block
            c = clip(ring, xmin, ymin, xmax, ymax)
            if len(c) >= 3 and area(c) >= 200:
                out.append({"id": f"m{p.get('xy_id')}", "crop": p.get("kultuur"), "kind": kind_of(p.get("kultuur"), p.get("massiivi_maakasutus")),
                            "use": p.get("massiivi_maakasutus"), "area_ha": p.get("pindala"), "polygon": [[round(x - xmin, 1), round(ymax - y, 1)] for x, y in c]})
    json.dump({"attribution": ATTRIBUTION, "source": WFS, "fetched": time.strftime("%Y-%m-%d"), "year": year, "fields": out},
              open(os.path.join(site_dir, "fields_2026.json"), "w"), ensure_ascii=False)
    kinds = {}
    for u in out:
        kinds[u["kind"]] = kinds.get(u["kind"], 0) + 1
    log(f"wrote sites/{site}/fields_2026.json: {len(out)} fields {dict(sorted(kinds.items(), key=lambda kv: -kv[1]))}")
    return out


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--site", required=True)
    ap.add_argument("--root", default=ROOT)
    a = ap.parse_args()
    sys.exit(0 if fetch(a.site, root=a.root) is not None else 1)
