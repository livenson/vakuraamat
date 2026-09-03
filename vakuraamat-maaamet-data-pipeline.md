# Vakuraamat — Maa-amet data types and conversion pipeline

**Purpose of this document:** a reference for exactly what data is available from the Estonian Land and Spatial Development Board's geoportal (geoportaal.maaamet.ee), and the concrete conversion path from each raw data type to a usable Godot/Terrain3D/Blender game artifact. Meant to sit alongside `vakuraamat-implementation-plan.md` — this document is the "what data, what tools, what output file" reference; the implementation plan is the "what code" reference.

---

## 1. Data categories available

### 1.1 Elevation / LiDAR
- **Raw point clouds (ALS):** nationwide airborne laser scanning coverage, delivered as **LAZ 1.4**, tiled one file per 1 km². Auto-classified into ground, vegetation, buildings, water, bridges, and noise classes. Typical density ~2.1 points/m² generally, up to ~18 points/m² in urban areas.
- **Derived DEM rasters** (the more directly usable form for terrain):
  - **DTM** (Digital Terrain Model — bare-earth elevation): 1 m, 5 m, 10 m, 25 m grid resolutions
  - **DSM** (Digital Surface Model — includes buildings/canopy): 1 m, 5 m
  - **nDSM** (normalized DSM — height *above* ground, i.e. buildings/vegetation height only): 1 m, 5 m
  - **CHM** (Canopy Height Model — forest canopy height specifically): 4 m, 10 m
  - Formats: **GeoTIFF** or **XYZ ASCII**
  - Projection: **EPSG:3301** (Estonian L-EST97), vertical datum **EH2000**

### 1.2 Orthophotos (aerial imagery)
- Nationwide coverage at 20–40 cm ground sample distance (GSD); denser urban coverage at 10–16 cm GSD
- Formats: **GeoTIFF** or **ECW**
- Tiled in a standard 5×5 km grid (2074 sheets nationwide)
- Both **RGB** and **CIR** (color-infrared — distinguishes vegetation/tree species, useful for forest tagging) available
- Roughly half the country is reflown annually, so acquisition date varies by tile — always check per-tile metadata

### 1.3 Cadastral data
- Land parcel boundaries and ownership-adjacent metadata
- Formats: **Shapefile, GeoPackage, DGN, DXF**
- This is the data source for manor/parcel boundaries referenced in the implementation plan's `ManorDefinition.cadastral_parcel_id`

### 1.4 Estonian Topographic Database (ETAK) and base maps
- Vector topographic data: roads, buildings, water bodies, land cover, administrative boundaries, place names
- Base maps at 1:10,000 / 1:20,000 in both raster and vector form

### 1.5 Forest data
- Forest stand data lives in the separate **Estonian Forest Registry** (metsaregister), not the core geoportal — queryable/downloadable independently
- Combine with CIR orthophotos and CHM for a fuller picture of forest type/density/height

### 1.6 Soil and geological data
- Soil map: 2045 sheets covering 43,300 km²
- Geological data at 1:50,000 and 1:400,000 scales

### 1.7 Historical maps (the layer central to the time-travel mechanic)
- **Orthophotos back to 1993** (earliest digital aerial coverage)
- **Cadastral maps from 1930–1944** (independent-Estonia era)
- **Soviet-era topographic maps** (1942 and 1963 coordinate systems, various scales, published 1946–1989)
- **Count Mellin's "Atlas of Livonia"** (1798–1810), viewable via the X-GIS application — the earliest usable cartographic layer
- These are raster scans of historical maps, generally **not georeferenced to modern precision out of the box** — see section 3.5 for how to handle this

### 1.8 Access methods
- Direct bulk download by map sheet, no registration required
- Live OGC services: **WMS / WFS / WMTS / WCS**, consumable directly in QGIS

### 1.9 License
Estonian Land Board Open Data License — **free for commercial and non-commercial use**, requires attribution (e.g. "Map data: Republic of Estonia Land and Spatial Development Board, [year]"), provided "as is," and the Land Board can request removal of attribution in writing. No royalties or per-seat fees. See `implementation-plan.md` section on licensing for the exact citation format to use in-game (credits screen) and in any store page.

---

## 2. Target game artifacts

Each raw data type maps to one or more of these final in-engine artifacts:

| Artifact | Used by | Produced from |
|---|---|---|
| Heightmap (16-bit PNG/EXR) | Terrain3D terrain mesh | DTM GeoTIFF |
| Terrain base texture | Terrain3D texture layer | Orthophoto GeoTIFF |
| Biome/forest tag layer | Hunting spawn system (Phase 3) | CIR orthophoto + CHM + forest registry |
| Building/road vector props | Blender-authored props, placed via ETAK data | ETAK/OSM vector data |
| Cadastral overlay | Manor boundary visualization, journal/map UI | Cadastral shapefiles |
| Historical map texture (per era) | Journal/map-comparison UI, era-specific ground texture | Scanned historical map rasters, georeferenced |
| Blender hero props | Buildings, landmarks, set-dressing | Manual modeling, informed by orthophoto reference |

