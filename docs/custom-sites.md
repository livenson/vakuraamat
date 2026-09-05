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
| `site.json` | manifest: terrain tile, centre, latitude, start position, named locations, codex keys | `tools/new_site.py`, then edited |
| `layout.json` | named positions in tile metres (x east, z south), `exclusions` (x, z, r) kept free of scattered vegetation, `pads` (x, z, w, d) levelled under buildings at import | hand, via the debug map (M) |
| `scenes.json` | the layer: landmarks, props, the real footprints, roads, parcels, traffic, the bicycle | hand |
| `scenes/era_2026.tscn` | the generated layer scene (do not hand-edit) | `make scenes` |
| `data/eras/era_2026.tres` | the one `EraDefinition`: id, year, scene, ground texture (the orthophoto) | scaffold |
| `data/structures/*.tres` | what can be built on an owned plot: cost in euros, rent bonus, allowed purposes, prerequisite | copied from the template, then edited |
| `parcels.json` | cadastral units with 2022 land values, purposes, ownership form, polygons | `make parcels` |
| `buildings.json` | real buildings: footprints, register attributes, addresses, cadastral links, LOD2 roofs | `make buildings` |
| `tenants.json` | Business Register companies matched to the plots and buildings | `make tenants` |
| `market.json` | median land value per m² by purpose | `make market` |
| `roads.json`, `buildings_2026.json`, `water_2026.json` | ETAK roads, laser building massing, still water | `make roads`, `make features` |
| `strings.csv` | the pack's translation keys (`keys,et,en`); core UI keys stay in `assets/i18n/strings.csv` | hand |

The terrain itself lives in `assets/terrain/<tile>/` (heightmap, canopy, orthophoto committed;
Terrain3D region data generated) and is referenced by `terrain.tile`. Packs made by the historical
game (they carry a `story`, `objectives` or `ending` in the manifest) are skipped by `Sites.scan`.

## Making a new pack

```sh
make site SITE=kvissentali NAME="Kvissentali" CENTER="657600 6477150"
make tile SITE=kvissentali      # Maa-amet DTM, nDSM, orthophoto; Terrain3D import; vegetation; buildings,
                                # parcels with land values, tenants, market, roads; scenes; validation  (~10 min, network)
godot --path . -- --site=kvissentali
make town SITE=kvissentali      # optional: open it as a shared town on the local SpacetimeDB
```

`make site` writes a working town pack: a landmark near the spawn, the real footprints, roads,
parcels, traffic and a bicycle, the template's structures, and the codex strings. Everything the
economy needs comes from `make tile`.

Choosing the centre: open the Maa-amet map (kaart.maaamet.ee), read the L-EST97 easting and
northing of the point you want in the middle, or geocode an address with
`https://inaadress.maaamet.ee/inaadress/gazetteer?address=<name>`. The 1:10 000 sheet grid
does not matter; sheets are mosaicked.

## Any point in Estonia from inside the game

The **New location...** button in the main menu takes an address, a place name, L-EST97
`"E N"` or `"lat, lon"` (or *Use my location*, a city-level IP lookup) and asks the **tile service**
for a pack:

```sh
make tile-service          # python3 tools/tile_service.py, loopback port 8765; needs GDAL, numpy, node (tools/play.sh starts it for you)
```

The service runs the same steps as `make site` + `make tile` in a workspace under `data_raw/service/`
(downloads shared with `data_raw/`), places the story skeleton on **anchors** found in the data
(register on open ground near the centre, landmark at the largest building or tallest trees, farm on
the widest open ground, trade post by a road, field on crops), and returns a zip. The game installs
it under `user://sites/<id>/` and `user://tiles/<id>/`; the world builds the Terrain3D data on the
first visit (about 15 s, progress on the fade) and saves it next to the tile. Runtime packs are
ordinary packs: `.tres` files load from `user://`, `strings.csv` is read directly, era textures are
image paths. The service URL can be changed in `user://settings.cfg` under `[service] url`.

