# Other countries: open data for a pack

Which countries publish the open data a Vakuraamat pack is built from, and how close each comes
to Estonia. The research dates from 2026-09-11. Four research passes covered about 35 countries,
and several ran out of web searches partway through, so any cell marked *(u)* is unverified: it
comes from memory, or from an official page whose licence could not be read. Treat those cells as
leads to confirm before building a pack. Latvia was built afterwards; [what building it taught
us](#latvia-what-the-research-got-right-and-wrong) shows how far the research can be trusted.

How a country is added is in [adding-a-country.md](adding-a-country.md); Latvia's own plan and
sources are in [latvia-plan.md](latvia-plan.md).

## What a pack needs

| Key | Layer | What the game does with it | Needed? |
|---|---|---|---|
| A | Terrain (1 m, from laser scans) and orthophoto | the ground, its colours, trees and roof heights from the laser | yes |
| B | Parcels, ideally with a value | plots, their owners' kind, land value | yes; the value is what makes the market |
| C | Building register (year, floors, use) | buildings' height, age, use and interiors | yes |
| D | 3D roofs (LOD2) | real roof shapes | no: roofs can be fitted to the laser points (Latvia step 4) |
| E | Single trees | measured trees | no: the laser canopy and a scatter stand in |
| F | Company register | who is registered on a plot | yes |
| G | Company money: taxes, turnover, employees per company | the economy, company health | the core of the game; rarest by far |
| H | Timetables (GTFS) | buses and departures | no |
| I | Field parcels (Europe); shop and place lists (elsewhere) | fields; "who is in this building" | no |

Status in the tables: **Y** free, bulk or API, commercial reuse allowed · **P** partial ·
**$** paid · **N** none · *(u)* unverified.

Two constraints apply beyond the data:

- **Licence.** The packs are open source, so every source must allow commercial reuse and
  redistribution: CC BY 4.0, CC0, or a national equivalent. Non-commercial and no-derivatives
  licences rule a source out (see [the traps](#licence-traps-and-other-blockers)).
- **The grid.** Everything is built on L-EST97 (EPSG:3301), a conformal projection centred on
  24°E. Measured with pyproj, its grid north is within 1.1° of true north and its scale within
  0.25 % across the Baltic states and southern Finland. Beyond that it drifts: scale is 0.65 % off
  at Oulu and 1 % at Rovaniemi; grid north turns 2–6° across Slovakia (scale 1.4–1.6 % off),
  8° at Prague and 10–12° across Denmark. Anywhere much further away needs a per-country grid
  first, which is a larger change than an adapter.

## Summary

| Country | Fit | Strongest | What is missing or blocked |
|---|---|---|---|
| **Estonia** | built | every layer; quarterly taxes, turnover and staff per company | none |
| **Latvia** | built | taxes, social tax and staff per company (quarterly, CC0); cadastre with a value on every parcel; laser points | LOD2 outside Rīga (fitted from the laser instead); turnover only from annual reports |
| **Lithuania** | very close | taxes paid **monthly** per company, monthly headcount and average wage (Sodra), revenue and profit; buildings; parcels | laser data needs a signed licence per package; parcel value *(u)* |
| **Denmark** | close | 5 years of taxable income and tax per company (bulk CSV), every XBRL annual report, BBR building register, CVR with owners | valuations by application and stale since 2013; free account; grid far from 24°E |
| **Finland** | being built ([plan](finland-plan.md)) | annual tax per company (CSV), Ryhti building register (open since 2025), key-free ground from the Funet mirror, Helsinki's own 1 m ground, 5 cm photos back to 1932, LOD2 | no turnover or staff per company; no parcel value; open laser points thin (0.5 pts/m²) |
| **Slovakia** | close on money | corporate income tax per company quarterly, VAT liability, full financial statements by API | no building register, no LOD2, no parcel value, no staff counts |
| **France** | good, no taxes | national laser data by end 2026, sale prices per parcel (DVF), BDNB buildings, annual accounts (INPI), staff bands | about 45 % of accounts confidential; no official LOD2; grid |
| **Belgium** | good on money | the national bank's accounts for nearly all companies, with staff counts, daily bulk | parcel values not open; three regions, three sets of sources; grid |
| **United Kingdom** | good on money | all company accounts in bulk (iXBRL), average staff mandatory; business rateable values | small companies omit turnover; parcels without addresses; no open orthophoto |
| **Luxembourg** | good, small | every geo layer open incl. national LOD2; accounts XML | one small country; CC BY-SA on accounts |
| **Slovenia** | good on land | laser data, cadastre and a market value for every property (CC BY 4.0) | company accounts one at a time; tax lists published as images |
| **Czechia** | fair | geodata, building register, bulk register with staff bands | accounts mostly scanned PDFs; no land value exists |
| **Norway** | fair | register with staff counts, latest-year key figures for every filer | tax lists login-only; orthophoto not open for commercial use |
| **Sweden** | fair | CC0 geodata, bulk register, weekly iXBRL accounts (near-complete from 2027) | no bulk tax data; building attributes not open |
| **Netherlands** | land only | laser data, national LOD2 (3DBAG), BAG buildings, national GTFS | company data deliberately anonymised; WOZ values one at a time |
| **Switzerland** | land only | laser data, national LOD2, GWR building register | private company accounts are not public at all |
| **Germany** | land only | laser data, LOD2 and parcels, collected Land by Land | company register capped at 60 lookups an hour, no bulk |
| **Austria** | fair | laser data, cadastre, field parcels | no building register; company API by application |
| **Spain** | land only | the richest building data (year, floors, use per building), laser data, GTFS | accounts paid per document; cadastral value withheld |
| **Poland** | fair | laser data, LOD2 in 10 voivodeships, register with board and owners | per-record access only; tax list for large companies only |
| **South Korea** | best outside Europe | an official land price on every parcel, building register API, every shop with coordinates, monthly headcount and pension (a payroll proxy) per workplace | 5 m terrain only; no open company register; grid |
| **Japan** | 3D only | PLATEAU LOD2 in about 300 cities, full company-number dump | no parcel values; no private company money |
| **US, Australia, Brazil** | city by city | New York, Sydney, São Paulo each have an Estonia-grade kit | nothing national; no private company money |
| **Weak** | – | – | Iceland, Portugal, Italy, Croatia, Ireland, Israel, Taiwan, Singapore, New Zealand, Canada, Georgia, Ukraine |

**The rare layer.** Company money (G) is what sets Estonia apart, and almost nobody else publishes
it: taxes paid per company come only from the Baltic states, Finland, Denmark and Slovakia. Parcels,
buildings, terrain and company registers are open across most of the EU, and the EU rules below
keep raising that floor.

**The next pack.** Lithuania is the nearest: everything Latvia has, with monthly money data. Its
one blocker is the laser licence, which needs a request, not code. Finland and Denmark follow,
each with an estimate for what is missing. Slovakia and the Western European countries need the
per-country grid first.

## Company money compared

The layer the game is built around, side by side. "Staff" means an employee count per company.

| Country | Taxes paid | Turnover | Staff | Cadence | Licence |
|---|---|---|---|---|---|
| Estonia | yes | yes | yes | quarterly | open |
| Latvia | yes, incl. VAT, income and social tax | annual reports (daily CSV) | yes | quarterly (latest quarter only; archive it) and 3-year annual | CC0 |
| Lithuania | yes (VMI) | revenue and profit (Registrų centras) | monthly headcount and average wage (Sodra, employers over 3 staff) | monthly | CC BY 4.0 (Sodra *(u)*) |
| Slovakia | corporate income tax, VAT liability, debts, tax reliability | full statements (RÚZ API) | no | quarterly | CC BY 4.0, free key |
| Denmark | taxable income and tax, 5 years | XBRL reports (small firms often gross profit only) | *(u)* | annual | public |
| Finland | taxable income and tax | iXBRL for about 5 % of companies | no | annual (November) | CC BY 4.0 |
| Belgium | no | accounts for nearly all companies (small ones: gross margin) | yes (social balance sheet) | daily bulk | *(u)* |
| United Kingdom | no | accounts in bulk (small companies may omit it) | yes, mandatory | daily and monthly | free reuse |
| France | no | INPI accounts, about 45 % confidential | size bands (SIRENE) | continuous | Licence Ouverte 2.0 |
| Luxembourg | no | accounts XML | *(u)* | quarterly | CC BY-SA 4.0 |
| Norway | tax lists: login, no bulk | latest-year key figures | yes | annual | NLOD |
| Sweden | on request only | weekly iXBRL (complete from 2027) | in reports | weekly | free |
| Poland | companies over €50 M revenue only | per company, no bulk | no | annual | public |
| Czechia | no | scanned PDFs | size bands | – | open |
| South Korea | no | audit reports (documents) | monthly headcount and pension bill per workplace | monthly | unrestricted |
| Australia | companies over A$100 M | same | employers of 100+ (WGEA) | annual | CC BY |
| Netherlands, Germany, Switzerland | no | anonymised, per record, or not public | no | – | – |

**Parcel values** are almost as rare: Estonia, Latvia, Slovenia (market value per property), South
Korea (official land price per parcel), New South Wales (land value per property), New Zealand
(councils that opted in) and New York (assessed value per lot). The stand-ins elsewhere are sale
prices (France's DVF), zonal land values (Germany, per Land *(u)*) and commercial rateable values
(the UK and Ireland).

## Latvia: what the research got right and wrong

Latvia was built from this research in September 2026 ([latvia-plan.md](latvia-plan.md)). The
research was right about every layer, and wrong in the direction of caution:

- **Company money is better than it said.** The research had VID's bulk files as unverified. They
  exist: one CSV of the latest quarter (taxes, VAT, income and social tax, average staff; 153,951
  rows for 2026 Q2) and a 3-year annual file with NACE codes, both CC0. The quarterly file is
  replaced each quarter, so the history has to be archived from now on. There is no turnover in
  it: turnover comes from the annual reports.
- **The ground took more work than it said.** The ready-made terrain is a 20 m grid, the LAZ files
  are refused (403), and the LAS sheets average 173 MB. So the pipeline grids its own 1 m ground
  from the points, and places a new world on one sheet so it downloads one instead of four.
- **LOD2 exists after all, in Rīga only**: the city's own models (CC BY 4.0), triangle meshes
  without attributes. Elsewhere roofs are fitted to the laser points.
- **The cadastre marks water**, which cleared the moored ships from the Daugava's orthophoto.
- **Dated changes**, all to watch: sale prices are published only until the end of 2026; state
  data moves from LKS-92 to LKS-2020 on 2026-10-01; the next VID quarter is due around
  mid-November 2026.

The lesson for the next country: the verified cells held, and the unverified ones were more
often better than feared than worse. The engineering (grid, file sizes, formats) is where the time
goes, and none of it shows in a layer table.

## Nordic and Baltic countries

### Lithuania

| Layer | Status | Source | Licence | Note |
|---|---|---|---|---|
| A | P | [geoportal.lt](https://www.geoportal.lt/geoportal/web/en/open-data) | mixed | Orthophoto sheets can be downloaded. Laser data cannot: packages are built, a licence is signed per package, then approved. Not listed as open data |
| B | Y (value *(u)*) | [Registrų centras cadastral parcels](https://data.gov.lt/datasets/2831/) | CC BY 4.0 | JSON per municipality, whole country |
| C | Y | [Registrų centras buildings](https://data.gov.lt/datasets/1812/) | CC BY 4.0 | Purpose, floors, areas, year built and modernised, energy class; quarterly. Link to addresses *(u)* |
| D, E | N *(u)* | – | – | |
| F | Y | Registrų centras legal-entity register | CC BY 4.0 | Shareholders not open *(u)* |
| G | **Y** | [VMI taxes paid per company](https://data.gov.lt/datasets/673/); [Sodra employer data](https://atvira.sodra.lt/imones/rinkiniai/index.html); [Registrų centras P&L](https://data.gov.lt/datasets/1666/) | CC BY 4.0 (Sodra *(u)*) | VMI monthly per company code. Sodra: monthly insured staff and average wage, employers over 3 staff. Revenue and profit from 2015 |
| H | P *(u)* | City GTFS (Vilnius, Kaunas) | – | No national feed confirmed |

### Denmark

| Layer | Status | Source | Licence | Note |
|---|---|---|---|---|
| A | Y | [Dataforsyningen](https://dataforsyningen.dk) terrain and surface models (DHM), orthophoto | SDFI free-data terms *(u)* | Free account |
| B | P | Matriklen and [Ejendomsvurdering (VUR)](https://datafordeler.dk/dataoversigt/ejendomsvurdering-vur/ejendomsvurdering/) via Datafordeler | free-data | Parcels free. Valuations by request to the Tax Agency; ordinary valuations suspended from 2013 |
| C | Y | BBR via Datafordeler | free-data | Year, floors, area, use: Estonia's EHR equivalent *(u)* |
| D | *(u)* | "Danmark i 3D" (SDFI) | – | Planned national LOD2; shipped *(u)* |
| F | Y | [CVR system-to-system access](https://datacvr.virk.dk/artikel/system-til-system-adgang-til-regnskabsdata) | free, registration | Owners and board *(u)* |
| G | **Y** | [Company tax list](https://sktst.dk/om-os/skatteoplysninger-for-selskaber) (bulk CSV); XBRL annual reports via CVR (every 10 min) | public | Taxable income and tax for every company. Small firms often report only gross profit. Staff counts *(u)* |
| H | Y *(u)* | Rejseplanen GTFS | – | |
| I | Y (licence *(u)*) | Landbrugsstyrelsen field parcels | – | |

### Finland

| Layer | Status | Source | Licence | Note |
|---|---|---|---|---|
| A | Y *(u)* | National Land Survey (NLS / Maanmittauslaitos): laser scanning, 2 m elevation model, surface model, orthophoto | CC BY 4.0 | From memory, not re-checked |
| B | P *(u)* | NLS cadastral index map | CC BY 4.0 | Outlines and property IDs only: no land use, no public value |
| C | Y | [Ryhti building data](https://ryhti.syke.fi/ryhti-jarjestelman-karttapalvelu-ja-paikkatietorajapinnat-nyt-auki/) (SYKE, open API since March 2025) | *(u)*, no login | Completion year, use, floors, floor area, address (from SYKE's field list) |
| D | P | [NLS Buildings 3D](https://www.maanmittauslaitos.fi/en/maps-and-spatial-data/datasets-and-interfaces/product-descriptions/buildings-3d) (LOD2 CityGML) | CC BY 4.0 | Sample areas only; grows with the laser programme |
| E | P *(u)* | Metsäkeskus forest data (stands, grid); Helsinki tree register | CC BY 4.0 | No national single trees |
| F | Y | [PRH open data API](https://avoindata.prh.fi) | CC BY 4.0 | Board and shareholders not open *(u)* |
| G | P | [Vero corporate income tax data](https://avoindata.suomi.fi/data/fi/dataset/yhteisojen-tuloverotuksen-julkiset-tiedot) (CSV each November, monthly corrections); [PRH iXBRL](https://www.prh.fi/fi/tietoa_prhsta/uutislistaus/tiedotteet/2025/avoin-data-digitilinpaatokset_22.4.2025.html) | CC BY 4.0 | Taxable income and tax per company, annual. No turnover or staff; iXBRL covers about 5 % of statements |
| H | Y *(u)* | Fintraffic / Digitransit GTFS | CC BY 4.0 *(u)* | |
| I | Y *(u)* | Ruokavirasto field parcels | CC BY 4.0 *(u)* | |

### Sweden

| Layer | Status | Source | Licence | Note |
|---|---|---|---|---|
| A | Y | [Lantmäteriet](https://www.lantmateriet.se/oppnadata) elevation model, laser data, orthophoto (STAC / COG since February 2025) | CC0 | Free account |
| B | P | Lantmäteriet property boundaries | CC0 | Assessed values are public by law but not open in bulk |
| C | P | Lantmäteriet buildings | CC0 | Footprint and purpose only |
| D, E | N *(u)* | – | – | Some city models |
| F | Y | [Bolagsverket bulk file and API](https://bolagsverket.se/apierochoppnadata/hamtaforetagsinformation/vardefulladatamangder.5294.html) (since February 2025) | free | Board *(u)* |
| G | P | Bolagsverket weekly iXBRL of digitally filed reports (from 2020) | free | Digital filing mandatory from financial years after 2025-12-31, so near-complete from 2027. Tax data on request only |
| H | Y (licence *(u)*) | Trafiklab GTFS Sverige 2 | CC0 *(u)* | Free key |
| I | Y *(u)* | Jordbruksverket field blocks | – | |

### Norway

| Layer | Status | Source | Licence | Note |
|---|---|---|---|---|
| A | P | hoydedata.no terrain, surface, points (open); [Norge i bilder](https://www.kartverket.no/en/on-land/flyfoto) orthophoto | CC BY 4.0 / restricted | The orthophoto needs an agreement; commercial use needs permission |
| B | P | Matrikkelen parcels (Geonorge) | CC BY 4.0 | No national value; municipal property-tax lists vary |
| C | P | Matrikkelen building points | CC BY 4.0 | Type and status; year and area through distributors |
| F | Y | [Enhetsregisteret bulk and roles API](https://www.brreg.no/en/use-of-data-from-the-bronnoysund-register-centre/datasets-and-api/) | NLOD | Staff count per company *(u)* |
| G | P | [Regnskapsregisteret API](https://data.brreg.no/regnskapsregisteret/regnskap); [tax lists](https://www.skatteetaten.no/en/forms/search-the-tax-lists/) | NLOD | Latest-year key figures only. Tax lists: login, logged lookups, no bulk |
| H | Y | Entur national GTFS / NeTEx | NLOD | |
| I | P *(u)* | NIBIO AR5 land cover | CC BY 4.0 | |

### Iceland

Not viable. No open national orthophoto (the main imagery is commercial), the property register is
per-property lookups, the company register has no bulk or API, and the tax lists are shown for
about two weeks a year, one lookup at a time. Mostly *(u)*: the official pages were rate-limited.

## Central and Eastern Europe

### Slovakia

| Layer | Status | Source | Licence | Note |
|---|---|---|---|---|
| A | Y | [ÚGKK ZBGIS](https://www.skgeodesy.sk/gku/produkty-sluzby/na-stiahnutie/zbgis.html): DMR 5.0, DMP 1.0 (1 m), classified points, orthophoto | free since 2023-07-01 (licence *(u)*) | Whole country |
| B | P | ZBGIS cadastral map (VKM) | free *(u)* | Geometry and number; no value |
| C | N | – | – | No open building register |
| F | Y | [RPO API](https://rpo.minv.sk/rpo-api-doc.html) and weekly SQL dumps | CC BY 4.0 | Includes statutory bodies |
| G | **Y** | [Finančná správa OpenData API](https://opendata.financnasprava.sk/page/openapi): corporate income tax per company (quarterly), VAT liability, tax reliability, debtors. [RÚZ API](https://www.registeruz.sk/cruz-public/home/api): balance sheet and P&L for every filer | CC BY 4.0; free key, 1,000 requests an hour | No staff counts |
| H | P *(u)* | City feeds (Bratislava) | – | |

### Slovenia

| Layer | Status | Source | Licence | Note |
|---|---|---|---|---|
| A | Y | [GURS CLSS 2023–25](https://flycom.si/en/%F0%9F%93%A2-data-for-the-whole-of-slovenia-is-now-available-on-our-clss-si-portal/): points, DMR, DMP, orthophoto | CC BY 4.0 | Whole country, rescanned on a cycle |
| B | **Y, with value** | [GURS real-estate cadastre and generalised market value](https://www.e-prostor.gov.si/dostopi/javni-dostop/) | CC BY 4.0 | The nearest thing to Estonia's taxation value; no owners who are persons |
| C | Y (attributes *(u)*) | Building cadastre | CC BY 4.0 | Year, floors, area, use expected |
| D | P *(u)* | GURS 3D | CC BY 4.0 | No confirmed LOD2 |
| F | P | [AJPES business register](https://podatki.gov.si/dataset/poslovni-register-slovenije) XML, twice a month | open | Basic fields; officers per record |
| G | P | AJPES JOLP annual reports | free, registration | One company at a time. Tax debtors published as images (a GDPR ruling) |

### Czechia

| Layer | Status | Source | Licence | Note |
|---|---|---|---|---|
| A | Y | [ČÚZK](https://geoportal.cuzk.cz/) DMR 5G, DMP 1G, orthophoto | CC BY 4.0 | |
| B | Y (no value) | ČÚZK cadastral map, [RÚIAN](https://cuzk.gov.cz/ruian/RUIAN.aspx) parcels | CC BY 4.0 | Czechia has no assessed value to publish |
| C | Y (partly *(u)*) | RÚIAN dump | CC BY 4.0 | Use, construction; year and floors in the open dump *(u)* |
| D | P | [Prague 3D](https://geoportalpraha.cz/data-a-sluzby/7e6316e95cfe4f36ae06bbfb687bf34b), Brno | city | No national model |
| F | Y | [dataor.justice.cz](https://dataor.justice.cz/) bulk XML (officers, shareholders); ARES; [ČSÚ RES](https://csu.gov.cz/produkty/registr-ekonomickych-subjektu-otevrena-data) | open | RES has a staff-size band |
| G | P | Filed accounts in the same bulk data | – | Mostly scanned PDFs |
| H | P | National timetables in JDF, not GTFS; Prague GTFS | – | |

### Poland

| Layer | Status | Source | Licence | Note |
|---|---|---|---|---|
| A | Y | GUGiK terrain and surface models, laser data, orthophoto | free since 2020 | |
| B | P | [KIEG](https://www.gov.pl/web/gugik/krajowa-integracja-ewidencji-gruntow-i-krajowa-integracja-uzbrojenia-terenu) WFS (295 counties), ULDK | free | Quality varies; no assessed value exists |
| C | P | County EGiB, BDOT10k (floors, function) | free | Year built inconsistent |
| D | **Y / P** | [GUGiK CityGML](https://www.geoportal.gov.pl/en/data/other-data/3d-models-of-building/): LOD2 in 10 voivodeships, LOD1 everywhere | free | |
| F | P | [KRS API](https://prs.ms.gov.pl/krs/openApi) (board, shareholders) | free | Per record, no bulk |
| G | P | e-KRS XML statements per company; [CIT list](https://dane.gov.pl/pl/dataset/1295) (revenue, costs, tax) | public | CIT list only for companies over €50 M revenue, groups, real estate |
| H | P | KPD catalogue of GTFS feeds | open | No single national feed |

### Croatia, Georgia, Ukraine

- **Croatia:** terrain open, laser data by application and fee; parcels and footprints without
  values; [court register API](https://data.gov.hr/ckan/en/dataset/sudski-registar) free with
  registration; accounts through [FINA](https://www.fina.hr/javne-usluge-za-poslovne-subjekte/registri/registar-godisnjih-financijskih-izvjestaja/uvid-u-javne-podatke-iz-rgfi-ja)
  one company at a time.
- **Georgia:** company register a free per-record lookup with officers and owners; no bulk found;
  geodata not checked.
- **Ukraine:** company register searchable again since January 2025; historical dumps exist but may
  be stale *(u)*; the public cadastral map restricted since 2022 *(u)*.

## Western Europe

### France

| Layer | Status | Source | Licence | Note |
|---|---|---|---|---|
| A | Y | [LiDAR HD](https://cartes.gouv.fr/aide/fr/partenaires/ign/observations-regulieres-territoire/relief/mnt-lidar-hd/) 0.5 m terrain, surface, height; BD ORTHO | Licence Ouverte 2.0 | About 80 % at end 2025, complete by end 2026 |
| B | Y | [Cadastre PCI](https://cadastre.data.gouv.fr) and DVF sale prices per parcel | Licence Ouverte 2.0 | DVF forbids re-identifying people and search-engine indexing; the tax base is not open |
| C | Y | [BDNB](https://bdnb.io/download/) (CSTB), 32 M buildings | Licence Ouverte 2.0 | Year, use, height, energy rating, linked to address and parcel |
| D | P | BD TOPO (LOD1), IGN LOD2 demonstrator | Licence Ouverte | No official national LOD2 |
| F | Y | SIRENE bulk and API; INPI RNE for directors | Licence Ouverte 2.0 | |
| G | P | [INPI annual accounts](https://data.inpi.fr/content/editorial/Acces_API_Entreprises) (about 1.2 M a year); SIRENE staff bands | Licence Ouverte 2.0, free account | About 45 % confidential |
| H | P / Y | [transport.data.gouv.fr](https://transport.data.gouv.fr) | mostly ODbL or Licence Ouverte | Hundreds of feeds |
| I | Y | RPG field parcels | Licence Ouverte | |

### Belgium

| Layer | Status | Source | Licence | Note |
|---|---|---|---|---|
| A | Y | Flanders DHMV II; [Wallonia laser 2021-22](https://geoportail.wallonie.be/catalogue/fe13bc84-e371-46ca-9632-8ad4139f1ee5.html); Brussels UrbIS orthophoto | free model licence / CC BY 4.0 / CC0 | Brussels laser *(u)* |
| B | P | [Federal cadastral plan](https://finance.belgium.be/en/experts-partners/open-data-patrimony/datasets/cadastral-map) | open *(u)* | The cadastral income per parcel is not open |
| C | P | Flanders building register; Brussels UrbIS | CC0 (Brussels) | No year or floor area *(u)* |
| D | Y / P | [Flanders 3D GRB](https://overheid.vlaanderen.be/grb-3dgrb) (LOD2); [Brussels UrbIS 3D](https://datastore.brussels/web/data/dataset/e9ec2aa4-cffd-11ee-bccc-00090ffe0001); Wallonia LOD1 (2013-14) | free / CC0 / CC BY 4.0 | |
| F | Y | KBO/BCE monthly CSV | free, registration | Board only in gazette PDFs |
| G | P (strong) | [NBB Central Balance Sheet Office](https://www.nbb.be/en/central-balance-sheet-office/consultation/web-services/authentic-data-daily-extract) daily extract | free; reuse terms *(u)* | Nearly all companies; staff in the social balance sheet; small ones often gross margin only |
| H | P | [transportdata.be](https://transportdata.be) | varies | No single national feed |

### United Kingdom

| Layer | Status | Source | Licence | Note |
|---|---|---|---|---|
| A | P | Environment Agency 1 m laser (England); Scottish and Welsh portals | OGL | No open national orthophoto |
| B | P / Y | [INSPIRE index polygons](https://use-land-property-data.service.gov.uk/datasets/inspire); Price Paid; [VOA rating list](https://voaratinglists.blob.core.windows.net/html/rlidata.htm) | OGL + OS attribution | Polygons carry no address or title; rateable values for about 2 M non-domestic properties |
| C | P | [EPC register bulk](https://get-energy-performance-data.communities.gov.uk/) | OGL except addresses | Floor area, age band, UPRN |
| F | Y | Companies House bulk, PSC snapshot, API | free reuse | Beneficial owners still public |
| G | P (best at scale) | Companies House accounts bulk (iXBRL, back to 2008) | free | Small companies may omit turnover; average staff mandatory |
| H | P / Y | [Bus Open Data Service GTFS](https://data.bus-data.dft.gov.uk/downloads/) | OGL | England buses; rail by account |

### Netherlands

| Layer | Status | Source | Licence | Note |
|---|---|---|---|---|
| A | Y | [AHN4 / AHN5](https://www.ahn.nl/dataroom), PDOK aerial photos | CC0 / CC BY 4.0 | |
| B | P | [Kadastrale kaart](https://www.pdok.nl/introductie/-/article/kadastrale-kaart) | CC BY | WOZ values one at a time; bulk needs a change in the law |
| C | Y | BAG | CC0 | Year, use, floor area; no floors |
| D | Y | [3DBAG](https://docs.3dbag.nl/en/copyright/) LOD2.2 | CC BY 4.0 | Whole country |
| F | P (weak) | [KvK open dataset](https://www.kvk.nl/en/ordering-products/kvk-business-register-open-data-set/) | CC BY 4.0 | Deliberately anonymised: no name, number or address |
| G | N | [KvK statements dataset](https://www.kvk.nl/en/ordering-products/kvk-financial-statements-open-data-set/) | CC BY 4.0 | Anonymised: cannot be linked to a company |
| H | Y | [OVapi GTFS](https://mobilitydatabase.org/feeds/gtfs/mdb-1077) | CC0 | National |

### Germany

Every layer is per Land. Terrain (DGM1) and orthophotos are open in all Länder since June 2024;
ALKIS parcels in 15 of 16 (Bayern's status *(u)*); LOD2 from each Land ([BW](https://www.lgl-bw.de/Produkte/3D-Produkte/3D-Gebaeudemodelle/LoD2/index.html),
[BY](https://geodaten.bayern.de/opengeodata/OpenDataDetail.html?pn=lod2), [NRW](https://www.opengeodata.nrw.de/produkte/geobasis/3dg/lod2_gml/), …; the national bundle is for authorities
only); zonal land values in most Länder *(u)*; national GTFS (DELFI). Companies are the wall:
handelsregister.de allows one record at a time, 60 an hour, no automated querying, no bulk; small
GmbHs file a balance sheet without an income statement.

### Switzerland, Austria, Luxembourg, Ireland

- **Switzerland:** [swisstopo OGD](https://www.swisstopo.admin.ch/en/free-geodata-ogd) terrain, surface
  and 10 cm imagery; swissBUILDINGS3D LOD2; the [GWR](https://www.housing-stat.ch) building register
  (year, floors, area); national GTFS. Parcels by canton, some by contract. Private company
  accounts are not public at all.
- **Austria:** national 1 m terrain and surface, [BEV cadastre](https://www.bev.gv.at/Services/Produkte/Kataster-und-Verzeichnisse/Kataster-Stichtagsdaten.html)
  with land use, field parcels, GTFS, all CC BY 4.0. No building register; the company API needs an
  approved application and small GmbHs file no turnover.
- **Luxembourg:** every geo layer open, including national LOD2; the [Centrale des Bilans](https://data.public.lu/en/organizations/centrale-des-bilans/)
  publishes filed accounts as quarterly XML with RCS numbers (CC BY-SA 4.0). One small country.
- **Ireland:** patchwork laser data; the [Tailte valuation list](https://tailte.ie/home/api/) (commercial
  rateable values); [CRO bulk and API](https://opendata.cro.ie) with a financial-statements CSV
  whose fields are *(u)*. Orthophoto and the land registry map are paid.

### Spain, Italy, Portugal

- **Spain:** [Catastro INSPIRE](https://www.catastro.hacienda.gob.es/webinspire/index.html) buildings
  with construction date, floors and use (the richest building data in the research); PNOA laser
  and orthophoto (CC BY 4.0); national GTFS. The cadastral value is protected; accounts cost money
  per document; the Basque Country and Navarre run their own cadastres.
- **Italy:** laser data covers about half the country; bulk [cadastral maps](https://www.agenziaentrate.gov.it/portale/download-massivo-cartografia-catastale)
  are geometry only; the company register's open part is 9 fields; accounts are paid.
- **Portugal:** new national laser data (CC BY 4.0, about 90 % by October 2025); the cadastre is open
  but patchy in the north; no building register; accounts are paid.

## Outside Europe

All of these need the per-country grid first.

### South Korea

| Layer | Status | Source | Licence | Note |
|---|---|---|---|---|
| A | P | NGII 5 m terrain (from maps, not laser), security-masked aerial photos | KOGL / key | |
| B | **Y** | [Cadastral SHP](https://www.data.go.kr/data/15125044/fileData.do) and [official land price per parcel](https://www.data.go.kr/data/15052266/fileData.do), annual | open (varies per set) | Estonia-grade |
| C | Y | [Building register API](https://www.data.go.kr/data/15134735/openapi.do) and bulk files | open, key | Approval year, floors, area, use, structure |
| D | P | VWorld 3D: LOD1 nationwide, detail in city cores | restrictive *(u)* | |
| F | P | OpenDART for filers | free key | Full register paid per record |
| G | **Y (substitute)** | [NPS workplaces](https://www.data.go.kr/data/3046071/openapi.do): every workplace with 3+ insured staff: monthly headcount, joiners, leavers, pension billed (about 9 % of payroll) | no restrictions | Monthly CSV; business number may be masked *(u)* |
| H | P | KTDB national GTFS (since May 2025), by application | – | |
| I | Y | [Every operating shop](https://www.data.go.kr/data/15083033/fileData.do) with industry, address, coordinates, quarterly | no restrictions | Far better than OpenStreetMap there |

### Japan

[PLATEAU](https://www.mlit.go.jp/plateau/open-data/) LOD1 and LOD2 with building attributes in about
300 cities (CC BY 4.0), the best 3D outside Europe; a full [company-number dump](https://www.houjin-bangou.nta.go.jp/download/zenken/index.html)
(monthly, commercial use allowed); a 5 m terrain model, 1 m being rolled out. Parcels are polygons
and numbers with no value; land prices exist only at sample points; there is no money data for
private companies (EDINET covers securities filers).

### United States, Australia, Brazil: city kits

Nothing national works: parcels sit with about 3,000 US county assessors and the national sets are
paid, and no country here publishes private-company money. Three cities have an Estonia-grade kit:

- **New York City:** [MapPLUTO](https://data.cityofnewyork.us/City-Government/Primary-Land-Use-Tax-Lot-Output-Map-MapPLUTO-/f888-ni5f)
  (assessed value, land use, owner, year built, floors, about 70 fields per lot, no restrictions),
  ACRIS deeds, the [city's LOD2 model](https://www.nyc.gov/site/planning/data-maps/open-data/dwn-nyc-3d-model-download.page)
  (2014), the street tree census, GTFS and national laser data (USGS 3DEP, public domain). Company
  money: only the one-off 2020–21 [PPP loan data](https://data.sba.gov/dataset/ppp-foia) (jobs
  reported per business).
- **Sydney:** national laser data ([ELVIS](https://elevation.fsdf.org.au/), CC BY 4.0), the
  [Valuer General's land values](https://data.nsw.gov.au/data/dataset/http-www-valuergeneral-nsw-gov-au-land-value-summaries-lv-php)
  for every property (monthly CSV, CC BY 4.0), the tax office's [corporate transparency](https://data.gov.au/data/dataset/corporate-transparency)
  figures for about 4,100 large companies and [WGEA](https://data.gov.au/data/dataset/wgea-dataset)
  headcounts for employers of 100+. NSW sale prices are BY-NC-ND.
- **São Paulo:** GeoSampa's open 0.5 m laser terrain and surface (2017) and a bulk property-tax
  cadastre with area, year built, use and unit values. Brazil's national company dump has a coarse
  size class, no money data.

### The rest

- **Canada:** national 1–2 m terrain from laser in 8 provinces; parcels and values provincial and
  mostly paid; federal company register open. Québec's register, the only source with staff
  counts, is CC BY-NC-SA, so it cannot be used.
- **New Zealand:** national laser data and imagery, parcels, and a valuation roll for the councils
  that opted in (all CC BY 4.0); the bulk company file needs a signed agreement; no company money.
- **Singapore:** no open terrain; parcels without values; public-housing blocks only.
- **Taiwan:** elevation finer than 20 m is classified; the cadastre is paid; company capital only.
- **Israel:** no open imagery; parcels without values; a basic company register.

## Where money is not published: an estimate

For a country without G, the economy can still run on estimates, labelled "estimated" in the game,
unlike Estonia's and Latvia's reported figures:

1. Identity and address from the company register; "who is in this building" from the register's
   addresses, and from Overture places (permissive licence; OpenStreetMap is share-alike) or a
   national shop list like Korea's.
2. Staff from the best proxy the country has: size bands (SIRENE, Czech RES, Brazil's size class),
   pension headcount (Korea), mandatory average staff in accounts (UK, Belgium).
3. Turnover as staff times the industry's revenue per employee from national statistics.
4. Real figures where they exist, for the companies they cover: tax lists (Finland, Denmark),
   accounts (UK, Belgium, France), large-company reports (Australia, Poland).

## Licence traps and other blockers

- **Unusable licences:** Québec's register (CC BY-NC-SA); NSW sale prices (BY-NC-ND); Norway's
  orthophoto (commercial use by permission); New Zealand's company bulk file (signed agreement).
- **Conditions to honour:** France's DVF forbids re-identifying people and search-engine indexing;
  Luxembourg's accounts are share-alike; OpenStreetMap is share-alike (ODbL), which binds the
  derived data.
- **Beneficial owners:** closed across the EU since the 2022 EU court ruling (C-37/20, C-601/20);
  the UK's register is still public.
- **Access friction:** free keys (Slovak tax office, 1,000 requests an hour; Polish REGON; Croatian
  register), registration (Danish, Portuguese and Spanish downloads), per-record-only registers
  (Poland, Germany, Slovenia), per-document fees (Spanish and Italian accounts).

## The EU floor: High-Value Datasets

Since 2024-06-09 (Implementing Regulation 2023/138), every EU country must publish free, in bulk and
by API, under CC BY 4.0 or looser:

- **Geospatial:** addresses, **buildings** (ID, geometry, floors, use), **cadastral parcels** (ID,
  geometry, code) and agricultural parcels. Values, owners and elevation are not required; whether
  elevation and orthophotos are in the list is *(u)*.
- **Companies:** basic data per company, and documents and accounts where the register holds them.
  Beneficial owners are not included. The Netherlands meets the rule on paper with anonymised data.
- **Transitional exemption** *(u)*: public bodies that must earn revenue, such as cadastre agencies,
  could delay to around June 2026, so more cadastres should have opened by now.

So parcels, buildings and registers keep getting easier; taxes paid and parcel values are not
covered and stay rare.

## Still to verify before building a pack

For the three nearest candidates, the cells that decide the work:

- **Lithuania:** whether the laser licence is granted for an open-source game and on what terms;
  whether parcels carry a value; the Sodra licence; a national GTFS.
- **Finland:** verified on 2026-09-13; the answers are in [finland-plan.md](finland-plan.md).
  - **Licences.** Everything used is CC BY 4.0, key-free through the Funet mirror.
  - **Laser points.** The open product is thin: 0.5 pts/m², no building class, and Helsinki's
    newest sheet is from 2008. The 5 p scans are not open.
  - **Cadastre.** It has no value and no land use. Helsinki publishes building rights per plot
    instead.
  - **Ryhti** is CC BY 4.0, but its buildings are points.
  - **Joins.** The Vero CSV joins PRH by business id.
  - **Grid.** L-EST97 is conformal, so tiles meet exactly everywhere. The whole country is covered
    and needs no grid of its own.
- **Denmark:** whether staff counts are in CVR; whether "Danmark i 3D" shipped; the terms of the
  free-data account; how far a 12° grid rotation matters before a per-country grid is needed.
