# Working on Vakuraamat with a coding agent

Read this before changing anything. `CLAUDE.md` points here; the human-facing overview is `README.md`.

## What this is
A Godot 4.7 (GDScript) digital twin of real Estonian ground, built from Maa-amet open data: one
1 km² tile, its real cadastral units with their 2022 taxation values, real buildings from the
Building Register with LOD2 roofs, the companies registered at each address (Business Register),
real roads, and every orthophoto flown over the place since 1993. You walk or fly through it and
ask the registers what is around you. Every place is a **site pack** under `sites/<id>/`
(Kvissentali is the first, Palupera the rural second); the engine reads the active pack through the
`Sites` autoload and never names a site. Authoring guide: `docs/custom-sites.md`.
Two earlier versions are tags: the historical three-era game is `v0.9-historical`, and the
present-day economy game (buying, renting, a shared SpacetimeDB town ledger) ends at `v0.5.1`.

## Hard rules
- Nothing is invented, owned, priced or bought. Every figure the UI shows is a field of a pack file;
  where a register says nothing, the line is absent. Terrain, buildings, trees, roads and traffic are
  regenerated from data on every machine, and a save is only where you were standing.
- The cadastre is read through `Parcels`: `units(pack)` is one pack's own file in its local metres,
  `all()` is every tile standing right now in world metres (a streamed neighbour's x/z shifted by its
  tile offset), `by_tunnus()` finds one. Companies through `Tenants.of(pack, tunnus)`, and what ties
  a unit to another through `Links.of(tunnus)`. All cache per file and are dropped by
  `GameState.reload()`.
- Every third-party file gets a row in `THIRD_PARTY.md` in the same commit (the project will be
  open source). Prefer CC0/MIT. Nothing from Fab/Megascans. Data files carry `attribution`.
- Site content lives in `sites/<id>/`: `site.json` (manifest), `layout.json` (positions),
  `scenes.json` (the layer), `data/eras/era_2026.tres`, `parcels.json`, `buildings.json`,
  `tenants.json`, `market.json`, `roads.json`, `stops.json`, `departures.json`, `fields_2026.json`, `strings.csv`. `make scenes SITE=<id>`
  regenerates `sites/<id>/scenes/*.tscn`; do not hand-edit those scenes. Engine code (`scripts/`,
  `scenes/`) must not reference a site by name; go through `Sites` (manifest, `data_dir`, `layout`, `tile`).
- Real names: the companies are real (legal persons only). The register's natural persons are never
  named: they exist in a pack only as the hashed ids `Links` groups plots by, and never reach the UI.
