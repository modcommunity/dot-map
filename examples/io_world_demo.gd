extends Node

## Toggle brushes, breakables, movers and their replication on [DotMapIO] (work package 6).
##
## [codeblock]
## godot --headless --path . res://examples/io_world_demo.tscn
## [/codeblock]
##
## Records are synthetic except the mover numbers of one real map's lifts
## ([code]examples/bsp_mesh/zm_4way_tunnel.entities.json[/code]); nodes are built here the way
## [method DotMapBspMesh.build_node] shapes them (a Node3D per model with a [code]model[/code] meta).

const CHECKS := 172
const SECTIONS := 15
const TUNNEL := "res://examples/bsp_mesh/zm_4way_tunnel.entities.json"

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()
var _entered := 0
var _completed := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("dot-map io world")
	_test_toggle_brush()
	_test_breakable()
	_test_door()
	_test_button_chain()
	_test_spinner()
	_test_train()
	_test_bind_world()
	_test_real_lifts()
	_test_replication()
	_test_determinism()
	_test_door_standin()
	_test_physbox()
	_test_spin_up()
	_test_physbox_pose()
	_test_state_transport()
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


func _io(records: Array, rate: int = 20) -> DotMapIO:
	var io := DotMapIO.new()
	io.rate = rate
	io.rng_seed = 3
	io.record_history = true
	_check(io.load_records(records).ok, "records load")
	return io


func _door_rec(entity: int, kind: String = "slide", extra: Dictionary = {}) -> DotMapMover:
	var d := {"entity": entity, "model": entity, "kind": kind, "classname": "func_door", "targetname": "door",
			"direction": [0, 1, 0], "distance": 2.0, "travel_time": 2.0, "wait": 3.0, "origin": [0, 0, 0],
			"axis": [0, 1, 0], "degrees": 90.0}
	d.merge(extra, true)
	return DotMapMover.from_record(d)


