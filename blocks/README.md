# Quest blocks

A block is one self-contained consequence: something the player does in one era that leaves a
visible trace in the later eras, told through one artifact (or one choice), one flag, a few props
and a few lines of dialogue per era role. `tools/compose_story.py` picks blocks for a site, places
them on the site's anchors (register, landmark, farm, field, trade) and writes the pack's items,
consequence points, scene nodes, ink knots, strings, objectives and ending rules. Blocks are the
"lego" of generated stories; the hand-written Palupera pack does not use them.

`blocks/<id>.json`:

| field | meaning |
|---|---|
| `id`, `flag` | block id; the TimelineState flag its consequence point sets |
| `kind` | `delivery` (an artifact handed to an NPC) or `choice` (a story point in the trigger era) |
| `trigger_era` | era role: `oldest`, `middle`, `newest` |
| `artifact` | delivery blocks: `id`, `origin_era` role, `spot` + `offset` where it lies |
| `story_point` | choice blocks: `spot`, `offset`, `knot` |
| `visible` | scene nodes (scenes.json syntax) shown in later eras when the flag is set; `absent` when it is not |
| `bonus` | true for the one block that gates the best ending on top of the counted ones |
| `strings` | `KEY: [et, en]`; `{PLACE}`, `{YEAR}`, `{OLDEST}`, `{NEWEST}` are substituted |
| `ink` | per role (`origin`, `trigger`, `later`, `before`, `any`): choice options for the era's NPC menu, ink syntax, `{ITEM}`, `{FLAG}`, `{TARGET_ID}`, `{NPC}`, `{TARGET_NPC}` substituted; `knot` for a choice block's story point |

Era roles with three eras: oldest, middle, newest. `later` = every era after the trigger era,
`before` = every era before the origin era, `any` = every era. Keys must be unique per block.
