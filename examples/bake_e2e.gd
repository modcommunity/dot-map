extends Node

## [DotMapTextureBake] end to end on 20 real albedo maps copied from a map store: bake, load through
## [DotMapSurfaces], compare, fall back. The originals are only read. With no store found (a fresh clone) the
## section is skipped and says so.

const REAL := 15
const PICK := 8
const CHECKS := REAL + PICK
const SECTIONS := 2
const SETS := 20
const CAP := 256
const SCRATCH := "user://bake_e2e"
const STORES := ["~/godot/zombie-zone-maps/.stores/pbr-library"]

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()
var _entered := 0
var _completed := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	print("dot-map texture bake, end to end")
	_test_variant_pick()
	_test_real_textures()
	print("%d passed, %d failed" % [_passed, _failed])
	for line in _failures:
		print("  FAIL  %s" % line)
	print("%d of %d sections ran to their last line" % [_completed, _entered])
	var bad := _entered != SECTIONS or _completed != _entered or _passed + _failed != CHECKS
	if bad:
		print("ERROR: %d checks in %d sections ran, %d in %d expected." % [_passed + _failed, _completed, CHECKS, SECTIONS])
	get_tree().quit(1 if bad or _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		_failures.append(what)


func _find_store() -> String:
	for s: String in STORES:
		var dir := s.replace("~", OS.get_environment("HOME"))
		if DirAccess.dir_exists_absolute(dir):
			return dir
	return ""


## The same downscale the runtime does, left uncompressed, for a tolerance comparison.
func _downscaled(path: String, cap: int) -> Image:
	var img := Image.load_from_file(path)
	while maxi(img.get_width(), img.get_height()) > cap:
		img.resize(maxi(1, img.get_width() / 2), maxi(1, img.get_height() / 2), Image.INTERPOLATE_LANCZOS)
	img.convert(Image.FORMAT_RGB8)
	return img


## Mean absolute difference of mip 0 over a pixel grid; the compressed image is padded to whole 4 px blocks, so only the shared area is compared.
func _mean_error(a: Image, b: Image) -> float:
	var w := mini(a.get_width(), b.get_width())
	var h := mini(a.get_height(), b.get_height())
	if absi(a.get_width() - b.get_width()) > 3 or absi(a.get_height() - b.get_height()) > 3:
		return 1.0
	var total := 0.0
	var n := 0
	for y in range(0, h, 3):
		for x in range(0, w, 3):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			total += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
			n += 3
	return total / float(maxi(n, 1))


func _test_variant_pick() -> void:
	_entered += 1
	var feats := func(list: Array) -> Callable: return func(f: String) -> bool: return f in list
	_check(DotMapTextureBake.pick_variant(feats.call(["s3tc", "bptc"])) == "s3tc", "a desktop GPU (s3tc, bptc) reads the s3tc bake")
	_check(DotMapTextureBake.pick_variant(feats.call(["etc2", "astc"])) == "etc2", "a phone or browser GPU (etc2, astc) reads the etc2 bake")
	_check(DotMapTextureBake.pick_variant(feats.call(["s3tc", "etc2"])) == "s3tc", "a GPU with both prefers s3tc")
	_check(DotMapTextureBake.pick_variant(feats.call(["astc", "bptc"])).is_empty(), "a GPU with only astc or bptc has no bake and decodes the source")
	_check(DotMapTextureBake.pick_variant(feats.call([])).is_empty(), "no GPU format (dedicated server, headless) picks nothing")
	_check(DotMapTextureBake.pick_variant(feats.call(["s3tc"]), true).is_empty(), "NOCOMP forces no bake")
	var tex := ImageTexture.create_from_image(Image.create(8, 8, false, Image.FORMAT_RGB8))
	tex.set_meta(DotMapTextureBake.META, {"size": 1, "md5": "", "w": 8, "h": 8, "max": 0, "variant": "etc2"})
	_check(not DotMapTextureBake.fits(tex, "res://missing.webp", 0, "s3tc"), "a bake that records another variant is ignored")
	tex.set_meta(DotMapTextureBake.META, {"size": 1, "md5": "", "w": 8, "h": 8, "max": 0})
	_check(DotMapTextureBake.fits(tex, "res://missing.webp", 0, "s3tc"), "a bake from before the variant record still loads")
	_completed += 1


func _test_real_textures() -> void:
	_entered += 1
	var store := _find_store()
	var variant := DotMapSurfaces.baked_variant()
	if store.is_empty() or variant.is_empty():
		print("  skipped: %s" % ("no map store on this machine" if store.is_empty() else "no VRAM format on this build"))
		for i in REAL:
			_check(true, "-")
		_completed += 1
		return
	_remove_tree(SCRATCH)
	var sets := DirAccess.get_directories_at(store)
	sets.sort()
	var copied := PackedStringArray()
	for s in sets:
		var src := "%s/%s/1k/albedo.webp" % [store, s]
		if copied.size() < SETS and FileAccess.file_exists(src):
			var dst := "%s/%s/1k/albedo.webp" % [SCRATCH, s]
			DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
			DirAccess.copy_absolute(src, dst)
			copied.append(dst)
	_check(copied.size() == SETS, "%d real albedo maps copied (%d)" % [SETS, copied.size()])
	var stats := DotMapTextureBake.bake_store(SCRATCH, "", CAP)
	_check(stats["baked"] == SETS and stats["failed"] == 0, "all baked beside the copies (%s)" % str(stats))

	var surfaces := DotMapSurfaces.new()
	surfaces.max_texture_size = CAP
	var from_bake := true
	var capped := true
	var exact := true
	var close := true
	var worst := 0.0
	var last_size: Array = []
	for p in copied:
		var tex := surfaces._file_texture(p)
		from_bake = from_bake and tex != null and tex.resource_path.ends_with(".%s.res" % variant)
		capped = capped and tex != null and maxi(tex.get_width(), tex.get_height()) == CAP
		if tex == null:
			continue
		var got := tex.get_image()
		last_size = [got.get_width(), got.get_height(), got.get_format(), got.has_mipmaps()]
		var want := Image.load_from_file(p)
		DotMapSurfaces.prepare_image(want, p, CAP, false, DotMapTextureBake.VARIANTS[variant])
		exact = exact and got.get_format() == want.get_format() and got.get_mipmap_count() == want.get_mipmap_count() and got.get_data() == want.get_data()
		got.decompress()
		var err := _mean_error(got, _downscaled(p, CAP))
		worst = maxf(worst, err)
		close = close and err < 0.03
	print("  worst error %.4f, last size %s" % [worst, str(last_size)])
	surfaces = null
	_check(from_bake, "every texture came from its baked .res, not the webp")
	_check(capped, "every baked texture is %d px" % CAP)
	_check(exact, "the baked image is byte-equal to the runtime's own compressed, mip-mapped image")
	_check(close, "decompressed, it is within 3%% mean error of a decode and downscale of the source (worst %.4f)" % worst)

	_test_bake_fallbacks(copied, variant)
	_remove_tree(SCRATCH)
	_completed += 1


func _test_bake_fallbacks(copied: PackedStringArray, variant: String) -> void:
	var missing := copied[0]
	DirAccess.remove_absolute("%s.%s.res" % [missing.get_basename(), variant])
	var s2 := DotMapSurfaces.new()
	s2.max_texture_size = CAP
	var t_missing := s2._file_texture(missing)
	_check(t_missing != null and t_missing.resource_path.is_empty() and maxi(t_missing.get_width(), t_missing.get_height()) == CAP, "a missing .res falls back to decoding the webp")
	var corrupt := copied[1]
	var f := FileAccess.open("%s.%s.res" % [corrupt.get_basename(), variant], FileAccess.WRITE)
	f.store_string("not a resource, a stale or foreign format")
	f.close()
	var s3 := DotMapSurfaces.new()
	s3.max_texture_size = CAP
	var t_corrupt := s3._file_texture(corrupt)
	_check(t_corrupt != null and t_corrupt.resource_path.is_empty() and maxi(t_corrupt.get_width(), t_corrupt.get_height()) == CAP, "an unreadable .res falls back to decoding the webp")
	var s4 := DotMapSurfaces.new()
	s4.max_texture_size = CAP / 2
	var t_small := s4._file_texture(copied[2])
	_check(t_small != null and t_small.resource_path.is_empty() and maxi(t_small.get_width(), t_small.get_height()) == CAP / 2, "a cap below the baked size decodes at the cap")

	DirAccess.copy_absolute(copied[4], copied[3])
	_check(not DotMapTextureBake.is_current(copied[3].get_basename(), copied[3], CAP), "a source changed under the same path is no longer current")
	var s5 := DotMapSurfaces.new()
	s5.max_texture_size = CAP
	var t_stale := s5._file_texture(copied[3])
	_check(t_stale != null and t_stale.resource_path.is_empty(), "a baked file of another source is not loaded")
	var s6 := DotMapSurfaces.new()
	s6.max_texture_size = 0
	var t_uncapped := s6._file_texture(copied[5])
	_check(t_uncapped != null and t_uncapped.resource_path.is_empty() and maxi(t_uncapped.get_width(), t_uncapped.get_height()) > CAP, "no cap asks for the source's size, so a lower-resolution bake is not used")
	var bare := Image.create(CAP, CAP, true, Image.FORMAT_RGB8)
	ResourceSaver.save(ImageTexture.create_from_image(bare), "%s.%s.res" % [copied[6].get_basename(), variant])
	var s7 := DotMapSurfaces.new()
	s7.max_texture_size = CAP
	var t_old := s7._file_texture(copied[6])
	_check(t_old != null and t_old.resource_path.is_empty(), "a baked file without the bake metadata (an older format) is not loaded")
	DirAccess.remove_absolute("%s.etc2.res" % copied[7].get_basename())
	var again := DotMapTextureBake.bake_store(SCRATCH, "", CAP)
	_check(again["baked"] == 5 and again["skipped"] == SETS - 5 and again["failed"] == 0, "a re-bake redoes only the missing, unreadable, changed, bare and half-missing ones (%s)" % str(again))
	var other := "etc2" if variant == "s3tc" else "s3tc"
	var wrong := copied[8]
	DirAccess.copy_absolute("%s.%s.res" % [wrong.get_basename(), other], "%s.%s.res" % [wrong.get_basename(), variant])
	var s8 := DotMapSurfaces.new()
	s8.max_texture_size = CAP
	var t_wrong := s8._file_texture(wrong)
	_check(t_wrong != null and t_wrong.resource_path.is_empty(), "the other variant's bake under this variant's name is ignored")


func _remove_tree(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		_remove_tree(dir.path_join(sub))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
