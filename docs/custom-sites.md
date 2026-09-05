# Custom locations and stories: site packs

Everything that ties Vakuraamat to one place and one story lives in a **site pack**, a directory
under `sites/<id>/`. The engine (scripts, scenes, shaders, models, the terrain pipeline) never
names a site; it reads the active pack through the `Sites` autoload. `sites/palupera/` is the
original slice; `sites/kvissentali/` is a scaffold for a Tartu location.

The active pack is chosen by `--site=<id>` on the command line, else by the last choice in
`user://settings.cfg`, else `palupera`. The main menu shows a **Location** button when more than
one pack exists. Saves record their site and switch to it on Continue.

## A pack, file by file

| File | What it is | Made by |
|---|---|---|
| `site.json` | manifest: terrain tile, centre, latitude, era ground maps, start, journal locations, objectives, register nudge, ending rules, codex keys | `tools/new_site.py`, then edited |
| `layout.json` | named positions in tile metres (x east, z south), `exclusions` (x, z, r) kept free of scattered vegetation, `pads` (x, z, w, d) levelled under buildings at import | hand, via the debug map (M) |
| `scenes.json` | the era layers: what stands where in each era, which flags show or hide it | hand |
| `scenes/<era>.tscn` | generated era scenes (do not hand-edit) | `make scenes` |
| `data/eras/*.tres` | one `EraDefinition` per era: id, year, order, scene, story, ground texture, currency, starting money | scaffold; `make era-maps` relinks textures |
| `data/consequence_points/*.tres` | one flag each, its trigger era and affected eras, journal text keys | hand |
| `data/items/*.tres` | `ItemBase` (era-local) and `ArtifactItem` (crosses eras; one consequence, one delivery target) | hand / copied from the template |
| `data/manors`, `data/structures`, `data/trade_goods`, `data/crops`, `data/animals` | building, trading, farming, hunting content, all keyed by era id | copied from the template with eras remapped, then edited |
| `narrative/<era>.ink` (+ `.ink.json`) | one ink story per era; NPC knots; Estonian lines with `# en:` tags, choices as `[et %% en]` | hand; `make ink` |
| `strings.csv` | the pack's translation keys (`keys,et,en`); core UI keys stay in `assets/i18n/strings.csv` | hand |
| `buildings_2026.json`, `water_2026.json` | real building massing and still water derived from the laser data | `make features`, then pruned by hand |

The terrain itself lives in `assets/terrain/<tile>/` (heightmap, canopy, orthophoto, era maps
committed; Terrain3D region data generated) and is referenced by `terrain.tile`, so two stories
can share one ground.

## Making a new pack

```sh
make site SITE=kvissentali NAME="Kvissentali" CENTER="657600 6477150"   # ERAS=1798,1938,2026
make tile SITE=kvissentali      # Maa-amet DTM, nDSM, orthophoto, historical maps; Terrain3D import;
                                # vegetation; buildings + water; scenes; validation  (~10 min, network)
godot --path . -- --site=kvissentali
```

`make site` writes a complete, boring, working story: a register near the spawn, one NPC per era,
one artifact found in the newest era and handed back in the oldest, whose delivery puts a stone by
the landmark in every later era, a trade post per era, farm plots and a home farm in the middle
era, hunting in the older eras, the real village massing in the newest. It copies the template
pack's crops, animals, structures, trade goods and the items they need, remapping era ids by
order, so farming, hunting, trading and building work on day one. Replace the story, keep the
pattern.

Choosing the centre: open the Maa-amet map (kaart.maaamet.ee), read the L-EST97 easting and
northing of the point you want in the middle, or geocode an address with
`https://inaadress.maaamet.ee/inaadress/gazetteer?address=<name>`. The 1:10 000 sheet grid
does not matter; sheets are mosaicked. The historical WMS (`kaart.maaamet.ee/wms/ajalooline`)
covers all of Estonia; the layers used per era year are chosen in `tools/new_site.py`
(`era_map_for`): one-verst map before 1923, the 1930-44 cadastral map to 1944, Soviet 1:10 000
to 1990, the 1994-98 base map to 2004, the orthophoto after that.

## Iterating

| Change | Then run |
|---|---|
| positions in `layout.json` | `make scenes`; pads and exclusions also need `make tile` (or `make scatter`) |
| `scenes.json` | `make scenes` |
| `.ink` | `make ink` |
| `strings.csv`, any `.tres` | `make import` (Godot re-imports the CSV into `.translation` files) |
| anything | `make validate` (pure python) and `make test` (Godot; the site test boots every pack) |

`make validate` catches unknown era, item, consequence and knot references, missing translation
keys, ink files without the EXTERNAL block, objectives whose target node exists in no scene, and
a start era without a register.

## site.json reference

