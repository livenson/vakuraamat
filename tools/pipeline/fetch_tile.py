#!/usr/bin/env python3
"""
Vakuraamat terrain pipeline, step 1 of 2: Maa-amet open data -> engine-ready files.

Fetches a 1 m DTM sheet and a matching orthophoto for a square area of interest
(AOI) in EPSG:3301 (L-EST97), clips them, and writes:

    <out>/heightmap.r32        raw float32 little-endian, row-major, row 0 = north,
                               metres above sea level (EH2000). 1 px = 1 m.
    <out>/ortho.jpg            true-colour orthophoto, same extent as the heightmap
    <out>/canopy.r32           vegetation/object height above ground in metres (1 m nDSM,
                               falling back to the 1:20000 CHM), same layout as heightmap.r32
    <out>/terrain_meta.json    extent, sheet number, height range, attribution

Step 2 (tools/godot/import_terrain.gd) turns these into Terrain3D region files.

Only needs python3 (stdlib), curl-free (urllib), and the GDAL command line tools
(rasterio, pyogrio, shapely and pyproj wheels; no GDAL install). QGIS is not required.

Examples:
    python3 tools/pipeline/fetch_tile.py --site kvissentali            # centre, size, tile and era maps from sites/<site>/site.json
    python3 tools/pipeline/fetch_tile.py --name palmse --center 613372 6598710
    python3 tools/pipeline/fetch_tile.py --site palupera --only-era-maps   # just the historical ground maps (WMS)

Era ground maps come from the Maa-amet historical WMS (kaart.maaamet.ee/wms/ajalooline, EPSG:3301):
    --era-map kk1940:era_1938_cadastral.png      schematic cadastral map 1930-1944
    --era-map yheverstakaart:era_1798_verst.png  one-verst map 1894-1922
Sheets: an AOI that crosses 1:10 000 sheet borders is mosaicked (rasterio.merge).

Sheet numbers can be looked up from a point automatically (downloads the
1:10 000 map sheet grid once into data_raw/).
"""
import argparse
import datetime as dt
import json
import time
import os
import re
import shutil
import sys
import urllib.parse
import urllib.request
import zipfile

GEOPORTAL_SEARCH = "https://geoportaal.maaamet.ee/index.php?lang_id=1&plugin_act=otsing&page_id=614"
GEOPORTAL_BASE = "https://geoportaal.maaamet.ee/"
GRID_ZIP = "https://geoportaal.maaamet.ee/docs/pohikaart/epk10T_SHP.zip"
GRID2T_ZIP = "https://geoportaal.maaamet.ee/docs/pohikaart/epk2T_SHP.zip"
WMS = "https://kaart.maaamet.ee/wms/fotokaart"
WMS_HISTORICAL = "https://kaart.maaamet.ee/wms/ajalooline"
WMS_MAX_PX = 4096
ATTRIBUTION = "Map data: Maa- ja Ruumiamet (Estonian Land and Spatial Development Board), {year}"


sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import geo  # noqa: E402

PROGRESS = None   # the tile service sets a callback(frac, text) when it runs this in-process


def log(msg):
    print(f"[fetch_tile] {msg}", flush=True)


def progress(frac, text):
    """The job's stage: a callback when the tile service runs the fetch in-process, else a line
    `[progress] <0..1> <text>` on stdout."""
    if PROGRESS:
        PROGRESS(frac, text)
    else:
        print(f"[progress] {frac:.3f} {text}", flush=True)


def download(url, dest, post=None, label=None, span=None):
    """Fetch `url` to `dest` (cached). With `label` and `span` = (f0, f1) it reports progress lines while
    it downloads: "<label> 12/74 MB, 3.1 MB/s", the fraction moving from f0 to f1."""
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        log(f"reusing {dest}")
        return dest
    log(f"downloading {url}")
    req = urllib.request.Request(url, data=post, headers={"User-Agent": "vakuraamat-pipeline/0.1"})
    tmp = dest + ".part"
    with urllib.request.urlopen(req, timeout=600) as r, open(tmp, "wb") as f:
        total = int(r.headers.get("Content-Length") or 0)
        done = 0
        t0 = last = time.time()
        while True:
            chunk = r.read(1 << 18)
            if not chunk:
                break
            f.write(chunk)
            done += len(chunk)
            now = time.time()
            if label and span and now - last >= 0.5:
                last = now
                speed = done / max(now - t0, 0.001) / 1e6
                part = done / total if total else 0.0
                size = f"{done / 1e6:.0f}/{total / 1e6:.0f} MB" if total else f"{done / 1e6:.0f} MB"
                progress(span[0] + (span[1] - span[0]) * part, f"{label} {size}, {speed:.1f} MB/s")
    os.replace(tmp, dest)
    log(f"saved {dest} ({os.path.getsize(dest) / 1e6:.1f} MB)")
    return dest


