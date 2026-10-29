extends Node3D

## Builds a converted map the way a game does and prints where its texture memory goes: the renderer's own counters, then every
## texture reached from the scene by category (CPU image bytes, format, mips). tools/texture_audit.sh runs it under a display.
##   -- --world=<prefix> [--cap=<model texture px, default 0 = own size>] [--nomodels] [--half=0|1]

var _seen := {}
var _rows := {}


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	DotMapBspMesh.model_texture_max = int(args.get("cap", 0))
	var res := DotMapBspMesh.load_prefix(str(args.get("world", "")))
	if not res.ok:
		printerr("cannot load: ", res.error)
		get_tree().quit(2)
		return
	var world: DotMapBspMesh = res.value
	if args.has("nomodels"):
		world.model_library = "/nonexistent"
	var t0 := Time.get_ticks_msec()
	var surfaces := DotMapSurfaces.new()
	if args.has("half"):
		surfaces.half_res_masks = args["half"] != "0"
	var built := DotMapWorld.build(world, {"material_for": surfaces.world_material_for(world, str(args["world"]).get_base_dir())})
	if not built.ok:
		printerr("cannot build: ", built.error)
		get_tree().quit(3)
		return
	add_child(built.value)
	print("build %d ms" % (Time.get_ticks_msec() - t0))
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	for i in 6:
		await get_tree().process_frame
	_walk(built.value)
	var env := (built.value as Node).find_children("*", "WorldEnvironment", true, false)
	for we in env:
		_environment((we as WorldEnvironment).environment)
	_report()
	get_tree().quit(0)


func _walk(n: Node) -> void:
	if n is GeometryInstance3D:
		var gi := n as GeometryInstance3D
		var group := _group(n)
		for m: Material in [gi.material_override, gi.material_overlay]:
			_material(m, group)
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mesh := (n as MeshInstance3D).mesh
			for i in mesh.get_surface_count():
				_material(mesh.surface_get_material(i), group)
	for c in n.get_children():
		_walk(c)


func _group(n: Node) -> String:
	var s := str(n.name).to_lower()
	if s.begins_with("sky"):
		return "sky"
	var p := n
	while p != null:
		var nm := str(p.name).to_lower()
		if nm.contains("prop") or nm.contains("model") or nm.contains("lib"):
			return "model"
		p = p.get_parent()
	return "world"


func _material(m: Material, group: String) -> void:
	if m == null:
		return
	if m is BaseMaterial3D:
		for slot in BaseMaterial3D.TEXTURE_MAX:
			var t := (m as BaseMaterial3D).get_texture(slot as BaseMaterial3D.TextureParam)
			if t != null:
				_texture(t, "%s/std slot %d" % [group, slot])
	elif m is ShaderMaterial:
		var sm := m as ShaderMaterial
		for p in sm.shader.get_shader_uniform_list():
			var v: Variant = sm.get_shader_parameter(p["name"])
			if v is Texture2D:
				_texture(v, "%s/%s" % [group, p["name"]])


func _environment(e: Environment) -> void:
	if e != null and e.sky != null and e.sky.sky_material is PanoramaSkyMaterial:
		_texture((e.sky.sky_material as PanoramaSkyMaterial).panorama, "sky/panorama")


func _texture(t: Texture2D, cat: String) -> void:
	var id := t.get_instance_id()
	if _seen.has(id):
		return
	_seen[id] = true
	var img := t.get_image()
	var bytes := 0
	var fmt := "none"
	var mips := false
	if img != null:
		bytes = img.get_data().size()
		fmt = _fmt(img.get_format())
		mips = img.has_mipmaps()
	var key := "%s | %s | %s%s" % [cat, t.get_class(), fmt, "" if mips else " nomips"]
	var r: Array = _rows.get(key, [0, 0])
	r[0] += 1
	r[1] += bytes
	_rows[key] = r


func _fmt(f: int) -> String:
	for k in ClassDB.class_get_enum_constants("Image", "Format"):
		if ClassDB.class_get_integer_constant("Image", k) == f:
			return k.trim_prefix("FORMAT_")
	return str(f)


func _report() -> void:
	var mb := 1048576.0
	print("RenderingServer texture mem %.1f MB, buffer mem %.1f MB, video mem %.1f MB" % [
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / mb,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED) / mb,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / mb])
	print("Performance texture mem %.1f MB, static mem %.1f MB, RSS %d MB" % [
			Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / mb,
			Performance.get_monitor(Performance.MEMORY_STATIC) / mb, _rss_mb()])
	var keys := _rows.keys()
	keys.sort_custom(func(a, b): return _rows[a][1] > _rows[b][1])
	var total := 0
	for k in keys:
		total += _rows[k][1]
		print("AUDIT %8.1f MB  %5d tex  %s" % [_rows[k][1] / mb, _rows[k][0], k])
	print("AUDIT total reached CPU image bytes %.1f MB in %d textures" % [total / mb, _seen.size()])


func _rss_mb() -> int:
	var f := FileAccess.open("/proc/self/status", FileAccess.READ)
	while f != null and not f.eof_reached():
		var line := f.get_line()
		if line.begins_with("VmRSS:"):
			return int(line.get_slice(":", 1).strip_edges().split(" ")[0]) / 1024
	return -1
