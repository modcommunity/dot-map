extends Node3D

## Culling without BSP: [DotOccluderBaker] and [DotAreaPortal] on a hand-made level of eight rooms in a row.
##
## [codeblock]
## godot --headless --path . res://examples/culling_demo.tscn
## godot --path . res://examples/culling_demo.tscn -- --shot=<dir> [--size=1280x720]   # under a display: frames and draw calls
## [/codeblock]

const CHECKS := 28
const ROOMS := 8
const ROOM := Vector3(10, 4, 10)

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()
var _entered := 0
var _completed := 0
var _level: Node3D
var _portals: Array[DotAreaPortal] = []


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("dot-map culling")
	_level = _build_level()
	add_child(_level)
	var shot := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot = a.substr(7)
	_test_baker()
	_test_portal()
	_test_binding()
	_test_roundtrip()
	if not shot.is_empty():
		await _shoot(shot)
	print("")
	print("%d passed, %d failed" % [_passed, _failed])
	for line in _failures:
		print("  FAIL  %s" % line)
	print("%d of %d sections ran to their last line" % [_completed, _entered])
	if _entered != 4 or _completed != _entered or _passed + _failed != CHECKS:
		print("ERROR: %d sections, %d checks ran; 4 and %d expected." % [_entered, _passed + _failed, CHECKS])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		_failures.append(what)


func _box(parent: Node3D, pos: Vector3, size: Vector3, nm: String) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.position = pos
	m.name = nm
	parent.add_child(m)
	return m


## Rooms along -Z, each with a floor, ceiling, side walls and a divider whose doorway alternates sides.
func _build_level() -> Node3D:
	var level := Node3D.new()
	level.name = "Level"
	for r in ROOMS:
		var z := -r * ROOM.z
		_box(level, Vector3(0, -0.25, z), Vector3(ROOM.x, 0.5, ROOM.z), "Floor%d" % r)
		_box(level, Vector3(0, ROOM.y + 0.25, z), Vector3(ROOM.x, 0.5, ROOM.z), "Ceiling%d" % r)
		_box(level, Vector3(-ROOM.x / 2 - 0.25, ROOM.y / 2, z), Vector3(0.5, ROOM.y, ROOM.z), "WallW%d" % r)
		_box(level, Vector3(ROOM.x / 2 + 0.25, ROOM.y / 2, z), Vector3(0.5, ROOM.y, ROOM.z), "WallE%d" % r)
		var c := -3.0 if r % 2 == 0 else 3.0
		var dz := z - ROOM.z / 2
		_box(level, Vector3((-5.0 + c - 1.0) / 2, ROOM.y / 2, dz), Vector3(c + 4.0, ROOM.y, 0.4), "DividerA%d" % r)
		_box(level, Vector3((c + 1.0 + 5.0) / 2, ROOM.y / 2, dz), Vector3(4.0 - c, ROOM.y, 0.4), "DividerB%d" % r)
		var portal := DotAreaPortal.new()
		portal.size = Vector3(2, 3, 0.2)
		portal.position = Vector3(c, 1.5, dz)
		portal.name = "Portal%d" % r
		level.add_child(portal)
		portal.owner = level
		_portals.append(portal)
		for i in 30:
			var p := _box(level, Vector3(-4 + (i % 6) * 1.6, 0.4, z - 4 + (i / 6) * 1.8), Vector3(0.6, 0.8, 0.6), "Prop%d_%d" % [r, i])
			p.mesh = (p.mesh as BoxMesh).duplicate()
	_add_decoys(level)
	return level