Scripted equivalent: `curl -X POST :8765/tile -d '{"name":"Aakre","x":629807,"y":6441719}'`, poll
`/status?id=aakre`, `/download?id=aakre`, then
`godot --headless --path . res://tools/godot/install_pack.tscn -- --zip=aakre.zip --id=aakre`.

## The Locations panel

*Locations...* in the main menu (and in the pause menu, which saves first) lists the packs you have
(shipped and installed, with Play / Continue), the packs already generated on the tile service
(Install and play), suggested Estonian places to generate with one click
(`assets/data/suggested_places.json`), a place search (address, place name, coordinates, or your IP
location), and the friends section.

## Towns: the shared ledger

A town is one SpacetimeDB database holding a tile's ledger: parcels with land values and prices,
owners, tenants, bids, obligations, improvements, presence and the news feed. Nothing else is
shared; every client regenerates the tile from Maa-amet data. The module lives in
`server/vakuraamat/` (Rust, see its README); `make module` builds it, `make server` runs a local
SpacetimeDB on 127.0.0.1:3300, and `make town SITE=<id>` publishes the module under the pack's town
name and seeds it from `parcels.json`, `tenants.json`, the pack's structures and
`assets/data/economy.json` through `tools/town_admin.py`. The town name (`tools/town_admin.py name`)
encodes the tile centre and a hash of the pack's parcel and tenant files, so a regenerated pack is a
new town and a client whose pack differs is refused. `DEBUG=1 make town` allows `grant_cash` for
local play. The Godot client is the vendored `addons/SpacetimeDB` SDK with bindings generated into
`spacetime_bindings/` (`godot --headless --path . --script res://addons/SpacetimeDB/cli.gd` after
publishing the module as `vakuraamat`; commit the result).

In the game, the `Ledger` autoload probes the server named in `user://settings.cfg` (`[town] url`,
default `http://127.0.0.1:3300`; set it in the Locations panel's Town section or paste a friend's)
for the pack's town when the world loads. If the town answers, the game joins it with the identity
token kept in `[town] token`, subscribes to every table and plays online: purchases, bids, rents and
months come from the server, other players walk around as blue figures with name plates, and the HUD
says so. If it does not answer, or `[town] offline` is set, the same rules run in the offline book,
which is what the save file holds. Only `scripts/ledger/town_ledger.gd` touches the SDK; `ledger_test`
greps the rest. `town_test` starts a throwaway server on port 3777, publishes the prebuilt module,
seeds Kvissentali and checks that two clients see each other's purchases, bids and presence; it
reports a skipped pass when the CLI or the module build is missing.

### Playing the ledger

In the world, **V** opens the vakuraamat: the plots nearest to you with land value, price, owner and
monthly yield (filters all / mine / for sale), one plot's card with Buy, Bid, List for sale, Build,
Collect arrears, Settle arrears and Accept offer, your portfolio (cash, income, obligations to pay,
favours, heat, reputation, donations), offers in and out, and the town's month, price index and
connection. **B** opens the card of the plot you stand on. **N** is the town feed. Gold outlines on
the ground are your plots, amber ones carry your open bid, blue ones nearby are for sale. Without a
town server the same rules run in your own offline book (`LocalLedger`); a month passes every ten
real minutes and pays rents, raises land tax and lets the Kask, Tamm and Lepik families bid on
your plots. `--open=ledger` and `--open=news` work with `--screenshot`.

### Hosting a town for friends

The local server answers only on this machine. For a town others can join, publish the same module
to SpacetimeDB's Maincloud (free tier) and point the game at it:

```sh
spacetime login                                     # once; opens the browser
make town SITE=kvissentali SERVER=maincloud         # publish + seed the town there
```

