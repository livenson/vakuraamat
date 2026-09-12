#!/usr/bin/env python3
"""Latvian cadastre for a tile (docs/latvia-plan.md, step 2): parcels.json and buildings.json from the
State Land Service's (VZD) open data, with Rīga's LOD2 roofs where the city has modelled them.

    python3 tools/pipeline/fetch_cadastre_lv.py --site riga_vecpilseta

Sources, all CC BY 4.0 and listed through data.gov.lv's CKAN API:
  * the spatial cadastre, one shapefile zip per municipality (`<ATVK>_kk_shp.zip`): parcel and
    building outlines in LKS-92 with their cadastral numbers, nothing else;
  * the descriptive cadastre, national zips holding one XML per municipality: parcels (area, land-use
    purposes with their areas), buildings (use, kind, floors, year taken into use, materials),
    valuations (the cadastral values), addresses, properties (which parcels and buildings form one
    immovable, and its land-book folio) and ownership (only the kind of owner: natural or legal
    person, state, municipality; never a name). Only the municipality's own XML is read, by HTTP
    range request out of the national zip, and only the records of the tile's objects are kept;
  * the address register's municipality polygons, to know which municipality a tile lies in;
  * Rīgas dome's LOD2 models per neighbourhood (CityGML, triangles in LKS-92 with LAS-2000,5
    heights, no attributes) and the neighbourhood polygons that say which files a tile needs. A model
    belongs to the building whose outline holds most of its footprint.

The pack files keep the Estonian shape. Two fields carry the game's own vocabulary so the engine's
rules work unchanged: a parcel's `purpose` is the game's purpose class (ELAMUMAA, ARIMAA...), mapped
from the Latvian land-use purpose, whose code and name stay beside it (`purpose_code`,
`purpose_text`); a building's `kind` is the game's class from the use code. Everything else is the
register's own words, in Latvian.
"""
import argparse, io, json, os, re, struct, sys, time, urllib.parse, urllib.request, zlib
import xml.etree.ElementTree as ET

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import geo  # noqa: E402
import paths  # noqa: E402

ROOT = paths.ROOT
CKAN = "https://data.gov.lv/dati/api/3/action/package_show?id="
SPATIAL = "kadastra-informacijas-sistemas-atverti-telpiskie-dati"
TEXT = "kadastra-informacijas-sistemas-atvertie-dati"
VARIS = "varis-atvertie-dati"
RIGA_LOD2 = "rigas-apkaimju-lod2-modeli"
RIGA_NEIGHBOURHOODS = "rigas_apkaimes"
UA = {"User-Agent": "vakuraamat-pipeline/0.1 (open-source game; polite, cached)"}
LKS92, LEST97 = 3059, 3301
ATTRIBUTION = {
    "cadastre": "Izmantoti Nekustamā īpašuma valsts kadastra informācijas sistēmas dati, {year} (VZD, CC BY 4.0)",
    "addresses": "Izmantoti Valsts adrešu reģistra informācijas sistēmas dati, {year} (VZD, CC BY 4.0)",
    "lod2": "Rīgas apkaimju LOD2 modeļi: Rīgas valstspilsētas pašvaldība (CC BY 4.0)",
}
VALUATION = {"field": "univ", "note": "universālā kadastrālā vērtība (the universal cadastral value, the newest valuation base; "
             "a valuation, not a market price). `land_value_fisc` is the fiscal value property tax is still levied on"}

# The Latvian land-use purpose (NĪLM) names mapped onto the game's purpose classes, by the words in
# the name; the first match wins. What matches nothing keeps no class (the book shows the Latvian name).
PURPOSE_CLASSES = [
    ("daudzdzīvokļu", "ELAMUMAA"), ("dzīvojamo māju", "ELAMUMAA"), ("dzīvojamās apbūves", "ELAMUMAA"),
    ("komercdarbības", "ARIMAA"), ("jauktas centra", "ARIMAA"), ("autostāvviet", "TRANSPORDIMAA"), ("rūpnieciskās ražošanas", "TOOTMISMAA"), ("noliktav", "TOOTMISMAA"),
    ("inženiertehniskās", "TOOTMISMAA"), ("satiksmes", "TRANSPORDIMAA"), ("ielu", "TRANSPORDIMAA"), ("ceļu", "TRANSPORDIMAA"),
    ("dzelzceļa", "TRANSPORDIMAA"), ("ostu", "TRANSPORDIMAA"), ("lidlauk", "TRANSPORDIMAA"),
    ("izglītības", "UHISKONDLIKE_EHITISTE_MAA"), ("zinātnes", "UHISKONDLIKE_EHITISTE_MAA"), ("veselības", "UHISKONDLIKE_EHITISTE_MAA"),
    ("sociālās", "UHISKONDLIKE_EHITISTE_MAA"), ("kultūras", "UHISKONDLIKE_EHITISTE_MAA"), ("reliģisk", "UHISKONDLIKE_EHITISTE_MAA"),
    ("valsts aizsardzības", "RIIGIKAITSEMAA"), ("pārvaldes", "UHISKONDLIKE_EHITISTE_MAA"), ("sporta", "UHISKONDLIKE_EHITISTE_MAA"),
    ("sabiedriskās", "UHISKONDLIKE_EHITISTE_MAA"), ("sabiedriskas", "UHISKONDLIKE_EHITISTE_MAA"),
    ("diplomātisko", "UHISKONDLIKE_EHITISTE_MAA"), ("apstādījumu", "ULDKASUTATAV_MAA"), ("dabas pamatnes", "ULDKASUTATAV_MAA"), ("parku", "ULDKASUTATAV_MAA"),
    ("zaļ", "ULDKASUTATAV_MAA"), ("rekreācijas", "ULDKASUTATAV_MAA"), ("kapsēt", "ULDKASUTATAV_MAA"),
    ("ūdens", "VEEKOGUDE_MAA"), ("ūdeņ", "VEEKOGUDE_MAA"), ("lauksaimniec", "MAATULUNDUSMAA"), ("mežsaimniec", "MAATULUNDUSMAA"),
    ("derīgo izrakteņu", "MAETOOSTUSMAA"), ("atkritumu", "JAATMEHOIDLA_MAA"), ("aizsargājam", "KAITSEALUNE_MAA"),
]
# Element names in a building's construction list -> the material keys the Estonian packs use.
ELEMENT_KEYS = [("pamat", "foundation"), ("fasād", "facade"), ("sienas", "wall_type"), ("jumta seg", "roof_cover"),
                ("jumta nesoš", "roof_structure"), ("pārsegum", "floors_structure")]
