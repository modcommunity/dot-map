extends Node3D

## [DotMapBrush]: every kind built, measured, ray-cast and (with --shot) drawn.
##
## [codeblock]
## godot --headless --path . res://examples/brushes_demo.tscn
## godot --path . res://examples/brushes_demo.tscn -- --shot=~/frames/brushes   # on a display
## [/codeblock]
##
## The checks cannot see a face wound inside out or a texture stretched along a slope, so
## the frame has to be looked at: the checker material below makes both obvious.

const CHECKS := 62
const SECTIONS := 4

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()
var _entered := 0
var _completed := 0
var _bodies := {}


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("dot-map brushes")
	_test_spec()
	_build_gallery()
	await get_tree().physics_frame
	await get_tree().physics_frame
	_test_bounds()
	_test_uvs()
	_test_collision()
	var prefix := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			prefix = arg.substr(7).replace("~", OS.get_environment("HOME"))
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
	print("  " + title)


func _done() -> void:
	_completed += 1


func _check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		_failures.append(what)


func _specs() -> Dictionary:
	return {
		"box": {"kind": "box", "size": [3, 2, 3]},
		"wedge": {"kind": "ramp", "size": [6, 3, 3]},
		"stairs": {"kind": "stairs", "size": [6, 3, 3], "params": {"steps": 6}},
		"cylinder": {"kind": "cylinder", "size": [3, 3, 3]},
		"cone": {"kind": "cone", "size": [3, 4, 3]},
		"spike": {"kind": "spike", "size": [1.5, 4, 1.5]},
		"arch": {"kind": "arch", "size": [6, 5, 1.5], "params": {"thickness": 1.0}},
		"quarter_pipe": {"kind": "quarter_pipe", "size": [6, 3, 4]},
		"slab_holes": {"kind": "slab_holes", "size": [8, 0.6, 5], "params": {"holes": [[-2, 0, 1.5, 1.5], [1.5, 0.5, 2, 1]]}},
	}


func _test_spec() -> void:
	_section("specs")
	for kind in DotMapBrush.kinds():
		_check(_specs().has(kind), "demo has a spec for %s" % kind)
	_check(DotMapBrush.has_kind("ramp") and DotMapBrush.resolve("ramp") == "wedge", "ramp is wedge")
	var bad := DotMapBrush.validate({"kind": "teapot", "size": [1, 1, 1]})
	_check(not bad.ok and bad.error.code == DotError.CODE_INVALID, "unknown kind is invalid")
	_check(not DotMapBrush.validate({"kind": "box", "size": [1, 0, 1]}).ok, "flat size is invalid")
	_check(not DotMapBrush.validate({"kind": "box", "size": [1, 1]}).ok, "two-part size is invalid")
	_check(not DotMapBrush.validate({"kind": "stairs", "size": [1, 1, 1], "params": {"steps": 0}}).ok, "no steps is invalid")
	_check(not DotMapBrush.validate({"kind": "slab_holes", "size": [1, 1, 1], "params": {"holes": [[1, 2]]}}).ok, "bad hole is invalid")
	_check(DotMapBrush.build_body({"kind": "box", "size": [1, 0, 1]}) == null, "invalid spec builds nothing")
	_check(DotMapBrush.pieces({"kind": "stairs", "size": [1, 1, 1], "params": {"steps": 4}}).size() == 4, "stairs: a piece per step")
	_done()


func _build_gallery() -> void:
	var checker := StandardMaterial3D.new()
	checker.albedo_texture = _checker()
	checker.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var floor_body := StaticBody3D.new()
	var fm := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 30)
	fm.mesh = pm
	var flat := StandardMaterial3D.new()
	flat.albedo_color = Color(0.32, 0.34, 0.36)
	fm.material_override = flat
	floor_body.add_child(fm)
	var fc := CollisionShape3D.new()
	var fs := BoxShape3D.new()
	fs.size = Vector3(60, 0.2, 30)
	fc.shape = fs
	fc.position.y = -0.1
	floor_body.add_child(fc)
	add_child(floor_body)
	var i := 0
	var specs := _specs()
	for key: String in specs:
		var body := DotMapBrush.build_body(specs[key], checker)
		body.name = key
		var size := DotMapBrush.size_of(specs[key])
		var col := i % 5
		var row := i / 5
		body.position = Vector3((col - 2) * 9.0, size.y * 0.5, row * 9.0)
		add_child(body)
		_bodies[key] = body
		var label := Label3D.new()
		label.text = key
		label.font_size = 80
		label.pixel_size = 0.006
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = body.position + Vector3(0, size.y * 0.5 + 0.8, 0)
		add_child(label)
		i += 1
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.25, 0.3, 0.38)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.62, 0.68)
	env.ambient_light_energy = 0.4
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	var cam := Camera3D.new()
	cam.name = "Camera"
	add_child(cam)
	cam.position = Vector3(-6, 14, 24)
	cam.look_at(Vector3(0, 0, 4.5), Vector3.UP)
	cam.current = true


