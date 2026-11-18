extends "suite_base.gd"

## DotMapDropIntake: paths read off a command line, the web drop's own folder skipped, window drops handed to the first
## acceptor that claims them, deep and configurable folder search, and every unclaimed or missing path refused out loud.
## Headless, on the bsp_mesh fixture.

const FIXTURE_DIR := "res://examples/bsp_mesh"
const BASE := "user://drop_intake_demo"
const DROP := "user://drop_intake_demo/dropped"
const OUTSIDE := "user://drop_intake_demo/outside"

var _results: Array = []


func _ready() -> void:
	DotLog.set_level(DotLog.Level.OFF)
	_run.call_deferred()


func _run() -> void:
	print("dot-map drop intake")
	_wipe(BASE)
	var cache_was := DotMapLocalMaps.zip_cache
	DotMapLocalMaps.zip_cache = BASE.path_join(".zip_cache")
	_make_fixtures()
	_test_args()
	_test_web_root()
	_test_window()
	_test_limits()
	_test_docs()
	DotMapLocalMaps.zip_cache = cache_was
	DotMapLocalMaps.zip_max_files = DotMapLocalMaps.ZIP_MAX_FILES
	_wipe(BASE)
	_finish(18 + 4 + 16 + 6 + 14, 5)


func _make_fixtures() -> void:
	var pair := {"fixture.json": FileAccess.get_file_as_bytes(FIXTURE_DIR.path_join("fixture.json")),
			"fixture.bin": FileAccess.get_file_as_bytes(FIXTURE_DIR.path_join("fixture.bin"))}
	# A map three folders below what is dropped, as a download often unpacks: outer/inner/mymap/convert/<pair>.
	for name: String in pair:
		_write_bytes(OUTSIDE.path_join("deep/outer/inner/mymap/convert").path_join(name), pair[name])
		_write_bytes(OUTSIDE.path_join("plain/convert").path_join(name), pair[name])
	_zip(OUTSIDE.path_join("zipped.zip"), {"zipped/convert/fixture.json": pair["fixture.json"], "zipped/convert/fixture.bin": pair["fixture.bin"]})
	_zip(OUTSIDE.path_join("other.zip"), {"readme.txt": "hi".to_utf8_buffer()})
	_write_bytes(OUTSIDE.path_join("notes.txt"), "hello".to_utf8_buffer())
	_write_bytes(OUTSIDE.path_join("level.custom"), "{}".to_utf8_buffer())
	DirAccess.make_dir_recursive_absolute(OUTSIDE.path_join("emptydir"))


