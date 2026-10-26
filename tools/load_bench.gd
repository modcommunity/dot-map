extends SceneTree
## Times the pure-CPU stages of loading a converted world and prints a digest of the output.
## godot --headless --path . --script tools/load_bench.gd -- <prefix> <workers>

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var prefix := args[0]
	var workers := int(args[1])
	var t0 := Time.get_ticks_msec()
	var t := t0
	var w: DotMapBspMesh = DotMapBspMesh.load_prefix(prefix).value
	w.load_threads = workers
	print("load_prefix ms ", Time.get_ticks_msec() - t)
	t = Time.get_ticks_msec()
	var s := DotMapSurfaces.new()
	s.load_threads = workers
	var mf := s.world_material_for(w, prefix.get_base_dir())
	print("textures ms ", Time.get_ticks_msec() - t)
	t = Time.get_ticks_msec()
	var groups := w.build_meshes(0, mf)
	print("build_meshes ms ", Time.get_ticks_msec() - t)
	t = Time.get_ticks_msec()
	var hs := w.hull_shapes(0)
	var cs := w.concave_shapes(0)
	print("shapes ms ", Time.get_ticks_msec() - t)
	print("TOTAL ms ", Time.get_ticks_msec() - t0)
	var d := []
	for g: Dictionary in groups:
		for i in (g["mesh"] as ArrayMesh).get_surface_count():
			d.append((g["mesh"] as ArrayMesh).surface_get_arrays(i))
	var vs := 0
	for g: Dictionary in groups:
		for i in (g["mesh"] as ArrayMesh).get_surface_count():
			vs += ((g["mesh"] as ArrayMesh).surface_get_arrays(i)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	print("DIGEST meshes ", var_to_bytes(d).hex_encode().sha256_text().substr(0, 12), " verts ", vs, " hulls ", hs.size(), " ",
		var_to_bytes(hs.map(func(h: Dictionary) -> Variant: return h["shape"].points)).hex_encode().sha256_text().substr(0, 12),
		" concave ", cs.size(), " ", var_to_bytes(cs.map(func(c: ConcavePolygonShape3D) -> Variant: return c.get_faces())).hex_encode().sha256_text().substr(0, 12))
	quit()