## A 1 m cell: a bright border and a diagonal, so stretch and a flipped face both show.
func _checker() -> Texture2D:
	var img := Image.create(64, 64, true, Image.FORMAT_RGB8)
	for x in 64:
		for y in 64:
			var edge := x < 3 or y < 3
			var light := (x / 32 + y / 32) % 2 == 0
			img.set_pixel(x, y, Color(0.95, 0.85, 0.3) if edge else (Color(0.75, 0.75, 0.78) if light else Color(0.35, 0.4, 0.55)))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _bounds_of(key: String) -> AABB:
	var mi := (_bodies[key] as Node).get_node("Mesh") as MeshInstance3D
	return mi.mesh.get_aabb()


func _test_bounds() -> void:
	_section("meshes fill their size and collide")
	var specs := _specs()
	for key: String in specs:
		var want := DotMapBrush.size_of(specs[key])
		var got := _bounds_of(key)
		_check(got.size.is_equal_approx(want) or got.size.distance_to(want) < 0.01, "%s mesh is %s, want %s" % [key, got.size, want])
		_check(got.get_center().length() < 0.01, "%s is centred (%s)" % [key, got.get_center()])
		var shapes := 0
		for c in (_bodies[key] as Node).get_children():
			if c is CollisionShape3D and (c as CollisionShape3D).shape is ConvexPolygonShape3D:
				shapes += 1
		_check(shapes > 0, "%s has convex collision" % key)
	_check(_bodies["arch"].get_child_count() == 1 + 10, "arch: 10 convex segments")
	_done()


