class_name DotOccluderBaker
extends RefCounted

## Bakes occluders from a scene's static meshes: large flat faces (walls, floors, ceilings) become quads of
## one [OccluderInstance3D].

const NODE_NAME := "BakedOccluders"
const SKIP_GROUP := &"dot_no_occluder"

## Smallest face area in square metres.
var min_area: float = 6.0
## Smallest side of the face's rectangle in metres.
var min_side: float = 1.5
## Share of the rectangle the triangles must cover (a doorway-sized hole fails it).
var min_fill: float = 0.85
## How far a quad is pulled in from every edge, in metres.
var inset: float = 0.04
## Quads kept, largest first.
var max_quads: int = 256
## Plane tolerance in metres, and in dot product for normals.
var plane_eps: float = 0.02
var normal_eps: float = 0.01

## Filled by [method bake]: meshes seen, faces found, quads kept.
var stats := {"meshes": 0, "faces": 0, "quads": 0}


## Bakes [param root]'s meshes into one OccluderInstance3D child. Fails when no face is large enough.
func bake(root: Node3D) -> DotResult:
	var old := root.get_node_or_null(NODE_NAME)
	if old != null:
		root.remove_child(old)
		old.free()
	stats = {"meshes": 0, "faces": 0, "quads": 0}
	var to_root := root.global_transform.affine_inverse() if root.is_inside_tree() else Transform3D.IDENTITY
	var quads: Array[Dictionary] = []
	_walk(root, root, to_root, quads)
	stats["faces"] = quads.size()
	quads.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["area"] > b["area"])
	if quads.size() > max_quads:
		quads.resize(max_quads)
	stats["quads"] = quads.size()
	if quads.is_empty():
		return DotResult.fail(DotError.CODE_INVALID, "no face is large enough to occlude", str(root.name))
	var verts := PackedVector3Array()
	var index := PackedInt32Array()
	for q in quads:
		var base := verts.size()
		verts.append_array(q["corners"])
		index.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	var occ := ArrayOccluder3D.new()
	occ.set_arrays(verts, index)
	var inst := OccluderInstance3D.new()
	inst.name = NODE_NAME
	inst.occluder = occ
	root.add_child(inst)
	inst.owner = root if root.owner == null else root.owner
	return DotResult.success(inst)


func _walk(n: Node, root: Node3D, to_root: Transform3D, quads: Array[Dictionary]) -> void:
	if n is Node3D and not (n as Node3D).visible:
		return
	if n.is_in_group(SKIP_GROUP) or n is OccluderInstance3D:
		return
	if n is MeshInstance3D and _solid(n as MeshInstance3D):
		var mi := n as MeshInstance3D
		var xf: Transform3D = to_root * mi.global_transform if mi.is_inside_tree() else _local_chain(mi, root)
		stats["meshes"] += 1
		var groups: Array[Dictionary] = []
		_collect(mi.mesh, xf, groups)
		for g in groups:
			var q := _quad(g)
			if not q.is_empty():
				quads.append(q)
	for c in n.get_children():
		_walk(c, root, to_root, quads)


func _local_chain(mi: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = mi
	while n != null and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


func _solid(mi: MeshInstance3D) -> bool:
	if mi.mesh == null or mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
		return false
	if mi.transparency > 0.0:
		return false
	for s in mi.mesh.get_surface_count():
		var m := mi.get_active_material(s)
		if m is BaseMaterial3D and (m as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			return false
	return true


func _collect(mesh: Mesh, xf: Transform3D, groups: Array[Dictionary]) -> void:
	for s in mesh.get_surface_count():
		if mesh is ArrayMesh and (mesh as ArrayMesh).surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var count := idx.size() if not idx.is_empty() else v.size()
		for t in range(0, count - 2, 3):
			var a: Vector3 = xf * v[idx[t] if not idx.is_empty() else t]
			var b: Vector3 = xf * v[idx[t + 1] if not idx.is_empty() else t + 1]
			var c: Vector3 = xf * v[idx[t + 2] if not idx.is_empty() else t + 2]
			var cross := (b - a).cross(c - a)
			var area := cross.length() * 0.5
			if area < 1e-6:
				continue
			_add(groups, cross.normalized(), a, b, c, area)


func _add(groups: Array[Dictionary], n: Vector3, a: Vector3, b: Vector3, c: Vector3, area: float) -> void:
	var d := n.dot(a)
	for g in groups:
		if (g["n"] as Vector3).dot(n) > 1.0 - normal_eps and absf(float(g["d"]) - d) < plane_eps:
			g["tris"].append([a, b, c])
			g["area"] += area
			return
	groups.append({"n": n, "d": d, "tris": [[a, b, c]], "area": area})


func _quad(g: Dictionary) -> Dictionary:
	if float(g["area"]) < min_area:
		return {}
	var n: Vector3 = g["n"]
	var u := n.cross(Vector3.UP if absf(n.y) < 0.99 else Vector3.RIGHT).normalized()
	var w := n.cross(u)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for t: Array in g["tris"]:
		for p: Vector3 in t:
			var q := Vector2(p.dot(u), p.dot(w))
			lo = lo.min(q)
			hi = hi.max(q)
	var ext := hi - lo
	if minf(ext.x, ext.y) < min_side or float(g["area"]) < min_fill * ext.x * ext.y:
		return {}
	lo += Vector2(inset, inset)
	hi -= Vector2(inset, inset)
	if hi.x <= lo.x or hi.y <= lo.y:
		return {}
	var o: Vector3 = n * float(g["d"])
	var corners := PackedVector3Array([
		o + u * lo.x + w * lo.y, o + u * hi.x + w * lo.y, o + u * hi.x + w * hi.y, o + u * lo.x + w * hi.y])
	return {"corners": corners, "area": (hi.x - lo.x) * (hi.y - lo.y)}
