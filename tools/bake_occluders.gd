extends SceneTree

## Bakes occluders into a scene file from its static meshes, headless. Run [code]--import[/code] first.
## Meshes in group [code]dot_no_occluder[/code], hidden and translucent ones are skipped.

func _init() -> void:
	var path := ""
	var out := ""
	var baker := DotOccluderBaker.new()
	var dry := false
	for a in OS.get_cmdline_args():
		if a == "--dry":
			dry = true
		elif a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--min-area="):
			baker.min_area = float(a.substr(11))
		elif a.begins_with("--min-side="):
			baker.min_side = float(a.substr(11))
		elif a.begins_with("--min-fill="):
			baker.min_fill = float(a.substr(11))
		elif a.begins_with("--max-quads="):
			baker.max_quads = int(a.substr(12))
		elif path.is_empty() and (a.ends_with(".tscn") or a.ends_with(".scn")):
			path = a
	if path.is_empty():
		printerr("usage: godot --headless -s tools/bake_occluders.gd -- <scene.tscn> [--out=<scene.tscn>] [--dry]")
		quit(2)
		return
	var packed := load(path) as PackedScene
	if packed == null:
		printerr("cannot load %s" % path)
		quit(1)
		return
	var root := packed.instantiate() as Node3D
	if root == null:
		printerr("%s has no Node3D root" % path)
		quit(1)
		return
	var res := baker.bake(root)
	print("%s: %d meshes, %d large faces, %d quads" % [path, baker.stats["meshes"], baker.stats["faces"], baker.stats["quads"]])
	if not res.ok:
		printerr(res.error.message)
		quit(1)
		return
	if not dry:
		var scene := PackedScene.new()
		var pack_err := scene.pack(root)
		var save_err := ResourceSaver.save(scene, out if not out.is_empty() else path) if pack_err == OK else pack_err
		if save_err != OK:
			printerr("cannot save: error %d" % save_err)
			quit(1)
			return
		print("wrote %s" % (out if not out.is_empty() else path))
	root.free()
	quit(0)
