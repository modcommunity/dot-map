extends SceneTree
## Fails (exit 1) when a converted world has a library prop that did not load, or one that would be invisible and solid.
## godot --headless --path . -s res://tools/prop_audit.gd -- /abs/worlds [/abs/more/worlds ...] [--allow-proxied]

func _init() -> void:
	var roots: Array[String] = []
	var allow_proxied := false
	for a in OS.get_cmdline_user_args():
		if a == "--allow-proxied":
			allow_proxied = true
		else:
			roots.append(a)
	var maps := 0
	var bad := 0
	for root in roots:
		for id in DirAccess.get_directories_at(root):
			var prefix := root.path_join(id).path_join(id)
			if not FileAccess.file_exists(prefix + ".json"):
				continue
			var res := DotMapBspMesh.load_prefix(prefix)
			if not res.ok:
				continue
			var w: DotMapBspMesh = res.value
			var props := w.build_props()
			props.free()
			maps += 1
			var invisible := w._unseen.size()
			if invisible > 0 or (w.missing_models > 0 and not allow_proxied):
				bad += 1
				print("FAIL %s: %d model(s) unresolved, %d drawn as proxy, %d invisible" % [id, w.missing_models, w.missing_proxied, invisible])
	print("prop_audit: %d maps, %d failed" % [maps, bad])
	quit(1 if bad > 0 or maps == 0 else 0)
