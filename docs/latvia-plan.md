# Latvia: the second country

**Status (2026-09-11):**
- Sources verified by probe for a Rīga square (LKS-92 E 506000–507000, N 312000–313000; L-EST97
  about E 506700, N 6311800) and a rural square by Līvāni.
- Time-sensitive downloads are archived in `data_raw/lv/` (step 0).
- Step 1 is done: the `Latvia` adapter and `tools/pipeline/fetch_tile_lv.py` build a Rīga Old Town
  tile (centre 506400 6311650) in under a minute from a cold cache.
- Steps 3–7 are done too (companies, roads and buses, roofs outside Rīga, Latvian as a language, the border). Step 2 is done: `tools/pipeline/fetch_cadastre_lv.py` writes the pack's `parcels.json` (838
  units, all valued) and `buildings.json` (775 buildings, 713 dated, 615 with Rīga's LOD2 roofs).
  `sites/riga_vecpilseta` validates, boots in `make test` and is committed on the `latvia` branch.

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
| Laser points | LĢIA, sheet list `s3.storage.pub.lvdc.gov.lv/lgia-opendata/las/LGIA_OpenData_las_saites.txt` (65,917 sheets, 1×1 km) | LAS 1.2, uncompressed, ~170 MB/km²; **no CRS in the file** (EPSG:3059, LAS-2000,5 heights). Rīga 6.1 pts/m² (2016), rural ~4 pts/m² (2013–2019). LĢIA's own classes, read from where the points lie (the agency publishes no list): 2 ground, 3–5 vegetation, 6 buildings, 7 noise, **9 bridge decks, 11 piers and moored boats, 14 water surface** (ASPRS would put water in 9) | CC BY 4.0 |
| Ground model | LĢIA `citi/dtm/DTM_Latvija_20m.7z` | 20 m grid, whole country, 399 MB. Too coarse: we grid our own from the laser points | CC BY 4.0 |
| Orthophoto | LĢIA 6th cycle (2016–18), `ortofoto_rgb_v6/LGIA_OpenData_Ortofoto_rgb_v6_saites.txt` | 25 cm GeoTIFF in 2.5 km sheets, tiled: a window is cut over `/vsicurl/` (500 m in 4.6 s). The georeference is only in the `.tfw` beside each sheet. LĢIA's open-data list also offers cycles 1–5 (1994–2015) for download, the plot page's history strip. 7th/8th cycles (2019–24) only by application, WMS | CC BY 4.0 |
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
| `heightmap.r32`, `canopy.r32` | the laser sheets under the tile, reprojected to EPSG:3301 | Done (step 1). A 1024 m tile on the Estonian grid straddles four 1 km sheets (470 MB for the Old Town, cached). Ground: classes 2 and 14 averaged per metre, holes under buildings filled; cells with no return at all in areas wider than 17 m are open water, set to the median water-surface height (0.39 m on the Daugava), because interpolating from the banks streaked across the river. Canopy: the highest **vegetation** return (3–5) above the ground, so a roof never reads as a tree, unlike Maa-amet's nDSM, which the building footprints have to mask |
| `ortho.jpg` | 6th-cycle orthophoto, windows cut over `/vsicurl/` and warped to EPSG:3301 | Done (step 1). The plot page's history strip can draw on cycles 1–5 (1994–2015) |
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
| Orthophoto 2016–18 is the newest open one | Cycles 1–5 give the history; apply to LĢIA for the WMS of cycles 7–8 (terms to check) |
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
1. **Adapter and ground.** Done 2026-09-11:
   - `Latvia` in `sources.py`, tested before Estonia. A point is Latvian when LĢIA has a laser
     sheet under it and it is off Estonian land by `assets/data/estonia.json`: Valga resolves to
     Estonia, Valka to Latvia, the Gulf of Rīga to nobody.
   - `fetch_tile.py` hands a non-Estonian tile to its adapter's `build_tile`.
   - `new_site.py` stamps `"country"` in `site.json` and writes Latvian credits.
   - Screenshots show the Old Town on its orthophoto, with trees only where the vegetation points
     are, at 89–110 fps.
   - `make validate` fails on the pack until step 2 brings `parcels.json`.
   - Still open: the tile service runs the Estonian stages in its own job code, so a Latvian place
     cannot be made from the menu yet; that is step 7.
2. **Cadastre and buildings.** Done 2026-09-11:
   - **What it reads.** The municipality comes from the address register's polygons (a state city
     from `Pilsetas` with `VKUR_TIPS` 101, else `Novadi`; `ATRIB` is the ATVK code). The outlines
     come from its `kk_shp.zip`, only the cadastral groups under the tile. The attributes come from
     the municipality's own XML in six national zips, read by range request (about 90 MB compressed
     for Rīga, cached per export date) and streamed, keeping only the tile's objects.
   - **Parcels.** `land_value` is the universal cadastral value (`univ`, 2025-01-01); `fisc` sits
     beside it as `land_value_fisc`. `purpose` holds the game's classes, mapped by the words of the
     Latvian purpose names (parking and mixed city-centre use included); `purpose_code` and
     `purpose_text` keep the register's own. `ownership` is the owner's kind as the register writes
     it (`juridiska persona`, `pašvaldība`, `valsts`, `fiziska persona`); the playground rule now
     accepts `pašvaldība`. `land_registry` is the property's land-book folio, so `Links` ties the
     parcels of one property. 13 parcels carry no purpose in the register and have no class. `link`
     is null: no public per-parcel URL on kadastrs.lv was found that opens the object.
   - **Buildings.** Use, kind, floors, year taken into use, the element materials
     (`Sienas`, `Fasāde`, `Jumta segums` ...), the address, the VAR address code (`ads.var_code`, the
     key for the companies in step 3) and the parcels a building stands on. Heights come from the
     building-class laser points (`fetch_tile_lv` keeps them as `data_raw/lv/<tile>_roofs.r32`).
   - **LOD2.** The Rīga models are triangle meshes without attributes; each goes to the building
     whose outline holds most of its footprint. Coplanar triangles are merged back into faces and
     wound so roofs face up and walls face out (the engine takes a face's normal from its vertex
     order). Pieces under 1 m² are dropped: the models carry every cornice, 222 faces a building
     against 16 in Maa-amet's. A model whose base lies more than a metre under the ground is
     anchored a metre under it. The file is written compact: 8 MB against Pirita's 3 MB.
   - **Engine.** The building sheet names the Latvian cadastre and its designation instead of
     "EHR", and the book no longer shows a register link for a plot without one.
   - **Checks.** Old Town screenshots, the plot page and the building sheet; `--bench` 114 fps at
     street level and 124 fps flying; `make test` green with the pack.
   - **Left over.** Some faces still lack windows, roofs read paler than Rīga's red tiles in the
     orthophoto, and the ground between buildings is lumpy in places (holes under buildings
     interpolated from the ground points).
   - **Menu (2026-09-12).** Latvia can be tried from the Locations page:
     - The map draws Latvia beside Estonia (`assets/data/latvia.json`).
     - Six Latvian suggestions: Rīga Alberta iela, Jūrmala Majori, Cēsis, Kuldīga, Valka and Līvāni.
     - The search finds Latvian places and addresses through the service's `/geocode_lv`.
     - `Locator.in_coverage` replaces the Estonia-only check in the create path and "Use my location".
     - The tile service builds a Latvian place: ground and orthophoto from LĢIA, then
       `fetch_cadastre_lv` instead of the Estonian registers, and nothing to refine. The same job
       serves neighbour tiles streamed from a Latvian place.
     - The frozen sidecar carries the new modules and `estonia.json` (the Valga/Valka test).
     - Places outside Rīga get flat roofs until step 4. None has roads or bus stops before
       step 5.
