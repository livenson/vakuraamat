#!/usr/bin/env python3
"""Cadastral units for a tile from the Maa-amet cadastre (WFS kataster:ky_kehtiv on the Keskkonnaagentuur
geoserver): number (tunnus), address, intended purposes, area, ownership form, the 2022 land value, polygon.

    python3 tools/pipeline/fetch_parcels.py --site kvissentali [--root <workspace>]

Writes sites/<site>/parcels.json: {"attribution", "fetched", "valuation", "summary", "parcels": [{tunnus, address,
purpose [..], purpose_pct [..], area, ownership, registered, land_registry, municipality, land_value (EUR, the
2022 regular valuation's taxation value `maks_hind`, null when unset), land_value_per_m2, ehak (settlement code),
settlement, county, ads_oid, polygon [[x, z]...], x, z, link}]}. `summary` aggregates the EHAK codes, settlement
and municipality names, the county and the valued total; the tenant, market and news tools read it.
`link` opens the unit in Maa-amet's X-GIS. The game's codes overlay (K), the ledger and F8 reports read this file;
small public-land parcels (ULDKASUTATAV_MAA) in built areas get a playground.
"""
import argparse, json, os, sys, time, urllib.parse, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WFS = "https://gsavalik.envir.ee/geoserver/kataster/wfs"
UA = {"User-Agent": "vakuraamat-pipeline/0.1 (open-source game; polite, cached)"}
ATTRIBUTION = "Maakataster (katastriüksused, maa maksustamishind 2022): Maa- ja Ruumiamet"
VALUATION = {"year": 2022, "field": "maks_hind", "note": "maa korraline hindamine 2022 (taxation value, not a market price)"}
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
        mh = p.get("maks_hind")
        land_value = int(mh) if isinstance(mh, (int, float)) and mh > 0 else None
        area = p.get("pindala") or 0
        out.append({"tunnus": p.get("tunnus"), "address": p.get("l_aadress"), "purpose": purposes, "purpose_text": [PURPOSE_TEXT.get(s, s) for s in purposes],
                    "purpose_pct": [p.get(k) for k in ("so_prts1", "so_prts2", "so_prts3") if p.get(k)], "area": p.get("pindala"), "ownership": p.get("omvorm"),
                    "registered": p.get("registr"), "land_registry": p.get("kinnistu"), "municipality": p.get("ov_nimi"),
                    "land_value": land_value, "land_value_per_m2": round(land_value / area, 2) if land_value and area else None,
                    "ehak": str(p.get("hkood")) if p.get("hkood") else None, "settlement": p.get("ay_nimi"), "county": p.get("mk_nimi"), "ads_oid": p.get("ads_oid"),
                    "polygon": poly, "x": round((min(xs) + max(xs)) / 2, 1), "z": round((min(zs) + max(zs)) / 2, 1), "link": LINK.format(tunnus=p.get("tunnus"))})
    json.dump({"attribution": ATTRIBUTION, "source": WFS, "fetched": time.strftime("%Y-%m-%d"), "valuation": VALUATION, "summary": summarize(out), "parcels": out},
              open(os.path.join(site_dir, "parcels.json"), "w"), ensure_ascii=False)
    kinds = {}
    for u in out:
        k = u["purpose"][0] if u["purpose"] else "?"
        kinds[k] = kinds.get(k, 0) + 1
    valued = [u for u in out if u.get("land_value")]
    log(f"wrote sites/{site}/parcels.json: {len(out)} units {dict(sorted(kinds.items(), key=lambda kv: -kv[1]))}; "
        f"{len(valued)}/{len(out)} valued, total {sum(u['land_value'] for u in valued):,} EUR")
    return out


def summarize(units):
    """Aggregate the identifiers the tenant, market and news tools key on (also available to old packs via this function)."""
    def most_common(vals):
        vals = [v for v in vals if v]
        return max(set(vals), key=vals.count) if vals else None
    valued = [u for u in units if u.get("land_value")]
    return {"ehak": sorted({u["ehak"] for u in units if u.get("ehak")}), "settlements": sorted({u["settlement"] for u in units if u.get("settlement")}),
            "municipalities": sorted({u["municipality"] for u in units if u.get("municipality")}), "county": most_common([u.get("county") for u in units]),
            "n_valued": len(valued), "total_land_value": sum(u["land_value"] for u in valued)}


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--site", default="palupera")
    ap.add_argument("--root", default=ROOT)
    a = ap.parse_args()
    fetch(a.site, a.root)
    sys.exit(0)
