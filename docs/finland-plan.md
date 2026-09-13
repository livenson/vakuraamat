# Finland: the third country

**Status (2026-09-13):**
- Sources checked by probe for three places:
  - Helsinki, Senaatintori: ETRS-TM35FIN E 386392, N 6672050; L-EST97 E 552890, N 6670790.
  - Porvoo old town: TM35 426370, 6695926; L-EST97 591774, 6696463.
  - A rural square near Loppi: TM35 360347, 6734322; L-EST97 524030, 6731856.
- **Steps 1–6 are done** (2026-09-13); what each left open is under its step below:
  - 1: ground;
  - 2: plots and buildings;
  - 3: companies;
  - 4: timetables and fields;
  - 5: address search;
  - 6: the menu, with a country picker.

  Step 7, Finnish as a game language, is done too, waiting for a native speaker's review.
  `sites/helsinki_senaatintori` is a shipped pack with every layer.
- **Step 1**, the adapter and the ground:
  - `sources.Finland`, `tools/pipeline/fetch_tile_fi.py`, `assets/data/finland.json` and the
    `fi` descriptor.
  - The Senaatintori tile builds in 81 s from a cold cache.
  - `sites/helsinki_senaatintori` has a manifest and a tile. In the game at 103 fps, the square,
    the cathedral terrace and the harbour stand on the city's 1 m ground under its 5 cm photograph,
    with trees only where the canopy is. There are no buildings yet.
  - There are no registers yet, so `make validate` fails on the pack until step 2. It is not
    committed.
- Work is on the `finland` branch.

The goal is the one Latvia met: a Finnish place that plays like an Estonian one. It uses the same
pack files and the same rule that every figure is a register field. How a country is added is in
[adding-a-country.md](adding-a-country.md). Latvia's plan ([latvia-plan.md](latvia-plan.md)) is the
model for this one.

## Decisions

- **One world grid, L-EST97 (EPSG:3301).** Finnish data is reprojected from ETRS-TM35FIN
  (EPSG:3067), and in Helsinki from ETRS-GK25 (EPSG:3879). The projection is conformal, so a
  tile's shapes are right everywhere and only the scale drifts. Measured with pyproj:

  | Place | Scale error | Grid north turns by |
  |---|---|---|
  | Helsinki | +0.03 % | +0.8° |
  | Turku | +0.04 % | −1.5° |
  | Tampere | +0.12 % | −0.2° |
  | Oulu | +0.65 % | +1.3° |
  | Rovaniemi | +1.0 % | +1.5° |
  | Utsjoki | +2.2 % | +2.6° |

  Tiles still meet exactly, because every tile is cut from the same grid. A building in Oulu is
  0.65 % larger than life. The whole country is covered.
- **Same pack format.**
  - `tunnus` holds the property id as printed, e.g. `91-8-142-4`. The printed form is the one the
    descriptor's `parcel_code` recognises.
  - `ehr` holds the permanent building id (VTJ-PRT), 10 characters, e.g. `103036806X`.
  - The check character of a VTJ-PRT is a digit about a third of the time, and Estonia's
    `building_code` pattern (`^\d{1,12}$`) would claim those. So `Countries.for_building_code` now
    tries the pack's own country first. Border tiles exist only between Estonia and Latvia, and
    Latvia's 14-digit codes never match Estonia's pattern, so nothing changes there.
- **No key.**
  - Every NLS (Maanmittauslaitos) API wants a personal key, which cannot ship in an open-source
    sidecar.
  - The Funet mirror of CSC's Paituli service republishes the NLS open files without one, with
    range requests and a sheet index per product.
  - Everything in step 1 comes from there, or from Helsinki's own open services.
- **Helsinki first.** The city publishes what the national open data lacks:
  - a 1 m ground model (2021);
  - a 5 cm photograph (2025);
  - photographs back to 1932;
  - LOD2 roofs carrying the building id;
  - footprints with register fields;
  - a street-tree register.

  Elsewhere a pack falls back to the national layers.
- **First places:** Helsinki Senaatintori (the city layers), then Porvoo's old town (national
  layers only, a wooden town for the roof fit).

