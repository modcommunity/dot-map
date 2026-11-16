extends "tests_image.gd"

## The terrain section of the bsp mesh suite.

const TERRAIN := "res://examples/bsp_mesh/terrain_fixture.json"


func _test_terrain() -> void:
	_section("terrain reads as the converter wrote it (dot-map-convert/tests/test_terrain.py)")
	var fx: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TERRAIN))
	var res := DotMapTerrain.from_dict(fx["terrain"])
	_check(res.ok, "the terrain fixture reads: %s" % ("" if res.ok else str(res)))
	if not res.ok:
		_done()
		return
	var t: DotMapTerrain = res.value
	var bad := PackedStringArray()
	for p: Array in fx["probes"]:
		var h := t.height_at(p[0], p[1])
		if (p[2] == null) != is_nan(h) or (p[2] != null and absf(h - float(p[2])) > 1e-4):
			bad.append("(%s, %s) %s != %s" % [p[0], p[1], h, p[2]])
	_check(bad.is_empty(), "heights match the converter's: %s" % ", ".join(bad))
	var pts := t.walk_points(1.0)
	_check(pts.size() == int(fx["walk_points"]), "walk points %d, converter %d" % [pts.size(), fx["walk_points"]])
	var first: Array = fx["walk_first"]
	var last: Array = fx["walk_last"]
	_check(not pts.is_empty() and pts[0].distance_to(Vector3(first[0], first[1], first[2])) < 1e-3
			and pts[-1].distance_to(Vector3(last[0], last[1], last[2])) < 1e-3, "first and last walk points match")
	var faces := t.faces()
	_check(faces.size() == int(fx["faces"]), "faces %d, converter %d (the hole is kept)" % [faces.size(), fx["faces"]])
	_check((faces[1] - faces[0]).cross(faces[2] - faces[0]).y < 0.0, "faces wind clockwise seen from above, so they face up")
	var want := PackedStringArray()
	var got := t.skirt_edges()
	for k in range(0, got.size(), 4):
		want.append("%d,%d,%d,%d" % [got[k], got[k + 1], got[k + 2], got[k + 3]])
	want.sort()
	var theirs := PackedStringArray(str(fx["skirt_edges"]).split(";"))
	theirs.sort()
	_check(want == theirs, "the skirt's rim edges are the converter's (%d), the enclosed hole has none" % want.size())
	var wall := t.skirt_faces()
	_check(wall.size() == want.size() * 6 and not is_nan(t.skirt_y), "a skirt of one quad per rim edge hangs to %.2f" % t.skirt_y)
	var lowest := INF
	for v in wall:
		lowest = minf(lowest, v.y)
	_check(is_equal_approx(lowest, t.skirt_y), "the wall reaches the skirt level, under the lowest ground")
	_check(t.build_shape().get_faces().size() == faces.size() and t.build_shape(true).get_faces().size() == faces.size() + wall.size(),
			"collision is the field alone unless the skirt is asked for")
	var plain: Dictionary = fx["terrain"].duplicate()
	plain.erase("skirt")
	_check(DotMapTerrain.from_dict(plain).value.skirt_faces().is_empty(), "a field written without a skirt draws none")
	var newer: Dictionary = fx["terrain"].duplicate()
	newer["format"] = DotMapTerrain.FORMAT + 1
	_check(DotMapTerrain.from_dict(newer).code() == DotError.CODE_VERSION, "a newer format is refused as a version error")
	var broken: Dictionary = fx["terrain"].duplicate()
	broken["bytes"] = 1
	_check(DotMapTerrain.from_dict(broken).code() == DotError.CODE_PARSE, "a wrong size is refused as a parse error")
	_check_terrain_mesh(DotMapTerrain.from_dict(fx["terrain"]).value)
	_done()


## build_mesh() builds packed arrays directly; it must match the SurfaceTool reference it replaced.
func _check_terrain_mesh(tr: DotMapTerrain) -> void:
	var built := tr.build_mesh()
	var arr_got: Array = built.surface_get_arrays(0)
	var ref_st := SurfaceTool.new()
	ref_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ground := tr.faces()
	for k in ground.size():
		ref_st.set_uv(Vector2(ground[k].x, ground[k].z))
		ref_st.add_vertex(ground[k])
	var skirt_tris := tr.skirt_faces()
	for k in range(0, skirt_tris.size(), 3):
		for side in 2:
			for v in 3:
				var q: Vector3 = skirt_tris[k + (v if side == 0 else 2 - v)]
				ref_st.set_uv(Vector2(q.x + q.z, q.y))
				ref_st.add_vertex(q)
	ref_st.generate_normals()
	var arr_want: Array = ref_st.commit_to_arrays()
	_check(arr_got[Mesh.ARRAY_VERTEX].size() == arr_want[Mesh.ARRAY_VERTEX].size(), "terrain mesh vertex count matches the SurfaceTool reference: %d vs %d" % [arr_got[Mesh.ARRAY_VERTEX].size(), arr_want[Mesh.ARRAY_VERTEX].size()])
	var worst := 0.0
	var ground_n: int = ground.size()
	for k in mini(arr_got[Mesh.ARRAY_NORMAL].size(), arr_want[Mesh.ARRAY_NORMAL].size()):
		if k < ground_n:
			worst = maxf(worst, (arr_got[Mesh.ARRAY_NORMAL][k] - arr_want[Mesh.ARRAY_NORMAL][k]).length())
	_check(worst < 0.001, "ground normals match the SurfaceTool reference (worst %f)" % worst)
	var uv_ok := true
	for k in mini(arr_got[Mesh.ARRAY_TEX_UV].size(), arr_want[Mesh.ARRAY_TEX_UV].size()):
		if not arr_got[Mesh.ARRAY_TEX_UV][k].is_equal_approx(arr_want[Mesh.ARRAY_TEX_UV][k]):
			uv_ok = false
	_check(uv_ok, "terrain uvs match the reference")
