extends Node3D

## One frame of an env_spritetrail behind a moving point: [code]-- --out=<png>[/code], not headless (it draws nothing there).


func _ready() -> void:
	var out := "/tmp/trail.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.06, 0.1)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 1.5, 6)
	cam.look_at(Vector3(0, 1, 0))
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 20)
	floor_mesh.mesh = plane
	add_child(floor_mesh)
	var mover := Node3D.new()
	add_child(mover)
	var fx := DotMapFx.new()
	fx.trail_target_fn = func(_n: String) -> Node3D: return mover
	add_child(fx.build([{"classname": "env_spritetrail", "pairs": [["origin", "0 0 0"], ["parentname", "rocket"],
			["lifetime", "1.2"], ["startwidth", "20"], ["endwidth", "2"], ["rendercolor", "255 140 40"], ["renderamt", "255"]]}]))
	for i in 60:
		var t := i / 59.0
		mover.position = Vector3(-4.0 + 8.0 * t, 1.0 + sin(t * TAU) * 0.8, 0.0)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png(out)
	print("saved %s (%d)" % [out, err])
	get_tree().quit()
