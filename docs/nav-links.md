# Doors and teleports for a navigation mesh

A navigation mesh is baked from static colliders, so the map's own logic is invisible to it: a door shut at the bake is a wall, a teleport is a box in the floor, and a door that a button, a trigger volume or a shot opens looks the same as one nothing opens. `DotMapNavLinks` (`addons/dot_map/io/dot_map_nav_links.gd`) reads that logic from a built map world and returns plain data. It moves nothing and runs no input; a bake, a bot or a tool decides what to do with it.

## Why here, and not in the bot

The facts live in the map's entity graph (`DotMapIO.entities`, their outputs, `destinations`, the volume nodes), which is dot-map's. A consumer that re-derived them would drift from the runtime that actually fires the inputs. dot-bot's `DotBotLinks` already read teleports and buttons by duck typing; it now takes this export as an opt-in, so a game that passes none is unchanged.

## The structure

`DotMapNavLinks.read(world)` takes anything with `io` and `volumes` (a `DotMapWorld`) and returns:

| Key | Value |
| --- | --- |
| `format` | `DotMapNavLinks.FORMAT`, bumped when a key changes meaning |
| `doors` | one per slide or hinge that starts shut: `entity`, `name`, `classname`, `box` (AABB at rest), `opens` (`touch`, `use` or `output`), `locked`, `opened_by` |
| `teleports` | one per teleport a runner could ever fire (clients flag, no filter, destination found): `entity`, `name`, `box`, `to` (Vector3), `enabled` now, `opened_by` (empty when enabled) |
| `openers` | `{entity index: {index, name, kind, box}}` for everything that can start a chain |
| `skipped` | counts of teleports left out: `flags`, `filtered`, `no_destination` |

An opener's `kind` is `walk` (a trigger volume to stand in), `use` (a button) or `shoot` (a button or door with an OnDamaged output). `opened_by` lists openers whose output chains reach the door or teleport, nearest first, each with `hops`, the chain length (a button to a relay to a door is 2). The chain follows any output but never through `Close`, `Lock`, `Disable`, `TurnOff` or `Kill`, which do not help a runner through. `DotMapNavLinks.chain(io, from, to)` returns the entity indices of one chain, for a log line.

Not covered: keys and counts of presses, a chain that needs something carried, and a shootable breakable without a mover box. A door whose only feeders are negative inputs has an empty `opened_by`; a consumer treats that as "nothing found", not "open".

## The consumer

`DotBotLinks.read(world, {"nav_export": export})` (or `apply_export(export)`) turns every opener that feeds a door or a disabled teleport into a gadget. Walk and use gadgets the bot already knew gain the door and teleport indices in `feeds`; a shot button is a new gadget kind, `shoot`, reached within `SHOOT_REACH` metres and fired by damaging it through `DotMapIO.hurt`, since a stand-in without a weapon is the map's own damage on the button. `unlock_doors` keeps the door hints. A bot held up by a door takes them in the "blocked" pass of `next_gadget`; the pass that looks for buttons enabling a teleport is unchanged.

## Proof

`examples/nav_links_demo.tscn` (24 checks) builds a synthetic entity set: a button through a relay to a door, a closer that must not count, a walk-in pad to a touch door, a shot button to a disabled teleport. dot-bot's `bot_selftest` section "unlock export" covers the gadget. mg-wipeout's `headless_io_bots` pins the first real runs on its Oaks and Pauls courses.
