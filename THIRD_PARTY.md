# Third-party components and data — licence register

Kept so the game can be published as open source later. Every addon, model, texture, data
source and tool that ships in the repository or in a build is listed with its licence and
what that licence obliges. "OSS release" says whether it is compatible with publishing the
whole project under a permissive open-source licence (MIT/Apache for code, CC BY for content).

**Project's own licence:** not chosen yet. Recommendation: MIT for code, CC BY 4.0 for original
content (writing, models, textures), with the data attribution below carried in the credits.

| Component | Version / date | Where | Licence | Obligations | OSS release |
|---|---|---|---|---|---|
| Godot Engine | 4.7.2 | engine | MIT | keep the engine licence text in the exported app (Godot does this) | yes |
| Terrain3D (TokisanGames) | 1.0.2-stable, 2026-05-19 | `addons/terrain_3d` | MIT | keep `addons/terrain_3d/LICENSE.txt` | yes |
| Sky3D (TokisanGames, J. Cuéllar) | 2.1.0, 2026-05-19 | `addons/sky_3d` | MIT; third-party textures listed in `addons/sky_3d/ThirdParty.md` | keep both files; check ThirdParty.md before redistributing the milky-way/moon textures | yes (check textures) |
| inkgd (Frédéric Maquin) | godot4 branch, 2024-01-28; local patch: `InkUtils.InkRuntime` uses `get_node_or_null` so first `init` no longer logs a missing-node error | `addons/inkgd` | MIT (runtime port of inkle's ink, also MIT) | keep `addons/inkgd/LICENSE` | yes |
| inkjs compiler | 2.4.0 (npm, dev tool only) | `tools/ink` (node_modules ignored) | MIT | not shipped | yes |
| Forest Vegetation sample pack (Renard Noir) | v1.0, 2026-08-27 | `assets/vendor/forest_vegetation` (materials, textures, licence; the 70 MB FBX models are not committed, re-download from the Asset Store to rerun `make props`), derived scenes in `assets/vegetation` | MIT (`LICENSE.txt` in the pack) | keep the licence file; attribution appreciated, not required | yes |
| Poly Haven ground textures (aerial_grass_rock, leafy_grass, brown_mud_leaves_01, gravel_floor, aerial_mud_1) | 1K, 2026-09-05, `tools/pipeline/fetch_polyhaven.py`, record in `assets/textures/POLYHAVEN.json` | `assets/terrain/textures` (repacked for Terrain3D) | CC0 1.0 | none | yes |
| Maa-amet / Maa- ja Ruumiamet geodata: 1 m DTM, nDSM, orthophoto (WMS `fotokaart`), historical maps (WMS `ajalooline`: 1930–44 cadastral map `kk1940`, one-verst map `yheverstakaart`), sheet grids, cadastral units (WFS), in-ADS geocoder | fetched 2026-09-03/04 (Palupera), 2026-09-05 (Kvissentali) | `assets/terrain/<tile>/*`, `sites/<id>/layout.json`, `sites/<id>/buildings_2026.json`, `sites/<id>/water_2026.json` | Estonian Land Board open data licence (free use incl. commercial, attribution required) | credit "Maa- ja Ruumiamet 2026" in-game and in the README; the Board may ask for the attribution to be removed in writing | yes (attribution) |
| ETAK, Estonian topographic database: building polygons (WFS `etak:e_401_hoone_ka`, Keskkonnaagentuur geoserver gsavalik.envir.ee) | fetched 2026-09-05 | `sites/<id>/buildings.json` (`tools/pipeline/fetch_buildings.py`) | Maa-amet open data licence (attribution) | credit "Eesti topograafia andmekogu, Maa- ja Ruumiamet" | yes (attribution) |
| Ehitisregister (EHR), the Building Register: first year of use, floors, area, volume, purpose per building (`livekluster.ehr.ee/api/building/v2/buildingdata`) | fetched 2026-09-05, cached in `data_raw/ehr/` | `sites/<id>/buildings.json` | public register data, open API; terms at ehr.ee (check before a commercial release) | credit "Ehitisregister"; polite use (cached, sequential) | yes (check terms) |
| Maa-amet Geo3D building models LOD2 (roof shapes), FileGDB per municipality (`geoportaal.maaamet.ee ... andmetyyp=hooned_lod2`) | fetched 2026-09-05, cached in `data_raw/lod2/` | `sites/<id>/buildings.json` `lod2` faces, built at runtime by `scripts/world/footprint_building.gd` | Maa-amet open data licence (free use, attribution) | credit "Hoonete ruumiandmed: Maa- ja Ruumiamet 2026" | yes (attribution) |
| Maa-amet Geo3D single-tree models (LOD0 üksikpuud: trunk position, height, crown, conifer/deciduous; towns flown 2020–2024), GeoPackage per municipality | fetched 2026-09-05, cached in `data_raw/trees/` | `assets/terrain/<tile>/trees.json` (`tools/pipeline/fetch_trees.py`), placed by `TerrainBuilder` | Maa-amet open data licence (free use, attribution) | credit "Üksikpuude mudeli andmekogum: Maa- ja Ruumiamet 2026" | yes (attribution) |
| Maa-amet cadastre, valid cadastral units (WFS `kataster:ky_kehtiv` on gsavalik.envir.ee: tunnus, address, purpose, area, ownership, polygon) | fetched 2026-09-05 | `sites/<id>/parcels.json` (`tools/pipeline/fetch_parcels.py`), K overlay, parcel kits | Maa-amet open data licence (attribution) | credit "Maakataster, Maa- ja Ruumiamet" | yes (attribution) |
| ETAK roads (WFS `etak:e_401`… `e_501_tee_j`: streets, paths, trails with width, surface, name) | fetched 2026-09-05 | `sites/<id>/roads.json` (`tools/pipeline/fetch_roads.py`), `scripts/world/road_network.gd` | Maa-amet open data licence (attribution) | credit "Eesti topograafia andmekogu, Maa- ja Ruumiamet" | yes (attribution) |
| Maa-amet in-ADS address gazetteer (geocoding, reverse geocoding, municipality lookup) | live | `scripts/autoload/locator.gd`, `tools/tile_service.py`, `tools/pipeline/fetch_buildings.py` | Maa-amet open data licence | attribution | yes |
| ip-api.com IP geolocation (optional, "Use my location" in the menu) | free endpoint, 2026-09-05 | `scripts/autoload/locator.gd` | free for non-commercial use, 45 requests/min; no key | swap for a paid/other provider before any commercial release; only the coarse city-level point is used | check before release |
| Blender-generated props (oak, boundary stone, buildings, figures) | scripts in `tools/blender` | `assets/models` | project's own | – | yes |
| Ink scripts, strings, design docs | ours | `assets/narrative`, `assets/i18n`, `*.md` | project's own | – | yes |
| Godot export templates | 4.7.2 | not in repo | MIT | – | yes |
| ambientCG LeafSet013, LeafSet019 (foliage cards) | 1K, 2026-09-04 | `assets/textures/foliage` (recomposed) | CC0 1.0 | none | yes |
| Poly Haven building materials (plastered_wall, red_brick_03, painted_concrete, concrete_wall_006, wood_planks_grey, old_planks_02, roof_tiles_14, corrugated_iron_02, reed_roof_03, brick_wall_006) | 1K, 2026-09-05, `tools/pipeline/fetch_polyhaven.py` | `assets/textures/buildings` (`*_color.jpg`, `*_normal.jpg`) | CC0 1.0 | none | yes |
| ambientCG Bark012 (tree bark), Plaster001/WoodSiding001/RoofingTiles006/Rock035 as baked into `assets/models/buildings/*.glb` | 1K, 2026-09-04 | `assets/textures/buildings/bark_*`, glb models | CC0 1.0 | none | yes |
| Realistic Water Shader (UnionBytes / Achim Menzel, K. S. Ernest Lee): wave and depth code adapted in `assets/shaders/lake.gdshader`, textures Water_N_A.png, Foam.png | master, 2026-09-05 | `assets/shaders/lake.gdshader`, `assets/textures/water` | MIT | keep the attribution in the shader header and here | yes |
| Blender Sapling Tree Gen (extension) | via extensions.blender.org, 2026-09-04 | tool only (`tools/blender/make_trees.py`); trees in `assets/models/trees` are its output | GPL-2.0-or-later (the add-on); generated meshes are ours | not shipped; presets read at generation time | yes (output only) |

## Candidates under evaluation (visual upgrade plan)

| Candidate | Licence | Notes for OSS release |
|---|---|---|
| Poly Haven models (pine tree) | CC0 1.0 | evaluated and dropped: photoscan mesh is ~950 MB, not game-usable |
| Tree3D (jeksun) | MIT | fine; marked unstable |
| Octahedral Impostors (wojtekpil, godot4 branch) | MIT | evaluated: last commit 2021, not used |
| godot-imposter (zhangjt93, master) | MIT | evaluated: editor-only baker verified on 4.5; not used, own baker written instead |
| SimpleGrassTextured (IcterusGames) | MIT | fine |
| FoliageFlow | check store page before use | – |
| Waterways (Arnklit) | MIT | fine |
| Godot 4 Realistic Water port | check repo licence before use | – |
| Quixel Megascans / Megaplants via Fab | Fab Standard Licence (free tier) | **not** redistributable in an open-source repo; do not use |

## How to add an entry
Add the row when the files land in the repo, with the exact version and date, the licence
file path kept in the tree, and the obligation in plain words.
