extends Node3D

## Measures and compares DotMapVisibility on a real converted map, on a real GPU: draw calls, primitives and
## frame time with vis_mode off / pvs / occluders / both from characteristic spots, and every frame against the
## `off` frame pixel for pixel from random spots (a pixel that differs is a hole or a pop-in).
## Run under a display (../gpu.sh shot dot-map examples/vis_proof.sh ...):
##   godot --path . res://examples/vis_proof.tscn -- --world=<prefix> [--spots=6] [--diffs=24] [--out=<dir>] [--size=640x360]

const MODES := ["off", "pvs", "occluders", "both"]

var _args := {}
var _world: DotMapBspMesh
var _dw: DotMapWorld
var _vis: DotMapVisibility
var _cam: Camera3D
var _out := "user://vis_proof"


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_out = str(_args.get("out", _out))
	DirAccess.make_dir_recursive_absolute(_out)
	await _run()
	get_tree().quit()


func _run() -> void:
	var prefix := str(_args.get("world", ""))
	var res := DotMapBspMesh.load_prefix(prefix)
	if not res.ok:
		printerr("cannot load ", prefix)
		return
	_world = res.value
	var surfaces := DotMapSurfaces.new()
	var built := DotMapWorld.build(_world, {"material_for": surfaces.world_material_for(_world, prefix.get_base_dir())})
	_dw = built.value
	add_child(_dw)
	if _world.build_environment() == null:
		var we := WorldEnvironment.new()
		we.environment = Environment.new()
		we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		we.environment.ambient_light_color = Color(0.8, 0.8, 0.85)
		add_child(we)
	_vis = DotMapVisibility.new()
	_vis.chunk_view_distance = 0.0   # the fog's far cut is not what is under test
	_vis.camera_ref = null
	_vis.shadows = DotMapVisibility.Shadows.ALL if _args.has("keepshadows") else (DotMapVisibility.Shadows.NONE if _args.has("noshadows") else DotMapVisibility.Shadows.REACHING)
	add_child(_vis)
	var set_up := _vis.setup(_world, _dw.visual)
	if not set_up.ok:
		print("PROOF %s no visibility data" % prefix.get_file())
		return
	if _args.has("noglass"):
		for n in _dw.visual.find_children("glass_*", "MeshInstance3D", true, false):
			(n as Node3D).queue_free()
	var size := str(_args.get("size", "640x360")).split("x")
	get_window().size = Vector2i(int(size[0]), int(size[1]))
	get_viewport().size = Vector2i(int(size[0]), int(size[1]))
	_cam = Camera3D.new()
	_cam.far = 400.0
	_cam.current = true
	add_child(_cam)
	var spots := await _pick_spots(int(_args.get("spots", "6")), int(_args.get("diffs", "24")))
	var name := prefix.get_file()
	for s: Dictionary in spots["metric"]:
		var row := "PROOF %s spot=%s at=(%.0f,%.0f,%.0f) clusters_pvs=%d%%" % [name, s["kind"], s["pos"].x, s["pos"].y, s["pos"].z, int(s["open"] * 100.0)]
		for m in MODES:
			var r := await _measure(s, m)
			row += " | %s draws=%d objs=%d prims_k=%d cpu_ms=%.2f gpu_ms=%.2f" % [m, r["draws"], r["objects"], r["prims"] / 1000, r["cpu"], r["gpu"]]
		print(row)
	var worst := {"pvs": 0.0, "occluders": 0.0, "both": 0.0}
	var bad := {"pvs": 0, "occluders": 0, "both": 0}
	var total := 0
	for s: Dictionary in spots["diff"]:
		total += 1
		var base := await _frame(s, "off")
		for m in ["pvs", "occluders", "both"]:
			var img := await _frame(s, m)
			var frac := _diff(base, img)
			if frac > 0.0005:
				if m == "pvs" and _args.has("bisect"):
					await _bisect(s, img)
				bad[m] += 1
				img.save_png("%s/%s_%d_%s.png" % [_out, name, total, m])
				base.save_png("%s/%s_%d_off.png" % [_out, name, total])
			worst[m] = maxf(worst[m], frac)
	print("PROOF %s diff positions=%d | pvs: %d over 0.05%% (worst %.3f%%) | occluders: %d (worst %.3f%%) | both: %d (worst %.3f%%)" % [
			name, total, bad["pvs"], worst["pvs"] * 100.0, bad["occluders"], worst["occluders"] * 100.0, bad["both"], worst["both"] * 100.0])


