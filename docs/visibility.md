# Visibility: drawing only what the camera can see

A converted map is drawn as 16 m chunks (a 6 m height band each) of merged faces plus stand-in props. Without culling every chunk inside the frustum is drawn, including the shop behind three walls. `DotMapVisibility` (`addons/dot_map/bsp/dot_map_visibility.gd`) uses the map's own precomputed visibility data to draw only the chunks the camera's position could see, and adds occluders made from the map's large solid brushes for whatever that data cannot cover.

## What the converter keeps

`tools/bsp/dotbsp/vis.py`, called at the end of `mesh.build` (on by default, `visibility=False` turns it off), writes a `vis` record into the `dot-bsp-mesh` manifest. Every array lives in the `.bin` as an `{offset, count}` block, so a map without the data costs nothing and an older reader ignores it (the manifest version is unchanged).

| Key | What |
| --- | --- |
| `clusters`, `head` | cluster count and the world model's root node; 0 clusters means no precomputed data (occluders only) |
| `planes` (4 floats), `nodes` (3 ints) | the split-plane tree, converted to metres and Godot axes; a negative child is leaf `-1 - child` |
| `leaf_cluster`, `leaf_area` | each leaf's cluster (`-1` is solid) and area |
| `cluster_area` | each cluster's area |
| `pvs`, `pvs_offsets` | the potentially visible set per cluster, still run-length compressed as stored (a zero byte is followed by a count of zero bytes); the audible sets are dropped and equal rows shared |
| `portals`, `portal_entities` | area portals as `[key, area, area]`, and the entities that open and close them (`key`, `target` door, `start_open`, `window`) |
| `occluder_vertices`, `occluder_indices` | triangles of every large opaque world brush |

Each surface record gains `clusters`: every cluster any of its triangles touches, from one box query per triangle through the plane tree (1 unit of slack). The 3D sky has none and is always drawn. `DotMapBspMesh.build_meshes` unions a chunk's records into its `clusters` (null if any record has none), and `build_node` puts it on the MeshInstance3D as the `vis_clusters` meta.

An occluder brush is solid, not window, grate or translucent, has no translucent, sky or trigger side, no glass, foliage, water, fence, grate or chain-link material, at least one visible side, and is large (middle extent at least 1.5 m, middle times largest at least 6 m²). Each is shrunk by 4 cm (at most a quarter of its thinnest side) so it never hides the face it is part of.

## The runtime

```gdscript
var vis := DotMapVisibility.new()
vis.mode = DotMapVisibility.parse_mode(cfg_text)  # off | pvs | occluders | both
add_child(vis)
var res := vis.setup(world, world_node)           # a DotMapBspMesh and its build_node() tree
vis.set_door_open("door_store", false)            # the portals that door controls close
```

