#!/usr/bin/env python3
"""Country data adapters: everything the pipeline and the tile service do differently per country.

A country is one adapter here and one descriptor for the game (assets/data/countries/<id>.json).
The callers - fetch_tile.py, tools/tile_service.py, cross_border.py, fetch_departures.py,
new_site.py - ask the adapter covering a point (`for_point`) or named by a pack (`by_id`) and name no
country themselves. docs/adding-a-country.md walks through adding one.

    python3 tools/pipeline/sources.py --list
    python3 tools/pipeline/sources.py --check 657600 6477150

Implemented: Estonia (Maa-amet DTM 5 m and 1 m, nDSM, orthophoto WMS, in-ADS gazetteer, the cadastre,
ETAK + Building Register + Geo3D LOD2 buildings, ETAK roads and water, Geo3D single trees, the business
register, PRIA fields, the national GTFS) and Latvia (LĢIA laser points and orthophoto cycles, VZD
cadastre and buildings, Rīga's LOD2, UR and VID companies, OpenStreetMap roads, ATD and Rīgas satiksme
GTFS, VARIS addresses; docs/latvia-plan.md). The rest of the world has a documented plan and no code
yet (PLANNED below, docs/custom-sites.md "Other countries").
"""
import argparse, json, os, sys, threading

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


