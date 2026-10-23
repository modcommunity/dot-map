extends Node3D

## Every surface kind of [DotMapSurfaces] on code-built boxes, and the suite that proves the
## library hands back what a map generator expects.
##
## [codeblock]
## godot --headless --path . res://examples/surfaces_demo.tscn
## # Frames, on a display (xvfb-run, or a real GPU through gpu.sh):
## godot --path . res://examples/surfaces_demo.tscn -- --shot=/tmp/frames
## [/codeblock]
##
## Headless it only checks; with [code]--shot=<prefix>[/code] it renders three views to
## [code]<prefix>_overview.png[/code], [code]_low.png[/code] and [code]_close.png[/code] and quits.
## [b]An interface and a look are what no assertion reaches[/b]: the checks cannot tell a normal
## map that is inside out, or a texture twice the size it should be, so the frames have to be
## looked at.

const CHECKS := 105
const SECTIONS := 4

const COLUMNS := 5
const CUBE := 3.0
const GAP := 2.4

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()
var _entered := 0
var _completed := 0
var _surfaces := DotMapSurfaces.new()


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("dot-map surfaces")
	_test_kinds()
	_test_material_flags()
	_test_aliases_and_fallback()
	_test_paths()
	_build_gallery()

	var prefix := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			prefix = arg.substr(7)
	if prefix != "":
		await _shoot(prefix)

	print("")
	print("%d passed, %d failed" % [_passed, _failed])
	for line in _failures:
		print("  FAIL  %s" % line)
	print("%d of %d sections ran to their last line" % [_completed, _entered])
	if _entered != SECTIONS or _completed != _entered:
		print("ERROR: %d sections entered and %d completed, %d expected." % [_entered, _completed, SECTIONS])
		get_tree().quit(1)
		return
	if _passed + _failed != CHECKS:
		print("ERROR: %d checks ran, %d expected. A section aborted part-way." % [_passed + _failed, CHECKS])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)


func _section(title: String) -> void:
	_entered += 1
	print(title)


func _done() -> void:
	_completed += 1


func _check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		_failures.append(what)
		print("  FAIL  %s" % what)


func _test_kinds() -> void:
	_section("every kind loads")
	var kinds := _surfaces.kinds()
	_check(kinds.size() == 28, "twenty-eight kinds")
	for k in kinds:
		var res := _surfaces.try_material(StringName(k))
		_check(res.ok, "%s loads" % k)
		if not res.ok:
			continue
		var m: StandardMaterial3D = res.value
		_check(
			m.albedo_texture != null and m.normal_texture != null and m.roughness_texture != null,
			"%s has albedo, normal and roughness" % k
		)
		_check(m.albedo_texture.get_width() == 1024, "%s is 1K" % k)
	_done()


func _test_material_flags() -> void:
	_section("materials are world-space triplanar at a real scale")
	var m := _surfaces.material(&"brick")
	_check(m.uv1_triplanar and m.uv1_world_triplanar, "brick is world triplanar")
	_check(m.normal_enabled, "brick has its normal map on")
	_check(is_equal_approx(m.uv1_scale.x, 1.0 / 3.0), "brick covers three metres a texture")
	_check(_surfaces.material(&"brick") == m, "the same kind and tint is one material")
	_check(_surfaces.material(&"brick", Color(0.5, 0.5, 0.5)) != m, "a tint is another material")
	_check(_surfaces.material(&"metal").metallic > 0.0, "metal is metallic")
	_check(_surfaces.material(&"plaster").metallic == 0.0, "plaster is not")
	_check(_surfaces.describe()["kinds"] == 28, "describe counts kinds")
	_done()


func _test_aliases_and_fallback() -> void:
	_section("aliases, unknown kinds and a missing texture")
	_check(_surfaces.resolve(&"wall") == &"plaster", "wall is plaster")
	_check(_surfaces.resolve(&"road") == &"asphalt", "road is asphalt")
	_check(_surfaces.resolve(&"brick") == &"brick", "a kind resolves to itself")
	_check(not _surfaces.has_kind(&"unobtainium"), "an unknown kind is not a kind")
	_check(not _surfaces.try_material(&"unobtainium").ok, "an unknown kind is a failure")
	_check(
		_surfaces.try_material(&"unobtainium").error.code == DotError.CODE_INVALID,
		"and the code is invalid"
	)
	var f := _surfaces.material(&"unobtainium")
	_check(f != null and f.albedo_texture == null, "material() still returns a flat material")
	var broken := DotMapSurfaces.new("res://does/not/exist")
	var res := broken.try_material(&"brick")
	_check(not res.ok and res.error.code == DotError.CODE_IO, "a missing root is an io failure")
	_check(broken.material(&"brick") != null, "and material() still answers")
	_done()


