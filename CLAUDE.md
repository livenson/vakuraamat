# Claude Code notes

Follow `AGENTS.md` — it holds the rules, commands, conventions and pitfalls for this repository.
Additional Claude-specific guidance:

- Verify visually: after any change to scenes, shaders or generated assets, take a screenshot with
  the world's `--screenshot` option (add `--site=<id>` for another pack) and look at it before reporting.
- Site packs: content changes go in `sites/<id>/`, never in engine code; run `make validate` after.
- `/debug-game` (project skill) launches the game and watches it; the manual recipe follows.
- When the user is playtesting, watch the report feed with Monitor (`tail -F "$HOME/Library/Application Support/Godot/app_userdata/Vakuraamat/reports/feed.log"`),
  read each report's JSON and screenshot, fix, then `python3 tools/dev.py reload <files>` or `restart`; `replay <id>` puts a
  fresh game at the reported spot for a screenshot check.
- Run `make test` before committing; commit per logical step with the FPS number when rendering changed.
- Keep `THIRD_PARTY.md` and `vakuraamat-visual-upgrade-plan.md` status lines current.
- Playtest triage order: read the report's position first. A position outside 0..1024 means a
  streamed tile; check whether the same thing happens in the origin tile before blaming streaming
  (the "fallen trees" were a model problem visible everywhere).
- Kill stray processes before a debug session: `pgrep -fl "Godot --headless|make test|tile_service"`.
  A hung test loop keeps spawning instances that `tools/dev.py` then targets instead of the player's game.
- After changing a mesh, texture or region data on disk, `python3 tools/dev.py restart`; hot reload
  covers scripts, era scenes, pack data and shaders only.
- Facing, snapping and offset rules are in `AGENTS.md` (conventions and pitfalls); read them before
  touching movers, parcel kits or anything that samples the terrain.
