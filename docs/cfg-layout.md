# The `cfg/` layout: per addon, per game, one generic `server.yml`

Design for task `cfg-layout-split`. It lives in dot-map because the rotation file (`maps.yml`) is the first setting to move, but the rule is family-wide and the code is in dot-core and dot-server-deploy.

## What is built for the rotation file

The operator edits `cfg/server/` only; the shipped tiers are the author's. For `maps.yml`, weakest first, each in every root (`res://cfg`, beside the executable, `user://cfg`, `--config DIR`):

| Tier | Path |
| --- | --- |
| addon | `cfg/addons/dot_map/maps.yml` |
| game | `cfg/game/<game>/dot_map/maps.yml` (ships with the game, e.g. `cfg/game/mg-deathrun/dot_map/maps.yml`) |
| operator | `cfg/server/addons/dot_map/maps.yml` |
| operator, one game | `cfg/server/game/<game>/dot_map/maps.yml` |

- **An operator file replaces the shipped list.** A file that starts with `merge: true` is layered over the weaker ones instead (a rotation of the same name still replaces its list). `remove: [map_id, ...]` at the top of any file takes those maps out of every rotation. `DotMapRotationFile.find_layers(config_dir, game)` returns the files that apply, from `DotAddonConfig.replace_aware_layers`, and `load_files` reads them.
- **No file at all** is the zero-config case: every installed map rotates, sorted by id (`DotMapRotation.sort_unordered`). The game rotation and `cfg/content/games.yml` `maps:` lists are dot-server-deploy's and are not read here.
- The old `cfg/server/dot_map/maps.yml` and the flat `cfg/maps.yml` are read through `DotCfgLegacy` (one WARN each, until 2026-12-31); the new path wins whole when both exist.
- A game sets `DotAddonConfig.game` (or passes its name to `find_layers`) so the game tiers are read.

The rest of this page is the original design, kept for the reasoning; where it names `cfg/server/<addon>/`, read `cfg/server/addons/<addon>/`.

## Survey: what exists today

- **dot-core `DotAddonConfig`** already reads every `*.yml` in `cfg/addons/<addon_name>/`, sorted by file name, over four roots (`res://cfg`, `<exe>/cfg`, `user://cfg`, `--config DIR`), with env `<ADDON>_<PATH>` and cli `--<addon>.<path>=v`, and refuses secret-named keys from both. One adopter: game-zombie-zone (`zz_packs.gd`, `cfg/addons/zombie_zone/packs.yml`). **Gap: the directory is the addon name as passed**, so `"dot-map"` reads `cfg/addons/dot-map/`, while the packs already use underscores (`zz_medieval_weapons`, `zz_modern_weapons`, `zz_historical_monsters`, `zombie_zone`). Normalise `-` to `_` in `_candidate_dirs`.
- **dot-core `DotProfileSet`** (`docs/profiles.md`) already has the tiers `cfg/addons/<addon>/<kind>/<id>.yml` < `cfg/game/<game>/<kind>/<id>.yml` < `cfg/server/addons/<addon>/<kind>/<id>.yml` < `cfg/server/game/<game>/<kind>/<id>.yml` (the old `cfg/server/<kind>/` is shimmed).
- **dot-server-deploy `cfg/`** (what an operator edits, via `--config DIR`): flat files read by `host/tmc_config.gd` `FILES`: `server.yml`, `net.yml`, `log.yml`, `rcon.yml`, `auth.yml`, `groups.yml`, `permissions.yml`, `vote.yml`, `security.yml`, `party.yml`, `matchmaking.yml`, `replay.yml`, `admin_menu.yml`, `loading.yml`; plus `content.yml` (per-game overrides, `TmcGameConfig`), `addons.yml` (extra packs, `TmcAddonsConfig`), `games.yml` (`TmcGameRotation`). `server.yml` today mixes generic keys (`sv_name`, `sv_maxplayers`, timeouts) with whole subsystems.
- **dot-server**: `cfg/server.cfg` and `autoexec.cfg` (console cvar scripts), `user://cfg/server.json`, `admins.json`, `bans.json`. Console scripts are not yaml settings and stay.
- **dot-server-security**: `cfg/*.example.json` (ban feeds, rules), shipped as examples only.
- **Rotation**: dot-map `DotMapRotationFile.find()` looks for `cfg/maps.yml` (or the name in `sv_map_rotation_file`) in the `--config` dir, `res://`, `user://`, beside the executable. Its shape is `defaults:` / `games:` with named rotations, the same as `content.yml`. mg-deathrun ships `cfg/maps.yml`; mg-wipeout and mg-dangerous-delivery name the cvar. The per-game `content.yml` also carries `metadata.map_vote` (dot-vote settings) per game.
- **Packs**: zz-medieval-weapons, zz-modern-weapons, zz-historical-monsters already ship `cfg/addons/<pack_underscored>/<id>.yml`, one file per profile at the top of the addon folder, not under a kind folder.
- **Per-map files**: mg-wipeout-maps `cfg/wo_<course>.cfg` (cvar lines per course). These are map content, not server settings; out of scope, stay with the map pack.