class DataSource:
    """What a country adapter provides. Optional layers return None / [] when unavailable.

    The tile service's stages receive `stage(text, fraction)` or `rstage(text)` to report progress and
    `run(label, seconds, fn, *args, **kwargs) -> (ok, result)`, its time-boxed runner: a national
    service that stalls must not hold the pack."""
    id = "base"
    name = "abstract"
    label = ""                 # the agency the service's progress names: "<label> data"
    crs = None                 # projected metric CRS the tile is built in (EPSG code)
    bbox = None                # coverage in that CRS: (xmin, ymin, xmax, ymax)
    outline = None             # assets/data/<file>: the country's land (tools/pipeline/fetch_outline.py)
    own_tile = False           # the ground comes from build_tile, not fetch_tile.py's Estonian steps
    attribution = ""
    historical_layers = {}     # {year_upper_bound: (layer, file stem, strength, tint)}

    def covers(self, x, y):
        return self.bbox is not None and self.bbox[0] <= x <= self.bbox[2] and self.bbox[1] <= y <= self.bbox[3]

    def place(self, x, y):
        """Where to centre a new world asked for at (x, y): the point itself, unless the country's data
        comes in sheets that a small move saves downloading. The point must stay inside the world."""
        return x, y

    _land = None

    def land(self):
        """The country's land (shapely, L-EST97) from its outline file, or None without the file."""
        if self._land is None and self.outline:
            import paths
            path = os.path.join(paths.ROOT, "assets", "data", self.outline)
            if os.path.exists(path):
                from shapely.geometry import Polygon
                from shapely.ops import unary_union
                self._land = unary_union([Polygon(r).buffer(0) for r in json.load(open(path))["land"] if len(r) >= 3])
        return self._land

    def on_land(self, x, y):
        """Whether a point is on the country's land by its outline (300 m generalised); None when the
        outline is not at hand (the frozen sidecar without it)."""
        land = self.land()
        if land is None:
            return None
        from shapely.geometry import Point
        return land.contains(Point(x, y))

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

    def build_tile(self, a, raw_dir, out_dir, bbox):
        """The whole tile (heightmap, canopy, ortho.jpg, terrain_meta.json with "country") when own_tile."""
        raise NotImplementedError

    # --- a job, in the tile service --------------------------------------------------------------
    def estimate(self, box, raw_dir, items, head):
        """What a pack over `box` downloads: append {name, bytes, cached} to `items` (`head(url)` is a
        HEAD request's size) and return the bytes the refine pass fetches afterwards."""
        return 0

    def registers(self, sid, ws, stage, run):
        """The register stages of a job after the ground: cadastre, buildings, companies, roads, stops.
        Returns a thread still running beside the rest (the stops, at Overpass's pace), or None."""
        return None

    def refine(self, sid, ws, rstage, run):
        """What a pack does not need to be walked in, fetched after it is playable. Returns (ok, the
        ground's resolution in metres). The game's descriptor says how it recognises the result."""
        return True, 1

    def border(self, site, root):
        """This country's parcels, buildings and companies for a scratch copy of a neighbour's pack
        on the border (cross_border.py keeps the rows on this side)."""
        raise NotImplementedError

    def border_roads(self, site, root):
        """Roads on this side for a neighbour's pack whose own road source stops at the border:
        write them and return their attribution, or None when the neighbour's roads already cross."""
        return None

    def departures(self, site, root, refresh=False, max_age_days=7):
        return None

    def codex(self, name):
        """What the pack is made of, in the codex: {"CODEX_REAL" | "CODEX_INVENTED" | "CODEX_DATA":
        {"et", "en", "lv"}}."""
        return {}

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
    label = "Maa-amet"
    crs = 3301
    bbox = (369000, 6377000, 740000, 6635000)
    outline = "estonia.json"
    attribution = "Map data: Maa- ja Ruumiamet; buildings: ETAK, Ehitisregister, Geo3D"
    historical_layers = {1923: ("yheverstakaart", "verst", 0.45, (0.93, 0.88, 0.72)), 1945: ("kk1940", "cadastral", 0.4, (1.0, 0.97, 0.9)),
                         1991: ("nltopo_c63_10T", "soviet10k", 0.4, (0.95, 0.95, 0.9)), 2005: ("vanaBaaskaart", "baaskaart", 0.4, (0.97, 0.97, 0.95))}
    ORTHO_BYTES = 6 * 1024 ** 2      # the WMS orthophoto JPEG (4096 px) and the small historical maps
    CREDIT_ET = 'Maa maksustamishind 2022: Maakataster, Maa- ja Ruumiamet. Ettevõtted: Äriregistri avaandmed, Registrite ja Infosüsteemide Keskus (CC BY 4.0).'
    CREDIT_EN = 'Land values 2022: the cadastre, Maa- ja Ruumiamet. Companies: e-Business Register open data, Centre of Registers and Information Systems (CC BY 4.0).'

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

    def estimate(self, box, raw_dir, items, head):
        """The DTM sheets of the tile's corners (the 5 m ground the pack ships; the 1 m one is the
        refine pass's), the 1:2000 nDSM sheets and the orthophoto."""
        import urllib.parse
        import fetch_tile
        xmin, ymin, xmax, ymax = box

        def fname_of(url):
            return urllib.parse.parse_qs(urllib.parse.urlparse(url).query)["f"][0]

        def add(name, url):
            local = os.path.join(raw_dir, fname_of(url))
            cached = os.path.exists(local)
            items.append({"name": name, "bytes": os.path.getsize(local) if cached else head(url), "cached": cached})

        sheets = sorted({fetch_tile.sheet_for_point(px, py, raw_dir) for px, py in [(xmin + 1, ymin + 1), (xmax - 1, ymin + 1), (xmin + 1, ymax - 1), (xmax - 1, ymax - 1)]})
        refine = 0
        for sh in sheets:
            add("DTM %s (5 m)" % sh, fetch_tile.dtm_download_url(sh, "dem_5m_geotiff"))
            fine = fetch_tile.dtm_download_url(sh)   # fetched afterwards, not part of the wait
            refine += 0 if os.path.exists(os.path.join(raw_dir, fname_of(fine))) else head(fine)
        for sheet in fetch_tile.sheets_2000_for_bbox(xmin, ymin, xmax, ymax, raw_dir):
            links = sorted(fetch_tile.geoportal_links(sheet, "ndsm_rel_1m_geotiff"), key=fetch_tile.link_year)
            if links:
                add("nDSM %s" % sheet, links[-1])
        items.append({"name": "orthophoto, maps", "bytes": self.ORTHO_BYTES, "cached": False})
        return refine

    def registers(self, sid, ws, stage, run):
        import fetch_buildings, fetch_fields, fetch_parcels, fetch_roads, fetch_stops, fetch_tenants, market
        stage("building register", 0.5)
        run(f"{sid}: building register", 240, fetch_buildings.fetch, sid, root=ws, progress=lambda f, t: stage(t, 0.5 + 0.1 * f))
        stage("cadastre", 0.61)
        run(f"{sid}: cadastre", 120, fetch_parcels.fetch, sid, root=ws)
        stage("roads", 0.63)
        run(f"{sid}: roads", 120, fetch_roads.fetch, sid, root=ws)
        # Overpass queues requests for tens of seconds: the stops fetch runs beside the register stages
        stops = threading.Thread(target=lambda: run(f"{sid}: stops", 600, fetch_stops.fetch, sid, root=ws), daemon=True)
        stops.start()
        stage("fields (PRIA)", 0.635)
        run(f"{sid}: fields", 120, fetch_fields.fetch, sid, root=ws)
        stage("tenants (business register)", 0.64)
        run(f"{sid}: tenants", 180, fetch_tenants.fetch, sid, root=ws)
        stage("market snapshot", 0.66)
        run(f"{sid}: market", 60, market.derive, sid, root=ws)
        return stops

    def refine(self, sid, ws, rstage, run):
        """The 1 m ground model in place of the 5 m one, the measured trees, the timetables. The game
        takes the pack again while its ground is coarse (the descriptor's "refine": "ground")."""
        import fetch_departures, fetch_tile, fetch_trees, paths
        rstage("1 m ground model")
        ok, _ = run(f"{sid}: 1 m ground model", 900, fetch_tile.main,
                    ["--project", ws, "--site", sid, "--raw-dir", paths.raw_root(), "--dem-res", "1", "--only-dem"])
        rstage("measured trees")
        run(f"{sid}: measured trees", 600, fetch_trees.fetch, sid, root=ws)
        rstage("bus departures (public transport register)")
        # the national GTFS is one 52 MB zip for the whole country, cached a week like the register dumps
        run(f"{sid}: departures", 300, fetch_departures.fetch, sid, root=ws)
        return ok, 1 if ok else 5

    def border(self, site, root):
        import fetch_buildings, fetch_parcels, fetch_tenants
        fetch_parcels.fetch(site, root)
        fetch_buildings.fetch(site, root)
        fetch_tenants.fetch(site, root)

    def departures(self, site, root, refresh=False, max_age_days=7):
        import fetch_departures
        return fetch_departures.fetch_ee(site, root, refresh, max_age_days)

    def codex(self, name):
        return {
            "CODEX_REAL": {"et": f"Maa: {name}, Maa- ja Ruumiameti kõrgusandmed, ortofoto, hooned, katastriüksused ja maa väärtused, meetri täpsusega.",
                           "en": f"The ground: {name}, from the Land Board's elevation data, orthophoto, buildings, cadastral units and land values, to the metre.",
                           "lv": f"Zeme: {name}, no Igaunijas Zemes un telpiskās plānošanas departamenta augstuma datiem, ortofoto, ēkām, kadastra vienībām un zemes vērtībām, ar metra precizitāti."},
            "CODEX_INVENTED": {"et": "Majade seinad ja katused on taastatud ehitisregistri mõõtude ja Maa-ameti LOD2 mudeli järgi; sisemused, puud, liiklus ja möödujad on välja mõeldud. Ükski inimene siin ei kujuta päris inimest.",
                               "en": "The walls and roofs are reconstructed from the Building Register's measurements and Maa-amet's LOD2 model; the interiors, the trees, the traffic and the passers-by are invented. No person here depicts a real one.",
                               "lv": "Sienas un jumti atjaunoti pēc Ēku reģistra mēriem un Maa-amet LOD2 modeļa; interjeri, koki, satiksme un garāmgājēji ir izdomāti. Neviens cilvēks šeit neattēlo īstu cilvēku."},
            "CODEX_DATA": {"et": "Kaardiandmed: Maa- ja Ruumiamet 2026. %s" % self.CREDIT_ET,
                           "en": "Map data: Maa- ja Ruumiamet 2026. %s" % self.CREDIT_EN,
                           "lv": "Kartes dati: Maa- ja Ruumiamet 2026. Zemes nodokļa vērtības: kadastrs; uzņēmumi: Igaunijas uzņēmumu reģistra atvērtie dati (CC BY 4.0)."},
        }

    def geocode(self, query):
        import urllib.parse, urllib.request
        url = "https://inaadress.maaamet.ee/inaadress/gazetteer?results=8&features=EHAK,TANAV,KATASTRIYKSUS,EHITISHOONE&address=" + urllib.parse.quote(query)
        d = json.load(urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "vakuraamat/0.1"}), timeout=20))
        return [{"name": a.get("pikkaadress") or a.get("ipikkaadress") or query, "x": float(a["viitepunkt_x"]), "y": float(a["viitepunkt_y"])}
                for a in d.get("addresses", []) if a.get("viitepunkt_x")]

    def reverse(self, x, y):
        import fetch_buildings
        names = fetch_buildings.municipalities(x - 1, y - 1, x + 1, y + 1)
        return names[0] if names else ""


