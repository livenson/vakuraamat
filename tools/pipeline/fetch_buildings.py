#!/usr/bin/env python3
"""Real building footprints and attributes for a tile.

    python3 tools/pipeline/fetch_buildings.py --site kvissentali [--no-ehr] [--root <workspace>]

Sources (both open data, attribution required):
  * ETAK, the Estonian topographic database (Keskkonnaagentuur geoserver, WFS layer
    etak:e_401_hoone_ka): every building polygon in the bbox, its type and, for most, the Building
    Register code (ehr_gid).
  * EHR, the Building Register (livekluster.ehr.ee, GET /api/building/v2/buildingdata?ehr_code=):
    first year of use, floors, footprint area, gross volume, name, purpose, status.
  * Maa-amet 3D building models (Geo3D, LOD2 with roof shapes, FileGDB per municipality, read with
    GDAL): the actual roof geometry, keyed by ETAK id. Downloads are cached in data_raw/lod2/.
  * The tile's canopy.r32 (nDSM) for the measured height of footprints without a model.

Writes sites/<site>/buildings.json:
  [{id, ehr, polygon [[x, z]...] (tile metres, x east, z south), x, z, w, d, h, floors, year, name,
    purpose, type, address, color, wall_color, roof_color, materials {structure, facade, wall_type, roof_cover,
    roof_structure, heat_source, energy, heating, foundation, water, sewage, electricity, gas, monument},
    chimney, solar, well, monument, lod2: {z_min, z_max, faces [[[x, y, z]...]...]} or null}]
The register's technical indicators drive the look: facade material -> wall colour, roof covering ->
roof colour, heat source and fuel -> chimney, solar electricity -> panels, own well -> a well ring.
A building appears in an era when year <= the era's year; buildings without a year are shown in the
newest era only (tools/gen_era_scenes.py "footprints" node). EHR answers are cached in data_raw/ehr/.
"""
import argparse, json, os, shutil, subprocess, sys, time, urllib.parse, urllib.request, zipfile

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ETAK_WFS = "https://gsavalik.envir.ee/geoserver/etak/wfs"
EHR_API = "https://livekluster.ehr.ee/api/building/v2/buildingdata?ehr_code={code}"
UA = {"User-Agent": "vakuraamat-pipeline/0.1 (open-source game; polite, cached)"}
ATTRIBUTION = {"etak": "Eesti topograafia andmekogu (ETAK), Maa- ja Ruumiamet", "ehr": "Ehitisregister (EHR), Majandus- ja Kommunikatsiooniministeerium",
               "lod2": "Hoonete ruumiandmed (3D, LOD2): Maa- ja Ruumiamet"}
GAZETTEER = "https://inaadress.maaamet.ee/inaadress/gazetteer?features=EHAK&results=2&x={x}&y={y}"
LOD2_URL = "https://geoportaal.maaamet.ee/index.php?lang_id=1&plugin_act=otsing&andmetyyp=hooned_lod2&dl=1&f=hooned_lod2-{name}-gdb.zip&page_id=833"
COLORS = {"dwelling": [0.84, 0.76, 0.6], "outbuilding": [0.46, 0.38, 0.29], "other": [0.62, 0.62, 0.58]}


def log(msg):
    print(f"[fetch_buildings] {msg}", flush=True)


def get_json(url, timeout=60, retries=3):
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=timeout) as r:
                return json.load(r)
        except Exception as e:  # noqa: BLE001
            if attempt == retries - 1:
                log(f"giving up on {url[:90]}: {e}")
                return None
            time.sleep(1.5 * (attempt + 1))


def fetch_etak(xmin, ymin, xmax, ymax):
    q = {"service": "WFS", "version": "2.0.0", "request": "GetFeature", "typeNames": "etak:e_401_hoone_ka", "srsName": "EPSG:3301",
         "bbox": f"{xmin},{ymin},{xmax},{ymax},EPSG:3301", "outputFormat": "application/json", "count": 5000}
    d = get_json(ETAK_WFS + "?" + urllib.parse.urlencode(q), timeout=120)
    return (d or {}).get("features", [])


def fetch_ehr(code, cache_dir):
    os.makedirs(cache_dir, exist_ok=True)
    p = os.path.join(cache_dir, f"{code}.json")
    if os.path.exists(p):
        return json.load(open(p))
    d = get_json(EHR_API.format(code=code), timeout=40)
    time.sleep(0.15)
    if d is not None:
        json.dump(d, open(p, "w"))
    return d


