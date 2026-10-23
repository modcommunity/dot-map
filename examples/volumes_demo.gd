extends Node

## The volumes a converted map's brush entities become ([DotMapVolumes] on [DotMapIO]): hurt,
## push, teleport, gravity, trigger, ladder and water, the effects and sounds, the command
## allow-list, and Office's timed hurt reproduced from its own links.
##
## [codeblock]
## godot --headless --path . res://examples/volumes_demo.tscn
## [/codeblock]

const CHECKS := 114
const SECTIONS := 13
const OFFICE := "res://examples/io/office_io.doc.json"

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()
var _entered := 0
var _completed := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("dot-map volumes")
	_test_hurt_cycle()
	_test_hurt_model_and_kind()
	_test_triggers()
	_test_push_teleport_gravity()
	_test_boxes()
	_test_effects_sounds()
	_test_commands()
	_test_hurt_once_and_force()
	_test_soundscapes()
	_test_trigger_soundscape()
	_test_movers_push_and_block()
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(OFFICE))
	if doc is Dictionary:
		_test_office_timing(doc)
		_test_office_second_entry(doc)
	print("")
	print("%d passed, %d failed" % [_passed, _failed])
	for line in _failures:
		print("  FAIL  %s" % line)
	print("%d of %d sections ran to their last line" % [_completed, _entered])
	if _entered != SECTIONS or _completed != _entered:
		print("ERROR: %d sections entered and %d completed, %d expected." % [_entered, _completed, SECTIONS])
		get_tree().quit(1)
		return
	if _passed + _failed != CHECKS:
		print("ERROR: %d checks ran, %d expected. A section aborted part-way." % [_passed + _failed, CHECKS])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)


func _section(title: String) -> void:
	_entered += 1
	print("  " + title)


func _done() -> void:
	_completed += 1


func _check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		_failures.append(what)


func _rec(index: int, cls: String, tname: String, pairs: Array = [], outs: Array = []) -> Dictionary:
	var outputs: Array = []
	for o: Array in outs:
		outputs.append({"output": o[0], "target": o[1], "input": o[2], "param": o[3] if o.size() > 3 else "",
				"delay": o[4] if o.size() > 4 else 0.0, "times": o[5] if o.size() > 5 else -1})
	return {"index": index, "classname": cls, "targetname": tname, "parentname": "", "pairs": pairs, "outputs": outputs}


## A manifest volume record for a box from [param lo] to [param hi] (metres).
func _vol(entity: int, kind: String, cls: String, lo: Vector3, hi: Vector3, extra: Dictionary = {}) -> Dictionary:
	var planes: Array = [[1, 0, 0, hi.x], [-1, 0, 0, -lo.x], [0, 1, 0, hi.y], [0, -1, 0, -lo.y], [0, 0, 1, hi.z], [0, 0, -1, -lo.z]]
	var r := {"entity": entity if entity >= 0 else null, "model": 1, "classname": cls, "kind": kind,
			"targetname": "", "spawnflags": 1, "disabled": false, "outputs": [], "brushes": [planes]}
	r.merge(extra, true)
	return r


func _world(records: Array, vols: Array, rate: int = 60) -> Array:
	var io := DotMapIO.new()
	io.rate = rate
	io.record_history = true
	var r := io.load_records(records)
	_check(r.ok, "records load")
	var ents := DotMapEntities.from_manifest({"volumes": vols})
	return [io, DotMapVolumes.build(ents, io)]


func _body(id: int, pos: Vector3, kind: String = "player", name: String = "") -> Dictionary:
	return {"id": id, "body": "b%d" % id, "position": pos, "kind": kind, "name": name, "height": 1.8}


## Runs [param ticks] rounds of advance then step; [param bodies] is a Callable(tick) -> Array.
func _run_ticks(io: DotMapIO, vols: DotMapVolumes, ticks: int, bodies: Callable) -> void:
	for i in ticks:
		io.advance(1)
		vols.step(bodies.call(io.now))