- Playtest loop: reports from F8 land in `user://reports/` (feed.log); `python3 tools/dev.py reload|restart|replay|
  teleport|screenshot` talks to the running debug game through `user://dev/commands.jsonl`
  (`DevChannel` autoload); `python3 tools/dev.py nan` lists the 3D nodes whose transform or bounds
  hold a NaN or inf (what breaks the renderer's sorting). See `docs/dev-loop.md`.
- Pack files use `null`, not a missing key, for what a register does not say (71 of Kvissentali's
  211 buildings have no year), and `Dictionary.get(key, default)` only substitutes the default when
  the key is *absent*: `int(null)` then fails with "Nonexistent 'int' constructor" and takes the rest
  of the loop with it. Read those fields through a helper that treats null as empty (`PlaceSearch._text`
  and `_num` are the pattern).
- Country data adapters: `tools/pipeline/sources.py` (Estonia implemented; add a class per country).
- A pack for a new place is built in two passes. The job ships what the place needs to be walked in
  (the 5 m ground model, 4 MB a sheet against 75 MB for the 1 m one; the register, cadastre, roads,
  tenants), then `refine_job` fetches the 1 m ground, the measured trees and the departures in the
  background and rewrites the zip. The tile's `terrain_meta.json` carries `dtm_res_m`; while it says
  5, `Locator.take_refined` takes the finished pack the next time the place is entered from the menu
  (the install clears the region data, so the ground is rebuilt from the finer model on the way in).
  Every stage that reaches a national service goes through `with_deadline`: an optional layer may
  never hold the pack (the notices feed, since removed, once held it for eight minutes). Per-building register
  lookups go through `fetch_buildings.prefetch_ehr` (a few threads sharing one rate limit), never one
  after another.
- Buildings come from `tools/pipeline/fetch_buildings.py` (ETAK polygons + Building Register attributes +
  Geo3D LOD2 roofs) into `sites/<id>/buildings.json`; parcels with land values from `fetch_parcels.py`,
  tenants from `fetch_tenants.py`, the valuation medians from `market.py`, the bus lines and
  departure times from `fetch_departures.py`.
- The tile service holds the pipeline modules in memory from the moment it started: after changing
  anything under `tools/pipeline/`, restart it (`pkill -f tools/tile_service.py`, then `tools/play.sh`
  or `make service`) or the next pack is built by the old code. Cached `.slim` register files are
  keyed on `register_extra.SLIM_VERSION`; bump it when a slimmer changes.
- Every pack records which pipeline built it as `"pipeline"` in its `site.json` (`PACK_VERSION` in
  `tools/new_site.py`, mirrored by `Sites.PACK_VERSION`; `make validate` fails if the two drift).
  **Bump it whenever a stage starts producing something a pack cannot do without** - a new field the
  UI reads, a source added, a shape changed. Downloaded packs stamped lower than the build's number
  are rebuilt: the tile the player is walking on is loaded first and swapped afterwards
  (`TileStreamer.refresh_tile`), the rest go through `Locator`'s background queue. A refresh
  re-fetches the registers and keeps the ground, so it costs seconds, not the twenty minutes a
  forced rebuild does.
- Service: `tools/tile_service.py` (packs for a point, port 8765) is a loopback Python server the game
  talks to through `Locator`. It is the only service.
- Core UI strings stay in `assets/i18n/strings.csv`; place strings go in the pack's `strings.csv`
  (imported to `.translation` next to it; `make import` after editing).
- Generated data is not committed: `assets/terrain/*/data`, tree meshes and impostor atlases. Rebuild
  with `make tile` / `make trees`. Large stable binaries are in git LFS (`.gitattributes`).

## Commands
- Tree models: `assets/models/trees/<name>_src.glb` (vendored) beats the Sapling `<name>.glb`; `make trees`
  (or `prepare_trees.gd -- --only=<name>` then `bake_impostors.tscn -- --only=<name>`) merges its meshes,
  prunes stray pieces beside the trunk, brightens the needles and bakes the impostor. `MODEL_HEIGHT` in
  terrain_builder.gd is the model's own height; instances scale to the canopy height, up to 6x.
- Releases: add the entry to `CHANGELOG.md`, then `git tag -a vX.Y.Z` with the same summary as its
  message and push the tag; `.github/workflows/build.yml` builds the three platforms and makes the
  GitHub release whose notes are the tag's `CHANGELOG.md` entry (the tag's message when there is
  none), followed by the commits since the previous tag.
- `make setup` once; `make test` before every commit (validates every pack, boots every pack, dev
  channel, traffic, streaming, interiors, search, links); `make lint` (the same checks as GitHub:
  gdlint with `.gdlintrc`, ruff with `ruff.toml`, shellcheck, actionlint when installed);
  `make export` for a macOS build.
- New location: `make site SITE=<id> NAME="..." CENTER="<easting> <northing>"` then `make tile SITE=<id>`
  (fetches DTM/nDSM/orthophoto, builds terrain, derives buildings and water,
  generates scenes, validates). `make validate` is pure python and fast; run it after editing a pack.
- Godot headless scripts: `godot --headless --path . -s res://tools/godot/<tool>.gd` for SceneTree
  tools; scenes that need autoloads run as `godot --headless --path . res://tools/godot/<test>.tscn`.
- zsh does not word-split unquoted variables: when looping over argument strings use `${=args}`.
- Screenshots for visual checks: `godot --path . res://scenes/world/world.tscn -- --screenshot=/abs.png
  --frames=400 --spawn=x,z,yaw --open=journal|map|menu|book|place|companies --enter="<address part>"`;
  add `--site=<id>` for another pack.

