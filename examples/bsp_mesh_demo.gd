extends Node3D

## [DotMapBspMesh]: the converter's fixture read, built, and ray-cast.
##
## [codeblock]
## godot --headless --path . res://examples/bsp_mesh_demo.tscn
## [/codeblock]
##
## The fixture is [code]examples/bsp_mesh/fixture.{json,bin}[/code], written by
## [code]tools/bsp/tests/mesh_fixture.py[/code] (whose test fails when it is stale): a 512-unit
## floor slab 16 high, a wall along its far edge, and a door named [code]gate[/code] 8 units
## thick at (256, 256, 16), at 0.01905 m per unit.

const CHECKS := 109
const SECTIONS := 9
const FIXTURE := "res://examples/bsp_mesh/fixture"
const GLASS := "res://examples/bsp_mesh/glass"
const TERRAIN := "res://examples/bsp_mesh/terrain_fixture.json"
const U := 0.01905

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()
var _entered := 0
var _completed := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("dot-map bsp mesh")
	var world := _test_read()
	if world != null:
		_test_build(world)
		_test_environment(world)
		await _test_collide(world)
		await _test_glass()
	_test_terrain()
	_test_mesh_lods()
	var lit_world := _test_lightmap()
	if world != null and lit_world != null:
		_test_drawn(world, lit_world)
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


func _test_read() -> DotMapBspMesh:
	_section("reads and refuses")
	var res := DotMapBspMesh.load_prefix(FIXTURE)
	_check(res.ok, "the fixture loads: %s" % (res.error if not res.ok else ""))
	if not res.ok:
		return null
	var world: DotMapBspMesh = res.value
	var c := world.counts()
	_check(c["surfaces"] == 5 and c["triangles"] == 36, "5 surfaces, 36 triangles: %s" % c)
	_check(c["hulls"] == 3 and c["movers"] == 1, "3 hulls, 1 mover: %s" % c)
	_check(world.models() == PackedInt32Array([0, 1]), "models 0 and 1: %s" % world.models())
	_check(world.mover(1).get("targetname") == "gate", "the door's record: %s" % world.mover(1))
	_check(world.model_origin(1).is_equal_approx(Vector3(256 * U, 16 * U, -256 * U)),
			"the door's origin in Godot axes: %s" % world.model_origin(1))
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE + ".json"))
	var stored := FileAccess.get_file_as_bytes(FIXTURE + ".bin")
	var bad := stored.duplicate()
	bad[bad.size() / 2] = bad[bad.size() / 2] ^ 0xFF
	var r := DotMapBspMesh.from_data(doc, bad)
	_check(not r.ok and r.error.code == DotError.CODE_INTEGRITY, "a changed byte is refused")
	var newer := doc.duplicate(true)
	newer["version"] = DotMapBspMesh.VERSION + 1
	r = DotMapBspMesh.from_data(newer, stored)
	_check(not r.ok and r.error.code == DotError.CODE_VERSION, "a newer format is refused")
	var lying := doc.duplicate(true)
	(lying["surfaces"][0] as Dictionary)["vertex_count"] = 1 << 20
	r = DotMapBspMesh.from_data(lying, stored)
	_check(not r.ok and r.error.code == DotError.CODE_PARSE, "a surface past the data is refused")
	r = DotMapBspMesh.load_prefix("res://examples/bsp_mesh/none")
	_check(not r.ok and r.error.code == DotError.CODE_IO, "a missing file is an io failure")
	_done()
	return world