Then set the server to `https://maincloud.spacetimedb.com` in the Locations panel's Town section and
share the town address the panel shows; a friend pastes the server into their own Town section,
generates the same tile (same centre, same pipeline) and joins. A pack whose `parcels.json` or
`tenants.json` differs gets a `LEDGER_HASH_MISMATCH`; re-run `make parcels` and `make tenants` on both
sides, or share the pack. Keep the news flowing with a scheduled `make news SITE=<id> SERVER=maincloud`
(cron `*/15 * * * *`, or a launchd `StartInterval` of 900 with `SPACETIME_TOKEN` in its environment).
SpacetimeDB's licence allows one production instance per project; Maincloud counts as that.

## The book: how the menus look

Every menu and panel is a page of the register: `scripts/ui/book_theme.gd` builds one Theme (aged
paper, iron-gall ink, the cadastre's blue for anything you can act on, a rubric red only as the
margin rule and for money owed; EB Garamond for titles and prose, IBM Plex Sans with tabular
numerals for buttons, tables and figures) and every top-level Control sets it. Use the type
variations rather than font overrides: `TitleLabel`, `HeadLabel`, `SubheadLabel`, `ProseLabel`,
`DetailLabel`, `ColumnLabel` for text, `PrimaryButton`, `TextButton`, `RowButton` for buttons. Money
goes through `BookTheme.money()` (thousands grouped), dates through `Ledger.date_for()`. The front
page's plate (`scripts/ui/map_plate.gd`) draws the pack's cadastral units over its orthophoto and
fills the saved book's plots; `tools/godot/menu_shot.tscn` screenshots the menu (`--locations` for
the second page).

## Real buildings: ETAK footprints, the Building Register, LOD2 roofs

`make buildings SITE=<id>` (part of `make tile`, and of every tile-service job) writes
`sites/<id>/buildings.json`:

- **ETAK** (the topographic database, WFS) gives every building polygon in the tile and its type;
- the **Building Register (EHR)** adds, per building code, the first year of use, floors, footprint
  area, volume, purpose and status;
- **Maa-amet Geo3D LOD2** adds the actual roof geometry (FileGDB per municipality, read with GDAL;
  the municipality comes from the address gazetteer);
- the tile's **nDSM** gives a measured height where the model is missing.

The `footprints` node in `scenes.json` (`{"type": "footprints", "source": "buildings.json", "year":
1938}`) places one `FootprintBuilding` per building whose first year of use is not later than the
era's year (undated buildings only where `include_undated` is set, normally the newest era), so the
1938 layer of a generated pack shows only the houses that stood in 1938. The node builds the LOD2
mesh at runtime (walls and roof as two materials, a foundation skirt, a trimesh collider) or, without
a model, extrudes the footprint to its measured height. Palupera uses real footprints in 2026 and its
hand-placed manor, school and farm models in the older eras; generated packs use footprints in every
era. `buildings_2026.json` (laser massing boxes, `village` node) remains as the fallback when the
register is unreachable.

The register's technical indicators shape each building: facade material sets the wall colour
(plaster, brick, wood siding, fibre-cement, concrete...), roof covering the roof colour (tile, sheet
metal, eternit, bitumen), heat source and fuel add a chimney, solar electricity adds panels (from 2005
on), an own dug well puts a stone ring beside the house, and monuments or manor main buildings are
preferred as the story's landmark anchor. All of it is in `buildings.json` under `materials`,
`chimney`, `solar`, `well`, `monument`, so a story block can also read it (a house with its own
well, a wooden house from 1930, a listed building). Buildings inside the layout's exclusion circles
are skipped so hand-placed models keep their spot.

### Inside the buildings

