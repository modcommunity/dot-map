class_name DotMapTextureBake
extends RefCounted
## Bakes a texture file into what [DotMapSurfaces] would build from it at load, so a client skips the decode, the cap and the compression.
##
## `<name>.s3tc.res` (desktop) and `<name>.etc2.res` (web and phones) are [ImageTexture]s of the capped, slimmed, mip-mapped, VRAM-compressed image: loading one is a read and an upload (0.2 ms, against 11 to 14 ms to decode a 1k webp and 3 ms more to compress it). [DotMapSurfaces] reads them from beside the source file. Never bake on the target: the files are engine-version specific, like an import.

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
		if ResourceSaver.save(ImageTexture.create_from_image(img), out) != OK:
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
		if FileAccess.file_exists(base + ".s3tc.res") and FileAccess.file_exists(base + ".etc2.res") and FileAccess.get_modified_time(base + ".s3tc.res") >= FileAccess.get_modified_time(f):
			stats["skipped"] += 1
			continue
		var res := bake_file(f, base, max_size)
		stats["baked" if res.ok else "failed"] += 1
	stats["ms"] = Time.get_ticks_msec() - started
	return stats


static func _files(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for sub in DirAccess.get_directories_at(dir):
		out.append_array(_files(dir.path_join(sub)))
	for f in DirAccess.get_files_at(dir):
		if f.get_extension() in ["webp", "jpg"] and f.get_basename() in ["albedo", "normal", "roughness", "ao"]:
			out.append(dir.path_join(f))
	return out