func _test_hurt_cycle() -> void:
	_section("a hurt volume hits on entry, every hurtrate after, and stops when the body leaves or it is disabled")
	var w := _world([
		_rec(0, "trigger_hurt", "lava", [["damage", "20"], ["damagetype", "8"]], [["OnHurt", "log", "FireUser1"]]),
		_rec(1, "info_target", "log"),
	], [_vol(0, "hurt", "trigger_hurt", Vector3(0, 0, 0), Vector3(4, 3, 4), {"targetname": "lava"})])
	var io: DotMapIO = w[0]
	var vols: DotMapVolumes = w[1]
	var hits: Array = []
	io.damage_fn = func(body: Variant, amount: float, kind: String, attacker: Variant) -> void:
		hits.append([io.now, body, amount, kind, (attacker as DotMapEntity).targetname])
	var pos := [Vector3(2, 0, 2)]
	var provider := func(_t: int) -> Array: return [_body(1, pos[0])]
	_run_ticks(io, vols, 5, provider)
	_check(hits.size() == 1 and hits[0][0] == 1, "first hit on the tick of entry: %s" % [hits])
	_check(hits[0][2] == 10.0 and hits[0][3] == "burn" and hits[0][4] == "lava", "20 a second at hurtrate 0.5 is 10, kind burn from damagetype 8, attacker is the volume")
	_run_ticks(io, vols, 60, provider)
	var ticks: Array = hits.map(func(h: Array) -> int: return h[0])
	_check(ticks == [1, 31, 61], "then every 30 ticks (0.5 s at 60 a second): %s" % [ticks])
	pos[0] = Vector3(20, 0, 2)
	_run_ticks(io, vols, 120, provider)
	_check(hits.size() == 3, "no more hits once out of the volume")
	_check(io.pending() == 0, "and nothing left scheduled")
	pos[0] = Vector3(2, 0, 2)
	_run_ticks(io, vols, 1, provider)
	_check(hits.size() == 4, "entering again hits again at once")
	io.send("lava", "Disable")
	_run_ticks(io, vols, 90, provider)
	_check(hits.size() == 4, "a disabled volume does not hurt a body inside")
	io.send("lava", "Enable")
	_run_ticks(io, vols, 1, provider)
	_check(hits.size() == 5 and hits[4][0] == io.now, "enabled with the body still inside hurts it again at once")
	io.send("lava", "SetDamage", "100")
	_run_ticks(io, vols, 30, provider)
	_check(hits[hits.size() - 1][2] == 50.0, "SetDamage changes the rate: %s" % [hits[hits.size() - 1]])
	_check(io.delivered > 0 and io.coverage()["unhandled"].is_empty(), "OnHurt reached its target and no input went unhandled: %s" % [io.coverage()["unhandled"]])
	var two := [_body(1, Vector3(2, 0, 2)), _body(2, Vector3(3, 0, 3), "npc")]
	io.send("lava", "Disable")
	vols.step(two)
	io.advance(2)
	io.send("lava", "Enable")
	hits.clear()
	vols.step(two)
	var who: Array = hits.map(func(h: Array) -> String: return str(h[1]))
	_check(who == ["b1"], "spawnflag 1 hurts clients only, an npc standing in it is spared: %s" % [who])
	io.damage_fn = Callable()  # the lambda captures io: a cycle, reported as a leak at exit
	_done()


func _test_hurt_model_and_kind() -> void:
	_section("damagemodel 1 doubles to the cap; damage kinds; OnHurtPlayer")
	var w := _world([
		_rec(0, "trigger_hurt", "dbl", [["damage", "10"], ["damagemodel", "1"], ["damagecap", "40"], ["damagetype", "262144"]],
				[["OnHurtPlayer", "r", "Trigger"]]),
		_rec(1, "logic_relay", "r", [], [["OnTrigger", "c", "Add", "1"]]),
		_rec(2, "math_counter", "c"),
	], [_vol(0, "hurt", "trigger_hurt", Vector3.ZERO, Vector3(4, 3, 4))])
	var io: DotMapIO = w[0]
	var vols: DotMapVolumes = w[1]
	var amounts: Array = []
	var kinds: Array = []
	io.damage_fn = func(_b: Variant, amount: float, kind: String, _a: Variant) -> void:
		amounts.append(amount)
		kinds.append(kind)
	var provider := func(_t: int) -> Array: return [_body(1, Vector3(1, 0, 1))]
	_run_ticks(io, vols, 151, provider)
	_check(amounts == [5.0, 10.0, 20.0, 40.0, 40.0, 40.0], "5 (10 a second, half a second) doubles to the cap of 40: %s" % [amounts])
	_check(kinds[0] == "radiation", "262144 is radiation")
	_check((io.find("c")[0] as DotMapCounter).value == 6.0, "OnHurtPlayer fired once per hit into the counter")
	var missing := DotMapIO.new()
	missing.load_records([_rec(0, "trigger_hurt", "h", [["damage", "5"]])])
	var v2 := DotMapVolumes.build(DotMapEntities.from_manifest({"volumes": [_vol(0, "hurt", "trigger_hurt", Vector3.ZERO, Vector3(2, 2, 2))]}), missing)
	v2.step([_body(1, Vector3(1, 0, 1))])
	_check(int(missing.missing_callables.get("damage", 0)) == 1, "no damage_fn: a counted no-op, nothing crashes")
	_done()