---

## 3. Conversion pipelines, per data type

### 3.1 DTM → Terrain3D heightmap

**Tools:** QGIS (primary), GDAL (command-line alternative)

1. Download the DTM GeoTIFF tile(s) covering your target location from the geoportal.
2. In QGIS: clip to your exact area of interest (Raster → Extraction → Clip Raster by Extent/Mask Layer).
3. Reproject if needed — Terrain3D doesn't care about geographic projection, only relative elevation, so EPSG:3301 is fine to keep as-is; just note the scale (1 map unit = 1 meter in L-EST97, which is convenient).
4. Convert to a normalized 16-bit format Terrain3D can import:
   - QGIS: Raster → Conversion → Translate, output as 16-bit PNG or keep as GeoTIFF (Terrain3D can import GeoTIFF heightmaps directly in recent versions — check current Terrain3D docs for supported import formats, as this has changed across releases)
   - GDAL equivalent: `gdal_translate -ot UInt16 -scale input_dtm.tif output_heightmap.png`
5. Import into Terrain3D via its heightmap import tool, matching the real-world extent (Terrain3D supports terrains from 64×64 m up to 65.5×65.5 km, so a 1 km² tile is comfortably within range).

**Note on vertical exaggeration:** Estonia is very flat (highest point 318 m). At true 1:1 scale, elevation changes may read as visually flat in-engine. Decide deliberately whether to apply a vertical exaggeration multiplier (common in terrain games) and document the chosen factor so all eras use the same one consistently.

### 3.2 DSM/nDSM/CHM → auxiliary layers

- **nDSM** is the fastest way to get an approximate building-height and vegetation-height map without manual modeling — useful as a first-pass placement guide for where Blender props (buildings) should go and roughly how tall.
- **CHM** feeds directly into the forest/biome tagging step (3.4) for hunting spawn logic.
- These are processed the same way as DTM (QGIS clip → GDAL convert) but typically consumed as data layers for placement logic rather than as the walkable terrain mesh itself.

### 3.3 Orthophoto → terrain texture

1. Download the orthophoto GeoTIFF (or ECW — convert ECW to GeoTIFF first via GDAL if needed: `gdal_translate input.ecw output.tif`) covering the same extent as your DTM tile.
2. Clip to match the DTM extent exactly in QGIS (critical — texture and heightmap must share the same bounding box for correct draping).
3. Export as a standard image format Terrain3D accepts for texture painting/base color (PNG or JPG, sized to a power-of-two if performance matters — e.g. 2048×2048 or 4096×4096 depending on tile size and desired texel density).
4. Assign as the terrain's base color/albedo layer in Terrain3D.

**CIR variant:** if you also download the color-infrared version, keep it as a separate reference layer — it's not directly a game texture, but it's the best source for classifying vegetation type when hand-placing forest props or configuring biome tags.

### 3.4 Forest data → biome/spawn tags

There's no single clean "biome map" file — this is a derived layer you build:

1. Start from CIR orthophoto (vegetation is far more distinguishable in CIR than RGB) plus CHM (canopy height) for the target tile.
2. In QGIS, do a simple classification pass (raster calculator or classify by CHM height thresholds + CIR reflectance) to produce a small number of biome classes — e.g. "dense forest," "sparse forest/edge," "open field," "wetland/bog," "water."
3. If the Forest Registry (metsaregister) data is available for your tile, cross-reference stand type/age for more accurate classification instead of guessing from imagery alone.
4. Export the classification as a raster (or convert to polygons) and bring it into Godot as a simple lookup texture/data resource, matching `AnimalDefinition.spawn_biome_tags` from the implementation plan — i.e., the exported biome map's pixel value at a given world position determines which animals are eligible to spawn there.

### 3.5 Historical maps → era ground textures and journal overlays

Historical maps present a genuinely different problem from modern DTM/orthophoto data: they are **scanned raster images of paper maps**, not georeferenced GIS data by default, and their positional accuracy (especially the 1798 Mellin Atlas) is much lower than modern surveying.

**Two distinct uses require two different treatments:**

**A. As a journal/UI overlay (comparison mechanic)** — lower precision is fine here, arguably even desirable for authenticity:
1. Download the historical map raster for your area from the geoportal's historical map WMS/download options.
2. Crop to roughly the same area as your modern tiles — pixel-perfect alignment is not required for a UI comparison tool where the player is visually cross-referencing, not walking on it.
3. Use directly as a 2D texture in the journal/map UI (per the earlier design research on the "map-layer whodunit" mechanic) — an opacity-slider or side-by-side comparison between historical and modern layers.

