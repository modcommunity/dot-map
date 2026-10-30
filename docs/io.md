# The input/output runtime

`addons/dot_map/io/`, work package 5 of [converter-v2.md](converter-v2.md). It runs the logic a converted map carries as outputs (a trigger enables a hazard after 3 s, a timer adds to a counter, a counter breaks a window) on the server, from the game's tick. Only dot-core is needed.

## Why it is shaped like this

- **Time is the game's tick.** `advance(ticks)` is the only thing that moves `now`; a link's delay is `round(delay * rate)` ticks. A replay, or a server at another tick rate, gives the same order. Events due on the same tick run in the order they were queued, which is the order of the links in the file.
- **Fire, then deliver.** `fire(entity, output)` only queues one event per link; a target is resolved when its event is delivered, so an entity killed or renamed in between is simply not found, and `*` patterns, class names and `!self`/`!activator`/`!player` work. `times` is spent at queue time and the link is removed at zero.
- **A loop is cut by chain depth, not by a ban.** A cycle with a delay in it (two relays re-triggering each other every second) is legal and runs. A zero-tick cycle is the only way to hang a tick, so an event queued on the tick it was caused on carries `depth + 1`, dropped past `max_chain` (64) and counted in `loop_trips`; a tick also stops at `max_events_per_tick`.
- **Randomness is a stream per entity** (`DotRandomStream` from `rng_seed` and the entity's index), so a `logic_case` pick or a random timer repeats for the same seed and does not move when another entity draws.
- **Commands are never run.** `point_servercommand` records `{tick, text, name, kind, allowed}` in `commands`. A chat line and a cvar in `command_allow` go on to the game's `event` callable; everything else is `denied`, counted and logged. The per-map config layer ([map-config.md](map-config.md)) is where an allowed cvar is applied. `point_clientcommand` is recorded as kind `clientcommand`, never allowed and never sent to `event`; a chat line starting with `!` or `/` is refused.

## What a map gives it and what it gives back

`load_document(doc)` reads the lossless store's `dot-bsp-source` document (`entities[].index, classname, targetname, parentname, pairs, outputs`); `load_records(records)` takes the same records from any other source and is the one interface the loader sits behind. A foreign format is `CODE_PARSE`, a newer version `CODE_VERSION`. `state_changed(entity, key, value, tick)` is the only way out of the logic classes (`enabled`, `color`, a counter's `value`); `snapshot()` is the same for a joiner. `coverage()` lists inputs no class or handler implemented, calls to a callable the game did not set, unresolved targets, loops and denied commands.

## Classes