func _test_triggers() -> void:
	_section("trigger_multiple and trigger_once: entry, wait, filters, start-all and end-all")
	var w := _world([
		_rec(0, "trigger_multiple", "multi", [["wait", "2"]], [["OnStartTouch", "c", "Add", "1"], ["OnTrigger", "t", "Add", "1"],
				["OnStartTouchAll", "all", "Add", "1"], ["OnEndTouchAll", "none", "Add", "1"], ["OnEndTouch", "e", "Add", "1"]]),
		_rec(1, "trigger_once", "once", [], [["OnTrigger", "o", "Add", "1"]]),
		_rec(2, "trigger_multiple", "named", [["wait", "0"], ["filtername", "f"]], [["OnTrigger", "n", "Add", "1", 0.0, 1]]),
		_rec(3, "filter_activator_name", "f", [["filtername", "alice"]]),
		_rec(4, "math_counter", "c"), _rec(5, "math_counter", "t"), _rec(6, "math_counter", "o"),
		_rec(7, "math_counter", "n"), _rec(8, "math_counter", "all"), _rec(9, "math_counter", "none"), _rec(10, "math_counter", "e"),
	], [
		_vol(0, "multiple", "trigger_multiple", Vector3(0, 0, 0), Vector3(2, 2, 2), {"wait": 2.0}),
		_vol(1, "once", "trigger_once", Vector3(10, 0, 0), Vector3(12, 2, 2), {"wait": -1.0}),
		_vol(2, "multiple", "trigger_multiple", Vector3(20, 0, 0), Vector3(22, 2, 2), {"wait": 0.0, "filter": "f"}),
	])
	var io: DotMapIO = w[0]
	var vols: DotMapVolumes = w[1]
	var cv := func(n: String) -> float: return (io.find(n)[0] as DotMapCounter).value
	var bodies := [[_body(1, Vector3(1, 0, 1))]]
	var provider := func(_t: int) -> Array: return bodies[0]
	_run_ticks(io, vols, 1, provider)
	_check(cv.call("c") == 1.0 and cv.call("t") == 1.0 and cv.call("all") == 1.0, "entry fires OnStartTouch, OnTrigger and OnStartTouchAll")
	_run_ticks(io, vols, 60, provider)
	_check(cv.call("t") == 1.0, "standing in it, OnTrigger waits out the 2 s")
	_run_ticks(io, vols, 60, provider)
	_check(cv.call("t") == 2.0 and cv.call("c") == 1.0, "and fires again after the wait without a second OnStartTouch")
	bodies[0] = [_body(1, Vector3(1, 0, 1)), _body(2, Vector3(1.5, 0, 1.5))]
	_run_ticks(io, vols, 1, provider)
	_check(cv.call("c") == 2.0 and cv.call("all") == 1.0, "a second body fires OnStartTouch but not OnStartTouchAll")
	bodies[0] = [_body(2, Vector3(1.5, 0, 1.5))]
	_run_ticks(io, vols, 1, provider)
	_check(cv.call("e") == 1.0 and cv.call("none") == 0.0, "one leaving fires OnEndTouch, not OnEndTouchAll")
	bodies[0] = []
	_run_ticks(io, vols, 1, provider)
	_check(cv.call("none") == 1.0, "the last one out fires OnEndTouchAll")
	bodies[0] = [_body(3, Vector3(11, 0, 1))]
	_run_ticks(io, vols, 300, provider)
	_check(cv.call("o") == 1.0 and io.find("once").is_empty(), "a once trigger fires once and is gone")
	bodies[0] = [_body(4, Vector3(21, 0, 1), "player", "bob")]
	_run_ticks(io, vols, 3, provider)
	_check(cv.call("n") == 0.0, "a filter keeps out the wrong name")
	bodies[0] = [_body(5, Vector3(21, 0, 1), "player", "alice")]
	_run_ticks(io, vols, 3, provider)
	_check(cv.call("n") == 1.0, "and lets the right one in, once (the output has times=1)")
	io.send("multi", "Disable")
	bodies[0] = [_body(1, Vector3(1, 0, 1))]
	var before: float = cv.call("c")
	_run_ticks(io, vols, 5, provider)
	_check(cv.call("c") == before, "a disabled trigger ignores a body in it")
	io.send("multi", "Enable")
	_run_ticks(io, vols, 1, provider)
	_check(cv.call("c") == before + 1.0, "and meets it afresh when enabled")
	_done()