## Conventions and pitfalls
- The world's flags (`--site=`, `--spawn=`, `--open=`, `--enter=`, `--screenshot=`) are user args: they go
  after `--`, and the run must name `res://scenes/world/world.tscn`, else the main menu opens and waits.
- Real buildings snap to the lowest vertex of their footprint outline (the group's bounding box sank
  L-shaped houses); the eave is the top of the longest wall face; window sills measure from the ground
  under each face. Test with a report replay: `-- --report=<json> --screenshot=...`.
- World flags for checks: `--examine="<address part>"` opens a building's register sheet (E on its
  wall), `--open=find:<text>` and `--open=plots:<text>` open the find bar and the book's plot list
  with a query typed in, `--open=plot:<tunnus>#<n>` opens the plot page and enlarges the nth picture of its history,
  `--open=goto:<text>` types a query into the find bar **and chooses the first result**,
  `--focus=<tunnus>` (or `--open=focus:<tunnus>`) lights a plot and everything the registers tie it to,
  `--open=hover:<tunnus>` holds the debug map's slip open over one plot,
  `--hour=<h>` sets the time of day (street lights and windows light after
  18:30), `--fly` starts in the air for a survey.
- Performance numbers: `--bench` (with `--windowed --site=<id>`) turns once at street level, walks at the
  nearest building (the summary's `moved_m`, `to_centre_m`, `above_ground_m` and `user://logs/bench_walk.png`
  show that floors and walls still hold the player), flies 2 km
  north at 120 m across the next tiles, uncapped, then quits; the summary is printed as `[bench]` lines
  and written to `user://logs/bench.json`, and PerfLog's SPIKE lines name what ran (tile loads, slow
  members, traffic ticks, pipeline compilations). `--bench-off=traffic,details,doors,tcol` switches a
  system off to bisect a hitch. `--scale3d=<mode>:<scale>` overrides the 3D upscaler (mode 0 bilinear,
  1 FSR1, 2 FSR2, 3 MetalFX spatial, 4 MetalFX temporal) and `--fx=a,b,c` limits the environment
  effects to the ones named (`sdfgi`, `ssao`, `ssil`, `fog`, `glow`, `grade`; `softsun` adds the soft
  sun shadows, which are off by default). Compare before/after on the same site, alternating runs: a laptop's
  FPS drifts 20-30% as it heats, draw calls and hitch counts do not. Use a pack that has been entered as the
  origin (`toomemagi`); a tile only ever streamed as a neighbour has no `terrain_assets.tres` and renders
  Terrain3D's checkerboard when launched with `--site`.
- Drawing: shared meshes and materials are cached for the session (`HumanFigure.scene`/`tinted`,
  `MeshMerge.instance`/`baked`, door and detail meshes) and released by the world's `_exit_tree`; a
  vendored model with many parts goes through `MeshMerge` (one surface per material). Every prop class
  sets a `visibility_range_end`. Beyond 350 m buildings draw as `BuildingChunks` cells (merged on the
  worker pool, one per 128 m, the building's mesh names its cell as `visibility_parent`); each cell also
  carries the walls as an occluder, switched off while the player is inside one of its buildings.
  Every `WorkerThreadPool.add_task` must be waited for (`wait_for_task_completion`), or what the task
  captured outlives the renderer and the quit crashes (exit 134, "RenderingServer is null").
- Physics is Jolt. Concave colliders set `backface_collision = true`: Jolt ignores the back of a face
  otherwise, and the LOD2 walls are wound either way (the player walked through them).
- Data sources, make targets and the terrain pipeline are documented in `docs/data-pipeline.md`; the
  README only links there. Keep the README short.
- Poly Pizza downloads cannot be scripted (403 on the file host); the user saves the glb by hand into
  `assets/vendor/polypizza/<name>.glb`, then add a THIRD_PARTY.md row (Kenney and Quaternius there are
  CC0, "Poly by Google" is CC BY 3.0). Scale every vendored model from its bounds (`Interiors._bounds`).
- The pipeline's Python is `.venv-service/bin/python` (`make setup`; rasterio, pyogrio, shapely, pyproj
  wheels, no system GDAL); `make` targets, `tools/play.sh` and the game's launcher pick it up. Raster and
  vector work goes through `tools/pipeline/geo.py`; caches through `paths.raw(<name>)`. `make service`
  freezes the tile service into a sidecar that CI ships beside every build.
