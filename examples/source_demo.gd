extends "suite_base.gd"

## DotMapVpk, DotMapVtf and DotMapVpkWriter on made-up archives (headless): VPK v1 and v2, preload bytes, files in the
## dir and in a part, the extension filter, case, CRC, and every refusal; VTF formats, mip choice, KeyValues and the
## converter's material names. `-- --vpk=<a *_dir.vpk>` adds the real-archive section: tree parse and read timings,
## and every VTF of the first N (`--sample=`, default 200) decoded. Nothing of Valve's is in this repository.

const ROOT := "user://source_demo"

var _real := ""
var _sample := 200


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--vpk="):
			_real = arg.trim_prefix("--vpk=")
		elif arg.begins_with("--sample="):
			_sample = int(arg.trim_prefix("--sample="))
	_run.call_deferred()


func _run() -> void:
	print("dot-map source (VPK, VTF)")
	_wipe(ROOT)
	var sections := 4
	var checks := 47
	_test_crc()
	_test_vpk()
	_test_vtf()
	_test_text()
	if _real != "":
		sections += 1
		checks += 4
		_test_real()
	_wipe(ROOT)
	_finish(checks, sections)


func _test_crc() -> void:
	_section("crc32 is zlib's, at every length around the 8-byte step")
	_c(DotMapVpk.crc32("123456789".to_ascii_buffer()) == 0xCBF43926, "the check value of '123456789'")
	_c(DotMapVpk.crc32(PackedByteArray()) == 0, "empty is 0")
	var ok := true
	for n in [1, 7, 8, 9, 15, 16, 17, 100, 1000]:
		var data := PackedByteArray()
		for i in n:
			data.append((i * 37 + 11) & 0xFF)
		# The same bytes through gzip, whose trailer holds zlib's CRC-32 and the length.
		var gz := data.compress(FileAccess.COMPRESSION_GZIP)
		ok = ok and DotMapVpk.crc32(data) == gz.decode_u32(gz.size() - 8)
	_c(ok, "it equals the CRC-32 gzip stores, for 1 to 1000 bytes")
	_done()


func _test_vpk() -> void:
	_section("vpk: v2 and v1, preload, dir and part, filter, refusals")
	var green := DotMapVpkWriter.vtf_rgba(4, 4, 3, Color8(20, 200, 30), Color8(0, 0, 255))
	var red := DotMapVpkWriter.vtf_dxt1(8, 8, 0xF800)
	var vmt := "\"LightmappedGeneric\" { \"$basetexture\" \"metal/wall\" }".to_utf8_buffer()
	var files := {
		"materials/metal/wall.vmt": [vmt, -1, 0],
		"materials/Metal/Wall.vtf": [green, 0, 0],
		"materials/metal/red.vtf": [red, 0, 20],
		"materials/root.txt": [PackedByteArray([1, 2, 3]), 0, 0],
	}
	for version in [1, 2]:
		var base := ROOT.path_join("v%d/game_textures" % version)
		_c(DotMapVpkWriter.write_vpk(base, files, version) == OK, "v%d writes" % version)
		var vpk := DotMapVpk.new()
		_c(vpk.open(base + "_dir.vpk") and vpk.entries.size() == 4, "v%d opens and lists its 4 files" % version, str(vpk.entries.keys()) + vpk.error)
		_c(vpk.has("MATERIALS/METAL/RED.VTF") and vpk.read("materials/metal/wall.vmt") == vmt, "v%d is case-blind, a dir file reads" % version)
		_c(vpk.read("materials/metal/red.vtf") == red, "v%d: preload bytes and the part body join" % version)
		_c(vpk.read("materials/metal/wall.vtf") == green, "v%d: a part file reads" % version)
	var only := DotMapVpk.new()
	_c(only.open(ROOT.path_join("v2/game_textures_dir.vpk"), PackedStringArray(["vtf"])) and only.entries.size() == 2,
		"only_ext keeps the vtf files and nothing else", str(only.entries.keys()))
	_c(only.read("materials/metal/wall.vmt").is_empty() and only.error.begins_with("not in "), "and a file it dropped is absent, said so", only.error)

	var vpk2 := DotMapVpk.new()
	vpk2.open(ROOT.path_join("v2/game_textures_dir.vpk"))
	vpk2.verify_crc = false
	_c(vpk2.read("materials/metal/wall.vtf") == green, "verify_crc off still reads")

	DotMapVpkWriter.write_vpk(ROOT.path_join("bad/crc"), {"materials/x.vtf": [red, 0, 0]}, 2, true)
	var bad := DotMapVpk.new()
	_c(bad.open(ROOT.path_join("bad/crc_dir.vpk")) and bad.read("materials/x.vtf").is_empty() and bad.error.begins_with("crc mismatch"),
		"a file that fails its CRC is not read", bad.error)
	bad.verify_crc = false
	_c(bad.read("materials/x.vtf") == red, "unless the caller turned the check off")

	DotMapVpkWriter.write_vpk(ROOT.path_join("bad/nopart"), {"materials/x.vtf": [red, 0, 0], "materials/y.vmt": [vmt, -1, 0]}, 2, false, true)
	var nopart := DotMapVpk.new()
	_c(nopart.open(ROOT.path_join("bad/nopart_dir.vpk")) and nopart.read("materials/x.vtf").is_empty() and nopart.error.begins_with("cannot open "),
		"a missing part is an error naming it, not a silent empty file", nopart.error)
	_c(nopart.read("materials/y.vmt") == vmt, "while a file in the dir still reads")

	var bytes := FileAccess.get_file_as_bytes(ROOT.path_join("v2/game_textures_dir.vpk"))
	var cut := ROOT.path_join("bad/cut_dir.vpk")
	_write_bytes(cut, bytes.slice(0, 60))
	var cv := DotMapVpk.new()
	_c(not cv.open(cut) and cv.error.begins_with("truncated tree") and cv.entries.is_empty(), "a cut-short tree is refused", cv.error)
	var wrong := bytes.duplicate()
	wrong.encode_u32(0, 0x12345678)
	_write_bytes(ROOT.path_join("bad/sig_dir.vpk"), wrong)
	_c(not cv.open(ROOT.path_join("bad/sig_dir.vpk")) and cv.error.begins_with("not a VPK v1/v2"), "a wrong signature is refused", cv.error)
	wrong = bytes.duplicate()
	wrong.encode_u32(4, 3)
	_write_bytes(ROOT.path_join("bad/ver_dir.vpk"), wrong)
	_c(not cv.open(ROOT.path_join("bad/ver_dir.vpk")) and cv.error.begins_with("not a VPK v1/v2"), "version 3 is refused", cv.error)
	_c(not cv.open(ROOT.path_join("v2/game_textures_000.vpk")) and cv.error.begins_with("not a *_dir.vpk"), "a part is not a directory", cv.error)
	_c(not cv.open(ROOT.path_join("none_dir.vpk")) and cv.error.begins_with("cannot open"), "a missing file is refused", cv.error)
	_c(not cv.open(ROOT.path_join("bad/sig_dir.vpk"), PackedStringArray(["vtf"])) and cv.entries.is_empty(), "a refusal leaves no entries")
	_done()


