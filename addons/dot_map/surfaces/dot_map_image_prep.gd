class_name DotMapImagePrep
extends RefCounted
## Decoded texture images made ready for the GPU: channel slimming, half-size masks, size cap, mipmaps and VRAM compression. Split from [DotMapSurfaces], which owns what a surface kind is.

## Whether the part named [param part] (albedo, normal, roughness, ao) is kept at half size under the two options.
static func halves(part: String, masks: bool, normals: bool) -> bool:
	return (masks and part in ["roughness", "ao"]) or (normals and part == "normal")


## [param tex] cut to the next level of its own mip chain (a quarter of the memory) as a new texture; [param tex] itself when it has no level to spare or is under 8 px.
static func without_top_mip(tex: Texture2D) -> Texture2D:
	var img := tex.get_image() if tex != null else null
	if img == null or not img.has_mipmaps() or mini(img.get_width(), img.get_height()) < 8:
		return tex
	var half := Image.create_from_data(maxi(1, img.get_width() >> 1), maxi(1, img.get_height() >> 1), true, img.get_format(),
			img.get_data().slice(img.get_mipmap_offset(1)))
	return ImageTexture.create_from_image(half) if half != null else tex


## Slims, caps, mip-maps and VRAM-compresses a decoded file image: a raw 1k RGB map is 4 MB with mips, the compressed one 0.7 MB. Safe on a worker.
static func prepare_image(img: Image, path: String, max_size: int, half_masks: bool = false, mode_override: int = -1, half_normals: bool = false) -> void:
	if shrink_image(img, path, max_size, half_masks, half_normals):
		compress_image(img, mode_override)


## The part of [method prepare_image] that is safe on a pool worker: channels, size and mipmaps. False when [param img] is already compressed. Compression is separate because it runs its own pool group, and a group waited on from inside a pool task deadlocks.
static func shrink_image(img: Image, path: String, max_size: int, half_masks: bool = false, half_normals: bool = false) -> bool:
	if img.is_compressed():
		return false
	slim_image(img, path)
	if halves(path.get_file().get_basename(), half_masks, half_normals) and mini(img.get_width(), img.get_height()) >= 8:
		img.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_LANCZOS)
	while max_size > 0 and maxi(img.get_width(), img.get_height()) > max_size:
		img.resize(maxi(1, img.get_width() / 2), maxi(1, img.get_height() / 2), Image.INTERPOLATE_LANCZOS)
	img.generate_mipmaps()
	return true


## VRAM-compresses a [method shrink_image]d image for the build's format ([param mode_override] picks one); call it from the main thread, never from a pool task.
static func compress_image(img: Image, mode_override: int = -1) -> void:
	if OS.has_feature("web"):
		return    # the web template ships no BC/ETC compressor (_image_compress_bc_func is null): every call only logs an error, so keep the raw mipmapped image
	var mode := mode_override if mode_override >= 0 else (Image.COMPRESS_S3TC if OS.has_feature("s3tc") else (Image.COMPRESS_ETC2 if OS.has_feature("etc2") else -1))
	if mode < 0 or (mode_override < 0 and OS.get_environment("NOCOMP") != "") or img.is_compressed() or img.get_width() < 4 or img.get_height() < 4:
		return
	var channels := Image.USED_CHANNELS_RGBA
	if img.get_format() == Image.FORMAT_RGBA8 and img.detect_used_channels() == Image.USED_CHANNELS_RGB:
		channels = Image.USED_CHANNELS_RGB    # an opaque alpha channel doubles the compressed size for nothing
	match img.get_format():
		Image.FORMAT_R8:
			channels = Image.USED_CHANNELS_R
		Image.FORMAT_RG8:
			channels = Image.USED_CHANNELS_RG
		Image.FORMAT_RGB8:
			channels = Image.USED_CHANNELS_RGB
	img.compress_from_channels(mode as Image.CompressMode, channels)


## Drops the channels a set's [param path] part never samples: roughness and AO keep red, a normal map red and green
## (both shaders rebuild z). A raw 1k set decodes to 4 MB per map, and a big map draws hundreds of sets.
static func slim_image(img: Image, path: String) -> void:
	if img.is_compressed():
		return
	var part := path.get_file().get_basename()
	if part in ["roughness", "ao"] and img.get_format() != Image.FORMAT_R8:
		img.convert(Image.FORMAT_R8)
	elif part == "normal" and img.get_format() != Image.FORMAT_RG8:
		img.convert(Image.FORMAT_RG8)
