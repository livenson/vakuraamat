# Vakuraamat — first iteration design: mechanics, narrative, level design

> **Revision note (2026-09-05):** this document describes the historical three-era game, kept at the
> git tag `v0.9-historical`. The game is now a present-day economy on the same real ground with a shared
> town ledger; the current rules are in `AGENTS.md`, `README.md` and `docs/custom-sites.md`.


**Purpose of this document:** the creative design for the Phase 1 vertical slice, complementing `implementation-plan.md` (the code/architecture plan) and `../maaamet-data-reference.md` (the data plan). Where the implementation plan says "5 consequence points, 2–4 artifacts, 3 eras," this document says *which* ones, and why.

Everything here is scoped strictly to Phase 1. Farming, hunting, trading, and manor expansion are deliberately absent — they arrive in Phases 2–5 and must not leak into this slice.

The manor, the family, and all characters are **fictional by design** (section 3.3), placed on real terrain in the Palupera area (section 4.1). The names should be verified as not matching a real historical manor or real people before content is finalized (section 7).

---

## 1. Design intent

**Fantasy:** you hold the land register of a small South Estonian manor and can step into the years it records. What you carry between those years leaves marks the land still shows today.

**Emotional register:** warm and curious — continuity and stewardship rather than loss. Think *A Short Hike* or *Pentiment*'s gentler passages, not *This War of Mine*. Consequences should feel *meaningful and a little wondrous*, never like puzzle rewards and never heavy. There is room for melancholy (a ruin is still a ruin), but the dominant feeling is "this place had good people in it, and some of what they made is still here." No ending is a failure state; some endings simply keep more.

**The three questions the slice must answer for a playtester:**
1. Do I understand *why* the thing I did in one era changed the other era? (legibility — the make-or-break metric)
2. Did revisiting the same ground in another era feel meaningful rather than repetitive?
3. Did I want to know what happened to these people?

**Slice length target:** 45–90 minutes of play.

---

## 2. Mechanics

### 2.1 Core verbs (the complete list for Phase 1)
- **Move** — first-person walking. First-person is chosen deliberately: it avoids character rigging/animation entirely (a large cost for a solo beginner) and maximizes the "standing on the same real ground in two eras" effect.
- **Look / examine** — hover-and-read on objects, buildings, and landscape features. Examine text is era-aware (the same oak reads differently in 1798 vs 2026) and carries the player character's voice (see 3.3) — this is the main place the player's personality lives, so it should be written with the same care as dialogue.
- **Pick up** — adds an item to inventory.
- **Talk** — ink-driven dialogue with NPCs; choices are few and meaningful.
- **Give / deliver** — hand an item to an NPC or place it at a location. This is the only way an artifact triggers a consequence.
- **Open the register** — switch era (see 2.2).
- **Read the journal** — see logged consequences and compare the era maps (see 2.4).

There is no combat, no stamina, no crafting, no economy, no timers. Anything not on this list is out of scope for Phase 1.

### 2.2 Era switching — the register as the device
The vakuraamat itself is the time-travel mechanism, making the title literal. The player carries the book at all times; opening it shows three entries (one per era) and choosing one switches era.

