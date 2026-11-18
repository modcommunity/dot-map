class_name DotMapPropBatch
extends RefCounted
## Draws a world's small static props as merged meshes, one surface per material per [member cell], instead of one node per prop.
##
## A converted map places thousands of small props (Fork: 4,300 under 4,096 triangles, 371 materials), and each was its own draw per
## surface: 4,800 draws from one overlook, the frame on a desktop GPU. [method batch] bakes the meshes of every plain prop under a
## world's [code]Props[/code] node (a [Node3D]/[MeshInstance3D] tree: no script, no skin, no blend shapes, no group) whose mesh has at
## most [member max_tris] triangles into one [ArrayMesh] per [member cell] of the map, a surface per material, so the cell is one draw
## per material however many props it holds. The same triangles, materials and transforms are drawn. Larger meshes keep their LOD
## levels: the copies of one within an [member instance_cell] are drawn as one [MultiMeshInstance3D], and a lone copy keeps its node. The chunks stay direct children of [code]Props[/code], so [DotMapVisibility] culls them by their bounds.
## A chunk fades no earlier than any prop in it did: props are grouped by fade distance (a quarter octave), and a chunk's
## [member GeometryInstance3D.visibility_range_end] is its members' furthest reach from the chunk's centre (Godot measures the range
## to an instance's bounds centre). Collision bodies, proxies (meta [code]dot_map_proxy[/code]) and anything with behaviour are left as they are.

const CHANNEL := "dot_map.batch"

## The edge of a batching cell, metres. Smaller keeps frustum, occlusion and fade culling finer; larger folds more props into one draw.
var cell: float = 64.0
## Most triangles a prop's mesh may have to be merged; larger meshes stay their own node. 0 merges none.
var max_tris: int = 4096

## The edge of an instancing cell, metres: copies of one larger mesh within a cell are drawn as one [MultiMeshInstance3D]. 0 instances none.
var instance_cell: float = 256.0

## Props the last [method batch] folded meshes of.
var batched_props: int = 0
## Mesh copies folded, and the chunks drawn for them.
var batched_meshes: int = 0
var chunks: int = 0
## Larger mesh copies drawn as instances by the last [method batch], and the [MultiMeshInstance3D]s drawing them.
var instanced_meshes: int = 0
var multimeshes: int = 0


## Bakes the small plain props under [param props] into merged chunks; returns the number of chunks made.
func batch(props: Node3D) -> int:
	batched_props = 0
	batched_meshes = 0
	chunks = 0
	if max_tris <= 0:
		return 0
	var tris_of := {}
	var cells := {}    # key -> {parts: [part], box}
	var members: Array[Node] = []
	for c in props.get_children():
		if not _plain(c):
			continue
		var parts: Array[Dictionary] = []
		_collect(c as Node3D, Transform3D.IDENTITY, (c as Node3D).transform, parts)
		# A prop's small leaf meshes are baked even when a larger part of it keeps its own node (and LOD levels).
		parts = parts.filter(func(p: Dictionary) -> bool: return p["mi"].get_child_count() == 0 and _small(p["mi"].mesh, tris_of, max_tris))
		if parts.is_empty():
			continue
		batched_props += 1
		for p in parts:
			members.append(p["mi"])
			var mi: MeshInstance3D = p["mi"]
			var at := (p["xf"] as Transform3D) * mi.get_aabb().get_center()
			var key := [Vector3i((at / cell).floor()), mi.cast_shadow, mi.layers, mi.gi_mode, mi.transparency, mi.material_overlay,
				mi.visibility_range_fade_mode, _fade_bucket(mi.visibility_range_end)]
			if not cells.has(key):
				cells[key] = []
			(cells[key] as Array).append(p)
			batched_meshes += 1
	for key: Array in cells:
		var node := _chunk(cells[key])
		if node != null:
			props.add_child(node)
			chunks += 1
	for mi in members:
		mi.get_parent().remove_child(mi)
		mi.free()
	_instance(props, tris_of)
	DotLog.info(CHANNEL, "props batched", {"props": batched_props, "meshes": batched_meshes, "chunks": chunks, "cell": cell, "max_tris": max_tris,
			"instanced": instanced_meshes, "multimeshes": multimeshes})
	return chunks


