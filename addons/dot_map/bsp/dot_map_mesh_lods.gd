class_name DotMapMeshLods
extends RefCounted

## Run-time LOD generation for a glTF model read without the editor import.


## Gives every unskinned [MeshInstance3D] mesh under [param root] with at least [param min_tris] triangles its LOD levels
## (meshoptimizer, as the editor's import does; a glTF read at run time has none), after cutting it to [param max_tris]
## (0: not cut). About a second for a million triangles, once per model. Returns how many meshes changed.
static func add(root: Node, min_tris: int, max_tris: int = 0) -> int:
	if min_tris <= 0:
		return 0
	var done := {}
	var changed := 0
	for found in root.find_children("*", "MeshInstance3D", true, false):
		var mi := found as MeshInstance3D
		var mesh := mi.mesh as ArrayMesh
		if mesh == null or mi.skin != null or mesh.get_blend_shape_count() > 0:
			continue
		if not done.has(mesh):
			done[mesh] = _with_lods(mesh, min_tris, max_tris)
		if done[mesh] != mesh:
			mi.mesh = done[mesh]
			changed += 1
	return changed


static func _with_lods(mesh: ArrayMesh, min_tris: int, max_tris: int) -> Mesh:
	var tris := 0
	var all: Array = []
	for i in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(i) != Mesh.PRIMITIVE_TRIANGLES:
			return mesh
		var arrays := mesh.surface_get_arrays(i)
		var index: Variant = arrays[Mesh.ARRAY_INDEX]
		tris += (index as PackedInt32Array).size() / 3 if index != null else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		all.append(arrays)
	if tris < min_tris:
		return mesh
	var importer := _importer_of(mesh, all)
	importer.generate_lods(25.0, 60.0, [])
	if max_tris > 0 and tris > max_tris:
		# Each surface restarts from the first level small enough for its share, then gets its own levels again.
		var share := float(max_tris) / float(tris)
		for i in all.size():
			var arrays: Array = all[i]
			var base := (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3 if arrays[Mesh.ARRAY_INDEX] != null else 0
			for l in importer.get_surface_lod_count(i):
				var indices := importer.get_surface_lod_indices(i, l)
				if indices.size() / 3 <= int(base * share) or l == importer.get_surface_lod_count(i) - 1:
					arrays[Mesh.ARRAY_INDEX] = indices
					break
		importer = _importer_of(mesh, all)
		importer.generate_lods(25.0, 60.0, [])
	var out := importer.get_mesh()
	return out if out != null else mesh


static func _importer_of(mesh: ArrayMesh, all: Array) -> ImporterMesh:
	var importer := ImporterMesh.new()
	for i in all.size():
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, all[i], [], {}, mesh.surface_get_material(i), mesh.surface_get_name(i))
	return importer