# Register technical indicators (klNimetus) that shape a building's look.
TECH_KEYS = {
    "Kande- ja jäigastavate konstruktsioonide materjal": "structure", "Välisseina välisviimistluse materjal": "facade",
    "Välisseina liik": "wall_type", "Katusekatte materjal": "roof_cover", "Katuste ja katuselagede kandva osa materjal": "roof_structure",
    "Soojusallikas": "heat_source", "Energiakandja": "energy", "Soojusvarustuse liik": "heating", "Vundamendi liik": "foundation",
    "Veevarustuse liik": "water", "Kanalisatsiooni liik": "sewage", "Elektrisüsteemi liik": "electricity",
    "Võrgu- või mahutigaasi olemasolu": "gas", "Kultuuriväärtus": "monument",
}
# facade / wall material -> wall colour (Estonian rural palette); roof covering -> roof colour
FACADE_COLORS = [
    ("keraamiline tellis", [0.62, 0.36, 0.28]), ("tellis", [0.66, 0.42, 0.32]), ("krohv", [0.88, 0.82, 0.68]), ("silikaat", [0.86, 0.85, 0.8]),
    ("fassaadiplaat", [0.78, 0.78, 0.74]), ("betoon", [0.68, 0.68, 0.65]), ("raudbetoon", [0.66, 0.66, 0.63]), ("plekk", [0.7, 0.72, 0.74]),
    ("palk", [0.42, 0.32, 0.22]), ("laudis", [0.72, 0.58, 0.3]), ("puit (vooder)", [0.74, 0.6, 0.32]), ("puit", [0.55, 0.42, 0.28]),
    ("kivi", [0.6, 0.58, 0.52]), ("plokk", [0.8, 0.78, 0.72]),
]
ROOF_COLORS = [
    ("katusekivi", [0.6, 0.3, 0.22]), ("kivi", [0.55, 0.3, 0.24]), ("plekk", [0.45, 0.28, 0.24]), ("eterniit", [0.55, 0.55, 0.52]),
    ("bituumen", [0.22, 0.2, 0.19]), ("PVC", [0.24, 0.23, 0.22]), ("rullmaterjal", [0.22, 0.2, 0.19]), ("rookatus", [0.55, 0.48, 0.3]), ("õlg", [0.6, 0.52, 0.3]),
]


def pick_color(value, table, default):
    v = (value or "").lower()
    for key, col in table:
        if key.lower() in v:
            return col
    return default


def summarize_ehr(d):
    e = (d or {}).get("ehitis") or {}
    andmed = e.get("ehitiseAndmed") or {}
    pohi = e.get("ehitisePohiandmed") or {}
    ots = ((e.get("ehitiseKasutusotstarbed") or {}).get("kasutusotstarve") or [{}])[0]
    tech = {}
    for tn in (e.get("ehitiseTehnilisedNaitajad") or {}).get("tehnilineNaitaja") or []:
        k = TECH_KEYS.get(tn.get("klNimetus"))
        if k and tn.get("nimetus") and k not in tech:
            tech[k] = tn.get("nimetus")
    year = andmed.get("esmaneKasutus")
    try:
        year = int(year) if year and int(year) > 1000 else None
    except (TypeError, ValueError):
        year = None
    def num(v):
        try:
            return float(v) if v not in (None, "") else 0.0
        except (TypeError, ValueError):
            return 0.0
    area = num(pohi.get("ehitisalunePind"))
    volume = num(pohi.get("mahtBruto"))
    floors = int(num(pohi.get("maxKorrusteArv"))) or None
    heat = (tech.get("heat_source") or "").lower()
    energy = (tech.get("energy") or "").lower()
    kujud = (e.get("ehitiseKujud") or {}).get("ruumikuju") or []
    kaddr = [a for k in kujud for a in ((k.get("ehitiseKujuAadressid") or {}).get("aadress") or []) if a.get("olek", "K") == "K"]
    taddr = [a for a in ((e.get("ehitiseAadressid") or {}).get("aadress") or []) if ((a.get("olekviit") or {}).get("olek", "K")) == "K"]
    first = (kaddr or taddr or [{}])[0]
    kys = [k for k in ((e.get("ehitiseKatastriyksused") or {}).get("ehitiseKatastriyksus") or []) if k.get("olek", "K") == "K"]
    ads = {"adr_id": first.get("adrId"), "aadr_id": first.get("aadr_id"), "ads_oid": kujud[0].get("adsOid") if kujud else None,
           "koodaadress": first.get("koodaadress"), "full_address": first.get("taisaadress")} if first else None
    return {"year": year, "floors": floors, "area": area, "volume": volume,
            "ads": ads, "addresses": sorted({a.get("lahiaadress") for a in kaddr + taddr if a.get("lahiaadress")}),
            "cadastral": [k.get("katastritunnus") for k in kys if k.get("katastritunnus")],
            "height_est": round(volume / area, 1) if area and volume else None,
            "name": andmed.get("nimetus"), "purpose": ots.get("kaosIdTxt"), "purpose_code": ots.get("kaosKood"), "status": andmed.get("seisund"),
            "materials": tech,
            "chimney": bool(heat) and not any(k in heat for k in ("puudub", "soojuspump", "elektri")) or "tahke" in energy or "ahi" in heat,
            "solar": "päikese" in (tech.get("electricity") or "").lower(),
            "well": "kaev" in (tech.get("water") or "").lower(),
            "monument": bool(tech.get("monument"))}