- Company data: `tenants.json` keeps the register's people files as structure only (`board_size`,
  `shareholders`, `owners` = hashed ids for links). Never print an `owners` entry, never add names,
  e-mails or phones; `make validate` rejects them.
- Sketchfab is scriptable: `make mcp` builds the MCP server (`sketchfab-search`, `-model-details`,
  `-download`; token in the ignored `sketchfab.token`). The MCP omits the licence: check it with
  `GET https://api.sketchfab.com/v3/models/<uid>` (`license.label`); only CC BY / CC0 ship, "Free
  Standard" forbids redistribution. Models go to `assets/vendor/sketchfab/<name>.glb` with a row in
  `CREDITS.md` there and in THIRD_PARTY.md. Packs are split into one glb per model with
  `blender --background --python tools/blender/split_glb.py -- <pack.glb> <out_dir> "<name>=<regex>" ...`;
  the download tool needs the output directory to exist. Sketchfab exports are often in cm or with
  a scaled root: never assume metres, fit from bounds.
- "Resource file not found: res://" and "Error loading resource: ''" right after a pack switch, with no
  GDScript backtrace: Terrain3D reading a downloaded tile's still-empty data directory on its first
  visit. Harmless; the region is built and saved right after.
- Prop checks without a world: `tools/godot/figure_preview.tscn` (the eight figures), `bike_preview.tscn`
  (bicycles with riders, side-on, a red block marking the riding direction).
- Main-menu screenshot: `godot --path . res://tools/godot/menu_shot.tscn -- --windowed --out=/abs.png`
  (or `--fullscreen`; `--locations` for the second page, `--creating` / `--failed` for the world-creation
  sheet). Menu strings come from compiled translations: run `godot --headless --import` after editing
  `strings.csv` or the screenshot shows raw keys.
- Strings: `assets/i18n/strings.csv` (keys, et, en). Add keys, never hard-code text.
- UI look: `BookTheme` (scripts/ui/book_theme.gd) is the one theme; new panels set `theme =
  BookTheme.theme()` and use its type variations (HeadLabel, DetailLabel, PrimaryButton, TextButton,
  RowButton) instead of font or colour overrides; euro figures through `BookTheme.money()`, no " · " joins.
- A node added from a `SceneTree._init()` script enters the tree one frame later: `await process_frame`
  before touching Terrain3D objects. `assert()` does not stop headless tests; use the
  `_check()` helper pattern and the watchdog timer.
- GDScript: annotate types when the right side is a Variant (`var x: String = dict.key`), or the
  headless parser fails with "Cannot infer the type".
- Terrain3D 1.0.2 on Godot 4.7.2: never set `region_size` on the node in a scene; never save a
  `Terrain3DMaterial` from headless; headless import prints a harmless `double_slider.gd` error.
- Tile world mapping: north-west corner at Godot (0, y, 0); +X east, +Z south; heights are metres.
  `TerrainGeoref` converts to EPSG:3301.
- Sky3D owns the Environment; extra effects are set in `World._configure_environment()`.
- Buildings: origin at the base, `metadata/footprint` on the group; EraController snaps to the lowest
  corner and `import_terrain.gd` levels pads listed in the layout.
- Facing: exported models (MakeHuman figures, Kenney cars, the CSG bicycle) face +Z; agents, NPCs
  and the player face -Z. Turn a model once where it is loaded (`model.rotation.y = PI`), never in
  the mover. Render a preview with a direction arrow (`tools/godot/figure_preview.tscn`) before trusting it.
- Vendored meshes may lie on their side (the junipers did, in every tile). Check a new vegetation or
  prop mesh standing on a plane before scattering it; `tools/godot/fix_mesh_up.gd` stands one upright.