func _test_args() -> void:
	_section("args: dropped-on-the-exe paths, engine option values skipped, --map-path, missing paths reported")
	var plain := _abs("plain")
	var notes := _abs("notes.txt")
	var project := ProjectSettings.globalize_path("res://")
	var got := DotMapDropIntake.paths_in_args(PackedStringArray([plain]))
	_check(got["paths"] == PackedStringArray([plain]) and (got["missing"] as PackedStringArray).is_empty(), "a bare path, as a drop on the exe gives: %s" % str(got))
	got = DotMapDropIntake.paths_in_args(PackedStringArray(["--path", project, "--headless", "--script", notes, notes]))
	_check(got["paths"] == PackedStringArray([notes]), "--path and --script values are not drops, the later bare one is: %s" % str(got["paths"]))
	got = DotMapDropIntake.paths_in_args(PackedStringArray(["--map-path=" + plain, "--map-path", notes]))
	_check(got["paths"] == PackedStringArray([plain, notes]), "--map-path=<p> and --map-path <p>: %s" % str(got["paths"]))
	got = DotMapDropIntake.paths_in_args(PackedStringArray(["--map-path=/no/such/map", "--map-path"]))
	_check(got["missing"] == PackedStringArray(["/no/such/map", "--map-path with no path"]), "a missing --map-path is reported: %s" % str(got["missing"]))
	got = DotMapDropIntake.paths_in_args(PackedStringArray(["/no/such/folder", "pg_flatgrass", "res://main.tscn", "user://x", "--solo-map=pg", "--", "++"]))
	_check((got["paths"] as PackedStringArray).is_empty() and got["missing"] == PackedStringArray(["/no/such/folder"]),
			"a missing absolute path is reported, a bare word and engine paths are not: %s" % str(got))
	got = DotMapDropIntake.paths_in_args(PackedStringArray(["wss://tmcdev.net:6100/", "ws://127.0.0.1:6100", "https://x.net/a", "tmcdev.net:6100", plain]))
	_check(got["paths"] == PackedStringArray([plain]) and (got["missing"] as PackedStringArray).is_empty(),
			"a connect URL or host:port is not a path, so never 'missing': %s" % str(got))
	got = DotMapDropIntake.paths_in_args(PackedStringArray(["--config", plain]))
	_check(got["paths"] == PackedStringArray([plain]), "an option the list does not know is a switch, so its next word is read")
	got = DotMapDropIntake.paths_in_args(PackedStringArray(["--config", plain]), PackedStringArray(["--config"]))
	_check((got["paths"] as PackedStringArray).is_empty(), "a game's own value option is skipped once listed")
	got = DotMapDropIntake.paths_in_args(PackedStringArray(["--level=" + notes]), PackedStringArray(), "--level")
	_check(got["paths"] == PackedStringArray([notes]), "the explicit option's name is configurable")
	var windows := plain.replace("/", "\\")
	got = DotMapDropIntake.paths_in_args(PackedStringArray([windows]))
	_check(got["paths"] == PackedStringArray([plain]), "backslashes are read as separators when the raw path does not exist: %s" % str(got["paths"]))

	var intake := _intake()
	_check(intake.take_cmdline(PackedStringArray(["--headless", "pg_word"])).is_empty() and _results.is_empty(), "no paths on the command line: nothing handled, no signal")
	var r := intake.take_cmdline(PackedStringArray([plain, "/no/such/map.zip"]))
	_check(str(r.get("source", "")) == "command line" and (r["added"] as Array).size() == 1, "an exe drop of a map folder is added: %s" % str(r.get("errors", "")))
	_check((r["errors"] as PackedStringArray).size() == 1 and (r["errors"] as PackedStringArray)[0] == "map.zip: not found", "a missing one is refused by name: %s" % str(r["errors"]))
	_check(_results.size() == 1, "handled emitted once")
	intake.free()
	_test_config_options(plain)
	_done()


## A fake dot-core config: `--demo-title <value>` takes a value, `--demo-loud` is a bool switch.
class FakeConfig:
	var title := ""
	var loud := false

	func config_keys() -> PackedStringArray:
		return PackedStringArray(["title", "loud"])

	func _match_key(raw: String, keys: PackedStringArray) -> String:
		return raw if keys.has(raw) else ""


func _test_config_options(plain: String) -> void:
	var config := FakeConfig.new()
	var intake := _intake()
	intake.config_prefixes = PackedStringArray(["--demo-"])
	intake.option_takes_value = func(_prefix: String, stem: String) -> bool: return DotMapDropIntake.config_takes_value(config, stem)
	var args := PackedStringArray(["--demo-title", plain, "--demo-loud", plain, "--demo-unknown", plain, "--other.key", plain, "--demo-title=" + plain, "x"])
	var stripped := DotMapDropIntake.strip_config_args(args, intake.config_prefixes, intake.option_takes_value)
	_check(stripped == PackedStringArray([plain, plain, "x"]),
			"a valued option eats its folder, a bool switch and an unknown key do not, `--addon.key v` and `--k=v` go: %s" % str(stripped))
	_check(intake.paths_in(args) == PackedStringArray([plain, plain]), "paths_in reads what is left that exists")
	_check(DotMapDropIntake.strip_config_args(args, PackedStringArray(["--demo-"])).size() == 1, "with no takes_value every option without = eats a non-option argument")
	var r := intake.take_cmdline(PackedStringArray(["--demo-title", plain, "--demo-loud"]))
	_check(r.is_empty(), "a folder that is a config value is not a drop")
	intake.free()


func _test_web_root() -> void:
	_section("web: the browser's drop folder is skipped, an ordinary list is kept")
	var root := _abs("")
	var both := PackedStringArray([root, _abs("plain"), _abs("notes.txt")])
	_check(DotMapDropIntake.without_web_root(both) == PackedStringArray([_abs("plain"), _abs("notes.txt")]), "the parent of every other entry is dropped")
	var mixed := PackedStringArray([_abs("plain"), _abs("notes.txt")])
	_check(DotMapDropIntake.without_web_root(mixed) == mixed, "two siblings stay")
	_check(DotMapDropIntake.without_web_root(PackedStringArray([root])) == PackedStringArray([root]), "a single path stays")
	var nested := PackedStringArray([root, _abs("deep/outer")])
	_check(DotMapDropIntake.without_web_root(nested) == nested, "a grandchild is not the browser's layout, kept")
	_done()