## Draws the copies of each larger mesh (left by the bake) within an [member instance_cell] as one [MultiMeshInstance3D]:
## the same mesh, LOD levels, material and transforms, one draw per surface for all of them.
func _instance(props: Node3D, tris_of: Dictionary) -> void:
	instanced_meshes = 0
	multimeshes = 0
	if instance_cell <= 0.0:
		return
	var groups := {}
	for c in props.get_children():
		if not _plain(c) or c.name == "Batch":
			continue
		var parts: Array[Dictionary] = []
		_collect(c as Node3D, Transform3D.IDENTITY, (c as Node3D).transform, parts)
		for p in parts:
			var mi: MeshInstance3D = p["mi"]
			if mi.get_child_count() > 0 or _overrides_surfaces(mi):
				continue
			var at := (p["xf"] as Transform3D) * mi.get_aabb().get_center()
			var key := [mi.mesh, mi.material_override, Vector3i((at / instance_cell).floor()), mi.cast_shadow, mi.layers, mi.gi_mode,
				mi.transparency, mi.material_overlay, mi.visibility_range_fade_mode, _fade_bucket(mi.visibility_range_end), mi.lod_bias]
			if not groups.has(key):
				groups[key] = []
			(groups[key] as Array).append(p)
	for key: Array in groups:
		var list: Array = groups[key]
		if list.size() < 2:
			continue
		props.add_child(_multimesh(list))
		multimeshes += 1
		for p: Dictionary in list:
			var mi: MeshInstance3D = p["mi"]
			mi.get_parent().remove_child(mi)
			mi.free()
			instanced_meshes += 1


## Each of [param list]'s copies (each [code]{mi, xf}[/code]) placed relative to [param centre], where its instance node stands.
static func instance_transforms(list: Array, centre: Vector3) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for p: Dictionary in list:
		out.append(Transform3D(Basis.IDENTITY, -centre) * (p["xf"] as Transform3D))
	return out


static func _overrides_surfaces(mi: MeshInstance3D) -> bool:
	for s in mi.get_surface_override_material_count():
		if mi.get_surface_override_material(s) != null:
			return true
	return false


## One [MultiMeshInstance3D] at [param list]'s bounds centre drawing each copy at its transform, with the first's settings and
## a fade no earlier than any copy's.
static func _multimesh(list: Array) -> MultiMeshInstance3D:
	var first: MeshInstance3D = list[0]["mi"]
	var box := AABB()
	for i in list.size():
		var b: AABB = (list[i]["xf"] as Transform3D) * (list[i]["mi"] as MeshInstance3D).get_aabb()
		box = b if i == 0 else box.merge(b)
	var centre := box.get_center()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = first.mesh
	mm.instance_count = list.size()
	var placed := instance_transforms(list, centre)
	for i in placed.size():
		mm.set_instance_transform(i, placed[i])
	var node := MultiMeshInstance3D.new()
	node.name = "Instances"
	node.multimesh = mm
	node.position = centre
	node.material_override = first.material_override
	node.material_overlay = first.material_overlay
	node.cast_shadow = first.cast_shadow
	node.layers = first.layers
	node.gi_mode = first.gi_mode
	node.transparency = first.transparency
	node.lod_bias = first.lod_bias
	node.visibility_range_fade_mode = first.visibility_range_fade_mode
	_fade_like(node, list, centre)
	return node


## [param node]'s fade: no earlier than any of [param list]'s members (each [code]{mi, xf}[/code]) faded, measured from [param centre].
static func _fade_like(node: GeometryInstance3D, list: Array, centre: Vector3) -> void:
	var reach := 0.0
	var margin := 0.0
	for p: Dictionary in list:
		var mi: MeshInstance3D = p["mi"]
		if mi.visibility_range_end <= 0.0:
			return
		var d := ((p["xf"] as Transform3D) * mi.get_aabb().get_center()).distance_to(centre)
		reach = maxf(reach, mi.visibility_range_end + d)
		margin = maxf(margin, mi.visibility_range_end_margin)
	node.visibility_range_end = reach
	node.visibility_range_end_margin = margin