func _test_push_teleport_gravity() -> void:
	_section("push, teleport with landmark, gravity")
	var w := _world([
		_rec(0, "trigger_push", "wind", [["spawnflags", "1"]], [["OnStartTouch", "c", "Add", "1"]]),
		_rec(1, "trigger_teleport", "tp", [["target", "dest"]]),
		_rec(2, "trigger_teleport", "tplm", [["target", "dest2"], ["landmark", "lm"]]),
		_rec(3, "trigger_gravity", "grav", [["gravity", "0.25"]]),
		_rec(4, "math_counter", "c"),
	], [
		_vol(0, "push", "trigger_push", Vector3(0, 0, 0), Vector3(2, 2, 2), {"direction": [0, 1, 0], "speed": 10.0}),
		_vol(1, "teleport", "trigger_teleport", Vector3(10, 0, 0), Vector3(12, 2, 2), {"target": "dest"}),
		_vol(2, "teleport", "trigger_teleport", Vector3(20, 0, 0), Vector3(22, 2, 2), {"target": "dest2"}),
		_vol(3, "gravity", "trigger_gravity", Vector3(30, 0, 0), Vector3(32, 2, 2), {"gravity": 0.25}),
	])
	var io: DotMapIO = w[0]
	var vols: DotMapVolumes = w[1]
	io.destinations = {"dest": {"at": [100.0, 5.0, 100.0], "yaw": 90.0}, "dest2": {"at": [200.0, 0.0, 0.0], "yaw": 0.0}, "lm": {"at": [20.0, 0.0, 0.0], "yaw": 0.0}}
	var moves: Array = []
	var events: Array = []
	io.move_fn = func(body: Variant, motion: Variant) -> void: moves.append([body, motion])
	io.event_fn = func(kind: String, data: Dictionary) -> void: events.append([kind, data])
	vols.step([_body(1, Vector3(1, 0, 1))])
	vols.step([_body(1, Vector3(1, 0, 1))])
	_check(moves.size() == 2 and moves[0][1] == Vector3(0, 10, 0), "a push hands the game its velocity each step the body is in it: %s" % [moves])
	_check((io.find("c")[0] as DotMapCounter).value == 1.0, "OnStartTouch fired once")
	vols.step([_body(2, Vector3(1, 0, 1), "npc")])
	_check(moves.size() == 2, "spawnflags 1: an npc is not pushed")
	io.send("wind", "SetPushSpeed", "1000")
	moves.clear()
	vols.step([_body(1, Vector3(1, 0, 1))])
	_check(is_equal_approx((moves[0][1] as Vector3).y, 25.4), "SetPushSpeed takes source units a second: %s" % [moves])
	io.send("wind", "SetPushDirection", "0 90 0")
	moves.clear()
	vols.step([_body(1, Vector3(1, 0, 1))])
	var dir: Vector3 = (moves[0][1] as Vector3).normalized()
	_check(dir.is_equal_approx(Vector3(0, 0, -1)), "SetPushDirection 0 90 0 points along source +y, which is Godot -z: %s" % [dir])
	moves.clear()
	vols.step([_body(1, Vector3(11, 0, 1))])
	var t: Transform3D = moves[0][1]
	_check(t.origin == Vector3(100, 5, 100) and is_equal_approx(t.basis.get_euler().y, deg_to_rad(90.0)), "a teleport sends the body to the destination, facing its yaw")
	_check(events.any(func(e: Array) -> bool: return e[0] == "teleport"), "and says so on the event callable")
	moves.clear()
	vols.step([_body(1, Vector3(21, 0, 1))])
	_check((moves[0][1] as Transform3D).origin == Vector3(201, 0, 1), "a landmark keeps the body's offset from it: %s" % [(moves[0][1] as Transform3D).origin])
	var empty := DotMapIO.new()
	empty.load_records([_rec(0, "trigger_teleport", "x", [["target", "nowhere"]])])
	var v2 := DotMapVolumes.build(DotMapEntities.from_manifest({"volumes": [_vol(0, "teleport", "trigger_teleport", Vector3.ZERO, Vector3(2, 2, 2), {"target": "nowhere"})]}), empty)
	v2.step([_body(1, Vector3(1, 0, 1))])
	_check(empty.unresolved.has("teleport:nowhere"), "a destination nothing carries is counted, not a crash")
	events.clear()
	vols.step([_body(1, Vector3(31, 0, 1))])
	vols.step([_body(1, Vector3(50, 0, 1))])
	_check(events.size() == 2 and events[0][1]["scale"] == 0.25 and events[1][1]["scale"] == 1.0, "gravity: the scale on entry and back to 1 on leaving: %s" % [events.size()])
	_done()


func _test_boxes() -> void:
	_section("ladders and water are boxes for the controller's modes")
	var ents := DotMapEntities.from_manifest({"volumes": [
		_vol(-1, "ladder", "worldspawn", Vector3(0, 0, 0), Vector3(0.1, 3, 1)),
		_vol(5, "ladder", "func_ladder", Vector3(5, 0, 0), Vector3(5.1, 4, 1), {"targetname": "lad"}),
		_vol(-1, "water", "worldspawn", Vector3(10, -2, 0), Vector3(14, 0, 4), {"slime": false}),
		_vol(-1, "hurt", "trigger_hurt", Vector3.ZERO, Vector3.ONE),
	]})
	var io := DotMapIO.new()
	io.load_records([_rec(5, "func_ladder", "lad")])
	var vols := DotMapVolumes.build(ents, io)
	var lad := vols.ladder_boxes()
	var wat := vols.water_boxes()
	_check(lad.size() == 2 and wat.size() == 1, "two ladder boxes, one water box")
	_check(lad[0].is_equal_approx(AABB(Vector3(0, 0, 0), Vector3(0.1, 3, 1))), "a ladder box is the brush: %s" % [lad[0]])
	_check(wat[0].is_equal_approx(AABB(Vector3(10, -2, 0), Vector3(4, 2, 4))), "a water box likewise")
	var two := DotMapVolume.from_record({"kind": "water", "brushes": [
		_vol(-1, "water", "x", Vector3.ZERO, Vector3.ONE)["brushes"][0], _vol(-1, "water", "x", Vector3(5, 0, 0), Vector3(6, 1, 1))["brushes"][0]]})
	_check(two.brush_boxes().size() == 2 and two.bounds().size.x == 6.0, "two brushes are two boxes, not their union")
	io.send("lad", "Disable")
	_check(vols.ladder_boxes().size() == 1, "a disabled ladder entity is off the list")
	_check(_climb(vols.ladder_boxes()[0]), "a body walked up the ladder box stays inside it from foot to top")
	_done()


## A body going up the box a step at a time: always touching, until it passes the top.
func _climb(box: AABB) -> bool:
	var ok := true
	var y := box.position.y
	while y < box.end.y - 0.2:
		var feet := Vector3(box.position.x - 0.05, y, box.position.z + 0.5)
		var hull := AABB(feet - Vector3(0.4, 0, 0.4), Vector3(0.8, 1.8, 0.8))
		ok = ok and box.intersects(hull)
		y += 0.5
	return ok


