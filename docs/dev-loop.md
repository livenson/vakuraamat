# The development loop: report from the game, fix, come back to the same spot

Three pieces, all in debug builds (running from the project) and off in exported release builds.

## 1. Report an issue in the game: F8

F8 grabs the frame as you see it, then opens a note box. *Send* writes to `user://reports/`:

- `report_<time>.json`: your note, site, layer, month, cash, owned plots, position, yaw and pitch, what the crosshair
  was on (node path, label, hover text, ids), interactables within 15 m, register buildings within
  25 m (name, year, materials), committed flags, artifacts, the last engine errors and warnings,
  the locale and FPS, and a `replay` command line;
- `report_<time>.png`: the frame;
- a save slot named after the report;
- one line appended to `reports/feed.log`.

`user://` is `~/Library/Application Support/Godot/app_userdata/Vakuraamat` on macOS
(`~/.local/share/godot/app_userdata/Vakuraamat` on Linux, `%APPDATA%\Godot\app_userdata\Vakuraamat`
on Windows). `python3 tools/dev.py reports` lists them, `show <id>` prints one.

## 2. Claude Code watches the feed

`make dev-watch` tails the feed for a human. For Claude Code the same file is a `Monitor` source:

```
tail -F "<userdir>/reports/feed.log"
```

Every report becomes an event in the session; Claude reads the JSON and the screenshot, fixes, runs
`make test`, and answers with a reload or a restart (below). Nothing needs to be typed in the session.

## 3. Back to the same spot: replay, hot reload, restart

- **Replay**: `python3 tools/dev.py replay <id>` (or the `replay` line inside the report) starts the
  world scene with `--report=<file>`: the report's site is selected, its save slot loaded, the
  player placed at the recorded position, yaw and pitch.
- **Hot reload** into the running game: `python3 tools/dev.py reload <paths>` appends a command to
  `user://dev/commands.jsonl`; the `DevChannel` autoload polls it twice a second and answers in
  `user://dev/results.log` (`tools/dev.py results`). Per file type:
  - `.gd`: the script re-reads its source and `reload(true)` keeps instance state (exported values,
    connections to renamed functions and changed autoload structure are the cases where it fails;
    the result says "error N (restart needed)");
  - era `.tscn`: the cache entry is replaced and the current era layer is instanced again with the
    player where they stand (`make scenes` first when `scenes.json` changed);
  - anything under `sites/<id>/` (`.tres`, `strings.csv`, `site.json`, `parcels.json`): the pack is
    re-read, registries and strings reload, the layer re-instanced;
  - shaders, textures, other resources: replaced in the cache.
- **Restart at this spot**: `python3 tools/dev.py restart` makes the game write a report of where it
  is and relaunch itself on it. Use it after changes hot reload cannot take.
- Also: `teleport x z [yaw]`, `era <id>`, `screenshot </abs.png>`, `codes`, `quit`.
- Several games may run at once (a playtest plus a replay, plus the test suite). Each instance
  registers itself in `user://dev/instances/<pid>.json` and only executes commands addressed to its
  pid (`"pid": 0` means all). `tools/dev.py` targets the newest instance by default; `--pid <n>`
  picks one and `--all` broadcasts; `python3 tools/dev.py instances` lists them.

## Aerial checks

`--fly` starts the player flying; `--spawn=x,z[,yaw[,height[,pitch]]]` places them (a height keeps
them in the air, a pitch in degrees tilts the view), e.g. a border check from the air:
`godot --path . res://scenes/world/world.tscn -- --site=kvissentali --fly --spawn=940,500,-90,110,-28 --screenshot=/tmp/a.png`.
`--no-stream` keeps neighbouring tiles from loading during measurements.

## M: debug map

The map shows the 1024 m tile the player stands in (the site's own drape, or a streamed
neighbour's orthophoto), redraws live while open, and a click teleports within that tile.

## K: codes overlay

K toggles an overlay with the cadastral unit under you (number, purpose, area, owner, X-GIS link),
the building you look at (ETAK id, Building Register link), the nearest road and the target node, and
draws the unit boundary; the links go to the clipboard. `python3 tools/dev.py codes` toggles it from
outside. Reports include the same fields.

## /debug-game

In Claude Code, `/debug-game [site | report-id]` (project skill in `.claude/skills/debug-game/`) launches the
game from the session, starts the three watches (report feed, engine errors, channel results) and
follows the react-fix-reload-verify protocol above.

## Limits

Godot's own "Synchronize Script Changes" only works for games launched from the editor, so this
channel does the equivalent by hand. `Script.reload(true)` is best-effort: a stale closure or a
changed signal signature can misbehave until the next restart, which is why restart-at-spot exists
and is cheap (about ten seconds on a shipped tile, plus the terrain build on a fresh downloaded one).
The channel is a plain file drop on the local machine; it is not a network service.