## A model node with one solid child, as the mesh builder makes.
func _model_node(model: int, at: Vector3 = Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.set_meta(&"model", model)
	n.position = at
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 4
	n.add_child(body)
	add_child(n)
	return n


func _solid(n: Node3D) -> bool:
	return (n.get_child(0) as StaticBody3D).collision_layer != 0


func _ticks(io: DotMapIO, tname: String, key: String, value: Variant) -> Array:
	var out: Array = []
	for h: Dictionary in io.history:
		if h["name"] == tname and h["key"] == key and h["value"] == value:
			out.append(h["tick"])
	return out


func _test_toggle_brush() -> void:
	_section("func_brush, func_wall_toggle and func_illusionary switch drawn and solid")
	var io := _io([
		_rec(0, "func_brush", "wall", [["model", "*1"]]),
		_rec(1, "func_wall_toggle", "gate", [["model", "*2"], ["spawnflags", "1"]]),
		_rec(2, "func_illusionary", "ghost", [["model", "*3"]]),
		_rec(3, "func_brush", "ever", [["model", "*4"], ["solidity", "2"]]),
		_rec(4, "logic_relay", "r", [], [["OnTrigger", "wall", "Disable"], ["OnTrigger", "gate", "Enable", "", 0.5], ["OnTrigger", "wall", "Alpha", "128"]]),
	])
	var n1 := _model_node(1)
	var n2 := _model_node(2)
	var n3 := _model_node(3)
	var n4 := _model_node(4)
	_check(io.bind_world(self) == 4, "four brush entities found their models by *N")
	_check(n1.visible and _solid(n1), "a func_brush starts drawn and solid")
	_check(not n2.visible and not _solid(n2), "a wall toggle with spawnflag 1 starts hidden and not solid")
	_check(n3.visible and not _solid(n3), "an illusionary brush is drawn and never solid")
	io.send("r", "Trigger")
	io.advance(10)
	_check(not n1.visible and not _solid(n1), "Disable hides it and lets bodies through")
	_check(n2.visible and _solid(n2), "Enable shows it and blocks bodies, 0.5 s (10 ticks) later")
	var mesh := MeshInstance3D.new()
	n1.add_child(mesh)
	io.send("wall", "Alpha", "64")
	_check(is_equal_approx(mesh.transparency, 1.0 - 64.0 / 255.0), "Alpha shows as the meshes' transparency: %s" % mesh.transparency)
	io.send("wall", "Alpha", "128")
	io.send("wall", "Enable")
	_check(n1.visible and _solid(n1) and (io.entity_of(0) as DotMapToggleBrush).alpha == 128, "Enable brings it back, Alpha is state")
	io.send("ever", "Disable")
	_check(not n4.visible and _solid(n4), "solidity 2 stays solid while hidden")
	io.send("ever", "Kill")
	_check(not n4.visible and not _solid(n4), "Kill takes the node out of the world")
	io.send("ghost", "Toggle")
	_check(not n3.visible and not _solid(n3), "Toggle on an illusionary brush hides it")
	n1.free()
	n2.free()
	n3.free()
	n4.free()
	_done()


func _test_breakable() -> void:
	_section("breakables: health, damage, OnBreak, propdata, glass")
	var io := _io([
		_rec(0, "func_breakable", "crate", [["health", "30"], ["model", "*5"]], [["OnBreak", "c", "Add", "1"], ["OnHealthChanged", "c", "Add", "10"]]),
		_rec(1, "math_counter", "c", [["max", "100"]]),
		_rec(2, "func_breakable", "plain", [["model", "*6"]]),
		_rec(3, "func_breakable", "trig", [["health", "5"], ["spawnflags", "1"]]),
		_rec(4, "func_breakable_surf", "pane", [["model", "*7"]]),
		_rec(5, "func_breakable", "armoured", [["health", "50"], ["minhealthdmg", "10"]]),
		_rec(6, "prop_physics", "barrel", [["model", "models/props_c17/oildrum001.mdl"]]),
		_rec(7, "func_breakable", "bulletproof", [["health", "5"], ["material", "7"]]),
		_rec(8, "logic_relay", "r", [], [["OnTrigger", "plain", "Break", "", 1.0]]),
	])
	var seen: Array = []
	io.effect_fn = func(kind: String, e: DotMapEntity, on: bool) -> void: seen.append([kind, e.targetname, on])
	io.propdata_fn = func(model: String) -> Dictionary: return {"health": 40.0, "material": "metal"} if model.ends_with("oildrum001.mdl") else {}
	io.start()
	var crate := io.entity_of(0) as DotMapBreakable
	_check(not io.hurt(0, 10.0) and crate.health == 20.0, "10 damage leaves 20 of 30")
	_check(io.hurt(0, 25.0) and crate.broken, "the next hit breaks it")
	_check((io.entity_of(1) as DotMapCounter).value == 11.0, "OnHealthChanged (+10) then OnBreak (+1) ran their links: %s" % (io.entity_of(1) as DotMapCounter).value)
	_check(not crate.alive and seen == [["break", "crate", true]], "a broken entity is gone and the effect callable heard of it: %s" % [seen])
	_check(not io.hurt(2, 100.0), "a breakable with no health in the map takes no damage")
	io.send("r", "Trigger")
	io.advance(20)
	_check((io.entity_of(2) as DotMapBreakable).broken, "but Break still breaks it, here from a timed link")
	_check(not io.hurt(3, 100.0) and not (io.entity_of(3) as DotMapBreakable).broken, "spawnflag 1 breaks only on trigger")
	_check(io.hurt(4, 1.0), "a breakable_surf with no health breaks on one point")
	_check(not io.hurt(5, 9.0) and io.hurt(5, 50.0), "minhealthdmg ignores light hits")
	var barrel := io.entity_of(6) as DotMapBreakable
	_check(barrel.health == 40.0 and barrel.material == "metal", "a prop takes its health and material from the game's propdata")
	_check(not io.hurt(7, 50.0), "material 7 (unbreakable glass) takes no damage")
	io.send("barrel", "SetHealth", "5")
	io.send("barrel", "RemoveHealth", "5")
	_check(barrel.broken, "SetHealth and RemoveHealth drive it to zero")
	var client := _io([_rec(0, "func_breakable", "crate", [["health", "30"]])])
	client.authoritative = false
	_check(not client.hurt(0, 99.0), "a client's damage does nothing")
	# glass: the converter's DotMapGlass is driven through the entity
	var io2 := _io([_rec(0, "func_breakable_surf", "window", [["model", "*9"]])])
	var visual := _model_node(9)
	var pane := DotMapGlass.new()
	pane.model = 9
	pane.visual = visual
	pane.collision_layer = 1
	add_child(pane)
	io2.bind_breakables([{"entity": 0, "model": 9, "health": 3.0, "glass": "glass", "material": 0}])
	io2.bind_world(self)
	_check(pane.authoritative == false and visual.visible, "a bound pane stops deciding for itself and is drawn")
	io2.hurt(0, 2.0)
	_check(not pane.is_broken() and visual.visible, "damage below its health leaves the glass up")
	io2.hurt(0, 2.0)
	_check(pane.is_broken() and not visual.visible, "the break shatters the pane: it is hidden and its shards fly")
	pane.free()
	visual.free()
	_done()


func _test_door() -> void:
	_section("a door's motion is a function of the tick: open, wait, close, lock, speed")
	var io := _io([_rec(0, "func_door", "door", [], [["OnOpen", "log", "Add", "1"], ["OnFullyOpen", "log", "Add", "10"], ["OnFullyClosed", "log", "Add", "100"], ["OnClose", "log", "Add", "1000"]]),
			_rec(1, "math_counter", "log", [["max", "100000"]])])
	io.bind_movers([_door_rec(0)])
	io.start()
	var d := io.entity_of(0) as DotMapMoverNode
	_check(d.fraction_at(0, 20) == 0.0, "closed at the start")
	io.send("door", "Open")
	io.advance(20)
	_check(is_equal_approx(d.fraction_at(io.now, 20), 0.5), "halfway after 1 s of a 2 s travel")
	io.advance(20)
	_check(d.fraction_at(io.now, 20) == 1.0, "fully open at 2 s")
	_check(_ticks(io, "door", "motion", [0.0, 1.0, 0, 2.0]) == [0], "the motion record says where and when it started")
	var log := io.entity_of(1) as DotMapCounter
	_check(log.value == 11.0, "OnOpen then OnFullyOpen fired: %s" % log.value)
	io.advance(59)
	_check(d.fraction_at(io.now, 20) == 1.0, "it holds for the 3 s wait (tick 99)")
	io.advance(1)
	_check(log.value == 1011.0, "then closes by itself (OnClose at tick 100): %s" % log.value)
	io.advance(40)
	_check(d.fraction_at(io.now, 20) == 0.0 and log.value == 1111.0, "and reports OnFullyClosed at tick 140: %s" % log.value)
	io.send("door", "Lock")
	io.send("door", "Open")
	io.advance(60)
	_check(d.fraction_at(io.now, 20) == 0.0, "a locked door ignores Open")
	io.send("door", "Unlock")
	io.send("door", "SetPosition", "0.25")
	io.advance(10)
	_check(is_equal_approx(d.fraction_at(io.now, 20), 0.25), "SetPosition goes to a fraction and stops there")
	io.send("door", "SetSpeed", "39.37")
	var before := d.fraction_at(io.now, 20)
	_check(is_equal_approx(before, 0.25), "SetSpeed does not jump the door")
	io.send("door", "Open")
	io.advance(15)
	_check(is_equal_approx(d.fraction_at(io.now, 20), 0.25 + 0.75 * 15.0 / 30.0), "a faster speed (1 m/s over 2 m: 1.5 s from closed) takes 15 ticks for half of the remaining way")
	_check(DotMapMover.from_record({"kind": "slide", "distance": 4.0, "direction": [0, 1, 0]}).transform_at(0.5).origin == Vector3(0, 2, 0), "the record's own pose function is what the node is set from")
	# a hinge
	var io2 := _io([_rec(0, "func_door_rotating", "hinge", [["model", "*0"]])])
	io2.bind_movers([_door_rec(0, "rotate")])
	io2.send("hinge", "Toggle")
	var n := _model_node(0, Vector3(5, 0, 0))
	io2.bind_world(self)
	io2.advance(40)
	_check(n.transform.basis.is_equal_approx(Basis(Vector3.UP, deg_to_rad(90.0))) and n.position.is_equal_approx(Vector3(5, 0, 0)), "a hinge turns about its own origin")
	n.free()
	_done()


func _test_button_chain() -> void:
	_section("a button opens a door; use, lock and wait")
	var io := _io([
		_rec(0, "func_button", "btn", [["spawnflags", "1024"]], [["OnPressed", "door", "Open"], ["OnPressed", "btn", "Lock"], ["OnPressed", "btn", "Unlock", "", 5.0]]),
		_rec(1, "func_door", "door"),
	])
	io.bind_movers([_door_rec(1, "slide", {"wait": 2.0}), DotMapMover.from_record({"entity": 0, "model": 0, "kind": "button", "classname": "func_button",
			"distance": 0.0, "direction": [1, 0, 0], "wait": 1.0, "use": true, "targetname": "btn"})])
	io.start()
	var door := io.entity_of(1) as DotMapMoverNode
	_check(io.use(0).ok, "using a button presses it")
	io.advance(1)
	_check(door.fraction_at(io.now, 20) > 0.0, "and its OnPressed link starts the door")
	_check(io.use(0).ok, "a locked button still answers use")
	var btn := io.entity_of(0) as DotMapMoverNode
	_check(btn.locked, "the button locked itself with OnPressed")
	io.advance(130)
	_check(not btn.locked and door.fraction_at(io.now, 20) == 0.0, "5 s later it unlocks (the door waited 2 s and closed)")
	var io2 := _io([_rec(0, "func_door", "d")])
	io2.bind_movers([_door_rec(0, "slide", {"use": true, "wait": -1.0})])
	io2.use(0)
	io2.advance(40)
	_check(io2.entity_of(0).state()["motion"][1] == 1.0, "using a door opens it and wait -1 keeps it open")
	io2.use(0)
	io2.advance(40)
	_check(io2.entity_of(0).state()["motion"][1] == 0.0, "using it again closes it")
	_check(not io2.use(99).ok and not io2.hurt(0, 5.0), "use of nothing is refused, damage to a door does nothing")
	_done()


func _test_spinner() -> void:
	_section("func_rotating: start, stop, reverse and speed as functions of the tick")
	var io := _io([_rec(0, "func_rotating", "fan", [["model", "*0"]])])
	io.bind_movers([DotMapMover.from_record({"entity": 0, "model": 0, "kind": "spin", "classname": "func_rotating", "axis": [0, 1, 0], "degrees_per_second": 90.0})])
	var fan := io.entity_of(0) as DotMapMoverNode
	var n := _model_node(0)
	io.bind_world(self)
	_check(fan.angle_at(100, 20) == 0.0, "stopped until started")
	io.send("fan", "Start")
	io.advance(20)
	_check(is_equal_approx(fan.angle_at(io.now, 20), deg_to_rad(90.0)), "90 degrees a second")
	_check(n.basis.is_equal_approx(Basis(Vector3.UP, deg_to_rad(90.0))), "the node follows the tick")
	io.send("fan", "Stop")
	io.advance(40)
	_check(is_equal_approx(fan.angle_at(io.now, 20), deg_to_rad(90.0)), "Stop holds the angle")
	io.send("fan", "Reverse")
	io.send("fan", "Start")
	io.advance(20)
	_check(is_equal_approx(fan.angle_at(io.now, 20), 0.0), "Reverse then Start turns back")
	io.send("fan", "SetSpeed", "0.5")
	io.advance(20)
	_check(is_equal_approx(fan.angle_at(io.now, 20), deg_to_rad(-45.0)), "SetSpeed 0.5 is half the top speed")
	n.free()
	_done()


func _test_train() -> void:
	_section("a train follows its stored path_track corners and fires OnPass")
	var path := [{"name": "a", "at": [0, 0, 0]}, {"name": "b", "at": [4, 0, 0], "speed": 2.0}, {"name": "c", "at": [4, 0, 4]}]
	var io := _io([
		_rec(0, "func_tracktrain", "train", [["model", "*0"]]),
		_rec(1, "path_track", "a", [], []), _rec(2, "path_track", "b", [], [["OnPass", "log", "Add", "1"]]),
		_rec(3, "path_track", "c", [], [["OnPass", "log", "Add", "10"]]), _rec(4, "math_counter", "log", [["max", "1000"]]),
	])
	io.bind_movers([DotMapMover.from_record({"entity": 0, "model": 0, "kind": "path", "classname": "func_tracktrain", "speed": 4.0, "path": path})])
	var tr := io.entity_of(0) as DotMapMoverNode
	var n := _model_node(0, Vector3(0, 1, 0))
	io.bind_world(self)
	io.start()
	io.send("train", "StartForward")
	io.advance(10)
	_check(tr.path_point(tr.path_at(io.now, 20)).is_equal_approx(Vector3(2, 0, 0)), "4 m/s for half a second is 2 m along")
	io.advance(11)
	_check((io.entity_of(4) as DotMapCounter).value == 1.0, "passing the second corner fires its OnPass")
	_check(is_equal_approx(n.position.x, 4.0) and n.position.z > 0.0 and is_equal_approx(n.position.y, 1.0), "the node moves with the train, its own offset kept: %s" % n.position)
	io.advance(100)
	_check((io.entity_of(4) as DotMapCounter).value == 11.0, "the last corner's OnPass fired")
	_check(is_equal_approx(tr.path_at(io.now, 20), 8.0) and tr.state()["spin"][1] == 0.0, "it stops at the end of an open path")
	io.send("train", "StartBackward")
	io.advance(200)
	_check(tr.path_at(io.now, 20) == 0.0, "backward runs it home")
	io.send("train", "TeleportToPathTrack", "b")
	_check(is_equal_approx(tr.path_at(io.now, 20), 4.0), "TeleportToPathTrack jumps to a corner")
	var ring := path.duplicate()
	ring.append({"loop": "a"})
	var io2 := _io([_rec(0, "func_tracktrain", "t2")])
	io2.bind_movers([DotMapMover.from_record({"entity": 0, "model": 0, "kind": "path", "classname": "func_tracktrain", "speed": 4.0, "path": ring})])
	io2.send("t2", "StartForward")
	io2.advance(20 * 5)
	var t2 := io2.entity_of(0) as DotMapMoverNode
	_check(t2.path_at(io2.now, 20) < 13.7 and t2.path_at(io2.now, 20) >= 0.0 and io2.pending() > 0, "a looped path wraps and keeps scheduling its next corner: %s, %d pending" % [t2.path_at(io2.now, 20), io2.pending()])
	var tank := _io([_rec(0, "func_tanktrain", "tank")])
	_check(tank.entity_of(0) is DotMapMoverNode, "a tank train is a path mover like a track train")
	n.free()
	_done()


func _test_bind_world() -> void:
	_section("the entity classes are registered for DotMapIO to drive, and a game can replace one")
	var io := DotMapIO.new()
	io.load_records([_rec(0, "func_door", "d"), _rec(1, "func_breakable", "b"), _rec(2, "func_brush", "w"), _rec(3, "func_plat", "p")])
	_check(io.entity_of(0) is DotMapMoverNode and io.entity_of(3) is DotMapMoverNode, "doors and lifts are mover entities")
	_check(io.entity_of(1) is DotMapBreakable and io.entity_of(2) is DotMapToggleBrush, "breakables and brushes have classes")
	io.send("d", "Open")
	_check(io.unhandled.get("func_door|open", 0) == 1, "a mover with no record counts the input as unhandled instead of failing")
	_check(io.bind_movers([_door_rec(7)]) == 0 and io.missing_callables.has("bind_mover.func_door"), "a record for no entity is counted, not an error")
	io.register_class("func_door", DotMapEntity)
	io.load_records([_rec(0, "func_door", "d")])
	_check(not io.entity_of(0) is DotMapMoverNode, "register_class replaces a class")
	_done()


func _test_real_lifts() -> void:
	_section("a real map's lifts: the stored travel is what the node ends up at")
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(TUNNEL))
	if not doc is Dictionary:
		_check(false, "the fixture reads")
		_done()
		return
	var ents := DotMapEntities.from_manifest(doc)
	var recs: Array = []
	var movers: Array = []
	for m in ents.movers:
		if m.kind == DotMapMover.KIND_SLIDE and m.is_animatable():
			recs.append(_rec(m.entity, m.classname, m.targetname))
			movers.append(m)
	_check(movers.size() >= 3, "the tunnel has lifts: %d" % movers.size())
	var io := _io(recs)
	var holder: Array = []
	for m: DotMapMover in movers:
		var n := Node3D.new()
		n.set_meta(&"model", m.model)
		n.position = m.origin
		add_child(n)
		holder.append(n)
	io.bind_movers(movers)
	var first := movers[0] as DotMapMover
	holder[0].set_meta(&"model", first.model)
	var ent := io.entity_of(first.entity) as DotMapMoverNode
	ent.bind_node(holder[0])
	ent.accept(io, "Open", "", null, null)
	io.advance(int(ceil(first.travel_time * io.rate)) + 2)
	_check(ent.fraction_at(io.now, io.rate) == 1.0, "it reaches the end of its stored travel in the stored time (%.2f s)" % first.travel_time)
	_check((holder[0] as Node3D).position.is_equal_approx(first.origin + first.direction * first.distance), "and the node sits at origin + direction * distance")
	for n: Node in holder:
		n.free()
	_done()


