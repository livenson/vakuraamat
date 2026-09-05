# Vakuraamat

A time-travel farming / hunting / trading game set on real Estonian terrain built from
Maa-amet (Estonian Land and Spatial Development Board) open data. Godot 4.7, GDScript,
Terrain3D.

Design and plan: `vakuraamat-implementation-plan.md` (phases, architecture rules) and
`vakuraamat-maaamet-data-pipeline.md` (data sources). This README covers what exists
in the repo right now.

## Screenshots

| | |
|---|---|
| ![1938: the manor as the village school](docs/screenshots/manor_1938.jpg) 1938, the manor as the village school | ![1938: Kaseoja farm and the pond](docs/screenshots/farm_1938.jpg) 1938, Kaseoja farm by the pond |
| ![1798: the manor](docs/screenshots/manor_1798.jpg) 1798, the manor | ![1798: the barn-dwelling](docs/screenshots/barn_1798.jpg) 1798, the barn-dwelling |
| ![2026: the ruin](docs/screenshots/ruin_2026.jpg) 2026, the ruin where the register is found | ![2026: Leida at the oak](docs/screenshots/oak_leida.jpg) 2026, Leida at the oak |
| ![The road into the village](docs/screenshots/forest_road.jpg) The road into the village, real trees from the laser scan | ![The register](docs/screenshots/register.jpg) The register: the era switch |
| ![The journal](docs/screenshots/journal.jpg) The journal: ledger, blended era maps, codex | ![Trading](docs/screenshots/trade.jpg) Trading, era-local goods and money |
| ![Building](docs/screenshots/build.jpg) Building at the farm, on its real cadastral unit | ![Debug map](docs/screenshots/debug_map.jpg) Debug map (M): everything in the era, click to teleport |

All ground, buildings' positions, tree heights and the ponds come from Maa- ja Ruumiamet open data
of the real Palupera village square; the manor, the family and the story are fiction.

Place and story are a **site pack** (`sites/<id>/`): Palupera is the original, Kvissentali (Tartu)
a scaffold, and any 1 km² of Estonia can be added with two make targets. See
[docs/custom-sites.md](docs/custom-sites.md) and the section below.

## Status: all five phases playable

- **Phase 1, the slice:** three eras of the Palupera square, the register as the era
  switch, five consequence points with visible changes, four artifacts, six NPCs in
  Estonian and English, the journal (ledger, blended era maps, codex), chapter commit
  points, save/continue and three endings. Content follows `vakuraamat-first-iteration-design.md`.
- **Phase 2, farming:** plots and seed bins in 1938 and 2026; four crops grow on the
  shared day clock; harvests are era-local.
- **Phase 3, hunting:** hare, roe deer and black grouse spawn on their land-cover class
  (from the orthophoto + nDSM control map) in 1798 and 1938, flee, and can be taken.
- **Phase 4, trading:** one post per era (manor granary, dairy cooperative shop, village
  shop) with era-scoped goods and money (kopecks, cents, cents). Nothing crosses eras.
- **Phase 5, base building:** two manors on real cadastral units (Kaseoja farm on
  58201:002:0026, the manor park on 58201:001:0228), five structures with material and
  money costs and prerequisites; the park unlocks from a consequence flag.

Farming, hunting, trading and building never reference the timeline, consequence or
artifact systems; the tests check that by grepping the source.

Run the game: `godot --path .` (main menu). Controls: WASD, E interact, Tab register,
J journal, I bag, L language, Esc menu (continue, fullscreen, language, save and quit).
Fullscreen: F11, on macOS Cmd+Ctrl+F; remembered in `user://settings.cfg`, `-- --fullscreen` /
`-- --windowed` override once. Headless checks:

```sh
for t in boot_test playthrough_test farming_test hunting_test economy_test; do
  godot --headless --path . res://tools/godot/$t.tscn; done
```

Site layout lives in `sites/palupera/layout.json` (positions found from the cadastral parcel
and the nDSM building footprint); `sites/palupera/scenes.json` says what stands where in each
era and `make scenes` regenerates the era scenes from both.

Narrative: `sites/<id>/narrative/era_*.ink` (Estonian lines with `# en:` tags, choices as
`[et %% en]`), compiled with `make ink`. Strings: core UI keys in `assets/i18n/strings.csv`,
place and story keys in `sites/<id>/strings.csv`. Press L in game to switch language.

## Custom locations and stories

```sh
make site SITE=kvissentali NAME="Kvissentali" CENTER="657600 6477150"   # scaffold a pack (EPSG:3301 centre)
make tile SITE=kvissentali      # Maa-amet DTM, nDSM, orthophoto, 1938 cadastral and one-verst maps,
                                # Terrain3D import, vegetation, buildings + water, scenes, validation
godot --path . -- --site=kvissentali
```

