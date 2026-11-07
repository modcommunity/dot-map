extends Node

## The surface textures left out of the client shell's pck still resolve once a pack carrying them is mounted and listed in
## DotMapSurfaces.fallback_roots. The pack is built here (PCKPacker, three 4x4 textures for one kind); no CDN, no dot-cloud.

const POOL := "res://dot_cloud/synth/1/surfaces"
const MISSING_ROOT := "res://shell_without_surfaces"

var _passed := 0
var _failed := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("FAIL ", what)


func _run() -> void:
	print("dot-map surfaces pack")
	var pck := _build_pack()
	_check(not pck.is_empty(), "synthetic pack built")

	var s := DotMapSurfaces.new(MISSING_ROOT)
	_check(not s.try_material(&"brick").ok, "before the mount: the shell has no textures and says io")
	_check(s.try_material(&"brick").code() == DotError.CODE_IO, "before the mount: the failure code is io")
	_check(DotMapSurfaces.fallback_roots.is_empty(), "no fallback root by default")

	_check(ProjectSettings.load_resource_pack(pck), "synthetic pack mounts")
	var plain := DotMapSurfaces.new(MISSING_ROOT)
	_check(not plain.try_material(&"brick").ok, "mounted but not listed: still not found (the root is explicit)")

	DotMapSurfaces.fallback_roots = PackedStringArray([POOL])
	var fresh := DotMapSurfaces.new(MISSING_ROOT)
	var res := fresh.try_material(&"brick")
	_check(res.ok, "listed: the kind resolves through the mounted pack")
	if res.ok:
		var m: StandardMaterial3D = res.value
		_check(m.albedo_texture != null and m.albedo_texture.get_width() == 4, "albedo came from the pack")
		_check(m.normal_texture != null and m.roughness_texture != null, "normal and roughness came from the pack")
	_check(not fresh.try_material(&"concrete").ok, "a kind the pack lacks still fails")

	DotMapSurfaces.fallback_roots = PackedStringArray()
	print("RESULT %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _build_pack() -> String:
	var stage := ProjectSettings.globalize_path("user://surf_stage")
	DirAccess.make_dir_recursive_absolute(stage)
	var packer := PCKPacker.new()
	var out := ProjectSettings.globalize_path("user://surfaces_synth.pck")
	if packer.pck_start(out) != OK:
		return ""
	var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
	img.fill(Color(0.5, 0.4, 0.3))
	for f in ["albedo", "normal", "roughness"]:
		var res_path := "%s/%s.res" % [stage, f]
		ResourceSaver.save(ImageTexture.create_from_image(img), res_path)
		var imp := "%s/%s.jpg.import" % [stage, f]
		var fa := FileAccess.open(imp, FileAccess.WRITE)
		fa.store_string('[remap]\n\nimporter="keep"\npath="%s/brick/%s.res"\n' % [POOL, f])
		fa.close()
		packer.add_file("%s/brick/%s.res" % [POOL, f], res_path)
		packer.add_file("%s/brick/%s.jpg.import" % [POOL, f], imp)
	if packer.flush() != OK:
		return ""
	return out