func _test_replication() -> void:
	_section("server state reaches clients: brush, door, glass, and a joiner's snapshot")
	var recs := [
		_rec(0, "func_brush", "wall", [["model", "*1"]]),
		_rec(1, "func_door", "door", [["model", "*2"]]),
		_rec(2, "func_breakable_surf", "window", [["model", "*3"]]),
		_rec(3, "logic_relay", "r", [], [["OnTrigger", "wall", "Color", "255 0 0"], ["OnTrigger", "wall", "Disable", "", 0.5], ["OnTrigger", "door", "Open", "", 1.0], ["OnTrigger", "window", "Break", "", 2.0]]),
	]
	var host := _io(recs)
	host.bind_movers([_door_rec(1, "slide", {"wait": -1.0})])
	var sync := DotMapStateSync.new()
	var inbox: Array = []
	sync.attach_host(host, func(peer: Variant, msg: Dictionary) -> void: inbox.append([peer, msg]))
	sync.add_peer("a")
	_check(inbox.size() == 1 and inbox[0][1]["type"] == "io_snapshot", "a peer added gets a snapshot first")
	var client := _io(recs)
	client.authoritative = false
	client.bind_movers([_door_rec(1, "slide", {"wait": -1.0})])
	var cnodes := {1: _model_node(1), 2: _model_node(2), 3: _model_node(3)}
	var pane := DotMapGlass.new()
	pane.model = 3
	pane.visual = cnodes[3]
	pane.collision_layer = 1
	add_child(pane)
	client.bind_world(self)
	var seen_door: Array = []
	_check(sync.apply(client, inbox[0][1]).ok, "the client takes the snapshot")
	host.start()
	host.send("r", "Trigger")
	var steps := 0
	while host.now < 80:
		host.advance(1)
		for item: Array in inbox:
			if (item[1] as Dictionary)["type"] == "io_state":
				_check(sync.apply(client, item[1]).ok, "a state message applies") if steps < 3 else sync.apply(client, item[1])
				steps += 1
		inbox.clear()
		client.advance(1) if client.now < host.now else null
		if host.now in [20, 40, 60, 79]:
			seen_door.append([host.now, snappedf((host.entity_of(1) as DotMapMoverNode).fraction_at(host.now, 20), 0.001), snappedf((client.entity_of(1) as DotMapMoverNode).fraction_at(client.now, 20), 0.001)])
	_check(not (client.entity_of(0) as DotMapEntity).enabled and not (cnodes[1] as Node3D).visible, "the client's brush went away at the host's tick")
	_check((client.entity_of(0) as DotMapEntity).color == "255 0 0", "the colour arrived")
	var agree := true
	for row: Array in seen_door:
		agree = agree and row[1] == row[2]
	_check(agree and seen_door.size() == 4 and seen_door[1][1] > 0.0, "the door is at the same fraction on both ends at every sampled tick: %s" % [seen_door])
	_check(pane.is_broken() and not (cnodes[3] as Node3D).visible, "the glass broke on the client, shards and all")
	_check(client.send("door", "Open").ok == false and client.pending() == 0, "a client runs no logic")
	# a joiner after everything happened
	var late := _io(recs)
	late.authoritative = false
	late.bind_movers([_door_rec(1, "slide", {"wait": -1.0})])
	var late_sync := DotMapStateSync.new()
	_check(late_sync.apply(late, sync.snapshot_message()).ok, "a joiner applies the host's snapshot")
	var ignored_before := late_sync.ignored
	_check(not (late.entity_of(0) as DotMapEntity).enabled and (late.entity_of(2) as DotMapBreakable).broken, "it already has the brush off and the window broken")
	late.advance(5)
	_check((late.entity_of(1) as DotMapMoverNode).fraction_at(late.now, 20) == (host.entity_of(1) as DotMapMoverNode).fraction_at(late.now, 20), "and the door in the right place for its clock")
	_check(not late_sync.apply(late, {"type": "chat"}).ok and not late_sync.apply(late, {"type": "io_state", "tick": 1, "changes": 5}).ok, "foreign and malformed messages are refused")
	late_sync.apply(late, {"type": "io_state", "tick": late.now, "changes": [[99, "enabled", true], [0, "nonsense", 1], "x"]})
	_check(late_sync.refused == 2 and late_sync.ignored == ignored_before + 1, "unknown entities and shapes are refused, an unknown key is ignored: %d, %d" % [late_sync.refused, late_sync.ignored])
	_check(not late_sync.apply(late, {"type": "io_state", "tick": late.now - 1, "changes": []}).ok, "a tick lower than the client's clock is refused")
	var many: Array = []
	for i in DotMapStateSync.MAX_CHANGES + 1:
		many.append([0, "enabled", true])
	_check(not late_sync.apply(late, {"type": "io_state", "tick": late.now, "changes": many}).ok, "an oversize message is refused whole")
	_check(not late_sync.apply(late, {"type": "io_state", "tick": INF, "changes": []}).ok, "an infinite tick is refused")
	_check(not DotMapStateSync.new().apply(host, {"type": "io_state", "tick": host.now + 1, "changes": []}).ok, "an authoritative runtime takes no state from a message")
	pane.free()
	for n: Node in cnodes.values():
		n.free()
	_done()