Every real building that is not an outbuilding gets a door on the wall the exterior draws it on.
E at the door steps in: the first visit generates the interior from the footprint (a floor per
storey on the register's floor count, inner walls with window openings on the exterior's rhythm and a
gap at the door, a ceiling, a ramp between storeys with an open landing), partitions it into rooms (a
deterministic split of the floor plan by use: living room, kitchen and bedrooms in a dwelling, a reception
and offices, a salesroom with a back room; every partition wall has a doorway with a lintel, every room its
lamp, the ramp keeps to the largest room and no cut lands next to the entrance) and furnishes each room by
its role: shop counters and shelves where a company is registered, desks for offices, a bed, table
and sofa in dwellings, benches and cabinets in workshops. Pieces are Kenney Furniture Kit models
(CC0, `assets/vendor/kenney_furniture_kit`). While inside, the exterior mesh and its collider hide so
the openings look out at the real street; E at the door or simply walking out through it restores
the exterior. `--enter="<address part>"` (or `<address part>@<degrees>` to turn after stepping in) starts a
screenshot run inside a building; the door's hover text shows the register's use, year and storeys.
Doors, tenant name plates and interiors also attach to streamed neighbour tiles (their tenants come
from that pack's `tenants.json` through `Tenants.of`); parcel outlines stay on the origin tile, whose
ledger is the one town.

## Cadastral units, roads and what stands on a plot

`make parcels SITE=<id>` fetches the cadastral units of the tile (Maa-amet cadastre WFS: number,
address, registered purposes, area, ownership, land-registry number, polygon) into
`sites/<id>/parcels.json`; `make roads SITE=<id>` fetches ETAK roads (streets, other roads,
pedestrian and cycle paths, trails; width, surface, name) into `roads.json`. Both run in `make tile`
and the tile service.

**What is generated for each plot is decided by `assets/data/parcel_rules.json`** (a pack can
override it with `sites/<id>/parcel_rules.json`): the first rule matching the unit's purpose, size,
ownership and the era year names a kit, built by `scripts/world/parcel_kit.gd`: `playground` (swing
frame, slide, sandpit, bench) on small municipal public land, `park` (benches) on larger public land,
`hedge` around residential plots, `fence` around industrial ones, `solar` (rows of tilted panel
tables where the orthophoto shows regular 3-20 m rows on a large industrial unit, rule
`needs_rows`; row spacing and direction come from a 2D FFT of the photo inside the unit), or
nothing. The `parcels` and
`roads` nodes in `scenes.json` place them (generated packs: newest era; Palupera: 2026). Roads are
ribbons on the terrain (`scripts/world/road_network.gd`): asphalt with kerbs for streets, light paving
for footpaths, gravel for other roads and trails.

**K in the game** shows the codes for where you stand and what you look at: the cadastral unit
(number, address, purpose, area, ownership) with its X-GIS link, the building's ETAK id and Building
Register link, the nearest road (name, type, width, surface), the target node path, and draws the
unit's boundary on the ground; the links are copied to the clipboard. F8 reports carry the same
`parcel`, `road` and `links` fields.

### Land values and the market snapshot

Every unit in `parcels.json` also carries `land_value`, the taxation value in euros from Maa-amet's 2022
regular land valuation (`maks_hind` in the same WFS response), `land_value_per_m2`, the EHAK settlement
code (`ehak`), `settlement`, `county` and `ads_oid`. The file's `summary` block aggregates the codes,
names and the valued total for the tools that key on them. `make market` (also part of `make tile`)
derives `market.json`: median euros per m² per intended purpose, quartiles and counts, plus an `all`
row. These are taxation values, not sale prices; if you export a table from Maa-amet's transaction
statistics environment (https://www.maaruum.ee/kinnisvara/htraru/, XLSX only), `make market
XLSX=<file>` joins it as `transactions`, which the game prefers when present. Older packs without
`land_value` still load; re-run `make parcels SITE=<id>` to add it.

### Tenants: real companies on real plots

`make tenants` (also part of `make tile`) reads the e-Business Register's daily basic-data file
(18 MB zip, CC BY 4.0, cached for a week under `data_raw/ariregister/`), keeps the companies whose
settlement code is one of the tile's, and matches each to a parcel or building: first by the ADS
address id that the Building Register records for every building, then by a normalised street and
house number against parcel and building addresses (`Pikk tänav 4`, `Pikk tn 4` and `Pikk tn 4-11`
are one key), then by farm name in villages. The result is `tenants.json`: registry code, name,
legal form, status, first registration date, address, `tunnus`, `building_id`, `match` (`exact`,
`street` for a company on one of the tile's streets whose number is outside it, `none`) and the
register link. Only legal persons are kept; sole proprietors carry a person's name and are skipped
(`--include-fie` overrides). Bankrupt and liquidating companies stay in the file flagged inactive,
so their premises can stand empty in the game. `--stats` prints the match statistics and the
unmatched street numbers, which is the loop for tuning the normaliser. Kvissentali matches about
260 companies, four in five exactly; Palupera about 30.

### News: the town feed

`make news` (or `tools/news_feeder.py --once`) pulls the region's headlines (ERR items tagged Eesti,
Tartu Postimees and Lõuna-Eesti Postimees for Tartu county, ERR alone elsewhere) and Official
Announcements of the planning and auction kinds whose address names the pack's settlement or
municipality, and posts them into the town through the `post_event` reducer with the publisher's
token. Only the headline or a composed notice title, the source, the date and the link are stored;
notice bodies, publishers and addressees never are, and person-directed notice kinds are not fetched
at all. `make news-local` writes the same items to `sites/<id>/news.json` (ignored by git) for offline
play. State lives in `data_raw/news/<town>.json` so reruns only add new items; `--dry-run` prints
them. Feeds and area names come from `parcels.json`'s `summary`; `sites/<id>/news_config.json` can
override `feeds`, `names` and `notice_types`. For a standing feed, a launchd job or cron line running
`make news SITE=<id>` every 15 minutes is enough.

## Traffic and the bicycle

The `traffic` node (`{"type": "traffic", "year": 2026, "density": 1.0, "max_agents": 40}`) builds a
`RoadGraph` from `roads.json` and keeps ambient agents on the roads around the player: walkers on
paths, streets and roads, cyclists, cars (right-hand lanes, pre-1950 black saloons, later vans and
hatchbacks) and horse carts. The mix follows the era year (only walkers and carts before 1900, bikes
and a few cars before 1950) and the clock (peaks at 7–9 and 16–19, few at night). Agents spawn
35–220 m from the player, despawn beyond 320 m, keep a minimum gap to the one ahead and turn around
at dead ends. Cars are Kenney Car Kit models (CC0, `assets/vendor/kenney_car_kit`): sedans,
hatchbacks, SUVs, vans, delivery vans, taxis and trucks after 1950, a near-black sedan before.
The `bicycle` node (`{"type": "bicycle", "name": "Bicycle", "x": .., "z": ..}`) parks
a rideable bike: E mounts it, E again dismounts, riding is about twice walking speed with momentum.
Both need `roads.json`; `tools/new_site.py` adds them to the newest era of a generated pack.

## Real trees

`make real-trees SITE=<id>` (part of `make tile` and the service) fetches Maa-amet's single-tree
models (trunk position, height, crown diameter, conifer or deciduous) for the tile into
`assets/terrain/<tile>/trees.json`. The dataset covers towns flown at low altitude in 2020–2024
(Tartu yes, Palupera no); where it exists the terrain builder places every measured tree with the
matching species and scale instead of the statistical scatter, and keeps the statistical bushes and
grass. Tiles without coverage are unchanged.

## Other countries

Everything the pipeline fetches for a place sits behind one interface, `tools/pipeline/sources.py`:
a metric CRS and coverage box, `dem`, `ortho`, optional `canopy`, `historical`, `buildings`, `trees`,
`geocode`, `reverse`. Estonia is the one implemented adapter (Maa-amet DTM, nDSM, orthophoto and
historical WMS, in-ADS gazetteer, ETAK + Building Register + Geo3D buildings, Geo3D trees).
`fetch_tile.py` refuses points no adapter covers, and `python3 tools/pipeline/sources.py --list`
prints the implemented and planned adapters (Finland, Latvia, the Netherlands, Denmark, Switzerland,
the UK, the US, and a coarse global fallback with what each would use). Adding a country means
writing one adapter class and registering it; the game side (packs, blocks, services) is unchanged.
The Estonian-specific parts that would still need a per-country answer are the historical map layers
per era and the story blocks' cultural texture.

## Endless map: neighbouring tiles

A pack is one 1024 m tile, but the world does not end there. `TileStreamer` (a child of the world)
treats the map as a grid of tiles with the active pack at (0,0). When the player comes within
300 m of a neighbouring tile, its pack is loaded: from `user://sites` if it is installed, else
requested from the tile service (`Locator.fetch_pack`, one job at a time), downloaded and installed
first. Loading means: the Terrain3D region at the grid offset (built from the tile inputs on first
use, about 5 s, and cached as that tile's own `data/terrain3d_00_00.res`, so later visits take well
under a second and the pack also works as an origin), the current era's ambient nodes (Buildings,
Roads, Parcels, Traffic, Village; story nodes of neighbour packs are dropped) under an offset root
that carries the pack id, and the ponds. Era switches swap the neighbours' content too. Tiles more
than one step from the player's tile are unloaded (memory only; the caches stay).

Neighbour pack ids come from the tile centre in L-EST97 (`t<easting>_<northing>`), so tiles
generated for one origin are reused by every origin on the same grid. Until a tile is ready the
player is held at the edge with a notice ("The land beyond is still being surveyed"); if the
service is unreachable, "There is no map beyond here" and a retry every 90 s. `--no-stream`
disables streaming (screenshots, measurements). Nodes that read pack files must resolve them
through `Sites.path_in(Sites.pack_of(self), ...)` and sample the terrain in global space
(`to_global`), because a streamed tile sits at an offset; `Parcels.at(pos)` already does.

Known limits: the historical drapes (verst map, 1940 cadastral map) cover the origin tile only,
neighbours show their orthophoto colour under the detail materials in every era; traffic agents
stay inside their tile's road graph.

## Starting everything

`tools/play.sh [--site=<id>] [--windowed]` (or `make play ARGS="..."`) starts the tile service
(port 8765) and the world service (port 8766) if they are not running, keeps their logs under the
user directory (`logs/tile_service.log`) and launches the game; the town server is `make server`. The game
also starts either service itself when it runs from the source tree and the configured URL is
local (`Locator.spawn_local`), so `godot --path .` works too; exported builds need a service URL
in `settings.cfg` (`[service] url`, `worlds_url`).

## Water, fish, ground and people

Every still-water patch in a pack's water file becomes a `Pond`: a rippling surface
(`assets/shaders/lake.gdshader`, adapted from the MIT Realistic Water Shader: gentle Gerstner
waves, drifting ripple normals, depth-based colour by Beer's law with refraction of what lies
below, foam along the shore), a basin carved into the terrain at load time (only where the laser
DTM was flat at the water level, so land inside a patch's bounding box stays), and a school of fish
circling below the surface (a MultiMesh, animated within 70 m of the player). Streamed tiles get
their ponds too. Vegetation is never scattered on water patches (`TerrainBuilder.water_exclusions`) nor under
building footprints (`TerrainBuilder.footprint_mask`: the register polygons grown 0.7 m, or the laser massing
rectangles), so nothing grows through an interior floor.

Ground and facade textures are CC0 sets from Poly Haven, fetched and packed by
`tools/pipeline/fetch_polyhaven.py` (record in `assets/textures/POLYHAVEN.json`): five terrain
materials (meadow, field, forest floor, gravel, soil) and ten building materials (plaster, brick,
concrete, prefab panel, boards, logs, roof tiles, corrugated iron, reed, fieldstone) that
`FootprintBuilding` picks from the Building Register's facade and roof texts.

People are MakeHuman figures generated headlessly with MPFB2 in Blender
(`tools/blender/make_humans.py`; MPFB extension and the CC0 system asset pack required): eight
variants (men and women, young to old, casual, work and elegant suits) with the game-engine rig,
exported to `assets/models/humans/*.glb`. `HumanFigure` drives them without animation clips: a
procedural gait (hip and knee swing, arm counter-swing, torso sway) for walkers, standing poses
(stand, arms folded, holding, sitting on the bicycle) for NPCs and riders, and era tints on the
clothes. Preview them with `godot --path . res://tools/godot/figure_preview.tscn -- --screenshot=/abs/out.png`.

## Iterating

| Change | Then run |
|---|---|
| positions in `layout.json` | `make scenes`; pads, exclusions and `buildings.json` also need `make tile` (or `make scatter`) |
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
  "id": "kvissentali",                    // must equal the directory name
  "name_key": "SITE_KVISSENTALI",         // menu label
  "subtitle_key": "SITE_KVISSENTALI_SUBTITLE",
  "terrain": {
    "tile": "kvissentali",                // assets/terrain/<tile>/
    "center": [657600, 6477150],          // EPSG:3301 easting, northing
    "size": 1024,                         // metres; one Terrain3D region (<= 2048)
    "latitude": 58.4, "longitude": 26.7, "utc_offset": 3.0, "date": [2026, 9, 3]   // Sky3D sun; the date starts the month clock
  },
  "start": {"era": "era_2026", "spawn": [508, 513], "yaw_deg": 180},
  "water": "water_2026.json", "buildings": "buildings_2026.json",
  "locations": {"LOC_LANDMARK": "landmark"},   // translation key -> layout key (named spots)
  "codex": ["CODEX_REAL", "CODEX_INVENTED", "CODEX_DATA"]   // journal tab: <key> and <key>_TITLE
}
```

## scenes.json reference

Positions are tile metres. Numbers may be expression strings using layout keys and loop
variables (`"manor[0] - manor_size[0] / 2"`, `"i * 4.5"`); text may interpolate fragment
parameters (`"EX_OAK_{year}"`). `at` is a layout key, `[x, z]` or
`{"ref": "farm", "offset": [dx, dz]}`; inside a group it is relative to the group.

| type | fields | notes |
|---|---|---|
| `group` | name, at, lift, children | a plain Node3D container |
| `use` | fragment, with | expands a named fragment with parameters |
| `repeat` | count, var, children | loop; `{i}` in names, `i` in expressions |
| `instance` | name, scene, at, scale, yaw / yaw_deg | any PackedScene or glb |
| `building` | name, model, yaw_deg, footprint [w, h, d], scale, skirt | collider and foundation skirt; tags the group for lowest-corner snapping |
| `box`, `torus` | size, y, color, at, rot / inner, outer, color, y | quick CSG props; colours by name from `colors` |
| `examine` | name, key, loc, label, at | hover text on a landmark |
| `tree`, `scatter` | at, scale, yaw, scene / prefix, count, radius, scale [min, max], seed | single tree, or a random disc of them |
| `footprints` | source, year, include_undated | the real buildings from `buildings.json` |
| `roads` | source | ETAK roads as terrain ribbons |
| `parcels` | source, year | cadastral units and their kits (`assets/data/parcel_rules.json`) |
| `traffic` | year, density, max_agents | ambient walkers, cyclists and cars on the road graph |
| `bicycle` | name, at | the rideable bicycle |
| `village` | source | massing boxes from the laser data, for packs without the register |

Fragments are the reusable blocks: `"fragments": {"oak": {"params": ["scale", "year"], "nodes": [...]}}`
and `{"type": "use", "fragment": "oak", "with": {"scale": 0.75, "year": 2026}}`.

## Rules that still hold

The ledger is the only state that is shared or saved; everything a pack places in the world is
regenerated from data. Structures a pack offers are `StructureDefinition`s with a euro cost, a rent
bonus and the purposes they may stand on; the module and the offline ledger both validate them.

Every data source a pack uses gets a row in `THIRD_PARTY.md`; the Maa-amet attribution is
shown in the menu and must stay, and the codex names the register, notice and news sources.
