# Data sources and the pipeline

Everything place-specific in Vakuraamat is generated from open data. This page lists the sources,
the tools that transform them, the files they produce and where the game reads them. The short
version with a diagram is in the [README](../README.md#data-sources-and-how-they-become-a-town).

## Sources

| Source | What | Tool | Output |
|---|---|---|---|
| Maa-amet geoportal, 1 m DTM sheets (`dem_1m_geotiff`) | ground heights, EH2000 | `tools/pipeline/fetch_tile.py` | `assets/terrain/<tile>/heightmap.r32`, `terrain_meta.json` |
| Maa-amet nDSM (1:2000 sheets) | canopy and object heights | `fetch_tile.py` | `assets/terrain/<tile>/canopy.r32` |
| Maa-amet WMS `fotokaart` (`EESTIFOTO`) | 25 cm orthophoto | `fetch_tile.py` | `assets/terrain/<tile>/ortho.jpg` |
| Maa-amet Geo3D single trees (LOD0 üksikpuud) | every laser-detected tree: position, height, crown, conifer or deciduous | `tools/pipeline/fetch_trees.py` | `assets/terrain/<tile>/trees.json` |
| ETAK topographic database, WFS `etak:e_401_hoone_ka` | building polygons and types | `tools/pipeline/fetch_buildings.py` | `sites/<id>/buildings.json` |
| EHR, the Building Register (`livekluster.ehr.ee`) | year, storeys, purpose, facade and roof materials, heating, water, addresses | `fetch_buildings.py` | `sites/<id>/buildings.json` |
| Maa-amet Geo3D LOD2 buildings | roof and wall faces | `fetch_buildings.py` | `sites/<id>/buildings.json` (`lod2`) |
| ETAK roads, WFS `etak:e_501_tee_j` | streets, roads, paths, trails with width, surface, name | `tools/pipeline/fetch_roads.py` | `sites/<id>/roads.json` |
| Maa-amet cadastre, WFS `kataster:ky_kehtiv` | cadastral units: number, address, purpose, area, ownership, polygon, the 2022 taxation value | `tools/pipeline/fetch_parcels.py` | `sites/<id>/parcels.json` |
| PRIA field register, WFS `pria_avalik:pria_pollud` and `pria_massiivid` on kls.pria.ee | farmed fields: polygon, the crop declared for this year's area aid | `tools/pipeline/fetch_fields.py` | `sites/<id>/fields_2026.json` (crops planted by `scripts/world/crops.gd`) |
| derived from `parcels.json` (optional Maa-amet transaction export) | euro per m² medians by purpose | `tools/pipeline/market.py` | `sites/<id>/market.json` |
| e-Business Register open data (daily CSV, CC BY 4.0) | companies matched to the tile's addresses | `tools/pipeline/fetch_tenants.py` | `sites/<id>/tenants.json` |
| Maa-amet in-ADS gazetteer | address and place search | `tools/tile_service.py` (`/geocode`) | menu results |
| ERR and Postimees RSS, Ametlikud Teadaanded | regional headlines, planning and auction notices | `tools/news_feeder.py` | town database events or `sites/<id>/news.json` |
| Poly Haven (CC0) | ground and facade PBR textures | `tools/pipeline/fetch_polyhaven.py` | `assets/terrain/textures/`, `assets/textures/buildings/` |

Licences, attribution strings and fetch dates are in `THIRD_PARTY.md`. Endpoints and the per-country
adapter interface are in `tools/pipeline/sources.py`; only Estonia is implemented.

## Transformations

1. **Terrain tile** (`make tile SITE=<id>`, or the tile service): `fetch_tile.py` finds the 1:10 000
   sheets under the corners, downloads and mosaics the DTM, clips the square with GDAL, fills NoData,
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
7. **Town** (`make town`): `tools/town_admin.py` seeds a SpacetimeDB database from `parcels.json`,
   `tenants.json` and `market.json`; `tools/news_feeder.py` posts the feed into it.

The tile service (`tools/tile_service.py`) runs steps 1 to 6 for any point in Estonia on request from
the menu and packs the result as a zip the game installs under `user://`.

## Where the game reads them

| File | Reader |
|---|---|
| `heightmap.r32`, `ortho.jpg`, `canopy.r32`, `trees.json` | `scripts/worldgen/terrain_builder.gd` (also at runtime for downloaded tiles) |
| `data/terrain3d_00_00.res` | Terrain3D |
| `buildings.json` | `scripts/world/footprint_building.gd` (walls, roofs, windows, chimneys), `scripts/world/interiors.gd` (rooms, furniture), the debug map (house numbers) |
| `roads.json` | `scripts/world/road_network.gd` (ribbons, kerbs, street lights), the traffic graph, the debug map (street names) |
| `parcels.json`, `market.json` | `scripts/world/parcel_kit.gd`, `scripts/world/parcel_marks.gd`, the ledger (`scripts/ledger/`), the K overlay |
| `fields_2026.json` | `scripts/world/crops.gd`: rows of cereal, rape, potato, legume or maize plants on each declared field; grassland and fallow stay as the ground shows them |
| `tenants.json` | `scripts/world/tenants.gd`, name plates, interiors (use of a building), the ledger |
| `news.json` or the town database | `scripts/ui/news_panel.gd` |
| `scenes/era_2026.tscn` | `scripts/era/era_controller.gd` |

## Requirements (macOS)

| Tool | Version used | Install |
|---|---|---|
| Godot | 4.7.2 stable | `brew install --cask godot` |
| Terrain3D | 1.0.2 stable (vendored in `addons/terrain_3d`, MIT) | in the repo |
| Sky3D | 2.1.0 (vendored in `addons/sky_3d`, MIT, pure GDScript) | in the repo |
| GDAL | 3.13 | `brew install gdal` |
| Blender | 5.2 LTS (only to regenerate props and trees) | `brew install --cask blender` |
| Python 3 | any 3.9+ (stdlib only) | system |
| SpacetimeDB | 2.10 CLI and a Rust toolchain (only for towns) | `make server` prints what is missing |

QGIS is not needed: the whole clip and convert step is scripted with GDAL. First open: run
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
| `make tile SITE=<id>` | `assets/terrain/<tile>/*`, then features, registers, scenes and the import | `sites/<id>/site.json` (centre, size), the sources above |
| `make features SITE=<id>` | `buildings_2026.json`, `water_2026.json`, `anchors.json` | the tile's laser data and orthophoto |
| `make buildings`, `roads`, `parcels`, `tenants`, `market`, `real-trees` | one JSON each, see the table above | WFS and register endpoints |
| `make scenes SITE=<id>` | `sites/<id>/scenes/era_2026.tscn` | `scenes.json`, `layout.json`, the JSONs |
| `make import` | Terrain3D region data and assets | the tile's inputs |
| `make scatter` | vegetation instances in the region file | control map, `canopy.r32`, layout exclusions |
| `make trees` | `assets/models/trees/*.glb`, `*_lod.tscn`, impostor atlases | Blender Sapling presets; a vendored `<name>_src.glb` (the Sketchfab spruce) wins over the generated tree and is merged, pruned and baked the same way |
| `make props` | boundary stone, figures, prepared vegetation scenes | Blender scripts in `tools/blender` |
| `make validate` | report | every `sites/*/` (no Godot) |
| `make server`, `make town SITE=<id>`, `make news` | a local SpacetimeDB, a seeded town, the feed | the pack |
| `make test`, `make lint` | the headless suite; gdlint, ruff, shellcheck | |

## The terrain pipeline in detail

```sh
# 1. Maa-amet -> heightmap.r32 + canopy.r32 + ortho.jpg + terrain_meta.json  (needs network)
python3 tools/pipeline/fetch_tile.py --site palupera        # or --name <tile> --center <E> <N>

# 2. -> Terrain3D region data + assets/material resources     (headless Godot)
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
    -s res://tools/godot/import_terrain.gd -- --site=palupera
```

Step 1 finds the 1:10 000 map sheets under the four corners (the sheet grid is downloaded once into
`data_raw/`), POSTs the geoportal download form for each sheet's 1 m DTM GeoTIFF (~74 MB, cached),
mosaics them with `gdalbuildvrt`, clips a square with `gdal_translate -projwin`, fills NoData with
`gdal_fillnodata` and writes a raw float32 heightmap (Godot's PNG loader truncates 16-bit to 8-bit
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
addons/SpacetimeDB/, spacetime_bindings/  the town client and its generated bindings
assets/terrain/<tile>/               heightmap.r32, canopy.r32, ortho.jpg, trees.json, terrain_meta.json, data/
assets/terrain/ortho_drape.gdshader  the orthophoto drape
assets/vendor/                       Kenney kits, forest vegetation, MakeHuman figures (see THIRD_PARTY.md)
sites/<id>/                          site pack: site.json, layout.json, scenes.json, *.json registers, scenes/, strings.csv
scripts/autoload/                    Sites, GameState, Ledger, Locator, SaveManager, EventBus, Reporter, DevChannel
scripts/world/                       terrain, buildings, interiors, roads, parcels, traffic, figures
scripts/ledger/                      the local book and the town client
scripts/ui/                          the book theme, panels, HUD, menu
server/vakuraamat/                   the SpacetimeDB module (Rust) and its pure rules crate
tools/pipeline/                      the fetchers and derivations
tools/godot/                         headless tools and tests
tools/dev.py, tools/tile_service.py, tools/town_admin.py, tools/news_feeder.py
data_raw/                            downloads and intermediates (git-ignored)
```

## Data licence

Maa-amet open data, free for commercial use with attribution. In-game credit line (also in
`terrain_meta.json`): "Map data: Maa- ja Ruumiamet (Estonian Land and Spatial Development Board),
2026". Companies: e-Business Register open data, CC BY 4.0. Everything else is listed in
`THIRD_PARTY.md`.
