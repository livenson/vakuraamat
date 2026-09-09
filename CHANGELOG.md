# Changelog

What changed in each release. A release is an annotated `v*` tag; pushing it builds macOS, Windows
and Linux and attaches them to a GitHub release whose notes are **this file's entry for that tag**,
followed by the commits since the previous one (`.github/workflows/build.yml`; the tag's own message
stands in when an entry is missing). Entries here are written for players, so a change is described
by what it does rather than by the code it touched; the commit list in the release has the detail.

The earliest entries were written from the tags' own messages after the fact.

## v0.7.0 — 2026-09-09

**One plot is the one every view is about.** The registers have always described a graph — plot,
building, company, owner — and the book showed it as four flat tables. Choose a plot now, from a row
in the book or a right click on the map, and it lights everywhere at once: its own row and the
companies registered on it are marked, its boundary stands on the ground as a low curtain of light,
and a dashed band arcs through the air to each thing the registers tie it to. Choose it again and
the marks go out.

Three kinds of tie, all of them read out of files the pack already held. Two units under one
*kinnistu* number are one registered immovable — Kapteni tn 3 and 3a. A building whose register row
names more than one unit stands over a boundary and ties those units together. And the companies on
two plots can share an owner. Each link says which of the three tied it, and a plot tied twice over
says both. In Kvissentali that is 29 plots tied to another, where the owner rule alone found 8.

A note the page makes a point of: a shared owner is an owner of *the companies* in the Business
Register. The cadastre does not say the land itself is jointly held, and the plot page says so
rather than letting you assume otherwise. The register's people are never named — a pack stores them
only as hashed ids, and none of them reaches the screen.

**The map's layers are laid on the ground you are standing on.** The debug map has coloured plots by
sector, company health and founding year for a while; choosing a layer used to leave nothing behind
when you closed it. Now the town is colour-coded around you in the same colours, with its key in the
corner, and **I** steps through the layers without opening the map at all. It is one baked picture
laid over the ground rather than anything built out of geometry, so it follows every slope exactly
and costs nothing to draw — 67 frames a second in the survey view against 68 with no layer at all. A
plot with no company on it is left as the real ground rather than washed grey.

**The find bar answers when you choose a result.** `/` opened it and typing listed the places, but
Enter did nothing at all — the results were listening for a key the text field had already eaten.
Arrows and Enter now work, and the results are buttons, so the mouse can pick one too. Its
placeholder was also mangled: the English read *" ettevõte või tänav"* where it should have read
"An address, a company or a street".

**A company the register has struck off no longer colours a plot.** Lootsi tn 14 showed red for a
business in trouble while its page correctly said no company was registered there; the layer was
taking a closed company as the plot's own. Three Kvissentali plots now read as the empty ones they
are, and on two more the live company gets its colour back from the closed one beside it. A plot
whose companies are all struck off is headed *Formerly registered here*, which is what the register
says.

And the same company is described the same way wherever you meet it — the book's plot page, the K
overlay and a building's register sheet each used to name a different subset of what the register
publishes.

**The news is gone.** The N panel carried the region's headlines and official notices. Of the 62 it
held in Kvissentali — the only place that ever had any — 43 came from one publisher's feed, and
exactly one named a plot. It was a national front page in a game about one square kilometre, it was
the only thing here that goes stale, and it stood on three publishers' goodwill in a project meant
to be open source. What goes with it is the only forward-looking thing the game had; if it returns
it should return as the planning and auction notices alone, on the plot page of the plot they name.

## v0.6.2 — 2026-09-09

The Locations page draws Estonia. The places it suggests used to be a list of names with a pair of
coordinates under each, which says nothing about whether a place is on an island, by Peipsi or an
hour from the world you already have. Now the country is above the list: a ring for every place
offered, a filled mark for a world you have installed, a ringed mark for the world you are standing
in. Point at a mark and it names itself; point at a row and its mark lights. The coastline is the
county division from the Land Board, with Võrtsjärv from the topographic database — Peipsi draws
itself, since the border runs down the middle of it.

The book's *Companies* page sorts. Click a heading — name, sector, employees, turnover, address —
and click it again to reverse, the way the plot list has always worked. Employees and turnover
start at the largest, names at A; a company the register publishes no figure for sorts last either
way instead of posing as a company with none.

A window you are not looking at no longer costs a processor core. The game drew the whole scene
again every frame whether or not anything had moved, so leaving it open behind a browser cost what
playing it cost; it now draws at the screen's own rate while you are there and falls to a trickle
when you click away.

And the towns run lighter. A frame in a town pack asked the graphics driver for about 5900 separate
draws; it asks for 1756 now, and the work the processor does per frame roughly halved. Two reasons,
both in the houses: every building used to mint its own wall, roof, window and trim material — some
840 of them in a tile of 211 houses, for what the register describes as a dozen looks — and the sun
drew four shadow passes over every building where two do. Nothing looks different; the shadows keep
their 400-metre reach, so a flying camera still sees a town with shadows in it.