func _test_paths() -> void:
	_section("a path function rebases the root")
	var seen: Array = []
	var s := DotMapSurfaces.new("res://nowhere")
	s.path_fn = func(p: String) -> String:
		seen.append(p)
		return p.replace("res://nowhere", DotMapSurfaces.DEFAULT_ROOT)
	var res := s.try_material(&"asphalt")
	_check(res.ok, "asphalt loads through the rebased path")
	_check(seen.size() == 3, "the function saw each of three textures")
	_check(seen.size() > 0 and String(seen[0]).begins_with("res://nowhere/asphalt/"), "it saw the unrebased path")
	_done()


# --- The gallery -------------------------------------------------------------------

func _build_gallery() -> void:
	var kinds := _surfaces.kinds()
	var rows := int(ceil(float(kinds.size()) / COLUMNS))
	var pitch := CUBE + GAP
	var width := COLUMNS * pitch
	var depth := rows * pitch

	var ground := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(width + 30.0, 0.2, depth + 40.0)
	ground.mesh = plane
	var flat := StandardMaterial3D.new()
	flat.albedo_color = Color(0.3, 0.3, 0.32)
	ground.material_override = flat
	ground.position = Vector3(0.0, -0.1, depth * 0.5 - 8.0)
	add_child(ground)

	for i in kinds.size():
		var col := i % COLUMNS
		var row := i / COLUMNS
		var cube := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(CUBE, CUBE, CUBE)
		cube.mesh = box
		cube.material_override = _surfaces.material(StringName(kinds[i]))
		cube.position = Vector3((col - (COLUMNS - 1) * 0.5) * pitch, CUBE * 0.5, row * pitch)
		cube.name = kinds[i]
		add_child(cube)
		var label := Label3D.new()
		label.text = kinds[i]
		label.font_size = 80
		label.pixel_size = 0.0055
		label.outline_size = 24
		label.position = cube.position + Vector3(0.0, CUBE * 0.5 + 0.3, 0.0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(label)

	# A long wall and a short one in one material: the brick is the same size on both, which
	# is what world-space mapping is for.
	var long_wall := MeshInstance3D.new()
	var lw := BoxMesh.new()
	lw.size = Vector3(width, 4.0, 0.4)
	long_wall.mesh = lw
	long_wall.material_override = _surfaces.material(&"brick")
	long_wall.position = Vector3(0.0, 2.0, -pitch)
	add_child(long_wall)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.light_energy = 0.8
	sun.shadow_enabled = true
	add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.25, 0.3, 0.38)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.65)
	env.ambient_light_energy = 0.35
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)

	var cam := Camera3D.new()
	cam.name = "Camera"
	cam.fov = 60.0
	add_child(cam)
	_view(cam, Vector3(0.0, 16.0, depth + 10.0), Vector3(0.0, 0.0, depth * 0.4))




func _view(cam: Camera3D, from: Vector3, at: Vector3) -> void:
	cam.position = from
	cam.look_at(at, Vector3.UP)
	cam.current = true


func _shoot(prefix: String) -> void:
	var cam: Camera3D = $Camera
	var pitch := CUBE + GAP
	var rows := int(ceil(float(_surfaces.kinds().size()) / COLUMNS))
	var depth := rows * pitch
	var views := {
		"overview": [Vector3(0.0, 16.0, depth + 10.0), Vector3(0.0, 0.0, depth * 0.4)],
		"low": [Vector3(-14.0, 1.7, depth + 3.0), Vector3(4.0, 1.5, depth * 0.3)],
		"close": [Vector3(-pitch + 1.0, 1.7, CUBE * 0.5 + GAP * 0.5), Vector3(-pitch - 0.3, 1.3, 0.0)],
	}
	for name: String in views:
		_view(cam, views[name][0], views[name][1])
		for i in 8:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s_%s.png" % [prefix, name])
		print("saved %s_%s.png (%dx%d)" % [prefix, name, img.get_width(), img.get_height()])