`DotMapEntity` is the base: `Kill`, `KillHierarchy`, `AddOutput` (key form and output form), `FireUser1..4`, `Enable`/`Disable`/`Toggle`/`TurnOn`/`TurnOff`, `Color`, `StartDisabled`. On top: `DotMapRelay` (`logic_relay`, fire-once, `CancelPending`), `DotMapTimer` (`logic_timer`, fixed or seeded random interval, high/low), `DotMapCounter` (`math_counter`), `DotMapCase` (`logic_case`, `PickRandom`, `PickRandomShuffle`), `DotMapCompare`, `DotMapBranch`, `DotMapAuto` (`logic_auto`), `DotMapTrigger` (`trigger_multiple`/`trigger_once` as logic; the game says when a body touches it with `DotMapIO.touch`), `DotMapServerCommand`. `DotMapColorBlend` (`math_colorblend`, `OutColor`), `DotMapMeasureMovement` (`logic_measure_movement`: holds the four names and tells the game through the `measure_movement` event, the runtime has no positions), `DotMapGlobal` (`env_global`, a flag and a counter shared through `DotMapIO.globals`) and `DotMapTemplate` (`point_template`: `ForceSpawn` copies each named template through `spawn_record`, with a `template_spawn` event per copy for the game to place; unless preserve-names is set, a copy's outputs and parent that name another entity of the set follow its numbered name, as the original engine does, so a copy kills its own set's copy), `DotMapGameScore` (`game_score`: the `score` event with points, team and activator), `DotMapGameUi` (`game_ui`: Activate takes one player's controls, `DotMapIO.feed_ui` turns the buttons they hold into the Pressed/Unpressed/axis outputs, the `ui_active` event asks the game to freeze them) and `DotMapCollisionPair` (`logic_collision_pair`: the `collision_pair` event, `collide` false means pass through).

## Map scripts

`lua_run` is never executed and its `code` key is never read at run time. At ship time the converter (`tools/bsp/dotbsp/scripts.py`) matches each snippet whole against a few exact templates (data, `fullmatch`, no eval) and writes `script: {status, ops, category}` on the entity in the shipped `doc.json`; the manifest's `scripts` lists every snippet with `status` (`translated` or `unhandled`), `category` (`template`, `wire`, `definition`, `passed call`, `empty`, `other`), the snippet text and how many outputs fire it. `RunCode` on a `DotMapScript` replays the translated operations to `event_fn` as `script.set_player_speed {kind: run|walk, value}`, `script.kill_players` and `script.cleanup_map {delay}`, each re-validated against a range table, so a forged document gains nothing. Untranslated snippets and `RunPassedCode` (a call into a function the map's addon defines) are recorded in `scripts` as refused and counted in `coverage()["scripts_refused"]`. `bsp.py store --scripts` prints the inventory: 17 distinct shapes in the 106 stored maps, 3 translated (two player speeds, a kill-and-reset), the rest WireMod output toggles (58 uses), helper definitions and four calls into a prop-hunt addon, left for hand porting in an addon.

## The catalogue

`load_catalogue()` reads `catalogue.json` beside `dot_map_io.gd`: every class the scanned maps use plus the classes a component implements, with input and output names (lower case to written name) and each key's type and default, the base entity's set stored once under `common`. `tools/bsp/defs/runtime.py` writes it from `tools/bsp/rules/entity_defs.json`; regenerate it whenever that file changes. `coverage()` uses it to say whether an input nothing implemented is a real engine input (`known`) or a typo (`not in the catalogue`); `class_def(name)` gives a game the defaults of a class's keys.

## Where a game plugs in

| To change | Where |
| --- | --- |
| What an input means for a game class (a hurt volume, a door, a breakable) | `register_handler(classname, fn(entity, input, param, activator, caller) -> bool)`, asked before the built-in inputs; true claims it |
| A class with state of its own | `register_class(classname, script)` with a script extending `DotMapEntity` |
| Damage, pushing a body, an effect, a text/hint/score/equip/chat/cvar event, an input aimed at the player | `damage_fn`, `move_fn`, `effect_fn`, `event_fn`, `actor_fn`; unset ones are counted no-ops |
| Which cvars a map may set | `command_allow` |

## Test

`examples/io_demo.tscn` (headless) runs delays, fire-once counts, cycles, the logic classes, the extension points and Office's real chains from `examples/io/office_io.doc.json`, the part of `mg_office_coursee`'s source document reachable from its map-start logic and its timed trigger. The expected times are read from the map's own links first. Findings: the map has 11 hurt volumes that start disabled (nine in `Obstacle6`, one in `Obstacle2`, `Spawn_HURT`). `Obstacle2`'s trigger, on entry, undoes everything at once, turns the hurt volume, the four steam entities and the red colour on at 3 s and re-arms itself at 6 s; nothing turns the hurt volume off at 6 s, it stays on until the next entry. `Obstacle6` enables one random hurt volume per lane at map start (three `logic_case` picks), and `Spawn_HURT` comes on 20 s after map start.

## Volumes: hurt, push, teleport, gravity, trigger, ladder, water

