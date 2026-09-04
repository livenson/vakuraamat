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
| inkgd (Frédéric Maquin) | godot4 branch, 2024-01-28 | `addons/inkgd` | MIT (runtime port of inkle's ink, also MIT) | keep `addons/inkgd/LICENSE` | yes |
| inkjs compiler | 2.4.0 (npm, dev tool only) | `tools/ink` (node_modules ignored) | MIT | not shipped | yes |
| Forest Vegetation sample pack (Renard Noir) | v1.0, 2026-08-27 | `assets/vendor/forest_vegetation`, derived scenes in `assets/vegetation` | MIT (`LICENSE.txt` in the pack) | keep the licence file; attribution appreciated, not required | yes |
| ambientCG ground textures (Grass001, Grass004, Ground037, Gravel022) | 1K, 2026-09-03 | `assets/terrain/textures` (repacked) | CC0 1.0 | none | yes |
| Maa-amet / Maa- ja Ruumiamet geodata: 1 m DTM, nDSM, orthophoto (WMS), 1930–44 cadastral map, one-verst map, sheet grids, cadastral units (WFS) | fetched 2026-09-03/04 | `assets/terrain/palupera/*`, `data/site_layout.json`, `data/buildings_2026.json` | Estonian Land Board open data licence (free use incl. commercial, attribution required) | credit "Maa- ja Ruumiamet 2026" in-game and in the README; the Board may ask for the attribution to be removed in writing | yes (attribution) |
| Blender-generated props (oak, boundary stone, buildings, figures) | scripts in `tools/blender` | `assets/models` | project's own | – | yes |
| Ink scripts, strings, design docs | ours | `assets/narrative`, `assets/i18n`, `*.md` | project's own | – | yes |
| Godot export templates | 4.7.2 | not in repo | MIT | – | yes |
| ambientCG LeafSet013, LeafSet019 (foliage cards) | 1K, 2026-09-04 | `assets/textures/foliage` (recomposed) | CC0 1.0 | none | yes |
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