## Things the baker must leave alone: a wall with a big doorway in one mesh, glass, an opted-out slab, a hidden slab.
func _add_decoys(level: Node3D) -> void:
	var holed := MeshInstance3D.new()
	holed.name = "HoledWall"
	var v := PackedVector3Array()
	var idx := PackedInt32Array()
	for r: Rect2 in [Rect2(-5, 0, 3, 4), Rect2(2, 0, 3, 4), Rect2(-2, 3, 4, 1), Rect2(-2, 0, 4, 0.0)]:
		if r.size.y <= 0.0:
			continue
		var b := v.size()
		v.append_array(PackedVector3Array([Vector3(r.position.x, r.position.y, 0), Vector3(r.end.x, r.position.y, 0),
				Vector3(r.end.x, r.end.y, 0), Vector3(r.position.x, r.end.y, 0)]))
		idx.append_array(PackedInt32Array([b, b + 1, b + 2, b, b + 2, b + 3]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	holed.mesh = mesh
	holed.position = Vector3(0, 0, -ROOMS * ROOM.z - 2)
	level.add_child(holed)
	var glass := _box(level, Vector3(30, 2, 0), Vector3(10, 4, 0.5), "GlassSlab")
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.material_override = mat
	_box(level, Vector3(40, 2, 0), Vector3(10, 4, 0.5), "OptedOutSlab").add_to_group(DotOccluderBaker.SKIP_GROUP)
	_box(level, Vector3(50, 2, 0), Vector3(10, 4, 0.5), "HiddenSlab").visible = false


func _test_baker() -> void:
	_entered += 1
	print("  baker: walls, floors and ceilings become quads; doorways, glass and opt-outs do not")
	var baker := DotOccluderBaker.new()
	var res := baker.bake(_level)
	_check(res.ok, "bake succeeds on the level")
	_check(baker.stats["quads"] == 80, "80 quads: 10 per room (%s)" % [baker.stats])
	_check(baker.stats["meshes"] == ROOMS * 36 + 1, "glass, opted-out and hidden meshes are not even read (%s)" % [baker.stats])
	var node := _level.get_node_or_null(DotOccluderBaker.NODE_NAME) as OccluderInstance3D
	_check(node != null and node.occluder is ArrayOccluder3D, "one OccluderInstance3D with an ArrayOccluder3D")
	var occ := node.occluder as ArrayOccluder3D
	_check(occ.vertices.size() == 80 * 4 and occ.indices.size() == 80 * 6, "four vertices and six indices per quad")
	var floor_quad := false
	var outside := 0
	var box := AABB(Vector3(-5.6, -0.5, -ROOMS * ROOM.z), Vector3(11.2, 5.5, ROOMS * ROOM.z + 5))
	for p in occ.vertices:
		if not box.has_point(p):
			outside += 1
		if is_equal_approx(p.y, 0.0) and absf(p.x) > 4.9:
			floor_quad = true
	_check(outside == 0, "no quad leaves the rooms")
	_check(floor_quad, "the floor's top face reaches within 4 cm of the walls (inset)")
	var again := DotOccluderBaker.new().bake(_level)
	var count := 0
	for ch in _level.get_children():
		if ch.name.begins_with(DotOccluderBaker.NODE_NAME):
			count += 1
	_check(again.ok and count == 1, "baking again replaces the node (%d)" % count)
	var strict := DotOccluderBaker.new()
	strict.min_area = 1000.0
	var none := strict.bake(_level)
	_check(not none.ok and none.code() == DotError.CODE_INVALID, "nothing large enough fails with CODE_INVALID, not an empty node")
	_check(_level.get_node_or_null(DotOccluderBaker.NODE_NAME) == null, "a failed bake leaves no node behind")
	var capped := DotOccluderBaker.new()
	capped.max_quads = 10
	capped.bake(_level)
	_check(capped.stats["quads"] == 10, "max_quads keeps the largest 10")
	_check(DotOccluderBaker.new().bake(_level).ok, "restored the full bake")
	_completed += 1


func _test_portal() -> void:
	_entered += 1
	print("  portal: closed blocks, open lets the view through, one signal per change")
	var p := _portals[0]
	var seen: Array[bool] = []
	p.toggled.connect(func(o: bool) -> void: seen.append(o))
	_check(not p.open and p.is_blocking(), "a new portal is closed and blocks")
	p.set_open(true)
	_check(p.open and not p.is_blocking(), "set_open(true) stops blocking")
	p.set_open(true)
	_check(seen == [true], "setting the same state emits nothing (%s)" % [seen])
	p.set_open(false)
	_check(p.is_blocking() and seen == [true, false], "closing blocks again and emits false")
	p.size = Vector3(-1, 0, 0)
	_check(p.size.x > 0.0 and p.size.y > 0.0, "a non-positive size is clamped")
	p.size = Vector3(2, 3, 0.2)
	_check(p.is_in_group(DotAreaPortal.GROUP), "portals are found by group")
	_completed += 1


## A map with one area portal, key 5, door "door": cluster 0 sees cluster 1 only while it is open.
func _test_binding() -> void:
	_entered += 1
	print("  binding: DotMapVisibility follows the portals under a node")
	var m := DotMapBspMesh.new()
	var blob := PackedByteArray()
	var vis := {"clusters": 3, "head": 0, "portals": [[5, 1, 2]],
			"portal_entities": [{"key": 5, "target": "door", "start_open": false, "window": false}]}
	var put := func(key: String, bytes: PackedByteArray, count: int) -> void:
		vis[key] = {"offset": blob.size(), "count": count}
		blob.append_array(bytes)
	put.call("planes", PackedFloat32Array([1, 0, 0, 0, 1, 0, 0, 10, 1, 0, 0, 20]).to_byte_array(), 3)
	put.call("nodes", PackedInt32Array([0, 1, -2, 1, 2, -1, 2, -4, -3]).to_byte_array(), 3)
	put.call("leaf_cluster", PackedInt32Array([0, 1, -1, 2]).to_byte_array(), 4)
	put.call("cluster_area", PackedInt32Array([1, 2, 3]).to_byte_array(), 3)
	put.call("pvs_offsets", PackedInt32Array([0, 1, 2]).to_byte_array(), 3)
	put.call("pvs", PackedByteArray([3, 3, 4]), 3)
	m.manifest = {"vis": vis}
	m._blob = blob
	var drawn := Node3D.new()
	add_child(drawn)
	var far := Node3D.new()
	far.set_meta(&"vis_clusters", PackedInt32Array([1]))
	drawn.add_child(far)
	var dv := DotMapVisibility.new()
	dv.run_headless = true
	dv.margin = 0.5
	add_child(dv)
	_check(dv.setup(m, drawn).ok, "setup on the two-room map")
	var bound := Node3D.new()
	add_child(bound)
	var door := DotAreaPortal.new()
	door.door = "door"
	bound.add_child(door)
	var unkeyed := DotAreaPortal.new()
	bound.add_child(unkeyed)
	_check(dv.bind_area_portals(bound) == 1, "only the portal with a key or door is bound")
	dv.update_from(Vector3(5, 0, 0))
	_check(not far.visible, "binding applies the portal's closed state at once")
	door.set_open(true)
	dv.update_from(Vector3(5.1, 0, 0))
	dv.update_from(Vector3(5, 0, 0))
	_check(far.visible, "an open door still shows the next room")
	door.set_open(false)
	dv.update_from(Vector3(6, 0, 0))
	_check(not far.visible, "closing the node hides the room behind the BSP portal")
	door.set_open(true)
	dv.update_from(Vector3(5, 0, 0))
	_check(far.visible, "opening it shows the room again")
	dv.queue_free()
	drawn.queue_free()
	bound.queue_free()
	_completed += 1


func _test_roundtrip() -> void:
	_entered += 1
	print("  saving: a baked scene keeps its occluder")
	var scene := PackedScene.new()
	_check(scene.pack(_level) == OK, "the baked level packs")
	var path := "user://culling_demo_level.tscn"
	_check(ResourceSaver.save(scene, path) == OK, "and saves")
	var copy := (load(path) as PackedScene).instantiate()
	var node := copy.get_node_or_null(DotOccluderBaker.NODE_NAME) as OccluderInstance3D
	_check(node != null and (node.occluder as ArrayOccluder3D).vertices.size() == 320, "the loaded copy has all 320 vertices")
	_check(copy.find_children("*", "DotAreaPortal", true, false).size() == ROOMS, "and every portal")
	copy.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_completed += 1


## Draw calls with nothing, the baked occluders, and the occluders plus every door shut; one frame each.
func _shoot(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().use_occlusion_culling = true
	var cam := Camera3D.new()
	cam.fov = 80.0
	cam.position = Vector3(0, 1.7, 3.5)
	cam.rotation_degrees = Vector3(-4, 0, 0)
	add_child(cam)
	cam.make_current()
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 20, 0)
	add_child(sun)
	var occ := _level.get_node(DotOccluderBaker.NODE_NAME) as OccluderInstance3D
	var baked := occ.occluder
	for portal in _portals:
		portal.set_open(true)
	var lines: Array[String] = []
	for step: Array in [["before", false, true], ["occluders", true, true], ["occluders_and_doors", true, false]]:
		occ.occluder = baked if step[1] else null
		for portal in _portals:
			portal.set_open(step[2])
		for i in 8:
			await get_tree().process_frame
		var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		var objs := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
		lines.append("%s: %d draw calls, %d objects" % [step[0], draws, objs])
		get_viewport().get_texture().get_image().save_png("%s/culling_%s.png" % [dir, step[0]])
	for l in lines:
		print("SHOT ", l)