func _test_window() -> void:
	_section("window: drops claimed by the first acceptor, searched deep, the rest refused loudly")
	var intake := _intake()
	_check(intake._window == get_window(), "the intake watches its window from _ready")
	get_window().files_dropped.emit(PackedStringArray([_abs("deep"), _abs("zipped.zip"), _abs("notes.txt"), _abs("emptydir"), _abs("other.zip"), "/no/such/thing"]))
	_check(_results.size() == 1, "one window drop, one handled signal")
	var r: Dictionary = _results[0] if _results.size() > 0 else {}
	var added: Array = r.get("added", [])
	var errors: PackedStringArray = r.get("errors", PackedStringArray())
	var ids := added.map(func(e: Dictionary) -> String: return str(e["id"]))
	_check(str(r.get("source", "")) == "window", "the source is the window")
	_check(ids == ["fixture_local", "fixture_local"], "the deep folder and the zip are added: %s | %s" % [str(ids), " | ".join(errors)])
	_check(DirAccess.dir_exists_absolute(DROP.path_join("mymap/convert")), "the deep find copies the map folder itself, not the outer folders")
	_check(not DirAccess.dir_exists_absolute(DROP.path_join("deep")), "the wrapping folders are not copied")
	_check(errors.size() == 4, "four refusals: %s" % " | ".join(errors))
	_check(errors.size() > 0 and errors[0] == "notes.txt: not a map this game can load (it takes a converted map folder or its .zip)", "the refusal names the file and what the game takes: %s" % (errors[0] if errors.size() > 0 else ""))
	_check(errors.has("thing: not found"), "a missing path is refused, not skipped")
	_check(not FileAccess.file_exists(DROP.path_join("other.zip")), "a zip of no map is not copied")
	_check(intake.drops == 1 and intake.added_total == 2 and intake.refused_total == 4, "the totals: %s" % " / ".join(intake.describe_lines()))
	var lines := DotMapDropIntake.lines_for(r)
	_check(lines.size() == 6 and lines[0].begins_with("Added map: ") and lines[2].begins_with("Cannot load notes.txt"), "lines for a toast: %s" % " | ".join(lines))

	# A game's own acceptor before the converted one: it claims its kind, the converted one still gets folders.
	var custom := _intake(false)
	custom.add_acceptor("a .custom level", func(path: String, to: String) -> Dictionary:
		if path.get_extension() != "custom":
			return {}
		return {"added": [{"id": "custom_level", "title": "Custom", "into": to}], "errors": PackedStringArray()})
	custom.add_converted_maps()
	var c := custom.handle(PackedStringArray([_abs("level.custom"), _abs("plain"), _abs("notes.txt")]))
	var c_ids := (c["added"] as Array).map(func(e: Dictionary) -> String: return str(e["id"]))
	_check(c_ids == ["custom_level", "fixture_local"], "each path goes to the acceptor that claims it: %s" % str(c_ids))
	_check((c["errors"] as PackedStringArray).size() == 1 and (c["errors"] as PackedStringArray)[0].ends_with("(it takes a .custom level or a converted map folder or its .zip)"),
			"the refusal lists every kind: %s" % str(c["errors"]))
	_check(custom.accepted_kinds() == PackedStringArray(["a .custom level", "a converted map folder or its .zip"]), "accepted_kinds in order")

	var none := _intake(false)
	var n := none.handle(PackedStringArray([_abs("plain")]))
	_check((n["errors"] as PackedStringArray).size() == 1 and (n["errors"] as PackedStringArray)[0] == "plain: this game loads no dropped maps", "with no acceptor every drop is refused: %s" % str(n["errors"]))
	intake.free()
	custom.free()
	none.free()
	_done()


