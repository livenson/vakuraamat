# Data sources and the pipeline

Everything place-specific in Vakuraamat is generated from open data. This page lists the sources,
the tools that transform them, the files they produce and where the game reads them. The short
version with a diagram is in the [README](../README.md#data-sources-and-how-they-become-a-place).

## Sources

| Source | What | Tool | Output |
|---|---|---|---|
| Maa-amet geoportal, 1 m DTM sheets (`dem_1m_geotiff`) | ground heights, EH2000 | `tools/pipeline/fetch_tile.py` | `assets/terrain/<tile>/heightmap.r32`, `terrain_meta.json` |
| the same sheets at 5 m (`dem_5m_geotiff`, `--dem-res 5`) | the ground a new place ships with; the tile service fetches the 5 m model first and replaces it with the 1 m one in its refine pass (`--only-dem`) | `fetch_tile.py`, `tools/tile_service.py` | the same files, `dtm_res_m: 5` in the meta |
| Maa-amet map sheet grids (`epk10T_SHP.zip`, `epk2T_SHP.zip`) | which 1:10 000 and 1:2000 sheets lie under the tile | `fetch_tile.py` (`GRID_ZIP`, `GRID2T_ZIP`) | cached in `data_raw/epk10T/`, `data_raw/epk2T/` |
| Maa-amet nDSM (1:2000 sheets); the 1:20 000 CHM (`chm_geotiff`, trees only, coarser) where no nDSM exists | canopy and object heights | `fetch_tile.py` | `assets/terrain/<tile>/canopy.r32` |
| Maa-amet WMS `fotokaart` (`EESTIFOTO`) | 25 cm orthophoto; and one plot's square at a time, at the size the book shows it, for the plot page's "today" | `fetch_tile.py`, `scripts/ui/plot_history.gd` | `assets/terrain/<tile>/ortho.jpg`, `user://cache/plots/<pack>/` |
| Maa-amet historical orthophotos, WMS `ajalooline` (campaign layers `of1993-2000_10k`, `of2005`, `of2010`/`of2015`/`of2020` `aero`, `asulad`, `mets`) | the plot's own square in each campaign since 1993, fetched live when the book shows the plot | `scripts/ui/plot_history.gd` | `user://cache/plots/<pack>/` |
| Maa-amet administrative division (`maakond_shp.zip`, county polygons) and the ETAK standing-water WFS `etak:e_202_seisuveekogu_a` (Võrtsjärv) | the outline of Estonia for the menu's locator map; credit "Haldusjaotus ja siseveekogud: Maa- ja Ruumiamet, Eesti topograafia andmekogu" | `tools/pipeline/fetch_outline.py` (run by hand, the file is committed) | `assets/data/estonia.json` |
| Maa-amet Geo3D single trees (LOD0 üksikpuud) | every laser-detected tree: position, height, crown, conifer or deciduous | `tools/pipeline/fetch_trees.py` | `assets/terrain/<tile>/trees.json` |
| ETAK topographic database, WFS `etak:e_401_hoone_ka` | building polygons and types | `tools/pipeline/fetch_buildings.py` | `sites/<id>/buildings.json` |
| EHR, the Building Register (`livekluster.ehr.ee`) | year, storeys, purpose, facade and roof materials, heating, water, addresses | `fetch_buildings.py` | `sites/<id>/buildings.json` |
| Maa-amet Geo3D LOD2 buildings | roof and wall faces | `fetch_buildings.py` | `sites/<id>/buildings.json` (`lod2`) |
| ETAK roads, WFS `etak:e_501_tee_j` | streets, roads, paths, trails with width, surface, name | `tools/pipeline/fetch_roads.py` | `sites/<id>/roads.json` |
| Maa-amet cadastre, WFS `kataster:ky_kehtiv` | cadastral units: number, address, purpose, area, ownership, polygon, the 2022 taxation value | `tools/pipeline/fetch_parcels.py` | `sites/<id>/parcels.json` |
| PRIA field register, WFS `pria_avalik:pria_pollud` and `pria_massiivid` on kls.pria.ee | farmed fields: polygon, the crop declared for this year's area aid | `tools/pipeline/fetch_fields.py` | `sites/<id>/fields_2026.json` (crops planted by `scripts/world/crops.gd`) |
| OpenStreetMap, Overpass `highway=bus_stop` nodes (ODbL) | bus stops, snapped to the nearest ETAK road with a heading | `tools/pipeline/fetch_stops.py` | `sites/<id>/stops.json` (shelters by `RoadNetwork._bus_stops`) |
| Public transport register GTFS (`eu-gtfs.remix.com` mirror of the national feed) | the lines calling at the tile's stops, their destinations, departure times per service day and the route geometry | `tools/pipeline/fetch_departures.py` | `sites/<id>/departures.json` |
| derived from `parcels.json` (optional Maa-amet transaction export) | euro per m² medians by purpose | `tools/pipeline/market.py` | `sites/<id>/market.json` |
| e-Business Register open data (daily CSV, CC BY 4.0) | companies matched to the tile's addresses | `tools/pipeline/fetch_tenants.py` | `sites/<id>/tenants.json` |
| e-Business Register general data, persons and shareholders (daily JSON dumps, CC BY 4.0) | EMTAK activity and the sector, share capital, web address, annual-report employee counts, deletion date; board and shareholder counts and hashed ids (structure only, no names) | `tools/pipeline/register_extra.py` (slimmed once per download into `data_raw/ariregister/*.slim.jsonl`) | the same rows in `tenants.json` |
| Tax Board "tasutud maksud" quarterly open data (EMTA) | taxes paid, turnover and employees per company per quarter, the activity sector | `register_extra.py` (`data_raw/emta/`) | `tenants.json`: `employees`, `turnover`, `taxes`, `quarters`, `health` |
| Maa-amet in-ADS gazetteer | address and place search; the municipality under a point (reverse EHAK lookup) | `tools/tile_service.py` (`/geocode`), `scripts/autoload/locator.gd` (directly), `fetch_buildings.py` (which municipality's LOD2 and tree files to fetch) | menu results |
| ip-api.com IP geolocation (optional, "Use my location" in the menu) | a coarse city-level point; free for non-commercial use, no key | `scripts/autoload/locator.gd` | the menu's suggested place |
| Poly Haven (CC0) | ground and facade PBR textures | `tools/pipeline/fetch_polyhaven.py` | `assets/terrain/textures/`, `assets/textures/buildings/` |
| Sketchfab (CC BY, via the MCP server, `make mcp`) and Poly Pizza (CC0 / CC BY) models | cars, street lamps, benches, bus shelters, the spruce and juniper, hay bales, tractor, farm plants; playground, boats and stairs | downloaded, split with `tools/blender/split_glb.py`, listed in `assets/vendor/sketchfab/CREDITS.md` | `assets/vendor/sketchfab/`, `assets/vendor/polypizza/`, `assets/models/trees/spruce_src.glb` |

Licences, attribution strings and fetch dates are in `THIRD_PARTY.md`. Endpoints and the per-country
adapter interface are in `tools/pipeline/sources.py`; only Estonia is implemented.

## Transformations

1. **Terrain tile** (`make tile SITE=<id>`, or the tile service): `fetch_tile.py` finds the 1:10 000
   sheets under the corners, downloads and mosaics the DTM, clips the square (rasterio), fills NoData,
   writes the raw float heightmap, fetches the orthophoto and the nDSM for the same extent and writes
   `terrain_meta.json` (extent, sheets, height range, sources, attribution).
2. **Features** (`make features`): `extract_features.py` derives the village massing
   (`buildings_2026.json`, boxes for objects over 2.5 m that are not green) and still water
   (`water_2026.json`) from the laser data and the orthophoto, moored boats (`boats_2026.json`:
   bright hulls beside the river) and the anchors the layout uses.
3. **Registers** (`make buildings`, `make roads`, `make parcels`, `make tenants`, `make market`,
   `make real-trees`): the WFS and register fetches above, each writing one JSON in the pack.
4. **Scenes** (`make scenes`): `tools/gen_era_scenes.py` turns `scenes.json` and `layout.json` into
   `sites/<id>/scenes/era_2026.tscn`, a plain Godot scene with the footprints, roads, parcel kits,
   traffic and props at y 0 (the layer drops them onto the terrain when it activates).
5. **Terrain import** (`make import`, `tools/godot/import_terrain.gd`): headless Godot loads the raw
   heightmap as `FORMAT_RF`, classifies the orthophoto into detail materials (meadow, field, forest
   floor, gravel), rasterises roads and building footprints into the control map so nothing is
   scattered under them, places the measured trees and the statistical scatter with the Terrain3D
   instancer, and saves `data/terrain3d_00_00.res` and `terrain_assets.tres`.
6. **Validation** (`make validate`): `tools/validate_site.py` checks every pack without Godot.

The tile service (`tools/tile_service.py`) runs steps 1 to 4 and 6 for any point in Estonia on
request from the menu (the terrain with the 5 m ground model; the registers including the bus stops
and the PRIA fields) and packs the result as a zip the game installs under `user://`. It skips step 5:
the game builds the Terrain3D region itself when it loads the tile. A refine pass after the pack is
playable fetches the 1 m ground model, the measured trees and the departures and rewrites the zip.

## Where the game reads them

| File | Reader |
|---|---|
| `heightmap.r32`, `ortho.jpg`, `canopy.r32`, `trees.json` | `scripts/worldgen/terrain_builder.gd` (also at runtime for downloaded tiles) |
| `data/terrain3d_00_00.res` | Terrain3D |
| `buildings.json` | `scripts/world/footprint_building.gd` (walls, roofs, windows, chimneys), `scripts/world/interiors.gd` (rooms), the debug map (house numbers) |
| `roads.json` | `scripts/world/road_network.gd` (ribbons, kerbs, street lights), the traffic graph, the debug map (street names) |
| `parcels.json` | `scripts/world/parcels.gd` (the book, the find bar, the map arrow), `parcel_kit.gd`, `parcel_marks.gd`, the K overlay |
| `market.json` | the book's Place page: the 2022 taxation-value medians per purpose |
| `stops.json` | `scripts/world/road_network.gd`: a bus shelter at each stop (Soviet-era on roads, small modern on streets), its board readable |
| `departures.json` | `scripts/world/departures.gd`: the shelter's timetable board and its E sheet, and `bus_service.gd`, which puts a bus on the route at each departure |
| `fields_2026.json` | `scripts/world/crops.gd`: rows of cereal, rape, potato, legume or maize plants on each declared field; grassland and fallow stay as the ground shows them |
| `tenants.json` | `scripts/world/tenants.gd`, name plates, interiors (use of a building), the book |
| `scenes/era_2026.tscn` | `scripts/era/era_controller.gd` |

## Requirements (macOS)

| Tool | Version used | Install |
|---|---|---|
| Godot | 4.7.2 stable | `brew install --cask godot` |
| Terrain3D | 1.0.2 stable (vendored in `addons/terrain_3d`, MIT) | in the repo |
| Sky3D | 2.1.0 (vendored in `addons/sky_3d`, MIT, pure GDScript) | in the repo |
| Python 3.12 venv with numpy, Pillow, rasterio, pyogrio, shapely, pyproj (`tools/service/requirements.txt`) | `.venv-service`, made by `make setup` (uv) | no system GDAL: the wheels carry it |
| Blender | 5.2 LTS (only to regenerate props and trees) | `brew install --cask blender` |
| Python 3 | any 3.9+ (stdlib only) | system |

QGIS is not needed: the whole clip and convert step is scripted with rasterio (`tools/pipeline/geo.py`). First open: run
`godot --headless --path . --import` once (or open the project in the editor). Terrain3D's macOS
binaries are unsigned; if Gatekeeper blocks them run `xattr -dr com.apple.quarantine addons/terrain_3d`.

## Fresh clone

```sh
git clone <repo> vakuraamat && cd vakuraamat
make setup      # Homebrew tools, git-lfs pull, first Godot import
make tile       # Maa-amet data for Palupera and the terrain (~10 min, network); SITE=<id> for another pack
make test       # headless test suite
godot --path .  # play
```

Generated data is deliberately not in git: the Terrain3D region file (22 MB, rewritten on every
re-scatter), prepared tree meshes and impostor atlases. `make tile` rebuilds the terrain from the
committed inputs; `make trees` rebuilds the trees (needs Blender and a window for the impostor
bake). Large stable binaries (models, textures, addon binaries) are tracked with git LFS, see
`.gitattributes`.

## Make targets

| Target | Produces | Inputs |
|---|---|---|
| `make site SITE=<id> NAME=... CENTER=...` | `sites/<id>/` scaffold (manifest, layout, scenes.json, data, strings) | `tools/new_site.py`, the template pack |
| `make tile SITE=<id>` | `assets/terrain/<tile>/*`, the measured trees and the import, then features, buildings, parcels, roads, market and tenants where missing, and the scenes (not the stops, departures or fields) | `sites/<id>/site.json` (centre, size), the sources above |
| `make features SITE=<id>` | `buildings_2026.json`, `water_2026.json`, `anchors.json` | the tile's laser data and orthophoto |
| `make buildings`, `roads`, `parcels`, `tenants`, `market`, `real-trees` | one JSON each, see the table above | WFS and register endpoints |
| `make stops SITE=<id>` | `sites/<id>/stops.json` | Overpass, the pack's `roads.json` |
| (no make target) `python3 tools/pipeline/fetch_fields.py --site <id>` | `sites/<id>/fields_2026.json` | the PRIA WFS |
| `make scenes SITE=<id>` | `sites/<id>/scenes/era_2026.tscn` | `scenes.json`, `layout.json`, the JSONs |
| `make import` | Terrain3D region data and assets | the tile's inputs |
| `make scatter` | vegetation instances in the region file | control map, `canopy.r32`, layout exclusions |
| `make trees` | `assets/models/trees/*.glb`, `*_lod.tscn`, impostor atlases | Blender Sapling presets; a vendored `<name>_src.glb` (the Sketchfab spruce) wins over the generated tree and is merged, pruned and baked the same way |
| `make props` | boundary stone, figures, prepared vegetation scenes | Blender scripts in `tools/blender` |
| `make validate` | report | every `sites/*/` (no Godot) |
| `make departures SITE=<id>` | `sites/<id>/departures.json` | the register's GTFS (needs `make stops` first) |
| `make test`, `make lint` | the headless suite; gdlint, ruff, shellcheck and actionlint (skipped with a note when not installed) | |

## The terrain pipeline in detail

```sh
# 1. Maa-amet -> heightmap.r32 + canopy.r32 + ortho.jpg + terrain_meta.json  (needs network)
python3 tools/pipeline/fetch_tile.py --site palupera        # or --name <tile> --center <E> <N>

# 2. -> Terrain3D region data + assets/material resources     (headless Godot)
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
    -s res://tools/godot/import_terrain.gd -- --site=palupera
```

Step 1 finds the 1:10 000 map sheets under the four corners (the sheet grid is downloaded once into
`data_raw/`), POSTs the geoportal download form for each sheet's DTM GeoTIFF (1 m: ~74 MB; `--dem-res 5`:
~4 MB, resampled bilinearly to the 1 m output grid, a median 1.8 cm from the 1 m result and what the
tile service ships first so a new place can be walked in about a minute; `--only-dem` replaces the
heightmap of a tile that already stands, which is how the refinement pass upgrades it), all cached,
mosaics and clips them with `rasterio.merge`, fills NoData with `rasterio.fill` and writes a raw float32 heightmap (Godot's PNG loader truncates 16-bit to 8-bit
and its EXR loader rejects GDAL's channel names). It then fetches the orthophoto from the `fotokaart`
WMS (JPEG, at most 4096 px per request: 1024 m at 4096 px is 25 cm per pixel) and the nDSM.

Step 2 loads the heightmap as `Image.FORMAT_RF`, resamples the orthophoto to one texel per vertex as
the Terrain3D colour map, classifies every metre by colour into a detail material and writes the
control map, then saves the region and the assets. The 1 texel/m colour map is only a fallback: the
real drape is `assets/terrain/ortho_drape.gdshader`, Terrain3D's lightweight example shader plus a
world-space orthophoto lookup, so the 4096 px image maps exactly onto the 1024 m tile. Within
`detail_near` metres the orthophoto is modulated by the detail texture's luminance, normal and
roughness; beyond `detail_far` it is the pure orthophoto. The material lives inline in the scene
(a `Terrain3DMaterial` saved from a headless run comes out with null shader parameters).

### World mapping

The tile's north-west corner is Godot `(0, y, 0)`; `+X` is east, `+Z` is south, `y` is metres above
sea level (EH2000) times `z_scale` (default 1.0, recorded in the meta file). `scripts/terrain/terrain_georef.gd`
converts both ways using `terrain_meta.json`. The HUD shows the player's L-EST97 (EPSG:3301)
easting and northing so alignment can be checked against Maa-amet's map viewer.

### Limits

- One tile is one Terrain3D region (at most 2048 m); neighbours stream in as separate tiles
  ([custom-sites.md](custom-sites.md#endless-map-neighbouring-tiles)).
- The drape shader drops Terrain3D's projection, detiling and painted rotation.
- The 2022 land values are taxation values, not sale prices, and are labelled as such.

## Known quirks (Godot 4.7.2 + Terrain3D 1.0.2)

- Never set `region_size` on a Terrain3D node in a scene that also loads region files; it segfaults
  on load. The region file carries its own size.
- Don't save a `Terrain3DMaterial` from a headless run; its shader parameters come out null.
- A `Terrain3D` node added from a `SceneTree` script only initialises on the next frame
  (`await process_frame`), and its data directory must already exist.
- Headless `--import` prints a `double_slider.gd` script error from the Terrain3D editor UI. It is
  harmless.

## Layout of the repository

```
addons/terrain_3d/, addons/sky_3d/    vendored addons
assets/terrain/<tile>/               heightmap.r32, canopy.r32, ortho.jpg, trees.json, terrain_meta.json, data/
assets/terrain/ortho_drape.gdshader  the orthophoto drape
assets/vendor/                       Kenney car kit, forest vegetation, Sketchfab and Poly Pizza models (see THIRD_PARTY.md)
assets/models/humans/                MakeHuman figures
sites/<id>/                          site pack: site.json, layout.json, scenes.json, *.json registers, scenes/, strings.csv
scripts/autoload/                    PerfLog, EventBus, Sites, Locator, Reporter, DevChannel, SaveManager, GameState, WindowMode
scripts/world/                       terrain, buildings, interiors, roads, parcels, traffic, figures
scripts/ui/                          the book theme, panels, HUD, menu
tools/pipeline/                      the fetchers and derivations
tools/godot/                         headless tools and tests
tools/dev.py, tools/tile_service.py
data_raw/                            downloads and intermediates (git-ignored)
```

## Data licence

Maa-amet open data, free for commercial use with attribution. In-game credit line (also in
`terrain_meta.json`): "Map data: Maa- ja Ruumiamet (Estonian Land and Spatial Development Board),
2026". Companies: e-Business Register open data, CC BY 4.0. Everything else is listed in
`THIRD_PARTY.md`.

## The tile service as a sidecar

`make service` (`tools/service/build.sh`, PyInstaller) freezes `tools/tile_service.py` with the
pipeline, rasterio, pyogrio, shapely, pyproj, the template pack and the rules into one executable
in `dist/`. The CI build puts it beside the game (inside `Vakuraamat.app/Contents/MacOS` on macOS);
an exported game starts it with `--workspace user://service --raw-dir user://service/data_raw`, so
the Locations page works without the repository. From the source tree the game and `tools/play.sh`
run `tools/tile_service.py` with the venv's Python instead. The service runs the fetch, the
feeder and the validation in-process (no subprocesses), and every download cache (sheets, register
dumps, Tax Board, LOD2, trees) lives under one raw directory (`VAKURAAMAT_RAW_DIR`).

`POST /tile` takes two flags that change what a job does to a pack that already exists:

| flag | what it keeps | what it costs |
|---|---|---|
| neither | everything: the existing zip is handed back unchanged | seconds |
| `"refresh": true` | the ground already fetched (the 1 m DTM, the trees); every register is fetched again | seconds to a couple of minutes |
| `"force": true` | nothing; the workspace is removed and the whole pack rebuilt | about twenty minutes (the 1 m DTM alone is ~900 s, the trees ~600 s) |

The game only ever sends `refresh`, and only for a pack whose `"pipeline"` stamp is older than the
build expects - see **Packs that know how old they are** in `docs/custom-sites.md`. It installs the
site files and leaves `user://tiles` alone, so a running world can swap the pack in without adding
or removing a Terrain3D region.

## Starter places

A fresh build ships Kvissentali, Palupera and Pirita with their ground baked by CI, so entering them
builds nothing. The tiles around Kvissentali and Pirita come as one download instead of sixteen tile
service jobs: `tools/starter_places.py build` asks the running service for each neighbour (refreshing a
stale cached pack, making a missing one, waiting for its 1 m ground), drops files the current pipeline
no longer writes, checks the `PACK_VERSION` stamp and writes `build/starter-places.zip` and
`assets/data/starter_places.json` (release URL, sha256, the tile ids per place). `publish` uploads the
zip to a `places-<date>` release with `gh` (not a `v*` tag, so no build runs). In the game,
`Locator.starter_ensure` downloads it once (no timeout, progress on the HUD's tile line), checks the
sha256, unpacks the tiles on a worker thread and rescans the packs; the tile streamer waits for it before
asking the service for one of its tiles. A failed download falls back to the service for the session.