## The layout

```
cfg/
  server.yml                      generic server settings only
  addons/<addon_underscored>/     one folder per addon or pack: *.yml, then <kind>/<id>.yml
    dot_map/maps.yml
    dot_vote/vote.yml
    dot_server_security/security.yml
  game/<game>/                    the game's layer over the addons, same shape
    dot_map/maps.yml              this game's rotation over the addon default
    weapon/pistol.yml             profile kind, a few keys over the addon's pistol
  server/                         the operator's profile overrides (DotProfileSet tier; see below)
```

`<addon_underscored>` is the repository or pack directory name with `-` as `_`. `<game>` is the game's directory name (`game-zombie-zone`, `mg-deathrun`), not its pack id, because a directory is what a developer sees; the pack id `gamemann/<repo>` is accepted as an alias by the reader.

Two file shapes inside one addon folder, nothing else:

1. **Settings**: `*.yml` directly in the folder, read by `DotAddonConfig`, merged in file-name order (`10-base.yml`, `90-server.yml`).
2. **Profiles**: `<kind>/<id>.yml` (or `<kind>/<id>/<id>.yml`), read by `DotProfileSet`, one entity per file. A folder with a profile-kind name is never read as settings.

## Rule: where a setting lives

Ask in order; the first yes decides.

1. **Does a process need it before any addon exists, or does every game and server have it?** Name, port, tick rate, max players, timeouts, bind address, region. It goes in `cfg/server.yml`, flat `sv_*`/`net_*` keys exactly as today. Generic means no addon owns the key.
2. **Does one addon read it?** Then it is that addon's, in `cfg/addons/<addon>/`, whatever the topic: map rotation is dot-map's, the vote is dot-vote's, replay is dot-replay's, rcon is dot-console's. `server.yml` never grows a subsystem block.
3. **Is it a value only one game sets?** `cfg/game/<game>/<addon>/`, a file with only the keys it changes.
4. **Is it one entity among many (weapon, monster, class, NPC)?** A profile under `<kind>/<id>.yml`, never a key in a big file.
5. **Secret** (password, token, secret, `*_key`): never in env or argv. Stays in a file with restricted permissions, in `server.yml` or the addon's folder, refused by `DotConfig.sensitive_keys` and `DotAddonConfig`'s word filter exactly as today. This design adds no new way to set one. `rcon_password` leaves the shipped default file (see inventory).

`server.yml` is flat generic settings; it has no `defaults:`/`games:` nesting. Per-game server settings go in `cfg/game/<game>/server.yml`, same keys, applied over the generic file for that game only.

## Precedence

Weakest first, every setting, one order:

```
code defaults  <  cfg/addons/<addon>  <  cfg/game/<game>  <  cfg/server.yml (generic) / cfg/server/addons/ and cfg/server/game/ (operator profile overrides)  <  environment  <  command line
```

- Within a tier the four roots merge weakest first (`res://cfg`, `<exe>/cfg`, `user://cfg`, `--config DIR`), so a game ships its tier in the pack and the operator changes it in `--config DIR` without editing shipped files. Within one root, files merge in name order. Maps merge key by key; lists and scalars replace whole.
- Tier beats root: the tier order above is absolute, and roots only order files inside one tier. So an operator editing `DIR/addons/dot_map/` would lose to the game's `cfg/game/<game>/` file. **The operator's layer is therefore its own tier, `server`**: `DIR/server/<addon>/*.yml` for settings and `DIR/server/<kind>/<id>.yml` for profiles (the `cfg/server/` tier `DotProfileSet` already has, generalised to settings), and `cfg/server.yml` is the generic file beside it. One word, "server", means the operator's layer everywhere.
- Env and cli keep their present spelling (`DOT_MAP_ROTATION_MODE`, `--dot-map.rotation.mode=`, `PROFILE_<KIND>_<ID>_<KEY>`, `--sv-*`). Typed, existing keys only. `DotConfig` subclasses keep `env_prefix`/`cli_prefix`.