FACADE_COLORS = [("ķieģeļ", [0.66, 0.42, 0.32]), ("apmet", [0.85, 0.8, 0.68]), ("koka", [0.55, 0.42, 0.28]), ("koks", [0.55, 0.42, 0.28]),
                 ("guļbūv", [0.42, 0.32, 0.22]), ("dzelzsbeton", [0.72, 0.71, 0.68]), ("betona", [0.74, 0.73, 0.7]),
                 ("akmen", [0.6, 0.58, 0.52]), ("metāl", [0.62, 0.63, 0.64]), ("stikl", [0.5, 0.6, 0.65])]
ROOF_COLORS = [("dakstiņ", [0.6, 0.3, 0.22]), ("māla", [0.6, 0.3, 0.22]), ("skārd", [0.45, 0.28, 0.24]), ("metāl", [0.42, 0.42, 0.43]),
               ("šīfer", [0.55, 0.55, 0.52]), ("azbest", [0.55, 0.55, 0.52]), ("ruberoīd", [0.22, 0.2, 0.19]), ("bitum", [0.22, 0.2, 0.19]),
               ("ruļļ", [0.22, 0.2, 0.19]), ("niedr", [0.55, 0.48, 0.3]), ("salm", [0.6, 0.52, 0.3])]


def log(msg):
    print(f"[fetch_cadastre_lv] {msg}", flush=True)


# ------------------------------------------------------------------------------------------ CKAN and zips
_RESOURCES = {}


def resources(slug):
    """The dataset's resources [{name, url, ...}] (asked once per run; URLs change when a file is replaced)."""
    if slug not in _RESOURCES:
        req = urllib.request.Request(CKAN + slug, headers=UA)
        _RESOURCES[slug] = json.load(urllib.request.urlopen(req, timeout=60))["result"]["resources"]
    return _RESOURCES[slug]


def resource_url(slug, pred):
    for r in resources(slug):
        if pred(r):
            return r["url"]
    return None


def _range(url, a, b):
    req = urllib.request.Request(url, headers=dict(UA, Range=f"bytes={a}-{b}"))
    return urllib.request.urlopen(req, timeout=300)


class RemoteZip:
    """A zip on a server that answers range requests: its directory, and one member at a time."""

    def __init__(self, url):
        self.url = url
        head = urllib.request.urlopen(urllib.request.Request(url, method="HEAD", headers=UA), timeout=60)
        size = int(head.headers["Content-Length"])
        tail = _range(url, max(0, size - 70000), size - 1).read()
        i = tail.rfind(b"PK\x05\x06")
        if i < 0:
            raise ValueError(f"{url}: no zip directory in the last 70 kB")
        _n, cd_size, cd_off = struct.unpack("<HII", tail[i + 10:i + 20])
        cd = _range(url, cd_off, cd_off + cd_size - 1).read()
        self.entries = {}
        p = 0
        while p + 46 <= len(cd) and cd[p:p + 4] == b"PK\x01\x02":
            method, = struct.unpack("<H", cd[p + 10:p + 12])
            csize, usize, nl, el, cl = struct.unpack("<IIHHH", cd[p + 20:p + 34])
            off, = struct.unpack("<I", cd[p + 42:p + 46])
            name = cd[p + 46:p + 46 + nl].decode("utf-8", "replace")
            self.entries[name] = (method, csize, usize, off)
            p += 46 + nl + el + cl

    def save(self, name, dest):
        """The member's stored bytes to `dest` (cached): deflate stays deflated, see `open_member`."""
        if os.path.exists(dest) and os.path.getsize(dest) > 0:
            return dest
        method, csize, _usize, off = self.entries[name]
        lh = _range(self.url, off, off + 29).read()
        nl, el = struct.unpack("<HH", lh[26:30])
        start = off + 30 + nl + el
        tmp = dest + ".part"
        with _range(self.url, start, start + csize - 1) as r, open(tmp, "wb") as f:
            f.write(struct.pack("<H", method))
            while True:
                chunk = r.read(1 << 20)
                if not chunk:
                    break
                f.write(chunk)
        os.replace(tmp, dest)
        log(f"saved {os.path.basename(name)} ({csize / 1e6:.1f} MB compressed)")
        return dest

    def extract(self, name, dest):
        """A small member decompressed to `dest`."""
        if not os.path.exists(dest):
            raw = self.save(name, dest + ".z")
            with open_member(raw) as f, open(dest, "wb") as out:
                out.write(f.read())
            os.remove(raw)
        return dest


