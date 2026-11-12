# Rotation, voting and the time limit

## Rotation

**The cooldown is the whole design of a rotation.** Without one a server plays the same three popular maps for ever, because a vote is a popularity contest and popularity does not change between rounds.

The cooldown is **clamped to half the pool at choosing time**, not when it is set: a cooldown of eight on a server with six maps in rotation excludes everything, and the honest behaviour is to shorten the memory rather than to return nothing, which would leave the server on its current map for ever with no error anywhere. A pool of one repeats.

**The random mode is seeded and the seed advances deterministically**, so a client can show the same "next map" the server will pick without asking. A time-based reseed would make that prediction wrong.

## `DotMapVote`

**A vote's tie-break is deterministic and is not random.** Two maps on four votes each resolved by a coin flip means a client's live tally and the server's result can disagree, and the players who watched it read that as the vote being rigged. Ties go to the option nominated first.

- **Only some of the ballot is reserved for nominations.** All of it, and one organised group of three decides every map on a twenty-player server.
- **The current map is never an ordinary option.** "Play this again" is what the extend option is for, and having both splits the vote of the people who want the same thing.
- **A tie with extend goes to the new map.** The players who wanted something new are the ones who lose by staying, and a server that ties toward the status quo never changes map.

The commands (`rtv`, `nominate`, `nextmap`, `timeleft`) and the ballot on screen are dot-vote's and dot-ui's; this is the tally and the rule.

## The map has to end on its own

**A server that never changes map is not a server.** Somebody joins, plays the map they arrived on, and leaves, and the rotation, the catalogue and the vote all exist and are never reached. `DotMapTimeLimit` is the three mechanisms every long-lived server in this genre has, and each covers a case the others do not: a **time limit** so a map ends when nobody asks, **rock the vote** so one everybody hates ends early, and **extending** so one everybody is enjoying does not end on a timer.

**Counted in simulated seconds, advanced by the host**, never a wall clock: a server that stalls for ten seconds should not lose ten seconds off its map, and a test must be able to run an hour of it in a millisecond. Same choice `DotPropSpawner.advance` makes.

- **The expiry is latched.** The host's response is to run a vote and change the map, and both take time; without the latch a limit that reached zero would fire on every tick until the map changed: a vote opened at the tick rate.
- **Extending is bounded.** The people still on a map are the people who like it, so an unbounded extend means a popular map runs until everybody else has left.
- **Extending clears the rock-the-vote tally.** The players who wanted it to end have just been outvoted; carrying their votes forward ends the map the moment one more person joins and agrees.
- **Rocking the vote is idempotent per player.** Typing it twice is what somebody does when nothing visible happened, and counting it twice would let two people end a map for six.
- **A player who leaves takes their vote with them** (`unrock`). Otherwise a server whose players trickle away keeps their votes while the threshold falls, and a map ends on the votes of people who are not there.

`DotMapSession` emits `map_over` and **does not change the map itself**. What happens when a map ends is a game's decision (run a vote, take the next in the rotation, end the round first, show a scoreboard), and a session that decided would have to be fought by every game that wanted any of those.

The clock can wait while the server hibernates: `DotMapSession.follow_hibernation(server)` (duck-typed on `hibernation_changed(bool)`) or `set_hibernating`; `restart_on_wake` (default on) starts the map's own limit again on waking.

## The rotation file

