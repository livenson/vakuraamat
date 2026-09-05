# Vakuraamat town ledger (SpacetimeDB module)

One database per town: a 1 km² tile of real Estonian cadastral units. Clients regenerate terrain,
buildings and trees from Maa-amet data; only this ledger is shared. Every mutation is validated
here and error strings are the game's translation keys (`LEDGER_*`). Money is whole euros; the
economic period is a month, advanced by the scheduled `tick` only while a player is present.

- `src/lib.rs`: tables (`town`, `parcel`, `tenant`, `player`, `presence`, `bid`, `obligation`,
  `structure`, `improvement`, `event`, `tick_schedule`, private `economy_config`), reducers and the tick.
- `rules/`: pure arithmetic (rent, tax, list price, index drift, family bids, penalties) with
  `cargo test`; the module itself cannot be linked natively, so tests live here.

Build and run (the Makefile wraps these: `make module`, `make server`, `make town SITE=<id>`):

```sh
curl -sSf https://install.spacetimedb.com | sh          # CLI to ~/.local/bin
brew install rustup && rustup default stable && rustup target add wasm32-unknown-unknown
spacetime start --listen-addr 127.0.0.1:3300            # local server (3000 is often taken)
spacetime publish -s http://127.0.0.1:3300 -p server/vakuraamat -y <town-name>
python3 tools/town_admin.py seed --site kvissentali --db <town-name> [--debug]
```

Town names come from `tools/town_admin.py name --site <id>`: `vk-t<E>-<N>-<hash8>`, the tile centre
plus the first 8 hex digits of sha256(parcels.json ++ tenants.json). Seeding calls the admin reducers
(`seed_config`, `seed_parcel`, `seed_tenant`, `seed_structure`, `finish_seed`) over the HTTP API with
the publisher's token; `join_town(pack_hash, name)` refuses a client whose pack differs. `--debug`
enables `grant_cash` for local play. The news feeder posts through `post_event`.

Client bindings: `godot --headless --path . --script res://addons/SpacetimeDB/cli.gd` regenerates
`spacetime_bindings/` from the `vakuraamat` dev database named in `addons/SpacetimeDB/plugin_config.tres`
(publish the module under that name first). Regenerate after every schema change and commit the result.

Licence: this module is MIT like the game. SpacetimeDB itself is BSL 1.1 (one production instance).