def sheet_for_point(x, y, raw_dir):
    """Map a L-EST97 point to its 1:10 000 map sheet number (5-digit NR)."""
    grid_dir = os.path.join(raw_dir, "epk10T")
    shp = os.path.join(grid_dir, "epk10T.shp")
    if not os.path.exists(shp):
        os.makedirs(grid_dir, exist_ok=True)
        z = download(GRID_ZIP, os.path.join(raw_dir, "epk10T_SHP.zip"))
        with zipfile.ZipFile(z) as zf:
            zf.extractall(grid_dir)
    nums = geo.sheet_numbers(shp, (x, y, x + 0.001, y + 0.001))
    if not nums:
        sys.exit(f"no map sheet found for point {x},{y}")
    return nums[0]


def geoportal_links(sheet, kind):
    """Ask the geoportal download form for a sheet's files of one type. Sheet numbering
    depends on the product: DTM uses 1:10000 sheets (5 digits), CHM 1:20000 (4 digits),
    1 m nDSM 1:2000 (6 digits)."""
    body = urllib.parse.urlencode({"andmetyyp": kind, "kaardiruut": sheet}).encode()
    req = urllib.request.Request(GEOPORTAL_SEARCH, data=body, headers={"User-Agent": "vakuraamat-pipeline/0.1"})
    html = urllib.request.urlopen(req, timeout=60).read().decode("utf-8", "ignore")
    links = [l.replace("&amp;", "&") for l in re.findall(r'href="([^"]*dl=1[^"]*\.tif[^"]*)"', html)]
    return [urllib.parse.urljoin(GEOPORTAL_BASE, l) for l in links]


def dtm_download_url(sheet, kind="dem_1m_geotiff"):
    """Newest DTM link for a 1:10000 sheet."""
    links = geoportal_links(sheet, kind)
    if not links:
        sys.exit(f"geoportal returned no {kind} files for sheet {sheet}")
    # Files look like 64913_dtm_1m.tif (latest ALS cycle) and 64913_dem_1m_2017-2020.tif (older cycle).
    links.sort(key=lambda l: ("_dtm_" not in l, l))
    return links[0]


def link_year(url):
    m = re.findall(r"(20\d\d)", urllib.parse.parse_qs(urllib.parse.urlparse(url).query).get("f", [""])[0])
    return int(m[-1]) if m else 0


def sheets_2000_for_bbox(xmin, ymin, xmax, ymax, raw_dir):
    """1:2000 sheet numbers intersecting a bbox (each covers 1 x 1 km)."""
    grid_dir = os.path.join(raw_dir, "epk2T")
    shp = os.path.join(grid_dir, "epk2T.shp")
    if not os.path.exists(shp):
        os.makedirs(grid_dir, exist_ok=True)
        z = download(GRID2T_ZIP, os.path.join(raw_dir, "epk2T_SHP.zip"))
        with zipfile.ZipFile(z) as zf:
            zf.extractall(grid_dir)
    return geo.sheet_numbers(shp, (xmin + 1, ymin + 1, xmax - 1, ymax - 1))


def fetch_canopy(a, raw_dir, out_dir, xmin, ymin, xmax, ymax):
    """Write canopy.r32: height above ground (m) per metre. Prefer the 1 m nDSM (trees AND
    buildings), else the 1:20000 CHM (trees only, coarser) resampled to 1 m."""
    tifs = []
    source = None
    for sheet in sheets_2000_for_bbox(xmin, ymin, xmax, ymax, raw_dir):
        links = sorted(geoportal_links(sheet, "ndsm_rel_1m_geotiff"), key=link_year)
        if links:
            name = urllib.parse.parse_qs(urllib.parse.urlparse(links[-1]).query)["f"][0]
            tifs.append(download(links[-1], os.path.join(raw_dir, name)))
    if tifs:
        source = "ndsm_rel_1m (1:2000 sheets %s)" % ",".join(os.path.basename(t) for t in tifs)
    else:
        sheet20 = str(a.sheet or "")[:4]
        links = sorted(geoportal_links(sheet20, "chm_geotiff"), key=link_year)
        if not links:
            log("no nDSM or CHM available; skipping canopy layer")
            return None
        name = urllib.parse.parse_qs(urllib.parse.urlparse(links[-1]).query)["f"][0]
        tifs.append(download(links[-1], os.path.join(raw_dir, name)))
        source = "chm (1:20000 sheet %s, %s)" % (sheet20, name)
    clipped = os.path.join(raw_dir, f"{a.name}_canopy_{a.size}m.tif")
    # exactly the heightmap grid whatever the source resolution (bilinear); NoData -> 0 (no vegetation)
    data, zmax = geo.warp_canopy(tifs, (xmin, ymin, xmax, ymax), clipped)
    raw_out = os.path.join(raw_dir, f"{a.name}_canopy.r32")
    geo.write_r32(data, raw_out)
    shutil.copyfile(raw_out, os.path.join(out_dir, "canopy.r32"))
    log(f"canopy layer from {source}: 0..{zmax:.1f} m")
    return {"file": "canopy.r32", "source": source, "max_height": round(zmax, 2),
            "format": "float32 little-endian, row-major, row 0 = north; metres above ground; 0 = nothing"}


