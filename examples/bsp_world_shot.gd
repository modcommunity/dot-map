extends Node3D

## Renders one frame of a converted map the way a game would dress it: free photo and generated
## textures, the environment, the stand-in props. Run it under a display (tools/screenshot.sh).
##
##   godot --path . res://examples/bsp_world_shot.tscn -- --world=<prefix> --out=<png> [--view=spawn|overview] [--cam=x,y,z --look=x,y,z]

var _out := "user://shot.png"


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_out = str(args.get("out", _out))
	var res := DotMapBspMesh.load_prefix(str(args.get("world", "")))
	if not res.ok:
		printerr("cannot load: ", res.error)
		get_tree().quit(2)
		return
	var world: DotMapBspMesh = res.value
	print(world.describe_lines())
	print("free: %s, props: %d, ambient sounds: %d" % [world.is_free(), world.manifest.get("props", []).size(),
			world.sounds_data().get("ambient", []).size()])
	var dir := str(args["world"]).get_base_dir()
	var surfaces := DotMapSurfaces.new()
	var generated := {}
	for t: Dictionary in world.licence().get("textures", []):
		if str(t["kind"]) == "generated":
			generated[str(t["key"])] = dir.path_join(str(t["file"]))
	var cache := {}
	var mat_for := func(rec: Dictionary) -> Material:
		var key := str(rec.get("free", ""))
		if cache.has(key):
			return cache[key]
		var m: Material
		if generated.has(key):
			var sm := StandardMaterial3D.new()
			sm.albedo_texture = ImageTexture.create_from_image(Image.load_from_file(generated[key]))
			sm.uv1_triplanar = true
			sm.uv1_world_triplanar = true
			sm.uv1_scale = Vector3.ONE * 0.4
			m = sm
		else:
			m = surfaces.material(StringName(key.get_slice(":", 0)))
		cache[key] = m
		return m
	var env := world.build_environment()
	if env != null:
		add_child(env)
	add_child(world.build_props())
	add_child(world.build_sounds())
	var node := world.build_node(mat_for)
	add_child(node)
	var cam := Camera3D.new()
	var view := _default_view(world, node, str(args.get("view", "")))
	var from: Vector3 = view[0]
	var look: Vector3 = view[1]
	if args.has("cam"):
		var c := str(args["cam"]).split_floats(",")
		from = Vector3(c[0], c[1], c[2])
	if args.has("look"):
		var l := str(args["look"]).split_floats(",")
		look = Vector3(l[0], l[1], l[2])
	add_child(cam)
	cam.far = 300.0
	cam.position = from
	cam.look_at(look)
	cam.make_current()
	for i in 12:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(_out)
	print("saved %s (%s) from %s to %s" % [_out, error_string(err), from, look])
	get_tree().quit(0 if err == OK else 1)


## The camera when none is given: at the first player spawn looking at the map centre (the small sky model is not part of the map), or when the
## map has none (or --view=overview) from above one corner of the bounding box, looking down at the centre.
func _default_view(world: DotMapBspMesh, node: Node3D, view: String) -> Array:
	var box := AABB()
	var first := true
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		if mi.name.begins_with("sky3d"):
			continue
		var b: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	var centre := box.get_center()
	if view != "overview":
		for e: Dictionary in world.manifest.get("entities", []):
			if str(e.get("classname", "")).begins_with("info_player") and e.has("origin"):
				var p: Array = e["origin"]
				var eye := Vector3(p[0], p[1] + 1.6, p[2])
				return [eye, Vector3(centre.x, eye.y, centre.z)]
	var r := maxf(box.size.x, box.size.z)
	var from := centre + Vector3(r * 0.45, maxf(box.size.y, r * 0.7), r * 0.45)
	return [from, centre]
