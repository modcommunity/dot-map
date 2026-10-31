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

`kind` is `multiple` (fires on each entry, then waits `wait`), `once` (`wait` -1), `teleport` (`target`), `push` (`direction` a unit vector in Godot axes from `pushdir`, `speed` in metres a second, `spawnflags`; `DotMapVolume.push_velocity()` is their product, and a game applies it to bodies inside `contains`), `hurt` (`damage`), `gravity`, `water` or `ladder`. Each has `brushes` as plane lists (`n.p <= d` inside), `outputs`, `disabled` (starts disabled) and `filter`. `DotMapVolume.contains(point)` tests exactly, `bounds()` boxes it.

## Links

A link is `{from, from_name, from_class, output, target, input, param, delay, times, to, special}`: the output `OnPressed` of entity `from` calls `input` on every entity named `target` (`to`, indices, matched case-insensitively) after `delay` seconds, `times` times (-1 always). `special` marks `!activator`, `!caller` and the like, which resolve at run time to whoever fired. A target nothing carries has an empty `to` and is not special: `DotMapLinks.unresolved()` lists them and the converter prints the count. Running the inputs (`Open`, `Close`, `Toggle`, `Lock`, `Unlock`, `Enable`, `Disable`, `Trigger`, `StartForward`...) is the game's; `fired_by(entity, output)` gives the links in delay order and `driving(entity, input)` the reverse.

## Entities kept as data

Logic, paths and every class with no row in `dotbsp/classes.py` are in `entities` with every key (not the outputs, which are links), their `treatment` (`data` or `unknown`) and `origin`. `bsp.py mesh` fails on an unknown class unless `--allow-unknown`, and prints the unknown classes and the link counts; `DotMapEntities.unknown_classes()` lists them at load time.

## Commands and the unconverted list

`DotMapLinks.command_of(input)` names an input in game-neutral terms (`open`, `close`, `toggle`, `lock`, `unlock`, `press`, `enable`, `disable`, `trigger`, else empty) and `commands_for(entity)` / `DotMapEntities.commands_for(mover)` give what drives one, by delay, with who sent it, so a game's door, lift or barricade system adapts at this layer without parsing input names.

What nothing converts is listed per map: `bsp.py mesh` prints it, `bsp.py unconverted <maps>` fails (6) for a class that is neither converted (not `data`, or a runtime component in `classes.tsv`) nor on `tools/bsp/rules/unconverted_ignore.tsv` (class or `prefix*`, with a reason; a stale row also fails). `DotMapEntities.unconverted(ignore, runnable)` is the same check at load time, `runnable` being the classes the game's own handlers run.

## Glass and breakables

A surface whose texture maps (in `source_textures.tsv`) to a generic id starting `glass` (`glass`, `glass_frosted`; a tint column multiplies the colour), or that belongs to a `func_reflective_glass`, carries `glass: <kind>` in its record. `DotMapBspMesh.build_meshes` gives such a surface an alpha-blended material of its kind (`glass_material`, or the game's `glass_material_for`) without asking the game's material callback, in meshes of their own, and `build_node` turns shadow casting off for them. A new kind is a row in the table, an entry in `GLASS_LOOKS`, and a row in `free_textures.tsv`.

A surface's material record decides the rest (`tools/bsp/dotbsp/materials.py`): the packed `.vmt`'s `$translucent`, `$alphatest`, `$additive` and `$nocull` and the base texture's alpha (read at 64 px) pick a generated look for a surface no table made see-through. Smooth alpha is `glass` tinted by the texture's colour, a cut-out is `fence`, `grate`, `bars` or `foliage_card` by the name's words, additive is `glow`, and a card at least 90% solid stays solid. The record carries `material_flags`, and `two_sided` where `$nocull` stands alone (`DotMapBspMesh` draws those back faces when the game's material is a `BaseMaterial3D`). A compiler `translucent` flag with no record (a base-game material) is guessed from the name only when the name says fence, grate, bars or foliage; otherwise the surface stays opaque and is listed in the coverage report's `surfaces_opaque`, which `--ratchet` can only shrink. A `materials.tsv` row (texture glob or generic id, then a kind or `opaque`) in any rule tier overrides the derivation.

**One-way glass for a jail.** `DotMapOneWayGlass` (used by `DotMapDrawnWorld` unless `options.one_way_glass` is false or the game set its own `glass_material_for`) finds the cell by shape: the destination most teleports land on, at least 3 and at least 10 m below the highest one, with its neighbours within 5 m. Clear glass within the cell's radius (6 m) is drawn opaque to a camera inside that radius and see-through to a camera outside it, by a shader comparing `CAMERA_POSITION_WORLD` with the cell centre. Bars keep their own look. It is a view effect only; bullets and movement are unchanged.

**Pad aimed at the jail.** A pit-fall lands in the jail and the jail's own exit opens onto its doorstep, but a teleport that nothing else aims at, that lands within 30 m of the cell and sits more than 40 m from it (a pad on the far side of the map whose target is the doorstep) is a release gone wrong. `release_pits` in `dotbsp/movers.py` retargets it to the highest popular destination (the top of the spawn) and records `retargeted_from` on the volume.

The manifest's `breakables` lists every `func_breakable` and `func_breakable_surf` model with its `health` (1 when the map gives none) and `glass` (the kind when all its surfaces are glass). `build_breakables(root)` makes a `DotMapGlass` body for each glass one: solid on the layer given, hurt by `hurt()` on the authoritative end, then hidden, non-solid and shedding shards, with the `broken` signal for a sound or effect and `apply_broken()` for a client following the host. Glass that does not break is an ordinary hull of kind `glass`: a game keeps that kind off the layer its bullets and projectiles hit if they should pass.

## Testing

`python3 -I tools/bsp/tests/test_mesh.py` (the `Entities` tests) and `res://examples/bsp_entities_demo.tscn` (32 checks) run on `examples/bsp_mesh/zm_4way_tunnel.entities.json`, the entity data of a real map with three lifts whose buttons lock and unlock one another (`tools/bsp/tests/entities_fixture.py` rewrites it from the downloaded map; only the derived data is in the repository).

## What a game does with it

1. Load the mesh and build its entities: `world.entities()`.
2. For each mover, place the model's node at `origin` and drive `transform_at` from a fraction it keeps; honour `locked`, `toggle`, `wait`, `use` and `touch`.
3. Make a press, a touch or a volume entry fire the matching `fired_by` links after their delays, and map each `input` onto the mover.
4. Games with their own door and barricade systems adapt at this layer; the converter stays game-neutral.
