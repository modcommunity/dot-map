extends Node3D

## Renders one frame of a converted map the way a game would dress it: free photo and generated
## textures, the environment, the stand-in props. Run it under a display (tools/screenshot.sh).
##
##   godot --path . res://examples/bsp_world_shot.tscn -- --world=<prefix> --out=<png> [--cam=x,y,z --look=x,y,z]

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
	add_child(world.build_node(mat_for))
	var env := world.build_environment()
	if env != null:
		add_child(env)
	add_child(world.build_props())
	add_child(world.build_sounds())
	var movers: Array = world.manifest.get("movers", [])
	var o := func(i: int) -> Vector3:
		var p: Array = movers[mini(i, movers.size() - 1)].get("origin", [0, 0, 0])
		return Vector3(p[0], p[1], p[2])
	var cam := Camera3D.new()
	var from: Vector3 = o.call(0) + Vector3(0, 1.6, 0)
	var look: Vector3 = o.call(movers.size() / 2) + Vector3(0, 1.4, 0)
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