func _test_effects_sounds() -> void:
	_section("env effects and ambient sounds: inputs, stand-ins, area damage")
	var io := DotMapIO.new()
	io.load_records([
		_rec(0, "env_steam", "steam", [["StartDisabled", "1"], ["origin", "100 200 300"]]),
		_rec(1, "env_explosion", "boom", [["iMagnitude", "100"], ["origin", "0 0 0"]]),
		_rec(2, "env_explosion", "dud", [["iMagnitude", "100"], ["spawnflags", "1"]]),
		_rec(3, "env_shake", "shake"),
		_rec(4, "ambient_generic", "hum", [["message", "ambience/machine.wav"], ["health", "5"], ["spawnflags", "16"]]),
		_rec(5, "ambient_generic", "voice", [["message", "vo/line.wav"]]),
		_rec(6, "env_fire", "fire", [["StartDisabled", "1"], ["origin", "0 0 0"], ["firesize", "100"]]),
		_rec(7, "env_sprite", "spr"),
	])
	var fx: Array = []
	var ev: Array = []
	io.effect_fn = func(kind: String, e: DotMapEntity, on: bool) -> void: fx.append([kind, e.targetname, on])
	io.event_fn = func(kind: String, data: Dictionary) -> void: ev.append([kind, data])
	_check(io.attach_sounds([{"entity": 4, "stand_in": "machine", "looped": true}, {"entity": 5, "stand_in": ""}]) == 1, "one ambient sound has a free stand-in, the voice has none")
	io.start()
	_check(fx.has(["steam", "steam", false]) and fx.has(["sprite", "spr", true]), "map start tells the game each effect's state: %s" % [fx])
	io.send("steam", "TurnOn")
	_check(fx.has(["steam", "steam", true]), "TurnOn")
	io.send("steam", "TurnOff")
	_check(fx[fx.size() - 1] == ["steam", "steam", false], "TurnOff")
	io.send("spr", "HideSprite")
	_check(fx[fx.size() - 1] == ["sprite", "spr", false], "HideSprite")
	io.send("shake", "StartShake")
	_check(ev[0][0] == "shake", "StartShake is an event")
	var bodies := [_body(1, Vector3(1, 0, 0)), _body(2, Vector3(50, 0, 0))]
	var vols := DotMapVolumes.build(DotMapEntities.from_manifest({}), io)
	var hit: Array = []
	io.damage_fn = func(body: Variant, amount: float, kind: String, _a: Variant) -> void: hit.append([body, amount, kind])
	io.send("boom", "Explode")
	vols.step(bodies)
	_check(hit.size() == 1 and hit[0][0] == "b1" and hit[0][2] == "blast" and hit[0][1] > 50.0, "an explosion hurts the body in its radius, not the far one: %s" % [hit])
	hit.clear()
	io.send("dud", "Explode")
	vols.step(bodies)
	_check(hit.is_empty() and ev.any(func(e: Array) -> bool: return e[0] == "explosion"), "no-damage flag: the effect, no hurt")
	var at: Vector3 = (io.find("steam")[0] as DotMapEntity).origin(io)
	_check(at.is_equal_approx(Vector3(2.54, 7.62, -5.08)), "origin is source (100, 200, 300) in Godot axes and metres: %s" % [at])
	fx.clear()
	io.send("hum", "PlaySound")
	io.send("hum", "StopSound")
	io.send("hum", "ToggleSound")
	_check(fx == [["sound", "hum", true], ["sound", "hum", false], ["sound", "hum", true]], "play, stop, toggle go to the effect callable: %s" % [fx])
	io.send("hum", "Volume", "10")
	io.send("voice", "PlaySound")
	var hum := io.find("hum")[0] as DotMapSound
	_check(fx.size() == 3 and hum.volume == 1.0 and hum.stand_in == "machine", "volume input; a sound with no stand-in stays silent")
	io.send("fire", "StartFire")
	hit.clear()
	var ticks := io.ticks_for(0.5)
	io.advance(ticks - io.now % ticks)
	vols.step(bodies)
	_check(hit.size() == 1 and hit[0][2] == "burn", "a burning fire hurts what stands in it")
	io.send("fire", "Extinguish")
	hit.clear()
	io.advance(ticks)
	vols.step(bodies)
	_check(hit.is_empty(), "an extinguished one does not")
	_check(io.coverage()["unhandled"].is_empty(), "no input went unhandled: %s" % [io.coverage()["unhandled"]])
	_done()


func _test_commands() -> void:
	_section("map commands: never run, split, judged against the allow-list")
	var io := DotMapIO.new()
	io.load_records([_rec(0, "point_servercommand", "cmd")])
	io.command_allow = PackedStringArray(["sv_gravity", "mp_*", "exec", "sv_password"])
	var ev: Array = []
	io.event_fn = func(kind: String, data: Dictionary) -> void: ev.append([kind, data["name"]])
	var cmd := io.find("cmd")[0] as DotMapEntity
	io.record_command(cmd, "sv_gravity 400; say hi there; quit")
	_check(io.commands.size() == 3 and ev == [["cvar", "sv_gravity"], ["say", "say"]], "a line is split on ; and each part judged: %s" % [ev])
	var v := DotMapCommand.judge("exec evil.cfg", io.command_allow)
	_check(not v["allowed"] and v["reason"] == "never allowed", "exec stays denied even when the allow-list names it")
	_check(not DotMapCommand.judge("sv_password hunter2", io.command_allow)["allowed"], "so does a password")
	_check(not DotMapCommand.judge("mp_roundtime $(rm)", io.command_allow)["allowed"], "a value with shell-looking characters is denied")
	_check(not DotMapCommand.judge("mp_roundtime \"3\"", io.command_allow)["allowed"], "quotes too")
	_check(DotMapCommand.judge("MP_roundtime 3", io.command_allow)["allowed"], "a plain value on a pattern is allowed, case ignored")
	_check(not DotMapCommand.judge("mp_" + "x".repeat(300), io.command_allow)["allowed"], "an overlong line is denied")
	_check(not DotMapCommand.judge("net_graph 1", io.command_allow)["allowed"], "anything unlisted is denied")
	_check(not DotMapCommand.judge("say " + "a".repeat(210), io.command_allow)["allowed"], "a chat line has a length limit")
	_check(io.coverage()["commands_denied"] == 1, "denied commands are counted")
	_done()


