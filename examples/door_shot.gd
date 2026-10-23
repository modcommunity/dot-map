extends Node3D

## Frames of one prop_door_rotating of a converted map: closed, then half open for an opener on each side, from above and
## from the opener's eye. Run under a display (tools/door_shot.sh).
##
##   godot --path . res://examples/door_shot.tscn -- --world=<prefix> --entity=<index> --out=<png prefix>


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var res := DotMapBspMesh.load_prefix(str(args.get("world", "")))
	if not res.ok:
		printerr("cannot load: ", res.error)
		get_tree().quit(2)
		return
	var world: DotMapBspMesh = res.value
	var mat_for := DotMapSurfaces.new().world_material_for(world, str(args["world"]).get_base_dir())
	var built := DotMapWorld.build(world, {"material_for": mat_for})
	if not built.ok:
		printerr("cannot build the world: ", built.error)
		get_tree().quit(3)
		return
	var dw: DotMapWorld = built.value
	add_child(dw)
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.environment.ambient_light_color = Color(0.9, 0.9, 0.95)
	we.environment.background_mode = Environment.BG_COLOR
	we.environment.background_color = Color(0.5, 0.6, 0.75)
	add_child(we)
	var entity := int(args.get("entity", -1))
	var door: Node3D = dw.visual.find_child("Door_%d" % entity, true, false)
	var mover: DotMapMover = null
	for m: DotMapMover in DotMapEntities.from_manifest(world.manifest).movers:
		if m.entity == entity:
			mover = m
	var e := dw.io.entity_of(entity) as DotMapMoverNode
	if door == null or mover == null or e == null:
		printerr("no door for entity %d" % entity)
		get_tree().quit(4)
		return
	var cam := Camera3D.new()
	cam.far = 200.0
	cam.fov = 60.0
	add_child(cam)
	cam.make_current()
	# the hinge the converter chose, as a green post
	var post := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.03
	cyl.bottom_radius = 0.03
	cyl.height = 2.3
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.1, 1.0, 0.1)
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cyl.material = pm
	post.mesh = cyl
	post.position = mover.origin + Vector3(0, 1.15, 0)
	add_child(post)
	var front := Basis(Vector3.UP, deg_to_rad(mover.yaw)) * Vector3.RIGHT
	var centre := door.global_transform * (door.get_node("Panel") as Node3D).position
	var out := str(args.get("out", "user://door"))
	await _shoot(cam, centre + Vector3(0, 4.0, 0.01), centre, out + "_closed_top.png")
	for side in [["A", 1.0], ["B", -1.0]]:
		var eye: Vector3 = mover.origin + front * (1.4 * side[1]) + Vector3(0, 1.6, 0)
		var opener: Vector3 = mover.origin + front * (1.0 * side[1])
		var half := int(mover.travel_time * dw.io.rate * 0.5)
		e.accept(dw.io, "Close", "", null, null)
		dw.io.advance(int(mover.travel_time * dw.io.rate) + 5)
		await _shoot(cam, eye, centre, "%s_closed_eye%s.png" % [out, side[0]])
		e.accept(dw.io, "Open", "", opener, null)
		dw.io.advance(half)
		await _shoot(cam, centre + Vector3(0, 4.0, 0.01), centre, "%s_open%s_top.png" % [out, side[0]])
		await _shoot(cam, eye, centre, "%s_open%s_eye.png" % [out, side[0]])
		print("side %s: opener %s, panel rotation %.1f deg" % [side[0], opener, rad_to_deg(door.rotation.y) - mover.yaw])
	get_tree().quit(0)


func _shoot(cam: Camera3D, from: Vector3, look: Vector3, path: String) -> void:
	cam.position = from
	# from above, the near plane cuts the ceiling away (everything higher than 1.2 m over the panel's middle)
	cam.near = 2.8 if from.y > look.y + 2.0 else 0.05
	cam.look_at(look)
	for i in 6:
		await get_tree().process_frame
	var err := get_viewport().get_texture().get_image().save_png(path)
	print("saved %s (%s)" % [path, error_string(err)])
