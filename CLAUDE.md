# Claude Code notes

Follow `AGENTS.md` — it holds the rules, commands, conventions and pitfalls for this repository.
Additional Claude-specific guidance:

- Verify visually: after any change to scenes, shaders or generated assets, take a screenshot with
  the world's `--screenshot` option (add `--site=<id>` for another pack) and look at it before reporting.
- Site packs: content changes go in `sites/<id>/`, never in engine code; run `make validate` after.
- When the user is playtesting, watch the report feed with Monitor (`tail -F "$HOME/Library/Application Support/Godot/app_userdata/Vakuraamat/reports/feed.log"`),
  read each report's JSON and screenshot, fix, then `python3 tools/dev.py reload <files>` or `restart`; `replay <id>` puts a
  fresh game at the reported spot for a screenshot check.
- Run `make test` before committing; commit per logical step with the FPS number when rendering changed.
- Keep `THIRD_PARTY.md` and `vakuraamat-visual-upgrade-plan.md` status lines current.
