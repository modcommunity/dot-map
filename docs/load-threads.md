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

## Pre-baked textures and the sliced prefetch

A raw store file costs about 11 to 13 ms to decode (webp 11.1, png 10.7, jpg 4.8 for a 1k map; measured on 50 ze_biohazard_manor textures) plus 3.4 ms to mip-map and compress, 15 ms in all; loading the same image pre-baked is 0.18 ms. `tools/bake_textures.gd -- <store dir> [--out=<dir>] [--max=2048]` (`DotMapTextureBake`) writes `<name>.s3tc.res` and `<name>.etc2.res` beside each `albedo|normal|roughness|ao` file; `DotMapSurfaces` takes the one for the build's VRAM format when it is not larger than `max_texture_size`, else decodes as before. A baked file is about 0.9 MB against 0.23 MB for the webp, so ship it inside a compressed pack, not as a new download. Never published by the tool; baked files are engine-version specific like an import.

`DotMapSurfaces.prefetch(world, dir)` is a coroutine: it decodes in worker batches and yields a frame every 8 ms, so dot-cloud's fetch callbacks and the loading cover run during the decode. `await` it before `world_material_for`, which then finds every texture cached; without the call the prefetch blocks the main thread as before.