`cfg/addons/dot_map/maps.yml` says which installed maps rotate (the game's `cfg/game/<game>/dot_map/maps.yml` over it, then the operator's `cfg/server/addons/dot_map/maps.yml` and `cfg/server/game/<game>/dot_map/maps.yml`; an operator file replaces the shipped list unless it starts `merge: true`, and `exempt:` keeps maps out (see below); [layout](cfg-layout.md#what-is-built-for-the-rotation-file); with no file every installed map rotates, sorted by id; the old `cfg/server/dot_map/maps.yml` is read through the shim too; the flat `cfg/maps.yml` is still found through `DotCfgLegacy` with one WARN until 2026-12-31, and `DotMapRotationFile.find("cfg/maps.yml")` does all of that; `find_layers` lists the new-layout files weakest first), in the shape of the server's content.yml: `defaults:` for every game and `games: <game>:` for one, read by `DotMapRotationFile`. Layers, weakest first: the game's shipped file, the server's defaults, the game's own entry. A list replaces a list; scalars merge.

```yaml
defaults:
  rotation: surf
  rotations:
    surf:
      mode: random        # random or cycle (written order)
      cooldown: 3
      maps: [bhop_intro, "surf_*", owner/collection/*]
    all:
      maps: ["*"]
games:
  game-example:
    rotation: all
```

A bare `maps:` list is shorthand for a rotation called `main`; if `rotations: main` is also written it wins, with one WARN. Entries are `owner/map`, a bare name, `owner/collection/*`, or a name glob against the installed catalogue (quote a glob that starts with `*`: YAML refuses it bare). An id or pattern that matches nothing logs a WARN; a rotation that resolves to nothing plays the whole catalogue.

An unlisted map stays installed and loadable (`map <id>`, the map list marks it "not in rotation") but is out of the rotation's pool, `set_next`, the ballot and nominations: all read `DotMapDef.in_rotation`. `sv_map_rotation <name>` switches the active rotation at run time (admin), `maps_rotations` lists them. A host calls `DotMapRotationFile.load_files`, then `attach(session)` so a catalogue change re-applies it; `collections` must be filled by a host that has them for `owner/collection/*` to match.

`DotMapRotationFile.find(stem, config_dir)` looks in the host's `--config` directory first (`config_dir_arg()` reads the flag), so a server started with `--config /etc/x` is not silently skipped. When a rotation lists nothing that is installed, every map plays, unless the game sets `fallback_in` (`(DotMapDef) -> bool`) to keep some out, the way it does with no file at all. A sequential rotation never offers the map it just played, even when a forced or voted map moved the cursor under the cycle.

### Listing what plays, or exempting what does not

Two modes. **Include:** `maps:` lists what plays. **Exempt:** `exempt: [patterns]` keeps every installed map and takes some out. A file with only `exempt:` (no `maps:` anywhere) plays every installed map except those, sorted by id, and maps from mounted workshop or suggested packs that arrive later join it, because `content_refreshed` re-applies the file. `remove:` is the old name of the same key and is read the same way (the key is read once when the file is read, never per map).

```yaml
exempt: [dm_old_map, "dm_test_*", alice/some_map]
```

- Patterns are ids, `owner/map` refs and name globs; quote one that starts with `*`. One that matches nothing logs a WARN once, like an include entry.
- `exempt:` is read at the top of any layer, inside `defaults:` or a game's entry, and inside one rotation (`rotations: <name>: exempt:`, which applies to that rotation only). A rotation written with only `exempt:` plays every installed map but those.
- Exempt wins over an include in the same layer or any other; an operator layer with `merge: true` adds exempts to a shipped list.
- An exempt map stays installed and loadable (`map <id>`), is marked "not in rotation" and is out of the pool, ballot and nominations (`DotMapDef.in_rotation`). Exempting every map falls back to every map, with one WARN, so the server is never left with nothing to play.

## Per-map settings

A rotation entry may be a mapping, `- "zz_camp_*": {waves: camp_nights}` or `- {map: other, waves: hard}` (dot-core's `DotRotationSpec`, which stays a plain id list for everything else). `DotMapRotationFile.apply` copies each in-rotation map's settings into `DotMapDef.play` (runtime, never saved, opaque to dot-map; empty for a bare string, and cleared when another rotation is applied). `DotMapRotationFile.settings_for(catalogue, id)` answers the same for one id. `DotMapDef.play_candidates(key, override, fallback)` returns the values to try in order: a server command's (`sv_waves`), the entry's, then the map document's or the game's default; the game tries each and warns on one it does not know. The `sv_waves` command itself belongs to the game, since dot-map does not know what a wave is.

## Per-map profiles

Any map can run in any mode the game supports, per rotation. A rotation entry, a rotation or a whole section may name a profile with `mode:` or `cfg:`; the two keys are aliases (when both are written and differ, `mode:` wins with one WARN). The rotation file is read by dot-core's `DotYaml`, which refuses flow mappings (`{...}`), so write entries in block form:

```yaml
defaults:
  mode: tdm                  # section default: every rotation below, unless it names its own
  rotations:
    main:
      mode: cycle            # cycle/random/sequential still picks the order; use cfg: for the profile
      cfg: ctf               # rotation default for its entries
      maps:
        - cp_orange_x3       # plays ctf (the rotation's)
        - map: dm_arena      # entry form
          mode: ffa
        - cp_well:           # single-key form
            cfg: koth
        - owner/coll/*:      # a glob or collection: applied to every match
            mode: tdm
        - map: ctf_night
          cfg: night/fast    # a path: cfg/night/fast.yml
```

Precedence is entry, then rotation, then section; a stronger file layer replaces a weaker one's default.

What the value means (`DotMapRotationFile.resolve_profile`):

- A bare word (no `/`, not ending in `.yml`/`.yaml`) is a **mode id**. If `cfg/<id>.yml` (or `.yaml`) exists in the dot_map config tiers (`cfg/server/addon/dot_map/cfg/ctf.yml` for an operator, with the same `--config` and tier rules as `maps.yml`), its cvars apply too. No file is fine: the mode alone.
- A relative path is a file under that same `cfg/` directory; the extension may be left off. Its own `mode:` key names the mode.
- An absolute path (`/`, `res://`, `user://`) is read as is.
- A path that is not found, or does not parse, logs ONE WARN and the entry still plays, with the game's default mode and cvars. A profile never removes a map from the rotation.

A profile file is a map of cvars, either top-level `key: value` lines or under `cvars:` (nested values are skipped):

```yaml
mode: ctf          # only read when the file is named by path
cvars:
  timelimit: 20
  capturelimit: 3
```

The resolved profile lands on `DotMapDef.profile` as `{value, mode, cfg_path, values}` (runtime, never saved, empty for none), set by `DotMapRotationFile.apply` next to `DotMapDef.play`. `profile_for(catalogue, id, rotation)` and `profile_value(...)` answer per id, and `profile_changed(map, profile)` fires on each map change for a session the file is attached to (`note_changed(map)` emits it for a game that follows `DotMapSession.changed` itself). dot-map never reads the mode or the cvars: a game with modes applies them on the map change and restores its own values on the next; a game without modes ignores the profile.

`DotMapConfig.apply_values(map_id, values)` applies such a `values` map the way `apply(map_id)` applies a map's own files: checked against the config's whitelist, and put back on the next `apply`/`apply_values`/`restore`, except a key an operator changed meanwhile.
