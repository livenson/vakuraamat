# Working on Vakuraamat with a coding agent

Read this before changing anything. `CLAUDE.md` points here; the human-facing overview is `README.md`.

## What this is
A Godot 4.7 (GDScript) game on real Estonian terrain from Maa-amet open data. Three eras of one
1 km² tile, scripted cross-era consequences, era-local farming/hunting/trading/building. Every
place-and-story is a **site pack** under `sites/<id>/` (Palupera is the original; Kvissentali a
scaffold); the engine reads the active pack through the `Sites` autoload and never names a site.
Authoring guide: `docs/custom-sites.md`.
The design and plan documents in the repo root are authoritative: `vakuraamat-implementation-plan.md`
(architecture rules), `vakuraamat-first-iteration-design.md` (content), `vakuraamat-language-notes.md`,
`vakuraamat-maaamet-data-pipeline.md`, `vakuraamat-visual-upgrade-plan.md`.

## Hard rules
- No live simulation of causality: cross-era effects are flags in `TimelineState`, read by era scenes.
- Only `ArtifactItem`s cross eras. Farming, hunting, trading and building code must not reference
  `TimelineState`, `ConsequencePoint` or `ArtifactItem`; the tests grep for it.
- Every third-party file gets a row in `THIRD_PARTY.md` in the same commit (the project will be
  open source). Prefer CC0/MIT. Nothing from Fab/Megascans.
- Site content lives in `sites/<id>/`: `site.json` (manifest), `layout.json` (positions),
  `scenes.json` (era layers), `data/` (eras, consequence points, items, manors, structures, trade
  goods, crops, animals), `narrative/` (ink), `strings.csv`. `make scenes SITE=<id>` regenerates
  `sites/<id>/scenes/*.tscn`; do not hand-edit those scenes. Engine code (`scripts/`, `scenes/`)
  must not reference a site by name; go through `Sites` (manifest, `data_dir`, `layout`, `tile`).
- Playtest loop: reports from F8 land in `user://reports/` (feed.log); `python3 tools/dev.py reload|restart|replay|
  teleport|era|screenshot` talks to the running debug game through `user://dev/commands.jsonl`
  (`DevChannel` autoload). See `docs/dev-loop.md`.
- Country data adapters: `tools/pipeline/sources.py` (Estonia implemented; add a class per country).
- Buildings come from `tools/pipeline/fetch_buildings.py` (ETAK polygons + Building Register attributes +
  Geo3D LOD2 roofs) into `sites/<id>/buildings.json`; the `footprints` scene node filters them by era year.
- Services: `tools/tile_service.py` (packs for a point, port 8765) and `tools/world_service.py` (shared
  worlds and deliveries, port 8766) are loopback Python servers; the game talks to them through the
  `Locator` and `Friends` autoloads. Tests that need them start their own instance (`friends_test`).
- Generated stories come from `blocks/*.json` via `tools/compose_story.py` (used by `tools/new_site.py`
  and the tile service `tools/tile_service.py`); the Palupera pack is hand-written and does not use blocks.
- Core UI strings stay in `assets/i18n/strings.csv`; story/place strings go in the pack's
  `strings.csv` (imported to `.translation` next to it; `make import` after editing).
- Generated data is not committed: `assets/terrain/*/data`, tree meshes and impostor atlases. Rebuild
  with `make tile` / `make trees`. Large stable binaries are in git LFS (`.gitattributes`).

## Commands
- `make setup` once; `make test` before every commit (validates every pack, boots every pack, then
  the Palupera story tests); `make lint`; `make export` for a macOS build.
- New location: `make site SITE=<id> NAME="..." CENTER="<easting> <northing>"` then `make tile SITE=<id>`
  (fetches DTM/nDSM/orthophoto/historical maps, builds terrain, derives buildings and water,
  generates scenes, validates). `make validate` is pure python and fast; run it after editing a pack.
  GitHub too: gdlint with `.gdlintrc`, ruff with `ruff.toml`, shellcheck); `make export` for a macOS build.
- Godot headless scripts: `godot --headless --path . -s res://tools/godot/<tool>.gd` for SceneTree
  tools; scenes that need autoloads run as `godot --headless --path . res://tools/godot/<test>.tscn`.
- zsh does not word-split unquoted variables: when looping over argument strings use `${=args}`.
- Screenshots for visual checks: `godot --path . res://scenes/world/world.tscn -- --screenshot=/abs.png
  --frames=400 --era=era_1938 --spawn=x,z,yaw --open=register|journal|map|trade|build|menu`;
  add `--site=<id>` for another pack.

## Conventions and pitfalls
- Main-menu screenshot: `godot --path . res://tools/godot/menu_shot.tscn -- --windowed --out=/abs.png`
  (or `--fullscreen`).
- Ink: Estonian lines with `# en:` tags; choices `[et %% en]` (ink reserves `|`); `# me` marks the
  player; `# speaker: KEY` overrides. Compile with `make ink`. EXTERNAL functions are listed in
  `scripts/autoload/narrative.gd`.
- Strings: `assets/i18n/strings.csv` (keys, et, en). Add keys, never hard-code text.
- A node added from a `SceneTree._init()` script enters the tree one frame later: `await process_frame`
  before touching Terrain3D or inkgd objects. `assert()` does not stop headless tests; use the
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
- Streamed tiles sit at a 1024 m offset: nodes must read pack files through
  `Sites.path_in(Sites.pack_of(self), ...)` and sample the terrain with `to_global(...)`; `Parcels.at`
  already resolves the tile. Never assume tile-local equals world coordinates.
- Hot reload keeps instance state: a member variable added to a script is null on the live instance
  until restart, so guard new dictionaries and arrays (`if _cache == null: _cache = {}`), or `restart`.
- `tools/dev.py` targets the newest game instance; while `make test` runs, its headless games are
  newer than the player's, so pass `--pid <n>` (from `python3 tools/dev.py instances`).
- Headless (`--headless`) has no rendering buffers: MultiMesh transforms read back as zero and AABBs
  are empty. Verify anything visual with a windowed `--screenshot` run, not a headless probe.
- Water shaders that composite `SCREEN_TEXTURE` must write `ALPHA` (even 1.0) to land in the
  transparent pass; otherwise the screen copy is taken after the surface and everything below vanishes.
- Godot `-s` tool scripts run without autoloads: static helpers used by tools take paths, not `Sites`.
- Water patches from `extract_features.py` are bounding rectangles; long ditches become slabs over
  land. Basins are carved only where the DTM was flat, but the surface still covers the rectangle.

## Tests
`tools/godot/*_test.tscn`: boot (autoloads, data, ink, save), site (every pack: registries, era
scenes, translations, ink), userpack, friends, devchannel, traffic, streaming, playthrough (all five
Palupera consequences, chapters, endings, save round-trip), farming, hunting, economy (trading +
building). Keep them green. Each test is capped at 180 s by the Makefile; a test that is silent for
two minutes is stuck (usually a parse error in the test script), do not wait for it. `tools/validate_site.py`
checks pack references without Godot.
