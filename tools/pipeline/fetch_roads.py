#!/usr/bin/env python3
"""Roads, streets, paths and trails for a tile from ETAK (WFS etak:e_501_tee_j, line geometry).

    python3 tools/pipeline/fetch_roads.py --site kvissentali [--root <workspace>]

Writes sites/<site>/roads.json: {"attribution", "fetched", "roads": [{id, kind, type, width, surface, name,
points [[x, z]...]}]} in tile metres. kind: street (Tänav), road (Muu tee, maantee...), path
(Kergliiklustee: pedestrian/cycle), trail (Rada). The RoadNetwork node draws them on the terrain in the
newest era: asphalt with a pale kerb for streets, light paving for paths, gravel for roads and trails.
"""
import argparse, json, os, sys, time, urllib.parse, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WFS = "https://gsavalik.envir.ee/geoserver/etak/wfs"
UA = {"User-Agent": "vakuraamat-pipeline/0.1 (open-source game; polite, cached)"}
ATTRIBUTION = "Eesti topograafia andmekogu (ETAK), teed: Maa- ja Ruumiamet"
KIND = {"Tänav": "street", "Kergliiklustee": "path", "Rada": "trail"}


def log(msg):
    print(f"[fetch_roads] {msg}", flush=True)


def fetch(site, root=ROOT):
    site_dir = os.path.join(root, "sites", site)
    m = json.load(open(os.path.join(site_dir, "site.json")))
    tdir = os.path.join(root, "assets/terrain", m["terrain"]["tile"])
    meta = json.load(open(os.path.join(tdir, "terrain_meta.json")))
    xmin, ymin, xmax, ymax = meta["xmin"], meta["ymin"], meta["xmax"], meta["ymax"]
    q = {"service": "WFS", "version": "2.0.0", "request": "GetFeature", "typeNames": "etak:e_501_tee_j", "srsName": "EPSG:3301",
         "bbox": f"{xmin - 20},{ymin - 20},{xmax + 20},{ymax + 20},EPSG:3301", "outputFormat": "application/json", "count": 20000}
    try:
        d = json.load(urllib.request.urlopen(urllib.request.Request(WFS + "?" + urllib.parse.urlencode(q), headers=UA), timeout=300))
    except Exception as e:  # noqa: BLE001
        log(f"ETAK roads unavailable: {e}")
        return []
    out = []
    for f in d.get("features", []):
        p = f.get("properties", {})
        g = f.get("geometry") or {}
        lines = [g.get("coordinates", [])] if g.get("type") == "LineString" else (g.get("coordinates", []) if g.get("type") == "MultiLineString" else [])
        for line in lines:
            pts = [[round(c[0] - xmin, 1), round(ymax - c[1], 1)] for c in line if len(c) >= 2]
            if len(pts) < 2:
                continue
            tt = str(p.get("tyyp_tekst") or "")
            width = float(p.get("laius") or 0)
            kind = KIND.get(tt, "road")
            if width <= 0:
                width = {"street": 6.0, "road": 4.0, "path": 2.0, "trail": 1.2}[kind]
            out.append({"id": p.get("etak_id"), "kind": kind, "type": tt, "width": width, "surface": p.get("teekate_tekst"), "name": p.get("nimetus"),
                        "traffic": p.get("liiklus_tekst"), "points": pts})
    json.dump({"attribution": ATTRIBUTION, "source": WFS, "fetched": time.strftime("%Y-%m-%d"), "roads": out}, open(os.path.join(site_dir, "roads.json"), "w"), ensure_ascii=False)
    kinds = {}
    for r in out:
        kinds[r["kind"]] = kinds.get(r["kind"], 0) + 1
    log(f"wrote sites/{site}/roads.json: {len(out)} segments {kinds}")
    return out


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--site", default="palupera")
    ap.add_argument("--root", default=ROOT)
    a = ap.parse_args()
    fetch(a.site, a.root)
    sys.exit(0)