func _test_determinism() -> void:
	_section("the same inputs give the same run however the ticks are chunked")
	var recs := [
		_rec(0, "func_door", "door"),
		_rec(1, "logic_timer", "t", [["RefireTime", "7"]], [["OnTimer", "door", "Toggle"]]),
		_rec(2, "logic_relay", "r", [], [["OnTrigger", "door", "Open"]]),
	]
	var runs: Array = []
	for chunks: Array in [[1], [7], [13]]:
		var io := _io(recs, 30)
		io.bind_movers([_door_rec(0, "slide", {"wait": -1.0, "travel_time": 1.5})])
		io.start()
		io.send("r", "Trigger")
		var left := 900
		while left > 0:
			var step := mini(chunks[0], left)
			io.advance(step)
			left -= step
		runs.append(JSON.stringify(io.history))
	_check(runs[0] == runs[1] and runs[1] == runs[2], "history is identical for 1, 7 and 13 ticks a call")
	_check(runs[0].count("motion") >= 4, "and it is a real run: the door moved %d times" % runs[0].count("motion"))
	_done()


func _test_door_standin() -> void:
	_section("prop_door_rotating has no brush: a drawn panel and body swing about the hinge")
	var io := _io([_rec(0, "prop_door_rotating", "pd", [["angles", "0 90 0"]], [["OnFullyOpen", "log", "Add", "1"]]),
			_rec(1, "math_counter", "log", [["max", "10"]])])
	var m := _door_rec(0, "rotate", {"model": null, "classname": "prop_door_rotating", "targetname": "pd",
			"origin": [3, 0, 4], "axis": [0, 1, 0], "degrees": 90.0, "travel_time": 1.0, "use": true})
	io.bind_movers([m])
	var door := DotMapDoorStandIn.build(m, 90.0)
	add_child(door)
	var e := io.entity_of(0) as DotMapMoverNode
	e.set_hit_box(Transform3D(), Vector3.ONE)
	e.bind_node(door)
	_check(door.position == Vector3(3, 0, 4) and is_equal_approx(door.rotation.y, deg_to_rad(90.0)), "the node sits at the hinge, yawed by the entity's angles")
	_check(door.get_node_or_null("Panel") is MeshInstance3D and door.get_node_or_null("col_solid") is AnimatableBody3D, "with a drawn panel and a body of its own")
	_check((door.get_node("Panel") as Node3D).position.z < 0.0, "the panel lies along local +Y of the source entity")
	io.start()
	io.send("pd", "Open")
	io.advance(20)
	_check(door.transform.basis.is_equal_approx(Basis(Vector3.UP, deg_to_rad(180.0))) and door.position.is_equal_approx(Vector3(3, 0, 4)), "opening swings it a further 90 degrees about the hinge")
	_check((io.entity_of(1) as DotMapCounter).value == 1.0, "and OnFullyOpen fires at the end")
	io.send("pd", "Close")
	io.advance(20)
	_check(door.transform.basis.is_equal_approx(Basis(Vector3.UP, deg_to_rad(90.0))), "closing swings it back")
	# opendir 0: the door swings away from whoever opens it, decided once on opening and replicated.
	var away := _io([_rec(0, "prop_door_rotating", "pd", [["angles", "0 0 0"]])])
	var am := _door_rec(0, "rotate", {"model": null, "classname": "prop_door_rotating", "targetname": "pd",
			"origin": [0, 0, 0], "axis": [0, 1, 0], "degrees": 90.0, "travel_time": 1.0, "open_dir": 0, "yaw": 0.0, "use": true})
	away.bind_movers([am])
	var ae := away.entity_of(0) as DotMapMoverNode
	ae.accept(away, "Open", "", Vector3(2, 0, 0), null)
	away.advance(20)
	_check(ae.pose_delta(away.now, 20).basis.is_equal_approx(Basis(Vector3.UP, deg_to_rad(90.0))), "an opener on the front (+X) side: the panel swings the positive way, away from it")
	ae.accept(away, "Close", "", null, null)
	away.advance(20)
	ae.accept(away, "Open", "", Vector3(-2, 0, 0), null)
	away.advance(20)
	_check(ae.pose_delta(away.now, 20).basis.is_equal_approx(Basis(Vector3.UP, deg_to_rad(-90.0))), "an opener behind it: the other way")
	var joiner := _io([_rec(0, "prop_door_rotating", "pd", [])])
	joiner.bind_movers([DotMapMover.from_record(am.record)])
	joiner.entity_of(0).apply_state(joiner, "side", ae.state()["side"], 0)
	joiner.entity_of(0).apply_state(joiner, "motion", ae.state()["motion"], 0)
	_check(joiner.entity_of(0).state()["side"] == -1.0, "the chosen side is state a joiner receives")
	var forged := _io([_rec(0, "prop_door_rotating", "pd", [])])
	forged.bind_movers([DotMapMover.from_record(am.record)])
	var fe := forged.entity_of(0) as DotMapMoverNode
	_check(fe.apply_state(forged, "side", 1.0e11, 0) and fe._side == 1.0, "a forged side of 1e11 is clamped to +1")
	fe.apply_state(forged, "side", -5.0, 0)
	_check(fe._side == -1.0, "a side of -5 is clamped to -1")
	fe.apply_state(forged, "side", 0.0, 0)
	_check(fe._side == -1.0, "a side of 0 keeps the current side")
	forged.authoritative = false
	var sync := DotMapStateSync.new()
	var before := forged.now
	sync.apply(forged, {"type": DotMapStateSync.TYPE_STATE, "tick": before, "changes": [[0, "side", 1.0e11], [0, "side", INF]]})
	_check(sync.refused == 2 and fe._side == -1.0, "the state sync refuses a side beyond 1 or not finite")
	var unk := _io([_rec(0, "prop_door_rotating", "pd", [])])
	var um := DotMapMover.from_record(am.record.merged({"spawn_side": -1.0, "degrees": 90.0}))
	unk.bind_movers([um])
	var ue := unk.entity_of(0) as DotMapMoverNode
	_check(ue._side == -1.0, "a spawn_side of -1 starts on the back")
	ue.accept(unk, "Open", "", null, null)
	ue.accept(unk, "Close", "", null, null)
	unk.advance(40)
	ue.accept(unk, "Open", "", {"name": "timer"}, null)
	_check(ue._side == -1.0, "an opener with no position keeps spawn_side")
	var uj := _io([_rec(0, "prop_door_rotating", "pd", [])])
	uj.bind_movers([DotMapMover.from_record(um.record if "record" in um else am.record)])
	uj.entity_of(0).apply_state(uj, "side", ue.state()["side"], 0)
	_check(uj.entity_of(0).state()["side"] == ue.state()["side"], "a joiner stays consistent with the kept side")
	var fixed := DotMapMover.from_record({"kind": "rotate", "degrees": -90.0, "open_dir": 2, "spawn_side": 1.0})
	_check(fixed.side_away_from(Vector3(5, 0, 0)) == 1.0, "opendir 1 and 2 keep the record's own sign whoever opens")
	var back := DotMapMoverNode.new()
	back.set_mover(fixed)
	_check(back._side == -1.0 and fixed.rest_fraction() == 0.0, "spawnpos 1 on a back-only door stands at the positive angle")
	var nodoor := DotMapDoorStandIn.build(_door_rec(0, "rotate", {"solid": false}), 0.0)
	_check(nodoor.get_node_or_null("col_solid") == null, "a passable door gets no body")
	nodoor.free()
	door.free()
	_done()


