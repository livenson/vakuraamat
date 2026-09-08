# Seeing the place as it was — options for a historical imagery layer

A brainstorm, not a plan. What Maa-amet publishes, what it would cost to use, and five ways it could
sit in the game. Nothing here is implemented. Measurements were taken on 2026-09-08 against the live
services; the numbers are for one 1 km² tile in Tartu unless another place is named.

The short version: **there are two quite different sources here, and one of them is nearly free
because the game already talks to it.**

---

## 1. What is actually available

### 1a. The historical WMS the pipeline already uses

`https://kaart.maaamet.ee/wms/ajalooline` — the same service `fetch_tile.py` already calls for
`era_1798_verst.png` and `era_1938_cadastral.png`. Its layer list turns out to be far richer than
the two layers we take from it:

| kind | layers | span |
|---|---|---|
| orthophotos, one per campaign | `of1993-2000_10k`, `of2002`, `of2005`, then `of<year>aero` / `of<year>asulad` / `of<year>mets` | **1993 → 2025, nearly every year** |
| city orthophotos | `tartu2k2003`, `tln2000v`, `tln2000ht`, `tln2000_2005` | 2000–2005 |
| cadastral maps | `kk1940` (1930–1944), `lehman` (1978–1989) | |
| Estonian topographic | `ew_25T` (1923–1935), `ew_50T` (1935–1939), `ew_200T` (1935–1938) | |
| Russian imperial | `yheverstakaart` (1894–1922), `kaheverstakaart`, `kolmeverstakaart` (1866–1915) | |
| Soviet topographic | `nltopo_*` at 1:10 000 through 1:1 000 000, three epochs | 1940s–1980s |
| base maps | `pk_vr<year>` / `pk_mv<year>` colour and black-and-white | 1996 → 2026 |
| relief and surface models | `reljeef2012…2020`, `nDSM_2014`, `nDSM_2020` | |

Every one of these is georeferenced and answers a `GetMap` for an arbitrary bbox in EPSG:3301. A
tile's worth is a single call:

```
GET https://kaart.maaamet.ee/wms/ajalooline?SERVICE=WMS&VERSION=1.3.0&REQUEST=GetMap
    &LAYERS=of1993-2000_10k&CRS=EPSG:3301&BBOX=<ymin>,<xmin>,<ymax>,<xmax>
    &WIDTH=1024&HEIGHT=1024&FORMAT=image/jpeg
```

Verified on the Toomemägi tile: `of1993-2000_10k` returned 238 KB of black-and-white aerial imagery,
`of2007Tartu` 347 KB in colour, both exactly the tile's square, both with a small attribution mark in
the corner. **This is the same shape of file the era drape already consumes**, so it needs no new
machinery at all — only a way to choose which year is on the ground.

### 1b. Fotoladu — the photograph archive

`https://fotoladu.maaamet.ee` holds two collections:

- **Oblique aerial photographs** (`kaldaerofotod`), roughly 5.5 million frames since 2006, covering
  nearly the whole country. These are photographs of a place from a plane, not map products.
- **A scanned historical archive**, about 160 000 frames from 1939–1993, mostly black and white,
  from the Land Board, the Geological Survey, the Environmental Board, Tartu University Library and
  foreign archives for the war years. Individual frames are **not** precisely georeferenced; the
  mosaicked versions are, and those surface through the WMS above.

The oblique collection is queryable by coordinate:

```
GET https://fotoladu.maaamet.ee/api.php?B=<lat>&L=<lon>
```

It answers with an HTML gallery. For one point on Toomemägi that was **212 photographs spanning
2009–2024** (7–31 per year), shot from 0.1 to 3.4 km, from six camera bodies. Each record carries an
id, a timestamp, the folder, the full frame size and the shooting altitude:

```
data-ImageAtts="1052820,2016-09-13-11-02-19,img/a7r/2016-09,26.71501,58.38024"
title="ID:1052820 Pildistuskõrgus: 1.4 km"
```

and the frames are fetched directly:

```
thumbnail  https://fotoladu.maaamet.ee/data/img/<camera>/<month>/thumbs/<name>.jpg   ~2.5 KB
HD         https://fotoladu.maaamet.ee/data/img/<camera>/<month>/hd/<name>.jpg       ~1.2 MB, 1920×1280
```

`?foto=<id>` gives one photo's page with the camera's own position. The HD frames carry a tiled
"Maa-amet" watermark across the image.

**The catch:** this is a web application, not a documented API. `api.php` returns markup that would
have to be parsed, and the tidier-looking endpoints beside it (`paring_closest.php`,
`paring_db_arhiiv.php`) want parameters that are not published — they answered empty or 500 to
plain coordinate queries. Anything built on this should expect to be re-fixed when the site changes,
should cache hard, and should degrade to nothing rather than breaking a world.

### 1c. Licence

Both are Maa-amet open data: free to use, attribution required ("Foto: Maa- ja Ruumiamet" for the
photographs, the usual map-data line for the WMS). Two consequences worth deciding early:

