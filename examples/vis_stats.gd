extends Node

## How much of a converted map DotMapVisibility can cull: items, their cluster spread, and the drawn
## share (by items and by triangles) from random points.
## godot --headless --path . res://examples/vis_stats.tscn -- --maps=<prefix>,<prefix> [--points=60]

func _ready() -> void:
	await _run()
	get_tree().quit()


func _arg(key: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.substr(key.length() + 3)
	return fallback


func _run() -> void:
	var points := int(_arg("points", "60"))
	for prefix in _arg("maps", "").split(",", false):
		var read := DotMapBspMesh.load_prefix(prefix)
		if not read.ok:
			print("STAT %s load failed" % prefix)
			continue
		var world: DotMapBspMesh = read.value
		var node := world.build_node()
		node.add_child(world.build_props())
		add_child(node)
		var vis := DotMapVisibility.new()
		vis.run_headless = true
		add_child(vis)
		vis.setup(world, node)
		var always := 0
		var spread := 0
		var tris_all := 0
		var tris := PackedInt32Array()
		var chunk_n := 0
		for item in vis._items:
			var cl: PackedInt32Array = item["clusters"]
			var n: Node = item["node"]
			var t := 0
			if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
				chunk_n += 1
				for s in (n as MeshInstance3D).mesh.get_surface_count():
					t += (n as MeshInstance3D).mesh.surface_get_array_len(s) / 3
			tris.append(t)
			tris_all += t
			if cl.has(-1):
				always += 1
			else:
				spread += cl.size()
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var box := AABB()
		for item in vis._items:
			var n: Node = item["node"]
			if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
				var b := (n as MeshInstance3D).global_transform * (n as MeshInstance3D).mesh.get_aabb()
				box = b if box.size == Vector3.ZERO else box.merge(b)
		var done := 0
		var tries := 0
		var it_sum := 0.0
		var tri_sum := 0.0
		while done < points and tries < points * 500:
			tries += 1
			var p := box.position + Vector3(rng.randf(), rng.randf(), rng.randf()) * box.size
			if vis.clusters_in_box(AABB(p - Vector3.ONE, Vector3.ONE * 2.0)).is_empty():
				continue
			vis._last_pos = Vector3.INF
			vis._camera_clusters = PackedInt32Array()
			vis.update_from(p)
			var shown_t := 0
			var shown_i := 0
			for i in vis._items.size():
				if vis._items[i]["shown"]:
					shown_i += 1
					shown_t += tris[i]
			it_sum += float(shown_i) / vis._items.size()
			tri_sum += float(shown_t) / maxf(1.0, tris_all)
			done += 1
		print("STAT %s clusters=%d items=%d chunks=%d always=%d avg_clusters_per_item=%.1f tris=%d points=%d shown_items=%.0f%% shown_tris=%.0f%%" % [
			prefix.get_file(), vis._clusters, vis._items.size(), chunk_n, always, float(spread) / maxf(1.0, vis._items.size() - always), tris_all, done,
			100.0 * it_sum / maxf(1.0, done), 100.0 * tri_sum / maxf(1.0, done)])
		node.queue_free()
		vis.queue_free()