## Spots: eye positions in open space with a floor under them, [kind: room|corridor|open by how much of the map the camera's PVS covers].
func _pick_spots(metric_n: int, diff_n: int) -> Dictionary:
	var body := StaticBody3D.new()
	var box := AABB()
	var first := true
	for item in _vis._items:
		var mi := item["node"] as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var shape := CollisionShape3D.new()
		var tri := ConcavePolygonShape3D.new()
		tri.set_faces(mi.mesh.get_faces())
		tri.backface_collision = true
		shape.shape = tri
		shape.transform = mi.global_transform
		body.add_child(shape)
		var b := mi.global_transform * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	add_child(body)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var found: Array[Dictionary] = []
	var tries := 0
	var want := maxi(diff_n, metric_n * 6)
	while found.size() < want and tries < want * 600:
		tries += 1
		var p := box.position + Vector3(rng.randf(), rng.randf(), rng.randf()) * box.size
		var leaf := _vis.leaf_at(p)
		if leaf < 0 or leaf >= _vis._leaf_cluster.size() or _vis._leaf_cluster[leaf] < 0:
			continue
		var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(p, p + Vector3.DOWN * 6.0))
		if down.is_empty():
			continue
		var eye: Vector3 = down["position"] + Vector3.UP * 1.7
		if _vis.leaf_at(eye) < 0 or _vis._leaf_cluster[_vis.leaf_at(eye)] < 0:
			continue
		# look along the longest clear direction of eight
		var best_d := 0.0
		var look := Vector3.FORWARD
		for k in 8:
			var dir := Vector3.FORWARD.rotated(Vector3.UP, k * TAU / 8.0 + rng.randf() * 0.3)
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, eye + dir * 200.0))
			var d := 200.0 if hit.is_empty() else eye.distance_to(hit["position"])
			if d > best_d:
				best_d = d
				look = dir
		if best_d < 2.0:
			continue
		_vis._last_pos = Vector3.INF
		_vis._camera_clusters = PackedInt32Array()
		_vis.update_from(eye)
		var sc := _vis.shown_count()
		found.append({"pos": eye, "look": look, "open": float(sc.x) / maxf(1.0, sc.y), "reach": best_d})
	body.queue_free()
	_vis.mode = DotMapVisibility.Mode.OFF
	_vis.set_mode(DotMapVisibility.Mode.OFF)
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["open"] < b["open"])
	var metric: Array[Dictionary] = []
	if found.size() >= metric_n:
		for i in metric_n:
			var f := found[int(float(i) / maxf(1.0, metric_n - 1.0) * (found.size() - 1))]
			f["kind"] = "room" if i < metric_n / 3 else ("corridor" if i < 2 * metric_n / 3 else "open")
			metric.append(f)
	var diff: Array[Dictionary] = []
	found.shuffle()
	for f in found.slice(0, diff_n):
		diff.append(f)
	return {"metric": metric, "diff": diff}


func _place(s: Dictionary, mode: String) -> void:
	_cam.global_position = s["pos"]
	_cam.look_at(s["pos"] + s["look"] + Vector3.DOWN * 0.05)
	_vis.set_mode(DotMapVisibility.parse_mode(mode))
	_vis._last_pos = Vector3.INF
	_vis._dirty = true


func _frame(s: Dictionary, mode: String) -> Image:
	_place(s, mode)
	for i in 4:
		await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


func _measure(s: Dictionary, mode: String) -> Dictionary:
	_place(s, mode)
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	for i in 6:
		await RenderingServer.frame_post_draw
	var draws := 0.0
	var objs := 0.0
	var prims := 0.0
	var cpu := 0.0
	var gpu := 0.0
	var n := 30
	for i in n:
		await RenderingServer.frame_post_draw
		draws += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		objs += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
		prims += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	return {"draws": int(draws / n), "objects": int(objs / n), "prims": int(prims / n), "cpu": cpu / n, "gpu": gpu / n}


static func _diff(a: Image, b: Image) -> float:
	if a.get_size() != b.get_size():
		return 1.0
	var da := a.get_data()
	var db := b.get_data()
	var bpp := 4 if a.get_format() == Image.FORMAT_RGBA8 else 3
	var n := a.get_width() * a.get_height()
	var bad := 0
	for i in n:
		var o := i * bpp
		if absi(da[o] - db[o]) > 6 or absi(da[o + 1] - db[o + 1]) > 6 or absi(da[o + 2] - db[o + 2]) > 6:
			bad += 1
	return float(bad) / n


## Which hidden items, shown again one at a time, change the pvs frame: what the pvs frame is missing, or what covers it.
func _bisect(s: Dictionary, pvs_img: Image) -> void:
	var hidden: Array = []
	for item in _vis._items:
		if not item["shown"]:
			hidden.append(item)
	for item in hidden:
		(item["node"] as Node3D).visible = true
		for i in 3:
			await RenderingServer.frame_post_draw
		var shot := get_viewport().get_texture().get_image()
		var f := _diff(pvs_img, shot)
		if f > 0.0005:
			shot.save_png("%s/bisect_%s.png" % [_out, (item["node"] as Node).name])
		(item["node"] as Node3D).visible = false
		if f > 0.0005:
			var nd := item["node"] as MeshInstance3D
			print("BISECT cams=%s aabb=%s" % [_vis._camera_clusters, nd.get_aabb() if nd != null else null])
			print("BISECT at=%s item=%s clusters=%s changes %.2f%% of pixels" % [s["pos"], (item["node"] as Node).name, item["clusters"], f * 100.0])