class _Inflate(io.RawIOBase):
    def __init__(self, path):
        self.f = open(path, "rb")
        method, = struct.unpack("<H", self.f.read(2))
        self.z = zlib.decompressobj(-15) if method == 8 else None
        self.buf = b""

    def readable(self):
        return True

    def readinto(self, b):
        while len(self.buf) < len(b):
            chunk = self.f.read(1 << 20)
            if not chunk:
                self.buf += self.z.flush() if self.z else b""
                break
            self.buf += self.z.decompress(chunk) if self.z else chunk
        n = min(len(b), len(self.buf))
        b[:n] = self.buf[:n]
        self.buf = self.buf[n:]
        return n

    def close(self):
        self.f.close()
        super().close()


def open_member(path):
    return io.BufferedReader(_Inflate(path), 1 << 20)


# ------------------------------------------------------------------------------------------ XML
def _local(tag):
    return tag.rsplit("}", 1)[-1]


def todict(e):
    """An element as {tag: [values]} (every child a list), text for a leaf."""
    kids = list(e)
    if not kids:
        return (e.text or "").strip()
    d = {}
    for k in kids:
        d.setdefault(_local(k.tag), []).append(todict(k))
    return d


def first(d, *path):
    """The first value down a path of tags, or None."""
    for key in path:
        if not isinstance(d, dict) or not d.get(key):
            return None
        d = d[key][0]
    return d


def every(d, *path):
    """Every value at the end of a path of tags (lists flattened along the way)."""
    level = [d]
    for key in path:
        level = [v for x in level if isinstance(x, dict) for v in x.get(key, [])]
    return level


def scan(path, item, keep):
    """Stream one municipality's XML and return {code: record} for the items `keep(record)` names."""
    out = {}
    n = 0
    with open_member(path) as f:
        for _ev, e in ET.iterparse(f, events=("end",)):
            if _local(e.tag) != item:
                continue
            n += 1
            rec = todict(e)
            code = keep(rec)
            if code:
                out.setdefault(code, []).append(rec)
            e.clear()
    log(f"{os.path.basename(path)}: {n:,} {item} read, {len(out):,} kept")
    return out


def member(dataset, atvk, cache_dir):
    """The municipality's XML from the national `<dataset>.zip`, saved compressed: (path, date)."""
    url = resource_url(TEXT, lambda r: r["url"].endswith(f"/{dataset}.zip"))
    if not url:
        raise RuntimeError(f"no {dataset}.zip in {TEXT}")
    rz = RemoteZip(url)
    names = sorted(n for n in rz.entries if n.endswith(".xml") and n.split("/")[1].startswith(atvk + "_"))
    if not names:
        raise RuntimeError(f"{dataset}.zip has no XML for municipality {atvk}")
    date = names[0].split("/")[1].split("_")[1]
    if len(names) > 1:
        log(f"{dataset}: {len(names)} parts for {atvk}; reading the first")
    return rz.save(names[0], os.path.join(cache_dir, f"{dataset}_{atvk}_{date}.xml.z")), date


# ------------------------------------------------------------------------------------------ where
def municipality(x, y, cache_dir):
    """(ATVK code, name) of the municipality holding an L-EST97 point: a state city from the address
    register's towns, else a municipality (novads)."""
    url = resource_url(VARIS, lambda r: r["url"].endswith("/aw_shp.zip"))
    rz = None
    (lx, ly), = geo.transform_points([(x, y)], LEST97, LKS92)
    from shapely.geometry import Point
    pt = Point(lx, ly)
    for layer in ("Pilsetas", "Novadi"):
        shp = os.path.join(cache_dir, layer + ".shp")
        if not os.path.exists(shp):
            rz = rz or RemoteZip(url)
            for ext in ("shp", "shx", "dbf", "prj", "cpg"):
                rz.extract(f"{layer}.{ext}", os.path.join(cache_dir, f"{layer}.{ext}"))
        for props, g in geo.features(shp, bbox=(lx - 1, ly - 1, lx + 1, ly + 1)):
            if layer == "Pilsetas" and props.get("VKUR_TIPS") != 101:
                continue   # a town inside a municipality: the municipality's files hold it
            if g is not None and g.contains(pt) and props.get("ATRIB"):
                return str(props["ATRIB"]), props.get("NOSAUKUMS")
    return None, None


# ------------------------------------------------------------------------------------------ geometry
def to_tile(ring, t, xmin, ymax, nd=2):
    """LKS-92 (x east, y north) coordinates as tile metres [x, z] on the L-EST97 grid."""
    xs, ys = t.transform([c[0] for c in ring], [c[1] for c in ring])
    pts = [[round(float(ex) - xmin, nd), round(ymax - float(ey), nd)] for ex, ey in zip(xs, ys)]
    if len(pts) > 1 and pts[0] == pts[-1]:
        pts = pts[:-1]
    return pts


def outer_ring(g):
    if g is None:
        return None
    if g.geom_type == "MultiPolygon":
        g = max(g.geoms, key=lambda p: p.area)
    return list(g.exterior.coords) if g.geom_type == "Polygon" else None


