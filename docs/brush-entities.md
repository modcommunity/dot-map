# Brush entities: doors, buttons, lifts, triggers and the links between them

The converter (`tools/bsp/bsp.py mesh`) writes everything a game needs to run a community map's mechanics into the mesh manifest, and `DotMapEntities` reads it back. This is the only place the logic exists: a game animates records, it never parses a map. The class-by-class table is [entity-classes](../tools/bsp/docs/entity-classes.md).

All lengths are metres, directions Godot axes, angles degrees, speeds per second. A mover's node sits at its `origin` (`DotMapBspMesh.build_node`), and its model's surfaces and hulls are found by `model`.

## The manifest sections

| Section | One record per | Written by |
| --- | --- | --- |
| `movers` | moving brush entity | `movers.movers` |
| `volumes` | trigger, push, hurt, teleport, gravity, water and ladder brush | `movers.volumes` |
| `links` | output of any entity (the graph) | `movers.links` |
| `entities` | entity kept as data, or of a class with no row | `movers.generic` |
| `destinations` | named point a teleport may send a body to | `movers.destinations` |

A manifest without the newer sections (`links`, `entities`, volume `outputs`) reads as empty ones; the format version stays 1 because nothing was removed.

## Movers

`kind` is `slide` (doors, `func_movelinear`), `button`, `rotate` (hinged doors), `rotate_button`, `spin`, `path` (trains), `plat` or `conveyor`.

| Key | Meaning |
| --- | --- |
| `model`, `entity`, `targetname`, `classname`, `origin`, `mins`, `maxs` | which brush, where, and its bounds |
| `direction`, `distance`, `lip` | slide, button and lift: unit direction, full travel (the brush's size that way less 2 units less `lip`, the original engine's formula; a negative lip lengthens it) |
| `axis`, `degrees` | hinge: axis and signed turn |
| `speed`, `travel_time` | metres (or degrees) a second, and the seconds one full travel takes |
| `wait` | seconds open before closing; -1 stays |
| `locked`, `toggle`, `start_open`, `use`, `touch`, `solid` | the spawnflags that matter |
| `degrees_per_second`, `start_on` | spinners |
| `path`, `start_speed` | trains: the corners `[{name, at, speed?}]` |
| `outputs`, `opened_by` | what it fires, and who drives it |

`DotMapMover` exposes these as fields and adds `transform_at(fraction)` (the node's transform from the closed pose; hinges turn about the node's origin), `advance(from, opening, seconds)`, `rest_fraction()` and `spin_rate()`. It moves nothing itself.

## Volumes

`kind` is `multiple` (fires on each entry, then waits `wait`), `once` (`wait` -1), `teleport` (`target`), `push` (`direction`, `speed`), `hurt` (`damage`), `gravity`, `water` or `ladder`. Each has `brushes` as plane lists (`n.p <= d` inside), `outputs`, `disabled` (starts disabled) and `filter`. `DotMapVolume.contains(point)` tests exactly, `bounds()` boxes it.

## Links

A link is `{from, from_name, from_class, output, target, input, param, delay, times, to, special}`: the output `OnPressed` of entity `from` calls `input` on every entity named `target` (`to`, indices, matched case-insensitively) after `delay` seconds, `times` times (-1 always). `special` marks `!activator`, `!caller` and the like, which resolve at run time to whoever fired. A target nothing carries has an empty `to` and is not special: `DotMapLinks.unresolved()` lists them and the converter prints the count. Running the inputs (`Open`, `Close`, `Toggle`, `Lock`, `Unlock`, `Enable`, `Disable`, `Trigger`, `StartForward`...) is the game's; `fired_by(entity, output)` gives the links in delay order and `driving(entity, input)` the reverse.

## Entities kept as data

Logic, paths and every class with no row in `dotbsp/classes.py` are in `entities` with every key (not the outputs, which are links), their `treatment` (`data` or `unknown`) and `origin`. `bsp.py mesh` fails on an unknown class unless `--allow-unknown`, and prints the unknown classes and the link counts; `DotMapEntities.unknown_classes()` lists them at load time.

## Testing

`python3 -I tools/bsp/tests/test_mesh.py` (the `Entities` tests) and `res://examples/bsp_entities_demo.tscn` (32 checks) run on `examples/bsp_mesh/zm_4way_tunnel.entities.json`, the entity data of a real map with three lifts whose buttons lock and unlock one another (`tools/bsp/tests/entities_fixture.py` rewrites it from the downloaded map; only the derived data is in the repository).

## What a game does with it

1. Load the mesh and build its entities: `world.entities()`.
2. For each mover, place the model's node at `origin` and drive `transform_at` from a fraction it keeps; honour `locked`, `toggle`, `wait`, `use` and `touch`.
3. Make a press, a touch or a volume entry fire the matching `fired_by` links after their delays, and map each `input` onto the mover.
4. Games with their own door and barricade systems adapt at this layer; the converter stays game-neutral.
