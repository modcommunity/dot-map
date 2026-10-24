# dot-map

Maps as content rather than as builds: one game, many maps, switched under live players. A catalogue, a loader that fetches delivered maps through dot-cloud, a session that swaps the world safely, a protocol that takes every client along, a rotation, a vote tally, and a time limit with rock-the-vote and extends.

Read the family [CLAUDE.md](../../CLAUDE.md) first; this file is only what is specific to maps. The reasoning is in [docs/](docs/README.md).

**Only dot-core is a dependency, at API level 19 or later (`DotYaml`, `DotRotationSpec`, `DotCommandNames`, `DotAddonConfig.file_layers`, `tier_dirs`, `apply_overrides`, `DotCfgLegacy`).** dot-cloud, dot-timer, dot-server and dot-net are all optional and none is named anywhere in the source: dot-cloud is found in `DotRegistry`, zones come back as text, commands are installed duck-typed, and messages go out through a `send_fn`. [content](docs/content.md#reaching-dot-cloud-without-naming-it)

## Read before

| Read | Before |
| --- | --- |
| [docs/README.md](docs/README.md) | the index |
| [docs/content.md](docs/content.md) | `DotMapDef`, the catalogue, the loader and dot-cloud, what is deliberately not here |
| [docs/changing.md](docs/changing.md) | `DotMapSession`, `net/` (the sync host and client), `DotMapCommands`, anything a host may tell a client |
| [docs/rotation.md](docs/rotation.md) | `DotMapRotation`, `DotMapVote`, `DotMapTimeLimit` |
| [docs/history.md](docs/history.md) | the bugs, and how each looked |

## Layout

| Path | What |
| --- | --- |
| `addons/dot_map/core/` | `DotMapDef` (id, version, scene, pack, tier, player range), `DotMapCatalogue` (the JSON an operator edits) |
| `addons/dot_map/runtime/` | `DotMapLoader` (def to `PackedScene`, fetching first), `DotMapRotation`, `DotMapRotationFile` (`cfg/addons/dot_map/maps.yml`, the game and operator tiers, `merge: true`, `remove:`, legacy `cfg/maps.yml` via `DotCfgLegacy`), `DotMapSession` (the node a game adds) |
| `addons/dot_map/net/` | `DotMapMessage` (the five messages), `DotMapSyncHost` (announce, wait, swap; read its class doc), `DotMapSyncClient` (fetch, ready, load; owns the trust rules) |
| `addons/dot_map/surfaces/` | `DotMapSurfaces`: a surface kind (`&"brick"`) to a world-space triplanar material; 28 CC0 photo kinds (four carpets, snow, rock, sand, cut stone, clay roof, ceiling tile, worn plaster and two wallpapers among them), credits beside them. [surfaces](docs/surfaces.md) |
| `addons/dot_map/brushes/` | `DotMapBrush`: box, wedge, stairs, cylinder, cone, spike, arch, quarter_pipe, slab_holes from a dictionary; convex collision, UVs in metres, a material slot. [brushes](docs/brushes.md) |
| `addons/dot_map/bsp/` | `DotMapBspMesh`: a converted map's `dot-bsp-mesh` files (`tools/bsp/bsp.py mesh`) read back into chunked meshes (a material callback per surface), convex hull shapes by kind, triangle shapes for displacements, a node per brush entity at its origin, and the mover records; `build_environment`, `build_sounds` and `build_props` apply a licence-pass map's sky, sun, fog, ambient sound stand-ins (`addons/dot_map/sounds/`, Kenney CC0) and stand-in models (`addons/dot_map/props/`, Kenney CC0) through callables, never a scene path; `DotMapSoundDriver` (fades and spins the `build_sounds` players from the `sound_fade` and `sound_spin` events, by entity index or name, values clamped); `build_props(scene_for, collide_fn)` gives a prop_dynamic whose `solid` is 2, 3, 4 or 6 a box body around its stand-in when the game passes `collide_fn` (0, 1 and 5 never collide; the converter writes `solid` into the prop record); `DotMapEntities` (`DotMapMover`, `DotMapVolume`, `DotMapLinks`) reads the movers, trigger volumes, output links and generic entities. `DotMapFx` draws a map's `env_sprite`, `env_lightglow`, `point_spotlight`, `infodecal` and `env_spritetrail` (`DotMapTrail`, a ribbon behind what moves; `trail_target_fn` names the followed node) records cheaply (generated textures, per-map caps, a `ray_fn` the game supplies; the game asks for it from the source document). `DotMapTerrain` reads the converter's terrain heightfield (`tools/bsp/dotbsp/terrain.py`) into one triangle shape, a mesh and the walk points an AI graph joins by slope. Checks the sha256, refuses a newer format, no threads. `DotMapVisibility` draws only the chunks and props the camera's cluster can see (the map's precomputed visibility, area portals and doors) and adds occluders from its large solid brushes; `vis_mode` off, pvs, occluders or both. [visibility](docs/visibility.md) |
| `addons/dot_map/config/` | `DotMapConfig`: per-map settings from `map/<name>.yml` (globs, `cfg/server` over shipped), a key whitelist, `apply` on load and `restore` on the next map; the converter writes a commented starter (`python3 -m dotbsp.mapcfg`). [map-config](docs/map-config.md) |
| `addons/dot_map/io/` | `DotMapIO`: a map's input/output logic on the server's tick (delays, fire-once counts, a zero-delay loop guard, a seeded stream per entity), `DotMapEntity` and the logic classes (relay, timer, counter, case, compare, branch, auto, trigger, template, `game_score`, `game_ui` through `feed_ui`, `logic_collision_pair`, `logic_beats` as a `beat` event and OnBeat from a `bpm` key or SetBPM, `logic_winlose` with `round_decide` and a `round_end` event of slow motion and camera); a game plugs in with `register_handler`, `register_class` and four callables, map commands are recorded and never run. [io](docs/io.md) |
| `addons/dot_map/vote/` | `DotMapVote`, `DotMapTimeLimit` |
| `addons/dot_map/integrations/` | `DotMapCommands`: `map`, `maps`, `mapinfo` on any host |
| `tools/sync-surfaces.sh` | copies the kinds a game uses into the game (`--check` for CI); the addon's own textures never ship to players |
| `examples/surfaces_demo.tscn` | the surfaces suite (headless) and, with `-- --shot=<prefix>`, three frames of every kind on boxes |
| `examples/brushes_demo.tscn` | the brushes suite (62 checks, headless) and, under `xvfb-run` with `-- --shot=<prefix>`, three frames |
| `examples/bsp_entities_demo.tscn` | the brush-entity suite (42 checks, headless) on a real map's movers, volumes and links, `examples/bsp_mesh/zm_4way_tunnel.entities.json` ([brush-entities](docs/brush-entities.md)) |
| `examples/bsp_mesh_demo.tscn` | the bsp mesh suite (84 checks, headless) on `examples/bsp_mesh/fixture`, which `tools/bsp/tests/mesh_fixture.py` writes, and `terrain_fixture.json` (`tools/bsp/tests/test_terrain.py --write`) |
| `examples/vis_demo.tscn` | the visibility suite (16 checks on a synthetic map, headless); `-- --maps=<pack prefix>,...` adds the no-holes ray test on real converted packs ([visibility](docs/visibility.md#proof-no-holes)) |
| `examples/bsp_world_shot.tscn`, `tools/screenshot.sh` | one frame of a converted map dressed with its free textures, environment and stand-in props (under Xvfb) |
| `examples/io_world_demo.tscn` | toggle brushes, breakables, movers and state replication (headless, 205 checks in 17 sections) |
| `examples/io_demo.tscn` | the I/O suite (headless): delays, cycles, the logic classes, and Office's timed hazards from `examples/io/office_io.doc.json` |
| `examples/volumes_demo.tscn` | `DotMapVolumes`: hurt, push, teleport, gravity, trigger, ladder and water boxes, effects, sounds, the command allow-list, and Office's lava timing (headless, 128 checks in 13 sections) |
| `examples/world_demo.tscn` | `DotMapWorld` on the converted Office and Dan's course: one call, the hurt room per its own links, replication, manifest settings into the config (headless, 34 checks) |
| `addons/dot_map/io/` (`dot_map_door_standin`, `dot_map_physbox`, `dot_map_soundscape`) | the drawn `prop_door_rotating`, `func_physbox` bodies and `env_soundscape` classes ([io](docs/io.md)) |
| `examples/door_shot.tscn`, `tools/door_shot.sh` | frames of one `prop_door_rotating` of a converted map (`--entity=<index>`): closed, then half open from each side, from above and from the opener's eye, the hinge marked by a green post |
| `examples/map_selftest.tscn` | the suite; includes a real signed pack fetched by a peer |
| `tools/bsp/` | the family's one converter for community VBSP maps: reader, brush-to-box cutting, the intermediate JSON every game's adapter reads, `list` for a conversion queue, and the pieces every adapter repeated: `Flood` (reachable space), the entity and brush classifiers, prop matching, lights, `.gma` through fastgmad, the open-wall room plan, teleport destinations, the 0.0254 scale. Python, outside the addon so it never ships. [tools/bsp/README.md](tools/bsp/README.md) |

## Running and testing

- `tools/bsp/`: `python3 -I tools/bsp/tests/test_dotbsp.py` and `python3 -I tools/bsp/tests/test_lift.py`, `python3 -I tools/bsp/tests/test_terrain.py`, `python3 -I tools/bsp/tests/test_licence.py`, `python3 -I tools/bsp/tests/test_vis.py` (raw store, licence pass, environment, sound, free stand-ins, nearest texture), then re-convert a migrated game's maps (zombie-zone-maps, game-g2gfast) and compare; a fix there reaches every converting game.
- The family's two steps ([game-dev/CLAUDE.md](../../CLAUDE.md#validating-anything)), then `godot --headless --path . res://examples/map_selftest.tscn` and `res://examples/brushes_demo.tscn`. Run the check-only pass first: a missing `await` is a parse error and the scene then hangs.
- A change to the sync protocol is not done until game-g2gfast's `headless_net` passes; the protocol's first real transport found five bugs here. [history](docs/history.md#what-the-first-transport-found)
- A change to the cloud calls (`ensure`, `is_mounted`) must keep `_test_sync_a_delivered_map` meeting a real dot-cloud client: a by-name interface is one nobody else checks.

## Rules that bite

**Content**

- A map id is never renamed; change `display_name`. [content](docs/content.md#one-game-many-maps)
- The catalogue is not the rotation. One bad entry is dropped loudly, never fatal. An exact id wins a search. [content](docs/content.md#the-catalogue-is-not-the-rotation)
- `DotSemVer.parse` never returns null; check `.valid`. [content](docs/content.md#the-catalogue-is-not-the-rotation)
- dot-cloud is reached through the registry by name; a deployment that delivers its maps sets `require_cloud`. [content](docs/content.md#reaching-dot-cloud-without-naming-it)

**Changing**

- A change announces, loads the new scene, then `free()`s the old and adds the new in one call, then announces again. Never free first. A second change is refused, not queued. [changing](docs/changing.md#the-order-of-a-change)
- `announce` and `load` stay separate. A joiner's `ready` for the current map is answered with one `load`, once per peer per map. A change waits only on its `_participants`. A `load` that overtakes its fetch is held. [changing](docs/changing.md#changing-the-map-for-everybody)
- Progress messages are throttled; `ready` never is. [changing](docs/changing.md#changing-the-map-for-everybody)
- A delivered map is compared by `content_version` as well as `version`. [changing](docs/changing.md#changing-the-map-for-everybody)
- A map change is not a game change; never route a rotation through `DotGameManager`. [changing](docs/changing.md#changing-a-game-and-changing-a-map-are-different-operations)
- `map` lives here; `nextmap` and `timeleft` are dot-vote's. Do not register a name another addon owns. [changing](docs/changing.md#the-commands)
- The host names *which* map, never *what* it is: unknown maps must be delivered and resolve inside their pack after `simplify_path`. [changing](docs/changing.md#the-host-may-say-which-map-never-what-the-map-is)
- A template scene treats its pack as untrusted and takes paths only from keys the check covers; every path-shaped string in `meta` is checked. [changing](docs/changing.md#template-scenes)
- `send_fn` is called per peer, never with a broadcast id. [changing](docs/changing.md#it-is-transport-agnostic-and-that-is-not-laziness)

**Rotation and time**

- The cooldown is clamped to half the pool when choosing; the random mode's seed advances deterministically; vote ties are deterministic. [rotation](docs/rotation.md)
- `maps.yml` decides rotation through `DotMapDef.in_rotation` (runtime, never saved), which `available_for` reads; `enabled` stays the catalogue's own switch. Every offer path (pool, `set_next`, ballot, nominations) must read it, never `enabled` alone. `refresh_content()` makes fresh defs (in_rotation true) and emits `content_refreshed`; the file re-applies on it (API level 6), so do not add a second place that re-marks. The matcher is dot-core's `DotRotationSpec`, shared with the server's games.yml. [rotation](docs/rotation.md#the-rotation-file)
- Time limits run on simulated seconds; expiry is latched; extends are bounded and clear rtv; rtv is idempotent and leaves with the player. [rotation](docs/rotation.md#the-map-has-to-end-on-its-own)
- The session emits `map_over` and never changes the map itself. [rotation](docs/rotation.md#the-map-has-to-end-on-its-own)

## Where a game plugs in

| To change | Where |
| --- | --- |
| Where the loaded map is put in the tree | `DotMapSession.world_ref` |
| How the next map is chosen | `DotMapRotation.mode`, or `set_next` from a vote |
| How long a map stays off the menu | `DotMapRotation.cooldown` |
| How long a map runs | `DotMapSession.map_seconds`, or `DotMapTimeLimit.duration` |
| How many players must rock the vote | `DotMapTimeLimit.rtv_fraction` / `rtv_min_players` |
| How often a map may be extended | `DotMapTimeLimit.max_extends` |
| What happens when a map ends | The `map_over` signal. The session never decides |
| Whether the clock waits while the server sleeps | `DotMapSession.follow_hibernation(server)` or `set_hibernating`; `restart_on_wake` |
| What is on a ballot | `DotMapVote.max_options` / `reserved_for_nominations` |
| Whether a map is offered at all | `DotMapDef.enabled`, `min_players`, `max_players` |
| What a map is worth | `DotMapDef.tier`, read by `DotTimerStyle.points_for` |
| Where content comes from | A `DotCloudSource` subclass, in dot-cloud |
| Where a map's manifest is | `DotMapDef.manifest_url`, or the cloud client's `manifest_url_template` |
| How map changes reach clients | `DotMapSyncHost.send_fn` / `DotMapSyncClient.send_fn` |
| What a client will accept from a host | `DotMapSyncClient.accept_unknown_maps` |
| A built-in scene a host may name for delivered data | `DotMapSyncClient.trusted_template_scenes` / `template_path_keys` |
| How often a peer reports download progress | `DotMapSyncClient.progress_interval_sec` |
| Letting a peer in between changes | `DotMapSyncHost.admit_peer` (or `add_peer` + `join_payload`; the host sends the `load`) |
| Whether one slow peer holds the server | `DotMapSyncHost.swap_without_stragglers` |
| Whether `map` may be typed in chat | `DotMapCommands` `allow_chat_change`, then the host's `sv_chat_commands` |
| Anything else about a map | `DotMapDef.meta` |

Deliberately not here: a download UI, a transport, kicking a peer that cannot get the map, vote commands and menus (dot-vote, dot-ui), metadata scraped from the scene, per-map addon configuration, anything about what is in a map. [content](docs/content.md#deliberately-not-here), [changing](docs/changing.md#deliberately-not-here)
