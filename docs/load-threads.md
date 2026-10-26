# Threaded map loading (`map_load_threads`)

Off by default and never on the web. `0` is today's behaviour, `N` is N workers on the engine's pool, `-1` is automatic (processor count less one, at most 8): the meaning dot-core's `DotParallel.resolve_workers` gives every threading cvar. `DotParallel.available()` decides, so the web, a build without threads and a one-core machine run inline whatever the cvar says.

## What runs on workers

Only pure functions of frozen data, in `DotMapParallelBuild`, in batches of four tasks per worker so a whole map's arrays are never held at once (peak memory does not scale with the worker count):

| Stage | Task | Made on the main thread |
| --- | --- | --- |
| `DotMapBspMesh.build_meshes` | `_merged_arrays` of one material's records (slices, UV2/colour padding, index offsets) | `ArrayMesh.add_surface_from_arrays`, materials |
| `hull_shapes` | the points of one hull minus the model origin | `ConvexPolygonShape3D` |
| `concave_shapes` | the face array of one displacement surface | `ConcavePolygonShape3D` |
| `DotMapSurfaces.world_material_for` | `Image.load_from_file` and `generate_mipmaps` of every texture file the surfaces use | `ImageTexture`, materials |

Imported textures (`res://` with an import) are requested with `ResourceLoader.load_threaded_request` and collected before the material pass. The scene tree, meshes, shapes, materials and props are never touched off the main thread, and results are applied in index order, so the output is identical for every worker count (`examples/map_threads_selftest.tscn` compares hashes of the mesh arrays, hull points, faces and decoded pixels for 0, 1, 2, 4 and automatic).

## Binding it

dot-map has no console, so a game copies its cvar in once, before loading: `DotMapParallelBuild.default_workers = console.get_int("map_load_threads")`. A single world or surfaces object takes its own `load_threads`.

## Where the time goes

Measured on two converted survival maps (about 1 800 surfaces, 4 000 to 6 600 hulls, 100 000 vertices), headless, four cores shared with other jobs, best of three: reading and hashing the pack 125 ms, materials 160 ms, mesh arrays 25 ms, hull points 30 ms, faces 10 ms. The materials were nearly all one function: `light_floor()` scanned every ambient sample for each of the 157 materials (1 ms each), now computed once per world; that alone took the whole load from 357 to 221 ms and 342 to 212 ms, identical output. Threads then change the total by noise (212, 228, 215, 208 ms at 0, 1, 2 and 4 workers on one map; 221, 251, 232, 230 on the other), because the threadable parts add up to under 70 ms and a fork per batch costs a few ms. The cvar pays on a map with large displacement surfaces or many loose texture files, not on these. `tools/load_bench.sh <pack prefix>` prints the stage times and a digest of the output for 0, 1, 2 and 4 workers.
