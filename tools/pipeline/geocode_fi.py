#!/usr/bin/env python3
"""Finnish place and address search for the menu (the tile service's /geocode?country=fi). The NLS
and Digitransit geocoders want a personal key, so the search is built from open sources without one:

  * places, answered at once from two small files cached on first use: the municipalities
    (Statistics Finland's division, fetch_outline.py's file) and the 3,000 postcode areas with their
    Finnish and Swedish names ("Helsinki keskusta - Etu-Töölö", "Kruununhaka"), each at its centre;
  * addresses, asked live from Ryhti's open WFS (SYKE, CC BY 4.0): every building address in Finnish
    and Swedish. "Aleksanterinkatu 15" finds every town's; "Aleksanterinkatu 15, Helsinki" (or
    "..., Helsingfors") narrows it to one post office.

    python3 tools/pipeline/geocode_fi.py "Aleksanterinkatu 15, Helsinki"

Results are [{name, x, y}] on the L-EST97 grid, like Maa-amet's.
"""
import json, os, sys, time, unicodedata, urllib.parse, urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paths  # noqa: E402

RYHTI_WFS = "https://paikkatiedot.ymparisto.fi/geoserver/ryhti_building/wfs"
POSTAL = "https://geo.stat.fi/geoserver/postialue/wfs"
UA = {"User-Agent": "vakuraamat-pipeline/0.1 (open-source game; polite, cached)"}
MAX_AGE = 90 * 86400
_places = None


def log(msg):
    print(f"[geocode_fi] {msg}", flush=True)


def fold(s):
    """Lower case without diacritics: "Töölö" and "toolo", "Hämeenlinna" and "hameenlinna" meet."""
    s = unicodedata.normalize("NFKD", str(s or "").lower())
    return " ".join("".join(c for c in s if not unicodedata.combining(c) and c not in "\"'").replace(",", " ").split())


def _get(url, timeout=30):
    import fetch_cadastre_fi   # certifi's roots
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=timeout, context=fetch_cadastre_fi._tls()) as r:
        return json.load(r)


def _postal_areas():
    """Statistics Finland's postcode areas (the newest year published), cached as GeoJSON in TM35."""
    path = os.path.join(paths.raw("fi"), "postal_areas.json")
    if not (os.path.exists(path) and time.time() - os.path.getmtime(path) < MAX_AGE):
        for year in range(int(time.strftime("%Y")), int(time.strftime("%Y")) - 3, -1):
            q = urllib.parse.urlencode({"service": "WFS", "version": "2.0.0", "request": "GetFeature", "typeNames": f"postialue:pno_{year}",
                                        "srsName": "EPSG:3067", "outputFormat": "application/json"})
            try:
                d = _get(f"{POSTAL}?{q}", timeout=180)
            except Exception as e:  # noqa: BLE001 - not published yet: the year before
                log(f"postcode areas {year}: {str(e)[:80]}")
                continue
            if d.get("features"):
                json.dump(d, open(path, "w"), ensure_ascii=False)
                break
    return json.load(open(path)).get("features", []) if os.path.exists(path) else []


def places():
    """[(key, name, x, y, rank)]: municipalities first, then postcode areas (split at " - " into the
    districts they join), each in Finnish and Swedish."""
    global _places
    if _places is None:
        import shapely
        from pyproj import Transformer
        import fetch_tile_fi
        t = Transformer.from_crs("EPSG:3067", "EPSG:3301", always_xy=True)
        out = []
        fetch_tile_fi.municipality_at((0, 0, 1, 1))   # makes sure the division is cached
        for f in json.load(open(os.path.join(paths.raw("fi"), "kunta4500k.json")))["features"]:
            p = f["properties"]
            c = shapely.geometry.shape(f["geometry"]).representative_point()
            x, y = t.transform(c.x, c.y)
            for n in {p.get("nimi"), p.get("namn")} - {None}:
                out.append((fold(n), n, round(x), round(y), 0))
        munis = {str(f["properties"]["kunta"]): f["properties"].get("nimi")
                 for f in json.load(open(os.path.join(paths.raw("fi"), "kunta4500k.json")))["features"]}
        for f in _postal_areas():
            p = f["properties"]
            c = shapely.geometry.shape(f["geometry"]).representative_point()
            x, y = t.transform(c.x, c.y)
            town = munis.get(str(p.get("kunta")), "")
            for full in {p.get("nimi"), p.get("namn")} - {None}:
                for part in [full] + ([s for s in full.split(" - ")] if " - " in full else []):
                    name = f"{part}, {town} ({p.get('posti_alue')})" if town and fold(town) not in fold(part) else f"{part} ({p.get('posti_alue')})"
                    out.append((fold(part + " " + town), name, round(x), round(y), 1 if part == full else 2))
        _places = out
    return _places


def _quote(s):
    return s.replace("'", "''")


def addresses(street, town=None, limit=8):
    """Ryhti's addresses starting with `street`, in either language, in `town` when given."""
    cond = f"(address_fin ILIKE '{_quote(street)}%' OR address_swe ILIKE '{_quote(street)}%')"
    if town:
        cond += f" AND (postal_office_fin ILIKE '{_quote(town)}%' OR postal_office_swe ILIKE '{_quote(town)}%')"
    q = urllib.parse.urlencode({"service": "WFS", "version": "2.0.0", "request": "GetFeature", "typeNames": "ryhti_building:open_address",
                                "count": limit * 3, "outputFormat": "application/json", "srsName": "EPSG:3067", "CQL_FILTER": cond,
                                "propertyName": "address_fin,address_swe,postal_office_fin,location_geometry_data"})
    feats = _get(f"{RYHTI_WFS}?{q}").get("features", [])
    from pyproj import Transformer
    t = Transformer.from_crs("EPSG:3067", "EPSG:3301", always_xy=True)
    out, seen = [], set()
    for f in feats:
        p, g = f.get("properties") or {}, f.get("geometry") or {}
        if g.get("type") != "Point":
            continue
        swe = fold(street) and fold(p.get("address_swe") or "").startswith(fold(street)) and not fold(p.get("address_fin") or "").startswith(fold(street))
        addr = (p.get("address_swe") if swe else p.get("address_fin")) or p.get("address_fin")
        name = f"{addr}, {(p.get('postal_office_fin') or '').title()}".strip(", ")
        if name in seen:
            continue
        seen.add(name)
        x, y = t.transform(*g["coordinates"][:2])
        out.append({"name": name, "x": round(x), "y": round(y)})
        if len(out) >= limit:
            break
    return out


def search(q, limit=8):
    """Places whose name holds every word of the query, then addresses (a street and number, with an
    optional town after a comma)."""
    words = fold(q).split()
    if not words:
        return []
    hits = sorted((p for p in places() if all(w in p[0] for w in words)), key=lambda p: (p[4], len(p[1])))
    out, seen = [], set()
    for p in hits:
        if p[1] not in seen:
            seen.add(p[1])
            out.append({"name": p[1], "x": p[2], "y": p[3]})
        if len(out) >= limit // 2 and any(ch.isdigit() for ch in q):
            break   # a house number: leave room for the addresses
        if len(out) >= limit:
            break
    if len(out) < limit:
        street, _, town = q.partition(",")
        try:
            out += addresses(street.strip(), town.strip() or None, limit - len(out))
        except Exception as e:  # noqa: BLE001 - places still answer
            log(f"Ryhti address search unavailable ({e})")
    return out


if __name__ == "__main__":
    print(json.dumps(search(" ".join(sys.argv[1:]) or "Aleksanterinkatu 15, Helsinki"), ensure_ascii=False, indent=1))