func _test_build(world: DotMapBspMesh) -> void:
	_section("builds nodes, one per chunk and per brush entity")
	var asked: Array[Dictionary] = []
	var mat := StandardMaterial3D.new()
	var root := world.build_node(func(rec: Dictionary) -> Material:
		asked.append(rec)
		return mat)
	add_child(root)
	_check(asked.size() == 5, "the material callback is asked once per surface: %d" % asked.size())
	_check(asked.all(func(r: Dictionary) -> bool: return r.get("generic") != null), "every surface has a generic id")
	var w := root.get_node_or_null("world")
	_check(w != null and w.get_children().filter(func(c: Node) -> bool: return not str(c.name).begins_with("shadow_")).size() == 2, "the world is two chunks: %s" % [w.get_children() if w else "none"])
	var gate := root.get_node_or_null("gate_1") as Node3D
	_check(gate != null and gate.position.is_equal_approx(world.model_origin(1)), "the door node sits at its origin")
	var box := AABB()
	for mi: MeshInstance3D in w.get_children():
		var b := mi.get_aabb()
		box = b if box.size == Vector3.ZERO else box.merge(b)
	_check(box.size.is_equal_approx(Vector3(512 * U, 192 * U, 512 * U)), "the world's bounds: %s" % box)
	var door_mesh := gate.get_child(0) as MeshInstance3D if gate else null
	var dbox := door_mesh.get_aabb() if door_mesh else AABB()
	var global_box := AABB(dbox.position + door_mesh.position + gate.position, dbox.size) if door_mesh else AABB()
	_check(global_box.position.is_equal_approx(Vector3(252 * U, 16 * U, -288 * U)), "the door is drawn where the map put it: %s" % global_box)
	_check(door_mesh != null and door_mesh.mesh.surface_get_material(0) == mat, "the callback's material is used")
	var m: ArrayMesh = (w.get_child(0) as MeshInstance3D).mesh
	var a := m.surface_get_arrays(0)
	_check((a[Mesh.ARRAY_TEX_UV] as PackedVector2Array).size() == (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(),
			"one uv per vertex")
	_done()


func _test_environment(world: DotMapBspMesh) -> void:
	_section("environment, sounds and free stand-ins")
	_check(not world.is_free() and world.build_environment() == null, "a map with no licence pass is not free and has no environment")
	world.manifest["licence"] = {"textures": []}
	world.manifest["environment"] = {"sky": {"name": "sky_day01"}, "sun": {"pitch": -45.0, "yaw": 90.0, "colour": [1, 0.9, 0.8, 400.0], "ambient": [0.2, 0.2, 0.3]},
			"fog": [{"enabled": true, "colour": [0.5, 0.5, 0.6], "start": 5.0, "end": 60.0, "max_density": 1.0}],
			"cubemaps": [{"at": [1, 2, 3]}, {"at": [4, 5, 6]}]}
	world.manifest["sounds"] = {"ambient": [
			{"entity": 1, "at": [1, 2, 3], "stand_in": "machine", "volume": 0.5, "radius": 20.0, "pitch": 100.0, "looped": true, "start_silent": false, "everywhere": false},
			{"entity": 2, "at": [0, 0, 0], "stand_in": "", "looped": true},
			{"entity": 3, "at": [0, 0, 0], "stand_in": "no_such_sound", "looped": true}]}
	world.manifest["props"] = [{"stand_in": "chair", "at": [2, 0, -3], "yaw": 90.0, "scale": 1.0}, {"stand_in": "no_such_prop", "at": [0, 0, 0], "yaw": 0.0, "scale": 1.0}]
	var env := world.build_environment(1)
	var e := (env.get_node("Environment") as WorldEnvironment).environment
	_check(e.fog_enabled and e.sky != null and e.tonemap_mode == Environment.TONE_MAPPER_FILMIC, "sky, fog and tonemap are applied")
	var sun := env.get_node("Sun") as DirectionalLight3D
	_check(is_equal_approx(sun.light_energy, 2.0) and is_equal_approx(sun.rotation_degrees.x, -45.0), "the sun's energy and pitch")
	var fwd := -sun.basis.z
	_check(absf(fwd.x) < 0.01 and fwd.z < -0.5 and fwd.y < -0.5, "yaw 90 (source +y) shines towards -z: %s" % fwd)
	_check(env.get_node("Probes").get_child_count() == 1, "max_probes limits the reflection probes")
	env.free()
	var snd := world.build_sounds()
	_check(snd.get_child_count() == 1 and snd.get_child(0) is AudioStreamPlayer3D, "one sound: the others have no stand-in or no file")
	var pl := snd.get_child(0) as AudioStreamPlayer3D
	_check(pl.position == Vector3(1, 2, 3) and is_equal_approx(pl.max_distance, 20.0) and pl.stream != null, "placed with its radius and stream")
	_check(absf(pl.volume_db - linear_to_db(0.5)) < 0.01, "volume carried")
	var driver := DotMapSoundDriver.new()
	driver.root = snd
	_check(driver.handle("sound_fade", {"entity": 1, "name": "", "seconds": 0.0, "from": 0.0, "to": 1.0}) and absf(pl.volume_db) < 0.01, "sound_fade to 1 sets full volume by entity")
	_check(driver.handle("sound_spin", {"entity": 1, "seconds": 0.0, "from": 100.0, "to": 200.0}) and is_equal_approx(pl.pitch_scale, 2.0), "sound_spin sets the pitch")
	var _d := driver.handle("sound_spin", {"entity": 1, "seconds": 0.0, "from": 100.0, "to": 1.0e9})
	_check(is_equal_approx(pl.pitch_scale, 4.0), "an absurd pitch is clamped")
	_check(not driver.handle("sound_fade", {"entity": 99, "name": "nobody", "seconds": 1.0}) and not driver.handle("beat", {}), "an unknown player or event does nothing")
	_d = driver.handle("sound_fade", {"entity": 1, "seconds": NAN, "from": NAN, "to": INF})
	_check(is_finite(pl.volume_db) and is_finite(pl.pitch_scale), "NaN and infinite event values are replaced, never tweened")
	add_child(snd)
	_d = driver.handle("sound_fade", {"entity": 1, "seconds": 5.0, "from": 1.0, "to": 0.5})
	_check(driver._tweens.size() == 1, "a timed fade keeps one tween")
	pl.free()
	_d = driver.handle("sound_fade", {"entity": 99, "seconds": 1.0})
	driver._prune()
	_check(driver._tweens.is_empty(), "the tween of a freed player is dropped")
	snd.free()
	driver.free()
	var hooked := []
	var snd2 := world.build_sounds(func(_id: String) -> AudioStream: return AudioStreamGenerator.new(),
			func(rec: Dictionary, _s: AudioStream) -> Node:
				hooked.append(rec["entity"])
				return Node3D.new())
	_check(hooked == [1, 3] and snd2.get_child_count() == 2, "stream and node hooks replace the defaults: %s" % [hooked])
	snd2.free()
	var props := world.build_props()
	_check(props.get_child_count() == 1 and absf((props.get_child(0) as Node3D).rotation_degrees.y - 180.0) < 0.01, "the chair stand-in is placed and turned to face +X at yaw 90")
	_check((props.get_child(0) as Node3D).position == Vector3(2, 0, -3), "at its place")
	props.free()
	world.manifest["props"] = [{"stand_in": "chair", "at": [0, 0, 0], "yaw": 0.0, "scale": 1.0, "solid": 6},
			{"stand_in": "chair", "at": [3, 0, 0], "yaw": 0.0, "scale": 1.0, "solid": 0}, {"stand_in": "chair", "at": [6, 0, 0], "yaw": 0.0, "scale": 1.0, "solid": 1}]
	var made: Array = []
	var solid_props := world.build_props(Callable(), func(b: StaticBody3D) -> void: made.append(b))
	_check(solid_props.get_child_count() == 4 and made.size() == 1 and (made[0] as StaticBody3D).get_child(0).get("shape") is BoxShape3D, "only solid 2/3/4/6 gets a box body: %d" % made.size())
	solid_props.free()
	var solid_only := world.build_prop_collision()
	_check(solid_only != null and solid_only.get_child_count() == 1 and (solid_only.get_child(0) as CollisionShape3D).shape is BoxShape3D and absf((solid_only.get_child(0) as CollisionShape3D).position.x) < 1.0,
			"build_prop_collision: one box for the one solid prop, in world space")
	solid_only.free()
	var plain_props := world.build_props()
	_check(plain_props.find_children("Solid", "StaticBody3D", true, false).is_empty(), "no body unless the game asks for them")
	plain_props.free()
	_check(world.is_free() == false, "a surface with no free key keeps the map from being called free")
	_done()


func _test_collide(world: DotMapBspMesh) -> void:
	_section("hulls collide where the brushes are")
	var body := StaticBody3D.new()
	add_child(body)
	var shapes := world.hull_shapes(0)
	_check(shapes.size() == 2 and shapes.all(func(s: Dictionary) -> bool: return s["kind"] == "solid"), "two solid world hulls")
	for s: Dictionary in shapes:
		var cs := CollisionShape3D.new()
		cs.shape = s["shape"]
		body.add_child(cs)
	var door := AnimatableBody3D.new()
	door.position = world.model_origin(1)
	add_child(door)
	var ds := world.hull_shapes(1)
	_check(ds.size() == 1, "one door hull")
	for s: Dictionary in ds:
		var cs := CollisionShape3D.new()
		cs.shape = s["shape"]
		door.add_child(cs)
	_check(world.hull_shapes(0, PackedStringArray(["clip"])).is_empty(), "the kind filter")
	_check(world.concave_shapes(0).is_empty(), "no displacement, no triangle shape")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(2, 5, -2), Vector3(2, -5, -2)))
	_check(not hit.is_empty() and absf(hit["position"].y - 16 * U) < 0.01, "a ray down lands on the floor's top: %s" % hit.get("position"))
	hit = space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(1, 1, -256 * U), Vector3(9, 1, -256 * U)))
	_check(not hit.is_empty() and absf(hit["position"].x - 252 * U) < 0.01 and hit["collider"] == door,
			"a ray across hits the door's face: %s" % hit.get("position"))
	door.position += Vector3(0, 3, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	hit = space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(1, 1, -256 * U), Vector3(9, 1, -256 * U)))
	_check(hit.is_empty(), "a raised door lets the ray through: %s" % hit.get("position"))
	hit = space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(5, 1, -1), Vector3(5, 1, -11)))
	_check(not hit.is_empty() and absf(hit["position"].z + 496 * U) < 0.01, "the wall stops a ray at its face: %s" % hit.get("position"))
	_done()