def fetch_era_maps(era_maps, out_dir, xmin, ymin, xmax, ymax, px):
    """Historical ground maps for the same extent from the Maa-amet historical WMS: {file: layer}."""
    done = {}
    for fname, layer in era_maps.items():
        q = {"SERVICE": "WMS", "VERSION": "1.3.0", "REQUEST": "GetMap", "LAYERS": layer, "STYLES": "", "CRS": "EPSG:3301",
             "BBOX": f"{ymin},{xmin},{ymax},{xmax}", "WIDTH": px, "HEIGHT": px, "FORMAT": "image/png"}
        path = os.path.join(out_dir, fname)
        if os.path.exists(path):
            os.remove(path)
        download(WMS_HISTORICAL + "?" + urllib.parse.urlencode(q), path)
        with open(path, "rb") as f:
            if f.read(4) != b"\x89PNG":
                sys.exit(f"historical WMS did not return a PNG for layer {layer} - see {path}")
        done[fname] = {"layer": layer, "source": WMS_HISTORICAL}
        log(f"era map {layer} -> {fname}")
    return done


def fetch_dem(xmin, ymin, xmax, ymax, out_r32, raw_dir, name="tile"):
    """Estonian 1 m DTM for a bbox as raw float32 (mosaics the 1:10 000 sheets it touches). Returns (zmin, zmax, sheets)."""
    sheets = sorted({sheet_for_point(x, y, raw_dir) for x, y in [(xmin + 1, ymin + 1), (xmax - 1, ymin + 1), (xmin + 1, ymax - 1), (xmax - 1, ymax - 1)]})
    paths = []
    for sh in sheets:
        url = dtm_download_url(sh)
        fname = urllib.parse.parse_qs(urllib.parse.urlparse(url).query)["f"][0]
        paths.append(download(url, os.path.join(raw_dir, fname)))
    clipped = os.path.join(raw_dir, f"{name}_dtm_{int(xmax - xmin)}m.tif")
    data, zmin, zmax = geo.clip_dem(paths, (xmin, ymin, xmax, ymax), clipped)   # mosaicked, NoData filled
    raw_out = os.path.join(raw_dir, f"{name}_heightmap.r32")
    geo.write_r32(data, raw_out)
    shutil.copyfile(raw_out, out_r32)
    return zmin, zmax, sheets



