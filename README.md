This is the **map** asset for TMC's **Dot** collection. It exists so one game can carry a hundred maps, because a project per map falls apart somewhere around map forty.

This collection of assets provides modular building blocks for creating games and applications within the TMC ecosystem, ensuring consistency and interoperability across all `dot-*` assets. This includes core functionality, networking, authentication, cloud integration, and more.

**These assets are COMPLETELY OPEN SOURCE**. You are free to use, modify, and distribute them under the terms of the MIT license. The only thing not open source is the back-end web infrastructure. So if you opt into using your own authentication backend instead of integrating with TMC, you will need to build and integrate your own back-end infrastructure.

## From Maintainer & WARNING
This asset, along with all the others, was built initially with **Claude Code** and will continue to be maintained and extended using it. This is because I (`gamemann`) cannot build the entire TMC platform alone (I wish I could lol).

**Please treat this as partially tested.** Every asset has its own headless test suite and those suites pass, but very little of this has been in front of real players yet. Expect rough edges, and please report anything you run into.

I intend on reviewing code, testing, and editing documentation regularly. If you're interested in helping out, please let me know!

## Maps as Content, Not as Builds
**Maps as content, not as builds.** One Godot game, a hundred maps, switched under
live players.

A catalogue, a rotation with a cooldown, a map time limit with rock-the-vote and
extending, nominations and voting, and a loader that
resolves a map to a scene — fetching its content through
[dot-cloud](../dot-cloud) when the map is delivered and reading the disk when it ships
in the build.

## Why

The obvious way to ship a hundred surf maps is a hundred Godot projects. At map forty
that is a hundred export pipelines, a hundred copies of every addon, a player who
downloads a whole game to try one map, and records that cannot be compared because
each project has its own.

A map here is an id, a version, a scene path and optionally a content pack. The server
switches between them; the client fetches the one it needs; the leaderboard spans all
of them.

## Installing

Copy `addons/dot_map/` and [`dot-core`](../dot-core)'s `addons/dot_core/` into your
project and enable dot-map in *Project → Project Settings → Plugins*.

dot-cloud and [dot-timer](../dot-timer) are optional and are not named anywhere in the
source.

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
      "id": "surf_kitsune",
      "version": "2.1.0",
      "kind": "surf",
      "tier": 6,
      "content": "surf_pack_2024",
      "scene": "res://packs/surf_pack_2024/kitsune/map.tscn"
    }
  ]
}
```

The second map is delivered: its scene lives inside a dot-cloud pack that is fetched
and mounted before the scene is loaded.

## Rotation and voting

```gdscript
session.rotation.mode = DotMapRotation.Mode.RANDOM
session.rotation.cooldown = 5          # maps recently played that are off the menu

var vote := DotMapVote.new()
vote.nominate(&"surf_kitsune")
vote.begin(session.catalogue, session.rotation.pool(player_count), session.current)
vote.cast_vote(player_id, &"surf_kitsune")

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

## Documentation

[`CLAUDE.md`](CLAUDE.md) has the design reasoning: why the catalogue is not the
rotation, the order a map change has to happen in and what breaks when it does not,
and why the loader reaches dot-cloud through the registry rather than by name.

## Validating

```bash
godot --headless --path . --import
godot --headless --path . res://examples/map_selftest.tscn   # 120 checks
```

## Licence

MIT. See [LICENSE](LICENSE).
