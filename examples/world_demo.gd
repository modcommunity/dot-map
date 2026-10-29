extends Node

## DotMapWorld on the real converted Office and Dan's course: one call builds the world from the mesh
## manifest and the stored source document, and Office's timed hurt room behaves per its own links. Without
## the converted worlds (or the store holding their source documents) it prints SKIP and exits 0.

const CHECKS := 34
const SECTIONS := 5

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()
var _entered := 0
var _completed := 0
var _dir := ""


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_dir = OS.get_environment("HOME").path_join("godot/mg-wipeout-maps/worlds")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--worlds="):
			_dir = a.substr(9)
	_run.call_deferred()


func _run() -> void:
	print("dot-map world")
	if not FileAccess.file_exists(_dir.path_join("wo_office_course.json")):
		print("SKIP: no converted worlds in " + _dir)
		get_tree().quit(0)
		return
	await _test_office_build()
	await _test_office_hurt_room()
	await _test_replication()
	await _test_dans()
	await _test_manifest_settings()
	print("")
	print("%d passed, %d failed" % [_passed, _failed])
	for line in _failures:
		print("  FAIL  %s" % line)
	print("%d of %d sections ran to their last line" % [_completed, _entered])
	if _entered != SECTIONS or _completed != _entered or _passed + _failed != CHECKS:
		print("ERROR: %d sections (%d expected), %d checks (%d expected)." % [_entered, SECTIONS, _passed + _failed, CHECKS])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)


func _section(title: String) -> void:
	_entered += 1
	print("  " + title)


func _check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		_failures.append(what)


func _build(name: String, hooks: Dictionary = {}, options: Dictionary = {}) -> DotMapWorld:
	var res := DotMapWorld.build(_dir.path_join(name), hooks, options)
	_check(res.ok, "%s builds (%s)" % [name, res.error if not res.ok else ""])
	if not res.ok:
		return null
	var w: DotMapWorld = res.value
	add_child(w)
	return w


func _volume(w: DotMapWorld, tname: String) -> DotMapVolume:
	for n in w.volumes.nodes:
		if n.volume.targetname == tname:
			return n.volume
	return null


func _test_office_build() -> void:
	_section("one call builds Office: mesh, hulls, logic, volumes, hooks")
	var ladders := [0]
	var swims := [0]
	var w := _build("wo_office_course", {
		"ladder_fn": func(b: Array) -> void: ladders[0] = b.size(),
		"swim_fn": func(b: Array) -> void: swims[0] = b.size(),
	}, {"environment": false, "props": false, "sounds": false})
	if w == null:
		_completed += 1
		return
	_check(w.visual.get_child_count() > 50, "the drawn models are there: %d" % w.visual.get_child_count())
	var bodies := w.find_children("col_*", "CollisionObject3D", true, false)
	_check(bodies.size() > 50, "collision bodies per model and kind: %d" % bodies.size())
	_check(w.get_node("BspMesh/world/col_solid") is StaticBody3D, "the world's solid hulls are a static body")
	var moving := 0
	for b in bodies:
		if b is AnimatableBody3D:
			moving += 1
	_check(moving > 0, "movers carry animatable bodies: %d" % moving)
	_check(w.io.entities.size() > 400, "the stored document's entities run: %d" % w.io.entities.size())
	_check(w.volumes.nodes.size() == 93, "93 volumes joined to their entities: %d" % w.volumes.nodes.size())
	_check(ladders[0] == 10 and swims[0] == 8, "ladder_fn got 10 boxes and swim_fn 8: %s %s" % [ladders[0], swims[0]])
	_check(w.io.entity_of(128) is DotMapHurt and w.io.entity_of(130) is DotMapTrigger, "classes are registered")
	w.queue_free()
	await get_tree().process_frame
	_completed += 1


func _test_office_hurt_room() -> void:
	_section("Office's timed hurt room, per its own links")
	var hits: Array = []
	var w := _build("wo_office_course", {
		"damage_fn": func(_b: Variant, amount: float, kind: String, attacker: Variant) -> void:
			hits.append([w_now(), amount, (attacker as DotMapEntity).targetname]),
	}, {"environment": false, "props": false, "sounds": false, "seed": 7})
	if w == null:
		_completed += 1
		return
	_now_source = w
	var trig := _volume(w, "Obstacle2_trigger")
	var hurt := _volume(w, "Obstacle2_Hurt")
	var delay := 0.0
	for l in w.io.find("Obstacle2_trigger")[0].links:
		if str(l["target"]) == "Obstacle2_Hurt" and str(l["input"]).to_lower() == "enable":
			delay = float(l["delay"])
	_check(delay > 0.0, "the trigger's link to the hurt volume has a delay, read from the map: %s" % delay)
	var tb := trig.bounds()
	var hb := hurt.bounds()
	var pos := [tb.get_center()]
	pos[0].y = tb.position.y
	var provider := func() -> Array:
		return [{"id": 1, "body": "player", "position": pos[0], "kind": "player", "name": "p", "height": 1.8}]
	for i in 60:
		w.step(provider.call())
	var mine := func() -> Array: return hits.filter(func(h: Array) -> bool: return h[2] == "Obstacle2_Hurt")
	_check(mine.call().is_empty(), "nothing hurts in the first second: the hurt volume starts disabled")
	pos[0] = hb.get_center()
	pos[0].y = hb.position.y
	var enable_tick := 1 + int(round(delay * w.io.rate))
	for i in int(delay * w.io.rate) + 70:
		w.step(provider.call())
	var m: Array = mine.call()
	_check(m.size() >= 3, "the hurt volume hurts once enabled: %d hits" % m.size())
	_check(not m.is_empty() and abs(int(m[0][0]) - enable_tick) <= 2,
			"the first hit lands at entry + %s s (tick %s, expected near %s)" % [delay, m[0][0] if not m.is_empty() else -1, enable_tick])
	_check(m.size() >= 2 and int(m[1][0]) - int(m[0][0]) == 30, "then every 0.5 s")
	_check(not m.is_empty() and m[0][1] == 100.0, "200 a second at hurtrate 0.5 is 100 a hit")
	_check(w.io.loop_trips == 0, "no loop tripped the guard")
	for i in 3600:
		w.step()
	var cov := w.io.coverage()
	print("    after %.0f s: %s" % [w.io.seconds(), JSON.stringify(cov).substr(0, 1500)])
	_check((cov["unhandled"] as Dictionary).is_empty(), "60 s of Office leave no input without a class: %s" % [cov["unhandled"]])
	w.queue_free()
	await get_tree().process_frame
	_completed += 1