func _test_physbox() -> void:
	_section("func_physbox: a rigid body that EnableMotion frees, a damage wakes, and a client never simulates")
	var io := _io([_rec(0, "func_physbox", "crate", [["damagetoenablemotion", "50"], ["model", "*3"]], [["OnMotionEnabled", "log", "Add", "1"], ["OnBreak", "log", "Add", "10"]]),
			_rec(1, "math_counter", "log", [["max", "100"]]),
			_rec(2, "func_physbox", "free", [["model", "*4"]])])
	var crate := io.entity_of(0) as DotMapPhysbox
	var log := io.entity_of(1) as DotMapCounter
	var rb := RigidBody3D.new()
	add_child(rb)
	crate.bind_body(rb, true)
	_check(not crate.motion and rb.freeze, "damagetoenablemotion starts it frozen")
	crate.hurt(io, 10.0)
	_check(rb.freeze, "a hit under the threshold leaves it")
	crate.hurt(io, 60.0)
	io.advance(1)
	_check(crate.motion and not rb.freeze and log.value == 1.0, "a harder one frees it and fires OnMotionEnabled")
	io.send("crate", "DisableMotion")
	_check(rb.freeze, "DisableMotion freezes it")
	io.send("crate", "EnableMotion")
	_check(not rb.freeze, "EnableMotion frees it")
	var rb2 := RigidBody3D.new()
	add_child(rb2)
	(io.entity_of(2) as DotMapPhysbox).bind_body(rb2, true)
	_check(not rb2.freeze, "one with no threshold simulates from the start")
	var rb3 := RigidBody3D.new()
	add_child(rb3)
	(io.entity_of(2) as DotMapPhysbox).bind_body(rb3, false)
	_check(rb3.freeze, "a client keeps it frozen: the authority simulates")
	io.send("crate", "Break")
	io.advance(1)
	_check(log.value == 12.0 and rb.freeze, "breaking it fires OnBreak (and the earlier EnableMotion fired OnMotionEnabled again) and stops the body")
	_check(io.snapshot()["entities"][0].has("motion"), "its motion state is in a joiner's snapshot")
	for n in [rb, rb2, rb3]:
		n.free()
	_done()