def point_in_poly(px, pz, poly):
    inside = False
    n = len(poly)
    j = n - 1
    for i in range(n):
        xi, zi = poly[i]; xj, zj = poly[j]
        if (zi > pz) != (zj > pz) and px < (xj - xi) * (pz - zi) / ((zj - zi) or 1e-9) + xi:
            inside = not inside
        j = i
    return inside


def roof_colour(poly, ortho):
    """The roof as the orthophoto shows it: the median of the brighter half of the pixels inside the
    footprint (shadows and edges fall in the darker half). RGB 0..1, or None when too small."""
    if ortho is None:
        return None
    size = ortho.shape[0]
    xs = [p[0] for p in poly]; zs = [p[1] for p in poly]
    vals = []
    for z in range(max(int(min(zs)), 0), min(int(max(zs)) + 1, size)):
        for x in range(max(int(min(xs)), 0), min(int(max(xs)) + 1, size)):
            if point_in_poly(x + 0.5, z + 0.5, poly):
                vals.append(ortho[z, x])
    if len(vals) < 4:
        return None
    arr = np.array(vals)
    bright = arr[arr.max(axis=1) >= np.median(arr.max(axis=1))]
    c = np.median(bright, axis=0)
    return [round(float(v), 3) for v in c]


def canopy_height(poly, canopy):
    """90th percentile of the nDSM inside the polygon: the roof, not the chimney."""
    if canopy is None:
        return None
    size = canopy.shape[0]
    xs = [p[0] for p in poly]; zs = [p[1] for p in poly]
    vals = []
    for z in range(max(int(min(zs)), 0), min(int(max(zs)) + 1, size)):
        for x in range(max(int(min(xs)), 0), min(int(max(xs)) + 1, size)):
            if point_in_poly(x + 0.5, z + 0.5, poly):
                vals.append(float(canopy[z, x]))
    if len(vals) < 3:
        return None
    return round(float(np.percentile(vals, 90)), 1)


def municipalities(xmin, ymin, xmax, ymax):
    """Municipality names (omavalitsus) under the tile's centre and corners, via the address gazetteer."""
    names = []
    for x, y in [((xmin + xmax) / 2, (ymin + ymax) / 2), (xmin + 1, ymin + 1), (xmax - 1, ymin + 1), (xmin + 1, ymax - 1), (xmax - 1, ymax - 1)]:
        d = get_json(GAZETTEER.format(x=int(x), y=int(y)), timeout=20, retries=2) or {}
        for a in d.get("addresses", []):
            n = a.get("omavalitsus")
            if n and n not in names:
                names.append(n)
    return names


