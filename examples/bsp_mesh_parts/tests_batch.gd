extends "tests_terrain.gd"

## The prop batching and chunk merging sections of the bsp mesh suite.


func _box_mesh(size: Vector3, mat: Material) -> ArrayMesh:
	var box := BoxMesh.new()
	box.size = size
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, box.get_mesh_arrays())
	out.surface_set_material(0, mat)
	return out


func _prop(parent: Node3D, mesh: Mesh, xf: Transform3D) -> Node3D:
	var p := Node3D.new()
	p.transform = xf
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	p.add_child(mi)
	parent.add_child(p)
	return p


## Every drawn triangle under [param root], world space, per material: "material|a|b|c" with the corners in millimetres and
## rotated to start at the smallest, so the side the face is drawn from is part of the key.
func _triangles(root: Node3D) -> Array:
	var out := []
	var drawn := []   # [mesh, override, transform]
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		drawn.append([(n as MeshInstance3D).mesh, (n as MeshInstance3D).material_override, (n as Node3D).global_transform])
	for n: Node in root.find_children("*", "MultiMeshInstance3D", true, false):
		var mm := (n as MultiMeshInstance3D).multimesh
		var placed: Array = n.get_meta(&"test_placed")   # the headless server keeps no instance transforms
		for xf: Transform3D in placed:
			drawn.append([mm.mesh, (n as MultiMeshInstance3D).material_override, (n as Node3D).global_transform * xf])
	for d: Array in drawn:
		var mesh: Mesh = d[0]
		var xf: Transform3D = d[2]
		for s in mesh.get_surface_count():
			var a := mesh.surface_get_arrays(s)
			var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(v.size()))
			var mat: Material = d[1] if d[1] else mesh.surface_get_material(s)
			for i in range(0, idx.size(), 3):
				var c := [xf * v[idx[i]], xf * v[idx[i + 1]], xf * v[idx[i + 2]]].map(func(p: Vector3) -> String: return str(Vector3i((p * 1000.0).round())))
				if xf.basis.determinant() < 0.0:
					c.reverse()   # Godot draws a mirrored instance's faces turned back the right way out
				var lo := c.find(c.min())
				out.append("%s|%s|%s|%s" % [mat.get_instance_id() if mat else 0, c[lo], c[(lo + 1) % 3], c[(lo + 2) % 3]])
	out.sort()
	return out


