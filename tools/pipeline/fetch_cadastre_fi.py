#!/usr/bin/env python3
"""Finnish plots and buildings for a pack (docs/finland-plan.md, step 2): `parcels.json` and
`buildings.json` in the shape the Estonian and Latvian fetchers write, all of it key-free.

    plots       the NLS cadastral index map (INSPIRE WFS, JSON): the property id as printed
                (`91-8-142-4`) and its outline. No area, use or value is published: the area is the
                outline's, and in Helsinki the city's plot units (`Kaavayksikot`) add the zoning class
                and the building right in floor square metres
    buildings   Ryhti (SYKE's building register, OGC API): completion year, storeys, use, materials,
                heating, protection, and its addresses in Finnish and Swedish. Ryhti's buildings are
                points, so they stand in footprints: Helsinki's own register polygons (joined on the
                permanent building id, VTJ-PRT), elsewhere the NLS topographic database's building
                polygons from the Funet mirror (a Ryhti point inside each)
    roofs       fitted to the laser surface fetch_tile_fi kept (`data_raw/fi/<tile>_surface.r32`) by
                roof_fit.py, as in Latvia outside Rīga

Nothing is estimated: a plot without a zoning unit has no purpose, and none has a land value.

    python3 tools/pipeline/fetch_cadastre_fi.py --site helsinki_senaatintori
"""
import argparse, json, os, sys, time, urllib.parse, urllib.request

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import paths  # noqa: E402

ROOT = paths.ROOT
NLS_CP = "https://inspire-wfs.maanmittauslaitos.fi/inspire-wfs/cp/ows"
RYHTI = "https://paikkatiedot.ymparisto.fi/geoserver/ryhti_building/ogc/features/v1/collections/"
HEL_WFS = "https://kartta.hel.fi/ws/geoserver/avoindata/wfs"
MTK = "https://www.nic.funet.fi/index/geodata/mml/maastotietokanta/{year}/shp/"
MTK_YEARS = (2025, 2024)      # the mirror's newest topographic database first
TM35, LEST97 = 3067, 3301
UA = {"User-Agent": "vakuraamat-pipeline/0.1 (open-source game; polite, cached)"}
ATTRIBUTION = {
    "cadastre": "Kiinteistörekisterikartta: Maanmittauslaitos {month} (INSPIRE, CC BY 4.0)",
    "buildings": "Rakennustiedot: Ryhti, Suomen ympäristökeskus {year} (CC BY 4.0)",
    "helsinki": "Rakennukset ja kaavayksiköt: Helsingin kaupunki, kaupunkimittauspalvelut (CC BY 4.0)",
    "mtk": "Rakennukset: Maanmittauslaitoksen maastotietokanta {month} (CC BY 4.0)",
}
VALUATION = {"field": None, "year": None,
             "note": "Finland publishes no land value per plot: the purchase-price register is licensed and property-tax "
                     "values are not public in bulk. Helsinki's plots carry the zoning plan's building right instead"}

# The zoning plan's use class (the letters before the digits: AK, K, Y, L1, VP ...) -> the game's plot classes
ZONING_CLASSES = {"A": "ELAMUMAA", "K": "ARIMAA", "C": "ARIMAA", "P": "ARIMAA", "Y": "UHISKONDLIKE_EHITISTE_MAA",
                  "T": "TOOTMISMAA", "E": "TOOTMISMAA", "L": "TRANSPORDIMAA", "V": "ULDKASUTATAV_MAA", "R": "ULDKASUTATAV_MAA",
                  "W": "VEEKOGUDE_MAA", "M": "MAATULUNDUSMAA", "S": "KAITSEALUNE_MAA"}
# Facade materials as Ryhti writes them -> wall colours
FACADE_COLORS = [("tiili", [0.66, 0.42, 0.32]), ("betoni", [0.74, 0.73, 0.7]), ("puu", [0.62, 0.45, 0.3]),
                 ("kivi", [0.6, 0.58, 0.52]), ("metalli", [0.62, 0.63, 0.64]), ("lasi", [0.5, 0.6, 0.65])]