def fetch_lod2(xmin, ymin, xmax, ymax, cache_dir):
    """Maa-amet 3D building models (LOD2, roof shapes) for the tile: {etak_id: feature} with 3D faces.
    Downloads the FileGDB per municipality (cached), reads it with GDAL, clips to the bbox."""
    if not shutil.which("ogr2ogr"):
        log("ogr2ogr not found: no LOD2 roofs (brew install gdal)")
        return {}
    os.makedirs(cache_dir, exist_ok=True)
    found = {}
    for name in municipalities(xmin, ymin, xmax, ymax):
        fname = name.replace(" ", "_")
        zpath = os.path.join(cache_dir, f"hooned_lod2-{fname}-gdb.zip")
        if not os.path.exists(zpath):
            url = LOD2_URL.format(name=urllib.parse.quote(fname))
            log(f"downloading LOD2 buildings for {name}")
            try:
                with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=900) as r, open(zpath + ".part", "wb") as f:
                    shutil.copyfileobj(r, f)
                os.replace(zpath + ".part", zpath)
            except Exception as e:  # noqa: BLE001
                log(f"no LOD2 download for {name}: {e}")
                continue
        gdb_dir = os.path.join(cache_dir, f"hooned_lod2-{fname}")
        if not os.path.isdir(gdb_dir):
            with zipfile.ZipFile(zpath) as z:
                z.extractall(gdb_dir)
        gdbs = [os.path.join(dp, d) for dp, ds, _ in os.walk(gdb_dir) for d in ds if d.endswith(".gdb")]
        if not gdbs:
            continue
        out = os.path.join(cache_dir, f"clip_{fname}_{int(xmin)}_{int(ymin)}.geojson")
        if os.path.exists(out):
            os.remove(out)
        subprocess.run(["ogr2ogr", "-q", "-f", "GeoJSON", "-spat", str(xmin), str(ymin), str(xmax), str(ymax), "-dim", "XYZ", out, gdbs[0]],
                       check=False, capture_output=True)
        if not os.path.exists(out):
            continue
        for f in json.load(open(out)).get("features", []):
            eid = f.get("properties", {}).get("etak_id")
            if eid is not None:
                found[int(eid)] = f
        log(f"LOD2 {name}: {len(found)} building models inside the tile so far")
    return found


def lod2_faces(feature, xmin, ymax, bx, bz):
    """3D faces of a building relative to (bx, z_min, bz): x east, y up from the lowest vertex, z south."""
    g = feature.get("geometry") or {}
    polys = g.get("coordinates", []) if g.get("type") == "MultiPolygon" else [g.get("coordinates", [])]
    zs = [c[2] for poly in polys for ring in poly[:1] for c in ring if len(c) > 2]
    if not zs:
        return None
    z0 = min(zs)
    faces = []
    for poly in polys:
        ring = poly[0] if poly else []
        pts = [[round(c[0] - xmin - bx, 2), round(c[2] - z0, 2), round(ymax - c[1] - bz, 2)] for c in ring if len(c) > 2]
        if len(pts) > 1 and pts[0] == pts[-1]:
            pts = pts[:-1]
        if len(pts) >= 3:
            faces.append(pts)
    return {"z_min": round(z0, 2), "z_max": round(max(zs), 2), "faces": faces} if faces else None


def classify(tyyp_text, purpose_code):
    pc = str(purpose_code or "")
    if pc.startswith("11") or (tyyp_text or "").startswith("Elu-"):
        return "dwelling" if not pc.startswith("1274") else "outbuilding"
    if (tyyp_text or "").startswith("Kõrval") or pc.startswith("1271") or pc.startswith("1274"):
        return "outbuilding"
    return "other" if pc else "outbuilding"