3. **Companies and money.** Done 2026-09-12 (`tools/pipeline/fetch_tenants_lv.py`, also a stage of
   the service's Latvian job):
   - **Old Town results.** 2,361 companies on the tile's buildings and plots, and 2,581 more on its
     streets, in 10 s. VID taxes for 3,219, annual-report turnover for 3,237. Health: 1,936 sound,
     159 watch on turnover, 110 watch on an overdue report, 122 distressed by status, 34 by a year
     of zero taxes while employing.
   - **Matching.** First the company's address code against a building's or a parcel's (1,069).
     Then its address against the tile's in the same town (1,292): the premises after " - " are
     dropped and alternatives after ";" tried. Companies in flats carry the flat's own code, so
     the address match is the larger half.
   - **Status.** An open insolvency proceeding counts as bankrupt (`N`, distressed). Any row in
     the liquidation file counts as in liquidation (`L`, distressed). A legal-protection
     proceeding stays registered but is on watch, its reason the register status.
     Terminated entities are left out.
   - **Names.** The long legal forms are shortened as a sign writes them ("AS "Citadele
     banka"", "VSIA …"); 10 rows with other forms keep their full name. Sole traders (IK, IND)
     and farms (ZEM) are skipped; `validate_site` now rejects the Latvian sole-trader forms too.
   - **People.** Officers and members are kept as counts and uuid5 hashes of name, masked code
     and birth date, or a company's own number, so `Links` can tie co-owned firms and nothing
     readable is stored.
   - **Figures.** VID has no turnover: `turnover` is the last annual report's
     (`turnover_year`), `taxes` the last year VID has in full (`taxes_year`, the three-year
     file's 2024 until four archived quarters make a later year), and `employees` VID's latest
     quarter. `Tenants.facts` names the year of each figure, "turnover 61 781 €/yr (2025)".
     Banks' income statements carry no net turnover, so they show none.
   - **Left open.** No sector where VID's annual file lacks the company (new firms); no company
     link (the register's public page URL is unverified); a data.gov.lv rename would need the
     file names in `fetch_tenants_lv` updated.
4. **Roofs from the laser points** for buildings without LOD2. Done 2026-09-12
   (`tools/pipeline/roof_fit.py`, called by `fetch_cadastre_lv` for every building no Rīga model
   covers):
   - **Input.** `fetch_tile_lv` keeps the building-class returns as the highest height above the
     ground per metre (`data_raw/lv/<tile>_roofs.r32`).
   - **Fit.** Four candidates on the footprint's minimum rotated rectangle: flat, a gable along
     the long side, a gable across it, and a hip. Each takes its eave from a low percentile near
     the eaves and its ridge from a high one over the whole footprint. The smallest error against
     the cells wins, and a pitched roof has to beat the flat one by 15 %.
   - **When it stays flat.** Footprints under 82 % of their rectangle (L shapes) and roofs with
     less than 0.8 m between eave and ridge keep the flat roof at the measured height.
   - **Faces.** Written as LOD2 faces the engine already draws, wound so the engine's normal
     points up on roofs and out on walls; gable ends are pentagons. Buildings record
     `roof_source: "lod2" | "laser"`.
   - **Checks.** A synthetic house of each kind is recovered as that kind, heights within 0.4 m.
     Valka (the new `sites/valka` pack): 975 buildings, 137 gable along, 72 gable across, 31 hip,
     550 flat. The Old Town: 77 buildings without a model, 12 of them pitched. Screenshots from
     above show the town's houses with gables and hips instead of boxes.
5. **Roads, stops, departures, fields.** Roads, stops and departures done 2026-09-12:
   - **Roads.** `fetch_roads_lv.py` takes the tile's `highway` ways from OpenStreetMap and splits
     each at every node another way shares: the road graph joins edges only at their ends, and an
     OSM way runs through crossings. Paved roads are streets, unpaved ones roads, footways, steps
     and pedestrian streets paths (the Old Town's lanes, so no cars), tracks trails. Widths come
     from `width`, else `lanes`, else a default per class. Old Town: 2,518 segments from 1,442 ways.
   - **Stops.** `fetch_stops.py` was already country-neutral: 7 stops in the Old Town, all on a road.
   - **Departures.** `fetch_departures.py` chooses the feeds by the pack's `country`. For Latvia:
     ATD's regional buses and Rīgas satiksme's newest monthly zip. The GTFS reader now trims the
     padded names and values ATD writes (Pirita's Estonian timetable came out identical). Only
     buses and trolleybuses are kept: the game has no tram or train. Old Town: 132 routes, 2,449
     departures on lines 2 … 63, the night lines and ATD's regional buses. The service fetches
     them in the refine pass, as in Estonia.
   - **Checks.** Screenshots of the streets from above and of a bus at the Grēcinieku iela stop at
     08:00; `make test` green.
   - **Left open: fields.** LAD's declared fields carry only a crop code (`product_code`: 710,
     141, 720 …) and the code list is not among its open datasets. Drawing unknown crops would
     be inventing, so Latvian packs have no fields until the classifier is found. Also left
     open: tram and train routes, and tram stops (`railway=tram_stop`).
6. **Language.** Done 2026-09-12:
   - **Strings.** `assets/i18n/strings.csv` has an `lv` column for all 305 keys; the script that
     wrote it refused a missing key or a changed `%s`/`%d`. New packs get Latvian scaffold strings
     (`new_site.lv_text`); the Estonian packs' stories have no Latvian yet and fall back to
     English (the fallback locale was Estonian, now English).
   - **The switch.** A three-way cycle, Estonian → English → Latvian, in `scripts/ui/lang.gd`, used
     by the main menu's entry (it names the next language), the pause menu and the L key.
   - **Suggestions.** The suggested places carry `note_lv`.
   - **Tests.** `health_test` checks the health reasons in all three languages. The screenshot
     tools take `--locale=lv`.
   - **Checks.** The main menu, the Locations page and Valka's Companies page read in Latvian.
   - **Left open.** A native speaker's review; Latvian for the Estonian packs' place stories;
     register text stays in the register's own language (Estonian building uses in Estonia,
     Latvian in Latvia), with the game's own labels translated around it.
7. **Streaming across the border.** Done 2026-09-12 (`tools/pipeline/cross_border.py`, run by
   every tile-service job after its own registers):
   - **Why.** A tile is built by the country its centre lies in, and each country's registers
     stop at the border. East of Valka the tiles are 16–20 % Estonian: without a merge, Valga's
     streets would stand empty.
   - **What it does.** It measures the tile's share of the other country by the menu map's
     outlines. It runs that country's fetchers (VZD + UR, or Maa-amet + EHR + the e-Business
     Register) in a scratch copy of the pack, and merges the rows whose centre lies on the other
     side: parcels, buildings, companies matched exactly to them, and, for an Estonian pack,
     OpenStreetMap's roads over Latvia.
   - **Ground.** It needs nothing: LĢIA's laser sheets reach about a kilometre into Estonia,
     Valga's centre included.
   - **Result.** The border tile `t620139_6405171` holds 592 Latvian and 144 Estonian buildings
     (the Estonian ones with Maa-amet's LOD2 roofs), 373 + 87 parcels, 124 + 24 companies.
     Starting in Valka and walking east, the streamer fetches it from the service and it loads
     beside Valka; Piiri tn 19, an Estonian care home, stands in it.
   - **Engine.** The building sheet tells the register by the code (a Latvian designation has 14
     digits), not by the pack, since a border tile carries both.
   - **Left open.** Tram and train routes; the timetables on a border tile come from the pack's
     own country only; starter-place bundles for the Latvian places.

Each step bumps `PACK_VERSION` when it adds something the UI reads, and gets a `THIRD_PARTY.md`
row for every source in the same commit.

## More Latvian sources (surveyed 2026-09-11)

A second pass through data.gov.lv, most of it probed with real field names. Samples (37 MB) are in
`data_raw/lv/samples/extra/`. "Person filter" means: keep legal persons only (11-digit codes
starting with 4 or 5).

| # | Dataset | Join | In the game |
|---|---|---|---|
| 1 | BIS construction cases (`bis_jlyakg7hgslonjnwyrwc6w` cases, `bis_tln9s3hrpjlnucmjip9r3g` objects, `bis_04lylzfvt9f25h4divvcfq` new builds), daily CSV, CC0: stage (`Aktuala_stadija`: Iecere … Būvdarbi … Ekspluatācija), kind (new, rebuild, demolition, facade renewal), dates | building cadastral designation, VAR code, lat/lon | scaffolding and a fence while works run; "reconstruction, works since 2025-03". Never show the free-text object name (it can hold names) |
| 2 | Monuments under state protection (`valsts-aizsargajamo-nekustamo-piemineklu-saraksts`, 9,044 rows): value group, typology, dating, in force since, condition | cadastral designations (`;` list; some cells Excel-mangled) | "Monument of national significance, since 1998, condition: good". Titles naming historical people: show only typology and value group |
| 3 | Rīga historic centre plan (`rigas-vesturiska-centra-un-ta-aizsardzibas-zonas-teritorijas-planojums`): UNESCO site and buffer-zone boundaries, 2,408 culturally valuable buildings, lost historic buildings, permitted use | geometry, monument number | the UNESCO line on the map; "culturally valuable building" on the sheet |
| 4 | LĢIA orthophoto cycles 1–5 (1994–99 B/W 1 m, 2003–05 1 m, 2007–08 and 2010–11 0.5 m, 2013–15 0.25 m) from the `LGIA_OpenData_Ortofoto_*_saites.txt` lists; a window is cut over `/vsicurl/` with the `.tfw` beside it (`CPL_VSIL_CURL_ALLOWED_EXTENSIONS=.tif,.tfw`) | coordinates | the plot page's history strip. Strip-stored cycles pull whole rows: a 1 km cut of cycle 5 moves ~120 MB, so cut per plot, as the Estonian strip does |
| 5 | BIS energy certificates (`bis_ygdi8jmgg-bneuijz7wiwq`, 57 columns) and Rīga's heating efficiency of apartment blocks (`rigas-daudzdzivoklu-maju-apkures-energoefektivitates-raditaji`, renovation year and programme) | cadastral designations | an energy class on the sheet, a K-overlay mode. Drop the expert's name |
| 6 | Food businesses (PVD, `pakalpojumi.pvd.gov.lv/lv/opendata_files/ipvd_object_opendata/download`, daily): outlet name, company number, address, activity, last inspection grade; VID excise licences (222 MB CSV): licence kind, address, **opening hours** | address text → VAR, company number | real outlet names on plates and in interiors; shop windows lit by the real hours |
| 7 | TAPIS WFS (zoning `funkcionalais_zonejums`, encumbrances `apgrutinatas_teritorijas`, plans in public discussion); bbox **northing first** in EPSG:3059 | geometry | "Zoning: mixed centre JC8 (Rīga plan 2023)"; a notice when a plan is open for comment |
| 8 | Company distress for the health verdict: UR `suspensions-prohibitions`, `liquidations`, `maksatnespejas-procesi` (insolvency), `securing-measures` (drop the bailiff's name); VID `saimnieciskas-darbibas-apturesana`, `pvn-maksataji` | registration number | "distressed: VID suspended activity 2026-09-10" |
| 9 | Rīga environment-degrading buildings (`vidi-degradejosas-buves-riga`: status, class A/B/C, council decision) and municipal property (`rigas-ipasumi`, with vacant premises for rent or sale) | cadastral designation | grime and boarded windows; a "for rent, 52 m²" sign; a city-owned layer |
| 10 | BIS house files: the manager (company number, period) and repair works per year | building cadastral designation | "Managed by SIA … since 2011; heating repair 2025-10" |
| 11 | Public procurement (IUB daily JSON, `open.iub.gov.lv/data/notice/…`), EU-funds projects (with `KadastraNumurs` for the place) | registration number, cadastral number | "won 3 public contracts, 1.2 M €"; an EU plaque on the plot |
| 12 | LVĢMC observations (`hidrometeorologiskie-noverojumi`): last-hour weather, the Daugava gauge, warnings with polygons | station coordinates (the observation ids need a mapping to the station list) | live rain and temperature, the river level on a quay gauge |
| 13 | CSP small-area statistics: population on a 100 m grid, dwellings per cell, wages by neighbourhood | grid code (probably LKS-92 hectometres; check) | pedestrian density; a neighbourhood page |

Also found: VZD's registered-but-not-found buildings, pre-registered new builds and renamed streets;
Rīga's noise maps, planned resurfacing and poster columns; riga.lv event RSS with places and times;
pharmacies (ZVA live export with WGS84 coordinates). Not open: a tourist-accommodation register,
gambling venues, and the official notices of Latvijas Vēstnesis (HTML only).

Build first, by value against effort: construction cases (1), heritage (2, 3), the orthophoto history
(4), energy (5), outlets and opening hours (6), zoning (7), distress signals (8), degrading and
municipal buildings (9).

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