class Latvia(DataSource):
    """Latvia on the game's L-EST97 grid (docs/latvia-plan.md). A point is Latvian when LĢIA has a
    laser sheet under it and it is not on another country's land (the sheets reach over the border at Valga)."""
    id = "lv"
    name = "Latvia (LĢIA, VZD)"
    label = "LĢIA"
    crs = 3301
    bbox = (305000, 6165000, 770000, 6450000)
    outline = "latvia.json"
    own_tile = True
    attribution = "Map data: Latvijas Ģeotelpiskās informācijas aģentūra (LĢIA)"
    GROUND_ET = 'Kaardiandmed: Latvijas Ģeotelpiskās informācijas aģentūra (LĢIA) 2026, laserskaneerimine ja ortofoto 2016-2018 (CC BY 4.0).'
    GROUND_EN = 'Map data: Latvijas Ģeotelpiskās informācijas aģentūra (LĢIA) 2026, laser scanning and orthophoto 2016-2018 (CC BY 4.0).'

    def covers(self, x, y):
        if not super().covers(x, y):
            return False
        try:
            if any(s is not self and s.on_land(x, y) for s in SOURCES):
                return False
            import fetch_tile_lv
            return fetch_tile_lv.has_laser_sheet(x, y)
        except ImportError:   # a plain python3 without the pipeline's wheels (shapely, pyproj): cannot tell, so not Latvia
            return False

    def place(self, x, y):
        """The centre of the laser sheet holding the point (fetch_tile_lv.place_center): one sheet of
        170-300 MB instead of four. Unmoved when that centre would not be Latvia's (Valga's side)."""
        import fetch_tile_lv
        nx, ny = fetch_tile_lv.place_center(x, y)
        return (nx, ny) if for_point(nx, ny) is self else (x, y)

    def build_tile(self, a, raw_dir, out_dir, bbox):
        import fetch_tile_lv
        return fetch_tile_lv.build_tile(a, raw_dir, out_dir, bbox)

    def ortho(self, xmin, ymin, xmax, ymax, out_jpg, px):
        import fetch_tile_lv
        return fetch_tile_lv.fetch_ortho((xmin, ymin, xmax, ymax), out_jpg, px)

    def estimate(self, box, raw_dir, items, head):
        """The laser sheets under the tile: the ground, the canopy and the building heights all come
        from them. The orthophoto windows and the cadastre are estimated together."""
        import fetch_tile_lv
        index = fetch_tile_lv.las_index()
        keep, _, _ = fetch_tile_lv.select_sheets(box, index)   # what fetch_ground downloads: not the sheets it only grazes
        for sh in keep:
            local = os.path.join(raw_dir, "lv", "las", sh + ".las")
            cached = os.path.exists(local)
            items.append({"name": "laser points %s" % sh, "bytes": os.path.getsize(local) if cached else head(index[sh]), "cached": cached})
        items.append({"name": "orthophoto, cadastre", "bytes": 60 * 1024 ** 2, "cached": False})
        return 0

    def registers(self, sid, ws, stage, run):
        """The cadastre gives parcels and buildings in one pass, the register and VID the companies,
        OpenStreetMap the roads and stops. Fields wait for LAD's crop codes."""
        import fetch_cadastre_lv, fetch_roads_lv, fetch_stops, fetch_tenants_lv
        stage("cadastre (VZD), buildings, Rīga's roofs", 0.5)
        ok, _ = run(f"{sid}: cadastre", 1500, fetch_cadastre_lv.fetch, sid, root=ws)
        if not ok:
            raise RuntimeError("the Latvian cadastre could not be read (see the service log)")
        stage("companies (UR) and taxes (VID)", 0.62)
        run(f"{sid}: tenants", 600, fetch_tenants_lv.fetch, sid, root=ws)
        stage("roads (OpenStreetMap)", 0.64)
        run(f"{sid}: roads", 180, fetch_roads_lv.fetch, sid, root=ws)
        stops = threading.Thread(target=lambda: run(f"{sid}: stops", 120, fetch_stops.fetch, sid, root=ws), daemon=True)
        stops.start()
        return stops

    def refine(self, sid, ws, rstage, run):
        """The ground is 1 m from the start (the laser sheets) and measured trees are a later step:
        left are the older photographs (strip-stored, tens of MB a cycle) and the timetables. The
        meta is marked "refined", the game's cue to take the pack again (the descriptor's "refine":
        "flag"): a Latvian ground is never coarse."""
        import fetch_departures, fetch_tile_lv
        tile_dir = os.path.join(ws, "assets", "terrain", sid)
        rstage("older orthophotos (LĢIA, 2003-2015)")
        run(f"{sid}: older orthophotos", 600, fetch_tile_lv.add_history, tile_dir)
        rstage("bus departures (ATD, Rīgas satiksme)")
        run(f"{sid}: departures", 300, fetch_departures.fetch, sid, root=ws)
        meta_path = os.path.join(tile_dir, "terrain_meta.json")
        meta = json.load(open(meta_path))
        meta["refined"] = True
        with open(meta_path, "w") as f:
            json.dump(meta, f, indent=2, ensure_ascii=False)
        return True, 1

    def border(self, site, root):
        import fetch_cadastre_lv, fetch_tenants_lv
        fetch_cadastre_lv.fetch(site, root)
        fetch_tenants_lv.fetch(site, root)

    def border_roads(self, site, root):
        """OpenStreetMap's roads, for an Estonian pack: ETAK stops at the border."""
        import fetch_roads_lv
        fetch_roads_lv.fetch(site, root)
        return fetch_roads_lv.ATTRIBUTION

    def departures(self, site, root, refresh=False, max_age_days=7):
        import fetch_departures
        return fetch_departures.fetch_lv(site, root, refresh, max_age_days)

    def codex(self, name):
        return {
            "CODEX_REAL": {"et": f"Maa: {name}, Läti Geoinfoameti (LĢIA) laserpunktidest ja ortofotost, meetri täpsusega.",
                           "en": f"The ground: {name}, from the Latvian Geospatial Information Agency's (LĢIA) laser points and orthophoto, to the metre.",
                           "lv": f"Zeme: {name}, no Latvijas Ģeotelpiskās informācijas aģentūras (LĢIA) lāzerpunktiem un ortofoto, ar metra precizitāti."},
            "CODEX_INVENTED": {"et": "Majade seinad ja katused on taastatud registrite mõõtude ja katusemudelite või laserpunktide järgi; sisemused, puud, liiklus ja möödujad on välja mõeldud. Ükski inimene siin ei kujuta päris inimest.",
                               "en": "The walls and roofs are reconstructed from the registers' measurements and roof models or laser points; the interiors, the trees, the traffic and the passers-by are invented. No person here depicts a real one.",
                               "lv": "Sienas un jumti atjaunoti pēc reģistru mēriem un jumtu modeļiem vai lāzerpunktiem; interjeri, koki, satiksme un garāmgājēji ir izdomāti. Neviens cilvēks šeit neattēlo īstu cilvēku."},
            "CODEX_DATA": {"et": self.GROUND_ET, "en": self.GROUND_EN,
                           "lv": "Kartes dati: Latvijas Ģeotelpiskās informācijas aģentūra (LĢIA) 2026, lāzerskenēšana un ortofoto 2016–2018 (CC BY 4.0)."},
        }

    def geocode(self, query):
        import geocode_lv
        return geocode_lv.search(query)