def spatial(atvk, box, cache_dir):
    """The municipality's parcel and building outlines under an LKS-92 box: ({code: geom}, {code: (geom, parcel)})."""
    url = resource_url(SPATIAL, lambda r: r["url"].endswith(f"/{atvk}_kk_shp.zip"))
    if not url:
        raise RuntimeError(f"no spatial cadastre for municipality {atvk}")
    import fetch_tile
    zpath = fetch_tile.download(url, os.path.join(cache_dir, f"{atvk}_kk_shp.zip"))
    import zipfile
    names = zipfile.ZipFile(zpath).namelist()
    groups_shp = next((n for n in names if n.endswith("KKCadastralGroup.shp")), None)
    groups = None
    if groups_shp:
        groups = {str(p["CODE"]) for p, _g in geo.features(f"/vsizip/{zpath}/{groups_shp}", bbox=box)}
    parcels, buildings = {}, {}
    for n in names:
        folder, _, fname = n.rpartition("/")
        if not folder.startswith("ExportCadGroup_") or fname not in ("KKParcel.shp", "KKBuilding.shp"):
            continue
        if groups is not None and folder.split("_", 1)[1] not in groups:
            continue
        for props, g in geo.features(f"/vsizip/{zpath}/{n}", bbox=box):
            code = str(props.get("CODE") or "")
            if not code or g is None:
                continue
            if fname == "KKParcel.shp":
                parcels[code] = g
            else:
                buildings[code] = (g, str(props.get("PARCELCODE") or ""))
    log(f"outlines: {len(parcels)} parcels and {len(buildings)} buildings under the tile ({len(groups or [])} cadastral groups)")
    return parcels, buildings


# ------------------------------------------------------------------------------------------ Rīga LOD2
def riga_lod2(box, cache_dir):
    """Rīga's LOD2 building models under an LKS-92 box: [(footprint polygon, [triangles [[x, y, z]...]])],
    in LKS-92 with heights."""
    import fetch_tile
    from shapely.geometry import box as sbox
    url = resource_url(RIGA_NEIGHBOURHOODS, lambda r: r["url"].endswith("apkaimes.gpkg"))
    gpkg = fetch_tile.download(url, os.path.join(cache_dir, "rigas_apkaimes.gpkg"))
    info = __import__("pyogrio").read_info(gpkg)
    epsg = int(re.findall(r"\d+", str(info.get("crs") or "EPSG:3059"))[-1])
    area = sbox(*box)
    if epsg != LKS92:
        pts = geo.transform_points([(box[0], box[1]), (box[2], box[3])], LKS92, epsg)
        area_q = (pts[0][0], pts[0][1], pts[1][0], pts[1][1])
    else:
        area_q = box
    names = []
    from shapely.geometry import box as qbox
    for props, g in geo.features(gpkg, bbox=area_q):
        if g is None or not g.intersects(qbox(*area_q)):
            continue   # the neighbourhood's box meets the tile, its outline does not
        name = next((v for k, v in props.items() if isinstance(v, str) and k.lower() in ("apkaime", "nosaukums", "name", "apkaimes")), None)
        if name:
            names.append(name)
    models = []
    for name in sorted(set(names)):
        url = resource_url(RIGA_LOD2, lambda r, n=name: r.get("name", "").startswith(n + " ") and r.get("format") == "CityGML")
        if not url:
            log(f"no LOD2 model file for the neighbourhood {name}")
            continue
        os.makedirs(os.path.join(cache_dir, "lod2"), exist_ok=True)
        path = fetch_tile.download(url, os.path.join(cache_dir, "lod2", os.path.basename(urllib.parse.urlparse(url).path)))
        if path.endswith(".zip"):   # some neighbourhoods' CityGML comes zipped
            import zipfile
            with zipfile.ZipFile(path) as z:
                gml = next((n for n in z.namelist() if n.lower().endswith((".gml", ".xml"))), None)
                if not gml:
                    log(f"{os.path.basename(path)} holds no CityGML")
                    continue
                out = path[:-4] + ".gml"
                if not os.path.exists(out):
                    with z.open(gml) as src, open(out, "wb") as dst:
                        dst.write(src.read())
                path = out
        got = read_citygml(path, area)
        models += got
        log(f"LOD2 {name}: {len(got)} models under the tile")
    return models


def read_citygml(path, area):
    """[(footprint, triangles)] of the CityGML objects whose footprint meets `area`. The files list
    northing before easting (EPSG:3059's axis order); the triangles come back as [easting, northing, height]."""
    from shapely.geometry import MultiPoint
    out = []
    os.makedirs(os.path.dirname(path), exist_ok=True)
    for _ev, e in ET.iterparse(path, events=("end",)):
        if _local(e.tag) not in ("GenericCityObject", "Building"):
            continue
        tris = []
        for pl in e.iter():
            if _local(pl.tag) != "posList" or not pl.text:
                continue
            v = [float(t) for t in pl.text.split()]
            ring = [[v[i + 1], v[i], v[i + 2]] for i in range(0, len(v) - 2, 3)]
            if len(ring) > 1 and ring[0] == ring[-1]:
                ring = ring[:-1]
            if len(ring) >= 3:
                tris.append(ring)
        e.clear()
        if not tris:
            continue
        foot = MultiPoint([(p[0], p[1]) for t in tris for p in t]).convex_hull
        if foot.intersects(area):
            out.append((foot, tris))
    return out