func _test_spin_up() -> void:
	_section("func_rotating with fanfriction ramps to speed and down again, the same on a client")
	var recs := [_rec(0, "func_rotating", "fan", [["model", "*0"]])]
	var rec := {"entity": 0, "model": 0, "kind": "spin", "classname": "func_rotating", "axis": [0, 1, 0],
			"degrees_per_second": 90.0, "fan_friction": 20.0}
	var io := _io(recs)
	io.bind_movers([DotMapMover.from_record(rec)])
	var fan := io.entity_of(0) as DotMapMoverNode
	io.send("fan", "Start")
	io.advance(20)
	_check(is_equal_approx(fan.angle_at(io.now, 20), deg_to_rad(45.0)), "one second to full speed: half the angle of a flat start after that second")
	_check(is_equal_approx(fan.spin_velocity_at(io.now, 20), deg_to_rad(90.0)), "and at full speed after it")
	io.advance(20)
	_check(is_equal_approx(fan.angle_at(io.now, 20), deg_to_rad(135.0)), "then 90 degrees a second")
	io.send("fan", "Stop")
	io.advance(10)
	_check(is_equal_approx(fan.spin_velocity_at(io.now, 20), deg_to_rad(45.0)), "Stop slows it, not at once")
	io.advance(40)
	var held := fan.angle_at(io.now, 20)
	io.advance(20)
	_check(is_equal_approx(held, deg_to_rad(135.0 + 45.0)) and fan.angle_at(io.now, 20) == held, "it coasts to a stop 45 degrees on and stays")
	var client := _io(recs)
	client.authoritative = false
	client.bind_movers([DotMapMover.from_record(rec)])
	var sync := DotMapStateSync.new()
	_check(sync.apply(client, {"type": "io_state", "tick": io.now, "changes": [[0, "spin", io.entity_of(0).state()["spin"]]]}).ok
			and is_equal_approx((client.entity_of(0) as DotMapMoverNode).angle_at(io.now, 20), held), "a client given the state agrees on the angle")
	_done()