# NLS topographic database building classes (LUOKKA 422x1/422x2: the last digit is the storey class)
MTK_KINDS = {"4221": "dwelling", "4222": "other", "4223": "dwelling", "4224": "other", "4225": "other", "4226": "outbuilding", "4227": "other"}
MTK_NAMES = {"4221": "Asuinrakennus", "4222": "Liike- tai julkinen rakennus", "4223": "Lomarakennus", "4224": "Teollinen rakennus",
             "4225": "Kirkollinen rakennus", "4226": "Muu rakennus", "4227": "Kirkko"}


def log(msg):
    print(f"[fetch_cadastre_fi] {msg}", flush=True)


def _tls():
    """certifi's roots: the NLS and SYKE chains end in Telia Root CA v2, which macOS's /etc/ssl/cert.pem
    (what a plain python reads) does not carry; the frozen sidecar points SSL_CERT_FILE at certifi anyway."""
    import ssl
    try:
        import certifi
        return ssl.create_default_context(cafile=certifi.where())
    except ImportError:
        return None


def get_json(url, timeout=120, retries=3):
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=timeout, context=_tls()) as r:
                return json.load(r)
        except Exception as e:  # noqa: BLE001
            if attempt == retries - 1:
                raise
            log(f"retrying {url[:90]} ({e})")
            time.sleep(2 * (attempt + 1))


# ------------------------------------------------------------------------------------------ ids
def label_of(ref):
    """The 14-digit property id as printed: 09100801420004 -> 91-8-142-4."""
    ref = str(ref or "")
    if len(ref) != 14 or not ref.isdigit():
        return ref or None
    return f"{int(ref[:3])}-{int(ref[3:6])}-{int(ref[6:10])}-{int(ref[10:])}"


def building_id(prt, fallback):
    """The pack's numeric id: a VTJ-PRT's nine-digit serial (its tenth character is a check letter or
    digit), else a number from the footprint's own source."""
    prt = str(prt or "")
    return int(prt[:9]) if len(prt) == 10 and prt[:9].isdigit() else int(fallback)


def year_of(date):
    s = str(date or "")[:4]
    return int(s) if s.isdigit() and 1000 < int(s) <= int(time.strftime("%Y")) else None


# ------------------------------------------------------------------------------------------ sources
def nls_parcels(box):
    """The NLS cadastral index map under a TM35 box: [(label, 14-digit id, shapely geometry)]."""
    import shapely
    q = urllib.parse.urlencode({"service": "WFS", "version": "2.0.0", "request": "GetFeature", "typeNames": "cp:CadastralParcel",
                                "srsName": "urn:ogc:def:crs:EPSG::3067", "outputFormat": "application/json", "count": 20000})
    d = get_json(f"{NLS_CP}?{q}&bbox={box[0]:.0f},{box[1]:.0f},{box[2]:.0f},{box[3]:.0f},urn:ogc:def:crs:EPSG::3067")
    out = []
    for f in d.get("features", []):
        p = f.get("properties") or {}
        if f.get("geometry") and p.get("label"):
            out.append((str(p["label"]), str(p.get("nationalCadastralReference") or ""), shapely.geometry.shape(f["geometry"])))
    log(f"NLS cadastre: {len(out)} parcels under the tile")
    return out


def ryhti(collection, box_lonlat):
    """Every item of a Ryhti collection under a WGS84 box, following the API's pages."""
    url = RYHTI + f"{collection}/items?" + urllib.parse.urlencode(
        {"bbox": ",".join(f"{v:.6f}" for v in box_lonlat), "limit": 5000, "f": "application/json"})
    out = []
    while url:
        d = get_json(url)
        out += d.get("features", [])
        url = next((ln["href"] for ln in d.get("links", []) if ln.get("rel") == "next"), None)
    return out