## v0.6.1 — 2026-09-08

Tagged v0.6.0 first, and it never built: the packaging step for the tile service still expected a
directory that went with the economy, so all three platform builds stopped before they began and
nothing was attached to that tag. Nothing about the game changed between the two — everything below
is v0.6.0, with a build that runs.

The game is gone. Vakuraamat is a digital twin now: the same square kilometre of real Estonian
ground, the same real plots, buildings and companies, but nothing to buy, sell, bid on or build,
no money, no months passing, and no shared town.

What that means where you stand: the running head is the place and the time of day. The book (Tab)
has four pages instead of six, all read-only. *Plots* is the cadastre — address, purpose, area, the
2022 taxation value, the form of ownership — sortable by any of them and narrowed by typing an
address, a cadastral number or the name of a company registered there. *Plot* is one unit's page,
and it says more than it used to: its land registry number, when it was entered in the cadastre,
the settlement and municipality, the companies at it, a link into the register itself, and the
plot's own square out of every orthophoto flown over it since 1993. *Companies* is unchanged.
*Place* is new — the pack itself, what it holds, when its data was fetched, what a square metre of
each kind of land was valued at in 2022, and every source the figures come from.

**B** opens the plot you are standing on rather than buying it. The news (N) is still the region's
real headlines and the official notices that name this place. The journal (J) is the codex, which
no longer claims that prices move and three invented families bid on your plots: what is invented
here is the walls and roofs reconstructed from the Building Register, and the interiors, trees,
traffic and passers-by.

Flying over a place and reading the buildings below now works. It reached 120 metres before,
against a camera that sees four kilometres, so from any real survey height nothing answered at all,
and even in range it wanted an aim nobody can hold. The crosshair now names the nearest building it
falls inside, up to six hundred metres out, and holds it for a moment when your aim slips.

Saves keep only where you were: the place, the spot, the way you faced and the time of day.
Saves from the game do not load.

The bus stops tell the truth now, and buses keep it. The shelter's board used to carry five invented
Tartu lines on a made-up cadence; it carries the timetable the public transport register publishes
for that stop, hours down the side and minutes across, and E gives the next departures by the
world's clock. Kvissentali turns out to be the end of lines 8 and 10; Palupera gets one bus a day to
Elva, Otepää, Puka and Valga. A bus then turns up and runs the route, calling where the register
says it calls. It drives at a bus's speed rather than the clock's, so the journey takes longer in
game minutes than a real 8 would, but it leaves when it is supposed to.

Two things that were plainly wrong and now are not: the shelter's timetable was printed mirrored,
and most of the traffic was driving backwards - the model list that turns cars to face the way they
travel had the Lada turned round and three of the commonest cars left out.

Places you downloaded months ago catch up with the ones you download today. Most of them were
gathered before the register enrichment worked, so their companies had no line of business, no
staff, no standing — which is why the map's company layers washed those places in a single grey.
A place now records which version of the data pipeline made it, and one that is behind is quietly
gathered again: the registers are fetched afresh, the ground it already has is kept, and it takes
seconds rather than the twenty minutes a full rebuild does. You are not made to wait for it. A
neighbouring square is shown as it is and replaced when it is ready — never while you are standing
on it or indoors there — and the rest are brought up to date in the background while you walk about.
Storage says which places are behind and offers to fetch them now.

The plot's newest picture is as sharp as its older ones. Every year in "this plot over the years"
is fetched at the size you open it at, except today, which was enlarged out of the tile's own
photograph — 25 cm to the pixel, so a small plot's square is barely two hundred pixels there and no
enlargement puts detail back. Today is now asked for as its own picture like the rest, which in a
city means the finer flight the Land Board holds for it: on Rahe tn 24 in Haabersti that is roof
tiles and paving slabs where there was a smear.

The map's colours say what they are colouring. "Health" is the company on the plot, from the
business register, the Tax Board and the reporting deadline — not the state of the building, which
is what it read as; the layer is called company health now and the legend says where it comes from,
as does the founding-year layer, which is the company's year and not the house's.

## v0.5.1 — 2026-09-08

Some places could not be made into a world at all. Creating one would run to about three quarters
and then stop with "the world could not be created" and a line about register hashes — Pargi tn 17
in Tartu was one, and any place with a foreign company among its tenants was liable to be another.

Every company in the game keeps its owners as anonymous ids, never as names, so that companies
sharing an owner can be linked without anyone being identified. Estonian holders already arrive that
way. A holder registered abroad arrives as whatever that country's register calls them — the Paris
commercial register writes "900 606 898 R. C. S. Paris" — and that text was being carried straight
through, which the pack's own privacy check refused, correctly, by abandoning the whole job.

Foreign identifiers are now turned into anonymous ids of the same kind before they are stored, so
the link between co-owned companies still works and nothing readable is kept. Fourteen such holders
exist in the national register; a place near any of them was unbuildable and now is not.

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