func _test_hurt_once_and_force() -> void:
	_section("trigger_hurt: damage once per entry, and the damage force goes to the game")
	var w := _world([_rec(0, "trigger_hurt", "once", [["damage", "200"], ["damageonce", "1"], ["damageforce", "100 0 0"]]),
			_rec(1, "trigger_hurt", "rep", [["damage", "200"], ["damageforce", "100 0 0"], ["nodmgforce", "1"]])],
			[_vol(0, "hurt", "trigger_hurt", Vector3(0, 0, 0), Vector3(4, 3, 4)), _vol(1, "hurt", "trigger_hurt", Vector3(10, 0, 0), Vector3(14, 3, 4))])
	var io: DotMapIO = w[0]
	var vols: DotMapVolumes = w[1]
	var hits: Array = []
	var forces: Array = []
	io.damage_fn = func(_b: Variant, amount: float, _k: String, a: Variant) -> void: hits.append([(a as DotMapEntity).targetname, amount])
	io.event_fn = func(kind: String, data: Dictionary) -> void:
		if kind == "damage_force":
			forces.append(data["force"])
	io.start()
	var pos := [Vector3(2, 0, 2)]
	var provider := func(_t: int) -> Array: return [_body(1, pos[0])]
	_run_ticks(io, vols, 180, provider)
	_check(hits.size() == 1 and hits[0][1] == 100.0, "damage once: one hit in three seconds of standing there: %s" % [hits])
	_check(forces.size() == 1 and (forces[0] as Vector3).is_equal_approx(Vector3(2.54, 0, 0)), "and its force, 100 units a second along x: %s" % [forces])
	pos[0] = Vector3(20, 0, 20)
	_run_ticks(io, vols, 2, provider)
	pos[0] = Vector3(2, 0, 2)
	_run_ticks(io, vols, 40, provider)
	_check(hits.size() == 2, "leaving and coming back is a new entry: hurt again")
	hits.clear()
	forces.clear()
	pos[0] = Vector3(12, 0, 2)
	_run_ticks(io, vols, 90, provider)
	_check(hits.size() == 3, "without damage once it keeps hitting every hurtrate: %d" % hits.size())
	_check(forces.is_empty(), "nodmgforce sends no force")
	io.damage_fn = Callable()
	io.event_fn = Callable()
	_done()


func _test_soundscapes() -> void:
	_section("env_soundscape: the nearest enabled one that covers a player, proxies, and a change is an event")
	var w := _world([
			_rec(0, "env_soundscape", "sc_a", [["origin", "0 0 0"], ["radius", "400"], ["soundscape", "Alley"], ["position0", "spot"]]),
			_rec(1, "env_soundscape", "sc_b", [["origin", "800 0 0"], ["radius", "400"], ["soundscape", "Street"]]),
			_rec(2, "env_soundscape_proxy", "sc_p", [["origin", "1600 0 0"], ["radius", "400"], ["mainsoundscapename", "sc_a"]]),
			_rec(3, "info_target", "spot", [["origin", "0 100 0"]])], [])
	var io: DotMapIO = w[0]
	var vols: DotMapVolumes = w[1]
	var ev: Array = []
	io.event_fn = func(kind: String, data: Dictionary) -> void:
		if kind == "soundscape":
			ev.append(data)
	io.start()
	var pos := [Vector3(1, 0, 0)]
	var provider := func(_t: int) -> Array: return [_body(1, pos[0])]
	_run_ticks(io, vols, 2, provider)
	_check(ev.size() == 1 and ev[0]["name"] == "Alley", "inside the first radius: its soundscape, once (not every tick)")
	_check((ev[0]["positions"] as Array).size() == 1 and (ev[0]["positions"][0] as Vector3).is_equal_approx(Vector3(0, 0, -2.54)), "with the named position it plays at")
	pos[0] = Vector3(20.3, 0, 0)
	_run_ticks(io, vols, 1, provider)
	_check(ev.size() == 2 and ev[1]["name"] == "Street", "walking to the second: it changes")
	pos[0] = Vector3(40.6, 0, 0)
	_run_ticks(io, vols, 1, provider)
	_check(ev.size() == 3 and ev[2]["name"] == "Alley", "a proxy plays the soundscape it points at")
	pos[0] = Vector3(100, 0, 0)
	_run_ticks(io, vols, 1, provider)
	_check(ev.size() == 4 and ev[3]["name"] == "", "out of every radius: none")
	pos[0] = Vector3(1, 0, 0)
	io.send("sc_a", "Disable")
	_run_ticks(io, vols, 1, provider)
	_check(ev.size() == 4, "a disabled soundscape is not chosen (still none)")
	io.send("sc_a", "Enable")
	_run_ticks(io, vols, 1, provider)
	_check(ev.size() == 5 and ev[4]["name"] == "Alley", "enabled again: heard again")
	io.event_fn = Callable()
	_done()


