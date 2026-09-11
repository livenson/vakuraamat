# Latvia: the second country

**Status (2026-09-11):** sources verified by probe for a Rīga square (LKS-92 E 506000–507000,
N 312000–313000; L-EST97 about E 506700, N 6311800) and a rural square by Līvāni. Time-sensitive
downloads are archived in `data_raw/lv/` (step 0). No adapter code yet.

The goal is a Latvian place that plays like an Estonian one: the same pack files, the same book,
the same rule that every figure is a register field. Nothing in the pack format changes. A
`Latvia` adapter in `tools/pipeline/sources.py` and Latvian fetchers produce `parcels.json`,
`buildings.json`, `tenants.json` and the rest; the engine only loses its "is this Estonia" checks.

## Decisions

- **One world grid, L-EST97 (EPSG:3301), across the border.** Latvian data is reprojected into it
  by the fetchers. The Estonian projection is still accurate over Latvia (scale error 0.04 % in
  Rīga, 0.11 % at Daugavpils, the worst; grid north turns by up to 2.5° at Liepāja), invisible
  at 1 km. Tile ids (`t<easting>_<northing>`), `TerrainGeoref`, the streamer and the plot page keep
  working, and a player can walk from Valga into Valka. The HUD may show LKS-92 in Latvia.
- **Same pack format.** Field names stay as they are (`tunnus` holds the Latvian 11-digit cadastral
  code, `ehr` the 14-digit building code). Where a Latvian register says nothing, the field is
  `null`, as in Estonia.
- **The country is a property of the pack.** `site.json` gets `"country": "lv"`, so link builders,
  purpose tables and attribution can branch without guessing from coordinates.
- **First places:**
  1. Rīga, Vecpilsēta (Old Town) and the centre: the only area with LOD2 roofs, and the densest
     company and price data.
  2. Valga–Valka: the border runs through one town. It shows the one grid, but its roofs need
     step 4.

## Sources (probed 2026-09-11)

All data.gov.lv datasets are listed through CKAN: `https://data.gov.lv/dati/api/3/action/package_show?id=<slug>`.
Resource URLs change when a file is replaced, so fetchers resolve them through the API each time.

