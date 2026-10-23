# The input/output runtime

`addons/dot_map/io/`, work package 5 of [converter-v2.md](converter-v2.md). It runs the logic a converted map carries as outputs (a trigger enables a hazard after 3 s, a timer adds to a counter, a counter breaks a window) on the server, from the game's tick. Only dot-core is needed.

## Why it is shaped like this

- **Time is the game's tick.** `advance(ticks)` is the only thing that moves `now`; a link's delay is `round(delay * rate)` ticks. A replay, or a server at another tick rate, gives the same order. Events due on the same tick run in the order they were queued, which is the order of the links in the file.
- **Fire, then deliver.** `fire(entity, output)` only queues one event per link; a target is resolved when its event is delivered, so an entity killed or renamed in between is simply not found, and `*` patterns, class names and `!self`/`!activator`/`!player` work. `times` is spent at queue time and the link is removed at zero.
- **A loop is cut by chain depth, not by a ban.** A cycle with a delay in it (two relays re-triggering each other every second) is legal and runs. A zero-tick cycle is the only way to hang a tick, so an event queued on the tick it was caused on carries `depth + 1`, dropped past `max_chain` (64) and counted in `loop_trips`; a tick also stops at `max_events_per_tick`.
- **Randomness is a stream per entity** (`DotRandomStream` from `rng_seed` and the entity's index), so a `logic_case` pick or a random timer repeats for the same seed and does not move when another entity draws.
- **Commands are never run.** `point_servercommand` records `{tick, text, name, kind, allowed}` in `commands`. A chat line and a cvar in `command_allow` go on to the game's `event` callable; everything else is `denied`, counted and logged. The per-map config layer ([map-config.md](map-config.md)) is where an allowed cvar is applied.

## What a map gives it and what it gives back

`load_document(doc)` reads the lossless store's `dot-bsp-source` document (`entities[].index, classname, targetname, parentname, pairs, outputs`); `load_records(records)` takes the same records from any other source and is the one interface the loader sits behind. A foreign format is `CODE_PARSE`, a newer version `CODE_VERSION`. `state_changed(entity, key, value, tick)` is the only way out of the logic classes (`enabled`, `color`, a counter's `value`); `snapshot()` is the same for a joiner. `coverage()` lists inputs no class or handler implemented, calls to a callable the game did not set, unresolved targets, loops and denied commands.

## Classes

`DotMapEntity` is the base: `Kill`, `KillHierarchy`, `AddOutput` (key form and output form), `FireUser1..4`, `Enable`/`Disable`/`Toggle`/`TurnOn`/`TurnOff`, `Color`, `StartDisabled`. On top: `DotMapRelay` (`logic_relay`, fire-once, `CancelPending`), `DotMapTimer` (`logic_timer`, fixed or seeded random interval, high/low), `DotMapCounter` (`math_counter`), `DotMapCase` (`logic_case`, `PickRandom`, `PickRandomShuffle`), `DotMapCompare`, `DotMapBranch`, `DotMapAuto` (`logic_auto`), `DotMapTrigger` (`trigger_multiple`/`trigger_once` as logic; the game says when a body touches it with `DotMapIO.touch`), `DotMapServerCommand`. Not done: `math_colorblend`, `logic_measure_movement`, `env_global`, `point_template`.

## Where a game plugs in

| To change | Where |
| --- | --- |
| What an input means for a game class (a hurt volume, a door, a breakable) | `register_handler(classname, fn(entity, input, param, activator, caller) -> bool)`, asked before the built-in inputs; true claims it |
| A class with state of its own | `register_class(classname, script)` with a script extending `DotMapEntity` |
| Damage, pushing a body, an effect, a text/hint/score/equip/chat/cvar event, an input aimed at the player | `damage_fn`, `move_fn`, `effect_fn`, `event_fn`, `actor_fn`; unset ones are counted no-ops |
| Which cvars a map may set | `command_allow` |

## Test

`examples/io_demo.tscn` (headless) runs delays, fire-once counts, cycles, the logic classes, the extension points and Office's real chains from `examples/io/office_io.doc.json`, the part of `mg_office_coursee`'s source document reachable from its map-start logic and its timed trigger. The expected times are read from the map's own links first. Findings: the map has 11 hurt volumes that start disabled (nine in `Obstacle6`, one in `Obstacle2`, `Spawn_HURT`). `Obstacle2`'s trigger, on entry, undoes everything at once, turns the hurt volume, the four steam entities and the red colour on at 3 s and re-arms itself at 6 s; nothing turns the hurt volume off at 6 s, it stays on until the next entry. `Obstacle6` enables one random hurt volume per lane at map start (three `logic_case` picks), and `Spawn_HURT` comes on 20 s after map start.