def merge_faces(tris, min_area=1.0, d_gap=0.3, min_piece=0.1):
    """Coplanar triangles joined back into the faces they came from (a wall, a roof slope), so windows
    and gables see whole faces. Planes are grouped by normal (0.1 steps) and then by offset, split where
    two offsets lie more than `d_gap` apart, so a rounding boundary does not cut a wall in two. Faces are
    wound so the engine's Newell normal points up on a roof and out of the building on a wall; the
    base is dropped, and so are pieces under `min_area` m² that a kept face stands beside at their
    height (cornice mouldings: Rīga's models carry every one, 222 faces a building against 16 in
    Maa-amet's). A small piece with nothing beside it stays: it is the building, not its trim - the
    facets of a round drum or lantern, tessellated into hundreds of triangles under a square metre
    each, which dropped the stage under St James's spire and left it floating 7 m above the tower
    (playtest report 2026-09-12T12-59-02). Slivers under `min_piece` go regardless: on the Old Town
    tile keeping them all added 72% faces for 12% of the recovered surface; from 0.1 m² it is 27%
    faces for 88% of it, and the lantern stays 99% whole. Returns [[[e, n, h]...]]."""
    import warnings
    from shapely.geometry import Polygon
    from shapely.geometry.polygon import orient
    from shapely.ops import unary_union
    ps = [np.asarray(t, float) for t in tris]
    if not ps:
        return []
    centre = np.mean([p.mean(axis=0) for p in ps], axis=0)
    bins = {}
    for p in ps:
        n = np.cross(p[1] - p[0], p[2] - p[0])
        ln = np.linalg.norm(n)
        if ln < 1e-6:
            continue
        n /= ln
        if n[2] < -0.7:
            continue   # the base, facing down
        if abs(n[2]) > 0.3:
            n = n if n[2] > 0 else -n                             # a roof faces up
        elif (p.mean(axis=0) - centre)[:2] @ n[:2] < 0:
            n = -n                                                # a wall faces out
        bins.setdefault((round(n[0] * 10), round(n[1] * 10), round(n[2] * 10)), []).append((float(n @ p[0]), n, p))
    faces, small = [], []
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", RuntimeWarning)
        for lst in bins.values():
            lst.sort(key=lambda it: it[0])
            groups, cur = [], [lst[0]]
            for it in lst[1:]:
                if it[0] - cur[-1][0] > d_gap:
                    groups.append(cur)
                    cur = [it]
                else:
                    cur.append(it)
            groups.append(cur)
            for g in groups:
                n = np.mean([it[1] for it in g], axis=0)
                n /= np.linalg.norm(n)
                u = np.cross([0.0, 0.0, 1.0], n) if abs(n[2]) < 0.9 else np.cross([0.0, 1.0, 0.0], n)
                u /= np.linalg.norm(u)
                w = np.cross(n, u)                                # u x w = n: counter-clockwise in (u, w) faces n
                o = g[0][2][0]
                polys = [Polygon([((q - o) @ u, (q - o) @ w) for q in it[2]]) for it in g]
                polys = [q for q in polys if q.is_valid and q.area > 1e-4]
                if not polys:
                    continue
                merged = unary_union([q.buffer(0.02, join_style=2) for q in polys]).buffer(-0.02, join_style=2)
                for q in getattr(merged, "geoms", [merged]):
                    if q.is_empty or q.geom_type != "Polygon":
                        continue
                    ring = list(orient(q.simplify(0.05), 1.0).exterior.coords)[:-1]
                    if len(ring) >= 3 and q.area >= min_piece:
                        (faces if q.area >= min_area else small).append([list(o + a * u + b * w) for a, b in ring])
    return faces + _unsupported(small, faces)


def _unsupported(small, faces, reach=1.0, big=4.0):
    """The small pieces that no kept face of `big` m² or more stands beside at their height: within
    `reach` metres of its outline's box in plan and inside its height span. A moulding runs along a
    wall that is kept anyway; a drum's facets have no wall beside them, only the tower's top below
    and the spire above."""
    if not small:
        return []
    boxes = []
    for f in faces:
        p = np.asarray(f, float)
        # the face's area by the shoelace in its own plane (Newell): only the big ones hold trim
        n = np.sum(np.cross(p, np.roll(p, -1, axis=0)), axis=0)
        if 0.5 * np.linalg.norm(n) >= big:
            boxes.append([p[:, 0].min() - reach, p[:, 0].max() + reach, p[:, 1].min() - reach, p[:, 1].max() + reach,
                          p[:, 2].min() - 0.05, p[:, 2].max() + 0.05])
    if not boxes:
        return small
    b = np.asarray(boxes)
    c = np.asarray([np.mean(np.asarray(f, float), axis=0) for f in small])
    beside = ((c[:, None, 0] >= b[None, :, 0]) & (c[:, None, 0] <= b[None, :, 1]) & (c[:, None, 1] >= b[None, :, 2])
              & (c[:, None, 1] <= b[None, :, 3]) & (c[:, None, 2] >= b[None, :, 4]) & (c[:, None, 2] <= b[None, :, 5])).any(axis=1)
    return [f for f, keep in zip(small, ~beside) if keep]


def lod2_record(faces, t, xmin, ymax, bx, bz, ground=None):
    """The pack's {z_min, z_max, faces} for one building: x east, y up from the base, z south, relative
    to the building's centre (bx, bz) in tile metres. The base is the model's lowest vertex, or, where
    that lies more than a metre under `ground` (the lowest ground under the footprint; a few models reach
    down to the quay or a cellar), a metre under the ground, so the building does not rise by the depth."""
    zs = [p[2] for f in faces for p in f]
    if not zs:
        return None
    z0 = min(zs) if ground is None else max(min(zs), ground - 1.0)
    out = []
    for f in faces:
        xs, ys = t.transform([p[0] for p in f], [p[1] for p in f])
        out.append([[round(float(ex) - xmin - bx, 2), round(p[2] - z0, 2), round(ymax - float(ey) - bz, 2)] for ex, ey, p in zip(xs, ys, f)])
    return {"z_min": round(z0, 2), "z_max": round(max(zs), 2), "faces": out}


