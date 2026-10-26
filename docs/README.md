# dot-map docs

The reasoning behind maps as content, one subject per file. [CLAUDE.md](../CLAUDE.md) has the short rules; these say why.

| File | What it covers |
| --- | --- |
| [content.md](content.md) | Why one game with many maps, `DotMapDef`, the catalogue, reaching dot-cloud through the registry, zones as text |
| [changing.md](changing.md) | The order of a change, the five-message sync protocol and its rules, game vs map changes, the commands, what a host may name, template scenes, transport |
| [rotation.md](rotation.md) | The rotation's cooldown and seed, `DotMapVote`, `DotMapTimeLimit`, `map_over`, hibernation |
| [history.md](history.md) | The bugs, and how each looked |
| [surfaces.md](surfaces.md) | `DotMapSurfaces`: a material per surface kind, world-space triplanar, loaded by path for packs, sizes and credits; see-through generics and `keep_coverage`; `DotMapFx` (sprites, glows, cones, decals) |
| [brushes.md](brushes.md) | `DotMapBrush`: map-building solids as data, convex collision, UVs in metres |
| [brush-entities.md](brush-entities.md) | The converter's doors, buttons, lifts, triggers and output links as manifest data, and `DotMapEntities` reading them |
| [converter-v2.md](converter-v2.md) | The next converter: a lossless store of each source map, a replacement layer with a coverage report, the entity-class library and the I/O runtime, and the migration plan |
| [map-config.md](map-config.md) | `DotMapConfig`: per-map settings files with wildcards, the whitelist, applying on load and restoring on the next map, and the converter's starter file |
| [io.md](io.md) | `DotMapIO`: the queue, the tick, delays and fire-once counts, the logic classes, the loop guard, a game's handlers and callables, recorded commands, Office's timed hazard as the test |
| [culling.md](culling.md) | Culling for a hand-built level without BSP: what Godot 4.7 does natively, `DotOccluderBaker`, `DotAreaPortal`, measurements |
| [load-threads.md](load-threads.md) | `map_load_threads`: which load stages run on workers, why the output is identical, where the load time goes, how a game binds the cvar |
| [visibility.md](visibility.md) | `DotMapVisibility`: the converter's precomputed visibility and occluders, culling by the camera's cluster, area portals and doors, the no-holes test, measurements |
