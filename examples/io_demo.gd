extends Node

## [DotMapIO] on synthetic maps (delays, fire-once counts, cycles, logic classes, the extension
## points) and on the Office course's real timed hazards.
##
## [codeblock]
## godot --headless --path . res://examples/io_demo.tscn
## [/codeblock]
##
## [code]examples/io/office_io.doc.json[/code] is the part of that map's source document reachable
## from its map-start logic and its timed trigger (Obstacle2): the expected times are read from
## the map's own links, then compared with the simulation.

const CHECKS := 180
const SECTIONS := 14
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
	print("dot-map io")
	_test_delay_and_times()
	_test_relay()
	_test_cycles()
	_test_timer_and_counter()
	_test_case_compare_branch()
	_test_inputs_and_targets()
	_test_extension_points()
	_test_commands_and_document()
	_test_map_scripts()
	_test_catalogue_and_new_classes()
	_test_score_ui_and_pairs()
	_test_beats_and_winlose()
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(OFFICE))
	if doc is Dictionary:
		_test_office_start(doc)
		_test_office_lava(doc)
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


func _io(records: Array, rate: int = 20, seed_: int = 1) -> DotMapIO:
	var io := DotMapIO.new()
	io.rate = rate
	io.rng_seed = seed_
	io.record_history = true
	var r := io.load_records(records)
	_check(r.ok, "records load: %s" % r)
	return io


## Ticks at which [param key] of the entity named [param tname] became [param value].
func _when(io: DotMapIO, tname: String, key: String, value: Variant) -> Array:
	var out: Array = []
	for h: Dictionary in io.history:
		if h["name"] == tname and h["key"] == key and h["value"] == value:
			out.append(h["tick"])
	return out


func _test_delay_and_times() -> void:
	_section("a link's delay is whole ticks of the game's tick, and times counts down")
	var io := _io([
		_rec(0, "logic_relay", "r", [], [["OnTrigger", "t", "Disable", "", 0.5], ["OnTrigger", "t", "Enable", "", 1.0, 2]]),
		_rec(1, "info_target", "t"),
	])
	io.send("r", "Trigger")
	io.advance(9)
	_check(_when(io, "t", "enabled", false).is_empty(), "nothing before the delay")
	io.advance(1)
	_check(_when(io, "t", "enabled", false) == [10], "0.5 s at 20 ticks a second is tick 10: %s" % [_when(io, "t", "enabled", false)])
	io.advance(10)
	_check(_when(io, "t", "enabled", true) == [20], "1.0 s is tick 20")
	io.send("r", "Trigger")
	io.send("r", "Trigger")
	io.advance(40)
	_check(io.pending() == 0, "nothing left pending")
	var r: Array = (io.find("r")[0] as DotMapEntity).links
	_check(r.size() == 1, "the link with times=2 is gone after two firings (links left: %d)" % r.size())
	_check(io.send("nobody", "Trigger").code() == DotError.CODE_INVALID, "an unknown target is a result, not a crash")
	var io2 := _io([_rec(0, "logic_relay", "r", [], [["OnTrigger", "t", "Disable", "", 1.0]]), _rec(1, "info_target", "t")], 30)
	io2.send("r", "Trigger")
	io2.advance(29)
	var early := io2.history.is_empty()
	io2.advance(1)
	_check(early and _when(io2, "t", "enabled", false) == [30], "the same delay at 30 ticks a second is tick 30")
	_done()


func _test_relay() -> void:
	_section("relay: fire once, disabled, CancelPending")
	var io := _io([
		_rec(0, "logic_relay", "once", [["spawnflags", "1"]], [["OnTrigger", "t", "FireUser1"]]),
		_rec(1, "info_target", "t", [], [["OnUser1", "c", "Add", "1"]]),
		_rec(2, "math_counter", "c"),
		_rec(3, "logic_relay", "slow", [], [["OnTrigger", "c", "Add", "10", 2.0]]),
		_rec(4, "logic_relay", "off", [["StartDisabled", "1"]], [["OnTrigger", "c", "Add", "100"]]),
	])
	var c := io.find("c")[0] as DotMapCounter
	io.send("once", "Trigger")
	io.send("once", "Trigger")
	_check(c.value == 1.0, "a fire-once relay fires once (counter %s)" % c.value)
	io.send("off", "Trigger")
	_check(c.value == 1.0, "a relay that starts disabled does not fire")
	io.send("off", "Enable")
	io.send("off", "Trigger")
	_check(c.value == 101.0, "Enable lets it fire")
	io.send("slow", "Trigger")
	io.advance(20)
	io.send("slow", "CancelPending")
	io.advance(40)
	_check(c.value == 101.0, "CancelPending dropped the delayed output (counter %s)" % c.value)
	io.send("slow", "Trigger")
	io.advance(40)
	_check(c.value == 111.0, "and the relay still works afterwards")
	_done()


