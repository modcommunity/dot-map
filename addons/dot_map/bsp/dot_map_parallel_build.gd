class_name DotMapParallelBuild
extends RefCounted
## The pure-CPU stages of loading a converted world, on the worker pool when [code]map_load_threads[/code] is not 0.
##
## Every task reads frozen data and returns arrays; scenes, meshes, shapes and textures are made on the calling thread, in index order, so the result is the same for any worker count.

const CHANNEL := "dot_map.parallel"
## Entries per worker in flight at once: the arrays of a whole map are never held together.
const PER_WORKER := 4

## Process-wide default for [member DotMapBspMesh.load_threads] and [member DotMapSurfaces.load_threads]; a game copies its cvar here once. 0 is off, -1 automatic ([method DotParallel.resolve_workers]).
static var default_workers: int = 0


## How many items one fork carries for [param workers].
static func batch_size(workers: int) -> int:
	return maxi(DotParallel.resolve_workers(workers), 1) * PER_WORKER


## [method DotMapBspMesh.surface_arrays] merged per list of records in [param lists]; slot i is lists[i]'s.
static func merged(world: DotMapBspMesh, lists: Array, workers: int) -> Array:
	return DotParallel.run(func(i: int) -> Variant: return world._merged_arrays(lists[i]), lists.size(), &"map.mesh", workers)


## Hull points of [param recs] minus [param origin], one [PackedVector3Array] per record.
static func hull_points(world: DotMapBspMesh, recs: Array, origin: Vector3, workers: int) -> Array:
	return DotParallel.run(func(i: int) -> Variant:
		var p := int(recs[i]["point_offset"])
		var pts := world._blob.slice(p, p + 12 * int(recs[i]["point_count"])).to_vector3_array()
		for k in pts.size():
			pts[k] -= origin
		return pts, recs.size(), &"map.hulls", workers)


## Triangle faces (three points per index) of [param recs] minus [param origin], one array per record.
static func concave_faces(world: DotMapBspMesh, recs: Array, origin: Vector3, workers: int) -> Array:
	return DotParallel.run(func(i: int) -> Variant:
		var a := world.surface_arrays(recs[i])
		var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var index: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		var faces := PackedVector3Array()
		faces.resize(index.size())
		for k in index.size():
			faces[k] = verts[index[k]] - origin
		return faces, recs.size(), &"map.faces", workers)


## Decodes and mip-maps image files on workers, a batch at a time, and returns path -> [ImageTexture] (made here, on the calling thread). A file that does not decode is left out.
static func textures(paths: PackedStringArray, workers: int, max_size: int = 0) -> Dictionary:
	var out := {}
	var step := batch_size(workers)
	for from in range(0, paths.size(), step):
		var n := mini(step, paths.size() - from)
		var images := DotParallel.run(func(i: int) -> Variant:
			var img := Image.load_from_file(paths[from + i])
			if img != null:
				DotMapSurfaces.prepare_image(img, paths[from + i], max_size)
			return img, n, &"map.textures", workers)
		for i in n:
			if images[i] != null:
				out[paths[from + i]] = ImageTexture.create_from_image(images[i])
	return out


## The mean of the sky-facing (+y) ambient cube face over [param n] samples of 21 floats.
static func sky_mean(ambient: PackedFloat32Array, n: int) -> Vector3:
	var c := Vector3.ZERO
	for i in n:
		var o := 21 * i + 3 + 3 * 2
		c += Vector3(ambient[o], ambient[o + 1], ambient[o + 2])
	return c / float(n)
