extends Node3D

## Frames of the press-E prompt on a converted map: the eye on a button (prompt), then after the press. Run under a display
## (tools/use_shot.sh). godot --path . res://examples/use_shot.tscn -- --world=<prefix> --button=<index> --out=<png prefix>


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var prefix := ProjectSettings.globalize_path(str(args.get("world", "res://shotworld/surf_forbidden_ways_2nd/surf_forbidden_ways_2nd")))
	var res := DotMapBspMesh.load_prefix(prefix)
	if not res.ok:
		printerr("cannot load: ", res.error)
		get_tree().quit(2)
		return
	var mat_for := DotMapSurfaces.new().world_material_for(res.value, prefix.get_base_dir())
	var built := DotMapWorld.build(res.value, {"material_for": mat_for})
	if not built.ok:
		printerr("cannot build: ", built.error)
		get_tree().quit(3)
		return
	var dw: DotMapWorld = built.value
	add_child(dw)
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.environment.ambient_light_color = Color(0.9, 0.9, 0.95)
	add_child(we)
	var layer := CanvasLayer.new()
	add_child(layer)
	var prompt := DotMapUsePrompt.new()
	prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	prompt.position += Vector2(-120, 60)
	prompt.size = Vector2(240, 30)
	layer.add_child(prompt)
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var index := int(args.get("button", 39))
	var button := dw.io.entity_of(index) as DotMapMoverNode
	var use := DotMapUse.new(dw)
	var space := dw.get_world_3d().direct_space_state
	var box := AABB()
	var first := true
	for holder in dw.visual.get_children():
		if holder.has_meta(&"model") and button.key("model") == "*%d" % int(holder.get_meta(&"model")):
			for cs in holder.find_children("*", "CollisionShape3D", true, false):
				var b: AABB = (cs as CollisionShape3D).global_transform * (cs as CollisionShape3D).shape.get_debug_mesh().get_aabb()
				box = b if first else box.merge(b)
				first = false
	var centre := box.get_center()
	var out := str(args.get("out", "user://use"))
	for d: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var info := use.aim(space, centre + d * 1.2, -d)
		if not info.is_empty() and info["index"] == index:
			cam.position = centre + d * 1.2
			cam.look_at(centre)
			prompt.show_aim(info)
			await _shoot(out + "_prompt.png")
			print("prompt: ", prompt.text, " ", info["state"])
			var r := use.press(space, cam.position, -d, "p1")
			dw.io.advance(30)
			prompt.show_aim(use.aim(space, cam.position, -d))
			await _shoot(out + "_after.png")
			print("press ok=", r.ok, " state ", button.use_state(), " prompt visible ", prompt.visible)
			get_tree().quit(0)
			return
	printerr("no spot sees button ", index)
	get_tree().quit(4)


func _shoot(path: String) -> void:
	for i in 6:
		await get_tree().process_frame
	print("saved %s (%s)" % [path, error_string(get_viewport().get_texture().get_image().save_png(path))])