func _test_cycles() -> void:
	_section("cycles: zero-delay loops are cut, delayed loops run")
	var io := _io([
		_rec(0, "logic_relay", "a", [], [["OnTrigger", "b", "Trigger"], ["OnTrigger", "n", "Add", "1"]]),
		_rec(1, "logic_relay", "b", [], [["OnTrigger", "a", "Trigger"]]),
		_rec(2, "math_counter", "n"),
	])
	io.send("a", "Trigger")
	_check(io.loop_trips > 0, "a zero-delay cycle trips the guard")
	_check((io.find("n")[0] as DotMapCounter).value == float(io.max_chain / 2), "it ran max_chain hops then stopped (%s)" % (io.find("n")[0] as DotMapCounter).value)
	_check(io.pending() == 0 and io.delivered < 1000, "nothing runs away (delivered %d)" % io.delivered)
	var io2 := _io([
		_rec(0, "logic_relay", "a", [], [["OnTrigger", "b", "Trigger", "", 1.0], ["OnTrigger", "n", "Add", "1"]]),
		_rec(1, "logic_relay", "b", [], [["OnTrigger", "a", "Trigger", "", 1.0]]),
		_rec(2, "math_counter", "n"),
	])
	io2.send("a", "Trigger")
	io2.advance(20 * 10)
	var n := (io2.find("n")[0] as DotMapCounter).value
	_check(io2.loop_trips == 0 and n == 6.0, "a loop with a delay is legal: one beat per 2 s, 6 beats in 10 s (got %s)" % n)
	_check(io2.pending() == 1, "and it is still going")
	_done()


func _test_timer_and_counter() -> void:
	_section("timer and counter: beats, high/low, bounds, a counter-to-break chain")
	var io := _io([
		_rec(0, "logic_timer", "tm", [["RefireTime", "2"]], [["OnTimer", "c", "Add", "1"], ["OnTimerHigh", "h", "FireUser1"], ["OnTimerLow", "l", "FireUser1"]]),
		_rec(1, "math_counter", "c", [["max", "3"]], [["OnHitMax", "glass", "Break"], ["OutValue", "log", "FireUser1"]]),
		_rec(2, "func_breakable", "glass"),
		_rec(3, "info_target", "h", [], [["OnUser1", "hh", "Add", "1"]]),
		_rec(4, "info_target", "l", [], [["OnUser1", "ll", "Add", "1"]]),
		_rec(5, "math_counter", "hh"),
		_rec(6, "math_counter", "ll"),
		_rec(7, "info_target", "log"),
	])
	var broke := []
	io.register_handler("func_breakable", func(_e: DotMapEntity, input: String, _p: String, _a: Variant, _c: Variant) -> bool:
		if input.to_lower() == "break":
			broke.append(true)
			return true
		return false)
	io.start()
	io.advance(119)
	var c := io.find("c")[0] as DotMapCounter
	_check(c.value == 2.0 and broke.is_empty(), "one tick before 6 s: two beats, not broken yet (counter %s)" % c.value)
	io.advance(1)
	_check(broke.size() == 1, "the third beat (6 s, tick 120 at 20 a second) hits max and breaks the glass once: %d" % broke.size())
	_check(c.value == 3.0, "the counter stays at its max")
	io.advance(20 * 10)
	_check(c.value == 3.0 and broke.size() == 1, "further Add stays clamped and does not break it again")
	var hh := (io.find("hh")[0] as DotMapCounter).value
	var ll := (io.find("ll")[0] as DotMapCounter).value
	_check(hh + ll == 8.0 and absf(hh - ll) <= 1.0, "high and low alternate (%s, %s)" % [hh, ll])
	io.send("tm", "Disable")
	io.advance(200)
	_check(io.pending() == 0, "a disabled timer queues nothing")
	io.send("tm", "Enable")
	io.advance(39)
	var before := (io.find("hh")[0] as DotMapCounter).value + (io.find("ll")[0] as DotMapCounter).value
	io.advance(1)
	_check((io.find("hh")[0] as DotMapCounter).value + (io.find("ll")[0] as DotMapCounter).value == before + 1.0, "Enable re-arms from now: first beat 2 s later")
	var rnd := _io([_rec(0, "logic_timer", "t", [["UseRandomTime", "1"], ["LowerRandomBound", "1"], ["UpperRandomBound", "3"]], [["OnTimer", "n", "Add", "1"]]), _rec(1, "math_counter", "n")], 20, 7)
	var rnd2 := _io([_rec(0, "logic_timer", "t", [["UseRandomTime", "1"], ["LowerRandomBound", "1"], ["UpperRandomBound", "3"]], [["OnTimer", "n", "Add", "1"]]), _rec(1, "math_counter", "n")], 20, 7)
	rnd.start()
	rnd2.start()
	rnd.advance(600)
	rnd2.advance(600)
	var nn := (rnd.find("n")[0] as DotMapCounter).value
	_check(nn >= 10.0 and nn <= 30.0 and nn == (rnd2.find("n")[0] as DotMapCounter).value, "a random timer is deterministic for a seed and between its bounds (%s beats in 30 s)" % nn)
	_done()