## Migration shim

Principle: a reader gains the new path and keeps the old one for a fixed time. No game is edited in the same commit as the reader.

- New dot-core `DotCfgLegacy` (static, tiny): `find(old_path, new_path) -> String` returns the new path when it exists, else the old one with a **one-time** `DotLog.warn("cfg", "…")` per old path naming both, the removal date and the file it found. A static `Dictionary` of warned paths prevents repeats across reloads. Level WARN is right: recoverable, somebody should look.
- Shim removal date: **2026-12-31** (about ten weeks). After it the reader ignores the old path and logs ERROR once if the old file exists and the new one does not. Put the date in one constant, `DotCfgLegacy.REMOVE_AFTER`, so the greps find it.
- The old and new files are never both merged: new wins entirely, and the warning says so when both exist. (Merging would hide a stale file.)
- dot-server-deploy `tmc_config.gd` reads `FILES` through the shim: a flat `vote.yml` found in `--config DIR` is treated as `addons/dot_vote/vote.yml`; `server.yml` keys that belong to a subsystem are routed by a table (`LEGACY_KEYS: key -> addon`) with one WARN naming the keys moved.
- `./server upgrade` (dot-server-deploy) offers `./server cfg-migrate` that moves the files and rewrites `server.yml`, keeping a `cfg.bak/` copy. Not automatic: the operator's edits are theirs.

## Migration inventory

| Setting | Old path | New path | Owner |
| --- | --- | --- | --- |
| rotation, wildcards, `commands:` | `cfg/maps.yml`, `sv_map_rotation_file` | `cfg/addons/dot_map/maps.yml`; game's `cfg/game/<game>/dot_map/maps.yml` | dot-map |
| game's shipped rotation | `mg-deathrun/cfg/maps.yml` (and any game's) | `mg-deathrun/cfg/game/mg-deathrun/dot_map/maps.yml` | each game |
| map vote, time limit | `content.yml` `metadata.map_vote`, `vote:` | `cfg/addons/dot_vote/map_vote.yml`, game layer for per-game | dot-vote |
| game vote (enabled, exclude) | `cfg/vote.yml` | `cfg/addons/dot_vote/vote.yml` | dot-vote |
| log level, channels | `cfg/log.yml` | `cfg/addons/dot_log/log.yml` | dot-log |
| rcon port, allowed, password | `cfg/rcon.yml` | `cfg/addons/dot_console/rcon.yml`; password stays file-only, no default shipped | dot-console |
| backend url, timeout | `cfg/auth.yml` | `cfg/addons/dot_auth/auth.yml` | dot-auth |
| groups, users | `cfg/groups.yml`, `permissions.yml` | `cfg/addons/dot_server/groups.yml`, `permissions.yml` | dot-server |
| security | `cfg/security.yml` | `cfg/addons/dot_server_security/security.yml` | dot-server-security |
| party | `cfg/party.yml` | `cfg/addons/dot_party/party.yml` | dot-party |
| matchmaking | `cfg/matchmaking.yml` | `cfg/addons/dot_matchmaking/matchmaking.yml` | dot-matchmaking |
| replay | `cfg/replay.yml` | `cfg/addons/dot_replay/replay.yml` | dot-replay |
| admin menu | `cfg/admin_menu.yml` | `cfg/addons/dot_menu/admin_menu.yml` | dot-menu |
| loading cover | `cfg/loading.yml` | `cfg/addons/dot_core/loading.yml` | dot-core |
| bind, port, public ip | `cfg/net.yml` | `cfg/server.yml` (`net_*`) | dot-server-deploy |
| name, max players, timeouts, tick rate | `cfg/server.yml` | `cfg/server.yml` (unchanged; subsystem blocks removed) | dot-server-deploy |
| per-game cvars, name, max players | `cfg/content.yml` | `cfg/game/<game>/server.yml` (cvars under `cvars:`); `content.yml` shim kept | dot-server-deploy |
| extra packs | `cfg/addons.yml` | unchanged: it is content selection, not a setting, and its name is already taken by the new folder; rename to `cfg/packs.yml`, shim old | dot-server-deploy |
| game rotation (which game) | `cfg/games.yml` | `cfg/game_rotation.yml`, shim old | dot-server-deploy |
| weapon/monster profiles | `cfg/addons/<pack>/<id>.yml` | `cfg/addons/<pack>/weapon/<id>.yml` (monster: `monster/`) | each pack |
| zombie-zone packs | `cfg/addons/zombie_zone/packs.yml` | unchanged | game-zombie-zone |