- Anything placed on the terrain in a scene layer is snapped by `EraController`: container groups
  (`Buildings`, `Parcels`, `Village`) stay at y 0 and their children snap; a node that positions its
  own pieces on the ground sets `metadata/no_snap` on itself AND on its parcel group, or its heights
  double and it floats in the sky.
- Vegetation bakes exclude roads and building footprints at scatter time (`road_mask`, `footprint_mask`);
  region `.res` files are generated, so after touching scatter inputs or `buildings.json` run
  `make scatter SITE=<id>` on every machine. Cached neighbour tiles under `user://tiles` keep their old
  bake; the interior stamps grass away on first entry as the safety net.
- Streamed tiles sit at a 1024 m offset: nodes must read pack files through
  `Sites.path_in(Sites.pack_of(self), ...)` and sample the terrain with `to_global(...)`; `Parcels.at`
  already resolves the tile. Never assume tile-local equals world coordinates. Tenant lookups go
  through `Tenants.of(Sites.pack_of(node), tunnus)` and plots through `Parcels.all()` or
  `Parcels.by_tunnus()`, which already carry the offset;
  `TileStreamer.tile_ready` / `tile_unloaded` are the hooks for per-tile content.
- Hot reload keeps instance state: a member variable added to a script is null on the live instance
  until restart, so guard new dictionaries and arrays (`if _cache == null: _cache = {}`), or `restart`.
- `tools/dev.py` targets the newest game instance; while `make test` runs, its headless games are
  newer than the player's, so pass `--pid <n>` (from `python3 tools/dev.py instances`).
- Headless (`--headless`) has no rendering buffers: MultiMesh transforms read back as zero and AABBs
  are empty. Verify anything visual with a windowed `--screenshot` run, not a headless probe.
- Water shaders that composite `SCREEN_TEXTURE` must write `ALPHA` (even 1.0) to land in the
  transparent pass; otherwise the screen copy is taken after the surface and everything below vanishes.
- Godot `-s` tool scripts run without autoloads: static helpers used by tools take paths, not `Sites`.
- `HTTPRequest` cannot read `kaart.maaamet.ee/wms/...` over TLS: a GetMap comes back
  RESULT_CONNECTION_ERROR every time, while the same URL over plain http, the same host's other
  paths over https, and curl over either all answer normally (4.7.2; not gzip, and the certificate
  chain is the one `geoportaal.maaamet.ee` serves and Godot accepts). `PlotHistory` tries https and
  falls back to http; the imagery is public open data and the request carries nothing private.
- Water patches from `extract_features.py` are bounding rectangles; long ditches become slabs over
  land. Basins are carved only where the DTM was flat, but the surface still covers the rectangle.
- Loading a world hands the player the ground first and fills the rest in behind them: the era scene
  is parsed on a loader thread, its `Buildings` and `Parcels` enter the tree nearest-first a few
  milliseconds a frame (`EraController.detach_heavy` / `fill_pending`, the same path the streamer
  uses for neighbour tiles), finished building meshes are applied on a per-frame budget
  (`FootprintBuilding._queue_apply`), and a downloaded tile's vegetation is scattered after the fade
  lifts. Anything that walks the whole layer (doors, tenant signs, `_building_blocks`) must therefore
  skip its pass while `world.filling` and run again on `world.era_filled`, or it will scan a growing
  tree over and over and miss what arrives late. `data/vegetation.ok` marks a tile whose greenery
  stands; the runtime scatter never rewrites `terrain_assets.tres` (`save_assets` false), only `make tile` does.

## Tests
`tools/godot/*_test.tscn`: parse, geotiff, search, boot (autoloads, the layer, the cadastre, a save
round-trip), site (every pack: registry, layer scene, translations, plots, companies), userpack,
devchannel, traffic, streaming (a synthetic neighbour tile, and the merged offset-aware `Parcels.all()`
over both), interior, links (what `Links` ties a plot to, read from the pack files with no world, and
that an owner hash never leaves `links.gd`). Keep them green. `tools/validate_site.py` checks pack references without Godot.