func _test_case_compare_branch() -> void:
	_section("case, compare, branch")
	var recs := [
		_rec(0, "logic_case", "k", [["Case01", "a"], ["Case02", "b"], ["Case03", "c"]],
			[["OnCase01", "x", "Add", "1"], ["OnCase02", "y", "Add", "1"], ["OnCase03", "z", "Add", "1"], ["OnDefault", "d", "Add", "1"]]),
		_rec(1, "math_counter", "x"), _rec(2, "math_counter", "y"), _rec(3, "math_counter", "z"), _rec(4, "math_counter", "d"),
		_rec(5, "logic_compare", "cmp", [["CompareValue", "5"]], [["OnLessThan", "x", "Add", "1"], ["OnGreaterThan", "y", "Add", "1"], ["OnEqualTo", "z", "Add", "1"]]),
		_rec(6, "logic_branch", "br", [["InitialValue", "0"]], [["OnTrue", "x", "Add", "10"], ["OnFalse", "y", "Add", "10"]]),
	]
	var io := _io(recs)
	io.send("k", "InValue", "B")
	io.send("k", "InValue", "nope")
	_check((io.find("y")[0] as DotMapCounter).value == 1.0 and (io.find("d")[0] as DotMapCounter).value == 1.0, "InValue matches case-insensitively, else OnDefault")
	var picks: Array = []
	for s in range(1, 9):
		var p := _io(recs, 20, s)
		p.send("k", "PickRandom")
		picks.append("%s%s%s" % [(p.find("x")[0] as DotMapCounter).value, (p.find("y")[0] as DotMapCounter).value, (p.find("z")[0] as DotMapCounter).value])
		var again := _io(recs, 20, s)
		again.send("k", "PickRandom")
		_check((again.find("x")[0] as DotMapCounter).value == (p.find("x")[0] as DotMapCounter).value
				and (again.find("y")[0] as DotMapCounter).value == (p.find("y")[0] as DotMapCounter).value, "pick for seed %d repeats" % s)
	var distinct := {}
	for p: String in picks:
		distinct[p] = true
	_check(distinct.size() == 3, "eight seeds reach all three cases (%s)" % [distinct.keys()])
	var sh := _io(recs)
	for i in 3:
		sh.send("k", "PickRandomShuffle")
	_check((sh.find("x")[0] as DotMapCounter).value == 1.0 and (sh.find("y")[0] as DotMapCounter).value == 1.0 and (sh.find("z")[0] as DotMapCounter).value == 1.0, "a shuffle round hits each case once")
	io.send("cmp", "SetValueCompare", "3")
	io.send("cmp", "SetValueCompare", "9")
	io.send("cmp", "SetValueCompare", "5")
	_check((io.find("x")[0] as DotMapCounter).value == 1.0 and (io.find("y")[0] as DotMapCounter).value == 2.0 and (io.find("z")[0] as DotMapCounter).value == 1.0, "compare: less, greater, equal")
	io.send("br", "Test")
	io.send("br", "Toggle")
	io.send("br", "Test")
	_check((io.find("y")[0] as DotMapCounter).value == 12.0 and (io.find("x")[0] as DotMapCounter).value == 11.0, "branch: false then, after Toggle, true")
	_done()


func _test_inputs_and_targets() -> void:
	_section("common inputs and target names")
	var io := _io([
		_rec(0, "logic_relay", "r", [], [["OnTrigger", "grp_*", "Disable"], ["OnTrigger", "info_target", "FireUser2"], ["OnTrigger", "!activator", "Ping", "x"]]),
		_rec(1, "func_brush", "grp_a"),
		_rec(2, "func_brush", "GRP_b"),
		_rec(3, "info_target", "t", [], [["OnUser2", "!self", "AddOutput", "OnUser3 c:Add:5:0:-1"], ["OnUser3", "c", "Add", "7"]]),
		_rec(4, "math_counter", "c"),
		_rec(5, "func_brush", "k"),
		_rec(6, "env_thing", "child"),
	])
	var pinged: Array = []
	io.actor_fn = func(body: Variant, input: String, param: String, _caller: Variant) -> void:
		pinged.append([body, input, param])
	io.send("r", "Trigger", "", 0.0, "the body")
	_check(not (io.find("grp_a")[0] as DotMapEntity).enabled and not (io.find("grp_b")[0] as DotMapEntity).enabled, "a * pattern reaches every name, case-insensitively")
	_check(pinged == [["the body", "Ping", "x"]], "!activator goes to the game's actor callable: %s" % [pinged])
	var t := io.find("t")[0] as DotMapEntity
	_check(t.links.size() == 3, "the class-name target reached the info_target, whose AddOutput added a link")
	io.send("t", "FireUser3")
	io.send("t", "FireUser3")
	io.send("t", "FireUser3")
	_check(io.send("t", "FireUser1").ok, "FireUser1 has no links and is harmless")
	io.send("k", "Kill")
	_check(io.find("k").is_empty() and io.send("k", "Enable").code() == DotError.CODE_INVALID, "a killed entity cannot be found")
	io.send("t", "SetVolume", "3")
	_check(int(io.unhandled.get("info_target|setvolume", 0)) == 1, "an input nobody implements is counted: %s" % io.unhandled)
	_check(io.coverage()["unhandled"].has("info_target|setvolume"), "and reported by coverage()")
	_done()