var _now_source: DotMapWorld = null


func w_now() -> int:
	return _now_source.io.now if _now_source != null else 0


func _test_replication() -> void:
	_section("the host broadcasts state, a client follows without running logic")
	var sent: Array = []
	var host := _build("wo_office_course", {"send_fn": func(peer: Variant, msg: Dictionary) -> void: sent.append([peer, msg])},
			{"environment": false, "props": false, "sounds": false})
	var client := _build("wo_office_course", {}, {"environment": false, "props": false, "sounds": false, "authoritative": false})
	if host == null or client == null:
		_completed += 1
		return
	host.add_peer("c1")
	_check(sent.size() == 1 and sent[0][1]["type"] == "io_snapshot", "a joiner gets a snapshot first")
	var trig := _volume(host, "Obstacle2_trigger").bounds()
	var feet := trig.get_center()
	feet.y = trig.position.y
	for i in 200:
		host.step([{"id": 1, "body": "p", "position": feet, "kind": "player", "name": "p", "height": 1.8}])
	_check(sent.size() > 1, "state changes went out: %d messages" % sent.size())
	for s in sent:
		client.apply_state(s[1])
	var hurt_h := host.io.find("Obstacle2_Hurt")[0] as DotMapEntity
	var hurt_c := client.io.find("Obstacle2_Hurt")[0] as DotMapEntity
	_check(hurt_h.enabled and hurt_c.enabled, "the client's hurt volume is enabled with the host's")
	client.step()
	_check(client.io.pending() == 0, "a client queues no logic of its own")
	host.queue_free()
	client.queue_free()
	await get_tree().process_frame
	_completed += 1


func _test_dans() -> void:
	_section("Dan's course builds the same way")
	var ladders := [0]
	var w := _build("wo_dans_course", {"ladder_fn": func(b: Array) -> void: ladders[0] = b.size()},
			{"environment": false, "props": false, "sounds": false})
	if w == null:
		_completed += 1
		return
	_check(ladders[0] > 0, "its ladders reach the hook: %d" % ladders[0])
	_check(w.volumes.nodes.size() == 54, "54 volumes: %d" % w.volumes.nodes.size())
	_check(not w.spawn_points().is_empty(), "start points are listed")
	var bad := DotMapWorld.build(_dir.path_join("no_such_world"))
	_check(not bad.ok and bad.code() == DotError.CODE_IO, "a missing mesh is a CODE_IO failure, not a crash")
	w.queue_free()
	await get_tree().process_frame
	_completed += 1


func _test_manifest_settings() -> void:
	_section("the manifest's settings are the weakest config layer, behind the game's whitelist")
	var loaded := DotMapBspMesh.load_prefix(_dir.path_join("wo_office_course"))
	_check(loaded.ok, "the mesh loads")
	if not loaded.ok:
		_completed += 1
		return
	var m: DotMapBspMesh = loaded.value
	m.manifest["settings"] = {"sv_airaccelerate": 150, "sv_evil": 1}
	var applied := {}
	var setter := func(k: String, v: Variant) -> bool:
		applied[k] = v
		return true
	var getter := func(_k: String) -> Variant:
		return 0
	var cfg := {"allow": {"sv_airaccelerate": {}, "sv_gravity": {}}, "defaults": {"sv_gravity": 700},
			"get_fn": getter, "set_fn": setter}
	var res := DotMapWorld.build(m, {}, {"config": cfg, "environment": false, "props": false, "sounds": false})
	_check(res.ok, "the world builds with a config")
	if res.ok:
		var w: DotMapWorld = res.value
		add_child(w)
		_check(applied.get("sv_airaccelerate") == 150.0, "the map's own cvar is applied once the game allows it: %s" % [applied])
		_check(applied.get("sv_gravity") == 700.0, "the options' defaults sit beside it")
		_check(not applied.has("sv_evil"), "and a key the game did not allow is refused")
		w.queue_free()
		await get_tree().process_frame
	_completed += 1