```jsonc
{
  "id": "palupera",                       // must equal the directory name
  "name_key": "SITE_PALUPERA",            // menu label
  "subtitle_key": "MENU_SUBTITLE",        // menu subtitle
  "terrain": {
    "tile": "palupera",                   // assets/terrain/<tile>/
    "center": [637548, 6444029],          // EPSG:3301 easting, northing
    "size": 1024,                         // metres; one Terrain3D region (<= 2048)
    "latitude": 58.1158, "longitude": 26.3341, "utc_offset": 3.0, "date": [2026, 9, 3],   // Sky3D sun
    "era_maps": {"era_1938": {"layer": "kk1940", "file": "era_1938_cadastral.png"}}        // WMS ground maps
  },
  "start": {"era": "era_2026", "spawn": [508, 513], "yaw_deg": 180},
  "water": "water_2026.json", "buildings": "buildings_2026.json",
  "locations": {"LOC_OAK": "oak"},        // journal map markers: translation key -> layout key
  "objectives": [                         // first matching rule wins; HUD text + optional marker
    {"when": "register_locked", "key": "OBJ_FIND_REGISTER", "target": "RegisterBook", "lift": 1.2},
    {"chapter": 1, "key": "OBJ_VISIT_ERAS"},
    {"chapter": 3, "not_flag": "epilogue", "key": "OBJ_SIT", "target": "Leida", "era": "era_2026", "lift": 2.2}
  ],
  "register_nudge": {"chapter": 1, "era": "era_1798"},   // arrow in the register during that chapter
  "ending": {
    "trigger_flag": "epilogue",           // set by ink when the story ends; opens the ending panel
    "counted_flags": ["family_recorded_1798", "north_field_ploughed", "well_kept_open", "cellar_opened"],
    "bonus_flag": "letter_delivered",
    "tiers": [{"min_kept": 4, "bonus": true, "key": "ENDING_ORCHARD"}, {"min_kept": 2, "key": "ENDING_FURROWS"}, {"key": "ENDING_FOREST"}],
    "partial_key": "ENDING_BOX_PARTIAL"   // shown when the bonus is done but not everything was kept
  },
  "codex": ["CODEX_REAL", "CODEX_INVENTED"],   // journal tab: <key> and <key>_TITLE
  "debug": {"build_node": "Manor_kaseoja_farm"}
}
```

Chapter flow is engine-side and the same for every pack: the prologue commits when the register
is first opened; chapter 1 ends when every era has been visited; later chapters end when ink calls
`end_chapter()`; the ending panel opens when `ending.trigger_flag` is set.

## scenes.json reference

Positions are tile metres. Numbers may be expression strings using layout keys and loop
variables (`"manor[0] - manor_size[0] / 2"`, `"i * 4.5"`); text may interpolate fragment
parameters (`"EX_OAK_{year}"`). `at` is a layout key, `[x, z]` or
`{"ref": "farm", "offset": [dx, dz]}`; inside a group it is relative to the group.

| type | fields | notes |
|---|---|---|
| `group` | name, at, flag, visible_when, min_chapter, lift, children | a `Conditional` node: shown when the flag matches (and the chapter is reached) |
| `use` | fragment, with | expands a named fragment with parameters |
| `repeat` | count, var, children | loop; `{i}` in names, `i` in expressions |
| `instance` | name, scene, at, scale, yaw / yaw_deg | any PackedScene or glb |
| `building` | name, model, yaw_deg, footprint [w, h, d], scale, skirt | collider and foundation skirt; tags the group for lowest-corner snapping |
| `box`, `torus` | size, y, color, at, rot / inner, outer, color, y | quick CSG props; colours by name from `colors` |
| `examine` | name, key, loc, label, at | hover text, marks the journal location |
| `story_point` | name, knot, speaker, text, loc, label, radius | a place that starts an ink knot |
| `npc` | name, id, knot, label, color, at, height, yaw, pose | `id` is the artifact delivery target; pose stand / arms_folded / holding |
| `pickup` | name, item, examine, at | era-local or artifact item lying in the world |
| `register` | name, at, text | the vakuraamat; exactly one, in the start era |
| `tree`, `scatter` | at, scale, yaw, scene / prefix, count, radius, scale [min, max], seed | single tree, or a random disc of them |
| `farm_plots` | at, count, seeds | plots plus a seed bin |
| `trade_post` | at, key, color | one per era; goods from `data/trade_goods` |
| `manor_site` | id, at | build marker for a `ManorDefinition` |
| `hunting` | max_animals | spawner using the land-cover map |
| `village` | source | massing boxes from the buildings json |

Fragments are the reusable blocks: `"fragments": {"oak": {"params": ["scale", "year"], "nodes": [...]}}`
and `{"type": "use", "fragment": "oak", "with": {"scale": 0.75, "year": 1938}}`.

## Rules that still hold

Cross-era effects are flags set by consequence points only; farming, hunting, trading and
building never read them; only artifacts cross eras. A pack that wants a new visible consequence
adds a `ConsequencePoint`, an ink line that calls `trigger()` or delivers an artifact with
`give_item()`, and `group` nodes with that flag in the affected eras. Nothing else changes.

Every data source a pack uses gets a row in `THIRD_PARTY.md`; the Maa-amet attribution is
shown in the menu and must stay.