func _test_extension_points() -> void:
	_section("a game's handlers, classes and callables")
	var io := _io([
		_rec(0, "logic_relay", "r", [], [["OnTrigger", "door", "Open"], ["OnTrigger", "door", "Enable"]]),
		_rec(1, "func_door", "door"),
		_rec(2, "game_text", "msg"),
	])
	var seen: Array = []
	_check(io.register_handler("func_door", func(e: DotMapEntity, input: String, _p: String, _a: Variant, _c: Variant) -> bool:
		seen.append(input)
		return input == "Open" and e.classname == "func_door").ok, "a handler registers")
	_check(not io.register_handler("", Callable()).ok, "an empty one is refused with a result")
	io.send("r", "Trigger")
	_check(seen == ["Open", "Enable"], "the handler sees every input first: %s" % [seen])
	_check(int(io.unhandled.get("func_door|open", 0)) == 0 and not (io.find("door")[0] as DotMapEntity).enabled == false, "the one it claimed is not counted, the other ran built in")
	io.event("hint", {"text": "hi"})
	io.damage(null, 1.0, "burn", null)
	_check(io.missing_callables.has("event.hint") and io.missing_callables.has("damage"), "an unset callable is a counted no-op: %s" % io.missing_callables)
	var got: Array = []
	io.event_fn = func(kind: String, data: Dictionary) -> void:
		got.append([kind, data])
	io.event("hint", {"text": "hi"})
	_check(got.size() == 1 and got[0][0] == "hint", "an assigned callable is called")
	_check(not io.register_class("", null).ok and io.register_class("game_text", DotMapRelay).ok, "register_class takes a script")
	var io2 := DotMapIO.new()
	io2.register_class("game_text", DotMapRelay)
	io2.load_records([_rec(0, "game_text", "m", [], [["OnTrigger", "m", "FireUser1"]])])
	_check(io2.entities[0] is DotMapRelay, "and builds that class")
	_check(io.describe()["entities"] == 3 and io.describe()["callables"]["event"], "describe() reports the runtime")
	_done()


func _test_commands_and_document() -> void:
	_section("commands are recorded not run; the document reader refuses what it cannot read")
	var io := _io([
		_rec(0, "point_servercommand", "cmd"),
		_rec(1, "logic_relay", "r", [], [
			["OnTrigger", "cmd", "Command", "say hello"], ["OnTrigger", "cmd", "Command", "sv_gravity 400"],
			["OnTrigger", "cmd", "Command", "mp_roundtime 3"], ["OnTrigger", "cmd", "Command", "rcon_password x"],
			["OnTrigger", "cmd", "Command", "quit"]]),
	])
	io.command_allow = PackedStringArray(["sv_gravity", "mp_*"])
	var events: Array = []
	io.event_fn = func(kind: String, data: Dictionary) -> void:
		events.append([kind, data["name"]])
	io.send("r", "Trigger")
	_check(io.commands.size() == 5, "all five recorded")
	_check(events == [["say", "say"], ["cvar", "sv_gravity"], ["cvar", "mp_roundtime"]], "only a chat line and allow-listed cvars reach the game: %s" % [events])
	_check(io.coverage()["commands_denied"] == 2, "the others are denied and counted")
	_check(io.load_document({"format": "other"}).code() == DotError.CODE_PARSE, "a foreign document is a parse failure")
	_check(io.load_document({"format": "dot-bsp-source", "version": 9, "entities": []}).code() == DotError.CODE_VERSION, "a newer version is refused")
	_check(io.load_document({"format": "dot-bsp-source", "version": 1}).code() == DotError.CODE_PARSE, "a document without entities is refused")
	_done()


func _test_map_scripts() -> void:
	_section("lua_run: translated operations are replayed as events, script text is never run")
	var hostile := "os.execute('touch /tmp/dotmap_pwned') RunConsoleCommand('rcon_password','x')"
	var io := _io([
		_rec(0, "lua_run", "speed", [["code", "for i, ply in pairs(player.GetAll()) do if (ply:IsValid()) then ply:SetRunSpeed( 185 ) end end"]]),
		_rec(1, "lua_run", "evil", [["code", hostile]]),
		_rec(2, "lua_run", "forged", [["code", hostile]]),
		_rec(3, "lua_run", "plain", [["code", "x = 1"]]),
		_rec(4, "logic_relay", "r", [], [["OnTrigger", "speed", "RunCode"], ["OnTrigger", "evil", "RunCode"], ["OnTrigger", "forged", "RunCode"],
			["OnTrigger", "plain", "RunCode"], ["OnTrigger", "speed", "RunPassedCode", "Foo.Bar()"]]),
	])
	io.entities[0].record["script"] = {"status": "translated", "ops": [{"op": "set_player_speed", "kind": "run", "value": 185.0}], "category": "template"}
	io.entities[1].record["script"] = {"status": "unhandled", "ops": [], "category": "other"}
	io.entities[2].record["script"] = {"status": "translated", "ops": [{"op": "set_player_speed", "kind": "run", "value": 185.0},
		{"op": "exec", "cmd": "rm -rf /"}, {"op": "set_player_speed", "kind": "run", "value": 1e9}, {"op": "kill_players", "extra": 1}], "category": "template"}
	var events: Array = []
	io.event_fn = func(kind: String, data: Dictionary) -> void:
		events.append([kind, data.get("op", ""), data.get("kind", ""), data.get("value", 0)])
	io.send("r", "Trigger")
	_check(events[0] == ["script.set_player_speed", "set_player_speed", "run", 185.0], "a translated snippet reaches the game as an event: %s" % [events])
	_check(events.size() == 2, "only the whitelisted operations are replayed, the forged ones are not: %d" % events.size())
	_check(io.scripts.size() == 7 and io.scripts.filter(func(r: Dictionary) -> bool: return not r["allowed"]).size() == 5, "every attempt is recorded, five refused")
	_check(io.coverage()["scripts_refused"] == 5, "the refusals are counted in coverage")
	_check(io.unhandled.get("lua_run|runpassedcode", 0) == 1, "RunPassedCode is an unhandled input, its text is never read")
	_check(not FileAccess.file_exists("/tmp/dotmap_pwned"), "the hostile snippet did not run")
	_check(not DotMapScript.valid_op({"op": "set_player_speed", "kind": "run"}) and not DotMapScript.valid_op("kill_players") and not DotMapScript.valid_op({"op": "cleanup_map", "delay": -1}), "malformed operations are refused")
	_check(DotMapScript.valid_op({"op": "cleanup_map", "delay": 0.25}) and DotMapScript.valid_op({"op": "kill_players"}), "and well-formed ones pass")
	_check(DotMapCommand.judge("lua_run os.execute('x')", PackedStringArray(["lua_run"]))["allowed"] == false, "lua_run is still never an allowed console command")
	_check(io.load_document({"format": "dot-bsp-source", "version": 1, "entities": [_rec(0, "lua_run", "a", [["code", hostile]])]}).ok, "a stored document with a script loads")
	_check(io.entities[0] is DotMapScript and io.scripts.size() == 7, "loading a document runs nothing")
	_check(io.entities[0].keys.get("code", "") == hostile and events.size() == 2, "the code key is kept as data only")
	_done()