func _test_vtf() -> void:
	_section("vtf: formats, mip choice, refusals")
	var green := DotMapVpkWriter.vtf_rgba(4, 4, 3, Color8(20, 200, 30), Color8(0, 0, 255))
	var img := DotMapVtf.image(green)
	_c(img != null and img.get_size() == Vector2i(4, 4) and img.get_pixel(3, 3).to_rgba32() == Color8(20, 200, 30).to_rgba32(),
		"RGBA8888 reads its largest mip", DotMapVtf.error)
	img = DotMapVtf.image(green, 2)
	_c(img != null and img.get_size() == Vector2i(2, 2) and img.get_pixel(0, 0).to_rgba32() == Color8(0, 0, 255).to_rgba32(),
		"a smaller mip when the largest is over max_side", DotMapVtf.error)
	img = DotMapVtf.image(green, 1)
	_c(img != null and img.get_size() == Vector2i(1, 1), "down to the 1x1", DotMapVtf.error)
	img = DotMapVtf.image(DotMapVpkWriter.vtf_dxt1(8, 8, 0xF800))
	_c(img != null and img.get_size() == Vector2i(8, 8) and img.get_pixel(5, 6).r > 0.95 and img.get_pixel(5, 6).g < 0.05,
		"DXT1 decodes", DotMapVtf.error)
	img = DotMapVtf.image(DotMapVpkWriter.vtf_flat(2, 2, 12, PackedByteArray([30, 20, 10, 200])))
	_c(img != null and img.get_pixel(1, 1).to_rgba32() == Color8(10, 20, 30, 200).to_rgba32(), "BGRA8888 swaps to RGBA", DotMapVtf.error)
	img = DotMapVtf.image(DotMapVpkWriter.vtf_flat(2, 2, 3, PackedByteArray([30, 20, 10])))
	_c(img != null and img.get_pixel(0, 1).to_rgba32() == Color8(10, 20, 30, 255).to_rgba32(), "BGR888 swaps and is opaque", DotMapVtf.error)
	img = DotMapVtf.image(DotMapVpkWriter.vtf_flat(2, 2, 1, PackedByteArray([200, 30, 20, 10])))
	_c(img != null and img.get_pixel(0, 0).to_rgba32() == Color8(10, 20, 30, 200).to_rgba32(), "ABGR8888 swaps to RGBA", DotMapVtf.error)
	img = DotMapVtf.image(DotMapVpkWriter.vtf_flat(2, 2, 5, PackedByteArray([128])))
	_c(img != null and absf(img.get_pixel(1, 0).r - 128.0 / 255.0) < 0.01, "L8 is grey", DotMapVtf.error)
	_c(DotMapVtf.image(PackedByteArray([1, 2, 3])) == null and DotMapVtf.error == "not a vtf", "bytes that are not a vtf are refused")
	_c(DotMapVtf.image(DotMapVpkWriter.vtf_head(4, 4, 99, 1)) == null and DotMapVtf.error == "vtf format 99", "an unread format is named", DotMapVtf.error)
	var short := DotMapVpkWriter.vtf_rgba(4, 4, 1, Color.RED, Color.RED).slice(0, 100)
	_c(DotMapVtf.image(short) == null and DotMapVtf.error == "vtf cut short", "a cut-short body is refused", DotMapVtf.error)
	_c(DotMapVtf.size_of(13, 8, 8) == 32 and DotMapVtf.size_of(15, 1, 1) == 16 and DotMapVtf.size_of(12, 3, 2) == 24, "size_of: blocks and pixels")
	_done()


