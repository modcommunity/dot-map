extends "suite_base.gd"

## DotMapLocalMaps: raw convert folders copied under a root are found, named "(local)", loaded and given start points.
## Headless. The fixture section copies examples/bsp_mesh/fixture; `-- --source=<a map's convert folder>` adds a real
## map copied the way a person would, built into a DotMapWorld.

const FIXTURE := "res://examples/bsp_mesh/fixture"
const ROOT_A := "user://local_maps_demo/a"
const ROOT_B := "user://local_maps_demo/b"
const ROOT_REAL := "user://local_maps_demo/real"

var _source := ""


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--source="):
			_source = arg.trim_prefix("--source=").rstrip("/")
	_run.call_deferred()


func _run() -> void:
	print("dot-map local maps")
	_wipe("user://local_maps_demo")
	_test_fixture()
	var sections := 1
	var checks := 22
	if _source != "":
		sections += 1
		checks += 11
		_test_real()
	else:
		print("  (no --source: the real map section is skipped)")
	_wipe("user://local_maps_demo")
	_finish(checks, sections)


func _test_fixture() -> void:
	_section("fixture: the copied layouts, ids, titles and generated spawns")
	_check(DotMapLocalMaps.roots() == PackedStringArray(["res://addons/maps", "user://maps"]), "the default roots")

	# A whole map folder with convert/ inside and an addon.json beside it.
	_copy_files(FIXTURE.get_base_dir(), ROOT_A.path_join("fixture_map/convert"), ["fixture.json", "fixture.bin"])
	_write(ROOT_A.path_join("fixture_map/addon.json"), JSON.stringify({"title": "Fixture Title", "type": "map"}))
	# The convert folder itself, renamed by the copy, under a second root, with a surf name.
	_copy_files(FIXTURE.get_base_dir(), ROOT_B.path_join("convert"), ["fixture.json", "fixture.bin"])
	_rename_pair(ROOT_B.path_join("convert"), "fixture", "surf_fixture")
	# The same fixture again under the second root: the first root's copy wins.
	_copy_files(FIXTURE.get_base_dir(), ROOT_B.path_join("again"), ["fixture.json", "fixture.bin"])
	# A manifest with no mesh beside it, and an empty folder: neither is a map.
	_copy_files(FIXTURE.get_base_dir(), ROOT_B.path_join("half"), ["glass.json"])
	DirAccess.make_dir_recursive_absolute(ROOT_B.path_join("empty"))

	var found := DotMapLocalMaps.scan(PackedStringArray([ROOT_A, ROOT_B]))
	var ids := found.map(func(e: Dictionary) -> String: return str(e["id"]))
	_check(ids == ["fixture_local", "surf_fixture_local"], "two maps found, sorted, half and empty skipped: %s" % str(ids))
	var fx: Dictionary = found[0] if found.size() > 0 else {}
	var surf: Dictionary = found[1] if found.size() > 1 else {}
	_check(str(fx.get("root", "")) == ROOT_A, "the first root's copy wins over the second's")
	_check(str(fx.get("prefix", "")) == ROOT_A.path_join("fixture_map/convert/fixture"), "the prefix inside convert/")
	_check(str(fx.get("title", "")) == "Fixture Title (local)", "the title from addon.json, tagged: %s" % str(fx.get("title", "")))
	_check(fx.get("kind") == DotMapDef.KIND_ARENA, "an unprefixed name is an arena map")
	_check(str(surf.get("title", "")) == "surf_fixture (local)", "no addon.json: the name, tagged")
	_check(surf.get("kind") == DotMapDef.KIND_SURF, "surf_ is a surf map")
	_check(DotMapLocalMaps.kind_for("gm_fork") == DotMapDef.KIND_SANDBOX and DotMapLocalMaps.kind_for("BHOP_x") == DotMapDef.KIND_BHOP,
			"gm_ is sandbox, the prefix is case-blind")
	_check(DotMapLocalMaps.find(&"surf_fixture_local", PackedStringArray([ROOT_A, ROOT_B])).get("dir") == ROOT_B.path_join("convert"),
			"find by id")
	_check(DotMapLocalMaps.find(&"fixture", PackedStringArray([ROOT_A, ROOT_B])).is_empty(), "the bare name is not a local id")
	_check(DotMapLocalMaps.scan(PackedStringArray(["user://local_maps_demo/none"])).is_empty(), "a missing root is no maps")

	var def := DotMapLocalMaps.to_def(fx)
	_check(def.validate().ok, "the def validates: %s" % str(def.validate()))
	_check(def.id == &"fixture_local" and def.display_name == "Fixture Title (local)", "the def's id and name")
	_check(def.version.begins_with("0.0.0-") and def.version.length() == 18, "the version is the manifest hash: %s" % def.version)
	_check(def.is_local() and def.scene_path.ends_with("fixture.json"), "local, pointing at the manifest")

	var opened := DotMapLocalMaps.open(fx)
	_check(opened.ok, "the copy loads: %s" % str(opened))
	var mesh: DotMapBspMesh = opened.value if opened.ok else null
	var starts: Array[Dictionary] = []
	var hulls: Array[Dictionary] = []
	if mesh != null:
		starts = DotMapLocalMaps.spawns(mesh)
		hulls = mesh.hull_shapes(DotMapBspMesh.WORLD)
	_check(starts.size() == 1 and bool(starts[0]["generated"]), "no spawns in the manifest: one generated")
	_check(starts.size() == 1 and starts[0]["origin"] is Vector3, "the generated spawn is a point")
	_check(not hulls.is_empty(), "the world has collision hulls: %d" % hulls.size())

	_write(ROOT_B.path_join("convert/surf_fixture.bin"), "not a mesh")
	_check(not DotMapLocalMaps.open(surf).ok, "a damaged copy fails to load, it does not crash")
	_check(DotMapLocalMaps.describe_lines(found).size() == 2, "a summary line per map")
	_done()