**B. As an in-world era ground texture (draping onto the 3D terrain for that era)** — this needs real georeferencing:
1. In QGIS, use the **Georeferencer tool** (Raster → Georeferencer) to manually place ground control points on the historical scan, matching them to known-stable features also visible in the modern orthophoto (church locations, river bends, road junctions — features unlikely to have moved).
2. Georeferencer will warp/rectify the historical raster to real-world coordinates (EPSG:3301), producing a usable GeoTIFF.
3. From here, treat it exactly like a modern orthophoto (section 3.3) — clip to your tile extent, export as a texture, assign to that era's terrain in Terrain3D.
4. **Expect imprecision, especially for the 1798 Mellin Atlas** — early cartography was not surveyed to modern standards. Budget time for this step and set expectations that some manual warping/approximation is unavoidable; this is a known characteristic of historical map georeferencing, not a pipeline failure.

**Practical note:** since terrain *shape* (the DTM) for historical eras is not separately available — Estonia wasn't LiDAR-scanned in 1798 — the actual 3D landform should reasonably be treated as unchanged across eras (real terrain changes very slowly at this timescale outside of quarrying/major earthworks), with only the **surface texture and placed props/buildings** varying by era. This is a useful simplification: one shared heightmap, multiple era-specific textures and prop sets, which also matches the implementation plan's `EraDefinition` structure (each era has its own `terrain_texture` but can reuse the same underlying heightmap where appropriate).

### 3.6 Cadastral data → manor boundaries and parcel visualization

1. Download cadastral shapefiles/GeoPackage for your target area.
2. In QGIS, identify and export the specific parcel(s) relevant to your manor locations (matching `ManorDefinition.cadastral_parcel_id` in the implementation plan).
3. Two use paths:
   - **Visual boundary in-world:** convert parcel polygon outlines to a simple line mesh or decal in Godot, useful for a "manor territory" visualization overlay.
   - **Gameplay/logic only:** keep as pure data (polygon bounds) used for spawn-region checks (e.g. "is player inside manor X's parcel") without any visual representation.

### 3.7 ETAK vector data → building/road placement reference

1. Download ETAK vector layers (buildings, roads, water) for your tile.
2. Use in QGIS as a placement reference — building footprint polygons tell you where and roughly how large real structures were, which is far faster than eyeballing the orthophoto for Blender prop placement.
3. This data does **not** need to be imported into Godot directly for most purposes — it's primarily a Blender/level-design reference layer for accurate, real-world-grounded prop placement, not a runtime asset. Optionally, road/building centerlines and footprints could be exported and used to auto-generate rough prop placement in Godot as a starting point for hand-refinement.

---

## 4. Recommended toolchain summary

| Step | Tool |
|---|---|
| Download, clip, reproject, classify, georeference | **QGIS** (primary GIS workstation tool) |
| Command-line batch conversion | **GDAL** (`brew install gdal` on macOS) |
| Historical map rectification | QGIS Georeferencer plugin |
| Terrain import | **Terrain3D** (Godot addon) |
| Hero prop modeling | **Blender**, using orthophoto/ETAK as reference (BlenderGIS optional, for quick previews only — see prior tooling notes on its maintenance status) |
| Runtime biome/spawn data | Custom exported raster or resource, read by Godot's hunting spawn system |

## 5. Suggested file naming and folder mapping

Ties directly into the implementation plan's `assets/terrain/` and `data/` folders:

```
assets/terrain/
├── era_1798/
│   ├── heightmap.png          # shared or era-specific, per section 3.5 decision
│   └── texture_georeferenced_mellin.png
├── era_occupation/
│   ├── heightmap.png
│   └── texture_soviet_topo.png
├── era_present/
│   ├── heightmap.png
│   └── texture_orthophoto.png
└── shared/
    ├── biome_tags.png         # from section 3.4
    └── cadastral_parcels.geojson
```

---

## 6. Open questions to resolve before large-scale production

- **Vertical exaggeration factor** for the flat Estonian terrain — pick one value and apply consistently across all eras (section 3.1).
- **Shared vs. per-era heightmap** — confirm the simplification in section 3.5 (same landform, different textures/props per era) is acceptable for your chosen location, or whether any era needs deliberate terrain differences (e.g. a since-drained wetland, a filled-in quarry) that would require manually sculpting a variant heightmap for that specific era.
- **Historical map coverage for your final chosen location** — not every real location will have equally good historical map coverage across all target eras; verify availability for your specific chosen manor/location before committing to it in the design.
- **Attribution text** — finalize the exact credit line for the in-game credits screen and store page per the Open Data License terms (section 1.9).
