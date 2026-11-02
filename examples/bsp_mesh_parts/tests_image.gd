extends Node3D

## The counters and the prepare_image section of the bsp mesh suite.

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()
var _entered := 0
var _completed := 0


func _section(title: String) -> void:
	_entered += 1
	print("  " + title)


func _done() -> void:
	_completed += 1


func _check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		_failures.append(what)


func _filled(w: int, h: int, fmt: Image.Format, fn: Callable) -> Image:
	var img := Image.create(w, h, false, fmt)
	for y in h:
		for x in w:
			img.set_pixel(x, y, fn.call(x, y))
	return img


func _test_prepare_image() -> void:
	_section("prepare_image: the VRAM-compressed texture files read back as the raw ones did")
	var s3tc := OS.has_feature("s3tc")
	var packed := s3tc or OS.has_feature("etc2")
	var ramp := func(x: int, y: int) -> Color: return Color(x / 129.0, y / 69.0, 0.5)
	var albedo := _filled(130, 70, Image.FORMAT_RGB8, ramp)
	DotMapSurfaces.prepare_image(albedo, "res://x/albedo.jpg", 2048)
	_check(albedo.is_compressed() == packed and albedo.has_mipmaps(), "an odd-sized albedo is compressed with its mip chain: %s" % albedo.get_format())
	_check(not s3tc or albedo.get_format() == Image.FORMAT_DXT1, "an opaque albedo is DXT1, which has no alpha to lose")
	var back := albedo.duplicate() as Image
	if back.is_compressed():
		back.decompress()
	_check(absf(back.get_pixel(65, 35).r - 65 / 129.0) < 0.06 and absf(back.get_pixel(65, 35).g - 35 / 69.0) < 0.06, "its texels read back within block error: %s" % back.get_pixel(65, 35))
	var leaf := _filled(64, 64, Image.FORMAT_RGBA8, func(x: int, _y: int) -> Color: return Color(0.2, 0.6, 0.1, x / 63.0))
	DotMapSurfaces.prepare_image(leaf, "res://x/leaf.png", 2048)
	_check(not s3tc or leaf.get_format() == Image.FORMAT_DXT5, "an image with alpha is DXT5, never DXT1: %s" % leaf.get_format())
	if leaf.is_compressed():
		leaf.decompress()
	_check(leaf.get_pixel(1, 5).a < 0.15 and leaf.get_pixel(62, 5).a > 0.85, "the alpha ramp survives, so a cut-out still cuts: %s %s" % [leaf.get_pixel(1, 5).a, leaf.get_pixel(62, 5).a])
	var normal := _filled(64, 64, Image.FORMAT_RGB8, func(_x: int, _y: int) -> Color: return Color(0.65, 0.3, 1.0))
	DotMapSurfaces.prepare_image(normal, "res://x/normal.webp", 2048)
	_check(not s3tc or normal.get_format() == Image.FORMAT_RGTC_RG, "a normal map keeps two channels (the shaders rebuild z): %s" % normal.get_format())
	if normal.is_compressed():
		normal.decompress()
	_check(absf(normal.get_pixel(20, 20).r - 0.65) < 0.03 and absf(normal.get_pixel(20, 20).g - 0.3) < 0.03, "its x and y read back: %s" % normal.get_pixel(20, 20))
	var rough := _filled(64, 64, Image.FORMAT_RGB8, func(_x: int, _y: int) -> Color: return Color(0.25, 0.9, 0.9))
	DotMapSurfaces.prepare_image(rough, "res://x/roughness.webp", 2048)
	_check(not s3tc or rough.get_format() == Image.FORMAT_RGTC_R, "roughness is one channel: %s" % rough.get_format())
	if rough.is_compressed():
		rough.decompress()
	_check(absf(rough.get_pixel(30, 30).r - 0.25) < 0.02, "the red channel (what the shaders read) is the original's: %s" % rough.get_pixel(30, 30))
	var ao := _filled(64, 64, Image.FORMAT_L8, func(_x: int, _y: int) -> Color: return Color(0.5, 0.5, 0.5))
	DotMapSurfaces.prepare_image(ao, "res://x/ao.png", 2048)
	if ao.is_compressed():
		ao.decompress()
	_check(absf(ao.get_pixel(3, 3).r - 0.5) < 0.02, "a greyscale ao file keeps its value in red: %s" % ao.get_pixel(3, 3))
	var big := _filled(512, 256, Image.FORMAT_RGB8, ramp)
	DotMapSurfaces.prepare_image(big, "res://x/albedo.jpg", 128)
	_check(big.get_width() == 128 and big.get_height() == 64, "a file past the cap is halved to fit: %sx%s" % [big.get_width(), big.get_height()])
	var kept := _filled(512, 256, Image.FORMAT_RGB8, ramp)
	DotMapSurfaces.prepare_image(kept, "res://x/albedo.jpg", 0)
	_check(kept.get_width() == 512, "a cap of 0 keeps the size")
	var fmt := albedo.get_format()
	var again := _filled(16, 16, Image.FORMAT_RGB8, ramp)
	DotMapSurfaces.prepare_image(again, "res://x/albedo.jpg", 2048)
	var f1 := again.get_format()
	DotMapSurfaces.prepare_image(again, "res://x/albedo.jpg", 2048)
	_check(again.get_format() == f1 and fmt == f1, "an already-compressed image is left alone")
	var tiny := _filled(2, 2, Image.FORMAT_RGB8, ramp)
	DotMapSurfaces.prepare_image(tiny, "res://x/albedo.jpg", 2048)
	_check(not tiny.is_compressed(), "an image under one block stays raw")
	var t := ImageTexture.create_from_image(_filled(16, 16, Image.FORMAT_RGB8, ramp))
	_check(DotMapSurfaces.texture_report({"a": t}).size() == 1, "texture_report counts a texture by format")
	var opaque := _filled(64, 64, Image.FORMAT_RGBA8, func(x: int, _y: int) -> Color: return Color(0.2, 0.6, x / 63.0, 1.0))
	DotMapSurfaces.prepare_image(opaque, "res://x/albedo.png", 2048)
	_check(not s3tc or opaque.get_format() == Image.FORMAT_DXT1, "an RGBA image whose alpha is all opaque is DXT1, not DXT5: %s" % opaque.get_format())
	var src := _filled(64, 32, Image.FORMAT_RGB8, ramp)
	src.generate_mipmaps()
	var half := DotMapSurfaces.without_top_mip(ImageTexture.create_from_image(src)).get_image()
	_check(half.get_width() == 32 and half.get_height() == 16 and half.has_mipmaps(), "without_top_mip halves the size and keeps the rest of the chain: %sx%s" % [half.get_width(), half.get_height()])
	_check(half.get_data() == src.get_data().slice(src.get_mipmap_offset(1)), "its bytes are the source's mip 1, nothing re-encoded")
	var flat := ImageTexture.create_from_image(_filled(64, 32, Image.FORMAT_RGB8, ramp))
	_check(DotMapSurfaces.without_top_mip(flat) == flat, "a texture without mips is returned unchanged")
	var masks := DotMapSurfaces.new()
	masks.half_res_masks = true
	var mip_tex := ImageTexture.create_from_image(src)
	_check(masks._masked("res://x/albedo.webp", mip_tex) == mip_tex and masks._masked("res://x/roughness.webp", mip_tex) != mip_tex, "only roughness and ao lose their top mip")
	_done()