Work package 7. `DotMapVolumes.build(entities, io)` joins each manifest volume to its `DotMapEntity` by index (the geometry is the volume's, the behaviour and outputs the entity's) and `step(bodies)` runs once a tick after `io.advance(1)`. A body is `{id, body, position (feet), height, kind: player|npc|pushable|physics, name, class}`; the volume tests the body's whole column, feet to head (`DotMapVolume.touches_column`, a segment against each convex brush, 3 cm of slack under the feet), so a belt laid flat on a floor catches a body standing on it. A disabled or killed entity makes its volume empty, so enabling it again with somebody still inside is a new entry, as the original does, and that is what makes a timed hazard catch a player who waits.

| Class | Does |
| --- | --- |
| `trigger_hurt` (`DotMapHurt`) | `damage` a second times `hurtrate` (0.5) per hit, the first on entry, through `damage_fn(body, amount, kind, attacker)`; `damagetype` bit to kind; `damagemodel` 1 doubles to `damagecap`; OnHurt, OnHurtPlayer, SetDamage |
| `trigger_multiple` / `trigger_once` (`DotMapTrigger`) | OnStartTouch on entry, OnTrigger then the `wait` (again after it while the body stays), OnEndTouch, OnStartTouchAll / OnEndTouchAll, spawnflags by body kind, `filter_activator_name`, `filter_activator_class` and `filter_activator_team` (the body's `team`; a body without one is admitted and counted) (other filter classes admit everyone and are counted in `unhandled`) |
| `trigger_push` (`DotMapPush`) | the push velocity (a `Vector3`, m/s) to `move_fn` each step; SetPushSpeed (source units), SetPushDirection |
| `trigger_teleport` | a `Transform3D` to `move_fn` and a `teleport` event; the destination is `io.destinations[name]` (the manifest's `destinations`); `landmark` keeps the body's offset |
| `trigger_gravity` | a `gravity` event with the scale on entry and 1 on leaving (not with `persist`) |
| `func_ladder`, water brushes | `ladder_boxes()` and `water_boxes()`: one box per brush, for dot-player-controller's `DotFpsLadderMode.volumes` and `DotFpsSwimMode.volumes`; nothing here names that addon |
| `env_*` (`DotMapEffect`) | state to `effect_fn(kind, entity, on)` at map start and on each input; one-shots (explosion, shake, fade, spark) to `event_fn`; an explosion and a burning `env_fire` hurt bodies in range through `damage_fn` |
| `ambient_generic` (`DotMapSound`) | PlaySound, StopSound, ToggleSound, Volume, Pitch, fades to `effect_fn("sound", entity, on)`; `io.attach_sounds(manifest.sounds.ambient)` gives each its free stand-in, and one with none stays silent |

Map commands go through `DotMapCommand.judge`: a line is split on `;`, a chat line (200 characters) or a cvar on `command_allow` with a plain value is allowed, a list of verbs (`quit`, `exec`, `rcon*`, passwords, `bind`, `map`...) is never allowed even if listed, and every verdict is recorded.

`examples/volumes_demo.tscn` (headless, 146 checks in 15 sections) runs all of it, and shows Office's lava room from its own links: the trigger starts a 3 s timer, the hurt volume comes on at tick 181 and hits at once, then every 0.5 s while the player stays; leaving stops the hits; the trigger re-arms at 6 s and a second entry turns the hurt volume off before it can hit. The volume geometry there is a stand-in box, since the repository keeps Office's logic and not its brushes.

`trigger_hurt` honours `damageonce` (a body is hit once per stay; `DotMapHurt.once_flag` stays 0, see below) and `damageforce` (sent as the `damage_force` event `{body, force, source}` in m/s, zeroed by `nodmgforce`). `env_soundscape`, `_proxy` and `_triggerable` are `DotMapSoundscape`: the nearest enabled one covering a player fires the `soundscape` event `{body, name, entity, positions}` when it changes, and its `OnPlay` output.

`trigger_soundscape` is `DotMapTriggerSoundscape` (its volume kind is `soundscape`): a player inside hears the `env_soundscape_triggerable` it names wherever it stands, and the choice reverts on leaving (the usual `soundscape` event).

Damage once is no spawnflag. Across 1401 `trigger_hurt` entities in the 105 stored maps none sets a `damageonce` key, and no bit outside the base trigger filters (1 clients, 2 NPCs, 8 physics objects, 64 everything, 1024 debris) appears. Bit 8 is set on 25 of them, almost all with a lethal `damage` (999 to 10^12) and several with bits 1 and 2 beside it ("clients, NPCs, physics"), which is the base trigger's physics-objects filter, not a hit-once switch. So `once_flag` stays 0 and only the `damageonce` key turns it on. Re-run the sample with a scan of `~/mapsrc/store/*/doc.json`.

Not done: `func_water_analog` swimming physics (the controller's).

## Toggle brushes, breakables, movers and replication

Work package 6. `bind_world(world_root, manifest)` joins each entity to the drawn node whose `model` meta matches its `model "*N"` key, then `bind_movers` and `bind_breakables` hand the manifest's records to the entities. Motion is stored as (from, to, start tick, travel ticks) and the pose is computed for any tick, so a client that knows the tick draws the same frame; arrivals are self-scheduled events with a generation counter that drops stale ones.

| Class | Does |
| --- | --- |
| `func_brush`, `func_wall_toggle`, `func_illusionary` (`DotMapToggleBrush`) | Enable/Disable/Toggle, Alpha, SetSolid; shows, hides and switches collision on the bound node |
| `func_breakable`, `func_breakable_surf`, `prop_physics*` (`DotMapBreakable`) | health, `min_damage`, the break-on-trigger flag, Break/Shatter/SetHealth/AddHealth/RemoveHealth, OnTakeDamage/OnHealthChanged/OnBreak; a `break` effect and `broken` state; a `DotMapGlass` child is told to shatter (`apply_broken`) instead of duplicating glass code; `io.propdata_fn` supplies health for props |
| `func_door`, `func_door_rotating`, `func_movelinear`, `func_button`, `func_rot_button`, `func_plat` (`DotMapMoverNode`) | Open/Close/Toggle/Lock/Unlock/SetPosition/SetSpeed, autoclose by `wait`, OnOpen/OnClose/OnFullyOpen/OnFullyClosed |
| `func_rotating` | Start/Stop/Toggle/Reverse/SetSpeed |
| `func_tracktrain`, `func_tanktrain`, `func_train` and `path_track` | StartForward/StartBackward/Stop/Toggle/SetSpeed/TeleportToPathTrack along the record's `path`; corner speeds and OnPass; a looping ring |

Replication: the server is authoritative (`io.authoritative`), a client runs no logic and refuses `send`, `raise` and `touch`. `DotMapStateSync` batches every `state_changed` on the `settled` signal into one `io_state` message (`tick`, `[index, key, value]` changes), sends it through each peer's `send_fn`, and `add_peer` sends an `io_snapshot` of every entity first (join in progress). `apply()` on the client sets its clock, applies the changes and counts unknown entities in `refused` and unknown keys in `ignored`.

`examples/io_world_demo.tscn` (headless, 162 checks in 15 sections) covers all of it, including a two-peer exchange and a determinism run.

Movers push bodies (`DotMapMoverNode.push_bodies`, run by `DotMapVolumes.step`, through `move_fn`); a body pushed that does not move at least half the push is blocked: the `dmg` key is applied as `crush` damage every 0.25 s, `OnBlockedOpening` / `OnBlockedClosing` fire, and a slide, hinge or plat with `wait >= 0` reverses. `func_physbox` is `DotMapPhysbox` (a `RigidBody3D`; `damagetoenablemotion` / `forcetoenablemotion`, `EnableMotion` and the other inputs, `OnMotionEnabled`).

A `func_rotating` with a `fanfriction` (the converter writes `fan_friction` only when the map sets it) ramps to and from speed at `speed * friction / 20` per second, in the stored `spin` state (`[angle, target, tick, dir, velocity_at_tick, acceleration]`); the engine's own friction curve is not reproduced. A physbox reports its body's `pose` (`[x y z qx qy qz qw]`, local to the model node) at most ten times a second while it moves, in snapshots too, and a client eases its frozen body toward it.

`DotMapStateTransport` is the reference `send_fn`: `sync.attach_host(io, t.send)` (or the world's `send_fn` hook) queues each peer's messages, `t.flush_on(io)` sends them when a tick settles, as one `io_batch` per peer up to `max_bytes` (1100) of JSON; a bigger message, a snapshot say, goes alone. It names no net addon: `t.raw_send(peer, payload)` is the game's reliable channel, and on the client `DotMapStateTransport.is_state_payload(payload)` then `t.receive(io, sync, payload)` unpacks it. The payloads are plain dictionaries, so the channel only has to carry one of those.

Not done: tank-style train rotation.

## Correction: the Office lava room

An earlier description of Office's lava talked about a `logic_timer` and a `logic_relay` turning the hazard on and off. There is neither. The only 5 s in the map's logic is the chat line a `logic_auto` says at map start (`point_servercommand`, delay 5). The hazard is the chain `Obstacle2_trigger` (a `trigger_multiple`) to `Obstacle2_Hurt`, `Obstacle2_Steam` and `Obstacle2_Brush`, with `Spawn_HURT` (20 s after map start) and the nine `Obstacle6_Hurt_*` volumes that `Obstacle6_CaseA/B/C` enable at map start, one random pick per lane. On entry the trigger undoes everything at once (hurt `Disable`, brush green, steam off, itself `Disable`), then 3 s later enables the hurt volume, turns the steam on and the brush red, and 6 s later re-enables itself. Nothing turns the hurt volume off at 6 s; it stays on until the next entry undoes it. So a lava that appears to last 5 s is not in these outputs: whatever a game shows must come from the outputs as written (the hurt volume is live from 3 s after entry until the next entry), or from the game's own hurt rules (damage per second, a respawn), never from a timer the map does not have. `examples/io_demo.tscn` asserts this timeline tick by tick against `office_io.doc.json` (the stored Office entry's entities), reading the 3 s and 6 s from the links themselves: hurt on at entry + 180 ticks at 60 Hz, trigger re-armed at + 360, hurt still on afterwards, off again at the next entry.

## DotMapWorld: the one call

Work package 8. `DotMapWorld.build(prefix, hooks, options)` returns a `DotResult` whose value is a `Node3D` a game adds to its tree. It builds the mesh (glass included), environment, props and ambient sounds, one body per model and hull kind (`solid`, `clip`, `glass`, each on the layer the `layers` option names, an `AnimatableBody3D` for a mover so it carries riders), `DotMapGlass` panes, the `DotMapIO` from the stored source document, `bind_movers`, `bind_breakables`, `attach_sounds`, `DotMapVolumes`, `bind_world`, then `io.start()`.

The source document is `options.doc`, `options.doc_path`, `<prefix>.doc.json` beside the mesh, or the store entry named by the manifest's `source.sha256` (`options.store`, `$DOTBSP_STORE`, `~/mapsrc/store`). The store is never shipped, so a game that ships a map ships its document beside the mesh.

Hooks are plain callables in a dictionary: `damage_fn`, `move_fn`, `event_fn`, `effect_fn`, `actor_fn`, `propdata_fn`, `player_fn`, `material_for`, `send_fn` (host only, `DotMapStateSync`), and `ladder_fn` / `swim_fn`, which receive an `Array[AABB]` at build and whenever a volume is enabled or disabled, so dot-map never names dot-player-controller. `effect_fn("sound", entity, on)` is handled first by the world (it plays and stops the stand-in player), then passed on. Options also carry `command_allow`, `config` (a `DotMapConfig`: `game`, `config_dir`, `allow`, `defaults`, `get_fn`, `set_fn`; applied at build, restored when the node leaves the tree), `authoritative`, `rate`, `seed`, and `movers_only` (the world model is neither drawn nor collided and only brush entities with a mover are built, for a game that draws and collides the world itself).

Every tick the game calls `world.step(bodies)` (advance the logic, then the volumes). A client builds with `authoritative: false`, never calls `start`, and feeds host messages to `apply_state`. `add_peer` sends a snapshot first.

**Shots**: `world.shoot(space, from, to, amount, by, mask, limit)` casts one ray and hurts the breakable, button or door whose model it hits through `io.hurt` (returns the entity index, -1 for none); `limit` is the distance the game's own trace stopped the shot at, so a player in front shields the panel. A game calls it once per pellet after its combat resolves the shot (mg-wipeout `WoGame._shoot_io`).

`examples/world_demo.tscn` runs it on the converted Office and Dan's course (from `mg-wipeout-maps/worlds` and the store) and asserts the hurt room against its own links.

A `prop_door_rotating` is drawn by `DotMapDoorStandIn` (a panel hung at the hinge, with an `AnimatableBody3D` when solid; the hook `door_fn(mover, yaw)` replaces it with the game's model, built with its origin where the model's is and the entity's yaw (on a door hung off an authored hinge the world puts it under a pivot on the hinge, `panel_offset` along the panel, because the node swings about its own origin); `world.doors` lists them). Its direction follows the source keys: `opendir` 0 swings away from whoever opens it (the side is picked on opening from the opener's position, a `Vector3`, `Node3D` or body dictionary, and replicated as the `side` state), 1 forward, 2 back; `spawnpos` 1 or 2 (and spawnflag 1) starts it open on that side; spawnflag 2 is not "reverse" on a model door. The hinge is the model origin, except where the entity's `axis` key is a vertical line (or one point) within 1.2 m of it: 7 of the 304 stored doors. Those are stall and hospital doors whose origin is the panel's middle, so the converter puts the hinge on the axis, runs the panel from it through the origin (`panel_yaw`, `panel_width` in the record, clamped to 0.6-1.6 m and flagged `panel_assumed` because the origin is taken to be mid-panel; forward and back swap when the model's yaw faces away from that line) and `yaw` follows that frame; a horizontal axis (6 doors) or one farther off than a door is wide (3, copied helpers) is ignored. The engine's own use of `axis` is unverified; this follows the rendered result (`tools/door_shot.sh`: closed, half open from both sides). Not done: which side the panel hangs on for a model whose origin is the hinge is a guess until compared with the real model, and `regen` now keeps these doors in `movers` (before, `DotMapWorld` never saw one), so shipped worlds draw them only after a re-conversion. The manifest's `settings` (the map's own `point_servercommand` cvars, written by the converter) are the weakest layer of the config. `<prefix>.doc.json` is shipped beside each converted map by `bsp.py regen` and the importer.

Not done: tank trains.

## Riders and pushing

A body standing on a mover's top face (within `sv_mover_ride` m, default 0.15; 0 turns it off) is carried by the mover's step instead of being left behind or pushed; a body in the mover's way is pushed, and crushed only for an entity with a `dmg` key. `sv_mover_push 0` stops the pushing. The game gets the carry through `io.carry_fn(body, velocity, mover)`, or `move_fn` when that is unset; a body is a dictionary of `id`, `body`, `position` (feet), `height` and `radius`.

## Press-E

`DotMapUse` is the one use path: the client calls `aim(space, eye, dir)` every frame and hands the result to a `DotMapUsePrompt`; the host calls `press(space, eye, dir, user, activator)` when a player's use bit rises. `aim` returns `{index, entity, state, distance, in_range, label, at}` or an empty dictionary, and reads only replicated state, so a client can draw "[E] Use", "[E] Open" or "Locked" without logic. `press` refuses on a client, out of reach (`sv_use_reach`, 2.2 m), or inside the per-user and per-entity cooldown (`sv_use_cooldown`, 0.3 s, counted in io ticks), then calls `io.use`, so wait, toggle, lock and the `OnPressed`, `OnUseLocked`, `OnIn` and `OnOut` outputs behave exactly as a touch or a shot would. `effect_fn(kind, entity, at)` is the hook for a click or an animation beyond what the entity defines. Anything else usable (a weapon on the floor) can return the same dictionary from its own aim to share the prompt.
