# Working on Vakuraamat with a coding agent

Read this before changing anything. `CLAUDE.md` points here; the human-facing overview is `README.md`.

## What this is
A Godot 4.7 (GDScript) game on real Estonian terrain from Maa-amet open data. Three eras of one
1 km² tile (Palupera), scripted cross-era consequences, era-local farming/hunting/trading/building.
The design and plan documents in the repo root are authoritative: `vakuraamat-implementation-plan.md`
(architecture rules), `vakuraamat-first-iteration-design.md` (content), `vakuraamat-language-notes.md`,
`vakuraamat-maaamet-data-pipeline.md`, `vakuraamat-visual-upgrade-plan.md`.

## Hard rules
- No live simulation of causality: cross-era effects are flags in `TimelineState`, read by era scenes.
- Only `ArtifactItem`s cross eras. Farming, hunting, trading and building code must not reference
  `TimelineState`, `ConsequencePoint` or `ArtifactItem`; the tests grep for it.
- Every third-party file gets a row in `THIRD_PARTY.md` in the same commit (the project will be
  open source). Prefer CC0/MIT. Nothing from Fab/Megascans.
- Positions are authored in `data/site_layout.json`; `tools/gen_era_scenes.py` regenerates
  `scenes/eras/*.tscn`. Do not hand-edit those scenes.
- Generated data is not committed: `assets/terrain/*/data`, tree meshes and impostor atlases. Rebuild
  with `make tile` / `make trees`. Large stable binaries are in git LFS (`.gitattributes`).

## Commands
- `make setup` once; `make test` before every commit; `make export` for a macOS build.
- Godot headless scripts: `godot --headless --path . -s res://tools/godot/<tool>.gd` for SceneTree
  tools; scenes that need autoloads run as `godot --headless --path . res://tools/godot/<test>.tscn`.
- Screenshots for visual checks: `godot --path . res://scenes/world/world.tscn -- --screenshot=/abs.png
  --frames=400 --era=era_1938 --spawn=x,z,yaw --open=register|journal|map|trade|build`.

## Conventions and pitfalls
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

## Tests
`tools/godot/*_test.tscn`: boot (autoloads, data, ink, save), playthrough (all five consequences,
chapters, endings, save round-trip), farming, hunting, economy (trading + building). Keep them green.