# ------------------------------------------------------------------------------------------ records
# NĪLM codes whose group decides the class before any word does: 12xx is engineering infrastructure
# (power lines, pipelines, water intake and sewage works), whose names mention water and matched
# "ūdens" (Domes bulvāris 7A in Valka read as a lake, playtest report 2026-09-12T10-57-49)
PURPOSE_CODE_CLASSES = {"12": "TOOTMISMAA"}


def purpose_class(name, code=None):
    group = str(code or "")[:2]
    if group in PURPOSE_CODE_CLASSES:
        return PURPOSE_CODE_CLASSES[group]
    low = (name or "").lower()
    for word, cls in PURPOSE_CLASSES:
        if word in low:
            return cls
    return None


def address_text(a):
    """A short address the way the Estonian packs write one: street and number, or the house name."""
    if not a:
        return None
    street, house = first(a, "Street"), first(a, "House")
    if street and house:
        return f"{street} {house}"
    return house or street or first(a, "Village") or first(a, "Town")


def building_kind(use_id):
    """The game's building class from the use code (CC classification, 4 digits)."""
    import fetch_buildings
    return fetch_buildings.classify(None, use_id)


def materials(rec):
    out = {}
    for el in every(rec, "BuildingElementData", "ConstructionDataList"):
        name = (first(el, "BuildingElementName") or "").lower()
        mat = ", ".join(m for m in every(el, "BuildingElementMaterialKindList", "BuildingElementMaterialKind", "MaterialKindName") if m)
        if not mat:
            continue
        for word, key in ELEMENT_KEYS:
            if word in name and key not in out:
                out[key] = mat
                break
    return out