| Layer | Source | Format and access | Licence |
|---|---|---|---|
| Laser points | LĢIA, sheet list `s3.storage.pub.lvdc.gov.lv/lgia-opendata/las/LGIA_OpenData_las_saites.txt` (65,917 sheets, 1×1 km) | LAS 1.2, uncompressed, ~170 MB/km²; ground 2, vegetation 3–5, building 6, water 9; **no CRS in the file** (EPSG:3059, LAS-2000,5 heights). Rīga 6.1 pts/m² (2016), rural ~4 pts/m² (2013–2019) | CC BY 4.0 |
| Ground model | LĢIA `citi/dtm/DTM_Latvija_20m.7z` | 20 m grid, whole country, 399 MB. Too coarse: we grid our own from the laser points | CC BY 4.0 |
| Orthophoto | LĢIA 6th cycle (2016–18), `ortofoto_rgb_v6/LGIA_OpenData_Ortofoto_rgb_v6_saites.txt` | 25 cm GeoTIFF in 2.5 km sheets, tiled: a window is cut over `/vsicurl/` (500 m in 4.6 s). 7th/8th cycles (2019–24) only by application, WMS | CC BY 4.0 |
| Cadastre, geometry | VZD `kadastra-informacijas-sistemas-atverti-telpiskie-dati` | SHP zip per municipality (Rīga 21 MB), weekly. `KKParcel`, `KKBuilding` (+`PARCELCODE`), `KKParcelPart`, `KKEngineeringStructurePoly`. Fields are only codes and dates | CC BY 4.0 |
| Cadastre, attributes | VZD `kadastra-informacijas-sistemas-atvertie-dati` | national zips of one XML per municipality, weekly: `building.zip` 242 MB, `parcel.zip` 53 MB, `address.zip` 39 MB, `valuation.zip` 229 MB. XSDs published. Rīga's entry can be read by range request | CC BY 4.0 |
| Building fields | `building.zip` | `BuildingCadastreNr`, `VARISCode`, `BuildingName`, `BuildingUseKindId/Name` (e.g. 1251 "Rūpnieciskās ražošanas ēkas"), `BuildingKindId/Name`, `BuildingArea`, `BuildingGroundFloors`, `BuildingUndergroundFloors`, `BuildingExploitYear`, `BuildingDeprecation`, element materials per part (foundation, walls, roof), `ParcelCadastreNrList`. In the Rīga square: 96 % floors, 87 % year, 96 % address code | |
| Parcel fields | `parcel.zip`, `valuation.zip` | `ParcelCadastreNr`, `ParcelVARISCode`, `ParcelArea`, `LandPurposeKindId/Name` (NĪLM, e.g. 0801 "Komercdarbības objektu apbūve", with area per purpose); `ObjectCadastralValue` by `ValueType` `fisc` / `univ` / `prog` with dates | |
| Sale prices | VZD `nekustama-ipasuma-tirgus-datu-bazes-atvertie-dati` | yearly CSV zips from 2012, `;`, UTF-8 BOM: `TG_CSV` (flats, premises), `ZVB_CSV` (land with buildings), `ZV_CSV` (land). Per deal: cadastral number, address, date, price in EUR, floors, year, area, rooms. **The dataset notice says it is available until the end of 2026** | CC BY 4.0 |
| Buildings WFS | INSPIRE Buildings, `geo-dpps.viss.gov.lv/api/DPPSPackage/client/Ekas_un_bu_419_kg61P8/…` | bbox query, no key, EPSG:4258: `dateOfConstruction`, `numberOfFloorsAboveGround`, `currentUse`. A quick check, not the main path | |
| LOD2, Rīga | Rīgas dome `rigas-apkaimju-lod2-modeli` | 58 neighbourhoods in GDB, OBJ, CityGML; from 2021–22 laser scans; EPSG:3059 + LAS-2000,5; **no attributes** (only `OBJECTID`), CityGML axis order northing, easting | CC BY 4.0 |
| LOD1, Rīga | `rigas-lod1-modelis` | one GDB (113 MB) / CityGML (178 MB) | CC BY 4.0 |
| Trees | Rīgas dome `rigas-dizkoku-datubaze` | 1,329 protected trees (species in Latvian). No street-tree register | CC BY 4.0 |
| Roads | VZD `aw_shp.zip` `Ielas` | named street centrelines, no class, no width. Roads come from OpenStreetMap | CC BY 4.0 / ODbL |
| Addresses | VZD `varis-atvertie-dati`, daily | `aw_eka.csv` (141 MB): `KODS`, `STD` (full address), `KOORD_X` = **northing**, `KOORD_Y` = easting, `DD_N`, `DD_E`. No free geocoding API | CC BY 4.0 |
| Companies | Uzņēmumu reģistrs (UR), about 30 datasets, daily | `register.csv` (`;`): `regcode`, `name`, `type` (`IK` sole trader, `SIA`, `AS` …), `registered`, `terminated`, `closed`, `address`, **`addressid`** (the VAR code), `atvk`; `officers.csv`, `members.csv`, `stockholders.csv`, `beneficial_owners.csv`; annual reports `financial_statements.csv` (`year`, `employees`, `rounded_to_nearest`), `income_statements.csv` (`net_turnover`, `net_income` …), `balance_sheets.csv` | CC0 |
| Taxes, quarterly | VID `nodoklu-maksataju-taksacijas-ceturksni-samaksato-vid-administreto-nodoklu-kopsummas` | one CSV, **the latest quarter only** (2026 Q2, 153,951 rows): `Registracijas_kods`, `Taksacijas_gads_ceturksnis`, taxes paid, of which VAT in/out, personal income tax, social tax (thousands of EUR), `Videjais_nodarbinato_personu_skaits_cilv` | CC0 |
| Taxes, annual | VID `komersantu-ieprieksejos-tris-taksacijas-gados-…` | 3 years (the April 2025 file holds 2022–2024), adds `Pamatdarbibas_NACE_kods`, `Juridiska_adrese_ATVK_kods` | CC0 |
| Taxpayer rating | VID `nodoklu-maksataju-reitings` | overall rating per company, irregular | CC0 |
| GTFS | ATD `atd.lv/sites/default/files/GTFS/gtfs-latvia-lv.zip` (buses, daily); `vivi.lv/uploads/GTFS.zip` (trains); Rīgas satiksme on data.gov.lv, one new resource a month | GTFS | CC0 |
| Fields | LAD field-block WFS (`…/Lauku_blok_398_oDY1Pt/…`, bbox in **northing, easting**); declared fields as a yearly GPKG per region, cut over `/vsicurl/`; crop is `product_code` only | WFS, GPKG | CC0 |

**Keys that tie it together:**
- The parcel code has 11 digits. A building's 14-digit code starts with its parcel's code, and
  `KKBuilding.PARCELCODE` says the same.
- The VAR address code is the join: `VARISCode` on a building, `ARCode` on an address and
  `addressid` on a company.
- A company's `regcode` in UR is `Registracijas_kods` in VID.

## From sources to pack files