The two-line `defaults:`/`games:` shape of `maps.yml` and `content.yml` is kept inside the file for the shim period; once the game layer exists, `games:` is redundant (`cfg/game/<game>/` replaces it) and is dropped in the second phase, with a WARN while present.

## How dot-server-deploy and packs ship defaults

- **Packs ship defaults inside the pack**, in `res://cfg/addons/<pack>/` and `res://cfg/game/<game>/`. A new pack version replaces them, which is right: they are the author's. Pack export presets need `cfg/*` in `include_filter` (already documented in `addon-config.md`); dot-ci's export check should fail a pack with `cfg/` and no filter.
- **dot-server-deploy ships a commented example tree** `cfg/` (`server.yml`, `server/README.md`, `addons/<name>/*.example.yml`), not live files. Operators copy what they change into `--config DIR`. Live files shipped as defaults get edited in place and then conflict with the next update, which is how a test `rcon_password` reached the shipped `cfg/rcon.yml`. Only `*.example.yml` ship; the reader skips `*.example.yml`.
- `setup.sh` and `./server install` create `DIR/` with `server.yml` only; the rest appear when an operator needs them.
- `content/<game>/game.yml` (author defaults inside a pack) keeps its `cvars:` and `metadata:`; the operator layer on top is `cfg/game/<game>/server.yml`, replacing `content.yml`.

## Documentation updates

- `dot-core/docs/addon-config.md`: underscore normalisation, the `server` tier, `*.example.yml` skipped. `dot-core/docs/profiles.md`: settings and profile kinds share one tree; the "not done yet" adopter list gets the packs' `weapon/`, `monster/` kinds.
- New `dot-core/docs/cfg-layout.md` (short, links here) as the family reference; this file in dot-map keeps the map-specific part once the migration is done.
- `~/CLAUDE.md`: the "Configuration is layered" bullet gains the tier order (add the addon/game/server tiers and `cfg/server.yml`); docs table row for the new file.
- `docs/family.md` (dot-core and dot-server-deploy entries), `docs/extension-points.md` (config row), `docs/testing.md` if a suite is added.
- dot-map `README.md`, `CLAUDE.md` ("`cfg/maps.yml`" in the layout table), `docs/rotation.md`; dot-server-deploy README and `content/*/game.yml` header comments that name `cfg/server.yml` keys or `content.yml`.
- Each migrated addon's README line naming its old file.

## Tasks, in order

1. **dot-core** (held by another agent now; wait or hand over): underscore normalisation in `_candidate_dirs`; `server` tier for settings; `*.example.yml` skip; `DotCfgLegacy`; self-test cases (old path warns once, new path wins, both present). Bump the API level.
2. **dot-map**: `DotMapRotationFile.find()` looks in `addons/dot_map/maps.yml`, then `game/<game>/dot_map/maps.yml`, then legacy `maps.yml` via the shim; keep `sv_map_rotation_file` as an explicit override. Suite: `examples/map_selftest.tscn` plus a case per path. Doc updates for dot-map.
3. **dot-server-deploy**: `tmc_config.gd` reads `server.yml` plus routed addon folders through the shim; example tree; `./server cfg-migrate`; rename shims for `addons.yml`/`games.yml`; remove the live `rcon_password` default.
4. **Addons one at a time, each a small commit** (dot-vote, dot-log, dot-console, dot-server-security, dot-party, dot-matchmaking, dot-replay, dot-menu, dot-auth): read their folder via `DotAddonConfig`, falling back through the shim. One builder per addon repo.
5. **Games and packs**: move shipped `cfg/maps.yml` (mg-deathrun first, then the games that name `sv_map_rotation_file`), pack profile files into kind folders, game cvars out of deploy's `content.yml`. One builder per repo; each runs `./game.sh test`.
6. **Docs** (the list above) in the same commits as their code; `~/CLAUDE.md` last.
7. **2026-12-31**: delete the shim and the legacy tables; sweep with `grep -rn "DotCfgLegacy"`. Put it on a nightly item with that date.

## Open questions

- Is `cfg/server/` (operator layer for settings and profiles) acceptable beside `cfg/server.yml`, or should the operator layer be named something else to avoid two "server" entries? (Settled: it mirrors `addons/` and `game/`.)
- Game key: directory name (`mg-deathrun`) as proposed, or the content id half (`deathrun`)?
- Does the web client (no `--config`, `user://` only) need any of the operator layer, or is it server-only?