func _test_limits() -> void:
	_section("limits: search depth and zip size are settings, 0 is no limit")
	var intake := _intake()
	intake.search_depth = 2
	var r := intake.handle(PackedStringArray([_abs("deep")]))
	_check((r["added"] as Array).is_empty() and (r["errors"] as PackedStringArray).size() == 1, "a map three folders down is not found at depth 2")
	intake.search_depth = 0
	r = intake.handle(PackedStringArray([_abs("deep")]))
	_check((r["added"] as Array).size() == 1, "depth 0 searches every level")
	DotMapLocalMaps.zip_max_files = 1
	r = intake.handle(PackedStringArray([_abs("zipped.zip")]))
	var errs: PackedStringArray = r["errors"]
	_check((r["added"] as Array).is_empty() and errs.size() == 1 and errs[0].contains("more than zip_max_files 1"), "a zip over zip_max_files is refused, naming the setting: %s" % str(errs))
	DotMapLocalMaps.zip_max_files = 0
	r = intake.handle(PackedStringArray([_abs("zipped.zip")]))
	_check((r["added"] as Array).size() == 1, "zip_max_files 0 is no limit")
	DotMapLocalMaps.zip_max_files = DotMapLocalMaps.ZIP_MAX_FILES
	intake.into = BASE.path_join("elsewhere")
	r = intake.handle(PackedStringArray([_abs("plain")]))
	_check((r["added"] as Array).size() == 1 and DirAccess.dir_exists_absolute(BASE.path_join("elsewhere/plain/convert")), "into is where copies go")
	_check(intake.describe_lines().size() == 3 and intake.describe_lines()[0].contains("search_depth 0 (no limit)"), "describe_lines: %s" % " / ".join(intake.describe_lines()))
	intake.free()
	_done()


