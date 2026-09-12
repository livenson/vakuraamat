# Adding a country

A country is two things: an **adapter** in `tools/pipeline/sources.py`, for the pipeline and the
tile service, and a **descriptor** in `assets/data/countries/<id>.json`, for the game. No other
script names a country. Estonia (`ee`) and Latvia (`lv`) are the worked examples. Latvia was
added on top of Estonia (`docs/latvia-plan.md`) and is the better model for a country whose
data looks nothing like Estonia's.

Everything is built on one grid, L-EST97 (EPSG:3301). A country with its own grid is reprojected
into it the way Latvia's LKS-92 data is (`tools/pipeline/geo.py`). The grid is conformal and
reasonable around the Baltic, but it distorts the further you go. A country far from 24°E needs a
per-country grid first, which is a larger change than this guide covers.

## 1. The adapter (`tools/pipeline/sources.py`)

Subclass `DataSource` and add an instance to `SOURCES`. Put an adapter whose coverage test is
exact before one whose test is only a box. Latvia comes before Estonia because Latvia's test
excludes Estonian land.

| Member | What it is | Estonia | Latvia |
|---|---|---|---|
| `id`, `name`, `label` | the id packs carry (`site.json` `country`), a long name, and the agency the service's progress shows | `ee`, Maa-amet | `lv`, LĢIA |
| `bbox`, `covers(x, y)` | where the country is. `covers` can be stricter than the box | the box | a laser sheet under the point and not on another country's land |
| `place(x, y)` | where a new world asked for at a point is centred. The point must stay inside the world; the tile service keeps it as `terrain.focus`, where the player starts | the point | the centre of the laser sheet holding the point, so the world downloads one sheet instead of four (`fetch_tile_lv.place_center`) |
| `outline` | `assets/data/<file>` with the land as rings (`tools/pipeline/fetch_outline.py`). It gives `land()` / `on_land()` for the cross-border merge and the menu map | `estonia.json` | `latvia.json` |
| `own_tile`, `build_tile()` | the ground: heightmap, canopy, `ortho.jpg`, and `terrain_meta.json` with `"country"`. Without `own_tile`, `fetch_tile.py`'s own (Estonian) steps run | no | `fetch_tile_lv.build_tile` |
| `estimate()` | the download list the menu shows before a job, and the bytes the refine pass fetches later | DTM and nDSM sheets, orthophoto | laser sheets |
| `registers()` | the job's register stages: parcels, buildings, companies, roads, stops. Returns the stops thread | `fetch_buildings`, `fetch_parcels`, `fetch_roads`, `fetch_fields`, `fetch_tenants`, `market` | `fetch_cadastre_lv`, `fetch_tenants_lv`, `fetch_roads_lv` |
| `refine()` | what is fetched after the pack is playable. Returns (ok, ground resolution) | 1 m ground, trees, timetables | older photographs, timetables, `"refined": true` in the meta |
| `border()`, `border_roads()` | this country's rows for a neighbour's pack on the border (`cross_border.py`) | parcels, buildings, companies | the same, and OpenStreetMap roads |
| `departures()` | the timetables (`fetch_departures.py`) | national GTFS | ATD, Rīgas satiksme |
| `codex(name)` | the pack's "Real / Invented / Data" texts, in et, en and lv | | |
| `geocode(q)` | address search, `[{name, x, y}]` on the grid. The service's `/geocode?country=<id>` | in-ADS | VARIS (`geocode_lv.py`) |

Write each fetcher as its own module (`fetch_<thing>_<id>.py`) that produces the same files as the
Estonian one. The formats are in `docs/data-pipeline.md` and `docs/custom-sites.md`. The game reads
only those files, never the source data. Keep the shape of each row: `tunnus` for a parcel,
`ehr` for a building's register code, `registry_code` / `tunnus` / `building_id` for a company, and
`sector` from the game's EMTAK groups (`tools/pipeline/emtak.py`, which maps any NACE code).

The frozen service (`tools/service/tile_service.spec`) bundles every pipeline module and every
`assets/data/*.json` by itself, so a new module needs no entry there.

## 2. The descriptor (`assets/data/countries/<id>.json`)

The game reads it through `Countries` (`scripts/world/countries.gd`).

| Key | What the game does with it |
|---|---|
| `id`, `name` | `id` matches the adapter's |
| `outline` | a `res://` path to the same outline file. The menu map draws every country's |
| `coverage` | `[xmin, ymin, xmax, ymax]` on the grid. The locator only asks the service about points inside some country's box |
| `geocoder` | `{"url": "...{q}...", "results", "name": [keys], "x", "y"}` for a public gazetteer the game can ask itself, or `{"service": "/geocode?country=<id>&q={q}"}` when only the service can search |
| `refine` | `"ground"` if the game should take the pack again while its `dtm_res_m` is over 1. `"flag"` if the ground is fine from the start and the refine pass marks the meta `"refined"` instead |
| `photos` | the plot page's "over the years" strip. Either `{"wms", "epochs": [{label, layers}], "current_wms", "current_layer"}`, a historical WMS the game asks per plot, or `{"from_tile": true}`, where the refine pass cuts the older photographs over the tile into `ortho_<years>.jpg` and lists them as `history` in `terrain_meta.json` |
| `building_code` | `pattern`, a regex for the country's building codes, plus `register_key` and `code_key`, the register sheet's strings. The pattern decides which country a building belongs to on a border tile, so it must not match another country's codes |
| `parcel_code`, `parcel_link` | `parcel_code` is a regex for the country's plot codes; it decides a plot's country on a border tile. `parcel_link` is the link for a plot whose pack gives it none: `{property}` is its property number and `{tunnus}` its code. Latvia links a plot to its property's Lursoft card |
| `building_links`, `place_links` | the report's links. `{code}` is the building code; `{x}` and `{y}` are the point on the grid |

Add the strings a descriptor names to `assets/i18n/strings.csv` in every column. Then run
`godot --headless --path . --import`.

## 3. Check it

- `make test`. `countries_test` checks every descriptor: its files and strings exist, the photo
  source is complete, and building codes and packs resolve. Add your country's own examples to it
  the way Rīga and Pirita are there.
- `python3 tools/pipeline/sources.py --check <x> <y>` for a few points, including one on each side
  of every border.
- Build a place through the tile service. Screenshot it with the world's `--screenshot` flag, and
  open a plot with `--open=plot:<tunnus>#0` to see its history strip.
- Add a row per source to `THIRD_PARTY.md`: licence, attribution, and where it is used.

## What is still one-country

- `tools/pipeline/fetch_outline.py` fetches each country's outline in its own way (`--country`).
  It runs once per country, by hand.
- `scripts/world/links.gd` ties plots by the Estonian land-register number (`kinnistu`). A country
  without one simply has no such links.
- `scripts/ui/place_search.gd` folds Estonian and Latvian diacritics and street abbreviations.
  Another alphabet needs its own folding there.
- Traffic drives on the right (`scripts/world/bus_agent.gd`).