**Anywhere in Estonia, from the menu:** run `make tile-service` (a loopback Python service that
runs the pipeline on demand), then *New location...* in the main menu: type an address, a place, or
coordinates (or *Use my location*), pick a result, *Create the world*. The service fetches the Maa-amet
data, places the story skeleton on detected anchors and returns a pack; the game installs it under
`user://` and builds the terrain on first visit.

**Generated stories:** packs made by `make site` or the tile service get their story from quest
blocks (`blocks/*.json`, composed by `tools/compose_story.py`): one NPC per era, artifacts to carry
between eras, a choice, visible traces in the later years and three endings, all placed on anchors
found in the data. `make test` plays such a pack through end to end (`story_test`).

A pack holds everything place-specific: `site.json` (terrain tile and centre, sun position, era
ground maps, spawn, journal locations, objectives, ending rules), `layout.json`, `scenes.json`,
`data/` (eras, consequence points, items, manors, structures, trade goods, crops, animals),
`narrative/`, `strings.csv` and the derived `buildings_2026.json` / `water_2026.json`. The scaffold
is a complete, playable skeleton: a register, one NPC per era, one artifact whose return leaves a
stone in every later era, trading, farming, hunting and building copied from Palupera with the eras
remapped. The main menu offers a **Location** button when more than one pack exists; saves remember
their pack. `make validate` checks every pack for broken references without Godot; the site test in
`make test` boots every pack. Details: [docs/custom-sites.md](docs/custom-sites.md).

## Phase 0 technical spike (kept for reference)

One walkable 1 km² of real terrain centred on Palupera village and manor (map sheet 54432,
NW corner EPSG:3301 637036/6444541, 84 to 107 m), the 25 cm
orthophoto draped on it at full resolution, a Sky3D day/night cycle with the sun computed for
Palmse's real latitude/longitude, one Blender-authored prop, a first-person walker and an
FPS/coordinate HUD.
No game systems yet, by design. The site follows `vakuraamat-first-iteration-design.md`;
the earlier Palmse comparison tile was removed from the repo (regenerate with `make site SITE=palmse CENTER="613372 6598710"` and `make tile SITE=palmse`).

## Project init (fresh clone)

```sh
git clone <repo> vakuraamat && cd vakuraamat
make setup      # Homebrew tools, git-lfs pull, npm for the ink compiler, first Godot import
make tile       # downloads Maa-amet data for Palupera and builds the terrain (~10 min, network); SITE=<id> for another pack
make test       # headless test suite
godot --path .  # play
```

Generated data is deliberately not in git: the Terrain3D region file (22 MB, rewritten on every
re-scatter), prepared tree meshes and impostor atlases. `make tile` rebuilds the terrain from the
committed inputs (`heightmap.r32`, `canopy.r32`, `ortho.jpg`, era maps, `sites/<id>/layout.json`); `make trees`
rebuilds the trees (needs Blender and a window for the impostor bake). Large stable binaries
(models, textures, addon binaries, era map images) are tracked with git LFS, see `.gitattributes`.
Coding-agent conventions live in `AGENTS.md`.

## Data generation

| Target | Produces | Inputs |
|---|---|---|
| `make tile SITE=<id>` | `assets/terrain/<tile>/{heightmap.r32, canopy.r32, ortho.jpg, era_*.png, terrain_meta.json, data/, terrain_assets.tres}`, then `make features` and `make scenes` | `sites/<id>/site.json` (centre, size, era map layers), Maa-amet geoportal (DTM, nDSM), WMS orthophoto and historical maps, `sites/<id>/layout.json` (pads, exclusions) |
| `make scatter` | vegetation instances in the region file | control map, `canopy.r32`, layout exclusions |
| `make trees` | `assets/models/trees/*.glb`, `*_mesh.res`, `*_impostor.png`, `*_lod.tscn` | Blender Sapling presets, `assets/textures/foliage/*` |
| `make props` | oak, boundary stone, buildings, figures, prepared vegetation scenes | Blender scripts in `tools/blender`, `assets/textures/buildings/*` |
| `make site SITE=<id> NAME=... CENTER=...` | `sites/<id>/` scaffold (manifest, layout, scenes.json, data, ink, strings) | `tools/new_site.py`, the template pack's gameplay content |
| `make features SITE=<id>` | `sites/<id>/buildings_2026.json`, `water_2026.json` | `canopy.r32`, `heightmap.r32`, `ortho.jpg` (`tools/pipeline/extract_features.py`) |
| `make scenes SITE=<id>` | `sites/<id>/scenes/era_*.tscn` | `sites/<id>/scenes.json`, `layout.json`, `buildings_2026.json` |
| `make validate` | report | every `sites/*/` (`tools/validate_site.py`, no Godot) |
| `make ink` | `sites/*/narrative/*.ink.json` | `sites/*/narrative/*.ink` |