func _test_trigger_soundscape() -> void:
	_section("trigger_soundscape: standing in the volume plays the triggerable scape it names, wherever the player is")
	var w := _world([
			_rec(0, "env_soundscape_triggerable", "sc_t", [["origin", "5000 0 0"], ["radius", "100"], ["soundscape", "Cave"]]),
			_rec(1, "trigger_soundscape", "ts", [["soundscape", "sc_t"]])],
			[_vol(1, "soundscape", "trigger_soundscape", Vector3(0, 0, 0), Vector3(4, 3, 4), {"targetname": "ts"})])
	var io: DotMapIO = w[0]
	var vols: DotMapVolumes = w[1]
	var ev: Array = []
	io.event_fn = func(kind: String, data: Dictionary) -> void:
		if kind == "soundscape":
			ev.append(data)
	io.start()
	var pos := [Vector3(10, 0, 0)]
	var provider := func(_t: int) -> Array: return [_body(1, pos[0])]
	_run_ticks(io, vols, 2, provider)
	_check(ev.is_empty(), "far from a triggerable scape and outside the volume: silence")
	pos[0] = Vector3(1, 0, 1)
	_run_ticks(io, vols, 2, provider)
	_check(ev.size() == 1 and ev[0]["name"] == "Cave", "entering the trigger plays its scape, though the scape's radius is far away")
	pos[0] = Vector3(10, 0, 0)
	_run_ticks(io, vols, 2, provider)
	_check(ev.size() == 2 and ev[1]["name"] == "", "leaving it stops the scape")
	io.send("ts", "Disable")
	pos[0] = Vector3(1, 0, 1)
	_run_ticks(io, vols, 2, provider)
	_check(ev.size() == 2, "a disabled trigger plays nothing")
	io.event_fn = Callable()
	_done()


func _test_movers_push_and_block() -> void:
	_section("a moving door pushes the body in its way, hurts and turns back one it cannot move")
	var rec := {"entity": 0, "model": 1, "kind": "slide", "classname": "func_door", "targetname": "slab",
			"direction": [1, 0, 0], "distance": 2.0, "travel_time": 2.0, "wait": 3.0, "origin": [0, 0, 0],
			"mins": [-2.2, 0.0, -1.0], "maxs": [-1.2, 3.0, 1.0], "solid": true}
	var w := _world([_rec(0, "func_door", "slab", [["dmg", "10"]])], [], 20)
	var io: DotMapIO = w[0]
	var vols: DotMapVolumes = w[1]
	io.bind_movers([DotMapMover.from_record(rec)])
	var slab := io.entity_of(0) as DotMapMoverNode
	var moves: Array = []
	var hits: Array = []
	io.move_fn = func(_b: Variant, v: Variant) -> void: moves.append(v)
	io.damage_fn = func(_b: Variant, amount: float, kind: String, _a: Variant) -> void: hits.append([amount, kind])
	io.start()
	var provider := func(_t: int) -> Array: return [_body(1, Vector3(0, 0, 0))]
	_run_ticks(io, vols, 30, provider)
	_check(moves.is_empty() and hits.is_empty(), "a closed door pushes nobody")
	io.send("slab", "Open")
	_run_ticks(io, vols, 10, provider)
	_check(moves.is_empty(), "and one still far away pushes nobody")
	_run_ticks(io, vols, 10, provider)
	_check(not moves.is_empty() and (moves[0] as Vector3).is_equal_approx(Vector3(1, 0, 0)), "reaching the body it pushes it along at the door's 1 m/s: %s" % [moves.slice(0, 1)])
	_run_ticks(io, vols, 8, provider)
	_check(hits.size() >= 1 and hits[0][0] == 10.0 and hits[0][1] == "crush", "a body that does not move is crushed for the dmg key: %s" % [hits])
	_check(slab._to == 0.0, "and a door with a wait turns back")
	var motions := io.history.filter(func(h: Dictionary) -> bool: return h["key"] == "motion")
	_check(motions.size() >= 2, "the reversal is a new motion record for clients")
	var w2 := _world([_rec(0, "func_door", "slab", [["dmg", "10"]])], [], 20)
	var io2: DotMapIO = w2[0]
	io2.bind_movers([DotMapMover.from_record(rec)])
	var pos := [Vector3(0, 0, 0)]
	var hits2: Array = []
	io2.move_fn = func(_b: Variant, v: Variant) -> void: pos[0] = (pos[0] as Vector3) + (v as Vector3) / 20.0
	io2.damage_fn = func(_b: Variant, amount: float, _k: String, _a: Variant) -> void: hits2.append(amount)
	io2.start()
	io2.send("slab", "Open")
	var provider2 := func(_t: int) -> Array: return [_body(1, pos[0])]
	_run_ticks(io2, w2[1], 40, provider2)
	_check(hits2.is_empty() and (io2.entity_of(0) as DotMapMoverNode)._to == 1.0, "a body the game moves along is never blocked: no damage, no reversal")
	_check((pos[0] as Vector3).x > 0.4, "and it is carried ahead of the door: %s" % [pos[0]])
	for i in [io, io2]:
		i.move_fn = Callable()
		i.damage_fn = Callable()
	_done()