| Pack file | Filled from | Notes |
|---|---|---|
| `heightmap.r32`, `canopy.r32` | the laser sheets under the tile, reprojected to EPSG:3301 | A 1024 m tile on the Estonian grid straddles up to four 1 km sheets (~700 MB download, cached). Ground: class 2 gridded at 1 m, holes filled. Canopy: highest return minus ground. A cheap first pass: ground only, 5 m (the same two-pass split the Estonian job has) |
| `ortho.jpg` | 6th-cycle orthophoto, windows cut over `/vsicurl/` and warped to EPSG:3301 | The plot page's history strip has one picture (2016–18) until the newer cycles are licensed |
| `trees.json` | tree tops found in the vegetation classes (local maxima of the canopy) | Species unknown: conifer or deciduous from return intensity, or left out |
| `parcels.json` | `KKParcel` geometry + `parcel.zip` + `valuation.zip` + `address.zip` | `tunnus` = parcel code; `purpose` = NĪLM codes with `purpose_pct`; `land_value` from `ValueType` (which type the book shows is an open question); `link` to kadastrs.lv |
| `market.json` | the sale-price CSVs (prices per m² by purpose, deals near the tile) | Latvia has real deal prices, not only valuations; label them as such |
| `buildings.json` | `KKBuilding` geometry + `building.zip`; `lod2` from the Rīga models by footprint overlap | `year` = `BuildingExploitYear`, `floors` = `BuildingGroundFloors`, `purpose` = `BuildingUseKindName`, `kind` from `BuildingUseKindId`, `materials` from the element list |
| `roads.json` | OpenStreetMap ways, names checked against VZD `Ielas` | ODbL, like `stops.json` |
| `tenants.json` | UR register joined by `addressid`, VID quarter + archive, UR annual reports | See below |
| `stops.json`, `departures.json` | OSM stops (as now), the three GTFS feeds | `fetch_departures.py` takes a feed list per country |
| `fields_2026.json` | LAD WFS + declared GPKG | Needs a table from `product_code` to the game's crops |

**Companies (`tenants.json`):**
- Legal persons only. `IK` (individuālais komersants) is a sole trader and is skipped, as the
  Estonian FIE is. Farms (`ZS`) are an open question.
- Officers, members, stockholders and beneficial owners carry names and masked personal codes.
  They are kept as structure only (`board_size`, `shareholders`, hashed `owners`), like the
  Estonian register.
- VID gives `taxes` and `employees` per quarter, but no turnover. `turnover` comes from the UR
  income statement for the latest year, scaled by `rounded_to_nearest`. The health rules must
  accept an annual turnover beside quarterly taxes. `quarters` is built from our own archive
  (step 0).
- `sector` comes from the NACE code (`Pamatdarbibas_NACE_kods`, UR area of activity). EMTAK is
  NACE plus a fifth digit, so `emtak.py`'s section map applies; the Latvian activity text goes
  into `emtak.text`.

## What is missing and how to cover it

| Gap | Fix |
|---|---|
| No open 1 m ground model | Grid the laser points (numpy on laspy, or PDAL if its wheel fits the sidecar) |
| No LOD2 outside Rīga | Step 4. Without it `footprint_building.gd` extrudes each footprint to its height with a flat roof: right for Soviet apartment blocks, wrong for houses, farms and wooden towns. Fit a gable or hip roof to the building-class points (ridge line and height), or, cheaper, pick the roof by `kind` and floors |
| No single-tree data | Canopy maxima (above) |
| No road classes or widths | OpenStreetMap |
| No geocoder | The tile service indexes `aw_eka.csv` and answers `/geocode` for Latvia; `Locator` goes through the service instead of calling in-ADS directly |
| Orthophoto 2016–18, no history | Apply to LĢIA for the WMS of the newer cycles (terms to check) |
| Tax history only from now on | Archive every quarter (step 0); ask VID for older quarters, or use the annual file |

## Engine changes

- `scripts/autoload/locator.gd`:
  - `in_estonia` becomes "some adapter covers the point".
  - The in-ADS `GEOCODER` call moves behind the service's `/geocode` for points outside Estonia.
- `tools/pipeline/sources.py`: a `Latvia` class. Its box on the L-EST97 grid is about
  E 305000–770000, N 6165000–6450000, which overlaps Estonia's box along the border, so `covers`
  must test the country outline, not only the box.
- `tools/tile_service.py`, `fetch_tile.py`: pick the adapter for the point, not Estonia by default.
- `scripts/ui/plot_history.gd`: the Maa-amet WMS layers are Estonian. In a Latvian pack the plot
  page shows the pack's orthophoto only.
- `scripts/world/tenants.gd`, `road_network.gd`, `map_palette.gd`: already read `emtak.text` and
  `sector`, so nothing changes there; company links come from the pack (`link`), not a hard-coded
  host.
- `assets/data/estonia.json`: the menu's locator map gets Latvia (a Baltic outline).

## Language