func _pose_count(inbox: Array) -> int:
	var n := 0
	for m: Dictionary in inbox:
		for c: Array in m.get("changes", []):
			n += 1 if c[1] == "pose" else 0
	return n


func _test_physbox_pose() -> void:
	_section("a physbox's pose is reported while it moves and a client follows it")
	var recs := [_rec(0, "func_physbox", "crate", [["model", "*3"]])]
	var host := _io(recs)
	var rb := RigidBody3D.new()
	add_child(rb)
	(host.entity_of(0) as DotMapPhysbox).bind_body(rb, true)
	var sync := DotMapStateSync.new()
	var inbox: Array = []
	sync.attach_host(host, func(_p: Variant, msg: Dictionary) -> void: inbox.append(msg))
	sync.add_peer("a")
	host.start()
	host.advance(5)
	_check(_pose_count(inbox) == 0, "a body that is not moving reports no pose")
	rb.transform = Transform3D(Basis(Vector3.UP, 0.5), Vector3(1, 2, 3))
	host.advance(5)
	_check(_pose_count(inbox) == 1, "a moved one reports once")
	host.advance(10)
	_check(_pose_count(inbox) == 1 and sync.snapshot_message()["entities"][0].has("pose"), "and not again while still, and a joiner's snapshot has the pose")
	var client := _io(recs)
	client.authoritative = false
	var crb := RigidBody3D.new()
	add_child(crb)
	(client.entity_of(0) as DotMapPhysbox).bind_body(crb, false)
	var csync := DotMapStateSync.new()
	for m: Dictionary in inbox:
		csync.apply(client, m)
	for i in 20:
		(client.entity_of(0) as DotMapPhysbox).tick_view(client)
	_check(crb.transform.origin.distance_to(Vector3(1, 2, 3)) < 0.01, "the client's body is where the host's is")
	var pose: Array = host.snapshot()["entities"][0]["pose"]
	csync.apply(client, {"type": "io_state", "tick": 30, "changes": [[0, "pose", [4.0, 2.0, 3.0, pose[3], pose[4], pose[5], pose[6]]]]})
	for i in 12:
		(client.entity_of(0) as DotMapPhysbox).tick_view(client)
	_check(crb.transform.origin.distance_to(Vector3(4, 2, 3)) < 0.05, "a later pose is eased to")
	csync.apply(client, {"type": "io_state", "tick": 31, "changes": [[0, "pose", [1.0]]]})
	_check(csync.ignored == 1 and crb.transform.origin.distance_to(Vector3(4, 2, 3)) < 0.05, "a malformed pose is ignored")
	rb.free()
	crb.free()
	_done()


