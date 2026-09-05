# Vakuraamat

An economy game on real Estonian ground: buy, rent out and build on the actual cadastral plots of
a square kilometre, priced from Maa-amet's land values, with the real companies as tenants, alone
or in a town shared with other players. Built from Maa-amet (Estonian Land and Spatial Development
Board) and Business Register open data. Godot 4.7, GDScript, Terrain3D, SpacetimeDB.

Design and plan: `vakuraamat-implementation-plan.md` (phases, architecture rules) and
`vakuraamat-maaamet-data-pipeline.md` (data sources). This README covers what exists
in the repo right now.

## Screenshots

| | |
|---|---|
| ![The front page: the menu as a ledger page with the plate of the square kilometre](docs/screenshots/menu.jpg) The front page: the menu as ruled ledger entries, the plate of your square kilometre with its cadastral units | ![The plots: land value, price, owner and yield, nearest first](docs/screenshots/plots.jpg) The book (Tab): the plots nearest you with land value, price, owner and monthly yield, Guide and Go on every row |
| ![A Kvissentali street with real buildings and tenant name plates](docs/screenshots/street.jpg) A Kvissentali street: real buildings, real tenants on their name plates, the town notice on connecting | ![Inside a company's building: rooms, a doorway, windows onto the street](docs/screenshots/shop.jpg) Inside a company's building: rooms with doorways, furniture by use, the windows look out at the street |
| ![Inside a dwelling: a bedroom](docs/screenshots/home.jpg) Inside a dwelling: a bedroom, the floor above the ground, the exterior door open to the street | ![The town feed: real headlines next to the game's events](docs/screenshots/news.jpg) The town feed (N): the region's real headlines and planning notices next to the game's own events |
| ![Locations: packs you have, the tile service, suggested places, the town](docs/screenshots/locations.jpg) Locations: the packs you have, what the tile service can make, suggested places, the town address | ![Debug map: every tenant and plot on the orthophoto, click to teleport](docs/screenshots/map.jpg) Debug map (M): every plot and tenant on the orthophoto, click to teleport |
| ![Palupera: the rural pack](docs/screenshots/palupera.jpg) Palupera, the rural pack: 58 plots around the old manor site | ![The road into Palupera, real trees from the laser scan](docs/screenshots/forest_road.jpg) The road into Palupera, real trees from the laser scan |

All ground, buildings, tree heights, plots, land values and company names come from Maa- ja
Ruumiamet and Business Register open data of the real places; the prices that move, the tenants
that fall behind and the families that bid are the game's rules.

Every place is a **site pack** (`sites/<id>/`): Kvissentali (Tartu) is the first town, Palupera the
rural second, and any 1 km² of Estonia can be added with two make targets. See
[docs/custom-sites.md](docs/custom-sites.md) and the section below.

## Status: present-day economy on real plots

Vakuraamat is now an economy game on the real square kilometre: every cadastral unit carries
its 2022 land value in euros, real companies from the Business Register sit on the plots as
tenants, and one town's ledger (owners, prices, bids, obligations, news) can be shared with other
players through a SpacetimeDB town server. The historical three-era game (1798, 1938, 2026, farming,
hunting, ink stories) lives on at the tag `v0.9-historical`.

- **The book (Tab):** the plots nearest to you with land value, price, owner and monthly yield;
  a plot's card with Buy, Bid, List for sale, Build, Collect or Settle arrears, Accept offer, Guide
  and Go; your portfolio with cash, income, obligations, favours, heat and reputation; offers in
  and out; the town's month, price index and connection. **B** opens the plot under your feet.
- **A month every ten real minutes:** rents come in (tenants sometimes fall behind), land tax comes
  due, prices drift, and the Kask, Tamm and Lepik families bid on your plots.
- **The town feed (N):** the game's sales, rents and bids next to the region's real headlines and
  planning notices.
- **Online or offline:** with a town server reachable, everyone in the town shares one ledger and
  sees each other walk; without it the same rules run in your own book, which the save holds.
- **Walk in:** every real building has a door; inside is generated from its footprint and register
  data (storeys, window rhythm, a ramp between floors) and furnished by use with Kenney's CC0
  furniture. The exterior hides while you are in, so the windows look out at the real street.
- Terrain, buildings, trees, roads, parcels and traffic are unchanged: real, regenerated per tile,
  never sent over the network.

Run the game: `godot --path .` (main menu). Controls: WASD, E interact, Tab vakuraamat, B buy here,
N news, J journal, K codes, M map, L language, Esc menu. Fullscreen: F11, on macOS Cmd+Ctrl+F.
Headless checks: `make test` (validation, boot, site, user packs, dev channel, traffic, streaming,
ledger, town).

## Custom locations

```sh
make site SITE=kvissentali NAME="Kvissentali" CENTER="657600 6477150"   # scaffold a pack (EPSG:3301 centre)
make tile SITE=kvissentali      # Maa-amet DTM, nDSM, orthophoto, 1938 cadastral and one-verst maps,
                                # Terrain3D import, vegetation, buildings + water, scenes, validation
godot --path . -- --site=kvissentali
```

**Anywhere in Estonia, from the menu:** start with `tools/play.sh` (it launches the tile service, a loopback Python service that
runs the pipeline on demand), then *Locations* in the main menu: type an address, a place, or
coordinates (or *Use my location*), pick a result, *Create the world*. A progress sheet follows the
service through its stages (Maa-amet data, the building register, the cadastre, tenants and market,
packing; usually a couple of minutes) and the game installs the pack under `user://` and builds the
terrain on first visit.

**Generated packs:** packs made by `make site` or the tile service are complete town packs: a landmark, the
real footprints, roads, parcels with land values, tenants, the market snapshot, traffic and a bicycle.
`make test` boots every pack (`site_test`) and plays the offline ledger on Kvissentali (`ledger_test`).

**Streets, plots and facades:** ETAK roads become asphalt streets with kerbs, footpaths and gravel
roads; every cadastral unit gets what its registered purpose implies (`assets/data/parcel_rules.json`:
playground, park benches, garden hedge, industrial fence); buildings have textured facades by material,
window rows per floor, doors and chimneys. K shows the cadastral number, building codes and registry links.

**Land values:** every cadastral unit carries its official 2022 land value in euros (`land_value` in
`parcels.json`, from the same Maa-amet cadastre service), and `make market` derives `market.json`, the
median euros per m² by intended purpose. These are taxation values, labelled as such; a hand-exported
Maa-amet transaction table can be joined with `make market XLSX=<file>`.

**Tenants:** the companies registered on the tile's addresses come from the e-Business Register's
open data and are matched to parcels and buildings (`tenants.json`, `make tenants`), by the address
id the Building Register shares with the company register where possible, else by street and number.

**Towns (shared ledger):** `server/vakuraamat/` is a SpacetimeDB module holding a tile's ledger:
parcels, owners, prices, tenants, bids, obligations and news. `make server` runs SpacetimeDB locally,
`make town SITE=kvissentali` publishes and seeds the town from the pack. See
[docs/custom-sites.md](docs/custom-sites.md#towns-the-shared-ledger).

**News:** `make news` pushes the region's real headlines (ERR, Postimees) and official planning and
auction notices into the town feed as headline, source and link; `make news-local` keeps them in the
pack for offline play. Press N in the game.

**Real buildings and trees:** every building in a tile comes from the topographic database (footprint),
the Building Register (year built, floors, purpose, facade and roof materials, heating, water, solar)
and Maa-amet's LOD2 3D models (roof shapes); a building appears only in the eras after its first year
of use, coloured by its materials, with a chimney where there is a flue. In towns, every tree stands
where the laser scan found it, at its measured height (Maa-amet single-tree models).

**Report and fix loop:** F8 in the game saves a report (frame, note, position, target, nearby buildings,
recent errors, a save); `tools/dev.py` replays it, hot reloads scripts, scenes or pack data into the
running game, or restarts it at the same spot. See [docs/dev-loop.md](docs/dev-loop.md).

**Other countries:** the data side is one adapter class per country (`tools/pipeline/sources.py`);
only Estonia exists so far, the planned ones are listed there.

**Friends:** `make world-service`, then *Share this world* in the Locations panel gives a code; a
friend enters it under *Visit* and plays your world (regenerated on their side, starting from your
committed consequences). What they trigger there comes back to you as deliveries the next time you
load, as consequences with a ledger line. Some quest blocks can only be finished by a visitor.

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