## Quarter-octave bucket of a fade distance; 0 for none (drawn at any range).
static func _fade_bucket(end: float) -> int:
	return 0 if end <= 0.0 else 1 + roundi(log(end) / log(2.0) * 4.0)


static func _small(mesh: Mesh, tris_of: Dictionary, most: int) -> bool:
	if not tris_of.has(mesh):
		var t := 0
		var ok := mesh is ArrayMesh and (mesh as ArrayMesh).get_blend_shape_count() == 0
		if ok:
			for s in mesh.get_surface_count():
				if mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
					ok = false
					break
				var fmt := (mesh as ArrayMesh).surface_get_format(s)
				if fmt & (Mesh.ARRAY_FORMAT_BONES | Mesh.ARRAY_FORMAT_WEIGHTS | Mesh.ARRAY_FORMAT_CUSTOM0 | Mesh.ARRAY_FORMAT_CUSTOM1 \
						| Mesh.ARRAY_FORMAT_CUSTOM2 | Mesh.ARRAY_FORMAT_CUSTOM3):
					ok = false
					break
				var n := (mesh as ArrayMesh).surface_get_array_index_len(s)
				t += (n if n > 0 else (mesh as ArrayMesh).surface_get_array_len(s)) / 3
		tris_of[mesh] = t if ok else -1
	var tris: int = tris_of[mesh]
	return tris >= 0 and tris <= most


## A tree of only [Node3D] and [MeshInstance3D] (mesh set, no skin), with no script, group, visibility parent or begin range.
static func _plain(n: Node) -> bool:
	if n.has_meta(&"dot_map_proxy") or n.get_script() != null or not n.get_groups().is_empty():
		return false
	var cls := n.get_class()
	if cls == "MeshInstance3D":
		var mi := n as MeshInstance3D
		if mi.skin != null or mi.mesh == null or mi.visibility_range_begin > 0.0 or not mi.visibility_parent.is_empty():
			return false
	elif cls != "Node3D":
		return false
	for c in n.get_children():
		if not _plain(c):
			return false
	return true


## The visible meshes under [param n], each with its transform in the Props node's space.
static func _collect(n: Node3D, parent_xf: Transform3D, own: Transform3D, out: Array[Dictionary]) -> void:
	if not n.visible:
		return
	var xf := parent_xf * own
	if n is MeshInstance3D:
		out.append({"mi": n, "xf": xf})
	for c in n.get_children():
		_collect(c as Node3D, xf, (c as Node3D).transform, out)


## The material a mesh instance draws surface [param s] with.
static func _material(mi: MeshInstance3D, s: int) -> Material:
	if mi.material_override != null:
		return mi.material_override
	var m := mi.get_surface_override_material(s)
	return m if m != null else mi.mesh.surface_get_material(s)


## One mesh of [param list]'s surfaces in the chunk's frame (origin at the chunk's bounds centre), a surface per material and
## vertex format, drawn with the first member's settings.
static func _chunk(list: Array) -> MeshInstance3D:
	var box := AABB()
	for i in list.size():
		var mi: MeshInstance3D = list[i]["mi"]
		var b: AABB = (list[i]["xf"] as Transform3D) * mi.get_aabb()
		box = b if i == 0 else box.merge(b)
	var centre := box.get_center()
	var groups := {}    # [material, format] -> [[arrays, xf]]
	for p: Dictionary in list:
		var mi: MeshInstance3D = p["mi"]
		var mesh := mi.mesh as ArrayMesh
		var xf := Transform3D(Basis.IDENTITY, -centre) * (p["xf"] as Transform3D)
		for s in mesh.get_surface_count():
			var key := [_material(mi, s), mesh.surface_get_format(s) & _ATTRIBUTES]
			if not groups.has(key):
				groups[key] = []
			(groups[key] as Array).append([mesh.surface_get_arrays(s), xf])
	var out := ArrayMesh.new()
	for key: Array in groups:
		if out.get_surface_count() >= 256:
			break
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _merged(groups[key]))
		out.surface_set_material(out.get_surface_count() - 1, key[0])
	if out.get_surface_count() == 0:
		return null
	var first: MeshInstance3D = list[0]["mi"]
	var node := MeshInstance3D.new()
	node.name = "Batch"
	node.mesh = out
	node.position = centre
	node.material_overlay = first.material_overlay
	node.cast_shadow = first.cast_shadow
	node.layers = first.layers
	node.gi_mode = first.gi_mode
	node.transparency = first.transparency
	node.visibility_range_fade_mode = first.visibility_range_fade_mode
	_fade_like(node, list, centre)
	return node


