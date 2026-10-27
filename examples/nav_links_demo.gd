extends Node

## [DotMapNavLinks] on a synthetic entity set: a button through a relay to a door, a shot button to a disabled
## teleport, a walk-in pad to a door, and a closer that must not count.
##
## [codeblock]
## godot --headless --path . res://examples/nav_links_demo.tscn
## [/codeblock]

const CHECKS := 24
const SECTIONS := 3

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()
var _entered := 0
var _completed := 0


class FakeWorld extends RefCounted:
	var io: DotMapIO
	var volumes: DotMapVolumes


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("dot-map nav links")
	var links := _build()
	_test_doors(links)
	_test_teleports(links)
	_test_chain_and_empty()
	print("")
	print("%d passed, %d failed" % [_passed, _failed])
	for line in _failures:
		print("  FAIL  %s" % line)
	print("%d of %d sections ran to their last line" % [_completed, _entered])
	if _entered != SECTIONS or _completed != _entered or _passed + _failed != CHECKS:
		print("ERROR: %d sections, %d checks ran; %d and %d expected." % [_entered, _passed + _failed, SECTIONS, CHECKS])
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


func _rec(index: int, cls: String, tname: String, outs: Array = [], pairs: Array = []) -> Dictionary:
	var outputs: Array = []
	for o: Array in outs:
		outputs.append({"output": o[0], "target": o[1], "input": o[2], "param": "", "delay": 0.0, "times": -1})
	return {"index": index, "classname": cls, "targetname": tname, "parentname": "", "pairs": pairs, "outputs": outputs}


func _mover(entity: int, kind: String, cls: String, extra: Dictionary = {}) -> DotMapMover:
	var d := {"entity": entity, "model": entity, "kind": kind, "classname": cls, "direction": [0, 1, 0], "distance": 2.0,
			"travel_time": 1.0, "origin": [0, 0, 0], "axis": [0, 1, 0], "degrees": 90.0}
	d.merge(extra, true)
	return DotMapMover.from_record(d)


func _vol(entity: int, kind: String, cls: String, lo: Vector3, hi: Vector3, extra: Dictionary = {}) -> Dictionary:
	var planes: Array = [[1, 0, 0, hi.x], [-1, 0, 0, -lo.x], [0, 1, 0, hi.y], [0, -1, 0, -lo.y], [0, 0, 1, hi.z], [0, 0, -1, -lo.z]]
	var r := {"entity": entity, "model": 1, "classname": cls, "kind": kind, "targetname": "", "spawnflags": 1,
			"disabled": false, "outputs": [], "brushes": [planes]}
	r.merge(extra, true)
	return r


func _build() -> FakeWorld:
	var io := DotMapIO.new()
	var records: Array = [
		_rec(0, "func_button", "btn", [["OnPressed", "rel", "Trigger"]]),
		_rec(1, "logic_relay", "rel", [["OnTrigger", "door", "Open"]]),
		_rec(2, "func_door", "door"),
		_rec(3, "func_button", "shot", [["OnDamaged", "tp", "Enable"]]),
		_rec(4, "trigger_teleport", "tp", [], [["startdisabled", "1"]]),
		_rec(5, "trigger_multiple", "pad", [["OnStartTouch", "door2", "Open"]]),
		_rec(6, "func_door", "door2"),
		_rec(7, "func_button", "closer", [["OnPressed", "door", "Close"], ["OnPressed", "door3", "Lock"]]),
		_rec(8, "func_door", "door3"),
		_rec(9, "func_door", "open_door"),
	]
	_check(io.load_records(records).ok, "records load")
	io.bind_movers([_mover(0, "button", "func_button", {"use": true}), _mover(2, "slide", "func_door"),
			_mover(3, "button", "func_button", {"use": false}), _mover(6, "slide", "func_door", {"touch": true}),
			_mover(7, "button", "func_button", {"use": true}), _mover(8, "slide", "func_door"),
			_mover(9, "slide", "func_door", {"start_open": true})])
	io.start()
	for i in [0, 2, 3, 6, 7, 8, 9]:
		var e := io.entity_of(i) as DotMapMoverNode
		e.hit_half = Vector3(1, 1, 0.2)
		e.hit_frame = Transform3D(Basis.IDENTITY, Vector3(i * 10.0, 1, 0))
	io.destinations = {"dest": {"at": [5.0, 6.0, 7.0]}}
	var vols := [_vol(5, "multiple", "trigger_multiple", Vector3(50, 0, 0), Vector3(52, 2, 2), {"targetname": "pad"}),
			_vol(4, "teleport", "trigger_teleport", Vector3(40, 0, 0), Vector3(42, 2, 2), {"targetname": "tp", "target": "dest", "disabled": true})]
	var w := FakeWorld.new()
	w.io = io
	w.volumes = DotMapVolumes.build(DotMapEntities.from_manifest({"volumes": vols}), io)
	return w


