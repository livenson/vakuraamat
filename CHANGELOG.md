# Changelog

What changed in each release. A release is an annotated `v*` tag; pushing it builds macOS, Windows
and Linux and attaches them to a GitHub release whose notes are **this file's entry for that tag**,
followed by the commits since the previous one (`.github/workflows/build.yml`; the tag's own message
stands in when an entry is missing). Entries here are written for players, so a change is described
by what it does rather than by the code it touched; the commit list in the release has the detail.

The earliest entries were written from the tags' own messages after the fact.

## v0.5.0 — 2026-09-08

The land has a history now, and you can find your way around the town by typing.

### What the ground was doing before

- **A plot's page in the book shows the land itself, decade by decade**: the same square photographed
  in 1993–2000, 2010, 2015, 2020 and today, with the plot's own boundary drawn on every one. A plot
  that was forest in 1998 and a car park now says something its land value does not. The pictures
  come from the orthophoto campaigns Maa-amet has flown since 1993; today's is the tile's own
  photograph, so it always matches the world you are standing in.
- **Click a year to see it properly.** It opens at the size of the screen, fetched at that size
  rather than blown up, with the years along the bottom and the arrow keys to step between them.
- **Pressing E on a building shows it too.** A building stands on a plot, and what the ground was
  doing before it was built is the same question in both places — there is a button through to the
  plot's page in the book.
- Campaigns that did not fly over your plot are left out rather than shown blank, and a plot is
  fetched once and remembered.

### Finding a place

- **`/` opens a find bar over the world.** Type and plots, buildings, companies and streets come
  back with what they are and how far away. Enter points the arrow at one; Shift+Enter jumps.
  Pointing is the default on purpose — this is a game about walking a square kilometre.
- **The plot list has a search field** that narrows it as you type: an address, a cadastral number,
  or a company registered on the plot. A page holds 120 of a few hundred plots, so this is how you
  reach the ones past the letter A.
- **The plot list is ordered by name**, and ordered the way you read it: Aeru tn 9 comes before
  Aeru tn 10. Click any column heading to sort by it instead — area, value, price, owner, yield, or
  nearest first, which is what the list used to be.
- Searching knows the register writes streets two ways: "Aeru tn" and "Aeru tänav" are the same
  street, and either finds either. Estonian letters fold, so a keyboard without them still works.

### Elsewhere

- **A building's year now says "in use since".** The register records the year a building was taken
  into use — in practice the year of its use permit, which can be long after it was built. Madruse
  tn 4 stands in the 2010 photograph and has a permit dated 2015. There is no better year in the
  register, so the game stops implying one.
- The load no longer prints a warning for every building and parcel it places.
- Under the floor: the national elevation sheets can now be read by the game itself rather than by
  the Python pipeline — the first piece of making a new place without a service behind it.
- [docs/historical-imagery.md](docs/historical-imagery.md) writes down what else is available:
  orthophotos for nearly every year since 1993, map series back to 1866, and Maa-amet's archive of
  5.5 million aerial photographs.

## v0.4.1 — 2026-09-08

A build downloaded from a release could not make a world for a new place. The tile service that
comes with a build started and reported itself healthy, but carried no certificate store, so every
call it made to Maa-amet, the registers and the map services failed to verify and returned nothing.
It shipped that way in v0.2.0, v0.3.0 and v0.4.0; running from the repository was never affected.

- The service now carries the certificate bundle and points its connections at it.
- It writes to `logs/tile_service.log` in the game's own folder, so a service that misbehaves says
  why. It never had anywhere to report before, which is why this went three releases unseen.
- The game waits 45 s rather than 15 s for the service to come up — it unpacks 75 MB before its
  first line runs, which measured 10.7 s on a warm machine and more on a cold first launch — and
  when it does give up it says whether the service never started or started and did not answer.
- The build checks, before publishing, that the packaged service can actually geocode a place.
  A health check alone would have passed happily through all three broken releases.

## v0.4.0 — 2026-09-08

Loading. Both waits — opening a world you have, and making one for a place you do not — were long
enough to be the thing you noticed most, and both are now mostly gone.

### Opening a world

- The world opens on the ground and fills in behind you. The era layer's buildings and parcels
  arrive nearest-you-first a few milliseconds a frame instead of in one block, and the scene itself
  is parsed on a loader thread, so you are walking at **1.2 s on a built tile (was 3.8 s)** and
  **1.8 s on the first visit to a downloaded one (was 6.5 s)**. The two frozen frames a launch used
  to cost (2.8 s and 1.5 s of black screen) are gone; the town assembles around you over the next
  few seconds instead.
- A downloaded tile's trees, bushes and grass are scattered once you are on it, not while you wait:
  the first-visit ground build is **1.3 s instead of 4.7 s** and the place greens over while you
  walk it. An interrupted scatter is picked up on the next visit.
- Finished building meshes no longer land in one frame. Several hundred worker threads report back
  within a moment of each other, and applying them all at once was a second-and-a-half stall.

### Making a world for a new place

- **A new place is playable in about a minute instead of a quarter of an hour** — measured on
  Haapsalu with nothing cached: 107 s against 923 s. The pack you install is the same size (11 MB);
  the wait was the service fetching from the national services, and most of it was for detail you do
  not need to start walking.
- The ground a pack ships with is the 5 m model (4 MB a map sheet, against 75 MB for the 1 m one).
  Resampled to the tile's grid it sits a median of 1.8 cm from the 1 m ground, so the place looks
  like itself from the first step. The 1 m model is fetched afterwards, and the next time you enter
  that place from the menu it replaces the coarse one and the tile is rebuilt from it.
- The measured trees and the region's news are fetched after the pack is playable, not before it.
- The building register is asked about a whole tile at once rather than one building after another:
  871 buildings in 54 s, where 594 took 154 s.
- No single source can hold a pack any more. Every stage that reaches a national service has a time
  budget and is abandoned when it overruns — the notices feed alone used to hold a finished pack for
  eight minutes.
- The estimate on the Locations page tells the truth: it quotes the download it actually makes, and
  its speed is the average of recent transfers rather than the fastest ever seen (it was promising a
  minute for a quarter of an hour's work).

## v0.3.0 — 2026-09-07

Performance and playtest round: sliced vegetation scatter, tile streaming without the freeze
(staggered members, threaded scene parse, one tile at a time), buildings built on a worker thread,
tile-edge duplicates dropped, glass panes, sun shadow blending, building pick from the air with a
highlight, performance log in every build, parse test.

## v0.2.0 — 2026-09-06

Builds carry the tile-service sidecar: any address in Estonia becomes a world from the Locations
page, without the repository.

## v0.1.0 — 2026-09-06

First tagged build. Branding: the gold plot on the plate is a compact house-sized plot near the
centre, not a road strip.

## v0.9-historical

The three-era historical game the project grew out of, kept at its own tag. Its design documents are
in [docs/history/](docs/history/).
