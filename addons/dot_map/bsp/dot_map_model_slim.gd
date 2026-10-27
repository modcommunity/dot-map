class_name DotMapModelSlim
extends RefCounted

## Shrinks the textures of a library glTF after GLTFDocument has decoded them as RGBA8 with mipmaps: normal maps to two
## channels, unused alpha dropped, then GPU-compressed where the platform has a format. Identical images are shared.

const CHANNEL := "dot_map.model_slim"

## Off leaves a model exactly as GLTFDocument made it.
static var enabled: bool = true
## Longest texture side kept, 0 for no cap. A cap halves a larger image until it fits, so it is a visible loss; a game's cvar sets it.
static var max_texture_size: int = 0

## Images already slimmed, by content: key to WeakRef of the Texture2D, so a freed map frees its textures.
static var _shared: Dictionary = {}
## Textures seen / replaced and their CPU-side bytes before and after, since [method reset_stats].
static var stats := {"textures": 0, "shared": 0, "bytes_before": 0, "bytes_after": 0}


## Sets [member max_texture_size] for a caller that reaches this script by path.
static func set_max_texture_size(value: int) -> void:
	max_texture_size = maxi(value, 0)


static func reset_stats() -> void:
	stats = {"textures": 0, "shared": 0, "bytes_before": 0, "bytes_after": 0}


## The compressed format this platform can upload, or -1 for none (the browser has neither): the image then only changes channels.
static func compression() -> int:
	if OS.has_feature("s3tc"):
		return Image.COMPRESS_S3TC
	if OS.has_feature("etc2"):
		return Image.COMPRESS_ETC2
	return -1


## Replaces the textures of every material under [param root] with slim ones.
static func slim_model(root: Node) -> void:
	if not enabled or root == null:
		return
	var seen := {}
	var nodes: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	for n in nodes:
		var mesh := (n as MeshInstance3D).mesh
		if mesh == null or seen.has(mesh):
			continue
		seen[mesh] = true
		for s in mesh.get_surface_count():
			var mat := mesh.surface_get_material(s) as BaseMaterial3D
			if mat != null and not seen.has(mat):
				seen[mat] = true
				slim_material(mat)


## Slims each texture slot of one material.
static func slim_material(mat: BaseMaterial3D) -> void:
	for slot in [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_EMISSION, BaseMaterial3D.TEXTURE_NORMAL,
			BaseMaterial3D.TEXTURE_METALLIC, BaseMaterial3D.TEXTURE_ROUGHNESS, BaseMaterial3D.TEXTURE_AMBIENT_OCCLUSION]:
		var tex := mat.get_texture(slot) as ImageTexture
		if tex == null:
			continue
		var kind := &"normal" if slot == BaseMaterial3D.TEXTURE_NORMAL \
				else (&"colour" if slot == BaseMaterial3D.TEXTURE_ALBEDO or slot == BaseMaterial3D.TEXTURE_EMISSION else &"data")
		var slim := slim_texture(tex, kind)
		if slim != tex:
			mat.set_texture(slot, slim)


## A slim copy of [param tex] ([param kind] is colour, normal or data: a channel-packed map keeps all three colour channels),
## shared with every earlier image of the same content; [param tex] itself when it cannot be read or is already compressed.
static func slim_texture(tex: ImageTexture, kind: StringName) -> Texture2D:
	var src := tex.get_image()
	if src == null or src.is_empty() or src.is_compressed():
		return tex
	stats["textures"] += 1
	stats["bytes_before"] += src.get_data_size()
	var key := "%s|%d|%d|%d|%d|%d" % [kind, src.get_width(), src.get_height(), src.get_format(), max_texture_size, compression()]
	var raw := src.get_data()
	key += "|%d|%d" % [hash(raw), hash(raw.slice(raw.size() / 3))]
	var ref: WeakRef = _shared.get(key)
	var hit: Texture2D = ref.get_ref() as Texture2D if ref != null else null
	if hit != null:
		stats["shared"] += 1
		stats["bytes_after"] += 0
		return hit
	var out := slim_image(src, kind)
	var made := ImageTexture.create_from_image(out)
	stats["bytes_after"] += out.get_data_size()
	_shared[key] = weakref(made)
	return made


## The image in the smallest format that keeps what [param kind] reads, with mipmaps.
static func slim_image(src: Image, kind: StringName) -> Image:
	var img := src.duplicate() as Image
	if img.has_mipmaps():
		img.clear_mipmaps()
	while max_texture_size > 0 and maxi(img.get_width(), img.get_height()) > max_texture_size:
		img.resize(maxi(img.get_width() / 2, 1), maxi(img.get_height() / 2, 1), Image.INTERPOLATE_LANCZOS)
	var channels := Image.USED_CHANNELS_RGB
	if kind == &"normal":
		channels = Image.USED_CHANNELS_RG
	else:
		var used := img.detect_used_channels()
		if used == Image.USED_CHANNELS_RGBA or used == Image.USED_CHANNELS_LA:
			channels = Image.USED_CHANNELS_RGBA
	var mode := compression()
	if mode >= 0 and img.get_width() >= 4 and img.get_height() >= 4:
		img.generate_mipmaps(kind == &"normal")
		img.compress_from_channels(mode, channels)
		return img
	# No compressed format (the browser) or a texture under one block: only fewer channels.
	img.convert(Image.FORMAT_RG8 if channels == Image.USED_CHANNELS_RG \
			else (Image.FORMAT_RGBA8 if channels == Image.USED_CHANNELS_RGBA else Image.FORMAT_RGB8))
	img.generate_mipmaps(kind == &"normal")
	return img