- The camera (`camera_ref`, a `DotNodeRef`, or the viewport's) is put in the world's local space. Only after it moves `move_step` (0.25 m) are the clusters within `margin` (1 m) looked up, and only when that set changes are chunks shown or hidden; a frame where nothing changed costs one distance check.
- A chunk is shown when one of its clusters is in the union of those clusters' PVS rows and in an area reachable from the camera's through open portals. Props (each child of a `Props` node) are placed in clusters by their bounds when `setup` runs.
- Inside solid or outside the map (no cluster) everything is drawn: a noclip camera never sees a hole.
- Occluders are one `OccluderInstance3D`, and the viewport's `use_occlusion_culling` is turned on while the mode includes them and put back on `_exit_tree`. They hide props, characters and chunks in the same cluster set but behind a wall.
- `chunk_view_distance` sets `visibility_range_end` on world chunks that have none: below 0 the fog's far plane (the default), 0 never.
- `shadows` says what a chunk hidden by the PVS still does: `NONE` hides it, `ALL` draws it shadow-only, `REACHING` (default) draws it shadow-only only while a shadow-casting light that touches a drawn chunk reaches it.
- A headless host does nothing unless `run_headless` is set; a dedicated server never draws.
- A map with neither clusters nor occluders makes `setup` fail with `CODE_UNSUPPORTED`; the caller drops the node and draws everything.

A game exposes the mode as a client video setting and a server or command-line override; game-zombie-zone uses `vis_mode` (setting) and `--zz-vis-mode=` (config).

## Proof: no holes

`examples/vis_demo.tscn` runs 16 checks on a three-cluster synthetic map (plane tree, box queries, PVS rows, solid fallback, the margin near a wall, a closed door, mode off, the no-data failure). With `-- --maps=<pack prefix>,...` it also loads real converted maps, builds collision from every chunk and prop, picks random sample points in non-solid leaves with a floor below, and casts uniform rays to 300 m. A ray that first hits a hidden item is a hole, unless it crossed a solid leaf on the way (a gap in the drawn world, where no face exists to see through, counted separately).

| Map | Points × rays | Holes | Rays through undrawn solid | Items drawn on average |
| --- | --- | --- | --- | --- |
| zm_abandoned_mall (2299 clusters) | 60 × 400 | 0 | 0 | 27% of 1281 |
| zm_4way_tunnel (949 clusters) | 40 × 300 | 0 | 1 | 62% of 56 |
| zm_16chambres (1960 clusters, 16 portals) | 40 × 300 | 0 | 1 | 6% of 281 |

A map converted without the data (ze_jurassicpark: 0 clusters) gets occluders only (1828 triangles).

## Measured

`game-zombie-zone/tools/shot_bench.sh --zz-map-ids=zm_abandoned_mall --zombies=56 --seed=7 --zz-vis-mode=<mode>` on the GTX 1660 Ti box (Forward+ under Xvfb, 1280×720), back to back on one tree. The bench stands among 56 zombies in the mall's open middle, about the worst place for culling.

| Mode | fps | frame ms | physics ms (steps) | render ms | GPU ms | draws | objects |
| --- | --- | --- | --- | --- | --- | --- | --- |
| off | 16.2, 18.3 | 61.7, 54.7 | 26.1 (3.7), 22.7 (3.3) | 29.5, 26.2 | 19.3, 16.5 | 1539, 1537 | 2412, 2442 |
| pvs | 16.2 | 61.8 | 26.8 (3.7) | 28.6 | 18.5 | 1220 | 1827 |
| occluders | 15.8 | 63.5 | 27.6 (3.8) | 29.6 | 18.8 | 1347 | 2062 |
| both | 17.0, 17.3 | 58.7, 57.7 | 24.8 (3.5), 24.2 (3.5) | 27.5, 27.5 | 17.1, 17.2 | 1107, 1106 | 1644, 1646 |

Both together cut draws by 28% and objects by 32%. The frame rate does not move beyond the box's run-to-run spread (two off runs differ by 2 fps): this bench is bound by the game's physics step, which a slow frame pays for several times over, not by drawing. On dev02's CPU renderer, where drawing is the cost, the same pair went from 2183 to 1383 draws and 161 to 117 ms of rendering.

Screenshots from five spots in the mall, off against both, differ only where a price tag drawn through walls (no depth test) was hidden by an occluder: anything drawn through walls on purpose must set `ignore_occlusion_culling`. No geometry was missing.

### Chunk size and the per-position table

Chunks were 32 m columns: the mall had 42 chunks, each touching hundreds of clusters, so pvs hid little (62% of triangles were shown from random points). They are now 16 m columns with a 6 m height band (`DOTBSP_CHUNK`, `DOTBSP_CHUNK_Y` override at conversion): 119 chunks in the mall, 50% of triangles shown. 12 m / 4 m cut a little more (46%) but raised unculled draws by half. Re-run `bsp.py regen` to get the finer chunks; packs made before keep the 32 m ones.

`tools/shot_vis_proof.sh` (`examples/vis_proof.gd`) on the GTX 1660 Ti, 640×360, no zombies, draw calls per mode at spots picked by how much of the map their PVS sees (`--world=<prefix> --spots=6 --diffs=24 --out=<dir>`; `--bisect` names the hidden chunks that change a frame; `--keepshadows`):

| Map, spot | off | pvs | occluders | both |
| --- | --- | --- | --- | --- |
| mall, room (5% PVS) | 492 | 307 | 297 | 144 |
| mall, room (21%) | 418 | 307 | 354 | 213 |
| mall, corridor | 697 | 568 | 648 | 521 |
| mall, open | 592 | 543 | 525 | 472 |
| Death Star, room (2%) | 582 | 248 | 412 | 178 |
| Death Star, corridor | 1004 | 629 | 804 | 587 |
| Death Star, open (42%) | 2522 | 1430 | 2323 | 1270 |

The earlier "no reduction" was the coarse chunks plus one run's spread: the 42 mall chunks were nearly all in every row.

Pixel comparison against off at 24 random positions (1660 Ti, 640x360): a hidden chunk used to stop casting shadows, so light leaked where it shaded (3 of 12 mall positions, worst 0.97%). `shadows = ALL` fixed it but drew every hidden chunk into the shadow pass (Death Star open spot: 1430 draws became 2453). The default is now `REACHING`: a hidden chunk is drawn shadow-only only while a shadow-casting light reaches it from a drawn chunk (a point or spot light by its range; a sun by sweeping the chunk's box along the light direction onto the drawn chunks near the camera). Result: mall 0 positions over 0.05% (worst 0.002%), Death Star 0 over (worst 0.049%); a sun checked by distance from the camera alone had still leaked (0.84%), because a caster far up-sun shades the drawn area. Draw calls over the six spots (off / pvs, shadows REACHING vs NONE vs ALL): mall room 371 / 315 vs 305 vs 337, mall open 643 / 620 vs 602 vs 623, Death Star room 372 / 338 vs 289 vs 347, Death Star corridor 683 / 673 vs 581 vs 680. Shadows cost most of what pvs saves on Death Star (a sun reaches everything), so set `shadows = NONE` for a map where a flicker at the edge of a shadow does not matter.

## Re-importing

A world pack carries the data only once it is regenerated by this converter (`bsp.py regen <store key>`); an older pack draws as before.
