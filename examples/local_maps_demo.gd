extends "suite_base.gd"

## DotMapLocalMaps: raw convert folders copied under a root are found, named "(local)", loaded and given start points;
## zips of them are unpacked once into a cache, and dropped folders and zips are copied in while junk is refused. Headless. The fixture section copies examples/bsp_mesh/fixture; `-- --source=<a map's convert folder>` adds a real
## map copied the way a person would, built into a DotMapWorld.

const FIXTURE := "res://examples/bsp_mesh/fixture"
const ROOT_A := "user://local_maps_demo/a"
const ROOT_B := "user://local_maps_demo/b"
const ROOT_REAL := "user://local_maps_demo/real"
const ROOT_ZIP := "user://local_maps_demo/zips"
const DROP := "user://local_maps_demo/dropped"
const OUTSIDE := "user://local_maps_demo/outside"

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
	var cache_was := DotMapLocalMaps.zip_cache
	DotMapLocalMaps.zip_cache = "user://local_maps_demo/.zip_cache"
	_test_fixture()
	_test_zip_and_drop()
	DotMapLocalMaps.zip_cache = cache_was
	var sections := 2
	var checks := 24 + 16
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
	_check(not DotMapLocalMaps.is_original(fx) and not DotMapLocalMaps.surfaces_for(fx).use_original_textures, "a plain local map keeps the free textures")
	var orig_entry := {"name": "bhop_amor_orig"}
	_check(DotMapLocalMaps.is_original(orig_entry) and DotMapLocalMaps.surfaces_for(orig_entry).use_original_textures, "an _orig pack draws its own textures")
	_check(DotMapLocalMaps.describe_lines(found).size() == 2, "a summary line per map")
	_done()


