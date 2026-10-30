extends Node3D

## Frames of a body riding a converted map's mover (scenario ride) or shoved by it (push): the real DotMapIO rules, a capsule
## standing in for the player. Run under a display (tools/ride_shot.sh). godot --path . res://examples/ride_shot.tscn --
## --world=<prefix> --entity=<index> --scenario=ride|push --out=<png prefix> [--frames=8] [--span=1.0]

const RADIUS := 0.4
const HEIGHT := 1.8


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var prefix := String(args.get("world", ""))
	var res := DotMapBspMesh.load_prefix(prefix)
	if not res.ok:
		printerr("cannot load: ", res.error)
		get_tree().quit(2)
		return
	var built := DotMapWorld.build(res.value, {"material_for": DotMapSurfaces.new().world_material_for(res.value, prefix.get_base_dir())})
	if not built.ok:
		printerr("cannot build: ", built.error)
		get_tree().quit(3)
		return
	var dw: DotMapWorld = built.value
	add_child(dw)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.environment.ambient_light_color = Color(0.8, 0.8, 0.9)
	add_child(we)
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var index := int(args.get("entity", 0))
	var mover := dw.io.entity_of(index) as DotMapMoverNode
	var box := _box_of(dw, mover)
	var scenario := String(args.get("scenario", "ride"))
	var feet := Vector3(box.get_center().x, box.end.y + 0.02, box.get_center().z)
	if scenario == "push":
		feet.y += 3.0
	var cap := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = RADIUS
	mesh.height = HEIGHT
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.15, 0.1)
	mesh.material = mat
	cap.mesh = mesh
	add_child(cap)
	var pos := [feet]
	dw.io.carry_fn = func(_b: Variant, v: Variant, _m: Variant) -> void: pos[0] = (pos[0] as Vector3) + (v as Vector3) / float(dw.io.rate)
	cap.position = feet + Vector3(0, HEIGHT * 0.5, 0)
	var frames := int(args.get("frames", 8))
	var span := float(args.get("span", 1.0))
	var ticks := int(span * dw.io.rate)
	var out := String(args.get("out", "user://ride"))
	var lift := absf(float(mover.mover.distance))
	cam.position = box.get_center() + Vector3(0, lift * 0.45, 0) + Vector3(lift * 1.6, 0, lift * 0.6)
	cam.look_at(box.get_center() + Vector3(0, lift * 0.45, 0))
	for _i in 30:
		dw.step([{"id": 1, "body": 1, "position": pos[0], "height": HEIGHT, "radius": RADIUS}])
	dw.io.send(mover.targetname, "Open")
	var y0: float = feet.y
	for t in ticks + 1:
		if t % maxi(1, ticks / frames) == 0:
			cap.position = (pos[0] as Vector3) + Vector3(0, HEIGHT * 0.5, 0)
			await _shoot("%s_%s_%02d.png" % [out, scenario, t / maxi(1, ticks / frames)])
			print("t=%.2f s body y=%.2f (+%.2f) platform at %.0f%%" % [float(t) / dw.io.rate, (pos[0] as Vector3).y, (pos[0] as Vector3).y - y0, 100.0 * mover.fraction_at(dw.io.now, dw.io.rate)])
		dw.step([{"id": 1, "body": 1, "position": pos[0], "height": HEIGHT, "radius": RADIUS}])
	get_tree().quit(0)


func _box_of(dw: DotMapWorld, mover: DotMapMoverNode) -> AABB:
	var box := AABB()
	var first := true
	for holder in dw.visual.get_children():
		if holder.has_meta(&"model") and str(mover.key("model")) == "*%d" % int(holder.get_meta(&"model")):
			for cs in holder.find_children("*", "CollisionShape3D", true, false):
				var b: AABB = (cs as CollisionShape3D).global_transform * (cs as CollisionShape3D).shape.get_debug_mesh().get_aabb()
				box = b if first else box.merge(b)
				first = false
	return box


func _shoot(path: String) -> void:
	for i in 4:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)
