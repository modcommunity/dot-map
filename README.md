This is the **map** asset for TMC's **Dot** collection. It exists so one game can carry a hundred maps, because a project per map falls apart somewhere around map forty.

This collection of assets provides modular building blocks for creating games and applications within the TMC ecosystem, ensuring consistency and interoperability across all `dot-*` assets. This includes core functionality, networking, authentication, cloud integration, and more.

**These assets are COMPLETELY OPEN SOURCE**. You are free to use, modify, and distribute them under the terms of the MIT license. The only thing not open source is the back-end web infrastructure. So if you opt into using your own authentication backend instead of integrating with TMC, you will need to build and integrate your own back-end infrastructure.

## From Maintainer & WARNING
This asset, along with all the others, was built initially with **Claude Code** and will continue to be maintained and extended using it. This is because I (`gamemann`) cannot build the entire TMC platform alone (I wish I could lol).

**Please treat this as partially tested.** Every asset has its own headless test suite and those suites pass, but very little of this has been in front of real players yet. Expect rough edges, and please report anything you run into.

I intend on reviewing code, testing, and editing documentation regularly. If you're interested in helping out, please let me know!

## Maps as Content, Not as Builds
**Maps as content, not as builds.** One Godot game, a hundred maps, switched under live players.

A catalogue, a rotation with a cooldown, a map time limit with rock-the-vote and extending, nominations and voting, and a loader that resolves a map to a scene, fetching its content through [dot-cloud](https://github.com/modcommunity/dot-cloud) when the map is delivered and reading the disk when it ships in the build.

## Why

The obvious way to ship a hundred surf maps is a hundred Godot projects. At map forty that is a hundred export pipelines, a hundred copies of every addon, a player who downloads a whole game to try one map, and records that cannot be compared because each project has its own.

A map here is an id, a version, a scene path and optionally a content pack. The server switches between them; the client fetches the one it needs; the leaderboard spans all of them.

## Surface materials

`DotMapSurfaces` gives a map generator a photo material per surface kind (`&"brick"`, `&"asphalt"`, `&"tile_dark"`...), mapped in world space so code-built boxes need no UVs, and drawn the same in Forward+ and the browser's Compatibility renderer. Details in [docs/surfaces.md](docs/surfaces.md).

Textures: fifteen photographic PBR materials from [ambientCG](https://ambientcg.com) (Lennart Demes and contributors), **CC0 1.0**, one asset per kind; asset ids, pages and licence in [addons/dot_map/surfaces/CREDITS.md](addons/dot_map/surfaces/CREDITS.md).

## Installing

Copy `addons/dot_map/` and [`dot-core`](https://github.com/modcommunity/dot-core)'s `addons/dot_core/` into your project and enable dot-map in *Project → Project Settings → Plugins*.

dot-cloud and [dot-timer](https://github.com/modcommunity/dot-timer) are optional and are not named anywhere in the source.

## Five minutes

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

The second map is delivered: its scene lives inside a dot-cloud pack that is fetched and mounted before the scene is loaded.

A game whose maps are published one pack per map (dot-ci's `release-maps.yml`) lists them in its descriptor's `maps:` as pinned `<owner>/<map id>@<version>` keys, and dot-server hands them back as `DotGameManager.current_maps()`. `DotMapCatalogue.add_delivered(key, scene)` turns each into a delivered map, with the last segment of the content id as the id a player types:

```gdscript
for key in server.games.current_maps():
    catalogue.add_delivered(key, "map.tscn")
```

## A converted map, from files to a drawn world

A converted map is a prefix: `<prefix>.json` (the manifest), `<prefix>.bin` (geometry, lightmaps, visibility), usually `<prefix>.doc.json` (the source document, which gives entities and links) and `<prefix>.coverage.json`. `examples/bsp_mesh/fixture.json` and `fixture.bin` are a tiny one to start from, and the converter's `bsp.py regen` writes the real ones (below).

```gdscript
# `world` is a DotMapBspMesh, read from the prefix (the path without ".json").
var loaded := DotMapBspMesh.load_prefix("res://examples/bsp_mesh/fixture")
if not loaded.ok:
    push_error(str(loaded.error))
    return
var world: DotMapBspMesh = loaded.value

# 1. The whole playable world (geometry, props, doors, triggers, collision, the map's own environment).
var surfaces := DotMapSurfaces.new()
var material_for := surfaces.world_material_for(world, "res://examples/bsp_mesh")   # the folder the textures sit in
var built := DotMapWorld.build(world, {"material_for": material_for})
if not built.ok:
    return
var dw: DotMapWorld = built.value
add_child(dw)

# 2. Draw only what the camera can see. Fails quietly (the map is drawn whole) when the map has no visibility data.
var vis := DotMapVisibility.new()
add_child(vis)
vis.setup(world, dw.visual)

# 3. Lightmapped maps only: let the baked light drive the sky and ambient, and free the bake's own lamps. Returns null for a map without a lightmap.
DotMapLitWorld.attach(dw, world, environment, lamps)
```

`examples/bsp_world_shot.gd` is this flow in about eighty lines with a camera (`tools/screenshot.sh dot-map out.png --scene res://examples/bsp_world_shot.tscn`, with `--world=<prefix>`), and `world.build_node()` alone gives just the mesh tree when you want to place everything yourself. `world` in the snippets above is that `DotMapBspMesh`, never a node.

To make a converted map from an original, with the author's file in the converter's store (`bsp.py store`), from `tools/bsp`:

```bash
python3 bsp.py regen --out ../maps/my_map/my_map <game>/<map>      # writes my_map.json, .bin, .coverage.json, .doc.json
python3 bsp.py regen --ratchet --out ../maps/my_map/my_map <game>/<map>   # fails when more is unmapped than the committed coverage says
```

When a converted map is wrong, fix the converter or its rule tables and regenerate; do not patch the output ([docs/converter-v2.md](docs/converter-v2.md)).

## Rotation and voting

```gdscript
session.rotation.mode = DotMapRotation.Mode.RANDOM
session.rotation.cooldown = 5          # maps recently played that are off the menu

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
session.map_seconds = 1800.0          # half an hour
session.time_limit.rtv_fraction = 0.6 # 60% of players to end it early

session.map_over.connect(func(map, reason):
    # The session says the map is over. What happens next is yours.
    await session.change_to(session.rotation.choose(player_count).id)
)

# once per simulated tick
session.advance(delta)

# when somebody types !rtv
session.rock_the_vote(player_id, player_count)
```

## Changing the map for everybody

`DotMapSession` changes the map in one process. `DotMapSyncHost` and `DotMapSyncClient` change it for every connected peer: announce, fetch, ready, then load, over whatever transport you hand them a `send_fn` for.

```gdscript
var host := DotMapSyncHost.new()
host.session = session
host.send_fn = func(peer: int, payload: Dictionary) -> void: link.send_to(peer, payload)
add_child(host)

host.admit_peer(peer_id)                 # as each client joins; it is told the current map
await host.change_to(&"surf_tidewater")    # announce, wait for peers, swap, tell them to load
```

On the client, `DotMapSyncClient.handle(payload)` takes whatever arrives. A host may say which map, never what the map is: a map the client does not have must be delivered content. A game whose maps are data read by one scene in its own build lists that scene in `trusted_template_scenes`, and the delivered requirement then applies to the data instead — see [`docs/changing.md`](docs/changing.md#template-scenes) for exactly what that does and does not let a host do.

## Drawing only what can be seen

A converted map keeps its precomputed visibility data (clusters, the potentially visible set, area portals) and gets occluders from its large solid brushes. `DotMapVisibility` shows only the chunks and props the camera's cluster can see, re-deciding only when the camera changes cluster, and closes area portals when their doors shut. `vis_mode` is off, pvs, occluders or both; a map without the data draws everything. Details and measurements in [docs/visibility.md](docs/visibility.md).

## Documentation

[`docs/`](docs/README.md) has the design reasoning: why the catalogue is not the rotation, the order a map change has to happen in and what breaks when it does not, and why the loader reaches dot-cloud through the registry rather than by name.

## Validating

```bash
godot --headless --path . --import
godot --headless --path . res://examples/map_selftest.tscn   # 223 checks
```

## Licence

MIT. See [LICENSE](LICENSE).
