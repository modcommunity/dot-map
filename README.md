# dot-map

Maps as content, not as builds. One Godot game can carry a hundred maps and switch between them under live players. dot-map gives you a map catalogue, a rotation with a cooldown, a time limit with rock-the-vote, nominations and voting, a loader that turns a map into a scene, and tools for drawing converted BSP maps. Part of TMC's open source **Dot** collection (MIT licence).

> Built with Claude Code. Every addon has a headless test suite and the suites pass, but little of this has met real players yet. Please report rough edges.

## Why

The obvious way to ship a hundred maps is a hundred Godot projects: a hundred export pipelines, a hundred copies of every addon, and a player who downloads a whole game to try one map. Here a map is an id, a version, a scene path and optionally a content pack. The server switches between them, the client fetches the one it needs, and a leaderboard can span all of them.

## Install

Copy `addons/dot_map/` and [dot-core](https://github.com/modcommunity/dot-core)'s `addons/dot_core/` into your project and enable dot-map under **Project > Project Settings > Plugins**.

[dot-cloud](https://github.com/modcommunity/dot-cloud) (to fetch delivered maps) and [dot-timer](https://github.com/modcommunity/dot-timer) (zones) are optional and found at run time.

## Quick start

```gdscript
var session := DotMapSession.new()
session.world_ref = DotNodeRef.of_path(^"../World")
add_child(session)

session.load_catalogue("res://maps/catalogue.json")

session.changing.connect(func(_from, _to): timer_manager.set_zones(null))
session.changed.connect(func(map, _world):
    if session.zones_json != "":
        var zones := DotTimerZoneSet.from_json(session.zones_json)
        if zones.ok:
            timer_manager.set_zones(zones.value)
)

await session.change_to(&"surf_beginner")
```

`catalogue.json`:

```json
{
  "format": 1,
  "maps": [
    {
      "id": "surf_beginner",
      "version": "1.0.0",
      "name": "Surf Beginner",
      "kind": "surf",
      "tier": 1,
      "scene": "res://maps/surf_beginner/map.tscn",
      "zones": "res://maps/surf_beginner/zones.json"
    },
    {
      "id": "surf_tidewater",
      "version": "2.1.0",
      "kind": "surf",
      "tier": 6,
      "content": "surf_pack_2024",
      "scene": "res://packs/surf_pack_2024/tidewater/map.tscn"
    }
  ]
}
```

The second map is delivered: its scene lives in a dot-cloud pack that is fetched and mounted before the scene loads.

A game whose maps are published one pack per map lists them in its descriptor's `maps:` as pinned `<owner>/<map id>@<version>` keys, and dot-server returns them as `DotGameManager.current_maps()`. `DotMapCatalogue.add_delivered(key, scene)` turns each into a delivered map, using the last part of the content id as the id a player types:

```gdscript
for key in server.games.current_maps():
    catalogue.add_delivered(key, "map.tscn")
```

## Parts

| Piece | What it does | More |
| --- | --- | --- |
| `DotMapSession`, catalogue | Loads the catalogue and changes the map in one process. | [docs/content.md](docs/content.md) |
| `DotMapSyncHost`, `DotMapSyncClient` | Change the map for every connected peer. | [docs/changing.md](docs/changing.md) |
| `DotMapRotation`, `DotMapVote`, `DotMapTimeLimit` | Next-map choice, voting, time limit and rock-the-vote. | [docs/rotation.md](docs/rotation.md) |
| `DotMapSurfaces` | A photo material per surface kind, mapped in world space so code-built boxes need no UVs. | [docs/surfaces.md](docs/surfaces.md) |
| `DotMapBrush` | Map-building solids as data. | [docs/brushes.md](docs/brushes.md) |
| `DotMapBspMesh`, `DotMapWorld` | Read a converted map and build the playable world. | below |
| `DotMapIO`, entities | Doors, buttons, lifts, triggers and their output links. | [docs/io.md](docs/io.md), [docs/brush-entities.md](docs/brush-entities.md) |
| `DotMapNavLinks` | Closed doors and teleports as data for a navigation bake or an AI. | [docs/nav-links.md](docs/nav-links.md) |
| `DotMapVisibility`, `DotOccluderBaker`, `DotAreaPortal` | Draw only what can be seen. | [docs/visibility.md](docs/visibility.md), [docs/culling.md](docs/culling.md) |
| `DotMapConfig` | Per-map settings files. | [docs/map-config.md](docs/map-config.md) |

## A converted map, from files to a drawn world

A converted map is a prefix: `<prefix>.json` (the manifest), `<prefix>.bin` (geometry, lightmaps, visibility), usually `<prefix>.doc.json` (entities and links) and `<prefix>.coverage.json`. `examples/bsp_mesh/fixture.json` and `fixture.bin` are a tiny one to start from. The converter, [dot-map-convert](https://github.com/modcommunity/dot-map-convert), writes real ones.

```gdscript
# `world` is a DotMapBspMesh, read from the prefix (the path without ".json").
var loaded := DotMapBspMesh.load_prefix("res://examples/bsp_mesh/fixture")
if not loaded.ok:
    push_error(str(loaded.error))
    return
var world: DotMapBspMesh = loaded.value

# 1. The playable world: geometry, props, doors, triggers, collision and the map's environment.
var surfaces := DotMapSurfaces.new()
var material_for := surfaces.world_material_for(world, "res://examples/bsp_mesh")   # folder the textures sit in
var built := DotMapWorld.build(world, {"material_for": material_for})
if not built.ok:
    return
var dw: DotMapWorld = built.value
add_child(dw)

# 2. Draw only what the camera can see. If the map has no visibility data it is drawn whole.
var vis := DotMapVisibility.new()
add_child(vis)
vis.setup(world, dw.visual)

# 3. Lightmapped maps only: baked light drives the sky and ambient. Returns null otherwise.
DotMapLitWorld.attach(dw, world, environment, lamps)
```

`examples/bsp_world_shot.gd` is this flow with a camera: `tools/screenshot.sh dot-map out.png --scene res://examples/bsp_world_shot.tscn`, with `--world=<prefix>`. `world.build_node()` alone gives just the mesh tree if you want to place everything yourself.

`tools/prop_audit.gd` checks that no converted world has a library prop that failed to load or would be invisible but solid. Run it on the path a game reaches the worlds by: `godot --headless --path . -s res://tools/prop_audit.gd -- <worlds dir>...`. It exits 1 on a problem; `--allow-proxied` accepts maps drawn with box proxies.

When a converted map is wrong, fix the converter or its rule tables and regenerate. Do not patch the output ([docs/converter-v2.md](docs/converter-v2.md)).

### Maps that share art

A converted map that names a shared art slice (`licence.store_pack`, see [docs/content.md](docs/content.md#shared-stores-as-dot-cloud-slices)) needs two lines in the game's loader between reading the world and building it. A scoreboard or map screen should show the credit line (CC-BY asks for it):

```gdscript
var cloud: Object = DotRegistry.get_service(&"dot_cloud_client")
var licence: Dictionary = world.manifest.get("licence", {})
await DotMapStore.ensure(licence, cloud)                 # download and mount the slice once
DotMapStore.apply(licence, cloud, surfaces, world)       # before world_material_for / build_node
var credits := DotMapCredits.line(world.manifest)        # "Map by X | Art: A, B"; DotMapCredits.works(manifest) is the full list
```

## Rotation and voting

```gdscript
session.rotation.mode = DotMapRotation.Mode.RANDOM
session.rotation.cooldown = 5          # recently played maps kept off the menu (default 5)

var vote := DotMapVote.new()
vote.nominate(&"surf_tidewater")
vote.begin(session.catalogue, session.rotation.pool(player_count), session.current)
vote.cast_vote(player_id, &"surf_tidewater")

var winner := vote.finish()
if winner != null:
    session.rotation.set_next(winner.id)
```

## Ending a map

```gdscript
session.map_seconds = 1800.0          # default: half an hour
session.time_limit.rtv_fraction = 0.6 # default: 60% of players end it early

session.map_over.connect(func(map, reason):
    # The session says the map is over. What happens next is yours.
    await session.change_to(session.rotation.choose(player_count).id)
)

session.advance(delta)                       # once per simulated tick
session.rock_the_vote(player_id, player_count)   # when somebody types !rtv
```

## Changing the map for everybody

`DotMapSession` changes the map in one process. `DotMapSyncHost` and `DotMapSyncClient` change it for every connected peer: announce, fetch, ready, then load, over any transport you give a `send_fn`.

```gdscript
var host := DotMapSyncHost.new()
host.session = session
host.send_fn = func(peer: int, payload: Dictionary) -> void: link.send_to(peer, payload)
add_child(host)

host.admit_peer(peer_id)                   # as each client joins; it is told the current map
await host.change_to(&"surf_tidewater")    # announce, wait for peers, swap, tell them to load
```

On the client, pass whatever arrives to `DotMapSyncClient.handle(payload)`. A host may say which map, never what the map is: a map the client does not have must be delivered content. A game whose maps are data read by one scene in its own build lists that scene in `trusted_template_scenes`. See [docs/changing.md](docs/changing.md#template-scenes) for what that allows.

## Drawing only what can be seen

A converted map keeps its precomputed visibility data (clusters, the potentially visible set, area portals) and gets occluders from its large solid brushes. `DotMapVisibility` shows only the chunks and props the camera's cluster can see, and closes area portals when their doors shut. `mode` is `OFF`, `PVS`, `OCCLUDERS` or `BOTH` (default). A map without the data is drawn whole. Details and measurements are in [docs/visibility.md](docs/visibility.md).

A hand-built level gets the same from `DotOccluderBaker` (large walls and floors become occluder quads) and `DotAreaPortal` (a doorway that hides the room behind it while the door is shut). See [docs/culling.md](docs/culling.md). Both are opt-in.

## Documentation

[docs/README.md](docs/README.md) indexes the design notes: why the catalogue is not the rotation, the order a map change must happen in, and why the loader reaches dot-cloud through the registry.

## Testing

```bash
godot --headless --path . --import
godot --headless --path . res://examples/map_selftest.tscn
```

## Credits

| Asset | Author / source | Licence |
| --- | --- | --- |
| 28 photographic PBR surface materials, one per surface kind | Lennart Demes and contributors, [ambientCG](https://ambientcg.com) (asset ids and pages in [CREDITS.md](addons/dot_map/surfaces/CREDITS.md)) | CC0 1.0 |

## Licence

MIT. See [LICENSE](LICENSE).