func _office_world(doc: Dictionary) -> Array:
	var io := DotMapIO.new()
	io.rate = 60
	io.rng_seed = 1
	io.record_history = true
	_check(io.load_document(doc).ok, "the Office document loads")
	var ents := DotMapEntities.from_manifest({"volumes": [
		_vol(128, "hurt", "trigger_hurt", Vector3(4, 0, 0), Vector3(8, 4, 8), {"targetname": "Obstacle2_Hurt"}),
		_vol(130, "multiple", "trigger_multiple", Vector3(0, 0, 0), Vector3(8, 4, 8), {"targetname": "Obstacle2_trigger", "wait": 1.0}),
	]})
	return [io, DotMapVolumes.build(ents, io)]


func _test_office_timing(doc: Dictionary) -> void:
	_section("Office: the lava room's hurt timing from the map's own outputs (a player standing in it)")
	var w := _office_world(doc)
	var io: DotMapIO = w[0]
	var vols: DotMapVolumes = w[1]
	var hits: Array = []
	io.damage_fn = func(_b: Variant, amount: float, _kind: String, attacker: Variant) -> void:
		hits.append([io.now, amount, (attacker as DotMapEntity).targetname])
	io.start()
	var pos := [Vector3(2, 0, 4)]
	var provider := func(_t: int) -> Array: return [_body(1, pos[0], "player", "p1")]
	_run_ticks(io, vols, 1, provider)
	var t0 := io.now
	var hurt := io.find("Obstacle2_Hurt")[0] as DotMapEntity
	_check(t0 == 1 and not hurt.enabled and hits.is_empty(), "map start: the hurt volume is off and a player inside it is not hurt")
	var trig_hits := 0
	for h: Dictionary in io.history:
		if h["name"] == "Obstacle2_trigger" and h["key"] == "triggered":
			trig_hits += 1
	_check(trig_hits == 1, "the player standing in the trigger on tick 1 started the 3 s timer")
	_run_ticks(io, vols, 98, provider)
	pos[0] = Vector3(6, 0, 4)
	_run_ticks(io, vols, 80, provider)
	_check(hits.is_empty(), "walking into the hurt volume while it is off costs nothing (tick %d)" % io.now)
	_run_ticks(io, vols, 2, provider)
	_check(hits.size() == 1 and hits[0][0] == t0 + 180, "the hurt volume comes on 3 s after entry and hits at once: %s" % [hits])
	_check(hits.size() == 1 and hits[0][1] == 100.0 and hits[0][2] == "Obstacle2_Hurt", "200 a second at hurtrate 0.5 is 100, enough for a 100 hp player")
	_run_ticks(io, vols, 90, provider)
	var ticks: Array = hits.map(func(h: Array) -> int: return h[0])
	_check(ticks == [t0 + 180, t0 + 210, t0 + 240, t0 + 270], "and again every 0.5 s while he stays: %s" % [ticks])
	io.damage_fn = Callable()  # the lambda captures io: a cycle, reported as a leak at exit
	_done()


func _test_office_second_entry(doc: Dictionary) -> void:
	_section("Office: leaving is safe, the trigger re-arms at 6 s, and entering again undoes the hurt volume")
	var w := _office_world(doc)
	var io: DotMapIO = w[0]
	var vols: DotMapVolumes = w[1]
	var hits: Array = []
	io.damage_fn = func(_b: Variant, amount: float, _k: String, _a: Variant) -> void: hits.append([io.now, amount])
	io.start()
	var pos := [Vector3(2, 0, 4)]
	var provider := func(_t: int) -> Array: return [_body(1, pos[0], "player", "p1")]
	_run_ticks(io, vols, 99, provider)
	pos[0] = Vector3(6, 0, 4)
	_run_ticks(io, vols, 82, provider)
	_check(hits.size() == 1, "first hit at 3 s")
	pos[0] = Vector3(50, 0, 50)
	_run_ticks(io, vols, 90, provider)
	_check(hits.size() == 1 and io.now == 271, "he steps out at once: no more hits")
	var hurt := io.find("Obstacle2_Hurt")[0] as DotMapEntity
	var trig := io.find("Obstacle2_trigger")[0] as DotMapEntity
	_check(hurt.enabled and not trig.enabled, "the hurt volume stays on until the next entry; the trigger is still disarmed")
	_run_ticks(io, vols, 89, provider)
	_check(not trig.enabled, "one tick before 6 s still disarmed")
	_run_ticks(io, vols, 1, provider)
	_check(trig.enabled and io.now == 361, "armed again at 6 s (tick %d)" % io.now)
	pos[0] = Vector3(2, 0, 4)
	hits.clear()
	_run_ticks(io, vols, 1, provider)
	pos[0] = Vector3(6, 0, 4)
	_run_ticks(io, vols, 5, provider)
	_check(not hurt.enabled and hits.is_empty(), "entering again undoes the hurt volume before it can hit")
	var snap := io.snapshot()
	_check((snap["entities"][128] as Dictionary)["enabled"] == false, "a joiner's snapshot says it is off")
	io.damage_fn = Callable()  # the lambda captures io: a cycle, reported as a leak at exit
	_done()
