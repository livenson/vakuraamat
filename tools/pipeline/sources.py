#!/usr/bin/env python3
"""Country data adapters: where a tile's ground, pictures, buildings and trees come from.

Everything the pipeline needs for a place is behind one interface, so a second country is a second
adapter, not a second pipeline. `for_point(x, y, crs)` returns the adapter covering the point.

    python3 tools/pipeline/sources.py --list
    python3 tools/pipeline/sources.py --check 657600 6477150

Implemented: Estonia (Maa-amet DTM 1 m, nDSM, orthophoto WMS, historical maps WMS, in-ADS gazetteer,
ETAK + Building Register + Geo3D LOD2 buildings, Geo3D single trees). The rest of the world has a
documented plan and no code yet (see docs/custom-sites.md, "Other countries").
"""
import argparse, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


class DataSource:
    """What a country adapter provides. Optional layers return None / [] when unavailable."""
    id = "base"
    name = "abstract"
    crs = None                 # projected metric CRS the tile is built in (EPSG code)
    bbox = None                # coverage in that CRS: (xmin, ymin, xmax, ymax)
    attribution = ""
    historical_layers = {}     # {year_upper_bound: (layer, file stem, strength, tint)}

    def covers(self, x, y):
        return self.bbox is not None and self.bbox[0] <= x <= self.bbox[2] and self.bbox[1] <= y <= self.bbox[3]

    # --- the ground -----------------------------------------------------------------------------
    def dem(self, xmin, ymin, xmax, ymax, out_r32, raw_dir):
        """1 m float32 heightmap for the bbox (row 0 = north)."""
        raise NotImplementedError

    def ortho(self, xmin, ymin, xmax, ymax, out_jpg, px):
        raise NotImplementedError

    def canopy(self, xmin, ymin, xmax, ymax, out_r32, raw_dir):
        """Height above ground (nDSM), or None."""
        return None

    def historical(self, xmin, ymin, xmax, ymax, layer, out_png, px):
        """A historical map picture for the bbox, or None."""
        return None

    # --- the things on it -----------------------------------------------------------------------
    def buildings(self, site, root):
        return []

    def trees(self, site, root):
        return []

    # --- places -----------------------------------------------------------------------------------
    def geocode(self, query):
        """[{name, x, y}] in the adapter's CRS."""
        return []

    def reverse(self, x, y):
        """Municipality / place name at a point, or ''."""
        return ""


class Estonia(DataSource):
    id = "ee"
    name = "Estonia (Maa- ja Ruumiamet, Ehitisregister)"
    crs = 3301
    bbox = (369000, 6377000, 740000, 6635000)
    attribution = "Map data: Maa- ja Ruumiamet; buildings: ETAK, Ehitisregister, Geo3D"
    historical_layers = {1923: ("yheverstakaart", "verst", 0.45, (0.93, 0.88, 0.72)), 1945: ("kk1940", "cadastral", 0.4, (1.0, 0.97, 0.9)),
                         1991: ("nltopo_c63_10T", "soviet10k", 0.4, (0.95, 0.95, 0.9)), 2005: ("vanaBaaskaart", "baaskaart", 0.4, (0.97, 0.97, 0.95))}

    # The Estonian steps live in fetch_tile.py (ground), fetch_buildings.py and fetch_trees.py; this
    # adapter names them so a second country can be added beside them without touching the callers.
    def dem(self, xmin, ymin, xmax, ymax, out_r32, raw_dir):
        import fetch_tile
        return fetch_tile.fetch_dem(xmin, ymin, xmax, ymax, out_r32, raw_dir)

    def ortho(self, xmin, ymin, xmax, ymax, out_jpg, px):
        import fetch_tile
        return fetch_tile.fetch_ortho(xmin, ymin, xmax, ymax, out_jpg, px)

    def buildings(self, site, root):
        import fetch_buildings
        return fetch_buildings.fetch(site, root)

    def trees(self, site, root):
        import fetch_trees
        return fetch_trees.fetch(site, root)

    def geocode(self, query):
        import json, urllib.parse, urllib.request
        url = "https://inaadress.maaamet.ee/inaadress/gazetteer?results=8&features=EHAK,TANAV,KATASTRIYKSUS,EHITISHOONE&address=" + urllib.parse.quote(query)
        d = json.load(urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "vakuraamat/0.1"}), timeout=20))
        return [{"name": a.get("pikkaadress") or a.get("ipikkaadress") or query, "x": float(a["viitepunkt_x"]), "y": float(a["viitepunkt_y"])}
                for a in d.get("addresses", []) if a.get("viitepunkt_x")]

    def reverse(self, x, y):
        import fetch_buildings
        names = fetch_buildings.municipalities(x - 1, y - 1, x + 1, y + 1)
        return names[0] if names else ""


# Planned adapters (no code yet). Each needs: a metric CRS, a DEM (ideally lidar 1 m), an orthophoto
# service, optional canopy, historical maps, buildings, trees, and a geocoder.
PLANNED = {
    "fi": "Finland: NLS 2 m DEM and orthophotos (open, API key), NLS topographic DB buildings, National Archives historical maps",
    "lv": "Latvia: LGIA lidar DEM and orthophoto (open), cadastre buildings",
    "nl": "Netherlands: AHN 0.5 m DEM, PDOK orthophoto, BAG buildings with construction year, 3D BAG (LOD2)",
    "dk": "Denmark: Dataforsyningen DEM 0.4 m, orthophoto, BBR buildings",
    "ch": "Switzerland: swissALTI3D 0.5 m, SWISSIMAGE, swissBUILDINGS3D (LOD2)",
    "uk": "United Kingdom: DEFRA lidar 1 m (England), OS OpenMap buildings; orthophoto not open",
    "us": "United States: USGS 3DEP 1 m lidar, NAIP orthophoto, Microsoft building footprints",
    "world": "Fallback: Copernicus GLO-30 DEM + ESA WorldCover 10 m + OSM buildings; too coarse for a walkable 1 km² at this game's scale",
}

SOURCES = [Estonia()]


def for_point(x, y, crs=3301):
    for s in SOURCES:
        if s.crs == crs and s.covers(x, y):
            return s
    return None


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--check", nargs=2, type=float, metavar=("X", "Y"))
    a = ap.parse_args()
    if a.list or not a.check:
        for s in SOURCES:
            print(f"{s.id:6s} implemented  {s.name}  EPSG:{s.crs}")
        for k, v in PLANNED.items():
            print(f"{k:6s} planned      {v}")
    if a.check:
        s = for_point(*a.check)
        print(f"({a.check[0]:.0f}, {a.check[1]:.0f}) -> {s.name if s else 'no adapter covers this point'}")