Other one-off analyses (building footprints, ponds, parcel lookups) are documented inline in
`data/*.json` comments and the commit history; the WFS/WMS endpoints are in `THIRD_PARTY.md`.

## Requirements (macOS)

| Tool | Version used | Install |
|---|---|---|
| Godot | 4.7.2 stable | `brew install --cask godot` |
| Terrain3D | 1.0.2 stable (vendored in `addons/terrain_3d`, MIT) | already in repo |
| Sky3D | 2.1.0 (vendored in `addons/sky_3d`, MIT, pure GDScript) | already in repo |
| GDAL | 3.13 | `brew install gdal` |
| Blender | 5.2 LTS (only to regenerate props) | `brew install --cask blender` |
| Python 3 | any 3.9+ (stdlib only) | system |

QGIS is not needed: the whole clip/convert step is scripted with GDAL.

First open: run `godot --headless --path . --import` once (or just open the project in
the editor). Terrain3D's macOS binaries are unsigned; if Gatekeeper blocks them run
`xattr -dr com.apple.quarantine addons/terrain_3d`.

## Run

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path . res://scenes/spike/spike.tscn   # Phase 0 spike scene
tools/verify_spike.sh                                       # windowed run, screenshot + avg FPS, quits
```

WASD move, Shift sprint (9 m/s), Ctrl dash (20 m/s), Space jump, Esc opens the menu and releases the mouse.
F toggles fly mode, a survey tool with no gravity or collision that moves where you look
(40 m/s, Shift and Ctrl multiply). T teleports to the point you are looking at (ray-marched
against the heightfield, so it works across the whole tile), H returns to the spawn point. Sky3D runs a 30-minute day/night cycle with the sun
computed for the site's real latitude and longitude; the HUD shows the game clock. The HUD shows FPS and the
player's L-EST97 (EPSG:3301) easting/northing so alignment can be checked against
Maa-amet's map viewer.

To play on an Android TV over the home network, see [docs/tv-streaming.md](docs/tv-streaming.md)
(Sunshine on the Mac, Moonlight on the TV; no account or cloud involved).

## Terrain pipeline (repeatable, two commands)

```sh
# 1. Maa-amet -> heightmap.r32 + canopy.r32 + ortho.jpg + era maps + terrain_meta.json  (needs network)
python3 tools/pipeline/fetch_tile.py --site palupera        # or --name <tile> --center <E> <N> --era-map kk1940:era_1938_cadastral.png

# 2. -> Terrain3D region data + assets/material resources     (headless Godot)
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
    -s res://tools/godot/import_terrain.gd -- --site=palupera
