extends RefCounted

## The texture-file half of [DotMapSurfaces] (its base script): finds a PBR set's files, loads them imported, pre-baked or decoded,
## and halves masks and normals. [DotMapSurfaces] builds the materials on top.

var _textures: Dictionary = {}
## Longest side of a decoded texture file; larger ones are halved until they fit (0 keeps them). Store slices are imported, never touched.
var max_texture_size: int = 2048
## Roughness and AO maps keep half their size (a quarter of the memory) when true, decoded, imported or baked alike (the top mip is sliced off, nothing re-encoded). On by default: a frame diff on a manor map is at most 5 of 255.
var half_res_masks: bool = true
## Normal maps keep half their size too (same top-mip slice). On by default: a daylight frame at ground level differs by 0.19 of 255 on average, and it takes 258 MB off the manor.
var half_res_normals: bool = true
## Folder of the shared PBR sets (`<id>/<tier>/*.webp`) when the game delivers them apart from the pack; empty reads the folder the manifest names, beside the pack.
var pbr_library: String = ""
## Folders searched for a set before [member pbr_library], in order: a map's own slice and the shared slices it depends on.
var pbr_libraries: PackedStringArray = PackedStringArray()
var _set_roots: Dictionary = {}


## The suffix of the pre-baked texture this build loads (`dot-map-convert/tools/bake_textures.gd`), "" when it has no VRAM format to read.
static func baked_variant() -> String:
	return DotMapTextureBake.pick_variant(OS.has_feature, OS.get_environment("NOCOMP") != "")


## The pre-baked `<name>.<variant>.res` beside [param path] (already capped, mip-mapped and compressed, so no decode), or null when there is none, it is unreadable, predates the bake metadata, was baked from another file, or is not the size [member max_texture_size] and [member half_res_masks] want.
func _baked_texture(path: String) -> Texture2D:
	var variant := baked_variant()
	if variant.is_empty():
		return null
	var baked := "%s.%s.res" % [path.get_basename(), variant]
	if not FileAccess.file_exists(baked):
		return null
	var tex := ResourceLoader.load(baked, "ImageTexture") as Texture2D
	if tex == null or not DotMapTextureBake.fits(tex, path, max_texture_size, variant):
		return null
	return tex


## The first existing file of the set's [param part] (webp, then jpg), or "".
func _set_file(dir: String, part: String) -> String:
	for ext in ["webp", "jpg"]:
		var p := dir.path_join("%s.%s" % [part, ext])
		if FileAccess.file_exists(p) or ResourceLoader.exists(p):
			return p
	return ""


func _white() -> Texture2D:
	if not _textures.has("white"):
		var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
		img.fill(Color.WHITE)
		_textures["white"] = ImageTexture.create_from_image(img)
	return _textures["white"]


## A library set shipped in the pack (`pbr/<id>/`): albedo, normal, roughness and AO, world-triplanar.
func _pbr_material(dir: String, key: String) -> StandardMaterial3D:
	var sm := StandardMaterial3D.new()
	sm.resource_name = key
	sm.uv1_triplanar = true
	sm.uv1_world_triplanar = true
	sm.uv1_scale = Vector3.ONE * 0.5
	sm.albedo_texture = _set_texture(dir, "albedo")
	var n := _set_texture(dir, "normal")
	if n != null:
		sm.normal_enabled = true
		sm.normal_texture = n
	var r := _set_texture(dir, "roughness")
	if r != null:
		sm.roughness_texture = r
		sm.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	var ao := _set_texture(dir, "ao")
	if ao != null:
		sm.ao_enabled = true
		sm.ao_texture = ao
		sm.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	return sm


## The folder of the PBR set [param t] names: `<library>/<id>/<tier>` for a shared store, the pack's own `pbr/<id>` for an older one.
func _pbr_dir(dir: String, store: String, t: Dictionary) -> String:
	var id := str(t["file"]).get_file()
	if store.is_empty() and pbr_library.is_empty() and pbr_libraries.is_empty():
		return dir.path_join(str(t["file"]))
	var tier := str(t.get("tier", "1k"))
	for lib in pbr_libraries:
		var cand := lib.path_join(id).path_join(tier)
		if _has_set(cand):
			return cand
	var root := pbr_library if not pbr_library.is_empty() else dir.path_join(store).simplify_path()
	return root.path_join(id).path_join(tier)


func _has_set(dir: String) -> bool:
	if not _set_roots.has(dir):
		var found := false
		for ext in ["webp", "jpg"]:
			var p := dir.path_join("albedo." + ext)
			found = found or FileAccess.file_exists(p) or ResourceLoader.exists(p)
		_set_roots[dir] = found
	return _set_roots[dir]


func _set_texture(dir: String, name: String) -> Texture2D:
	var p := _set_file(dir, name)
	return _file_texture(p) if not p.is_empty() else null


func _file_texture(path: String) -> Texture2D:
	if _textures.has(path):
		return _textures[path]
	# A mounted store slice holds the engine's import (VRAM-compressed, mipmapped), never the source file.
	if path.begins_with("res://") and ResourceLoader.exists(path):
		var loaded := load(path) as Texture2D
		# A pack published with an .import marker but without its .ctex exists and loads as null: the raw file is still there.
		if loaded != null:
			var imported := _masked(path, loaded)
			_textures[path] = imported
			return imported
	var baked := _baked_texture(path)
	if baked != null:
		baked = _masked(path, baked)
		_textures[path] = baked
		return baked
	var img := Image.load_from_file(path)
	if img == null:
		return null
	DotMapImagePrep.prepare_image(img, path, max_texture_size, half_res_masks, -1, half_res_normals)
	var tex := ImageTexture.create_from_image(img)
	_textures[path] = tex
	return tex


## [param tex] of a roughness, AO or normal map without its top mip level when [member half_res_masks] or [member half_res_normals] says so: an imported or baked map is already compressed, so the next level of its own chain is cut out, with no decode or recompress.
func _masked(path: String, tex: Texture2D) -> Texture2D:
	if tex == null or not DotMapImagePrep.halves(path.get_file().get_basename(), half_res_masks, half_res_normals):
		return tex
	return DotMapImagePrep.without_top_mip(tex)