func _test_text() -> void:
	_section("vmt keys and the converter's material names")
	var keys := DotMapVtf.vmt_keys("\"LightmappedGeneric\"\n{\n\t\"$baseTexture\" \"Concrete/Floor\" // a comment\n\t$surfaceprop concrete\n}")
	_c(keys.get("$basetexture") == "Concrete/Floor" and keys.get("$surfaceprop") == "concrete", "keys at depth, quotes and comments handled", str(keys))
	keys = DotMapVtf.vmt_keys("patch { include \"materials/a/b.vmt\" insert { $x 1 } }")
	_c(keys.get("include") == "materials/a/b.vmt", "a one-line patch block", str(keys))
	_c(DotMapVtf.vmt_keys("a 1\na 2").get("a") == "1", "the first of a repeated key wins")
	_c(DotMapVtf.vmt_keys("\"a\" \"http://x\"").get("a") == "http://x", "// inside quotes is not a comment")
	_c(DotMapVtf.clean_material("\\Maps\\cp_x\\Concrete\\Floor001_12_-3_40") == "concrete/floor001", "a cubemap-patched name is its base",
		DotMapVtf.clean_material("\\Maps\\cp_x\\Concrete\\Floor001_12_-3_40"))
	_c(DotMapVtf.clean_material("/Brick/Wall") == "brick/wall", "lower case, no leading slash")
	_c(DotMapVtf.safe_name("Brick/Wall 01") == "brick_wall_01", "safe_name is the _orig pack's file name", DotMapVtf.safe_name("Brick/Wall 01"))
	_c(DotMapVtf.safe_name("///") == "unnamed", "and an empty one is unnamed")
	_c(DotMapVtf.safe_name("a".repeat(200)).length() == 80, "and at most 80 characters")
	_done()


func _test_real() -> void:
	_section("real archive %s" % _real)
	var t := Time.get_ticks_usec()
	var vpk := DotMapVpk.new()
	var opened := vpk.open(_real, PackedStringArray(["vmt", "vtf"]))
	_c(opened and not vpk.entries.is_empty(), "the tree parses", vpk.error)
	print("   %d entries in %.1f ms" % [vpk.entries.size(), (Time.get_ticks_usec() - t) / 1000.0])
	var read := 0
	var decoded := 0
	var bytes := 0
	var read_us := 0
	var decode_us := 0
	var failed := PackedStringArray()
	for path: String in vpk.entries:
		if not path.ends_with(".vtf") or read >= _sample:
			continue
		t = Time.get_ticks_usec()
		var data := vpk.read(path)
		read_us += Time.get_ticks_usec() - t
		if data.is_empty():
			failed.append("%s: %s" % [path, vpk.error])
			continue
		read += 1
		bytes += data.size()
		t = Time.get_ticks_usec()
		var img := DotMapVtf.image(data, 512)
		decode_us += Time.get_ticks_usec() - t
		if img != null:
			decoded += 1
		elif not DotMapVtf.error.begins_with("vtf format") and not DotMapVtf.error.begins_with("vtf thumbnail"):
			failed.append("%s: %s" % [path, DotMapVtf.error])
	_c(failed.is_empty(), "every sampled vtf reads with a good CRC and decodes or is an unread format", ", ".join(failed.slice(0, 3)))
	_c(read > 0 and decoded > 0, "some were read and some decoded", "%d read, %d decoded" % [read, decoded])
	_c(vpk.has(vpk.entries.keys()[0]), "has() on a listed path")
	print("   %d vtf read and CRC-checked (%.1f MB) in %.1f ms, %d decoded in %.1f ms" % [read, bytes / 1048576.0, read_us / 1000.0, decoded, decode_us / 1000.0])
	_done()


## [method _check] with the detail that explains a failure.
func _c(ok: bool, what: String, detail := "") -> void:
	_check(ok, what if ok or detail == "" else "%s: %s" % [what, detail])


func _write_bytes(path: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()


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