func _test_docs() -> void:
	_section("documents: a game's own map JSON taken from a file, a folder or a zip (DotMapDocDrop)")
	var doc := '{"kind":"demo_map","id":"demo_a","name":"Demo A"}'
	var other := '{"kind":"demo_map","id":"demo_b","name":"Demo B"}'
	_write_bytes(OUTSIDE.path_join("docs/a.json"), doc.to_utf8_buffer())
	_write_bytes(OUTSIDE.path_join("docs/sub/b.json"), other.to_utf8_buffer())
	_write_bytes(OUTSIDE.path_join("docs/notes.json"), '{"kind":"other"}'.to_utf8_buffer())
	_zip(OUTSIDE.path_join("docs.zip"), {"pack/a.json": doc.to_utf8_buffer(), "pack/b.json": other.to_utf8_buffer(), "../evil.json": doc.to_utf8_buffer()})
	_zip(OUTSIDE.path_join("onedoc.zip"), {"x/a.json": doc.to_utf8_buffer(), "readme.txt": "hi".to_utf8_buffer()})
	_zip(OUTSIDE.path_join("nodoc.zip"), {"x/other.json": '{"kind":"other"}'.to_utf8_buffer()})
	var into := BASE.path_join("docs_into")
	var kinds := PackedStringArray(["demo_map"])
	var taken: Array = []
	var take := func(d: Dictionary, text: String, name: String, to: String) -> Dictionary:
		taken.append(name)
		if str(d.get("id", "")) == "demo_b" and name == "b.json" and taken.size() > 100:
			return {"error": "unreachable"}
		var path := DotMapDocDrop.write_doc(to, str(d["id"]), text)
		return {"added": {"id": d["id"], "title": d["name"], "path": path}} if path != "" else {"error": "cannot write"}
	var r := DotMapDocDrop.accept(_abs("docs/a.json"), into, kinds, 3, take)
	_check((r["added"] as Array).size() == 1 and FileAccess.file_exists(into.path_join("demo_a.json")), "one dropped document is stored by id: %s" % str(r))
	r = DotMapDocDrop.accept(_abs("docs"), into, kinds, 3, take)
	_check((r["added"] as Array).size() == 2 and (r["errors"] as PackedStringArray).is_empty(), "a folder gives its documents, a deeper one included, the other kind left: %s" % str(r))
	_write_bytes(OUTSIDE.path_join("docs/sub/deeper/c.json"), '{"kind":"demo_map","id":"demo_c","name":"Demo C"}'.to_utf8_buffer())
	r = DotMapDocDrop.accept(_abs("docs"), into, kinds, 1, take)
	_check((r["added"] as Array).size() == 2, "depth 1 reaches sub/ and not deeper/: %s" % str(r["added"]))
	r = DotMapDocDrop.accept(_abs("onedoc.zip"), into, kinds, 3, take)
	_check((r["added"] as Array).size() == 1 and (r["errors"] as PackedStringArray).is_empty(), "a zip's documents are read in place: %s" % str(r))
	_check(not DirAccess.dir_exists_absolute(into.path_join("x")), "nothing is unpacked beside them")
	r = DotMapDocDrop.accept(_abs("docs.zip"), into, kinds, 3, take)
	_check((r["added"] as Array).size() == 2 and (r["errors"] as PackedStringArray).size() == 1 and (r["errors"] as PackedStringArray)[0].contains("unsafe path"), "an unsafe name in a zip is refused by name, the rest taken: %s" % str(r))
	r = DotMapDocDrop.accept(_abs("nodoc.zip"), into, kinds, 3, take)
	_check((r["added"] as Array).is_empty() and (r["errors"] as PackedStringArray).size() == 1 and (r["errors"] as PackedStringArray)[0] == "nodoc.zip: no map document in the zip", "a zip with no document of the kind says so: %s" % str(r))
	r = DotMapDocDrop.accept(_abs("notes.txt"), into, kinds, 3, take)
	_check(r.is_empty(), "a path holding none of the kind is not claimed (the intake refuses it)")
	r = DotMapDocDrop.accept(_abs("zipped.zip"), into, kinds, 3, take)
	_check((r["errors"] as PackedStringArray).size() == 1, "a zip of a converted mesh map is refused, not silently dropped")
	DotMapDocDrop.max_doc_bytes = 10
	r = DotMapDocDrop.accept(_abs("onedoc.zip"), into, kinds, 3, take)
	_check((r["added"] as Array).is_empty() and (r["errors"] as PackedStringArray)[0].contains("more than max_doc_bytes 10"), "a document over max_doc_bytes is refused, naming the setting: %s" % str(r))
	DotMapDocDrop.max_doc_bytes = 0
	r = DotMapDocDrop.accept(_abs("onedoc.zip"), into, kinds, 3, take)
	_check((r["added"] as Array).size() == 1, "max_doc_bytes 0 is no limit")
	DotMapDocDrop.max_doc_bytes = 16 * 1024 * 1024
	var bad := func(_d: Dictionary, _t: String, _n: String, _to: String) -> Dictionary: return {"error": "no spawns"}
	r = DotMapDocDrop.accept(_abs("docs/a.json"), into, kinds, 3, bad)
	_check((r["errors"] as PackedStringArray) == PackedStringArray(["a.json: no spawns"]), "the game's reason is kept with the file name")
	var lines := DotMapDocDrop.lines({"added": [{"title": "Demo A"}, {"name": "Demo B (local)"}], "errors": PackedStringArray(["x.json: no spawns"])}, "Press M.")
	_check(lines == PackedStringArray(["Added Demo A (local), Demo B (local). Press M.", "Not a map: x.json: no spawns"]), "lines: %s" % str(lines))
	var intake := _intake(false)
	intake.add_acceptor("a demo map .json, folder or zip", func(path: String, to: String) -> Dictionary: return DotMapDocDrop.accept(path, to, kinds, intake.search_depth, take))
	var h := intake.handle(PackedStringArray([_abs("onedoc.zip"), _abs("notes.txt")]))
	_check((h["added"] as Array).size() == 1 and (h["errors"] as PackedStringArray).size() == 1, "through the intake, a zip is added and a text file refused: %s" % str(h))
	intake.free()
	_done()


func _intake(converted: bool = true) -> DotMapDropIntake:
	_results.clear()
	var intake := DotMapDropIntake.new()
	intake.into = DROP
	if converted:
		intake.add_converted_maps()
	intake.handled.connect(_on_handled)
	add_child(intake)
	return intake


func _on_handled(result: Dictionary) -> void:
	_results.append(result)


func _abs(rel: String) -> String:
	return ProjectSettings.globalize_path(OUTSIDE.path_join(rel) if rel != "" else OUTSIDE).rstrip("/")


func _write_bytes(path: String, data: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("    cannot write %s" % path)
		return
	f.store_buffer(data)
	f.close()


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
