class_name DotMapTextureBake
extends RefCounted
## Bakes a texture file into what [DotMapSurfaces] would build from it at load, so a client skips the decode, the cap and the compression.
##
## `<name>.s3tc.res` (desktop) and `<name>.etc2.res` (web and phones) are [ImageTexture]s of the capped, slimmed, mip-mapped, VRAM-compressed image: loading one is a read and an upload (0.2 ms, against 11 to 14 ms to decode a 1k webp and 3 ms more to compress it). [DotMapSurfaces] reads them from beside the source file. Never bake on the target: the files are engine-version specific, like an import.

## Metadata key holding the source size, md5, dimensions and the bake cap.
const META := &"dot_bake"

const VARIANTS := {"s3tc": Image.COMPRESS_S3TC, "etc2": Image.COMPRESS_ETC2}


## Bakes [param src] into [param out_base] + ".<variant>.res" for both variants, capped to [param max_size] (0 for no cap). The files written, or an error for a file that does not decode or is under 4 px (never compressed, so the runtime keeps decoding it).
static func bake_file(src: String, out_base: String, max_size: int) -> DotResult:
	var first := Image.load_from_file(src)
	if first == null:
		return DotResult.fail(DotError.CODE_IO, "cannot decode %s" % src)
	if first.get_width() < 4 or first.get_height() < 4:
		return DotResult.fail(DotError.CODE_INVALID, "%s is under 4 px" % src)
	DirAccess.make_dir_recursive_absolute(out_base.get_base_dir())
	var written := PackedStringArray()
	for variant: String in VARIANTS:
		var img := first.duplicate() as Image
		DotMapSurfaces.prepare_image(img, src, max_size, false, VARIANTS[variant])
		var out := "%s.%s.res" % [out_base, variant]
		var tex := ImageTexture.create_from_image(img)
		tex.set_meta(META, {"size": _length(src), "md5": FileAccess.get_md5(src), "w": first.get_width(), "h": first.get_height(), "max": max_size})
		if ResourceSaver.save(tex, out) != OK:
			return DotResult.fail(DotError.CODE_IO, "cannot write %s" % out)
		written.append(out)
	return DotResult.success(written)


## Every `albedo`, `normal`, `roughness` and `ao` file under [param store] (a PBR library: `<id>/<tier>/<part>.webp|jpg`), baked beside itself, or into the same layout under [param out_dir] when it is not empty. Returns `{baked, failed, skipped, ms}`.
static func bake_store(store: String, out_dir: String = "", max_size: int = 2048) -> Dictionary:
	var started := Time.get_ticks_msec()
	var stats := {"baked": 0, "failed": 0, "skipped": 0, "ms": 0}
	for f in _files(store):
		var rel := f.trim_prefix(store).trim_prefix("/")
		var base := (out_dir.path_join(rel) if not out_dir.is_empty() else f).get_basename()
		if is_current(base, f, max_size):
			stats["skipped"] += 1
			continue
		var res := bake_file(f, base, max_size)
		stats["baked" if res.ok else "failed"] += 1
	stats["ms"] = Time.get_ticks_msec() - started
	return stats


## True when every variant exists beside [param out_base] and was baked from the current bytes of [param src] at [param max_size].
static func is_current(out_base: String, src: String, max_size: int) -> bool:
	var md5 := ""
	for variant: String in VARIANTS:
		var p := "%s.%s.res" % [out_base, variant]
		if not FileAccess.file_exists(p):
			return false
		var tex := ResourceLoader.load(p, "ImageTexture", ResourceLoader.CACHE_MODE_IGNORE) as Texture2D
		var meta: Dictionary = tex.get_meta(META, {}) if tex != null else {}
		if meta.is_empty() or int(meta["max"]) != max_size or int(meta["size"]) != _length(src):
			return false
		if md5.is_empty():
			md5 = FileAccess.get_md5(src)
		if meta["md5"] != md5:
			return false
	return true


## True when [param tex] (a baked file) is the right one for [param src] under [param cap] (0: none): baked from a file of this size, and neither smaller than the cap asks for nor larger. No source beside it means the bake is all there is.
static func fits(tex: Texture2D, src: String, cap: int) -> bool:
	var meta: Dictionary = tex.get_meta(META, {})
	if meta.is_empty():
		return false
	if not FileAccess.file_exists(src):
		return true
	if int(meta["size"]) != _length(src):
		return false
	var w := int(meta["w"])
	var h := int(meta["h"])
	while cap > 0 and maxi(w, h) > cap:
		w = maxi(1, w / 2)
		h = maxi(1, h / 2)
	var want := maxi(w, h)
	return maxi(tex.get_width(), tex.get_height()) == want


static func _length(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_length() if f != null else -1


static func _files(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for sub in DirAccess.get_directories_at(dir):
		out.append_array(_files(dir.path_join(sub)))
	for f in DirAccess.get_files_at(dir):
		if f.get_extension() in ["webp", "jpg"] and f.get_basename() in ["albedo", "normal", "roughness", "ao"]:
			out.append(dir.path_join(f))
	return out
