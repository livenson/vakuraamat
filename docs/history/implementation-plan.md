# Vakuraamat — implementation plan

**Revision note (2026-09-05):** place and story are now *site packs* under `sites/<id>/` (manifest, layout, declarative era scenes, data, ink, strings), chosen at runtime by the `Sites` autoload; the engine no longer names Palupera. `make site` scaffolds a pack for any EPSG:3301 centre and `make tile` fetches DTM, nDSM, orthophoto and the historical WMS maps, derives buildings and water, and generates the scenes. A Kvissentali (Tartu) scaffold exists. See `docs/custom-sites.md`. Earlier: **Revision note (2026-09-04):** Phases 0–5 are built and pass their headless tests (see `README.md`); the remaining work is content depth, playtesting the legibility criterion, and the Phase 6+ items. Earlier note (2026-09-03): Phase 0 is built. This revision aligns the plan with `first-iteration-design.md`: eras are fixed as 1798 / 1938 / 2026, the site is the Palupera area, one heightmap is shared across eras, the terrain pipeline is GDAL-scripted rather than QGIS, and an ambient day/night cycle (Sky3D) is part of the base scene.

**Purpose of this document:** a phased technical build plan for handing to Claude Code (or any coding agent/collaborator) to scaffold and implement the game incrementally. It captures the design decisions already made, defines a concrete architecture, and specifies what "stub" means at each phase so later phases extend rather than rewrite earlier work.