- **Fetch at runtime rather than shipping frames in a pack.** The game already fetches the
  orthophoto from a WMS at build time and the pack carries the result; photographs are different in
  kind — thousands per tile, watermarked, and someone else's. Fetching on demand keeps the pack
  small and keeps us out of redistribution.
- Every source used gets a row in `THIRD_PARTY.md`, as everything else does.

---

## 2. Five ways it could sit in the game

Ordered roughly by how much new machinery each needs.

### Option 1 — a year on the ground

The terrain's drape swaps between the orthophoto campaigns. You stand in the same street, on the
same buildings, and the ground beneath changes: the block that was a field in 1998, the forest that
was clear-cut, the car park that was a house.

*How it would work:* the ground drape is already a texture the world sets (`world._set_drape`,
`EraDefinition.texture()`), and the pack already fetches historical layers from this exact WMS. A
year would be one more entry with a layer name; the fetch is one `GetMap` per tile.

*Navigation:* a dial rather than a screen — hold a key and the year steps, the way the era switch
already works, with the year shown where the date sits now.

*Strengths:* costs almost nothing, uses machinery that exists, and it is the option that speaks
directly to a game about land. Works on every tile in the country with no per-place data.

*Weaknesses:* only the ground changes. The buildings stay as they are today, so 1998 is a 2026 town
standing on a 1998 photograph. That may read as a bug rather than a feature unless it is framed as
looking at an old photograph rather than travelling to 1998.

### Option 2 — photographs pinned on the map

The map screen (M) gains markers where Fotoladu has frames. Pick one and it opens full-screen with
its date; step through the years at that spot.

*How it would work:* one `api.php` query for the tile centre gives a couple of hundred frames with
dates; thumbnails are 2.5 KB each so a contact sheet is cheap.

*Strengths:* discoverable, does not touch the 3D world at all, and the map is already the place you
go to find out where things are. Safe: if Fotoladu is unreachable the map is simply as it is today.

*Weaknesses:* it is a browsing feature bolted to the side. You look at an archive rather than at the
place you are standing in.

### Option 3 — the viewfinder

Standing anywhere, a key holds up the nearest photograph of where you are — full-screen or as a
plate in the corner, with its date. Like holding an old photograph up against the view.

*How it would work:* query by the player's position, pick the frame whose subject is nearest, show
the HD frame.

*Strengths:* the strongest connection between the photograph and the place. It is the version that
would actually make someone say "look at this".

*Weaknesses:* the frames have no recorded heading, so the photograph cannot be aligned to where you
are looking — it is "a picture of here", not "this view, then". A near-vertical frame from 1.4 km up
also does not look much like what a person standing in the street sees; the low-altitude frames
(0.1–0.4 km) are the ones that would land. Needs a live query per position, so it needs caching and
a graceful failure.

### Option 4 — in the plot book

A parcel's page in the book gains a strip: this plot in 1998, 2005, 2014, 2025 — each a crop of that
year's orthophoto to the parcel's own polygon.

*How it would work:* entirely from the WMS, one small `GetMap` per year per parcel (or one per tile,
cropped locally to each polygon).

*Strengths:* ties the imagery to the thing the game is about. You are buying a plot; here is what has
happened on it in thirty years. It also gives the land value a story — a plot that was forest in 1998
and a car park now says something a number does not.

*Weaknesses:* the smallest, quietest version. Nobody will discover it by accident.

### Option 5 — photographs as things in the world

A frame becomes an object: a marker where something was photographed, a postcard you can pick up, a
plot you own showing you its own history when you buy it.

*Strengths:* the only version that is part of the game rather than beside it, and the one that could
reward exploring.

*Weaknesses:* the most design work by far, and it needs a reason to exist in the economy — a
collection with no consequence is a chore. Worth thinking about only after one of the others proves
that the imagery is worth looking at at all.

---

## 3. What this brainstorm suggests

**Option 1 is the one to try first**, and it is almost embarrassingly cheap: the layers are on a WMS
the pipeline already calls, in the format the drape already takes. It is a day's work to find out
whether watching the ground change under a fixed town is compelling or merely odd — and if it is
odd, nothing was spent finding out.

**Option 4 is the natural second**, for the same reason and with no new sources.

**Options 2 and 3 need Fotoladu**, and so need a decision about depending on a scraped web
application. If they are wanted, the honest way in is a small, well-cached, entirely optional layer
that a world never waits for and never fails because of.

**Option 5 should wait** for one of the others to earn it.

## 4. Open questions

- Does an unchanged 2026 town on a 1998 ground read as a feature or a fault? Worth a screenshot
  before it is worth any code.
- Which orthophoto years actually cover a given tile? The layer list is national but each campaign
  flew part of the country; a tile needs its own list, from `GetCapabilities` or by trying and
  seeing what comes back. (`of2013asulad` returned a 17 KB image for the Toomemägi tile against
  347 KB for `of2007Tartu` — probably empty coverage, so this matters.)
- Does the watermark on the Fotoladu HD frames matter for how they would be shown?
- Would the 1939–1993 mosaics reach a tile through the WMS, or only through Fotoladu's own tile
  service (`tms_aerofotod.php`)? The pre-1993 imagery is the most interesting of the lot and it is
  the least accessible.