func _test_prop_batch() -> void:
	_section("small static props bake into one mesh per material per cell, drawing the same triangles")
	var red := StandardMaterial3D.new()
	var blue := StandardMaterial3D.new()
	var small := _box_mesh(Vector3(1, 2, 0.5), red)
	var other := _box_mesh(Vector3(0.3, 0.3, 0.3), blue)
	var sphere := SphereMesh.new()
	sphere.radial_segments = 64
	sphere.rings = 32
	var big := ArrayMesh.new()
	big.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sphere.get_mesh_arrays())
	var props := Node3D.new()
	props.name = "Props"
	add_child(props)
	_prop(props, small, Transform3D(Basis.IDENTITY, Vector3(1, 0, 1)))
	_prop(props, small, Transform3D(Basis(Vector3.UP, 0.7).scaled(Vector3(1.5, 1, 1)), Vector3(3, 1, 2)))
	_prop(props, small, Transform3D(Basis.IDENTITY.scaled(Vector3(-1, 1, 1)), Vector3(5, 0, 4)))   # mirrored
	_prop(props, other, Transform3D(Basis(Vector3.RIGHT, 1.1), Vector3(2, 3, 6)))
	var mixed := _prop(props, big, Transform3D(Basis.IDENTITY, Vector3(8, 0, 8)))
	var part := MeshInstance3D.new()
	part.mesh = other
	part.position = Vector3(0, 2, 0)
	mixed.add_child(part)
	_prop(props, big, Transform3D(Basis(Vector3.UP, 0.3), Vector3(300, 0, 20)))
	_prop(props, big, Transform3D(Basis.IDENTITY.scaled(Vector3(2, 2, 2)), Vector3(304, 0, 20)))
	var copies := props.get_children().slice(-2).map(func(c: Node) -> Dictionary: return {"mi": c.get_child(0), "xf": (c as Node3D).transform})
	var expect_placed := DotMapPropBatch.instance_transforms(copies, (copies[0]["xf"] * (copies[0]["mi"] as MeshInstance3D).get_aabb()).merge(
			copies[1]["xf"] * (copies[1]["mi"] as MeshInstance3D).get_aabb()).get_center())
	var far := _prop(props, small, Transform3D(Basis.IDENTITY, Vector3(200, 0, 0)))
	(far.get_child(0) as MeshInstance3D).visibility_range_end = 40.0
	var scripted := _prop(props, small, Transform3D(Basis.IDENTITY, Vector3(2, 0, 2)))
	scripted.add_to_group(&"breakable")
	var before := _triangles(props)
	var b := DotMapPropBatch.new()
	b.max_tris = 1000
	var n := b.batch(props)
	for mmi: Node in props.find_children("*", "MultiMeshInstance3D", true, false):
		mmi.set_meta(&"test_placed", expect_placed)
	var after := _triangles(props)
	var off := range(mini(before.size(), after.size())).filter(func(i: int) -> bool: return before[i] != after[i])
	_check(before.size() == after.size() and off.is_empty(), "the same triangles, materials and windings are drawn (%d before, %d after, %d differ: %s)" % [
			before.size(), after.size(), off.size(), [before[off[0]], after[off[0]]] if not off.is_empty() else ""])
	_check(n == 2 and b.chunks == 2, "one chunk for the near cell and one for the far, faded prop: %d" % n)
	_check(b.batched_meshes == 6 and b.batched_props == 6, "six small meshes of six props baked: %d meshes, %d props" % [b.batched_meshes, b.batched_props])
	var near := props.get_children().filter(func(c: Node) -> bool: return c is MeshInstance3D and (c as MeshInstance3D).visibility_range_end == 0.0)
	_check(near.size() == 1 and (near[0] as MeshInstance3D).mesh.get_surface_count() == 2, "the near chunk is one surface per material")
	var faded := props.get_children().filter(func(c: Node) -> bool: return c is MeshInstance3D and (c as MeshInstance3D).visibility_range_end > 0.0)
	_check(faded.size() == 1 and (faded[0] as MeshInstance3D).visibility_range_end >= 40.0, "a faded prop's chunk fades no earlier")
	_check(is_instance_valid(scripted) and scripted.get_parent() == props and scripted.get_child_count() == 1, "a prop in a group keeps its own node")
	_check(is_instance_valid(mixed) and mixed.get_child_count() == 1 and (mixed.get_child(0) as MeshInstance3D).mesh == big,
			"a prop's large mesh keeps its node while its small part is baked")
	_check(b.multimeshes == 1 and b.instanced_meshes == 2, "two copies of a large mesh in one cell are one multimesh: %d of %d" % [b.multimeshes, b.instanced_meshes])
	var none := DotMapPropBatch.new()
	none.max_tris = 0
	_check(none.batch(props) == 0, "a max_tris of 0 bakes nothing")
	props.free()
	_done()


func _test_chunk_merge(world: DotMapBspMesh) -> void:
	_section("chunk merging: a small map keeps its cells, a merged one draws the same triangles in fewer chunks")
	_check(world.chunk_merge == 0 and world.auto_merge(0) == 1, "by default the fixture's two chunks are left alone")
	var whole := world.build_node(func(_r: Dictionary) -> Material: return null)
	add_child(whole)
	var cells := (whole.get_node("world") as Node3D).get_children().filter(func(c: Node) -> bool: return not str(c.name).begins_with("shadow_"))

	world.chunk_target = 1
	var n := world.auto_merge(0)
	var merged := world.build_node(func(_r: Dictionary) -> Material: return null)
	add_child(merged)
	var one := (merged.get_node("world") as Node3D).get_children().filter(func(c: Node) -> bool: return not str(c.name).begins_with("shadow_"))
	_check(n > 1 and one.size() == 1 and cells.size() == 2, "a target of one merges the cells into one chunk: n=%d, %d -> %d" % [n, cells.size(), one.size()])
	var shadows := (merged.get_node("world") as Node3D).get_children().filter(func(c: Node) -> bool: return str(c.name).begins_with("shadow_"))
	_check(_tri_count(one) == _tri_count(cells), "the merged chunk draws every triangle: %d vs %d" % [_tri_count(one), _tri_count(cells)])
	_check(shadows.size() <= 1, "one shadow proxy for the merged chunk: %d" % shadows.size())
	world.chunk_target = 512
	whole.free()
	merged.free()
	_done()


func _tri_count(nodes: Array) -> int:
	var t := 0
	for n: Node in nodes:
		var m := (n as MeshInstance3D).mesh
		for s in m.get_surface_count():
			var a := m.surface_get_arrays(s)
			t += ((a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() if a[Mesh.ARRAY_INDEX] != null else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return t