def fetch(site, root=ROOT, use_lod2=True):
    import fetch_buildings
    import fetch_tile_lv
    from pyproj import Transformer
    site_dir = os.path.join(root, "sites", site)
    m = json.load(open(os.path.join(site_dir, "site.json")))
    tile = m["terrain"]["tile"]
    tdir = os.path.join(root, "assets/terrain", tile)
    meta = json.load(open(os.path.join(tdir, "terrain_meta.json")))
    xmin, ymin, xmax, ymax = meta["xmin"], meta["ymin"], meta["xmax"], meta["ymax"]
    size = int(meta["size_px"])
    cache = paths.raw("lv", "cadastre")
    box = fetch_tile_lv.lks_bbox((xmin, ymin, xmax, ymax), margin=20.0)
    t = Transformer.from_crs(f"EPSG:{LKS92}", f"EPSG:{LEST97}", always_xy=True)
    year = time.strftime("%Y")

    atvk, muni = municipality((xmin + xmax) / 2, (ymin + ymax) / 2, paths.raw("lv", "aw"))
    if not atvk:
        sys.exit("no Latvian municipality under the tile centre")
    log(f"municipality {muni} ({atvk})")
    p_geo, b_geo = spatial(atvk, box, cache)
    p_codes, b_codes = set(p_geo), set(b_geo)

    def by_code(tag):
        return lambda r: (lambda c: c if c in p_codes or c in b_codes else None)(first(r, *tag))
    recs = {}
    for dataset, item, key in (("parcel", "ParcelItemData", ("ParcelBasicData", "ParcelCadastreNr")),
                               ("building", "BuildingItemData", ("BuildingBasicData", "BuildingCadastreNr")),
                               ("valuation", "ValuationItemData", ("ObjectRelation", "ObjectCadastreNr")),
                               ("address", "AddressItemData", ("ObjectRelation", "ObjectCadastreNr"))):
        path, date = member(dataset, atvk, cache)
        recs[dataset] = scan(path, item, by_code(key))
    # properties are keyed by their own number; keep those holding a tile object, then their ownership
    path, date = member("property", atvk, cache)
    props = scan(path, "PropertyItemData",
                 lambda r: first(r, "CadastreObjectIdData", "ProCadastreNr")
                 if any(c in p_codes or c in b_codes for c in every(r, "PropertyContentData", "ObjectList", "ObjectData", "ObjectCadastreNrData")) else None)
    pro_codes = set(props)
    path, date = member("ownership", atvk, cache)
    owners = scan(path, "OwnershipItemData", lambda r: (lambda c: c if c in pro_codes else None)(first(r, "ObjectRelation", "ObjectCadastreNr")))
    prop_of = {}
    for pc, rs in props.items():
        for c in every(rs[0], "PropertyContentData", "ObjectList", "ObjectData", "ObjectCadastreNrData"):
            prop_of.setdefault(c, pc)

    def values(code):
        out = {}
        for r in recs["valuation"].get(code, []):
            for row in every(r, "ValuationDataList", "ValuationRowData"):
                try:
                    out[first(row, "ValueType")] = (int(float(first(row, "ObjectCadastralValue"))), first(row, "ObjectCadastralValueDate"))
                except (TypeError, ValueError):
                    pass
        return out

    def addresses(code):
        return [a for r in recs["address"].get(code, []) for a in every(r, "AddressData")]

    def ownership(code):
        pc = prop_of.get(code)
        kinds = sorted({first(k, "PersonStatus") for r in owners.get(pc, []) for k in every(r, "OwnershipStatusKindList", "OwnershipStatusKind")} - {None})
        return ", ".join(kinds) if kinds else None

    # --- parcels ----------------------------------------------------------------------------------
    parcels = []
    unmatched = {}
    for code, g in sorted(p_geo.items()):
        ring = outer_ring(g)
        if not ring:
            continue
        poly = to_tile(ring, t, xmin, ymax, 1)
        xs = [c[0] for c in poly]; zs = [c[1] for c in poly]
        r = (recs["parcel"].get(code) or [{}])[0]
        area = first(r, "ParcelBasicData", "ParcelArea")
        area = float(area) if area else round(g.area)
        rows = sorted(every(r, "LandPurposeList", "LandPurposeData"), key=lambda d: -float(first(d, "LandPurposeArea") or 0))
        codes = [first(d, "LandPurposeKind", "LandPurposeKindId") for d in rows]
        names = [first(d, "LandPurposeKind", "LandPurposeKindName") for d in rows]
        classes = []
        for n, pc in zip(names, codes):
            c = purpose_class(n, pc)
            if c is None:
                unmatched[n] = unmatched.get(n, 0) + 1
            elif c not in classes:
                classes.append(c)
        pct = [round(100 * float(first(d, "LandPurposeArea") or 0) / area) for d in rows] if area else []
        vals = values(code)
        land = vals.get("univ", (None, None))[0]
        addr = addresses(code)
        prop = prop_of.get(code)
        folio = first(props.get(prop, [{}])[0], "LandbookData", "LandbookFolioNr") if prop else None
        parcels.append({
            "tunnus": code, "address": address_text(addr[0]) if addr else None, "purpose": classes, "purpose_code": codes,
            "purpose_text": names, "purpose_pct": pct, "area": area, "ownership": ownership(code), "registered": None,
            "land_registry": folio, "property": prop, "municipality": muni,
            "land_value": land, "land_value_per_m2": round(land / area, 2) if land and area else None,
            "land_value_date": vals.get("univ", (None, None))[1], "land_value_fisc": vals.get("fisc", (None, None))[0],
            "ehak": atvk, "settlement": first(addr[0], "Town") if addr else None, "county": None,
            "ads_oid": first(r, "ParcelBasicData", "ParcelVARISCode"), "polygon": poly,
            "x": round((min(xs) + max(xs)) / 2, 1), "z": round((min(zs) + max(zs)) / 2, 1), "link": None})
    if unmatched:
        log("purposes without a game class: " + "; ".join(f"{k} ({v})" for k, v in sorted(unmatched.items(), key=lambda kv: -kv[1])))

    # --- buildings --------------------------------------------------------------------------------
    roofs = None
    rp = fetch_tile_lv.roofs_path(paths.raw_root(), tile)
    if os.path.exists(rp):
        roofs = np.fromfile(rp, dtype="<f4").reshape(size, size)
    ortho = None
    try:
        from extract_features import load_ortho
        ortho = load_ortho(os.path.join(tdir, meta.get("texture", "ortho.jpg")), size)
    except Exception as e:  # noqa: BLE001 - the colours are a nicety
        log(f"orthophoto not read for roof colours: {e}")
    models = []
    if use_lod2 and atvk == "0001000":
        import pickle
        cached = os.path.join(paths.raw("lv", "riga"), f"{tile}_models.pickle")   # parsing 500 MB of CityGML takes minutes
        if os.path.exists(cached):
            models = pickle.load(open(cached, "rb"))
        else:
            models = riga_lod2(box, paths.raw("lv", "riga"))
            pickle.dump(models, open(cached, "wb"))
    owner_of = {}   # model index -> building code: the outline holding most of the model's footprint
    if models:
        from shapely.strtree import STRtree
        codes = list(b_geo)
        geoms = [b_geo[c][0] for c in codes]
        tree = STRtree(geoms)
        for i, (foot, _tris) in enumerate(models):
            best, share = None, 0.0
            for j in tree.query(foot):
                s = geoms[j].intersection(foot).area / max(foot.area, 1e-6)
                if s > share:
                    best, share = codes[j], s
            if best and share > 0.3:
                owner_of.setdefault(best, []).append(i)
    heights = np.fromfile(os.path.join(tdir, meta["heightmap"]), dtype="<f4").reshape(size, size)

    def ground_under(poly):
        return float(min(heights[min(max(int(z), 0), size - 1), min(max(int(x), 0), size - 1)] for x, z in poly))

    import roof_fit
    roof_kinds = {}
    buildings = []
    with_year = with_lod2 = 0
    for code, (g, pcode) in sorted(b_geo.items()):
        ring = outer_ring(g)
        if not ring:
            continue
        poly = to_tile(ring, t, xmin, ymax)
        if len(poly) < 3:
            continue
        xs = [c[0] for c in poly]; zs = [c[1] for c in poly]
        bx = round((min(xs) + max(xs)) / 2, 1); bz = round((min(zs) + max(zs)) / 2, 1)
        r = (recs["building"].get(code) or [{}])[0]
        basic = first(r, "BuildingBasicData") or {}
        use_id = first(basic, "BuildingUseKind", "BuildingUseKindId")
        yr = first(basic, "BuildingExploitYear")
        try:
            yr = int(yr) if yr and int(yr) > 1000 else None
        except ValueError:
            yr = None
        with_year += yr is not None
        floors = first(basic, "BuildingGroundFloors")
        floors = int(float(floors)) if floors else None
        h = fetch_buildings.canopy_height(poly, roofs)
        if h is None or h < 2.0:
            h = (floors or 1) * 3.2
        kind = building_kind(use_id)
        mats = materials(r)
        wall_color = fetch_buildings.pick_color(mats.get("facade") or mats.get("wall_type"), FACADE_COLORS, fetch_buildings.COLORS[kind])
        roof_color = fetch_buildings.pick_color(mats.get("roof_cover"), ROOF_COLORS, [k * 0.45 for k in fetch_buildings.COLORS[kind]])
        seen = fetch_buildings.roof_colour(poly, ortho)
        if seen:
            roof_color = [round(0.75 * seen[i] + 0.25 * roof_color[i], 3) for i in range(3)]
        model = None
        roof_source = None
        if code in owner_of:
            tris = [tri for i in owner_of[code] for tri in models[i][1]]
            model = lod2_record(merge_faces(tris), t, xmin, ymax, bx, bz, ground_under(poly))
            if model:
                with_lod2 += 1
                roof_source = "lod2"
                h = max(h, round(model["z_max"] - model["z_min"], 1))
        if model is None and roofs is not None:
            # no model: a roof fitted to the building-class laser heights (roof_fit.py), pitched where
            # the points show a ridge, else the flat roof at the measured height the engine draws anyway
            roof = roof_fit.fit(poly, roofs)
            if roof is not None:
                roof_kinds[roof["kind"]] = roof_kinds.get(roof["kind"], 0) + 1
                if roof["kind"] != "flat":
                    g = ground_under(poly)
                    model = {"z_min": round(g, 2), "z_max": round(g + roof["ridge"], 2), "faces": roof_fit.faces(roof, bx, bz),
                             "roof": roof["kind"]}
                    roof_source = "laser"
                h = round(float(roof["ridge"]), 1)
        addr = addresses(code)
        on = [c for c in every(basic, "ParcelCadastreNrList", "ObjectCadastreNrData") if isinstance(c, str)] or ([pcode] if pcode else [code[:11]])
        var_code = first(basic, "VARISCode")
        buildings.append({
            "id": int(code), "ehr": code, "lod2": model, "roof_source": roof_source, "polygon": poly, "x": bx, "z": bz,
            "w": round(max(xs) - min(xs), 1), "d": round(max(zs) - min(zs), 1), "h": round(float(h), 1),
            "floors": floors, "year": yr, "name": first(basic, "BuildingName"), "purpose": first(basic, "BuildingUseKind", "BuildingUseKindName"),
            "purpose_code": use_id, "status": first(basic, "BuildingDeprecation"), "type": first(r, "BuildingTypeData", "BuildingKind", "BuildingKindName"),
            "address": address_text(addr[0]) if addr else None, "kind": kind, "color": fetch_buildings.COLORS[kind],
            "wall_color": wall_color, "roof_color": roof_color, "korgus_m": None, "materials": mats,
            "chimney": kind == "dwelling", "solar": False, "well": False, "monument": False,
            "ads": {"var_code": var_code} if var_code else None, "addresses": sorted({address_text(a) for a in addr if address_text(a)}),
            "cadastral": sorted(set(on)),
        })
    buildings.sort(key=lambda b: (b["z"], b["x"]))

    # --- write ------------------------------------------------------------------------------------
    valued = [u for u in parcels if u.get("land_value")]
    summary = {"ehak": [atvk], "settlements": sorted({u["settlement"] for u in parcels if u.get("settlement")}),
               "municipalities": [muni], "county": None, "n_valued": len(valued), "total_land_value": sum(u["land_value"] for u in valued)}
    val = dict(VALUATION, year=int((valued[0].get("land_value_date") or year)[:4]) if valued else None)
    json.dump({"attribution": ATTRIBUTION["cadastre"].format(year=year) + "; " + ATTRIBUTION["addresses"].format(year=year),
               "source": resource_url(SPATIAL, lambda r: r["url"].endswith(f"/{atvk}_kk_shp.zip")), "fetched": time.strftime("%Y-%m-%d"),
               "country": "lv", "valuation": val, "summary": summary, "parcels": parcels},
              open(os.path.join(site_dir, "parcels.json"), "w"), ensure_ascii=False)
    attr = {"cadastre": ATTRIBUTION["cadastre"].format(year=year), "addresses": ATTRIBUTION["addresses"].format(year=year)}
    if with_lod2:
        attr["lod2"] = ATTRIBUTION["lod2"]
    # compact: Rīga's LOD2 faces make this ten times an Estonian pack's file, which the game parses on entry
    json.dump({"attribution": attr, "fetched": time.strftime("%Y-%m-%d"), "country": "lv", "buildings": buildings},
              open(os.path.join(site_dir, "buildings.json"), "w"), ensure_ascii=False, separators=(",", ":"))
    kinds = {}
    for u in parcels:
        k = u["purpose"][0] if u["purpose"] else "?"
        kinds[k] = kinds.get(k, 0) + 1
    log(f"wrote sites/{site}/parcels.json: {len(parcels)} units {dict(sorted(kinds.items(), key=lambda kv: -kv[1]))}; "
        f"{len(valued)}/{len(parcels)} valued, total {summary['total_land_value']:,} EUR")
    log(f"wrote sites/{site}/buildings.json: {len(buildings)} buildings, {with_year} dated, {with_lod2} with LOD2 roofs "
        f"({len(models)} models under the tile); roofs fitted to the laser points: {roof_kinds}")
    return parcels, buildings


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--site", required=True)
    ap.add_argument("--root", default=ROOT)
    ap.add_argument("--no-lod2", action="store_true", help="skip Rīga's LOD2 models (flat roofs at the measured height)")
    a = ap.parse_args()
    fetch(a.site, a.root, not a.no_lod2)