- **Switch from anywhere.** No fixed portals. Prior research on Radiant Historia's backtracking fatigue makes friction-free switching non-negotiable. Switching anywhere also produces the "Titanfall trick" for free: the player is standing on the same spot before and after, so before/after comparison is spatial and immediate.
- **Transition:** a short (2–3 s) fade through the book's page — long enough to read as deliberate, short enough never to annoy. The player's position is preserved; only the era's scene dressing changes.
- **Gating:** all three eras are available from the moment the player first opens the register (end of the prologue). No era is locked behind progress. Gating comes from *content* (an NPC won't talk until you've seen something; a location isn't relevant yet), not from the switching mechanic.
- **Cost:** none. Deliberately. Save-scumming is countered structurally by commit points (2.6), not by making switching expensive.

### 2.3 Inventory — two tiers, visually distinct
- **Era-local items** (plain icon): ordinary objects that exist in one era and cannot be carried through the register. Attempting to switch era while holding one simply leaves it behind where you stood — and the game says so the first time, teaching the rule cheaply. Phase 1 has very few of these (a handful of narrative props); the tier exists mainly so Phases 2–4 can plug into it.
- **Artifacts** (gold-bordered icon, distinct pickup sound): the only objects that travel between eras. There are exactly four in the slice (section 3.4). Each has exactly one intended delivery, and each is *telegraphed before the player finds it* — an NPC or examine-text mentions the need before the object appears.

The visual distinction is a hard rule from prior UX research: players must never confuse "loot I'm hoarding" with "history I'm rewriting."

### 2.4 The journal
Opens on a hotkey. Two tabs:
- **Ledger** — an auto-appending log. Every time a consequence flag flips, a one-sentence entry appears in plain language: *"You gave Juhan the ploughshare in 1938. In 2026, the north field is meadow, not forest."* This explicit causal sentence is the single most important piece of UI in the game (Radiant Historia lacked it and was criticized; Outer Wilds' ship log had it and is praised).
- **Maps** — the three era maps of the same ground (1798 Mellin-derived, 1938 from the 1930s cadastral maps, 2026 orthophoto), with an opacity slider to blend any two. In Phase 1 this is purely a comparison tool with no deduction logic — the lightweight descendant of the earlier "map-layer whodunit" idea. Locations the player has visited are marked on all three layers so the comparison is anchored.

### 2.5 Consequence system as experienced by the player
1. **Telegraph** — before the player can act, the need is stated in-world ("if only we still had the old ploughshare").
2. **Act** — deliver the artifact or make the choice.
3. **Immediate acknowledgement** — the NPC reacts; the ledger entry appears.
4. **Prompt to witness** — a soft nudge, not a forced cutscene: *"The register's 2026 page has a new line on it."* The player chooses when to go look.
5. **Witness** — switching to the affected era shows a visible change *at a location the player already knows*, ideally within sight of where they're standing.

Every one of the five consequence points must pass all five steps. If a consequence can't be witnessed as a visible change on the ground plus a dialogue delta, it's not a consequence point — it's flavor, and it gets cut or rewritten.

### 2.6 Chapters and commit points
The slice is divided into chapters (section 3.5). Within a chapter the player may switch eras freely and re-decide anything. At the end of each chapter the game autosaves and *commits* — flags set during that chapter become permanent. The player is told this plainly at the first chapter boundary.

This gives the player freedom to explore consequences without fear, while ensuring the run they actually finish carries real weight. It also structurally prevents every state from being softlockable: every chapter has at least one forward path regardless of flags.

Saving: autosave at every commit point and every era switch; manual save allowed at any time. With commit points in place, manual saving does not trivialize consequences.

### 2.7 Time of day (ambient only)
A day/night cycle runs in every era (Sky3D, with the sun computed for the site's real latitude and longitude, one full day in about 30 real minutes). It is **atmosphere, not a mechanic**: nothing is gated on the hour, no NPC schedule depends on it, and no timer runs against the player. Its one design use is continuity: the time of day is preserved across an era switch, so the same afternoon light falls on the oak in 1798 and 2026. Era dressing may set a *default* time on first entry (a bright 1938 morning, a long 2026 evening), never a forced one. Weather stays out of the slice.

### 2.8 Explicit non-mechanics (do not add during Phase 1)
No farming, hunting, trading, currency, base building, combat, health, hunger, weather system, skill trees, or crafting. Each of these has its own phase or is deferred indefinitely.

---

## 3. Narrative

### 3.1 Premise
Present day, 2026. The player has come to clear out a collapsed farmstead on land they've inherited from a relative they barely knew. In the ruins of the nearby manor they find a bound ledger — a vakuraamat, the register in which the manor once recorded every farm, family, and obligation on its land. The book still holds three entries for this farmstead: 1798, 1938, and, impossibly, 2026. Opening an entry places the player on the same ground in that year.

The narrative question that drives the slice: **who made this place, and how much of what they made is still here?**

### 3.2 The three eras
- **1798 — the manor.** Late Livonian serfdom. The farmstead is a chimneyless *rehielamu* (barn-dwelling) worked by a peasant family bound to the manor. The register is literally in use: the steward records who owes what. This is the era of *obligation* — the vakuraamat as a tool of the powerful.
- **1938 — the first owners.** Independent Estonia, two decades after the 1919 land reform broke up the manors and gave their land to the families who had worked it. The same family's descendants now *own* the farmstead for the first time in its history. The manor building has become the village schoolhouse. Everything is being built, mended, planted, argued over at the parish meeting. This is the era of *making* — hopeful, busy, slightly chaotic.
- **2026 — the present.** The manor is a ruin, the farmstead a foundation under nettles, the fields returning to forest — or not, depending on what the player has done. An elderly neighbor is the last person who remembers the 1938 farm. This is the era of *finding*, and the era where consequences are witnessed most fully.

A heavier alternative exists — **1949**, the collectivization and deportation year — and could be added as a fourth era in a later phase if the game wants to grow into that weight. It is deliberately *not* in the slice; the sensitivity practices it would require are noted in section 6 for future reference.

### 3.3 Names and characters (fictional; verify against manor and surname registries before finalizing)

**The manor: Tõrvamäe mõis** (German: *Törwenhof*). "Tar hill" — a plausible South Estonian toponym (tar-burning was a real peasant trade in the region) with no known historical manor of that name. The German form is what the 1798 register would use; the Estonian form is what everyone says.

**The family: Kaseoja.** In 1798 peasants had no surnames — Mart is simply *Kaseoja Mart*, "Mart of Kaseoja (birch-brook) farm." When Livonian peasants were given surnames in 1823–26, the steward registered the family under the German form of the farm name, **Birkenbach**. In 1937, in the middle of the national name-Estonianization campaign, Aino and Juhan change it back to **Kaseoja** — not inventing a name but reclaiming the one the land already had. The register the player carries shows all three states. This is what CP1 turns on: the surveyor's land-reform files say Birkenbach, the family says Kaseoja, and only the 1798 page proves they were always the same. See `language-notes.md` section 3.3. Verify the name isn't a prominent living family in the area and that the Birkenbach→Kaseoja pair isn't a real documented change.

- **The player** — unnamed, first-person. Examine-text has a voice: dry, observant, a little self-deprecating, quick to notice craft ("someone re-hung this door twice; the second time they got the hinges right"). Never sarcastic about the people. Never narrates feelings directly — the player supplies those.
- **Leida Kaseoja** (2026) — the elderly neighbor, ninety-one and entirely undiminished, sharp and funny. She was a small child here in 1938. She is the slice's emotional anchor and the recipient of the final artifact.
- **Aino and Juhan Kaseoja** (1938) — the young farm couple, descendants of the 1798 family and the first generation to own the land. Aino is the planner and talker; Juhan is the fixer, permanently mid-repair, cheerfully behind schedule. They have a small daughter who toddles through scenes but is never named — the player realizes late that she is Leida.
- **Villem Tamberg, the surveyor** (1938) — a county land surveyor re-measuring boundaries for the land-reform records, chronically lost, mildly comic, and the reason the family's old tenure matters (CP1). Not an antagonist; an obstacle with a clipboard.
- **Kaseoja Mart** (1798) — the serf farmer, the family's earliest recorded ancestor. Stubborn, practical, funny in a dry way.
- **Hans, the steward** (1798) — *kubjas*, the manor's overseer who keeps the register. Neither cruel nor kind; the book is his world.
- **The baron von Tolkenau** (1798) — referenced constantly, never seen. His absence is the point.

Continuity across eras is carried by **things**, not by any single person: the oak, the well, the north field, the orchard — and the register.

### 3.4 The four artifacts and five consequence points

| # | Flag | Trigger (era, action) | Affected era | Visible change | Telegraphed by |
|---|---|---|---|---|---|
| CP1 | `family_recorded_1798` | 1798 — give the **register page** (found in 1938) to the steward, who records the family's tenure properly under the farm name | 1938, 2026 | 1938: the surveyor can finally match "Birkenbach" in his files to the Kaseojas in front of him, and the boundary dispute with the neighbour evaporates; Aino is delighted. 2026: a boundary stone with the family name stands at the field edge | The surveyor in 1938: "My files say Birkenbach. You say Kaseoja. Until something older says both, I have no farm here." Aino: "The old baron's book would say. Nobody's seen it in a lifetime." |
| CP2 | `north_field_ploughed` | 1938 — give the **ploughshare** (found in 1798) to Juhan, whose new plough has cracked mid-season | 2026 | The north field is open meadow with visible old furrow lines, not young forest; Leida remembers the year they finally got the north field in | Juhan in 1938, over a broken plough: "Grandfather's old iron would've done it. That thing never broke." |
| CP3 | `well_kept_open` | 1798 — a **choice**, not an artifact: help Mart shore up the well against the steward's order to fill it | 1938, 2026 | 1938: the farmstead has its own sweet water, Aino brags about it. 2026: the well survives as a stone ring the player can look down into | The steward in 1798: "The well is to be filled; the manor's well will serve." Mart: "Serve whom." |
| CP4 | `cellar_opened` | 1938 — give the **manor key** (found in 1798) to Aino, opening the schoolhouse's sealed cellar where the baron's old apple-grafting stock was stored | 1938, 2026 | 1938: a short scene of the cellar and the first saplings going in beside the manor. 2026: an old orchard still stands beside the ruin, a few trees still bearing | Aino in 1938: "The old baron's orchard stock is under the school, they say. Nobody's had the key for a hundred years." |
| CP5 | `letter_delivered` | 2026 — give **Aino's letter** (found in 1938, written "to whoever finds this, from the first harvest") to Leida | 2026 only | Leida reveals where the family's box is buried; unlocks the epilogue scene | Leida in 2026, on first meeting: "Mother said she wrote it all down. I never found it." |

**Artifact list (four, within cap):** the register page (1938 → 1798), the ploughshare (1798 → 1938), the manor key (1798 → 1938), Aino's letter (1938 → 2026).

**Rules for how these were designed** (apply the same rules to any future consequence point):
- Every artifact's purpose is stated by an NPC *before* the player finds it — no arbitrary object logic (the specific failure prior research identified in Shadow of Destiny).
- Every change is *physically visible on the ground* in the affected era, not just a dialogue line.
- No consequence depends on another being done first. Flags are independent, so there is no state explosion: five booleans, thirty-two combinations, every one valid.
- One of the five (CP3) is a choice rather than a delivery, so the slice tests both trigger types.

### 3.5 Structure and pacing
- **Prologue (2026, ~10 min)** — arrive, explore the ruin, meet Leida, find the register, learn to switch. Ends when the player first opens the book. *Commit point.*
- **Chapter 1 (free era access, ~25 min)** — the player is nudged toward 1798 first (the register's first page is marked). Meet Mart and the steward; CP3 is available here; the ploughshare and manor key are discoverable; the register page cannot be used yet (the player hasn't found it). The chapter ends when the player has visited all three eras at least once. *Commit point — the player is told, for the first and only time, that choices are now permanent at chapter ends.*
- **Chapter 2 (free era access, ~25 min)** — 1938 opens up fully. Meet Aino, Juhan, and the surveyor; CP1, CP2, CP4 all become available; the letter is discoverable. *Commit point.*
- **Chapter 3 (free era access, ~15 min)** — return to 2026 with whatever the player has done. CP5 available. The player is free to go back and witness anything they missed. Ends when the player chooses to sit with Leida.
- **Epilogue (~5 min)** — one of three endings.

Total: roughly 80 minutes, which fits the slice target with margin.

### 3.6 Endings — three, all warm
Determined by how many of CP1–CP4 are set, plus whether CP5 was done. None is framed as failure; the difference is *how much of the place is still here to find*.
- **"Forest"** (0–1 of CP1–4): the land has quietly taken most of it back. Leida and the player sit on the oak's roots and she tells the stories anyway — the well, the plough, the apple trees — as things she remembers rather than things the player can see. The register's last page carries a single line in her voice.
- **"Furrows"** (2–3 of CP1–4): traces remain — a field, a well, a stone, a few apple trees. Leida walks the player to each one she remembers, unhurried, pointing with her stick. The register's last page lists what was kept.
- **"Orchard"** (all of CP1–4 *and* CP5): Leida leads the player to the buried box under the oldest apple tree. Inside: the family's papers, three generations, and a pressed apple blossom from 1938. The register's last page fills itself in — in the player's own handwriting — and the epilogue ends on the orchard in bloom.

If CP5 is done but fewer than four of CP1–4 are set, the box is found with the letter and the blossom but no papers — Leida shrugs: "Well. That's the part that mattered." It should be written as gently comic rather than sad.

---

## 4. Level design

### 4.1 The site — the Palupera area, Otepää highlands
**Recommended real tile:** a ~1 km² clip in the **Palupera area** (Elva municipality, Tartu county, historically Otepää parish), on the northern edge of the Otepää highlands. The fictional Tõrvamäe manor and Kaseoja farm are placed on this real ground; the real Palupera manor and its real families are not depicted.

Why this area, against the original criteria:
1. **Relief.** The Otepää highlands are the one part of the target region where 10–20 m of local relief is normal rather than exceptional — a manor on a rise reads naturally here.
2. **Water.** The Palu river runs through the area (and historically powered a mill), giving a stream boundary and a landmark.
3. **Forest edge and open field** both exist within any 1 km² clip here; the landscape is a patchwork.
4. **Roads.** The Palupera–Otepää road crosses the area.
5. **History that matches the design almost exactly.** The real Palupera manor was expropriated in the 1919–20 land reform, its land surveyed and partitioned into settler farms (*asundustalud*) allocated by lottery — first to War of Independence veterans, then to the manor's own labourers — and the manor house was handed to the parish and became the village school in 1933. A manor school existed in the area from 1776. This is the 1938 era of the design, in the real record. The design borrows the pattern, not the people.

**Historical map coverage, verified against the Maa-amet historical-maps WMS and local sources:**

| Era in game | Map layer available | Notes |
|---|---|---|
| 1798 | Mellin's Atlas of Livonia (1796 sheet covers this area) | Local historians have published an excerpt of the Mellin sheet for Palupera, confirming coverage. Low positional precision — see data pipeline doc 3.5. |
| 1798 (supporting) | Rücker's map of Livonia (1839); Swedish-era cadastral map (1684) exists for part of the area | Rücker is more precise than Mellin and only 40 years later; useful for cross-checking manor and farm positions. |
| 1938 | Schematic cadastral map 1931–1944 at 1:10,000 (*skeemiline katastrikaart*) | The ideal layer: drawn during exactly the period depicted, at farm-parcel scale, showing the post-reform settler-farm boundaries. Drawn over the Russian one-verst map base. |
| 1938 (supporting) | One-verst maps 1894–1922; two- and three-verst maps | Show the pre-reform manor landscape for before/after comparison. |
| 2026 | Orthophotos (RGB and CIR), 1 m DTM/DSM/CHM, current cadastre, ETAK | Full modern coverage as per the data pipeline doc. |
| Not used in slice | Soviet topographic maps 1946–1989; 1978–89 "lehmanahk" cadastral maps | Available if a 1949 era is ever added. |

All layers are served through the Maa-amet historical WMS in EPSG:3301, so they can be loaded together in QGIS and clipped to the same extent.

**Alternative if the Palupera area proves unsuitable on inspection:** the **Aakre** area (Valga county) — another manor school with a 275-year school history, similar landscape, same map coverage.

**Choosing the exact 1 km² clip** is the one remaining site decision: open the historical-maps application, overlay the 1931–44 cadastral sheet on the 1 m relief shading, and pick a square that contains a rise, a stretch of the Palu river or a tributary, a forest edge, and a road — then confirm the same square is legible on the Mellin sheet.

### 4.2 Spatial layout (relative, adapts to the chosen tile)
- **The oak** — center of the tile, on slightly raised ground. Present in all three eras (a 250-year-old oak is entirely plausible). This is the *anchor landmark*: from the oak you can see the manor, the farmstead, and the well. It is where the prologue starts and the epilogue ends.
- **The manor** — on the rise, northwest, ~200 m from the oak. Standing in 1798; the village schoolhouse in 1938, with children's noise; a ruin in 2026.
- **The orchard** — the slope just below the manor, between manor and oak. Bare in 1798 (the baron's grafting stock is in the cellar, unplanted); newly planted saplings in 1938 if CP4 is done, otherwise rough grass; in 2026 a small old orchard with a few trees still bearing (CP4), otherwise scrub. This is the slice's signature visible consequence and the site of the best ending.
- **The farmstead** — ~100 m south of the oak. Barn-dwelling in 1798; the same building with a new roof, a proper chimney, and half-built extensions in 1938; a foundation under nettles in 2026.
- **The well** — between farmstead and oak. Being dug/contested in 1798; a working well with a new winch in 1938 if kept; a stone ring in 2026 if kept, else nothing but a dip in the ground.
- **The north field** — open ground north of the oak, toward the manor. Strip fields in 1798; a half-ploughed field with a broken plough in 1938 (CP2 during chapter); meadow-with-furrows or young forest in 2026 (CP2). Also the site of the boundary stone (CP1).
- **The stream** — east edge. Constant across eras; a natural "you've reached the end of the world" boundary.
- **The forest** — south edge. Constant, but *closer* in 2026 (regrowth) unless the field was kept.
- **The road** — west edge, running north–south past the manor. Track in 1798, gravel with a milk-churn stand in 1938, asphalt in 2026.

The playable area is deliberately small — a player can walk from any point of interest to any other in under two minutes. Density of meaning over size.

### 4.3 Sightlines and navigation
- From the oak, all five primary locations (manor, orchard, farmstead, well, north field) are visible. Every era.
- The manor's silhouette on the rise is the one thing readable from anywhere in the tile — it's the compass.
- There are no waypoint markers or minimap. The journal's map tab and the manor silhouette are the navigation aids. This is a deliberate genre choice (exploration, not fetch-questing) and is cheap to build.
- Boundaries are natural (stream, forest, road-then-fence) — no invisible walls. The forest edge in 2026 is denser to naturally discourage wandering.

### 4.4 Era dressing — what changes, what doesn't
Per the data pipeline document, the *terrain shape is shared* across eras; only surface texture and placed props change. This is both a technical simplification and a thematic one: the land is the constant, people are what changes.

| Element | 1798 | 1938 | 2026 |
|---|---|---|---|
| Ground texture | Mellin-derived / strip fields | 1930s cadastral / consolidated fields | Orthophoto |
| Manor | Standing, lit, out of bounds inside | Schoolhouse, one classroom enterable | Ruin, walkable |
| Orchard | Bare slope | Saplings or grass (CP4) | Old trees or scrub (CP4) |
| Farmstead | Barn-dwelling, enterable | New roof and chimney, enterable | Foundation only |
| Field | Strips, hand-worked | Half-ploughed, broken plough (CP2) | Meadow or forest (CP2) |
| Well | Under construction | Working with winch, or absent (CP3) | Ring or dip (CP3) |
| Road | Dirt track | Gravel, milk-churn stand | Asphalt |
| Sound | Wind, livestock, distant work | Children at the school, a bicycle bell, hammering | Wind, birds, a far road |

Prop budget for the slice: the oak, the manor (exterior + one interior), the barn-dwelling (two roof states), the well (two states), the boundary stone, apple trees (sapling and mature), a cart, a bicycle, a milk-churn stand, a handful of small set-dressing items. Everything else is terrain texture. This is deliberately tight — around a dozen Blender hero assets total.

### 4.5 Onboarding through space
- The prologue path (ruin → oak → Leida → manor → register) is a loop that shows the player every primary location in 2026 *before* they can switch era, so the first switch to 1798 lands on ground they already know.
- The first switch is nudged to happen *at the oak*, so the very first before/after comparison is the strongest one available: the tree is the same, everything around it is not.
- The "era-local items stay behind" rule is taught by placing one obvious pick-up (a rusted tool) right beside the oak in 2026, so the player's first switch demonstrates the rule with zero cost.

---

## 5. Success criteria for the slice (design-side, complementing the implementation plan's technical criteria)
- [ ] A first-time playtester can explain, unprompted, why at least 4 of 5 consequences happened
- [ ] A playtester chooses to switch era at least once purely to *look*, without a task driving it
- [ ] No playtester asks "where am I supposed to go" for longer than ~2 minutes
- [ ] At least one playtester asks what happened to the daughter before Chapter 3 reveals it
- [ ] The full slice completes in 45–90 minutes for a first-time player

---

## 6. Historical accuracy and tone — practices for the slice
With 1938 as the middle era the sensitivity burden is light, but the game still portrays real history and should be careful about it:
- **The family and manor are fictional and stay fictional.** Verify the working names against real historical manors and real families before finalizing.
- **1798 serfdom is not softened into a costume drama.** Mart is bound to the manor; the steward's register is a real instrument of that. The tone is dry and human, not grim — but the facts are the facts. This is where the slice earns its historical credibility cheaply.
- **1938 is accurate in its details.** The 1919 land reform, the schoolhouse-in-the-manor pattern, the milk-churn stand, the county surveyor — these are all period-real and should be researched enough that an Estonian player nods. A short "what's real here" codex page, accessible from the journal, separates attested history (the register system, the land reform) from invention (this family, this manor).
- **A player who knows what comes after 1938 will feel it.** The design does not mention 1940 or 1949 anywhere in the slice, and should not. The lightness is honest because the characters don't know; the player's own knowledge is allowed to sit quietly underneath. Do not lampshade it.
- **Dead ends are warm, never punishing.** No fail states; endings differ in what is still here to find, not in whether the player "won."

*Kept for future reference, not for the slice:* if 1949 is ever added as a later era, the practices from prior research apply in full — deportation implied and never dramatized, no villain caricature, a fact-vs-fiction codex covering the deportations specifically, and a sensitivity review by the Estonian Institute of Historical Memory and/or the Vabamu Museum of Occupations and Freedom before release.

---

## 7. Decisions made and remaining checks

**Resolved:**
- **Middle era:** 1938 (section 3.2).
- **Real tile:** the Palupera area, Otepää highlands; exact 1 km² clip still to be chosen on the map (section 4.1).
- **Names:** Tõrvamäe mõis / Törwenhof; the Kaseoja family; Villem Tamberg; Hans the steward; baron von Tolkenau (section 3.3).
- **Player voice:** minimal first-person examine-text with personality (sections 2.1, 3.3).
- **Language:** ship in both Estonian and English. Write the primary script in **Estonian** — the idiom, the farm vocabulary, and the 1798 register language are native to it, and a translation *from* Estonian into English will read better than the reverse. Ink supports per-line localization; keep both languages in the same `.ink` files from the start rather than bolting on translation later. Examine-text volume is small enough that maintaining both is realistic for the slice.

**Remaining checks before content is written:**
- Verify **Tõrvamäe/Törwenhof** against the Estonian manor registry (e.g. the Estonian Manors portal and Stryk's *Rittergüter Livlands*) and **Kaseoja** against the population register to confirm neither is a real manor or a prominent living family in the Palupera area.
- Choose the exact **1 km² clip** and confirm it reads on the Mellin sheet as well as the 1931–44 cadastral sheet.
- Decide whether the **German** register language of 1798 appears untranslated in-game (as flavour, with the Estonian/English alongside) or is simply rendered in the game language — a tone decision with small localization cost.