func _test_score_ui_and_pairs() -> void:
	_section("game_score, game_ui and logic_collision_pair")
	var io := _io([
		_rec(0, "game_score", "pts", [["points", "20"], ["spawnflags", "2"]]),
		_rec(1, "game_ui", "ui", [["spawnflags", "480"]], [["PressedAttack2", "lamp", "FireUser1"], ["UnpressedAttack2", "lamp", "FireUser2"],
				["PlayerOn", "lamp", "FireUser3"], ["PlayerOff", "lamp", "FireUser4"]]),
		_rec(2, "env_light", "lamp"),
		_rec(3, "logic_collision_pair", "", [["attach1", "seat"], ["attach2", "base"]]),
		_rec(4, "logic_collision_pair", "off", [["attach1", "a"], ["attach2", "b"], ["startdisabled", "0"]])])
	var events: Array = []
	io.event_fn = func(kind: String, data: Dictionary) -> void: events.append([kind, data])
	io.start()
	var pair_events: Array = events.filter(func(e: Array) -> bool: return e[0] == "collision_pair")
	_check(pair_events.size() == 2 and pair_events[0][1]["collide"] == false and pair_events[1][1]["collide"] == true, "a pair starts without collisions unless StartDisabled is 0")
	io.send("off", "DisableCollisions")
	io.advance(1)
	_check(events.filter(func(e: Array) -> bool: return e[0] == "collision_pair").back()[1]["collide"] == false, "DisableCollisions is told to the game")
	io.send("pts", "ApplyScore", "", 0.0, "bob")
	io.send("pts", "AddScoreCT")
	io.advance(1)
	var scores: Array = events.filter(func(e: Array) -> bool: return e[0] == "score")
	_check(scores.size() == 2 and scores[0][1]["points"] == 20 and scores[0][1]["activator"] == "bob" and scores[0][1]["to_team"] == true, "ApplyScore tells the game the points and who")
	_check(scores[1][1]["team"] == 3, "AddScoreCT names the team")
	io.feed_ui(1, {"attack2": true})
	_check(io.active_uis().is_empty(), "a game_ui that was never activated ignores the buttons")
	io.send("ui", "Activate", "", 0.0, "bob")
	io.advance(1)
	var ui_events: Array = events.filter(func(e: Array) -> bool: return e[0] == "ui_active")
	_check(ui_events.size() == 1 and ui_events[0][1]["on"] and ui_events[0][1]["freeze"] and ui_events[0][1]["player"] == "bob", "Activate freezes the holder through the game")
	io.feed_ui(1, {"attack2": true})
	io.advance(1)
	_check(io.delivered_from.get(1, 0) >= 2, "the held button fires PressedAttack2 and PlayerOn (%s)" % [io.delivered_from])
	io.feed_ui(1, {"attack2": true})
	io.advance(1)
	var after_hold: int = io.delivered_from.get(1, 0)
	io.feed_ui(1, {})
	io.advance(1)
	_check(io.delivered_from.get(1, 0) == after_hold + 1, "a held button fires once, its release fires Unpressed")
	io.feed_ui(1, {"jump": true})
	io.advance(1)
	_check(io.active_uis().is_empty() and not (events.filter(func(e: Array) -> bool: return e[0] == "ui_active").back()[1]["on"]), "jump gives the controls back (spawnflag 256)")
	_check(io.unhandled.is_empty(), "no input went unhandled: %s" % [io.unhandled])
	_done()