# Planned adapters (no code yet). Each needs: a metric CRS, a DEM (ideally lidar 1 m), an orthophoto
# service, optional canopy, historical maps, buildings, trees, and a geocoder.
PLANNED = {
    "fi": "Finland: NLS 2 m DEM and orthophotos (open, API key), NLS topographic DB buildings, National Archives historical maps",
    "nl": "Netherlands: AHN 0.5 m DEM, PDOK orthophoto, BAG buildings with construction year, 3D BAG (LOD2)",
    "dk": "Denmark: Dataforsyningen DEM 0.4 m, orthophoto, BBR buildings",
    "ch": "Switzerland: swissALTI3D 0.5 m, SWISSIMAGE, swissBUILDINGS3D (LOD2)",
    "uk": "United Kingdom: DEFRA lidar 1 m (England), OS OpenMap buildings; orthophoto not open",
    "us": "United States: USGS 3DEP 1 m lidar, NAIP orthophoto, Microsoft building footprints",
    "world": "Fallback: Copernicus GLO-30 DEM + ESA WorldCover 10 m + OSM buildings; too coarse for a walkable 1 km² at this game's scale",
}

# Tested in order: an adapter whose test is exact (Latvia's laser sheets off other countries' land)
# goes before one whose test is only a box (Estonia's).
SOURCES = [Latvia(), Estonia()]


def for_point(x, y, crs=3301):
    for s in SOURCES:
        if s.crs == crs and s.covers(x, y):
            return s
    return None


def by_id(country, default="ee"):
    """The adapter a pack names (site.json "country"); the default for packs from before that field."""
    for s in SOURCES:
        if s.id == (country or default):
            return s
    return next(s for s in SOURCES if s.id == default)


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