**Engine:** Godot 4.7 (GDScript primary, C# optional later)
**Platform:** macOS development, PC (Steam) target
**Core creative pillars:** real Estonian geodata (Maa-amet), time travel across historical eras at one real location, scripted butterfly-effect consequences, farming, hunting, era-local trading, base/manor expansion over time.

---

## 1. Guiding constraints (do not violate without a deliberate decision)

These came out of prior design research and exist specifically to prevent the project from becoming unshippable. Claude Code (or whoever is implementing) should treat these as hard architectural rules, not suggestions:

1. **No live simulation of causality.** All cross-era consequences are represented as discrete flags in a single `TimelineState` resource, read by each era's scene at load time. Never build a system that recalculates world state procedurally from a chain of player actions.
2. **No open cross-era item economy.** Only a small, explicitly tagged set of "artifact" items may cross eras, and each has exactly one scripted delivery-and-flip effect. Ordinary inventory (farming produce, hunting yields, trade goods, currency) is era-local and never persists across eras.
3. **Trading is era-local.** Each trade post exists inside one specific era and trades in that era's goods and currency only. The *narrative* can reference trade across eras (e.g. a ledger recording who traded with whom, generations apart) without the *mechanic* moving goods across eras.
4. **Cap the state space per phase.** Each phase below states its own numeric caps (number of eras, consequence points, artifacts, etc.). Do not silently exceed a cap — if a cap turns out too small during implementation, that's a decision to surface to the user, not to quietly work around.
5. **Every phase must produce something playable.** No phase should end with only backend systems and no way to see/feel the result in-game.
6. **Stub means "real interface, fake content," not "TODO comment."** A stubbed system must have its final data structures, save/load hooks, and UI entry points in place from the start — only the *content* and *depth* of simulation are deferred. This is what lets later phases plug in without refactoring earlier ones.

---

## 2. Target architecture

### 2.1 High-level project structure

```
vakuraamat/
├── project.godot
├── addons/
│   ├── terrain_3d/                 # TokisanGames Terrain3D 1.0.2 (GDExtension, vendored)
│   └── sky_3d/                     # TokisanGames Sky3D 2.1 (GDScript, vendored): ambient day/night
├── assets/
│   ├── terrain/                    # <site>/: ONE shared heightmap + per-era textures, from data pipeline
│   ├── models/                     # Blender-authored props, exported glTF/FBX
│   ├── narrative/                  # .ink files (compiled to .json via inklecate)
│   └── ui/
├── data/
│   ├── eras.tres                   # EraDefinition resources
│   ├── consequence_points.tres     # ConsequencePoint resource list
│   ├── artifacts.tres              # ArtifactItem resource list
│   └── (later) crops.tres, animals.tres, trade_goods.tres, manors.tres
├── scenes/
│   ├── eras/
│   │   ├── era_1798/               # the manor (Livonian serfdom)
│   │   ├── era_1938/               # the first owners (post-land-reform republic)
│   │   └── era_2026/               # the present
│   ├── systems/                    # autoload singletons live here conceptually
│   └── ui/
├── scripts/
│   ├── autoload/
│   │   ├── timeline_state.gd       # the ONE global state singleton
│   │   ├── save_manager.gd
│   │   └── narrative_runner.gd     # wraps ink runtime
│   ├── era/
│   │   ├── era_definition.gd       # Resource
│   │   ├── era_controller.gd       # per-scene node, reads TimelineState on _ready
│   ├── items/
│   │   ├── item_base.gd
│   │   ├── artifact_item.gd        # extends item_base, cross-era-capable
│   │   └── inventory.gd
│   ├── consequence/
│   │   └── consequence_point.gd    # Resource: id, era_from, era_to, flag_name, description
│   ├── farming/                    # phase 2 — stub scaffolding created in phase 1 already
│   ├── hunting/                    # phase 3
│   ├── trading/                    # phase 4
│   └── base_building/              # phase 5
└── tests/
```

### 2.2 Core data model (build this in phase 1, it does not change shape later)

**`TimelineState`** (autoload singleton, `res://scripts/autoload/timeline_state.gd`)
```gdscript
extends Node
# The single source of truth for everything that has ever changed across eras.
# Flat dictionary. Never nested. Never simulated. Read-only from era scenes
# except through explicit set_flag() calls triggered by consequence points.

var flags: Dictionary = {}   # String -> Variant (bool/int/String)

func get_flag(flag_name: String, default = false):
    return flags.get(flag_name, default)

func set_flag(flag_name: String, value) -> void:
    flags[flag_name] = value
    SaveManager.mark_dirty()
    EventBus.flag_changed.emit(flag_name, value)

func has_flag(flag_name: String) -> bool:
    return flags.has(flag_name)
```

**`EraDefinition`** (Resource, one .tres per era)
```gdscript
extends Resource
class_name EraDefinition

@export var id: String                # e.g. "era_1798"
@export var display_name: String
@export var year_label: String        # e.g. "1798"
@export var scene_path: String        # path to the era's main scene
@export var terrain_texture: Texture2D    # era ground texture (orthophoto / georeferenced historical map)
@export var default_time_of_day: float = 10.0   # hours; used on FIRST entry only, never forced afterwards
@export var order: int                # for UI/journal chronological display
# No per-era heightmap: the landform is shared across eras (design doc 4.4, data doc 3.5).
# The site's single heightmap lives in assets/terrain/<site>/ and is loaded by the shared terrain scene.
```

**`ConsequencePoint`** (Resource, one .tres per scripted consequence)
```gdscript
extends Resource
class_name ConsequencePoint

@export var id: String
@export var flag_name: String              # matches TimelineState flag key
@export var trigger_era: String            # which era's action sets the flag
@export var affected_era: String           # which era's scene reads the flag
@export var trigger_description: String    # journal text: what caused it
@export var effect_description: String     # journal text: what changed
@export var journal_icon: Texture2D
```

**`ArtifactItem`** (extends `ItemBase`)
```gdscript
extends ItemBase
class_name ArtifactItem

@export var can_cross_eras: bool = true
@export var linked_consequence_point_id: String   # what it triggers on delivery
@export var valid_delivery_target: String         # NPC id or location id
```

**`Journal`** (autoload or UI singleton) — subscribes to `EventBus.flag_changed`, appends a human-readable log entry using `ConsequencePoint.effect_description`. This is the "de-friction / legibility" system flagged as make-or-break in prior research — build it in phase 1, not later.

### 2.3 Narrative layer

Use **ink** (inkle's scripting language) compiled via `inklecate`, run through a GDScript ink runtime wrapper (`InkGD` or similar). Ink gives delayed-branching/state-flag narrative for free and is the same tool used in Heaven's Wake-style time/history narrative games. Dialogue and journal text live in `.ink` files, not hardcoded in GDScript.

### 2.4 Data pipeline (offline, run once per site, not runtime code)

As built in Phase 0: `tools/pipeline/fetch_tile.py` (Maa-amet geoportal download + GDAL clip → raw float32 heightmap, WMS orthophoto, `terrain_meta.json`) → `tools/godot/import_terrain.gd` (headless Terrain3D region import). No QGIS in the loop; GDAL is scripted and repeatable. The heightmap is raw float32, not 16-bit PNG (Godot's PNG loader truncates to 8-bit). Historical era textures (Mellin scan, 1930–44 cadastral WMS layer) are georeferenced/clipped to the same `terrain_meta.json` extent and dropped in as additional per-era textures. Blender is used for hero props only, driven by headless scripts under `tools/blender/`.

### 2.5 Shared base scene

Every era scene instances one shared `TerrainBase` scene (Terrain3D + orthophoto/era-texture drape + Sky3D) and adds its own props, NPCs and texture. Sky3D's `TimeOfDay` is the game's single clock: ambient in Phase 1 (design doc 2.7), and the tick source for Phase 2 farming growth. Time of day is preserved across era switches.

---

## 3. Phase plan

Each phase lists: goal, what ships playable, what's stubbed vs. fully built, explicit non-goals, caps, and acceptance criteria. Build strictly in order — later phases assume earlier ones are complete and stable.

### Phase 0 — Technical spike (no game yet)
**Goal:** prove the terrain pipeline works before writing any game code.
**Ships:** a single walkable 1km² real-Estonian terrain tile in Godot with a first-person controller, using one Maa-amet DTM + orthophoto tile via Terrain3D. *(Built 2026-09-03 on a Palmse placeholder tile; to be re-fetched for the chosen Palupera clip — one pipeline run.)*
**Build:** QGIS export script/workflow documented; Terrain3D installed and configured (including the macOS Gatekeeper quarantine fix); one Blender hero prop imported and placed.
**Stub:** everything else. No inventory, no NPCs, no UI beyond an FPS counter.
**Non-goals:** do not build TimelineState yet — this phase is pure tech validation.
**Acceptance criteria:**
- [ ] Real DTM tile renders as walkable terrain at acceptable frame rate
- [ ] Orthophoto correctly draped as terrain texture, aligned
- [ ] One Blender-made prop placed and rendering correctly
- [ ] Documented, repeatable pipeline (script or step-by-step) for producing the next tile

### Phase 1 — Vertical slice: the time-travel core loop
*Status: built 2026-09-04; `tools/godot/playthrough_test.tscn` drives all five consequence points headless. The legibility playtest is still to be run with a real player.*
**Goal:** prove the entire TimelineState/ConsequencePoint/ArtifactItem/Journal architecture end-to-end with real (if minimal) content, per prior design research's recommended starting scope.
**Ships:** 3 eras (1798, 1938, 2026) of one real location (the Palupera clip), 5 consequence points, 4 artifact items, a working journal, basic ink-driven dialogue, era-switching via the register. Content is specified in `first-iteration-design.md`.
**Build:**
- `TimelineState`, `EraDefinition`, `ConsequencePoint`, `ArtifactItem`, `Journal`, `SaveManager`, `EventBus` — all fully implemented, not stubbed (this is the architectural spine everything else plugs into)
- 3 era scenes, each instancing the shared `TerrainBase` (2.5) with the Palupera heightmap and its own era texture + props
- Ink integration with a small branching script per era
- Era-switch UI: the register (vakuraamat) opened from anywhere, 2–3 s page fade, position and time of day preserved (design doc 2.2)
- Inventory UI showing era-local items vs. the 4 tagged artifacts distinctly (gold border, distinct pickup sound — design doc 2.3)
- Chapter commit points and autosave (design doc 2.6)
- Estonian-primary text with English translation from the start (design doc 7; language notes doc)
**Stub:** farming, hunting, trading, base-building — **not present at all yet**, not even stub folders with empty scripts. Building empty stub folders this early adds noise without value; Phase 2 introduces the farming stub properly.
**Caps:** exactly 3 eras, exactly 5 consequence points (CP1–CP5 as designed), exactly 4 artifacts. Do not exceed until Phase 1 ships and is played end-to-end.
**Acceptance criteria:**
- [ ] Player can traverse all 3 eras at the same location
- [ ] All 5 consequence points are deliverable and their effects are visible in a later era AND logged in the journal
- [ ] A playtester who hasn't seen the design doc can correctly predict at least 4 of 5 outcomes before triggering them (legibility test from prior research)
- [ ] Save/load preserves TimelineState correctly across a session restart

### Phase 2 — Farming (stub → real)
*Status: built 2026-09-04 (`scripts/farming`, `tools/godot/farming_test.tscn`). Seasons/soil remain deferred.*
**Goal:** add farming as a self-contained system without touching Phase 1's architecture.
**Ships:** plantable plots in the present-day era (or whichever era makes narrative sense), with a small crop set, growth timers, and harvest yielding era-local inventory items.
**Build now (real):**
```gdscript
extends Resource
class_name CropDefinition
@export var id: String
@export var display_name: String
@export var growth_stages: Array[Texture2D]
@export var growth_time_seconds: float
@export var yield_item_id: String
@export var yield_quantity: int
```
`FarmPlot` node: state machine (empty → planted → growing → ready → harvested), ticks growth from Sky3D's `TimeOfDay` (the shared clock from 2.5), spawns yield item(s) into local inventory on harvest.
**Stub now, extend later:** only 2–3 crop types; no soil quality/fertilizer system; no seasons (single fixed "growing works everywhere, always" rule) — these are the *depth* to add in a later pass, not now.
**Non-goals this phase:** crops do not affect TimelineState. Do not let farming output become an artifact item. Farming is purely an era-local activity/economy loop.
**Acceptance criteria:**
- [ ] Player can plant, wait, and harvest at least 2 crop types
- [ ] Harvested items appear correctly in era-local inventory
- [ ] Farming system has zero references to TimelineState, ConsequencePoint, or ArtifactItem in its code (architectural isolation check)

### Phase 3 — Hunting (stub → real)
*Status: built 2026-09-04 (`scripts/hunting`, `tools/godot/hunting_test.tscn`). Spawns read the terrain control map classes.*
**Goal:** add a wildlife/hunting system, isolated the same way.
**Build now (real):**
```gdscript
extends Resource
class_name AnimalDefinition
@export var id: String
@export var display_name: String
@export var model_scene: PackedScene
@export var spawn_biome_tags: Array[String]   # matches terrain tagging from data pipeline
@export var yield_item_id: String
@export var flee_behavior: bool = true
```
Simple spawner reading real forest-cover tags from the Maa-amet data pipeline (CHM/forest layer already identified in earlier geodata research) to bias spawn locations toward actual forested areas. Basic AI: wander, flee on player proximity, simple hit-registration on take-down.
**Stub now:** 2–3 animal types; no ecosystem/population simulation; no seasonal migration.
**Non-goals:** hunting yields do not cross eras or affect TimelineState.
**Acceptance criteria:**
- [ ] At least 2 huntable animal types spawn plausibly in forested real-terrain areas
- [ ] Successful hunt yields an era-local inventory item
- [ ] Hunting system has zero references to TimelineState/ConsequencePoint/ArtifactItem

### Phase 4 — Trading posts (era-local only)
*Status: built 2026-09-04 (`scripts/trading`, `tools/godot/economy_test.tscn`). Fixed prices, one post per era.*
**Goal:** let farming and hunting yields (plus any other era-local goods) be sold/bought at fixed trade-post locations, one per era, without reopening the cross-era economy problem.
**Build now (real):**
```gdscript
extends Resource
class_name TradeGood
@export var item_id: String
@export var base_price: int
@export var era_id: String        # this good only exists/trades in this era

extends Node
class_name TradePost
@export var era_id: String
@export var buys: Array[TradeGood]
@export var sells: Array[TradeGood]
@export var currency_id: String   # each era can have its own currency name/id
```
A trade post is a location + a buy/sell list, scoped to one `era_id`. Currency is also era-scoped (`currency_id`) — an era's coin has no meaning in another era, which is both mechanically clean and thematically resonant (the manor's ledger/vakuraamat can *record*, in narrative text, that "this same trade once happened generations ago," without any mechanical value crossing eras).
**Stub now:** fixed prices, no dynamic economy/supply-demand, one trade post per era to start.
**Non-goals (hard rule, not a stub — this is permanent):** no good, currency, or generic item ever crosses an era boundary through trading. Only tagged `ArtifactItem`s cross eras, and only via the Phase 1 delivery-and-flip mechanic, never via a trade post.
**Acceptance criteria:**
- [ ] Player can sell farming/hunting yield at their era's trade post for that era's currency
- [ ] Player can buy era-appropriate goods back
- [ ] Confirm by code review: no trade-post code path can move a non-artifact item or currency across `era_id` values

### Phase 5 — Base building / manor expansion
*Status: built 2026-09-04 (`scripts/base_building`, `tools/godot/economy_test.tscn`). Both manors are on the same tile; a second tile with travel is Phase 6+.*
**Goal:** let the player grow influence from one base location outward to other real, cadastrally-mapped manor locations.
**Design pattern (from prior research):** favor a **hub-plus-outposts** model (closer to Anno/Banished-style expansion) over a single-deep-city model (Frostpunk) — this maps naturally onto the real cadastral parcel data already in the pipeline, where each "manor" is a real mapped location the player travels to and gradually develops.
**Build now (real):**
```gdscript
extends Resource
class_name ManorDefinition
@export var id: String
@export var display_name: String
@export var era_id: String                 # which era this manor exists in (or list, if same manor across eras)
@export var cadastral_parcel_id: String     # ties to real Maa-amet cadastral data
@export var location_terrain_tile: String
@export var unlock_condition_flag: String   # optional TimelineState flag gating access

extends Node
class_name ManorController
@export var manor: ManorDefinition
var development_level: int = 0
var buildings_built: Array[String] = []
```
**Stub now:** 2 manors total (the home base + one expansion target); a small fixed set of buildable structures per manor; no cross-manor logistics/supply chains yet.
**Non-goals this phase:** manor development does not itself set TimelineState flags automatically — if a manor's growth should have a butterfly-effect consequence, that should be an explicit new `ConsequencePoint`, authored deliberately, not an automatic side effect of a farming/trading number crossing a threshold. This keeps the state space enumerable per the phase-1 guiding constraint.
**Acceptance criteria:**
- [ ] Player can travel between home base and at least one additional real-mapped manor location
- [ ] At least one buildable structure per manor, visibly changing the location
- [ ] Manor expansion is playable and legible without needing a spreadsheet-style management screen

### Phase 6+ (explicitly deferred, not specified in detail here)
- Additional eras beyond the original 3 (only after Phase 1's legibility test passes cleanly)
- Deeper farming (seasons, soil, fertilizer)
- Deeper hunting (ecosystem simulation)
- Additional manors and inter-manor logistics
- Any consideration of a genuinely cross-era economy — **do not build this without revisiting the state-explosion research first**

---

## 4. Open questions

**Resolved by the design doc:** era switching (the register, from anywhere); the eras (1798 / 1938 / 2026); the home base (fictional Tõrvamäe manor on real Palupera ground).

**Still open:**
- **Exact 1 km² Palupera clip.** Recommended: the square centred on the manor/village (NW corner EPSG:3301 637036 / 6444541; 22 m relief; the 1930–44 cadastral sheet for it is legible and shows the settler farms by name).
- **Vertical exaggeration.** Palupera has enough relief that 1.0 may be right; decide after walking the clip.
- **Currency naming per era** (Phase 4, cosmetic).
- **Name checks** before content is written: Tõrvamäe/Törwenhof against the manor registries; Kaseoja (a real, rare surname) against the Palupera population; the Birkenbach→Kaseoja pair against the Onomastika database.

## 5. Sequencing from here

Phase 0 is built. Before Phase 1 architecture starts:
1. Choose the Palupera clip and re-run the two pipeline commands (README) so the spike walks the real site.
2. Check off Phase 0's acceptance criteria in section 3 by walking the clip.
3. Then begin Phase 1 with the data model in section 2.2 and the content in the design doc — nothing from Phases 2–5 yet.