- **UI strings.** `assets/i18n/strings.csv` is `keys,et,en`. Add an `lv` column (and one in each
  pack's `strings.csv`); Godot's CSV import writes `strings.lv.translation` beside the others.
  Draft with a machine and have a native speaker review, especially the book's voice.
- **The switch.** It is a two-way flip hard-coded in `scripts/ui/ui_manager.gd:548`, `:758` and
  `scripts/ui/main_menu.gd:110`, `:288`. It becomes a cycle over a list (`et`, `lv`, `en`), and the
  first launch starts from `OS.get_locale_language()`.
- **Fonts.** EB Garamond and IBM Plex Sans contain every Latvian letter (āčēģīķļņšūž and the
  capitals; checked with fontTools). Nothing to do.
- **Register text** stays in the register's language, but the logic must stop reading Estonian
  words:
  - Parcel purposes already go through `PURPOSE_<code>` keys (`book_panel.gd:675`); add
    `PURPOSE_LV_<NĪLM>` rows.
  - `interiors.gd:518–524` picks rooms by Estonian substrings ("kauplus", "elamu", "ladu").
    The pipeline should write a neutral use class per building (it already writes `kind`), and
    interiors should read only that.
  - Building uses and activity texts are shown as the register wrote them. A translated class
    label beside them (from `kind` and `sector`) lets a player read a Latvian pack in Estonian or
    English.
- **Formats.** Euro in both countries; `BookTheme.money()` is fine. Latvian addresses read
  "Brīvības iela 1, Rīga"; the pack's `address` is shown as written.

## Steps

0. **Archive what can disappear.** Done 2026-09-11:
   - `data_raw/lv/nitis/`: the sale-price CSVs for 2012–2026, 59 MB.
   - `data_raw/lv/vid/cet_2026Q2.csv`: this quarter's taxes.
   - `data_raw/lv/vid/nm_3gadi_2025-04.csv`: taxes for 2022–2024.

   Still to do: download each new quarter as it comes out (VID replaced the file on 2026-08-14,
   so the next is due around mid-November), and move the store off this laptop.
1. **Adapter and ground.** `Latvia` in `sources.py`; laser sheets → heightmap and canopy;
   orthophoto windows; `terrain_meta.json` with Latvian attribution. Done when a Rīga tile loads
   with ground and orthophoto (screenshot) and `make validate` passes.
2. **Cadastre and buildings.** Parcels, buildings with year, floors and use, footprints; the Rīga
   LOD2 join. Done when the Old Town stands with its roofs and the book lists its plots.
3. **Companies and money.** UR + VID + annual reports into `tenants.json`; the health rules
   accept annual turnover. Done when name plates and the K overlay show Latvian companies and
   `health_test` passes on the pack.
4. **Roofs from the laser points** for buildings without LOD2. Done when Valka's houses have
   pitched roofs (screenshot beside the orthophoto).
5. **Roads, stops, departures, fields.** OSM roads, the GTFS feeds, LAD fields.
6. **Language.** `lv` column, the locale cycle, the neutral use and sector labels, the menu map.
7. **Streaming across the border.** Walk from Valga into Valka; starter places for Rīga.

Each step bumps `PACK_VERSION` when it adds something the UI reads, and gets a `THIRD_PARTY.md`
row for every source in the same commit.

## Attribution and licences

- VZD (cadastre, prices, addresses), CC BY 4.0: "Izmantoti Nekustamā īpašuma valsts kadastra
  informācijas sistēmas dati, <gads>" and "Izmantoti Valsts adrešu reģistra informācijas sistēmas
  dati, <gads>".
- LĢIA (laser points, orthophoto), CC BY 4.0 per its own licence (data.gov.lv labels the entries
  CC0): "Latvijas Ģeotelpiskās informācijas aģentūra".
- Rīgas dome (LOD1, LOD2, trees, city buildings), CC BY 4.0: "Rīgas valstspilsētas pašvaldība".
- UR, VID, LAD, ATD, Rīgas satiksme, VIVI: CC0; credited anyway.
- OpenStreetMap roads: ODbL, as the stops already are.

## Open questions

- **Which cadastral value the book shows.** `fisc` (for property tax) is the nearest to
  Estonia's taxation value; check what `univ` and `prog` mean before choosing.
- **Individual flat sales.** They carry an address but no owner. Showing them per building is
  within the "every figure is a register field" rule, but decide it deliberately; aggregates in
  `market.json` are safe either way.
- **Farms** (`ZS`, zemnieku saimniecības): companies in form, family-owned in practice. Include or
  skip.
- **LKS-2020.** LĢIA announces that state data moves from LKS-92 to LKS-2020 on 2026-10-01. Pin
  the transform per dataset, and read the CRS from each file rather than assuming EPSG:3059.
- **Newer imagery and laser scans** (Rīga 2021–22, orthophoto cycles 7–8): apply to LĢIA, and
  check that the terms allow redistribution inside a game download.