func _test_beats_and_winlose() -> void:
	_section("logic_beats as a beat signal and logic_winlose's ending")
	var io := _io([
		_rec(0, "logic_beats", "tempo", [["bpm", "120"], ["beatsperbar", "3"], ["disableannoucner", "1"]], [["OnBeat", "nb", "Add", "1"]]),
		_rec(1, "logic_beats", "silent"),
		_rec(2, "logic_winlose", "ending", [["slowmo", "0.25"], ["slowmoseconds", "3"], ["origin", "100 200 300"]],
				[["OnWin", "nw", "Add", "1"], ["OnLose", "nw", "Add", "10"]]),
		_rec(3, "logic_winlose", "plain"),
		_rec(4, "math_counter", "nb", [["max", "999"]]), _rec(5, "math_counter", "nw", [["max", "999"]]),
		_rec(6, "logic_beats", "frantic"), _rec(7, "logic_winlose", "endless", [["slowmo", "0.05"], ["slowmoseconds", "9999"]])], 20)
	var events: Array = []
	io.event_fn = func(kind: String, data: Dictionary) -> void: events.append([kind, data])
	var tempo := io.find("tempo")[0] as DotMapBeats
	io.start()
	io.advance(40)
	var beats: Array = events.filter(func(e: Array) -> bool: return e[0] == "beat")
	_check(beats.size() == 4, "120 bpm on a 20 Hz tick is four beats in two seconds (%d)" % beats.size())
	_check(beats[0][1]["downbeat"] == true and beats[1][1]["downbeat"] == false and beats[3][1]["downbeat"] == true and beats[3][1]["bar"] == 1, "a bar of three: the downbeat starts each")
	_check((io.find("nb")[0] as DotMapCounter).value == 4.0, "OnBeat is an output")
	_check(tempo.announcer_off() and not (io.find("silent")[0] as DotMapBeats).announcer_off(), "DisableAnnoucner is read as before")
	var frantic := io.find("frantic")[0] as DotMapBeats
	io.send("frantic", "SetBPM", "1000000")
	io.send("frantic", "Stop")
	_check(frantic.interval() >= 0.1 - 0.0001, "a huge tempo is clamped (interval %f)" % frantic.interval())
	io.send("silent", "SetBPM", "60")
	io.send("tempo", "Stop")
	io.advance(40)
	beats = events.filter(func(e: Array) -> bool: return e[0] == "beat")
	_check(beats.size() == 6, "SetBPM starts a silent entity, Stop ends the other (%d)" % beats.size())
	_check((io.find("silent")[0] as DotMapBeats).interval() == 1.0 and tempo.interval() == 0.5, "interval follows the tempo")
	events.clear()
	io.send("plain", "Lose")
	io.advance(1)
	var d: Array = events.filter(func(e: Array) -> bool: return e[0] == "round_decide")
	_check(d.size() == 1 and d[0][1]["won"] == false, "Lose asks the game to decide")
	(io.find("ending")[0] as DotMapWinLose).decided(io, true)
	(io.find("plain")[0] as DotMapWinLose).decided(io, false)
	var ends: Array = events.filter(func(e: Array) -> bool: return e[0] == "round_end")
	_check(ends.size() == 2 and ends[0][1]["time_scale"] == 0.25 and ends[0][1]["seconds"] == 3.0 and ends[0][1]["won"] == true, "decided tells the game the slow motion the keys name")
	_check(ends[0][1]["camera"] is Vector3 and ends[1][1]["camera"] == null and ends[1][1]["time_scale"] == 1.0, "a camera only when the entity has an origin; no slow motion by default")
	(io.find("endless")[0] as DotMapWinLose).decided(io, true)
	var last: Array = events.filter(func(e: Array) -> bool: return e[0] == "round_end").back()
	_check(last[1]["seconds"] == 15.0, "slowmoseconds is capped (%s)" % last[1]["seconds"])
	io.advance(1)
	_check((io.find("nw")[0] as DotMapCounter).value == 1.0, "OnWin fires on the decision")
	_check(io.unhandled.is_empty(), "no input went unhandled: %s" % [io.unhandled])
	_done()