def helsinki(layer, box):
    """A layer of Helsinki's open WFS under a TM35 box, as GeoJSON features in TM35."""
    q = urllib.parse.urlencode({"service": "WFS", "version": "2.0.0", "request": "GetFeature", "typeNames": f"avoindata:{layer}",
                                "srsName": "EPSG:3067", "outputFormat": "application/json"})
    return get_json(f"{HEL_WFS}?{q}&bbox={box[0]:.0f},{box[1]:.0f},{box[2]:.0f},{box[3]:.0f},EPSG:3067").get("features", [])


def mtk_zips(box):
    """The topographic database zips holding a TM35 box. A 24 x 12 km sheet (L4321) comes in a west and
    an east half (L4321L, L4321R) of 12 km each: the 6 km sheets A-D and E-H."""
    import fetch_tile_fi
    sheets = {s for entries in fetch_tile_fi.ortho_sheets(box).values() for s, _p in entries}
    return sorted({s[:5] + ("L" if s[5] in "ABCD" else "R") for s in sheets if len(s) == 6})


def mtk_buildings(box, cache):
    """The NLS topographic database's building polygons under a TM35 box: [(props, geometry)]. The zips
    (8-20 MB, every layer of the sheet) are cached; only the building polygons (r_*_p) are read."""
    import fetch_tile
    import geo
    out = []
    for name in mtk_zips(box):
        local = os.path.join(cache, f"{name}.shp.zip")
        if not os.path.exists(local):
            for year in MTK_YEARS:
                try:
                    fetch_tile.download(MTK.format(year=year) + f"{name[:2]}/{name[:3]}/{name}.shp.zip", local)
                    break
                except Exception as e:  # noqa: BLE001 - an older year, or no sheet (the sea)
                    log(f"topographic database {name} ({year}): {e}")
        if os.path.exists(local):
            rows = geo.features(f"/vsizip/{local}/r_{name}_p.shp", bbox=box)
            out += [(p, g) for p, g in rows if g is not None and str(p.get("LUOKKA", ""))[:3] == "422"]
    log(f"topographic database: {len(out)} building polygons under the tile")
    return out


def municipality_names():
    """{code: Finnish name} from the division fetch_outline.py caches."""
    import fetch_tile_fi
    fetch_tile_fi.municipality_at((0, 0, 1, 1))   # makes sure the file is there
    path = os.path.join(paths.raw("fi"), "kunta4500k.json")
    return {str(f["properties"]["kunta"]): f["properties"].get("nimi") for f in json.load(open(path))["features"]}


# ------------------------------------------------------------------------------------------ records
def zoning_class(code):
    letters = "".join(ch for ch in str(code or "") if ch.isalpha()).upper()
    return ZONING_CLASSES.get(letters[:1]) if letters else None


def kind_of(ryhti_use, hel_code, hel_type, mtk_class):
    """The game's building class (dwelling, outbuilding, other) from what the sources say, finest first."""
    t = (hel_type or "").lower()
    if any(w in t for w in ("talous", "sauna", "autotalli", "vaja", "käymälä", "katos", "muuntamo", "parakki")):
        return "outbuilding"
    if hel_code:
        c = str(hel_code)
        return "dwelling" if c[:1] == "0" else "outbuilding" if c[:2] in ("93", "94") else "other"
    if "asuin" in t:
        return "dwelling"
    u = (ryhti_use or "").lower()
    if any(w in u for w in ("kerrostalo", "pientalo", "vapaa-ajan")):
        return "dwelling"
    if any(w in u for w in ("talousrakennus", "sauna")):
        return "outbuilding"
    if u:
        return "other"
    return MTK_KINDS.get(str(mtk_class or "")[:4], "other")


def outer(g):
    if g is None:
        return None
    if g.geom_type == "MultiPolygon":
        g = max(g.geoms, key=lambda p: p.area)
    return g if g.geom_type == "Polygon" else None


