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
		# Layouts: <root>/<id>/<id>.json (arena), flat <root>/<id>.json (g2gfast, wipeout), <root>/<dir>/<id>.json (hide-n-seek);
		# a world is a .json with its .bin beside it.
		var found: Array[Array] = []
		for f in DirAccess.get_files_at(root):
			if f.ends_with(".json") and FileAccess.file_exists(root.path_join(f.get_basename() + ".bin")):
				found.append([f.get_basename(), root.path_join(f.get_basename())])
		for dir_id in DirAccess.get_directories_at(root):
			var sub := root.path_join(dir_id)
			for f in DirAccess.get_files_at(sub):
				if f.ends_with(".json") and FileAccess.file_exists(sub.path_join(f.get_basename() + ".bin")):
					found.append([f.get_basename(), sub.path_join(f.get_basename())])
		for entry in found:
			var id: String = entry[0]
			var prefix: String = entry[1]
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