```

What step 1 does:

1. Finds the 1:10 000 map sheets under the four corners (downloads Maa-amet's `epk10T` sheet
   grid once into `data_raw/`); several sheets are mosaicked with `gdalbuildvrt`.
2. POSTs the geoportal download form (`andmetyyp=dem_1m_geotiff`, `kaardiruut=<sheet>`)
   and downloads the 1 m DTM GeoTIFF for that sheet (~74 MB, cached in `data_raw/`).
3. Clips a `--size` m square with `gdal_translate -projwin`, fills any NoData (water) with
   `gdal_fillnodata`, and writes a raw float32 heightmap. Raw float is used on purpose:
   Godot's PNG loader truncates 16-bit to 8-bit and its EXR loader rejects GDAL's channel
   names.
4. Fetches the orthophoto for the same bbox from the `fotokaart` WMS (layer `EESTIFOTO`,
   EPSG:3301, JPEG, max 4096 px per request; 1024 m at 4096 px = 25 cm/px).
5. Fetches the nDSM canopy/object heights (1:2000 sheets) and the historical ground maps named in
   the site manifest from the `ajalooline` WMS (same bbox, PNG).
6. Writes `terrain_meta.json` with extent, sheets, height range, source URLs, fetch date and
   the attribution string.

What step 2 does: loads the raw heightmap as `Image.FORMAT_RF`, resamples the orthophoto
to one texel per vertex and imports it as the Terrain3D colour map (alpha 0.5 = neutral
roughness) over a flat white ground texture, then saves `data/terrain3d_00_00.res` and
`terrain_assets.tres`.

Step 2 also classifies every metre of the orthophoto by colour into one of four detail
materials (meadow, field, forest floor, gravel; CC0 textures from ambientCG in
`assets/terrain/textures/`) and writes that into the Terrain3D control map, so the ground
has tiled detail, normals and roughness up close.

Step 3 (optional): `tools/godot/scatter_vegetation.gd -- --tile=<name>` scatters trees, bushes
and grass tufts with the Terrain3D instancer according to the same land-cover classes
(canopy gets trees, meadow and field get grass) and saves them into the region file. The
models come from the Forest Vegetation sample pack (MIT, Renard Noir, vendored under
`assets/vendor/forest_vegetation`, prepared by `tools/godot/prepare_vegetation.gd`).

The 1 texel/m colour map is only a fallback. The real drape is `assets/terrain/ortho_drape.gdshader`,
Terrain3D's "lightweight" example shader plus a world-space orthophoto lookup: the scene sets
`ortho_texture`, `ortho_origin` and `ortho_extent` from `terrain_meta.json`, so the 4096 px
image maps exactly onto the 1024 m tile. Within `detail_near` metres the orthophoto colour is
modulated by the detail texture's luminance (plus its normal and roughness); beyond
`detail_far` it is the pure orthophoto. Terrain3D's texture assets cannot do this because
`uv_scale` is clamped to 0.001 (one repeat per 1000 m) and offset by half a texel. The material lives inline in the scene (see the note in the tool about
why it is not saved, and why `region_size` must not be set on the node). It prints probe heights that must equal
`gdallocationinfo` on the clipped GeoTIFF.

### World mapping

The tile's north-west corner is Godot `(0, y, 0)`; `+X` is east, `+Z` is south, `y` is
metres above sea level (EH2000) times `z_scale`. `scripts/terrain/terrain_georef.gd`
converts both ways using `terrain_meta.json`. Vertical exaggeration is `z_scale`
(default 1.0, recorded in the meta file and overridable with `--z-scale`). The Palupera
square has 22 m of relief at 1:1; the Palmse tile had 6 m.

### Limits of the current pipeline

- One tile = one Terrain3D region (at most 2048 m). Sheet boundaries are mosaicked.
- The override shader drops Terrain3D's projection/detiling/paintable-rotation features
  (inherited from the lightweight example). Fine for a drape; revisit if painted textures
  are needed later.
- Historical layers come from the WMS as pictures at 2048 px (about 50 cm/px); vector cadastral
  data is only used offline for positions.

## Layout

```
addons/terrain_3d/           Terrain3D 1.0.2 (vendored)
addons/sky_3d/               Sky3D 2.1.0 (vendored)
assets/terrain/ortho_drape.gdshader  Terrain3D override shader with world-aligned orthophoto
assets/terrain/<tile>/       heightmap.r32, canopy.r32, ortho.jpg, era_*.png, terrain_meta.json, data/, terrain_assets.tres
sites/<id>/                  site pack: site.json, layout.json, scenes.json, data/, narrative/, scenes/, strings.csv
scripts/autoload/sites.gd    the active pack; tools/new_site.py, tools/validate_site.py, tools/gen_era_scenes.py
assets/models/props/         boundary_stone.glb (generated by tools/blender/)
scenes/spike/                Phase 0 scene + script
scenes/player/               first-person walker
scripts/player|ui|terrain/   controller, HUD, georef helper
tools/pipeline/fetch_tile.py Maa-amet download + GDAL clip/convert (+ historical WMS maps)
tools/pipeline/extract_features.py  buildings and still water from the laser data
tools/godot/import_terrain.gd  headless Terrain3D import
tools/blender/make_boundary_stone.py  headless Blender prop generator
tools/verify_spike.sh        acceptance run (screenshot + FPS)
data_raw/                    downloads and intermediates (git-ignored, .gdignore)
```

## Known quirks (Godot 4.7.2 + Terrain3D 1.0.2)

- Never set `region_size` on a Terrain3D node in a scene that also loads region files; it
  segfaults on load. The region file carries its own size.
- Don't save a `Terrain3DMaterial` from a headless run; its shader parameters come out null.
  Define the material inline in the scene.
- A `Terrain3D` node added from a `SceneTree` script only initialises on the next frame
  (`await process_frame`), and its data directory must already exist.
- Headless `--import` prints a `double_slider.gd` script error from the Terrain3D editor UI.
  It is harmless: the editor setting it reads only exists in a real editor session, where
  the plugin loads without errors.

## Data licence

Maa-amet open data, free for commercial use with attribution. In-game credit line
(also in `terrain_meta.json`): "Map data: Maa- ja Ruumiamet (Estonian Land and Spatial
Development Board), 2026".