func _test_real() -> void:
	_section("real map: %s copied in whole" % _source.get_base_dir().get_file())
	var name := _source.get_base_dir().get_file()
	var folder := ROOT_REAL.path_join(name)
	_check(_copy_tree(_source, folder.path_join("convert")) > 0, "the convert folder copied")
	if FileAccess.file_exists(_source.get_base_dir().path_join("addon.json")):
		_copy_files(_source.get_base_dir(), folder, ["addon.json"])

	var found := DotMapLocalMaps.scan(PackedStringArray([ROOT_REAL]))
	_check(found.size() == 1, "found once: %s" % "; ".join(DotMapLocalMaps.describe_lines(found)))
	if found.size() != 1:
		for _i in 9:
			_check(false, "skipped: no single map found")
		_done()
		return
	var entry: Dictionary = found[0]
	print("    %s" % "; ".join(DotMapLocalMaps.describe_lines(found)))
	_check(str(entry.get("id", "")) == DotMapLocalMaps.prefix_in(_source).get_file() + "_local", "the id is the mesh name, suffixed")
	_check(str(entry.get("title", "")).ends_with(" (local)"), "tagged local")
	_check(DotMapLocalMaps.to_def(entry).validate().ok, "the def validates")

	var t0 := Time.get_ticks_msec()
	var opened := DotMapLocalMaps.open(entry)
	_check(opened.ok, "loads: %s" % str(opened))
	if not opened.ok:
		for _i in 5:
			_check(false, "skipped: the map did not load")
		_done()
		return
	var mesh: DotMapBspMesh = opened.value
	var starts := DotMapLocalMaps.spawns(mesh)
	var listed: Array = mesh.manifest.get("spawns", [])
	_check(not starts.is_empty(), "start points: %d" % starts.size())
	_check(listed.is_empty() or (starts.size() == listed.size() and not bool(starts[0]["generated"])), "the manifest's own spawns are used")

	var built := DotMapWorld.build(mesh, {}, {"environment": false})
	_check(built.ok, "builds a DotMapWorld: %s" % str(built))
	if built.ok:
		var world: DotMapWorld = built.value
		add_child(world)
		var bodies := world.find_children("*", "CollisionObject3D", true, false).size()
		_check(bodies > 0, "the world collides: %d bodies" % bodies)
		_check(not world.spawn_points().is_empty() or not starts.is_empty(), "the world has spawns")
		print("    loaded and built in %d ms, %d spawns, %d bodies" % [Time.get_ticks_msec() - t0, starts.size(), bodies])
		world.queue_free()
	else:
		_check(false, "no world to collide")
		_check(false, "no world for spawns")
	_done()


func _copy_files(from_dir: String, to_dir: String, names: Array) -> void:
	DirAccess.make_dir_recursive_absolute(to_dir)
	for n: String in names:
		var err := DirAccess.copy_absolute(from_dir.path_join(n), to_dir.path_join(n))
		if err != OK:
			print("    copy failed %s: %s" % [n, error_string(err)])


func _copy_tree(from_dir: String, to_dir: String) -> int:
	DirAccess.make_dir_recursive_absolute(to_dir)
	var count := 0
	for n in DirAccess.get_files_at(from_dir):
		if DirAccess.copy_absolute(from_dir.path_join(n), to_dir.path_join(n)) == OK:
			count += 1
	for d in DirAccess.get_directories_at(from_dir):
		count += _copy_tree(from_dir.path_join(d), to_dir.path_join(d))
	return count


func _rename_pair(dir: String, old: String, new_name: String) -> void:
	var json := FileAccess.get_file_as_string(dir.path_join(old + ".json"))
	var parsed: Dictionary = JSON.parse_string(json)
	parsed["bin"]["file"] = new_name + ".bin"
	parsed["name"] = new_name
	_write(dir.path_join(new_name + ".json"), JSON.stringify(parsed))
	DirAccess.rename_absolute(dir.path_join(old + ".bin"), dir.path_join(new_name + ".bin"))
	DirAccess.remove_absolute(dir.path_join(old + ".json"))


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)


func _wipe(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for d in DirAccess.get_directories_at(dir):
		_wipe(dir.path_join(d))
	for n in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(n))
	DirAccess.remove_absolute(dir)
