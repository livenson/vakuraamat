"""Raster and vector work for the pipeline through Python wheels instead of the GDAL command line:
rasterio (mosaic, clip, resample, fill), pyogrio + shapely (map-sheet grids, FileGDB and GeoPackage
reads) and pyproj (L-EST97 <-> WGS84). Keeps the pipeline pip-installable and lets the tile service
ship as one executable beside the game (tools/service/build.sh)."""
import csv, json, os

import numpy as np


def features(path, bbox=None, layer=None):
    """Features of a vector file (shapefile, FileGDB, GeoPackage): [(properties dict, shapely geometry)].
    `bbox` (xmin, ymin, xmax, ymax) filters by intersection where the driver supports it."""
    import pyogrio
    import shapely
    meta, _index, geoms, fields = pyogrio.raw.read(path, layer=layer, bbox=bbox, force_2d=False)
    names = list(meta["fields"])
    out = []
    for i, wkb in enumerate(geoms):
        props = {names[k]: (fields[k][i].item() if hasattr(fields[k][i], "item") else fields[k][i]) for k in range(len(names))}
        out.append((props, shapely.from_wkb(wkb) if wkb is not None else None))
    return out


def sheet_numbers(shp, bbox, field="NR"):
    """Map-sheet numbers (as strings) of a grid shapefile touching `bbox`."""
    return sorted({str(p[field]) for p, _g in features(shp, bbox=bbox) if p.get(field) is not None})


def transform_points(points, src_epsg, dst_epsg):
    """[(x, y)] from one CRS to another, axis order always x/east then y/north."""
    from pyproj import Transformer
    t = Transformer.from_crs(f"EPSG:{src_epsg}", f"EPSG:{dst_epsg}", always_xy=True)
    return [t.transform(x, y) for x, y in points]


def clip_dem(paths, bbox, out_tif=None, fill=True):
    """The 1 m ground model over `bbox` from one or more GeoTIFF sheets (mosaicked on the way):
    (float32 array rows north to south, zmin, zmax). NoData holes (water) are interpolated across."""
    import rasterio
    from rasterio.fill import fillnodata
    from rasterio.merge import merge
    xmin, ymin, xmax, ymax = bbox
    srcs = [rasterio.open(p) for p in paths]
    try:
        arr, transform = merge(srcs, bounds=(xmin, ymin, xmax, ymax), res=(1.0, 1.0), nodata=srcs[0].nodata)
        nodata = srcs[0].nodata
        crs = srcs[0].crs
    finally:
        for s in srcs:
            s.close()
    data = arr[0].astype(np.float32)
    if nodata is not None:
        mask = data != nodata
        if not mask.all() and fill:
            data = fillnodata(data, mask=mask.astype(np.uint8), max_search_distance=100.0).astype(np.float32)
            mask = np.ones_like(mask)
        valid = data[mask] if mask.any() else data
    else:
        valid = data
    if out_tif:
        with rasterio.open(out_tif, "w", driver="GTiff", height=data.shape[0], width=data.shape[1], count=1, dtype="float32",
                           crs=crs, transform=transform, compress="deflate") as dst:
            dst.write(data, 1)
    return data, float(valid.min()), float(valid.max())


def warp_canopy(paths, bbox, out_tif=None):
    """Canopy heights over `bbox` on the 1 m grid (bilinear, NoData -> 0): (float32 array, zmax)."""
    import rasterio
    from rasterio.enums import Resampling
    from rasterio.merge import merge
    xmin, ymin, xmax, ymax = bbox
    srcs = [rasterio.open(p) for p in paths]
    try:
        arr, transform = merge(srcs, bounds=(xmin, ymin, xmax, ymax), res=(1.0, 1.0), nodata=0.0, resampling=Resampling.bilinear, dtype="float32")
        crs = srcs[0].crs
    finally:
        for s in srcs:
            s.close()
    data = np.nan_to_num(arr[0].astype(np.float32), nan=0.0)
    if out_tif:
        with rasterio.open(out_tif, "w", driver="GTiff", height=data.shape[0], width=data.shape[1], count=1, dtype="float32",
                           crs=crs, transform=transform, nodata=0.0, compress="deflate") as dst:
            dst.write(data, 1)
    return data, float(data.max()) if data.size else 0.0


def write_r32(data, path):
    """A float32 array as the raw little-endian file Godot reads (row-major, row 0 north)."""
    np.ascontiguousarray(data, dtype="<f4").tofile(path)


def load_image_rgb(path, size):
    """An image resampled (box average) to size x size as float RGB in 0..1."""
    from PIL import Image
    Image.MAX_IMAGE_PIXELS = None
    im = Image.open(path).convert("RGB").resize((size, size), Image.BOX)
    return np.asarray(im, dtype=np.float32) / 255.0


def geojson_features(path, bbox, layer=None):
    """Features as GeoJSON-like dicts ({properties, geometry}) with 3D coordinates kept."""
    import shapely
    out = []
    for props, g in features(path, bbox=bbox, layer=layer):
        if g is None:
            continue
        out.append({"type": "Feature", "properties": props, "geometry": json.loads(shapely.to_geojson(g))})
    return out


def points_to_csv(path, layer, csv_path, fields):
    """Point features of a layer to a CSV with X, Y and the named fields (what ogr2ogr -lco GEOMETRY=AS_XY wrote)."""
    rows = features(path, layer=layer)
    with open(csv_path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["X", "Y"] + fields)
        for props, g in rows:
            if g is None:
                continue
            w.writerow([g.x, g.y] + [props.get(k, "") for k in fields])
    return csv_path


def exists_all(*paths):
    return all(os.path.exists(p) for p in paths)