## The vertex attributes a surface carries: surfaces merge only with others carrying the same ones.
const _ATTRIBUTES := Mesh.ARRAY_FORMAT_VERTEX | Mesh.ARRAY_FORMAT_NORMAL | Mesh.ARRAY_FORMAT_TANGENT | Mesh.ARRAY_FORMAT_COLOR \
		| Mesh.ARRAY_FORMAT_TEX_UV | Mesh.ARRAY_FORMAT_TEX_UV2


## Surface arrays of the same format, each moved by its transform, as one set of arrays (indices offset, normals and tangents turned).
static func _merged(items: Array) -> Array:
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var index := PackedInt32Array()
	for item: Array in items:
		var a: Array = item[0]
		var xf: Transform3D = item[1]
		var base := verts.size()
		var mirrored := xf.basis.determinant() < 0.0
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		verts.append_array(xf * v)
		var nb := xf.basis.inverse().transposed()
		if a[Mesh.ARRAY_NORMAL] != null:
			var n := Transform3D(nb, Vector3.ZERO) * (a[Mesh.ARRAY_NORMAL] as PackedVector3Array)
			for i in n.size():
				n[i] = n[i].normalized()
			normals.append_array(n)
		if a[Mesh.ARRAY_TANGENT] != null:
			var t: PackedFloat32Array = (a[Mesh.ARRAY_TANGENT] as PackedFloat32Array).duplicate()
			for i in range(0, t.size(), 4):
				var r := (xf.basis * Vector3(t[i], t[i + 1], t[i + 2])).normalized()
				t[i] = r.x
				t[i + 1] = r.y
				t[i + 2] = r.z
				if mirrored:
					t[i + 3] = -t[i + 3]
			tangents.append_array(t)
		if a[Mesh.ARRAY_INDEX] != null:
			var idx: PackedInt32Array = (_flipped(a[Mesh.ARRAY_INDEX]) if mirrored else (a[Mesh.ARRAY_INDEX] as PackedInt32Array).duplicate())
			for i in idx.size():
				idx[i] += base
			index.append_array(idx)
		else:
			var tri := PackedInt32Array()
			tri.resize(v.size())
			for i in v.size():
				tri[i] = base + i
			index.append_array(_flipped(tri) if mirrored else tri)
		for slot in [Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
			if a[slot] != null:
				if out[slot] == null:
					out[slot] = (a[slot]).duplicate()
				else:
					out[slot].append_array(a[slot])
	out[Mesh.ARRAY_VERTEX] = verts
	if not normals.is_empty():
		out[Mesh.ARRAY_NORMAL] = normals
	if not tangents.is_empty():
		out[Mesh.ARRAY_TANGENT] = tangents
	out[Mesh.ARRAY_INDEX] = index
	return out


## [param idx] with each triangle's winding reversed (a mirrored transform turns a triangle inside out).
static func _flipped(idx: PackedInt32Array) -> PackedInt32Array:
	var out := idx.duplicate()
	for i in range(0, out.size() - 2, 3):
		out[i + 1] = idx[i + 2]
		out[i + 2] = idx[i + 1]
	return out
