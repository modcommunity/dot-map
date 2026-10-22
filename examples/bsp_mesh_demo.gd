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

const CHECKS := 38
const SECTIONS := 4
const FIXTURE := "res://examples/bsp_mesh/fixture"
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
	_check(w != null and w.get_child_count() == 2, "the world is two chunks: %s" % [w.get_children() if w else "none"])
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
	snd.free()
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