func _test_zip_and_drop() -> void:
	_section("zip and drop: zips unpacked once by hash, dropped folders and zips copied in, junk refused")
	var src := FIXTURE.get_base_dir()
	var fixture := {"fixture.json": FileAccess.get_file_as_bytes(src.path_join("fixture.json")),
			"fixture.bin": FileAccess.get_file_as_bytes(src.path_join("fixture.bin"))}
	# A zip of a whole map folder (one folder down, convert/ inside), and one of the convert folder's files at its top.
	_zip(ROOT_ZIP.path_join("fixture_map.zip"), {"fixture_map/convert/fixture.json": fixture["fixture.json"],
			"fixture_map/convert/fixture.bin": fixture["fixture.bin"], "fixture_map/addon.json": JSON.stringify({"title": "Zipped"}).to_utf8_buffer(),
			"__MACOSX/fixture_map/._fixture.bin": PackedByteArray([0])})
	_zip(ROOT_ZIP.path_join("bare.zip"), {"surf_bare.json": _renamed_manifest("surf_bare"), "surf_bare.bin": fixture["fixture.bin"]})
	_write(ROOT_ZIP.path_join("broken.zip"), "not a zip")
	_zip(ROOT_ZIP.path_join("climb.zip"), {"../evil.json": fixture["fixture.json"], "../evil.bin": fixture["fixture.bin"]})

	var found := DotMapLocalMaps.scan(PackedStringArray([ROOT_ZIP]))
	var ids := found.map(func(e: Dictionary) -> String: return str(e["id"]))
	_check(ids == ["fixture_local", "surf_bare_local"], "two zips are maps, the broken and climbing ones are not: %s" % str(ids))
	var zipped: Dictionary = found[0] if found.size() > 0 else {}
	_check(str(zipped.get("zip", "")) == ROOT_ZIP.path_join("fixture_map.zip") and str(zipped.get("root", "")) == ROOT_ZIP, "the entry names its zip and root")
	_check(str(zipped.get("dir", "")).begins_with(DotMapLocalMaps.zip_cache), "unpacked under the cache: %s" % str(zipped.get("dir", "")))
	_check(str(zipped.get("title", "")) == "Zipped (local)", "the title from the zipped addon.json")
	_check(not FileAccess.file_exists("user://local_maps_demo/evil.json"), "a climbing name is never written outside the cache")
	_check(not _has_file(DotMapLocalMaps.zip_cache, "._fixture.bin"), "__MACOSX litter is not unpacked")
	_check(DotMapLocalMaps.open(zipped).ok, "the zipped map loads")
	var cached := DirAccess.get_directories_at(DotMapLocalMaps.zip_cache).size()
	var stamp := FileAccess.get_modified_time(str(zipped.get("prefix", "")) + ".bin")
	DotMapLocalMaps.scan(PackedStringArray([ROOT_ZIP]))
	_check(DirAccess.get_directories_at(DotMapLocalMaps.zip_cache).size() == cached and cached == 2
			and FileAccess.get_modified_time(str(zipped.get("prefix", "")) + ".bin") == stamp, "a second scan unpacks nothing again (%d cached)" % cached)

	# Dropped: a map folder, a zip, a lone .json (its folder is taken), and junk that must not crash or be copied.
	_copy_files(src, OUTSIDE.path_join("dropme/convert"), ["fixture.json", "fixture.bin"])
	_copy_files(src, OUTSIDE.path_join("loose"), ["fixture.json", "fixture.bin"])
	_rename_pair(OUTSIDE.path_join("loose"), "fixture", "bhop_loose")
	_write(OUTSIDE.path_join("notes.txt"), "hello")
	_write(OUTSIDE.path_join("fake.zip"), "PK not really")
	DirAccess.make_dir_recursive_absolute(OUTSIDE.path_join("emptydir"))
	var abs_out := ProjectSettings.globalize_path(OUTSIDE)
	var result := DotMapLocalMaps.accept_dropped(PackedStringArray([abs_out.path_join("dropme"),
			ProjectSettings.globalize_path(ROOT_ZIP.path_join("bare.zip")), abs_out.path_join("loose/bhop_loose.json"),
			abs_out.path_join("notes.txt"), abs_out.path_join("fake.zip"), abs_out.path_join("emptydir"),
			abs_out.path_join("missing"), "", ProjectSettings.globalize_path("user://")]), DROP)
	var added: Array = result.get("added", [])
	var errors: PackedStringArray = result.get("errors", PackedStringArray())
	var added_ids := added.map(func(e: Dictionary) -> String: return str(e["id"]))
	added_ids.sort()
	_check(added_ids == ["bhop_loose_local", "fixture_local", "surf_bare_local"], "a folder, a zip and a lone .json's folder are added: %s" % str(added_ids))
	_check(errors.size() == 6, "six junk drops refused with a reason each: %s" % " | ".join(errors))
	_check(errors.size() > 0 and errors[0].begins_with("notes.txt: "), "the reason names the dropped file")
	_check(DirAccess.dir_exists_absolute(DROP.path_join("dropme/convert")) and FileAccess.file_exists(DROP.path_join("bare.zip")),
			"the folder and zip are copied in")
	_check(not FileAccess.file_exists(DROP.path_join("fake.zip")) and not DirAccess.dir_exists_absolute(DROP.path_join("emptydir")),
			"nothing is copied for junk")
	var rescanned := DotMapLocalMaps.scan(PackedStringArray([DROP]))
	_check(rescanned.size() == 3, "a rescan of the drop root lists the three: %s" % "; ".join(DotMapLocalMaps.describe_lines(rescanned)))
	var again := DotMapLocalMaps.accept_dropped(PackedStringArray([abs_out.path_join("dropme")]), DROP)
	_check((again["added"] as Array).size() == 1 and (again["errors"] as PackedStringArray).is_empty(), "dropping the same folder again replaces the copy")
	var self_drop := DotMapLocalMaps.accept_dropped(PackedStringArray([ProjectSettings.globalize_path(DROP.path_join("dropme"))]), DROP)
	_check((self_drop["added"] as Array).size() == 1 and DotMapLocalMaps.open(self_drop["added"][0]).ok, "a folder already in the drop root is kept, not wiped")
	_done()


func _zip(path: String, files: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var zip := ZIPPacker.new()
	if zip.open(path) != OK:
		print("    cannot write %s" % path)
		return
	for name: String in files:
		zip.start_file(name)
		zip.write_file(files[name])
		zip.close_file()
	zip.close()


func _renamed_manifest(new_name: String) -> PackedByteArray:
	var parsed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE.get_base_dir().path_join("fixture.json")))
	parsed["bin"]["file"] = new_name + ".bin"
	parsed["name"] = new_name
	return JSON.stringify(parsed).to_utf8_buffer()


func _has_file(dir: String, file: String) -> bool:
	if FileAccess.file_exists(dir.path_join(file)):
		return true
	for d in DirAccess.get_directories_at(dir):
		if _has_file(dir.path_join(d), file):
			return true
	return false


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
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.include_hidden = true
	for sub in d.get_directories():
		_wipe(dir.path_join(sub))
	for n in d.get_files():
		DirAccess.remove_absolute(dir.path_join(n))
	DirAccess.remove_absolute(dir)