## Ground sources (probed 2026-09-13)

All NLS files are under `https://www.nic.funet.fi/index/geodata/`. Licence: CC BY 4.0 (the NLS
open-data licence). The credit names the NLS, the dataset and the delivery month.

| Layer | Source | Format and access | Licence |
|---|---|---|---|
| Ground model 2 m | `mml/dem2m/dem2m_direct.vrt` (a VRT over `2008_latest/<L4>/<L41>/<L4133D>.tif`) | Float32 GeoTIFF sheets, 6 × 6 km, nodata −9999, N2000 heights. A 1 km window cut over `/vsicurl/` takes 4 s | CC BY 4.0 |
| Ground model 1 m, Helsinki | City WCS `kartta.hel.fi/ws/geoserver/avoindata/wcs`, coverage `avoindata__Korkeusmalli_2021_1m` | `subset=E(...)&subset=N(...)` in **EPSG:3879 only**. A 1.1 km box comes back in 5 s (6.8 MB). Nodata −32767 | CC BY 4.0 (HRI) |
| Laser points, 0.5 p | `mml/laserkeilaus/2008_latest/<year>/<L413>/<n>/<L4133D1>.laz`, index `2008_latest.shp` (35,944 sheets: `label` "L4133D1 (2008)", `path`) | LAZ, 3 × 3 km, 9–63 MB. Details below the table | CC BY 4.0 |
| Laser points, 5 p | NLS MapSite only | **Not open data:** a separate licence, a Suomi.fi strong login, and a €26.69 minimum fee | – |
| Laser points, Helsinki | HRI `helsingin-laserkeilausaineistot` (2015, 2017, 2021) | LAZ in GK25 squares. The download goes through the city's map app; no direct URL found | CC BY 4.0 |
| Orthophoto | `mml/orto/normal_color_3067/<series>/<year>/<L41>/02m/<n>/<L4133D>.jp2`, index `ortho_all.shp` (50,723 sheet-years: `label` "L4133D (2023)", `path`) | JPEG2000, 6 × 6 km, 0.5 m, 1024-px blocks and overviews, 103 MB a sheet. A window over `/vsicurl/` takes 8 s a sheet; they are read side by side. Helsinki 2009, 2014, 2020, 2023; Porvoo 2009, 2013, 2018, 2022, 2025 | CC BY 4.0 |
| Orthophoto, Helsinki | City WMS `kartta.hel.fi/ws/geoserver/avoindata/wms`, `avoindata:Ortoilmakuva_<year>` | 60 layers, 1932 … `2025_5cm`. 4096 px PNG with transparency outside the city in 8 s | CC BY 4.0 |
| Colour-infrared | `mml/orto/infrared_3067/…`, the same layout | Not used | CC BY 4.0 |
| Country outline | Statistics Finland WFS `geo.stat.fi/geoserver/tilastointialueet/wfs`, `tilastointialueet:kunta4500k_<year>` | 308 municipalities, GeoJSON. Also tells a tile's municipality: Helsinki is `091` | CC BY 4.0 |
| LOD2, Helsinki | City CityGML (`kartta.hel.fi/3d/citydb-wfs/wfs`; per-area zips on `3d.hel.ninja`) | EPSG:3879, `RoofSurface`/`WallSurface`, attribute `Rakennustunnus_(VTJ-PRT)`. The WFS answered 403 "overloaded" on every GetFeature. Only Kalasatama is a listed zip. `3d.hel.ninja`'s certificate has expired | CC BY 4.0 |
| LOD2, elsewhere | Kuopio CityGML, Turku and Espoo WFS (listed only); NLS "Rakennukset 3D" (a few sample areas) | Roofs are fitted to the laser points (`roof_fit.py`) where no model exists | CC BY 4.0 |
| Single trees, Helsinki | City WFS `avoindata:Puurekisteri_piste` | 66,383 city trees: genus, species, trunk-size class, planting year | CC BY 4.0 |