func _test_catalogue_and_new_classes() -> void:
	_section("The catalogue, colour blend, measure movement, globals and templates")
	var io := _io([_rec(0, "math_colorblend", "blend", [["colormin", "0 0 0"], ["colormax", "255 100 50"], ["inmin", "0"], ["inmax", "10"]],
			[["OutColor", "lamp", "Color"]]),
		_rec(1, "env_light", "lamp"),
		_rec(2, "env_global", "g", [["globalstate", "lava_on"], ["initialstate", "1"], ["counter", "4"]],
			[["OutCounter", "lamp", "FireUser1"]]),
		_rec(3, "logic_measure_movement", "mm", [["measuretarget", "a"], ["target", "b"], ["targetscale", "2"]]),
		_rec(4, "point_template", "tpl", [["template01", "crate"], ["template02", "crate2"], ["spawnflags", "2"]],
			[["OnEntitySpawned", "lamp", "FireUser2"]]),
		_rec(5, "prop_physics", "crate", [["model", "box"]]),
		_rec(6, "prop_physics", "crate2")])
	var events: Array = []
	io.event_fn = func(kind: String, data: Dictionary) -> void: events.append([kind, data])
	var lamp := io.find("lamp")[0] as DotMapEntity
	io.start()
	_check((io.globals.get("lava_on", {}) as Dictionary).get("on", false) == true and io.globals["lava_on"]["counter"] == 4, "env_global starts on with its counter")
	io.send("blend", "InValue", "5")
	io.advance(1)
	_check(lamp.color == "128 50 25", "colorblend: half way between the two colours (%s)" % lamp.color)
	io.send("blend", "InValue", "99")
	io.advance(1)
	_check(lamp.color == "255 100 50", "colorblend: clamped at the maximum")
	io.send("g", "AddToCounter", "3")
	io.send("g", "TurnOff")
	io.advance(1)
	_check(io.globals["lava_on"]["counter"] == 7 and io.globals["lava_on"]["on"] == false, "env_global: counter and flag follow their inputs")
	_check(events.any(func(e: Array) -> bool: return e[0] == "measure_movement" and e[1]["pairing"]["scale"] == 2.0), "measure movement: pairing announced at map start")
	io.send("mm", "SetMeasureTarget", "c")
	io.send("mm", "Disable")
	io.advance(1)
	var last: Array = events.filter(func(e: Array) -> bool: return e[0] == "measure_movement").back()
	_check(last[1]["on"] == false and last[1]["pairing"]["measure"] == "c", "measure movement: a new target and the disable reach the game")
	var before := io.entities.size()
	io.send("tpl", "ForceSpawn")
	io.advance(1)
	_check(io.entities.size() == before + 2, "point_template: ForceSpawn adds a copy of each template (%d)" % (io.entities.size() - before))
	_check(events.filter(func(e: Array) -> bool: return e[0] == "template_spawn").size() == 2, "and tells the game for each")
	_check(events.filter(func(e: Array) -> bool: return e[0] == "template_spawn")[0][1]["maker"] == -1, "an input from nowhere has no maker")
	var copy := io.entities.back() as DotMapEntity
	_check(copy.targetname == "crate2" and copy.index == 8 and copy.classname == "prop_physics", "the copy keeps its name and gets the next free index")
	_check(io.unhandled.is_empty(), "no input went unhandled: %s" % [io.unhandled])
	var r := io.load_catalogue()
	_check(r.ok, "the shipped catalogue loads: %s" % r)
	var def := io.class_def("math_colorblend")
	_check((def.get("inputs", {}) as Dictionary).has("invalue") and (def.get("inputs", {}) as Dictionary).has("kill"), "a class has its own and the common inputs")
	_check(((def.get("keys", {}) as Dictionary).get("colormax", []) as Array) == ["color255", "255 255 255"], "keys carry a type and a default")
	var io2 := _io([_rec(0, "logic_relay", "r", [], [["OnTrigger", "r", "NoSuchInput"], ["OnSpawn", "r", "Toggle"]])])
	io2.load_catalogue()
	io2.start()
	io2.send("r", "NoSuchInput")
	io2.send("r", "TriggerWithParameter", "x")
	io2.advance(1)
	var cov := io2.coverage()
	_check(cov["catalogue"].get("logic_relay|nosuchinput") == "not in the catalogue", "coverage tells a typo from an engine input: %s" % [cov["catalogue"]])
	_check(cov["catalogue"].get("logic_relay|triggerwithparameter") == "known", "and a real input no class implements")
	_done()


func _doc_entity(doc: Dictionary, tname: String) -> Dictionary:
	for e: Dictionary in doc["entities"]:
		if str(e["targetname"]) == tname:
			return e
	return {}


func _office(doc: Dictionary, seed_: int) -> DotMapIO:
	var io := DotMapIO.new()
	io.rate = 60
	io.rng_seed = seed_
	io.record_history = true
	var r := io.load_document(doc)
	_check(r.ok, "the Office document loads: %s" % r)
	return io


