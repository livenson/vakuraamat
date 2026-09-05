#!/usr/bin/env python3
"""Cadastral units for a tile from the Maa-amet cadastre (WFS kataster:ky_kehtiv on the Keskkonnaagentuur
geoserver): number (tunnus), address, intended purposes, area, ownership form, polygon.

    python3 tools/pipeline/fetch_parcels.py --site kvissentali [--root <workspace>]

Writes sites/<site>/parcels.json: {"attribution", "fetched", "parcels": [{tunnus, address, purpose [..],
purpose_pct [..], area, ownership, registered, land_registry, polygon [[x, z]...], x, z, link}]}.
`link` opens the unit in Maa-amet's X-GIS. The game's codes overlay (K) and F8 reports read this file;
small public-land parcels (ULDKASUTATAV_MAA) in built areas get a playground in the newest era.
"""
import argparse, json, os, sys, time, urllib.parse, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WFS = "https://gsavalik.envir.ee/geoserver/kataster/wfs"
UA = {"User-Agent": "vakuraamat-pipeline/0.1 (open-source game; polite, cached)"}
ATTRIBUTION = "Maakataster (katastriüksused): Maa- ja Ruumiamet"
LINK = "https://xgis.maaamet.ee/ky/{tunnus}"
PURPOSE_TEXT = {"ELAMUMAA": "residential", "TRANSPORDIMAA": "transport", "ULDKASUTATAV_MAA": "public land", "SIHTOTSTARBETA_MAA": "no purpose set",
                "MAATULUNDUSMAA": "agricultural/forest", "TOOTMISMAA": "industrial", "UHISKONDLIKE_EHITISTE_MAA": "public buildings", "ARIMAA": "commercial",
                "JAATMEHOIDLA_MAA": "waste", "KAITSEALUNE_MAA": "protected", "RIIGIKAITSEMAA": "defence", "VEEKOGUDE_MAA": "water", "TURBATOOSTUSMAA": "peat",
                "MAETOOSTUSMAA": "mining", "SOTSIAALMAA": "social", "UHISKONDLIKEEHITISTEMAA": "public buildings"}


def log(msg):
    print(f"[fetch_parcels] {msg}", flush=True)


def fetch(site, root=ROOT):
    site_dir = os.path.join(root, "sites", site)
    m = json.load(open(os.path.join(site_dir, "site.json")))
    tdir = os.path.join(root, "assets/terrain", m["terrain"]["tile"])
    meta = json.load(open(os.path.join(tdir, "terrain_meta.json")))
    xmin, ymin, xmax, ymax = meta["xmin"], meta["ymin"], meta["xmax"], meta["ymax"]
    q = {"service": "WFS", "version": "2.0.0", "request": "GetFeature", "typeNames": "kataster:ky_kehtiv", "srsName": "EPSG:3301",
         "bbox": f"{xmin},{ymin},{xmax},{ymax},EPSG:3301", "outputFormat": "application/json", "count": 20000}
    try:
        d = json.load(urllib.request.urlopen(urllib.request.Request(WFS + "?" + urllib.parse.urlencode(q), headers=UA), timeout=300))
    except Exception as e:  # noqa: BLE001
        log(f"cadastre unavailable: {e}")
        return []
    out = []
    for f in d.get("features", []):
        p = f.get("properties", {})
        g = f.get("geometry") or {}
        polys = g.get("coordinates", []) if g.get("type") == "MultiPolygon" else [g.get("coordinates", [])]
        ring = max((poly[0] for poly in polys if poly), key=len, default=None)
        if not ring:
            continue
        poly = [[round(x - xmin, 1), round(ymax - y, 1)] for x, y in (c[:2] for c in ring)]
        if poly[0] == poly[-1]:
            poly = poly[:-1]
        xs = [c[0] for c in poly]; zs = [c[1] for c in poly]
        purposes = [p.get(k) for k in ("siht1", "siht2", "siht3") if p.get(k)]
        out.append({"tunnus": p.get("tunnus"), "address": p.get("l_aadress"), "purpose": purposes, "purpose_text": [PURPOSE_TEXT.get(s, s) for s in purposes],
                    "purpose_pct": [p.get(k) for k in ("so_prts1", "so_prts2", "so_prts3") if p.get(k)], "area": p.get("pindala"), "ownership": p.get("omvorm"),
                    "registered": p.get("registr"), "land_registry": p.get("kinnistu"), "municipality": p.get("ov_nimi"),
                    "polygon": poly, "x": round((min(xs) + max(xs)) / 2, 1), "z": round((min(zs) + max(zs)) / 2, 1), "link": LINK.format(tunnus=p.get("tunnus"))})
    json.dump({"attribution": ATTRIBUTION, "source": WFS, "fetched": time.strftime("%Y-%m-%d"), "parcels": out}, open(os.path.join(site_dir, "parcels.json"), "w"), ensure_ascii=False)
    kinds = {}
    for u in out:
        k = u["purpose"][0] if u["purpose"] else "?"
        kinds[k] = kinds.get(k, 0) + 1
    log(f"wrote sites/{site}/parcels.json: {len(out)} units {dict(sorted(kinds.items(), key=lambda kv: -kv[1]))}")
    return out


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--site", default="palupera")
    ap.add_argument("--root", default=ROOT)
    a = ap.parse_args()
    fetch(a.site, a.root)
    sys.exit(0)