func _test_state_transport() -> void:
	_section("DotMapStateTransport batches a tick's messages per peer and a client unpacks them")
	var recs := [_rec(0, "func_brush", "wall", [["model", "*1"]]), _rec(1, "func_brush", "wall2", [["model", "*2"]])]
	var host := _io(recs)
	var t := DotMapStateTransport.new()
	var wire: Array = []
	t.raw_send = func(peer: Variant, payload: Dictionary) -> void: wire.append([peer, payload])
	var sync := DotMapStateSync.new()
	sync.attach_host(host, t.send)
	t.flush_on(host)
	sync.add_peer("a")
	sync.add_peer("b")
	t.flush()
	_check(wire.size() == 2 and wire[0][1]["type"] == "io_snapshot", "each joiner's snapshot is sent on flush")
	wire.clear()
	host.start()
	host.send("wall", "Disable")
	host.advance(1)
	host.send("wall2", "Disable")
	host.advance(1)
	_check(wire.size() == 4 and wire[0][1]["type"] == "io_state", "each tick's changes leave as their own payload per peer, never a batch of one")
	wire.clear()
	t.send("a", {"type": "io_state", "tick": 1, "changes": []})
	t.send("a", {"type": "io_state", "tick": 2, "changes": []})
	t.flush()
	_check(wire.size() == 1 and wire[0][1]["type"] == "io_batch" and (wire[0][1]["messages"] as Array).size() == 2, "two messages to one peer travel as one batch")
	wire.clear()
	t.max_bytes = 40
	t.send("a", {"type": "io_state", "tick": 1, "changes": []})
	t.send("a", {"type": "io_state", "tick": 2, "changes": []})
	t.flush()
	_check(wire.size() == 2, "a batch splits at max_bytes")
	t.max_bytes = 1100
	var client := _io(recs)
	client.authoritative = false
	var csync := DotMapStateSync.new()
	var batch := {"type": "io_batch", "messages": [sync.snapshot_message(), {"type": "io_state", "tick": 9, "changes": [[0, "enabled", true]]}]}
	_check(DotMapStateTransport.is_state_payload(batch) and not DotMapStateTransport.is_state_payload({"type": "chat"}), "state payloads are told from the game's others")
	var r := t.receive(client, csync, batch)
	_check(r.ok and (client.entity_of(0) as DotMapEntity).enabled and not (client.entity_of(1) as DotMapEntity).enabled, "a client applies a whole batch in order")
	_check(not t.receive(client, csync, {"type": "io_batch", "messages": [5]}).ok, "a malformed batch is refused")
	_done()