func _test_office_start(doc: Dictionary) -> void:
	_section("Office: the 11 disabled hurt volumes, map start, the spawn timer")
	var io := _office(doc, 3)
	var disabled := 0
	var names := PackedStringArray()
	for e: DotMapEntity in io.entities:
		if e.classname == "trigger_hurt" and not e.enabled:
			disabled += 1
			names.append(e.targetname)
	_check(disabled == 11, "11 hurt volumes start disabled (%d: %s)" % [disabled, names])
	io.start()
	var lanes_ok := true
	for lane in ["A", "B", "C"]:
		var on := 0
		for e: DotMapEntity in io.entities:
			if e.classname == "trigger_hurt" and e.targetname.begins_with("Obstacle6_Hurt_" + lane) and e.enabled:
				on += 1
		lanes_ok = lanes_ok and on == 1
	_check(lanes_ok, "at map start exactly one hurt volume per lane is switched on")
	var again := _office(doc, 3)
	again.start()
	var same := true
	var other := _office(doc, 4)
	other.start()
	var differs := false
	for i in io.entities.size():
		if (io.entities[i] as DotMapEntity).enabled != (again.entities[i] as DotMapEntity).enabled:
			same = false
		if (io.entities[i] as DotMapEntity).enabled != (other.entities[i] as DotMapEntity).enabled:
			differs = true
	_check(same, "the same seed gives the same lane picks")
	var any_seed_differs := differs
	for s in range(5, 12):
		var o := _office(doc, s)
		o.start()
		for i in io.entities.size():
			if (io.entities[i] as DotMapEntity).enabled != (o.entities[i] as DotMapEntity).enabled:
				any_seed_differs = true
	_check(any_seed_differs, "and other seeds pick other routes")
	var spawn_doc := _doc_entity(doc, "Spawn_HURT")
	var auto := {}
	for e: Dictionary in doc["entities"]:
		if e["classname"] == "logic_auto":
			auto = e
	var measured := 0.0
	for o: Dictionary in auto["outputs"]:
		if o["target"] == "Spawn_HURT" and o["input"] == "Enable":
			measured = o["delay"]
	_check(not spawn_doc.is_empty() and measured == 20.0, "the map's own link: Spawn_HURT enabled 20 s after map start")
	var hurt := io.find("Spawn_HURT")[0] as DotMapEntity
	io.advance(20 * 60 - 1)
	_check(not hurt.enabled, "still off one tick before 20 s")
	io.advance(1)
	_check(hurt.enabled and _when(io, "Spawn_HURT", "enabled", true) == [1200], "on at tick 1200 exactly: %s" % [_when(io, "Spawn_HURT", "enabled", true)])
	_check(_when(io, "Spawn_brush", "enabled", true) == [1200], "the spawn brush too")
	var says: Array = []
	for c: Dictionary in io.commands:
		if c["kind"] == "say":
			says.append(c["tick"])
	_check(says == [0, 120, 300, 1200], "the four chat lines at 0, 2, 5 and 20 s: %s" % [says])
	var cv: Array = io.commands.filter(func(c: Dictionary) -> bool: return c["name"] == "sv_airaccelerate")
	_check(cv.size() == 1 and cv[0]["kind"] == "denied", "sv_airaccelerate is recorded and denied with no allow-list")
	_done()


func _test_office_lava(doc: Dictionary) -> void:
	_section("Office: the timed hazard (Obstacle2) reproduced from the map's own links")
	var trig := _doc_entity(doc, "Obstacle2_trigger")
	var meas := {}
	for o: Dictionary in trig["outputs"]:
		meas["%s|%s|%s" % [o["target"], o["input"], o["param"]]] = o["delay"]
	var d_on: float = meas["Obstacle2_Hurt|Enable|"]
	var d_steam: float = meas["Obstacle2_Steam|TurnOn|"]
	var d_red: float = meas["Obstacle2_Brush|Color|255 0 0"]
	var d_rearm: float = meas["Obstacle2_trigger|Enable|"]
	_check(d_on == 3.0 and d_steam == 3.0 and d_red == 3.0 and d_rearm == 6.0, "measured: on and red and steam at 3 s, trigger re-armed at 6 s")
	_check(meas["Obstacle2_Hurt|Disable|"] == 0.0 and meas["Obstacle2_trigger|Disable|"] == 0.0 and meas["Obstacle2_Brush|Color|0 255 0"] == 0.0, "and everything is undone at once on entry")
	var io := _office(doc, 1)
	io.start()
	io.advance(60)
	var t0 := io.now
	var hurt := io.find("Obstacle2_Hurt")[0] as DotMapEntity
	var tr := io.find("Obstacle2_trigger")[0] as DotMapTrigger
	var brush := io.find("Obstacle2_Brush")
	var steam := io.find("Obstacle2_Steam")
	_check(not hurt.enabled and steam.size() == 4, "before: hurt off, four steam entities share the name")
	io.touch(tr.index, "player1")
	_check(not tr.enabled and not hurt.enabled, "entry: the trigger disables itself, hurt stays off")
	io.advance(60)
	io.touch(tr.index, "player1")
	_check(io.pending() > 0 and _when(io, "Obstacle2_trigger", "triggered", t0) == [t0], "a second touch while disabled does nothing (triggered once)")
	io.advance(int(d_on * 60) - 61)
	_check(not hurt.enabled, "one tick before 3 s: hurt off")
	io.advance(1)
	_check(hurt.enabled and _when(io, "Obstacle2_Hurt", "enabled", true) == [t0 + 180], "3 s after entry the hurt volume turns on, tick %d" % (t0 + 180))
	var steam_on := true
	for s: DotMapEntity in steam:
		steam_on = steam_on and s.enabled
	_check(steam_on, "the steam turns on with it")
	_check((brush[0] as DotMapEntity).color == "255 0 0", "the brush is red")
	_check(not tr.enabled, "trigger still disarmed")
	io.advance(180)
	_check(tr.enabled and _when(io, "Obstacle2_trigger", "enabled", true) == [t0 + 360], "re-armed at 6 s, tick %d" % (t0 + 360))
	_check(hurt.enabled, "the hurt volume stays on until the next entry; nothing in the map turns it off at 6 s")
	io.advance(30)
	io.touch(tr.index, "player1")
	_check(not hurt.enabled and (brush[0] as DotMapEntity).color == "0 255 0" and not (steam[0] as DotMapEntity).enabled, "the next entry undoes it at once: hurt off, green, steam off")
	io.advance(180)
	_check(hurt.enabled and io.seconds() == float(t0 + 570) / 60.0, "and the cycle repeats 3 s after that entry")
	_done()