def fetch(site, root=ROOT, use_ehr=True, use_lod2=True, progress=None):
    """`progress(frac, text)`, when given, hears about the register lookups (one HTTP call per building)."""
    site_dir = os.path.join(root, "sites", site)
    m = json.load(open(os.path.join(site_dir, "site.json")))
    tile = m["terrain"]["tile"]
    tdir = os.path.join(root, "assets/terrain", tile)
    meta = json.load(open(os.path.join(tdir, "terrain_meta.json")))
    xmin, ymin, xmax, ymax = meta["xmin"], meta["ymin"], meta["xmax"], meta["ymax"]
    size = int(meta["size_px"])
    canopy = None
    if meta.get("canopy") and os.path.exists(os.path.join(tdir, meta["canopy"]["file"])):
        canopy = np.fromfile(os.path.join(tdir, meta["canopy"]["file"]), dtype="<f4").reshape(size, size)
    ortho = None
    ortho_path = os.path.join(tdir, meta.get("texture", "ortho.jpg"))
    if os.path.exists(ortho_path):
        try:
            from extract_features import load_ortho
            ortho = load_ortho(ortho_path, size)
        except Exception as e:  # noqa: BLE001 - the colours are a nicety
            log(f"orthophoto not read for roof colours: {e}")
    feats = fetch_etak(xmin, ymin, xmax, ymax)
    log(f"ETAK: {len(feats)} building polygons in the tile")
    cache = os.path.join(ROOT, "data_raw", "ehr")
    lod2 = fetch_lod2(xmin, ymin, xmax, ymax, os.path.join(ROOT, "data_raw", "lod2")) if use_lod2 else {}
    out = []
    with_ehr = with_year = with_lod2 = 0
    for i, f in enumerate(feats):
        if progress and i % 10 == 0:
            progress(i / max(len(feats), 1), f"building register {i}/{len(feats)}")
        g = f.get("geometry") or {}
        rings = g.get("coordinates") if g.get("type") == "Polygon" else (g.get("coordinates", [[]])[0] if g.get("type") == "MultiPolygon" else None)
        if not rings:
            continue
        poly = [[round(px - xmin, 2), round(ymax - py, 2)] for px, py in rings[0]]
        if len(poly) > 1 and poly[0] == poly[-1]:
            poly = poly[:-1]
        if len(poly) < 3:
            continue
        xs = [p[0] for p in poly]; zs = [p[1] for p in poly]
        props = f.get("properties", {})
        code = props.get("ehr_gid")
        if code and "-" in str(code):
            code = str(code).split("-")[0]   # ETAK numbers a building's parts "<code>-2"; the register knows the code alone
        info = {}
        if use_ehr and code:
            d = fetch_ehr(code, cache)
            if d:
                info = summarize_ehr(d); with_ehr += 1
        if info.get("year"):
            with_year += 1
        h = canopy_height(poly, canopy)
        if h is None or h < 2.0:
            h = info.get("height_est") or (info.get("floors") or 1) * 3.2
        kind = classify(props.get("tyyp_tekst"), info.get("purpose_code"))
        mats = info.get("materials", {})
        wall_color = pick_color(mats.get("facade") or mats.get("wall_type") or mats.get("structure"), FACADE_COLORS, COLORS[kind])
        roof_color = pick_color(mats.get("roof_cover"), ROOF_COLORS, [k * 0.45 for k in COLORS[kind]])
        seen = roof_colour(poly, ortho)
        if seen:   # the photographed roof, with a quarter of the material's colour for the texture's sake
            roof_color = [round(0.75 * seen[i] + 0.25 * roof_color[i], 3) for i in range(3)]
        etak_id = int(props.get("etak_id") or f.get("id", "0").split(".")[-1] or 0)
        bx = round((min(xs) + max(xs)) / 2, 1); bz = round((min(zs) + max(zs)) / 2, 1)
        model = lod2_faces(lod2[etak_id], xmin, ymax, bx, bz) if etak_id in lod2 else None
        if model:
            with_lod2 += 1
            h = max(h, round(model["z_max"] - model["z_min"], 1))
        out.append({
            "id": etak_id, "ehr": code, "lod2": model,
            "polygon": poly, "x": bx, "z": bz,
            "w": round(max(xs) - min(xs), 1), "d": round(max(zs) - min(zs), 1), "h": round(float(h), 1),
            "floors": info.get("floors"), "year": info.get("year"), "name": info.get("name"), "purpose": info.get("purpose"),
            "status": info.get("status"), "type": props.get("tyyp_tekst"), "address": props.get("ads_lahiaadress"),
            "kind": kind, "color": COLORS[kind], "wall_color": wall_color, "roof_color": roof_color, "korgus_m": props.get("korgus_m"),
            "materials": mats, "chimney": bool(info.get("chimney", kind == "dwelling")), "solar": bool(info.get("solar")),
            "well": bool(info.get("well")), "monument": bool(info.get("monument")),
            "ads": info.get("ads"), "addresses": info.get("addresses") or [], "cadastral": info.get("cadastral") or [],
        })
    out.sort(key=lambda b: (b["z"], b["x"]))
    path = os.path.join(site_dir, "buildings.json")
    json.dump({"attribution": ATTRIBUTION, "fetched": time.strftime("%Y-%m-%d"), "buildings": out}, open(path, "w"), indent=1, ensure_ascii=False)
    years = sorted(b["year"] for b in out if b["year"])
    log("appearance: %d with facade material, %d chimneys, %d solar, %d own wells, %d monuments" % (
        sum(1 for b in out if b["materials"].get("facade")), sum(1 for b in out if b["chimney"]), sum(1 for b in out if b["solar"]),
        sum(1 for b in out if b["well"]), sum(1 for b in out if b["monument"])))
    log(f"wrote {os.path.relpath(path, root)}: {len(out)} buildings, {with_ehr} with register data, {with_year} dated, {with_lod2} with LOD2 roofs"
        + (f" ({years[0]}..{years[-1]}, median {years[len(years) // 2]})" if years else ""))
    return out


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--site", default="palupera")
    ap.add_argument("--root", default=ROOT)
    ap.add_argument("--no-ehr", action="store_true", help="polygons and canopy heights only, no register lookups")
    ap.add_argument("--no-lod2", action="store_true", help="skip the Maa-amet 3D building models (roof shapes)")
    a = ap.parse_args()
    fetch(a.site, a.root, not a.no_ehr, not a.no_lod2)
    sys.exit(0)