func _test_glass() -> void:
	_section("glass is transparent, shadowless and breakable")
	var res := DotMapBspMesh.load_prefix(GLASS)
	_check(res.ok, "the glass fixture reads")
	if not res.ok:
		_done()
		return
	var world: DotMapBspMesh = res.value
	var glass_recs := world.surfaces.filter(func(r: Dictionary) -> bool: return r.has("glass"))
	_check(glass_recs.size() == 4, "four glass surfaces (the pane wall, the breakable and the fence in two cells): %d" % glass_recs.size())
	_check(world.surfaces.any(func(r: Dictionary) -> bool: return not r.has("glass")), "the floor is not glass")
	var seen: Array = []
	var plain := func(rec: Dictionary) -> Material:
		seen.append(rec.get("glass", ""))
		return StandardMaterial3D.new()
	var root := world.build_node(plain)
	add_child(root)
	_check(not seen.has("glass"), "a glass surface never asks the game's callback")
	var glass_nodes: Array = []
	var other_nodes: Array = []
	for model in root.get_children():
		for mi: MeshInstance3D in model.get_children():
			(glass_nodes if str(mi.name).begins_with("glass_") else other_nodes).append(mi)
	_check(glass_nodes.size() == 3 and not other_nodes.is_empty(), "glass sits in its own mesh instances: %d" % glass_nodes.size())
	var gi: MeshInstance3D = glass_nodes[0]
	_check(gi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "glass casts no shadow")
	var proxies := other_nodes.filter(func(m: MeshInstance3D) -> bool: return str(m.name).begins_with("shadow_"))
	var visuals := other_nodes.filter(func(m: MeshInstance3D) -> bool: return not str(m.name).begins_with("shadow_"))
	_check(not proxies.is_empty() and proxies.all(func(m: MeshInstance3D) -> bool:
			return m.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY and m.mesh.get_surface_count() == 1),
			"walls cast through one shadows-only surface each: %d" % proxies.size())
	_check(visuals.all(func(m: MeshInstance3D) -> bool: return m.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF),
			"the visual meshes cast none themselves")
	var tris := 0
	for m: MeshInstance3D in proxies:
		tris += (m.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
	_check(tris > 0, "the proxies hold the walls' triangles: %d" % tris)
	var mat := gi.mesh.surface_get_material(0) as StandardMaterial3D
	_check(mat != null and mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and mat.albedo_color.a < 0.5,
			"glass is alpha-blended and see-through")
	_check(DotMapBspMesh.glass_material(&"glass_frosted").albedo_color.a > DotMapBspMesh.glass_material(&"glass").albedo_color.a,
			"frosted is more opaque than clear")
	var fence_tex := DotMapBspMesh.cutout_texture(&"diamond")
	var fence_img := fence_tex.get_image()
	var covered := func(level: int) -> float:
		var lvl := Image.create_from_data(fence_img.get_width(), fence_img.get_height(), true, fence_img.get_format(), fence_img.get_data())
		var n := 0
		var w := maxi(fence_img.get_width() >> level, 1)
		var off := lvl.get_mipmap_offset(level)
		var d := lvl.get_data()
		for i in w * w:
			if d[off + i * 4 + 3] >= 128:
				n += 1
		return float(n) / float(w * w)
	_check(absf(covered.call(1) - covered.call(0)) < 0.12 and covered.call(2) > 0.1,
			"a thin cutout keeps its coverage in the mips, so a fence does not vanish at distance (%.2f, %.2f vs %.2f)" % [covered.call(1), covered.call(2), covered.call(0)])
	_check(DotMapBspMesh.glass_material(&"fence").alpha_antialiasing_mode == BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE, "cutouts use alpha to coverage")
	_check(DotMapBspMesh.glass_material(&"nonsense") == DotMapBspMesh.glass_material(&"glass"), "an unknown kind is clear glass, shared")
	_check(world.breakables().size() == 1 and str(world.breakables()[0]["glass"]) == "glass", "one breakable glass model")
	var panes := world.build_breakables(root)
	_check(panes.size() == 1 and panes[0].health == 20.0 and panes[0].model == 1, "a pane with the map's health")
	var pane: DotMapGlass = panes[0]
	_check(world.hull_shapes(1)[0]["kind"] == "glass", "its hull has kind glass")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(Vector3(1, 1, -256 * U), Vector3(9, 1, -256 * U))
	_check(space.intersect_ray(ray).get("collider") == pane, "the pane stops a ray")
	var events: Array = []
	pane.broken.connect(func(at: Vector3, by: StringName) -> void: events.append(by))
	_check(not pane.hurt(5.0, Vector3(1, 1, -5), &"u1") and not pane.is_broken(), "a light hit does not break it")
	pane.authoritative = false
	_check(not pane.hurt(99.0) and not pane.is_broken(), "a client cannot break it")
	pane.authoritative = true
	_check(pane.hurt(15.0, Vector3(0.2, 1, -5), &"u2") and pane.is_broken() and events == [&"u2"], "enough damage breaks it once")
	_check(not pane.hurt(9.0) and events.size() == 1, "a broken pane breaks no more")
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(not (pane.visual as Node3D).visible, "it is hidden")
	_check(not space.intersect_ray(ray).has("collider"), "a ray goes through where it stood")
	_check(root.get_children().any(func(c: Node) -> bool: return c is CPUParticles3D), "shards were spawned")
	var twin := DotMapGlass.new()
	add_child(twin)
	twin.apply_broken(Vector3.ONE, &"host")
	_check(twin.is_broken(), "the host's word breaks it on a client")
	_done()


func _test_mesh_lods() -> void:
	_section("a heavy library mesh gets LOD levels and a triangle cap")
	var sphere := SphereMesh.new()
	sphere.radial_segments = 128
	sphere.rings = 64
	var arrays := sphere.get_mesh_arrays()
	var whole := (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	var plain := ArrayMesh.new()
	plain.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = plain
	root.add_child(mi)
	_check(DotMapBspMesh.add_mesh_lods(root, 0) == 0 and mi.mesh == plain, "a minimum of 0 leaves the mesh alone")
	_check(DotMapBspMesh.add_mesh_lods(root, whole + 1) == 0 and mi.mesh == plain, "a mesh under the minimum is left alone")
	_check(DotMapBspMesh.add_mesh_lods(root, 1000) == 1 and mi.mesh != plain, "a mesh over it is replaced")
	var lod_mesh := mi.mesh as ArrayMesh
	var capped_root := Node3D.new()
	var capped := MeshInstance3D.new()
	capped.mesh = plain
	capped_root.add_child(capped)
	var _n := DotMapBspMesh.add_mesh_lods(capped_root, 1000, whole / 4)
	var kept := ((capped.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	_check(lod_mesh != null and ((lod_mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3) == whole, "without a cap the first level keeps every triangle (%d)" % whole)
	_check(kept <= whole / 4 and kept > 0, "a cap of a quarter starts from a level of at most that many: %d of %d" % [kept, whole])
	root.free()
	capped_root.free()
	_done()


func _test_terrain() -> void:
	_section("terrain reads as the converter wrote it (tools/bsp/tests/test_terrain.py)")
	var fx: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TERRAIN))
	var res := DotMapTerrain.from_dict(fx["terrain"])
	_check(res.ok, "the terrain fixture reads: %s" % ("" if res.ok else str(res)))
	if not res.ok:
		_done()
		return
	var t: DotMapTerrain = res.value
	var bad := PackedStringArray()
	for p: Array in fx["probes"]:
		var h := t.height_at(p[0], p[1])
		if (p[2] == null) != is_nan(h) or (p[2] != null and absf(h - float(p[2])) > 1e-4):
			bad.append("(%s, %s) %s != %s" % [p[0], p[1], h, p[2]])
	_check(bad.is_empty(), "heights match the converter's: %s" % ", ".join(bad))
	var pts := t.walk_points(1.0)
	_check(pts.size() == int(fx["walk_points"]), "walk points %d, converter %d" % [pts.size(), fx["walk_points"]])
	var first: Array = fx["walk_first"]
	var last: Array = fx["walk_last"]
	_check(not pts.is_empty() and pts[0].distance_to(Vector3(first[0], first[1], first[2])) < 1e-3
			and pts[-1].distance_to(Vector3(last[0], last[1], last[2])) < 1e-3, "first and last walk points match")
	var faces := t.faces()
	_check(faces.size() == int(fx["faces"]), "faces %d, converter %d (the hole is kept)" % [faces.size(), fx["faces"]])
	_check((faces[1] - faces[0]).cross(faces[2] - faces[0]).y < 0.0, "faces wind clockwise seen from above, so they face up")
	var want := PackedStringArray()
	var got := t.skirt_edges()
	for k in range(0, got.size(), 4):
		want.append("%d,%d,%d,%d" % [got[k], got[k + 1], got[k + 2], got[k + 3]])
	want.sort()
	var theirs := PackedStringArray(str(fx["skirt_edges"]).split(";"))
	theirs.sort()
	_check(want == theirs, "the skirt's rim edges are the converter's (%d), the enclosed hole has none" % want.size())
	var wall := t.skirt_faces()
	_check(wall.size() == want.size() * 6 and not is_nan(t.skirt_y), "a skirt of one quad per rim edge hangs to %.2f" % t.skirt_y)
	var lowest := INF
	for v in wall:
		lowest = minf(lowest, v.y)
	_check(is_equal_approx(lowest, t.skirt_y), "the wall reaches the skirt level, under the lowest ground")
	_check(t.build_shape().get_faces().size() == faces.size() and t.build_shape(true).get_faces().size() == faces.size() + wall.size(),
			"collision is the field alone unless the skirt is asked for")
	var plain: Dictionary = fx["terrain"].duplicate()
	plain.erase("skirt")
	_check(DotMapTerrain.from_dict(plain).value.skirt_faces().is_empty(), "a field written without a skirt draws none")
	var newer: Dictionary = fx["terrain"].duplicate()
	newer["format"] = DotMapTerrain.FORMAT + 1
	_check(DotMapTerrain.from_dict(newer).code() == DotError.CODE_VERSION, "a newer format is refused as a version error")
	var broken: Dictionary = fx["terrain"].duplicate()
	broken["bytes"] = 1
	_check(DotMapTerrain.from_dict(broken).code() == DotError.CODE_PARSE, "a wrong size is refused as a parse error")
	_done()


func _test_lightmap() -> DotMapBspMesh:
	_section("lightmap: a v2 surface with a second UV set, an atlas page and an ambient cube")
	# one triangle, positions then normals then uv then uv2 then indices, then a 2x1 RGB9E5 page, then one ambient sample
	var blob := PackedByteArray()
	var pos := PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)])
	var nor := PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP])
	var uv := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)])
	var uv2 := PackedVector2Array([Vector2(0.25, 0.5), Vector2(0.75, 0.5), Vector2(0.25, 0.5)])
	var offs := []
	for a: PackedByteArray in [pos.to_byte_array(), nor.to_byte_array(), uv.to_byte_array(), uv2.to_byte_array(),
			PackedInt32Array([0, 1, 2]).to_byte_array()]:
		offs.append(blob.size())
		blob.append_array(a)
	var page_at := blob.size()
	# 1.0 white: mantissa 256 at exponent 15 + 1 - 9 + ... = (256 * 2^-8) -> shared exponent field 16 holds 2^(16-15-9)*256 = 1.0
	var texel := 256 | (256 << 9) | (256 << 18) | (16 << 27)
	var page := PackedByteArray()
	page.resize(8)
	page.encode_u32(0, texel)
	page.encode_u32(4, texel)
	blob.append_array(page)
	var amb_at := blob.size()
	var cube := PackedFloat32Array([1, 2, 3])
	for face in 6:
		cube.append_array(PackedFloat32Array([0.1 * (face + 1), 0.0, 0.0]))
	blob.append_array(cube.to_byte_array())
	var doc := {"format": "dot-bsp-mesh", "version": 2, "bin": {"bytes": blob.size()},
			"lightmap": {"format": "rgbe9995", "scale": 1.0, "pages": [{"offset": page_at, "width": 2, "height": 1}],
					"ambient": {"offset": amb_at, "count": 1}},
			"surfaces": [{"model": 0, "material": "m", "vertex_count": 3, "position_offset": offs[0], "normal_offset": offs[1],
					"uv_offset": offs[2], "uv2_offset": offs[3], "index_offset": offs[4], "index_count": 3,
					"lightmap_page": 0}], "hulls": []}
	var r := DotMapBspMesh.from_data(doc, blob)
	_check(r.ok, "a v2 map loads: %s" % (r.error if not r.ok else ""))
	var w: DotMapBspMesh = r.value
	_check(w.has_lightmap() and w.lightmap_page(1) == null, "it has a lightmap, one page")
	var tex := w.lightmap_page(0)
	_check(tex != null and tex.get_width() == 2 and tex.get_height() == 1, "the page is a 2x1 texture")
	_check(tex.get_image().get_format() == Image.FORMAT_RGBE9995, "stored as RGB9E5")
	_check(tex.get_image().get_pixel(0, 0).is_equal_approx(Color(1, 1, 1)), "the white texel reads as 1.0: %s" % tex.get_image().get_pixel(0, 0))
	var a := w.surface_arrays(doc["surfaces"][0])
	_check((a[Mesh.ARRAY_TEX_UV2] as PackedVector2Array)[1].is_equal_approx(Vector2(0.75, 0.5)), "the second UV set is read")
	var bad := doc.duplicate(true)
	(bad["surfaces"][0] as Dictionary)["uv2_offset"] = blob.size()
	_check(not DotMapBspMesh.from_data(bad, blob).ok, "a uv2 block past the data is refused")
	var built := w.build_meshes(0)
	var arrays: Array = (built[0]["mesh"] as ArrayMesh).surface_get_arrays(0)
	_check(built.size() == 1 and arrays[Mesh.ARRAY_TEX_UV2] != null, "the built mesh keeps UV2")
	_check(w.ambient_at(Vector3(1, 2, 3), Vector3.UP).is_equal_approx(Color(0.3, 0, 0)), "ambient: the +y face for an up normal: %s" % w.ambient_at(Vector3(1, 2, 3), Vector3.UP))
	_check(w.ambient_at(Vector3(1, 2, 3), Vector3.DOWN).is_equal_approx(Color(0.4, 0, 0)), "ambient: the -y face for a down normal")
	_done()
	return w