func _test_uvs() -> void:
	_section("UVs are in metres")
	var small := DotMapBrush.mesh_of(DotMapBrush.pieces({"kind": "box", "size": [2, 2, 2]}))
	var big := DotMapBrush.mesh_of(DotMapBrush.pieces({"kind": "box", "size": [8, 2, 2]}))
	_check(_uv_span(small).is_equal_approx(Vector2(2, 2)), "2 m box: top face spans 2 x 2 UV (%s)" % _uv_span(small))
	_check(_uv_span(big).is_equal_approx(Vector2(8, 2)), "8 m box: top face spans 8 x 2 UV (%s)" % _uv_span(big))
	var scaled := DotMapBrush.mesh_of(DotMapBrush.pieces({"kind": "box", "size": [2, 2, 2]}), 0.5)
	_check(_uv_span(scaled).is_equal_approx(Vector2(4, 4)), "uv_metres 0.5 doubles the repeat")
	# A 45 degree slope: the wedge's sloped face is 4*sqrt(2) long and must span that in UV v.
	var wedge := DotMapBrush.mesh_of(DotMapBrush.pieces({"kind": "wedge", "size": [4, 4, 2]}))
	var found := false
	var arrays := wedge.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in range(0, verts.size(), 3):
		if absf(norms[i].y - 0.7071) < 0.01:
			var d := (uvs[i] - uvs[i + 1]).length()
			var e := (verts[i] - verts[i + 1]).length()
			found = absf(d - e) < 0.01
			break
	_check(found, "a slope's UV edge length equals its real length")
	var stairs := DotMapBrush.pieces({"kind": "quarter_pipe", "size": [6, 3, 3]})
	var full := 0
	for p: Array in stairs:
		full += p.size()
	var drawn: int = (DotMapBrush.mesh_of(stairs).surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	_check(drawn < full * 6, "quarter-pipe: faces shared between slices are not drawn")
	_done()


func _uv_span(m: ArrayMesh) -> Vector2:
	# The top face: the vertices with normal +y.
	var a := m.surface_get_arrays(0)
	var uvs: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	var norms: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in uvs.size():
		if norms[i].y > 0.99:
			lo = lo.min(uvs[i])
			hi = hi.max(uvs[i])
	return hi - lo


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	return get_world_3d().direct_space_state.intersect_ray(q)


func _test_collision() -> void:
	_section("rays hit the shape, not its box")
	var s := _bodies["stairs"] as Node3D
	var p := s.position
	# 6 steps over 6 m: step i covers x in [i, i+1) from the left edge, top at 0.5*(i+1) above the base.
	var base := p.y - 1.5
	for i in [0, 2, 5]:
		var x: float = p.x - 3.0 + i + 0.5
		var hit := _ray(Vector3(x, 10, p.z), Vector3(x, -1, p.z))
		_check(not hit.is_empty() and absf(hit["position"].y - (base + 0.5 * (i + 1))) < 0.01, "stairs step %d top" % i)
	var a := _bodies["arch"] as Node3D
	var under := _ray(Vector3(a.position.x, 0.3, a.position.z + 5), Vector3(a.position.x, 0.3, a.position.z - 5))
	_check(under.is_empty(), "arch: a ray through the opening hits nothing")
	var leg := _ray(Vector3(a.position.x - 2.7, 0.3, a.position.z + 5), Vector3(a.position.x - 2.7, 0.3, a.position.z - 5))
	_check(not leg.is_empty(), "arch: a ray through a leg hits")
	var crown := _ray(Vector3(a.position.x, 9, a.position.z), Vector3(a.position.x, -1, a.position.z))
	_check(not crown.is_empty() and absf(crown["position"].y - 5.0) < 0.1, "arch: crown at the full height (%s)" % crown.get("position", "none"))
	var sl := _bodies["slab_holes"] as Node3D
	var hole := _ray(Vector3(sl.position.x - 2, 5, sl.position.z), Vector3(sl.position.x - 2, -1, sl.position.z))
	_check(not hole.is_empty() and hole["position"].y < 0.01, "slab: a ray down a hole reaches the ground")
	var solid := _ray(Vector3(sl.position.x + 3.5, 5, sl.position.z - 1.5), Vector3(sl.position.x + 3.5, -1, sl.position.z - 1.5))
	_check(not solid.is_empty() and absf(solid["position"].y - 0.6) < 0.01, "slab: a ray beside the holes lands on top")
	var qp := _bodies["quarter_pipe"] as Node3D
	var mid := _ray(Vector3(qp.position.x, 9, qp.position.z), Vector3(qp.position.x, -1, qp.position.z))
	# At x centre the curve is at y = -h + sy * (1 - cos(asin(0.5))) .
	var want := 0.0 + 3.0 * (1.0 - cos(asin(0.5)))
	_check(not mid.is_empty() and absf(mid["position"].y - want) < 0.25, "quarter-pipe: curve height mid-way (%s vs %s)" % [mid.get("position", "none"), want])
	var cone := _bodies["cone"] as Node3D
	var tip := _ray(Vector3(cone.position.x, 9, cone.position.z), Vector3(cone.position.x, -1, cone.position.z))
	_check(not tip.is_empty() and absf(tip["position"].y - 4.0) < 0.01, "cone: apex at its height")
	var edge := _ray(Vector3(cone.position.x + 1.3, 9, cone.position.z), Vector3(cone.position.x + 1.3, -1, cone.position.z))
	_check(not edge.is_empty() and edge["position"].y < 1.0, "cone: near the rim it is low")
	var cyl := _bodies["cylinder"] as Node3D
	var corner := _ray(Vector3(cyl.position.x + 1.4, 9, cyl.position.z + 1.4), Vector3(cyl.position.x + 1.4, -1, cyl.position.z + 1.4))
	_check(corner.is_empty() or corner["position"].y < 0.01, "cylinder: the box corner is empty")
	_done()


func _shoot(prefix: String) -> void:
	var cam: Camera3D = $Camera
	var views := {
		"overview": [Vector3(-8, 15, 24), Vector3(0, 0, 4.5)],
		"close": [Vector3(-12, 5, 12), Vector3(-6, 1.5, 0)],
		"low": [Vector3(0, 2.5, 20), Vector3(1, 1.5, 9)],
	}
	for name: String in views:
		cam.position = views[name][0]
		cam.look_at(views[name][1], Vector3.UP)
		for i in 8:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s_%s.png" % [prefix, name])
		print("saved %s_%s.png (%dx%d)" % [prefix, name, img.get_width(), img.get_height()])