def fetch_ortho(xmin, ymin, xmax, ymax, out_jpg, px):
    """Latest nationwide orthophoto (EESTIFOTO) for a bbox from the fotokaart WMS, as JPEG."""
    px = min(px, WMS_MAX_PX)
    q = {"SERVICE": "WMS", "VERSION": "1.3.0", "REQUEST": "GetMap", "LAYERS": "EESTIFOTO", "STYLES": "",
         "CRS": "EPSG:3301", "BBOX": f"{ymin},{xmin},{ymax},{xmax}", "WIDTH": px, "HEIGHT": px, "FORMAT": "image/jpeg"}
    if os.path.exists(out_jpg):
        os.remove(out_jpg)
    download(WMS + "?" + urllib.parse.urlencode(q), out_jpg)
    with open(out_jpg, "rb") as f:
        if f.read(3) != b"\xff\xd8\xff":
            sys.exit("WMS did not return a JPEG (service exception?) - see ortho.jpg")
    return out_jpg


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--site", help="read tile name, centre, size and era maps from sites/<site>/site.json")
    ap.add_argument("--name", help="tile name, becomes assets/terrain/<name>/")
    ap.add_argument("--center", nargs=2, type=float, metavar=("X", "Y"), help="AOI centre in EPSG:3301 (easting northing)")
    ap.add_argument("--era-map", action="append", default=[], metavar="LAYER:FILE",
                    help="historical WMS layer to save as assets/terrain/<name>/FILE (repeatable)")
    ap.add_argument("--only-era-maps", action="store_true", help="fetch just the era maps (no DTM/orthophoto/canopy)")
    ap.add_argument("--map-px", type=int, default=2048, help="era map size in pixels (default 2048)")
    ap.add_argument("--size", type=int, default=1024, help="AOI edge length in metres (default 1024 = one Terrain3D region)")
    ap.add_argument("--sheet", help="1:10000 map sheet number; looked up from --center if omitted")
    ap.add_argument("--texture-px", type=int, default=WMS_MAX_PX, help="orthophoto size in pixels (max 4096 per WMS request)")
    ap.add_argument("--z-scale", type=float, default=1.0, help="vertical exaggeration recorded in meta (applied at import time)")
    ap.add_argument("--no-canopy", action="store_true", help="skip the nDSM/CHM canopy layer")
    ap.add_argument("--project", default=os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
                    help="project root (default: repo root)")
    ap.add_argument("--raw-dir", help="download cache (default: <project>/data_raw)")
    a = ap.parse_args(argv)
    era_maps = {}
    for em in a.era_map:
        layer, _, fname = em.partition(":")
        era_maps[fname or f"era_{layer}.png"] = layer
    if a.site:
        mpath = os.path.join(a.project, "sites", a.site, "site.json")
        if not os.path.exists(mpath):
            sys.exit(f"no such site: {mpath}")
        t = json.load(open(mpath)).get("terrain", {})
        a.name = a.name or t.get("tile", a.site)
        a.center = a.center or t.get("center")
        a.size = t.get("size", a.size)
        for era_id, spec in t.get("era_maps", {}).items():
            era_maps.setdefault(spec.get("file", f"{era_id}.png"), spec["layer"])
    if not a.name or not a.center:
        sys.exit("--name and --center are required unless --site is given")

    raw_dir = a.raw_dir or os.path.join(a.project, "data_raw")
    out_dir = os.path.join(a.project, "assets", "terrain", a.name)
    os.makedirs(raw_dir, exist_ok=True)
    os.makedirs(out_dir, exist_ok=True)
    # Keep Godot's importer out of the raw GeoTIFF/ENVI files.
    open(os.path.join(raw_dir, ".gdignore"), "a").close()

    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import sources
    if sources.for_point(a.center[0], a.center[1]) is None:
        sys.exit("no data adapter covers this point (tools/pipeline/sources.py --list); only Estonia is implemented")
    half = a.size / 2
    xmin, ymin = int(round(a.center[0] - half)), int(round(a.center[1] - half))
    xmax, ymax = xmin + a.size, ymin + a.size
    log(f"AOI EPSG:3301 x {xmin}..{xmax}  y {ymin}..{ymax}  ({a.size} m)")

    meta_path = os.path.join(out_dir, "terrain_meta.json")
    if a.only_era_maps:
        fetched = fetch_era_maps(era_maps, out_dir, xmin, ymin, xmax, ymax, a.map_px)
        if os.path.exists(meta_path):
            meta = json.load(open(meta_path))
            meta.setdefault("era_maps", {}).update(fetched)
            json.dump(meta, open(meta_path, "w"), indent=2)
        return
    if a.size > 2048:
        log("warning: Terrain3D regions are at most 2048 m; larger tiles need several regions")

    # Every 1:10 000 sheet the AOI touches (one per corner); mosaicked when there is more than one.
    sheets = a.sheet.split(",") if a.sheet else sorted({sheet_for_point(x, y, raw_dir) for x, y in
                                                        [(xmin + 1, ymin + 1), (xmax - 1, ymin + 1), (xmin + 1, ymax - 1), (xmax - 1, ymax - 1)]})
    a.sheet = sheets[0]
    log(f"map sheet(s) {','.join(sheets)}")
    progress(0.02, "map sheets " + ",".join(sheets))

    # --- DTM ---------------------------------------------------------------
    dtm_urls, dtm_paths = [], []
    for i, sh in enumerate(sheets):
        url = dtm_download_url(sh)
        fname = urllib.parse.parse_qs(urllib.parse.urlparse(url).query)["f"][0]
        dtm_urls.append(url)
        cached = os.path.exists(os.path.join(raw_dir, fname))
        f0, f1 = 0.05 + 0.4 * i / len(sheets), 0.05 + 0.4 * (i + 1) / len(sheets)
        text = f"1 m ground model, sheet {sh} ({i + 1}/{len(sheets)})"
        progress(f0, text + (", cached" if cached else ""))
        dtm_paths.append(download(url, os.path.join(raw_dir, fname), label=text, span=(f0, f1)))
    progress(0.5, "clipping the ground model")
    dtm_url = dtm_urls[0]
    dtm_name = ",".join(os.path.basename(p) for p in dtm_paths)
    clipped = os.path.join(raw_dir, f"{a.name}_dtm_{a.size}m.tif")
    # the sheets mosaicked and clipped; water bodies etc. may be NoData: interpolated across so the mesh has no holes
    data, zmin, zmax = geo.clip_dem(dtm_paths, (xmin, ymin, xmax, ymax), clipped)
    log(f"height range {zmin:.2f}..{zmax:.2f} m")

    # Raw float32: Godot reads it with Image.create_from_data(FORMAT_RF) - no codec surprises.
    # (Godot's PNG loader drops 16-bit to 8-bit and its EXR loader rejects GDAL's channel naming.)
    raw_out = os.path.join(raw_dir, f"{a.name}_heightmap.r32")
    geo.write_r32(data, raw_out)
    shutil.copyfile(raw_out, os.path.join(out_dir, "heightmap.r32"))
    expected = a.size * a.size * 4
    got = os.path.getsize(os.path.join(out_dir, "heightmap.r32"))
    if got != expected:
        sys.exit(f"heightmap.r32 is {got} bytes, expected {expected}")

    # --- Orthophoto via WMS (EESTIFOTO = latest nationwide orthophoto) -----
    px = min(a.texture_px, WMS_MAX_PX)
    q = {
        "SERVICE": "WMS", "VERSION": "1.3.0", "REQUEST": "GetMap", "LAYERS": "EESTIFOTO", "STYLES": "",
        "CRS": "EPSG:3301", "BBOX": f"{ymin},{xmin},{ymax},{xmax}",  # WMS 1.3 axis order for EPSG:3301 is northing,easting
        "WIDTH": px, "HEIGHT": px, "FORMAT": "image/jpeg",
    }
    progress(0.56, "orthophoto, 25 cm")
    ortho_path = os.path.join(out_dir, "ortho.jpg")
    if os.path.exists(ortho_path):
        os.remove(ortho_path)
    download(WMS + "?" + urllib.parse.urlencode(q), ortho_path, label="orthophoto, 25 cm", span=(0.56, 0.61))
    with open(ortho_path, "rb") as f:
        if f.read(3) != b"\xff\xd8\xff":
            sys.exit("WMS did not return a JPEG (service exception?) - see ortho.jpg")

    # --- Canopy / object heights --------------------------------------------
    progress(0.62, "canopy heights (nDSM)")
    canopy = fetch_canopy(a, raw_dir, out_dir, xmin, ymin, xmax, ymax) if not a.no_canopy else None

    # --- Historical ground maps for the eras ----------------------------------
    progress(0.9, "historical maps" if era_maps else "writing the tile")
    fetched_maps = fetch_era_maps(era_maps, out_dir, xmin, ymin, xmax, ymax, a.map_px)

    # --- Metadata ----------------------------------------------------------
    today = dt.date.today().isoformat()
    meta = {
        "name": a.name,
        "crs": "EPSG:3301",
        "sheet": sheets[0],
        "xmin": xmin, "ymin": ymin, "xmax": xmax, "ymax": ymax,
        "size_m": a.size,
        "size_px": a.size,
        "resolution_m": 1.0,
        "heightmap": "heightmap.r32",
        "heightmap_format": "float32 little-endian, row-major, row 0 = north edge (ymax), metres EH2000",
        "z_min": round(zmin, 3), "z_max": round(zmax, 3),
        "z_scale": a.z_scale,
        "texture": "ortho.jpg",
        "texture_px": px,
        "canopy": canopy,
        "era_maps": fetched_maps,
        "world_mapping": "Godot x = easting - xmin; Godot z = ymax - northing (north is -Z); y = height * z_scale",
        "source": {"dtm": dtm_url, "dtm_files": dtm_name, "dtm_sheets": sheets, "ortho_wms": WMS, "ortho_layer": "EESTIFOTO", "historical_wms": WMS_HISTORICAL},
        "fetched": today,
        "attribution": ATTRIBUTION.format(year=today[:4]),
        "license": "Maa-amet open data licence (free use with attribution)",
    }
    with open(meta_path, "w") as f:
        json.dump(meta, f, indent=2)
    log(f"wrote {out_dir}/{{heightmap.r32, ortho.jpg, terrain_meta.json}}")
    log("next: godot --headless --path . -s res://tools/godot/import_terrain.gd -- --tile=" + a.name + (" --site=" + a.site if a.site else ""))


if __name__ == "__main__":
    main()