**Laser sheets, as read:**
- The 2008 Helsinki sheet is LAS 1.0 with **no CRS**, so it is taken as TM35 from the index.
- It holds 0.56 points a square metre, in classes 1, 2, 3, 7, 9 and 10. There is **no building
  class**.
- Class 9 is water, as in ASPRS; Latvia uses 14.
- Sheets from 2020 on are thinned from the 5 p scans and carry EPSG:3067.
- The mirror's newest year is 2022. Helsinki's newest open sheet is from 2008.

## Register sources (probed 2026-09-13)

No key is needed anywhere below.

| Layer | Source | Format and access | Licence |
|---|---|---|---|
| Cadastre, geometry | NLS INSPIRE WFS `inspire-wfs.maanmittauslaitos.fi/inspire-wfs/cp/ows`, `cp:CadastralParcel` | GML 3.2, bbox with **easting first** in `urn:ogc:def:crs:EPSG::3067`. Helsinki box: 278 parcels. Details below the table | CC BY 4.0 |
| Cadastre, Helsinki | City WFS `avoindata:Kiinteisto_alue` (parcels) and `avoindata:Kaavayksikot` (plot units) | Plot units carry **building rights in k-m² (`rakennusoikeus`)** and the zoning use class, in 256 of 346 | CC BY 4.0 |
| Parcel value | none | Sale prices per deal are licensed (the purchase-price register), and property-tax values are not public in bulk | – |
| Market | Statistics Finland PxWeb `pxdata.stat.fi/…/StatFin/ashi/13mt` | Flat prices in €/m² and deal counts **per postcode, quarterly**, 2009–2026 | CC BY 4.0 |
| Buildings | Ryhti (SYKE) OGC API `paikkatiedot.ymparisto.fi/geoserver/ryhti_building/ogc/features/v1/collections/open_building/items?bbox=…` | GeoJSON **points**, 3.8 M buildings. Details below the table | CC BY 4.0 |
| Footprints, Helsinki | City WFS `avoindata:Rakennukset_alue_rekisteritiedot` | Polygons with `vtj_prt`, completion date, floors, the fine use code `c_kayttark`, floor area, material, property id | CC BY 4.0 |
| Footprints, national | NLS topographic database on the mirror, `maastotietokanta/2025/gpkg/MTK-rakennus_*.gpkg` | 4.1 GB for the whole country, no VTJ-PRT. Ryhti's points are placed into these footprints, or OpenStreetMap's | CC BY 4.0 |
| Addresses | Ryhti `open_address` | 3.86 M points in Finnish and Swedish, number range, postcode, `building_key`. The key-free geocoder is our own index of these, as Latvia's `geocode_lv.py` indexes VARIS | CC BY 4.0 |
| Companies | PRH `avoindata.prh.fi/opendata-ytj-api/v3/all_companies` | Daily zip, 96 MB, 463,594 rows. Details below the table | CC BY 4.0 |
| Company tax | Vero `yhteisö_tuloverotus_julk_<year>.csv` (list on vero.fi's open-data page) | Yearly, published each November: 2024 came out 2025-11-11, 384,627 rows. ISO-8859-1, `;`, decimal comma. Details below the table | CC BY 4.0 |
| Turnover | PRH XBRL API `avoindata.prh.fi/opendata-xbrl-api/v3/` | Digital statements, about 2.5 % of companies. Coded facts that need the SBR taxonomy | CC BY 4.0 |
| Staff | none found | – | – |
| GTFS | HSL `infopalvelut.storage.hsldev.com/gtfs/hsl.zip` (79 MB, daily); Waltti city feeds | Porvoo's buses are not in any open feed found | CC BY 4.0 |
| Fields | Ruokavirasto INSPIRE WFS `inspire.ruokavirasto-awsa.com/geoserver/wfs`, `LandUse.ExistingLandUse.GSAAAgriculturalParcel.<year>` | Crop code `KASVIKOODI` **with its name** (`KASVIKOODI_SELITE_FI`), area, organic flag. 2020–2025 | CC BY 4.0 |

Details for the register rows:
- **NLS cadastre fields.** `label` is the printed property id `91-8-142-4` and
  `nationalCadastralReference` the 14-digit one. Area, land use and value are not there.
- **Ryhti building fields:**
  - identity: VTJ-PRT, the property id, `building_key`;
  - dates: completion date, usage status, demolition date;
  - size: storeys, gross and floor area, volume, apartments;
  - build: facade and frame material, heating and energy source;
  - status: `is_protected` and cultural-historical significance.

  The open use code has only 7 classes. In the Helsinki box, 372 of 374 buildings have a year and
  361 have storeys.
- **PRH company fields:**
  - identity: business id (Y-tunnus), name history, company form, registration date, status;
  - sector: TOL 2008 code (NACE), in 460,526 rows;
  - addresses: visiting and postal, as street, number and postcode;
  - distress: liquidation, bankruptcy and restructuring (`companySituations`).

  Sole traders are not in it.
- **Vero columns:** tax year, business id, name, municipality, taxable income, tax charged,
  refund, tax still owed.

**Keys that tie it together:**
- **The property id** is the same value in all of these:
  - the NLS cadastre;
  - Helsinki's parcels and plot units;
  - Ryhti's `property_identifier`.

  It is written as 14 digits (`09100801420004`) or printed (`91-8-142-4`).
- **The VTJ-PRT** joins:
  - Ryhti buildings;
  - Helsinki's footprints and address points;
  - the Helsinki LOD2 models;
  - Ryhti's building permits.

  350 of the 374 Ryhti buildings in the Helsinki box have a city footprint.
- **The business id** joins PRH, Vero and XBRL.
- **A company reaches a building by its address text:** street, number and postcode against
  Ryhti's addresses. In the Helsinki box that places 5,689 companies; in the Porvoo box 1,186.

## From sources to pack files

| Pack file | Filled from | Notes |
|---|---|---|
| `heightmap.r32` | NLS 2 m model, bilinear to 1 m; Helsinki's 1 m model where it has data | Done (step 1). `dtm_res_m` is 1 where the city's model covers 90 % of the tile, else 2. The descriptor's `"refine": "flag"` means a 2 m ground is not taken for a coarse one. Outside the model is the sea, at 0 m. Tiles meet through Latvia's `blend_edges`. Under buildings, Helsinki's model is a triangulation, flat and faceted |
| `canopy.r32` | NLS 0.5 p laser points | Done (step 1). Details below the table |
| `ortho.jpg` | the newest NLS sheet per 6 km square; Helsinki's 5 cm photograph over it inside the city | Done (step 1) |
| `ortho_<year>.jpg` | the older NLS years (up to 6); in Helsinki six of the city's, spread from 1932 to 2015 | Done (`fetch_tile_fi.add_history`, the refine pass): 8 s for Senaatintori. The plot page's strip shows the block's outline on the same courtyard in every year |
| `parcels.json` | NLS INSPIRE parcels (+ Helsinki's plot units) | `land_value` null: there is none. In Helsinki, `building_right_m2` and the zoning class instead (a new optional field the book would show) |
| `market.json` | StatFin `13mt` postcode flat prices | Labelled as statistics, not valuations |
| `buildings.json` | Ryhti + footprints (Helsinki's, else MTK or OSM) + LOD2 in Helsinki, `roof_fit.py` elsewhere | Details below the table |
| `tenants.json` | PRH bulk by address, Vero by business id, XBRL where filed | Details below the table |
| `roads.json`, `stops.json` | OpenStreetMap (`fetch_roads_lv.py` is OSM-generic), `fetch_stops.py` | ODbL, as in Latvia |
| `departures.json` | HSL and Waltti GTFS | `fetch_departures.py` takes a feed list per country. HSL has trams and a metro: keep buses only, as in Latvia |
| `fields_2026.json` | Ruokavirasto crop parcels | The crop names come with the rows; a table from `KASVIKOODI` to the game's crops |

Details for the table rows:
- **`canopy.r32`:**
  - It is the highest return per metre above the ground. Empty metres (about half, at 0.5 points
    a square metre) take their neighbours' highest.
  - The sheets have no building class, so trees are told from roofs by the pulse: a pulse
    through foliage comes back more than once, and off a roof once.
  - A metre is canopy when at least 30 % of the returns over 2 m in its 7 m square came from
    split pulses. In Senaatintori's tile that keeps 13 % of the tile out of the 47 % the surface
    covers.
  - The full surface, roofs included, is kept as `data_raw/fi/<tile>_surface.r32` for the roof
    fit.
  - Helsinki's trees are from 2008.
- **`buildings.json`:**
  - `year` from the completion date, `floors` from the storeys, `purpose` from Helsinki's
    `c_kayttark` where present, else Ryhti's 7 classes.
  - Also materials, heating, and the protection flag.
- **`tenants.json`:**
  - Legal persons only.
  - Housing companies (asunto-osakeyhtiö, 92,686) and mutual property companies own the building
    itself: a kind of their own, not a business.
  - `taxes` and `taxable_income` are yearly.
  - No `employees` and no quarterly figures. The health rules must work without staff counts.

## What is missing and how to cover it

| Gap | Fix |
|---|---|
| No parcel value | Show what exists: building rights and zoning in Helsinki, postcode flat prices in `market.json`. Never a guessed value |
| No staff counts | Leave `employees` null. The map's size mode needs a fallback (tax charged, or none) |
| Only yearly taxes | `Tenants.facts` already names a figure's year |
| No building class in the open laser sheets | Trees from roofs by split pulses (done); footprints mask the rest |
| Old, thin laser points (Helsinki 2008) | Helsinki's own 2021 LAZ once its file URLs are known; the NLS 5 p is not open |
| Buildings are points | Footprints from Helsinki, the NLS topographic database, or OpenStreetMap |
| Only 7 open use classes | Helsinki's fine code; elsewhere the MTK class or OSM `building=` |
| Porvoo has no open timetable | Stops without departures |
| NLS APIs need a key | Everything from the Funet mirror and the cities; the geocoder is our own index of Ryhti addresses |

## Engine changes

Done:
- `Countries.for_building_code` tries the pack's country first.
- `PlaceSearch.FOLD` folds å.
- The descriptor, `COUNTRY_FI`, `UI_SHEET_REGISTER_FI` and `UI_SHEET_CODE_FI`.
- `countries_test` has Finnish examples.

To do:
- **The menu map.** It fits every outline on one plate, and Finland is 1,160 km tall against
  the Baltic states' 470 km, so Estonia and Latvia shrink. The map should frame the places it
  shows, or stop at Finland's south.
- **Swedish.** Every Finnish address has a Swedish form (Senatstorget). The search should match
  both.

## Language

- Finnish is not a game language yet. Adding `fi` to `Lang.LOCALES` and a `fi` column to
  `strings.csv` is its own step, done the way Latvian was (step 6 of the Latvian plan).
- Register text stays in the register's language. Ryhti and PRH give Finnish and Swedish;
  English for company forms.

## Steps

1. **Adapter and ground.** Done 2026-09-13.
   - **Adapter.** `sources.Finland`, tested after Latvia and before Estonia. A point is Finnish
     on Finland's land by the outline, or where the NLS has an orthophoto sheet (the outer
     skerries), and never on another country's land. Checked: Helsinki, Porvoo, Loppi,
     Mariehamn and Utsjoki are Finland. Tallinn, Valga and the islet Vaindloo are Estonia, Rīga
     and Valka are Latvia, and the open Gulf of Finland is nobody's.
   - **Ground.** `fetch_tile_fi.build_tile`: the ground, the canopy, the orthophoto and the
     meta, as above. `add_history` does the older photographs for the refine pass.
   - **Outline.** `fetch_outline.py --country fi --min-island 40` writes
     `assets/data/finland.json` (19 rings, 14 kB). The archipelago's many small islands inked the
     south-west coast black on the menu map; the skerries are still Finnish through the
     orthophoto-sheet test. The menu's credit line names Maanmittauslaitos and Statistics Finland.
   - **Dependencies.** `laspy` and `lazrs` in `tools/service/requirements.txt` and the sidecar
     spec.
   - **Service.** `Finland.registers` raises until step 2, so the menu cannot make a Finnish place
     yet.
2. **Cadastre and buildings.** Done 2026-09-13 (`tools/pipeline/fetch_cadastre_fi.py`, also a
   stage of the service's Finnish job). Senaatintori's tile takes 5 s.
   - **Plots.**
     - The NLS INSPIRE WFS in JSON. A property split into parts (the public areas, `91-2-9901-0`
       in 4 pieces) is one row: the largest part's outline, the parts' summed area, `parts`.
     - In Helsinki the city's plot unit is joined by the 14-digit id, else by an overlap over
       half. It adds the zoning class (AK homes, K business, Y public, L streets, V green,
       W water, T industry, E utilities: the game's plot classes) and `building_right_m2` with
       its `zoning_plan`.
     - `land_value` is null, and the file's `valuation.field` null says so; the validator no
       longer warns about it.
     - The book's plot page shows "Building right: 24400 m² of floor area (zoning plan 12936)"
       where there is one.
     - Result: 281 plots, 250 with a building right, all but 2 with a class.
   - **Buildings.**
     - Ryhti through its OGC API (text fields, `avoimet_rakennukset`, and `open_address` for the
       Finnish and Swedish addresses, all kept so either finds a building).
     - Footprints in Helsinki: the city's register polygons joined on the VTJ-PRT. That keeps the
       361 whole buildings among 4,114 polygons; the rest are stairs, oriels, canopies.
     - Footprints elsewhere: the NLS topographic database's building polygons (`r_<sheet>_p`,
       classes `422xx`) from the Funet mirror, each taking the Ryhti point inside it. A 24 km
       sheet comes as an L and an R zip of 12 km (the 6 km sheets A–D and E–H).
     - `id` is the VTJ-PRT's nine-digit serial; `ehr` the whole identifier.
     - `kind`: Helsinki's use code and type first, then Ryhti's 7 classes, then the topographic
       class.
     - Also `purpose` (Helsinki's type, e.g. "Liikerakennus", or Ryhti's class), year, storeys,
       facade, frame, heating, floor area, volume, apartments, the protection flag as `monument`,
       and the plot as `cadastral`.
     - Roofs: `roof_fit.py` on `_surface.r32`, which has no building class, so a tree over a
       roof is part of the fit.
     - Senaatintori: 344 buildings, 343 with a Ryhti record, 341 dated; 52 pitched roofs, 287 flat.
   - **Roads and stops.** OpenStreetMap through `fetch_roads_lv.py`, which works for any country
     (5,931 segments) and now takes the credit as a parameter; 14 bus stops.
   - **TLS.** The NLS and SYKE certificates chain to Telia Root CA v2, which macOS's
     `/etc/ssl/cert.pem` lacks. The Finnish fetchers use certifi's roots, as the sidecar does.
   - **Checks.** `make validate` is clean. In the game, at 95 fps:
     - the square stands among the blocks at their measured heights;
     - looking at a building shows "Toimistorakennus · in use since 1858 · 3 floors";
     - the plot page shows the building right.
   - **Left open.**
     - Helsinki's 3D models: the WFS answers "overloaded" or nothing, and only Kalasatama has a
       zip. The cathedral is a flat block until they can be read.
     - Ryhti marks 204 of the 374 central buildings "Tyhjillään" (vacant). It is the register's
       field, so `status` keeps it.
     - The split-pulse test takes the Alexander II statue for a tree.
3. **Companies and money.** Done 2026-09-13 (`tools/pipeline/fetch_tenants_fi.py`, a stage of the
   service's Finnish job):
   - **Register.** PRH's daily bulk, one 1.45 GB JSON array in a 96 MB zip, is streamed once per
     download into a slim file of what a tile needs: 440,753 companies with a street address, in
     12 s. It is refreshed after a week.
   - **Matching.** A company's visiting address, else its postal one, against the tile's building
     addresses: every Finnish and Swedish form Ryhti gives, by street and house number (`13 A` is
     `13a` then `13`; `16-18` also covers 17). The municipality code must be one of the tile's.
     Plot addresses are tried next, then "street" for a number outside the tile.
   - **Kept.**
     - Legal persons doing business. The open bulk has no sole traders at all.
     - Housing companies (asunto-osakeyhtiö) and mutual property companies are left out: they
       own the building rather than trade in it. The stats count them: 565 and 957 in
       Senaatintori's tile.
     - Dissolved companies (`endDate`) are skipped.
   - **Figures.**
     - `taxes` is Vero's tax charged for `taxes_year` (2024, the newest year, published
       2025-11-11), found by name on vero.fi's open-data page. `taxable_income` sits beside it.
     - No staff count is published, so `employees` is null. `turnover` is null until the XBRL
       statements are read.
     - `link` is the company's YTJ page.
     - The sector comes from the TOL 2008 code, NACE with a fifth digit like EMTAK, with its
       Finnish text.
   - **Health.** From the register's situations alone:
     - bankruptcy (`KONK`) and liquidation (`SELTILA`) are distressed;
     - restructuring (`SANE`) is watch.
   - **Validator.** It accepts a Finnish business id (`0112038-9`) as `registry_code`.
   - **Result, Senaatintori.** 21 s for 8,462 companies: 5,576 exact, 2,886 on the tile's
     streets.
     - 6,464 are in Vero's file, 2,643 of them paying tax.
     - 247 distressed, 3 on watch.
     - Largest sectors: services 2,351, finance 2,334 (holding companies), property 742,
       media 714, trade 603.
     - The biggest taxpayers are Solidium, Small Giant Games, SEB's Helsinki branch, Mandatum and
       Nordea Life.
     - Kämp Oy is at Ludviginkatu 6 in hospitality. The file is 7.4 MB, against Rīga's 4.5 MB.
   - **Left open.**
     - Turnover from the XBRL statements (2.5 % of companies, coded facts).
     - The map's employees mode has nothing to size by.
     - The book's Companies page shows Employees and Turnover, both dashes in Finland, and sorts by
       employees first. It needs a Taxes column, which Finland fills.
     - Archive each day's bulk, since a dissolved company drops out of it.
4. **Departures and fields.** Done 2026-09-13. Roads and stops came with step 2.
   - **Departures.** `fetch_departures.fetch_feeds` is Latvia's reader, generalised to a feed list
     and a set of route types. `fetch_fi` reads HSL's GTFS (79 MB, daily, CC BY 4.0), buses only
     (route types 701, 702 and 704; trams, metro, trains and ferries left out).
     - It streams the 990 MB `stop_times.txt` in 10 s.
     - Senaatintori: 10 stops, 106 routes, 7,210 departures. The service fetches them in the
       refine pass.
     - Outside HSL's region nothing is read yet. Porvoo's buses are in no open feed found; the
       Waltti cities (Turku, Tampere, Oulu …) are their own feeds, to add to `FI_FEEDS`.
   - **Fields.** `tools/pipeline/fetch_fields_fi.py`, a stage of the service's job: Ruokavirasto's
     crop parcels of the newest year published (2025; the 2026 layer answers 400 until it is out).
     The crop's Finnish name comes with each row, so the game's kind is read from it (`kesanto`
     fallow, `nurmi` grass, `ohra` cereal, `rypsi` rape …). A test tile by Loppi: 4 parcels of
     feed grass (Rehunurmi).
5. **Address search.** Done 2026-09-13 (`tools/pipeline/geocode_fi.py`, `Finland.geocode`, the
   service's `/geocode?country=fi`).
   - **No index to build.** Ryhti's addresses come only through its API (3.86 M, about 3.5 GB as
     GeoJSON), and there is no bulk file.
   - **Places are local:** the municipalities and Statistics Finland's 3,026 postcode areas, in
     Finnish and Swedish, the joined names split into their districts ("Helsinki keskusta -
     Etu-Töölö").
   - **Addresses are live:** a name-prefix filter on Ryhti's WFS (`CQL_FILTER`, about 2 s),
     narrowed to a post office when the query has a town after a comma.
   - **Results:**
     - "Aleksanterinkatu 15, Helsinki" finds the building.
     - "Kruununhaka" finds the district.
     - "toolo" finds Taka-, Keski- and Etu-Töölö.
     - "Alexandersgatan 1" finds the Swedish addresses of Loviisa and Kaskinen.
6. **Menu.** Done 2026-09-13, except the starter bundles.
   - **Suggestions.** Five Finnish places in `assets/data/suggested_places.json`, with notes in
     Estonian, English and Latvian: Porvoo's old town, Turku cathedral, Old Rauma, Tampere's
     Tammerkoski and Suomenlinna. Every suggestion now carries its `country`, by the adapters'
     exact test (14 Estonian, 6 Latvian, 5 Finnish). Helsinki Senaatintori is a shipped pack.
   - **Country picker.** A picker beside the Locations search: all countries, Estonia, Latvia,
     Finland. It is remembered in `user://played.cfg` (`[menu] country`); the first time it is the
     current world's country.
     - The search asks only that country's register (`Locator.geocode(q, country)`), which is also
       quicker than asking three one after another.
     - The field's example is the country's (`search_example` in the descriptors).
     - The ideas are that country's.
     - The map frames the country (`EstoniaMap.frame`): its outline's bounds with a margin,
       neighbours clipped, other countries' marks hidden.
     - "All countries" shows the whole plate, where Finland is two and a half times as tall as the
       Baltic states.
   - **Strings.** `MENU_OUTSIDE_ESTONIA` names the three countries; the search hint explains the
     picker.
   - **Left open.** The starter bundles: `starter_places.py build` makes Senaatintori's eight
     neighbours on the service, and `publish` uploads them to a GitHub release, which waits for the
     maintainer.
7. **Finnish as a language.** Done 2026-09-13, drafted without a native speaker.
   - **Strings.** `assets/i18n/strings.csv` has a `fi` column for all 342 keys. The script that
     wrote it refused a missing key or a `%s`/`%d`/`%%` that differs from the English, and checked
     the other columns read back unchanged.
     - Terms: a plot is a tontti, a cadastral unit a kiinteistö, a sector a toimiala, the health
       verdicts kunnossa / seurannassa / vaikeuksissa.
     - The building right reads "Rakennusoikeus: 24400 k-m² (asemakaava 12936)".
   - **Switch.** `Lang.LOCALES` is Estonian → English → Latvian → Finnish, named "Suomi";
     `project.godot` registers `strings.fi.translation`. Godot starts from the system locale, so a
     Finnish system opens in Finnish.
   - **Packs.**
     - The three adapters' codex texts have Finnish, and `new_site.fi_text` writes a pack's
       Finnish scaffold column beside `lv_text`'s.
     - Helsinki's pack strings were rebuilt with it.
     - The Estonian and Latvian packs have no Finnish column. `Sites.display_name` now falls back
       to English, then Estonian, instead of showing the raw key: in Finnish the Locations page
       listed "SITE_RIGA_VECPILSETA". The same was true of the Estonian packs in Latvian.
   - **Other text.** The suggested places carry `note_fi`. `health_test` checks the health reasons
     in every language of `Lang.LOCALES`, Finnish included.
   - **Fonts.** EB Garamond and IBM Plex Sans carry ä, ö and å; nothing to do.
   - **Left open.**
     - A native speaker's review, especially the book's voice.
     - Finnish for the Estonian and Latvian packs' place stories.
     - Register text stays in the register's language, as in Latvia: Finnish (and Swedish) in
       Finland, with the game's own labels translated around it.

Each step gets a `THIRD_PARTY.md` row per source in the same commit, and bumps `PACK_VERSION`
when it adds something the UI reads.

## Open questions

- **Helsinki's 2021 laser files.** A direct URL behind the map app would replace 2008's thin
  points in the city.
- **The Helsinki 3D WFS** answered 403 "overloaded". Are the per-area CityGML zips listed
  anywhere besides Kalasatama?
- **Housing companies**: show them as the building's owner, not as tenants?
- **What the book shows instead of a land value**: building rights and zoning, or nothing.