def fetch(site, root=ROOT):
    import shapely
    from pyproj import Transformer
    from shapely.strtree import STRtree
    import fetch_buildings
    import fetch_tile_fi
    import geo
    import roof_fit
    site_dir = os.path.join(root, "sites", site)
    m = json.load(open(os.path.join(site_dir, "site.json")))
    tile = m["terrain"]["tile"]
    tdir = os.path.join(root, "assets/terrain", tile)
    meta = json.load(open(os.path.join(tdir, "terrain_meta.json")))
    xmin, ymin, xmax, ymax = meta["xmin"], meta["ymin"], meta["xmax"], meta["ymax"]
    size = int(meta["size_px"])
    box = fetch_tile_fi.box_in((xmin, ymin, xmax, ymax), TM35, margin=20.0)
    corners = geo.transform_points([(box[0], box[1]), (box[2], box[1]), (box[0], box[3]), (box[2], box[3])], TM35, 4326)
    box_ll = (min(c[0] for c in corners), min(c[1] for c in corners), max(c[0] for c in corners), max(c[1] for c in corners))
    t = Transformer.from_crs(f"EPSG:{TM35}", f"EPSG:{LEST97}", always_xy=True)
    tile_box = shapely.geometry.box(0, 0, size, size)
    month, year = time.strftime("%m/%Y"), time.strftime("%Y")

    def to_tile(g, nd=2):
        """A TM35 polygon's outer ring as tile metres [x, z] on the L-EST97 grid."""
        xs, ys = t.transform(*zip(*g.exterior.coords))
        pts = [[round(float(ex) - xmin, nd), round(ymax - float(ey), nd)] for ex, ey in zip(xs, ys)]
        return pts[:-1] if len(pts) > 1 and pts[0] == pts[-1] else pts

    codes = fetch_tile_fi.municipality_at((xmin, ymin, xmax, ymax))
    names = municipality_names()
    city = fetch_tile_fi.HELSINKI in codes
    log(f"municipalities {', '.join(f'{names.get(c, c)} ({c})' for c in sorted(codes))}")

    # --- the registers ------------------------------------------------------------------------------
    parcels_raw = nls_parcels(box)
    zoning = helsinki("Kaavayksikot", box) if city else []
    r_buildings = ryhti("avoimet_rakennukset", box_ll)
    r_addresses = ryhti("open_address", box_ll)
    log(f"Ryhti: {len(r_buildings)} buildings, {len(r_addresses)} addresses; Helsinki plot units: {len(zoning)}")
    by_prt = {str(f["properties"].get("pysyva_rakennustunnus")): f for f in r_buildings if f["properties"].get("pysyva_rakennustunnus")}
    addr_of = {}
    for f in r_addresses:
        p = f["properties"]
        addr_of.setdefault(str(p.get("building_key")), []).append(p)

    def addresses(key):
        rows = sorted(addr_of.get(str(key), []), key=lambda p: (p.get("address_number") or 99))
        fin = [p["address_fin"] for p in rows if p.get("address_fin")]
        swe = [p["address_swe"] for p in rows if p.get("address_swe") and p.get("address_swe") != p.get("address_fin")]
        return fin, swe

    # --- plots --------------------------------------------------------------------------------------
    merged = {}
    for label, ref, g in parcels_raw:
        merged.setdefault(label, [ref, []])[1].append(g)
    zones = [(f["properties"], shapely.geometry.shape(f["geometry"])) for f in zoning if f.get("geometry")]
    zone_by_ref = {str(p.get("kaavayksikkotunnus")): (p, g) for p, g in zones}
    ztree = STRtree([g for _p, g in zones]) if zones else None
    buildings_on = {}   # 14-digit property id -> Ryhti building keys, for a plot's address
    for f in r_buildings:
        p = f["properties"]
        buildings_on.setdefault(str(p.get("sijaintikiinteisto")), []).append(p.get("rakennusavain"))
    parcels = []
    for label, (ref, parts) in sorted(merged.items()):
        whole = shapely.unary_union(parts)
        g = outer(whole)
        if g is None:
            continue
        poly = to_tile(g, 1)
        tp = shapely.geometry.Polygon(poly)
        if not tp.is_valid or not tp.intersects(tile_box):
            continue
        zone = zone_by_ref.get(ref)
        if zone is None and ztree is not None:
            best, share = None, 0.0
            for j in ztree.query(whole):
                s = zones[j][1].intersection(whole).area / max(whole.area, 1e-6)
                if s > share:
                    best, share = zones[j], s
            zone = best if share > 0.5 else None
        zp = zone[0] if zone else {}
        zcode = zp.get("kayttotarkoitusluokka_koodi")
        cls = zoning_class(zcode)
        address = None
        if zp.get("osoite"):   # "Aleksanterinkatu 15  00100 Helsinki": the street part
            address = " ".join(w for w in str(zp["osoite"]).split() if not (w.isdigit() and len(w) == 5)).replace(names.get(ref[:3], "#"), "").strip() or None
        if address is None:
            for key in buildings_on.get(ref, []):
                fin, _swe = addresses(key)
                if fin:
                    address = fin[0]
                    break
        area = round(whole.area)
        xs = [c[0] for c in poly]; zs = [c[1] for c in poly]
        right = zp.get("rakennusoikeus")
        parcels.append({
            "tunnus": label, "address": address, "purpose": [cls] if cls else [], "purpose_code": [zcode] if zcode else [],
            "purpose_text": [zp["kayttotarkoitusluokka"]] if zp.get("kayttotarkoitusluokka") else [], "purpose_pct": [100] if zcode else [],
            "area": area, "ownership": None, "registered": None, "land_registry": None, "property": label, "property_id": ref or None,
            "municipality": names.get(ref[:3]), "land_value": None, "land_value_per_m2": None, "land_value_date": None,
            "building_right_m2": int(right) if right else None, "zoning_plan": zp.get("kaavatunnus"),
            "ehak": ref[:3] or None, "settlement": None, "county": None, "ads_oid": None, "polygon": poly,
            "x": round((min(xs) + max(xs)) / 2, 1), "z": round((min(zs) + max(zs)) / 2, 1), "link": None, "parts": len(parts)})

    # --- footprints ---------------------------------------------------------------------------------
    feet = []   # (source, props, TM35 polygon, Ryhti properties or None)
    if city:
        for f in helsinki("Rakennukset_alue_rekisteritiedot", box):
            p = f["properties"]
            g = outer(shapely.geometry.shape(f["geometry"])) if f.get("geometry") else None
            if g is not None and p.get("vtj_prt"):
                r = by_prt.get(str(p["vtj_prt"]))
                feet.append(("helsinki", p, g, r["properties"] if r else None))
    else:
        polys = mtk_buildings(box, paths.raw("fi", "mtk"))
        tree = STRtree([outer(g) or g for _p, g in polys]) if polys else None
        claimed = {}
        for f in r_buildings:
            pt = shapely.geometry.shape(f["geometry"])
            (px, py), = geo.transform_points([(pt.x, pt.y)], 4326, TM35)
            here = shapely.geometry.Point(px, py)
            for j in (tree.query(here) if tree is not None else []):
                if polys[j][1].contains(here):
                    p = f["properties"]
                    old = claimed.get(j)   # two register points in one outline: the larger building keeps it
                    if old is None or (p.get("kerrosala") or 0) > (old.get("kerrosala") or 0):
                        claimed[j] = p
                    break
        for j, (p, g) in enumerate(polys):
            if outer(g) is not None:
                feet.append(("mtk", p, outer(g), claimed.get(j)))
        log(f"Ryhti points in a footprint: {len(claimed)} of {len(r_buildings)}")

    # --- buildings ----------------------------------------------------------------------------------
    surface = None
    sp = fetch_tile_fi.surface_path(paths.raw_root(), tile)
    if os.path.exists(sp):
        surface = np.fromfile(sp, dtype="<f4").reshape(size, size)
    else:
        log(f"no laser surface at {sp}: heights from the storeys, flat roofs")
    ortho = None
    try:
        from extract_features import load_ortho
        ortho = load_ortho(os.path.join(tdir, meta.get("texture", "ortho.jpg")), size)
    except Exception as e:  # noqa: BLE001 - the colours are a nicety
        log(f"orthophoto not read for roof colours: {e}")
    heights = np.fromfile(os.path.join(tdir, meta["heightmap"]), dtype="<f4").reshape(size, size)

    def ground_under(poly):
        return float(min(heights[min(max(int(z), 0), size - 1), min(max(int(x), 0), size - 1)] for x, z in poly))

    label_at = STRtree([shapely.geometry.Polygon(u["polygon"]) for u in parcels]) if parcels else None
    buildings, seen_ids = [], set()
    roof_kinds = {}
    with_year = with_register = 0
    for src, p, g, r in feet:
        poly = to_tile(g)
        if len(poly) < 3:
            continue
        xs = [c[0] for c in poly]; zs = [c[1] for c in poly]
        bx = round((min(xs) + max(xs)) / 2, 1); bz = round((min(zs) + max(zs)) / 2, 1)
        if not (0 <= bx < size and 0 <= bz < size):
            continue
        r = r or {}
        with_register += bool(r)
        prt = str(p.get("vtj_prt") or r.get("pysyva_rakennustunnus") or "") or None
        bid = building_id(prt, 800_000_000_000 + int(p.get("KOHDEOSO") or p.get("id") or len(buildings)))
        if bid in seen_ids:
            continue
        seen_ids.add(bid)
        yr = year_of(r.get("valmistumispaivamaara")) or year_of(p.get("c_valmpvm"))
        with_year += yr is not None
        floors = p.get("i_kerrlkm") or r.get("kerrosluku") or None
        floors = int(floors) if floors else None
        hel_code = p.get("c_kayttark")
        kind = kind_of(r.get("paaasiallinen_kayttotarkoitus"), hel_code, p.get("tyyppi"), p.get("LUOKKA"))
        facade = r.get("julkisivumateriaali")
        wall_color = fetch_buildings.pick_color(facade, FACADE_COLORS, fetch_buildings.COLORS[kind])
        roof_color = [round(k * 0.45, 3) for k in fetch_buildings.COLORS[kind]]
        seen = fetch_buildings.roof_colour(poly, ortho)
        if seen:
            roof_color = [round(0.75 * seen[i] + 0.25 * roof_color[i], 3) for i in range(3)]
        h = fetch_buildings.canopy_height(poly, surface)
        if h is None or h < 2.0:
            h = (floors or 1) * 3.2
        model, roof_source = None, None
        if surface is not None:
            roof = roof_fit.fit(poly, surface)
            if roof is not None:
                roof_kinds[roof["kind"]] = roof_kinds.get(roof["kind"], 0) + 1
                if roof["kind"] != "flat":
                    g0 = ground_under(poly)
                    model = {"z_min": round(g0, 2), "z_max": round(g0 + roof["ridge"], 2), "faces": roof_fit.faces(roof, bx, bz), "roof": roof["kind"]}
                    roof_source = "laser"
                h = round(float(roof["ridge"]), 1)
        fin, swe = addresses(r.get("rakennusavain"))
        if not fin and p.get("katunimi_suomi") and p.get("osoitenumero"):
            fin = [f"{p['katunimi_suomi']} {p['osoitenumero']}"]
            if p.get("katunimi_ruotsi"):
                swe = [f"{p['katunimi_ruotsi']} {p['osoitenumero']}"]
        on = label_of(r.get("sijaintikiinteisto")) or label_of(str(p.get("c_kiinteistotunnus") or "").replace("-", ""))
        if not on and label_at is not None:
            here = shapely.geometry.Point(bx, bz)
            hit = [parcels[j]["tunnus"] for j in label_at.query(here) if shapely.geometry.Polygon(parcels[j]["polygon"]).contains(here)]
            on = hit[0] if hit else None
        purpose = p.get("tyyppi") if src == "helsinki" and not str(p.get("tyyppi") or "").isdigit() else None
        purpose = purpose or r.get("paaasiallinen_kayttotarkoitus") or MTK_NAMES.get(str(p.get("LUOKKA") or "")[:4])
        mats = {k: v for k, v in (("facade", facade), ("wall_type", r.get("kantavien_rakenteiden_rakennusaine")),
                                  ("heating", r.get("lammitystapa")), ("heat_source", r.get("lammitysenergian_lahde")),
                                  ("construction", r.get("rakentamistapa"))) if v and v != "Muu"}
        buildings.append({
            "id": bid, "ehr": prt, "lod2": model, "roof_source": roof_source, "polygon": poly, "x": bx, "z": bz,
            "w": round(max(xs) - min(xs), 1), "d": round(max(zs) - min(zs), 1), "h": round(float(h), 1),
            "floors": floors, "year": yr, "name": None, "purpose": purpose,
            "purpose_code": hel_code or (str(p.get("LUOKKA")) if p.get("LUOKKA") else None), "status": r.get("kaytossaolo"),
            "type": r.get("paaasiallinen_kayttotarkoitus"), "address": fin[0] if fin else None, "kind": kind,
            "color": fetch_buildings.COLORS[kind], "wall_color": wall_color, "roof_color": roof_color, "korgus_m": None, "materials": mats,
            "floor_area": r.get("kerrosala") or p.get("i_kerrosala"), "volume": r.get("tilavuus") or p.get("i_raktilav"),
            "apartments": r.get("huoneistojen_lukumaara"),
            "chimney": kind == "dwelling" and (r.get("lammitysenergian_lahde") or "") != "Kauko- tai aluelämpö",
            "solar": False, "well": False, "monument": bool(r.get("suojeltu")), "ads": None,
            "addresses": sorted(set(fin + swe)), "cadastral": [on] if on else [], "footprint_source": src,
        })
    buildings.sort(key=lambda b: (b["z"], b["x"]))

    # --- write --------------------------------------------------------------------------------------
    summary = {"ehak": sorted(codes), "settlements": [], "municipalities": sorted(names.get(c, c) for c in codes), "county": None,
               "n_valued": 0, "total_land_value": 0}
    attr_c = ATTRIBUTION["cadastre"].format(month=month) + ("; " + ATTRIBUTION["helsinki"] if city else "")
    json.dump({"attribution": attr_c, "source": NLS_CP, "fetched": time.strftime("%Y-%m-%d"), "country": "fi", "valuation": VALUATION,
               "summary": summary, "parcels": parcels}, open(os.path.join(site_dir, "parcels.json"), "w"), ensure_ascii=False)
    attr_b = {"buildings": ATTRIBUTION["buildings"].format(year=year), "cadastre": ATTRIBUTION["cadastre"].format(month=month)}
    attr_b["footprints"] = ATTRIBUTION["helsinki"] if city else ATTRIBUTION["mtk"].format(month=month)
    json.dump({"attribution": attr_b, "fetched": time.strftime("%Y-%m-%d"), "country": "fi", "buildings": buildings},
              open(os.path.join(site_dir, "buildings.json"), "w"), ensure_ascii=False, separators=(",", ":"))
    kinds = {}
    for u in parcels:
        k = u["purpose"][0] if u["purpose"] else "?"
        kinds[k] = kinds.get(k, 0) + 1
    log(f"wrote sites/{site}/parcels.json: {len(parcels)} plots {dict(sorted(kinds.items(), key=lambda kv: -kv[1]))}, "
        f"{sum(1 for u in parcels if u['building_right_m2'])} with a building right")
    log(f"wrote sites/{site}/buildings.json: {len(buildings)} buildings ({'Helsinki' if city else 'topographic database'} footprints), "
        f"{with_register} with a Ryhti record, {with_year} dated; roofs fitted to the laser surface: {roof_kinds}")
    return parcels, buildings


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--site", required=True)
    ap.add_argument("--root", default=ROOT)
    a = ap.parse_args()
    fetch(a.site, a.root)