func _test_drawn(world: DotMapBspMesh, lit_world: DotMapBspMesh) -> void:
	_section("drawn world: model 0 only, moved into a game's frame, lit by the bake")
	var host := Node3D.new()
	add_child(host)
	var at := Transform3D(Basis.IDENTITY, Vector3(10, 0, 5))
	var drawn := DotMapDrawnWorld.attach(host, world, {"transform": at, "probes": 0, "cull": false})
	_check(drawn.root != null and drawn.root.name == "World" and drawn.root.get_parent() == host, "the node is World under the host")
	var names := drawn.root.get_children().map(func(c: Node) -> String: return String(c.name))
	_check(names == ["world"], "only the world model is drawn, no brush entity: %s" % [names])
	var chunk := drawn.root.get_node("world").get_child(0) as MeshInstance3D
	var box := chunk.global_transform * chunk.get_aabb()
	_check(is_equal_approx(box.position.x, chunk.get_aabb().position.x + 10.0), "the meshes are drawn in the game's frame: %s" % box)
	var all := DotMapDrawnWorld.attach(host, world, {"only_world": false, "probes": 0, "cull": false})
	_check(all.root.get_child_count() == 2, "only_world off keeps the door")
	var env := Environment.new()
	var lamp := OmniLight3D.new()
	host.add_child(lamp)
	var lit := DotMapDrawnWorld.attach(host, lit_world, {"transform": at, "environment": env, "lamps": [lamp], "probes": 0, "cull": false})
	_check(lit.lit != null and lit.lit.frame == lit.root, "a lightmapped world gets the ambient driver, in the drawn node's frame")
	_check(lamp.is_queued_for_deletion(), "the lamps the bake holds are freed")
	drawn.detach()
	_check(drawn.root == null and not is_instance_valid(drawn.lit), "detach lets go of the node")
	host.queue_free()
	_done()
