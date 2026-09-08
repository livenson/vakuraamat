# Changelog

What changed in each release. A release is an annotated `v*` tag; pushing it builds macOS, Windows
and Linux and attaches them to a GitHub release whose notes are the tag's message plus the commits
since the previous tag (`.github/workflows/build.yml`). Entries here are written for players, so a
change is described by what it does rather than by the code it touched; the commit list in the
release has the detail.

The earliest entries were written from the tags' own messages after the fact.

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