func _find(list: Array, entity: int) -> Dictionary:
	for d: Dictionary in list:
		if int(d["entity"]) == entity:
			return d
	return {}


func _test_doors(world: FakeWorld) -> void:
	_section("doors: who opens each, and what does not count")
	var out := DotMapNavLinks.read(world)
	var doors: Array = out["doors"]
	_check(int(out["format"]) == DotMapNavLinks.FORMAT, "the format is named")
	var door := _find(doors, 2)
	_check(not door.is_empty(), "a shut slide door is listed")
	var by: Array = door.get("opened_by", [])
	_check(by.size() == 1, "the closer's Close does not make it an opener (one opener)")
	_check(by.size() == 1 and int(by[0]["index"]) == 0 and by[0]["kind"] == "use", "the button is a use opener")
	_check(by.size() == 1 and int(by[0]["hops"]) == 2, "through a relay it is two hops")
	_check(door.get("opens") == "output", "a plain door opens by output")
	_check((door["box"] as AABB).has_point(Vector3(20, 1, 0)), "its box is the rest pose")
	var late := _find(doors, 6)
	_check(late.get("opens") == "touch", "a touch door says so")
	var late_by: Array = late.get("opened_by", [])
	_check(late_by.size() == 1 and late_by[0]["kind"] == "walk" and int(late_by[0]["index"]) == 5, "a walk-in pad opens it")
	_check(_find(doors, 8).get("opened_by", [1]).is_empty(), "a door only a Lock reaches has no opener")
	_check(_find(doors, 9).is_empty(), "a door that starts open is not listed")
	_check(_find(doors, 0).is_empty(), "a button is not a door")
	_check(doors.size() == 3, "three doors")
	_done()


func _test_teleports(world: FakeWorld) -> void:
	_section("teleports: a disabled one lists the shot that enables it")
	var out := DotMapNavLinks.read(world)
	var tps: Array = out["teleports"]
	_check(tps.size() == 1, "one teleport")
	var tp: Dictionary = tps[0] if not tps.is_empty() else {}
	_check(tp.get("to") == Vector3(5, 6, 7), "its destination is resolved")
	_check(tp.get("enabled") == false, "it is disabled now")
	var by: Array = tp.get("opened_by", [])
	_check(by.size() == 1 and by[0]["kind"] == "shoot" and int(by[0]["index"]) == 3, "the OnDamaged button is a shoot opener")
	_check((tp["box"] as AABB).has_point(Vector3(41, 1, 1)), "its box is the volume")
	var openers: Dictionary = out["openers"]
	_check(openers.has(0) and openers.has(3) and openers.has(5), "openers by entity index")
	_done()


func _test_chain_and_empty() -> void:
	_section("chain and a null world")
	var w := _build()
	var path := DotMapNavLinks.chain(w.io, 0, 2)
	_check(Array(path) == [0, 1, 2], "chain prints button, relay, door")
	_check(DotMapNavLinks.chain(w.io, 7, 2).is_empty(), "a Close never reaches")
	var none := DotMapNavLinks.read(null)
	_check((none["doors"] as Array).is_empty() and (none["teleports"] as Array).is_empty(), "no world, no links")
	_done()


func _done() -> void:
	_completed += 1
