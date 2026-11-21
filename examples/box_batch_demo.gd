extends Node3D

## [DotMapBoxBatch]: the draw budget. Boxes of one material in one cell fold into one mesh,
## nothing a player touches changes, and the see-through, vetoed and lone boxes stay as they were.
##
## [codeblock]
## godot --headless --path . res://examples/box_batch_demo.tscn
## [/codeblock]

const CHECKS := 13

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		_failures.append(what)


func _material(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	if colour.a < 0.999:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _box(parent: Node3D, at: Vector3, size: Vector3, material: Material, tag: StringName = &"") -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = material
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	if tag != &"":
		body.set_meta(tag, true)
	parent.add_child(body)
	return body


func _visible_meshes(root: Node) -> int:
	var n := 0
	for c in root.find_children("*", "MeshInstance3D", true, false):
		if (c as MeshInstance3D).is_visible_in_tree():
			n += 1
	return n


func _run() -> void:
	print("dot-map box batch")
	var floor_m := _material(Color(0.5, 0.5, 0.5))
	var red := _material(Color.RED)
	var glass := _material(Color(1, 0, 0, 0.25))
	var root := Node3D.new()
	add_child(root)
	for i in 40:
		_box(root, Vector3(i * 2.0, 1, 0), Vector3(1, 2, 1), floor_m)
	_box(root, Vector3(200, 1, 0), Vector3(1, 2, 1), floor_m)
	_box(root, Vector3(0, 1, 5), Vector3(1, 2, 1), red)
	_box(root, Vector3(2, 1, 5), Vector3(1, 2, 1), glass)
	_box(root, Vector3(4, 1, 5), Vector3(1, 2, 1), floor_m, &"breakable")
	var before := _visible_meshes(root)
	_check(before == 44, "44 boxes draw 44 meshes before batching (%d)" % before)
	var skip := func(body: Node3D, _mi: MeshInstance3D) -> bool: return body.has_meta(&"breakable")
	var headless := DotMapBoxBatch.build(root, DotMapBoxBatch.CELL, skip)
	_check(int(headless["boxes"]) == 0 and _visible_meshes(root) == before, "headless: nothing folds unless forced (%s)" % [headless])
	var got := DotMapBoxBatch.build(root, DotMapBoxBatch.CELL, skip, true)
	var after := _visible_meshes(root)
	_check(int(got["boxes"]) == 40, "the 40 opaque floor boxes of two cells fold (%s)" % [got])
	_check(after < before / 2, "the draws fall by more than half (%d -> %d)" % [before, after])
	_check(after == 6, "two floor cells, the far box, the lone red, the see-through and the vetoed one (%d)" % after)
	var bodies := 0
	var shapes := 0
	for c in root.get_children():
		if c is StaticBody3D:
			bodies += 1
			for p in c.get_children():
				if p is CollisionShape3D:
					shapes += 1
	_check(bodies == 44 and shapes == 44, "every box keeps its body and shape (%d, %d)" % [bodies, shapes])
	var holder: Node = root.get_node(DotMapBoxBatch.NODE_NAME)
	var merged: MeshInstance3D = holder.get_child(0)
	var aabb := merged.mesh.get_aabb()
	_check(aabb.size.x > 60.0 and aabb.size.x < 90.0, "a cell's mesh spans its boxes (%s)" % [aabb.size])
	_check(merged.mesh is ArrayMesh and merged.mesh.surface_get_material(0) == floor_m, "an ArrayMesh with the shared material")
	_check(merged.mesh.get_faces().size() % 36 == 0 and merged.mesh.get_faces().size() > 0, "the merged mesh is whole boxes")
	var again := DotMapBoxBatch.build(root, DotMapBoxBatch.CELL, skip, true)
	_check(int(again["boxes"]) == 0 and _visible_meshes(root) == after, "a second pass folds nothing")
	# A rotated, offset box lands where the original drew.
	var r := Node3D.new()
	add_child(r)
	for k in 2:
		var b := _box(r, Vector3(10 + k * 3, 1, 10), Vector3(1, 2, 3), floor_m)
		b.rotation.y = 0.5
	var lone := r.get_child(0) as Node3D
	var orig_box := (lone.get_child(0) as MeshInstance3D).mesh.get_aabb()
	var want := lone.transform * orig_box
	DotMapBoxBatch.build(r, DotMapBoxBatch.CELL, Callable(), true)
	var folded := (r.get_node(DotMapBoxBatch.NODE_NAME).get_child(0) as MeshInstance3D).mesh.get_aabb()
	_check(folded.encloses(want.grow(-0.01)), "a rotated box is folded in place")
	var shown := DotMapBoxBatch.undo(r)
	_check(shown == 2 and _visible_meshes(r) == 2 and not r.has_node(DotMapBoxBatch.NODE_NAME), "undo shows the originals and frees the merge (%d)" % shown)
	var big := Node3D.new()
	add_child(big)
	for k in 3:
		_box(big, Vector3(k * 500, 1, 0), Vector3(1, 1, 1), floor_m)
	var one := DotMapBoxBatch.build(big, 0.0, Callable(), true)
	_check(int(one["nodes"]) == 1 and int(one["boxes"]) == 3, "cell 0 folds a material into one mesh (%s)" % [one])
	root.queue_free()
	r.queue_free()
	big.queue_free()
	print("")
	print("%d passed, %d failed" % [_passed, _failed])
	for line in _failures:
		print("  FAIL  %s" % line)
	if _passed + _failed != CHECKS:
		print("ERROR: %d checks ran; %d expected." % [_passed + _failed, CHECKS])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)
