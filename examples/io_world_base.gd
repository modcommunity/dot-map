extends Node

## The harness of [code]io_world_demo[/code] (counters, check, record builders) and its door stand-in sections; split out only to keep each file small.

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()
var _entered := 0
var _completed := 0


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
	_test_door_sides()
	_test_door_hinge()
	door.free()
	_done()


func _test_door_hinge() -> void:
	# A door hung off an authored hinge (panel_yaw): the node sits on the hinge, the panel runs from it along that yaw
	# whatever the entity's angles, and it swings away from the opener about that hinge.
	var hrec := {"model": null, "classname": "prop_door_rotating", "targetname": "hd", "origin": [10, 0, 20], "axis": [0, 1, 0],
			"degrees": 90.0, "travel_time": 1.0, "open_dir": 0, "yaw": 0.0, "panel_yaw": 0.0, "panel_width": 1.2, "panel_offset": 0.6, "use": true}
	var hm := _door_rec(0, "rotate", hrec)
	var hdoor := DotMapDoorStandIn.build(hm, 270.0)
	add_child(hdoor)
	var hpanel := hdoor.get_node("Panel") as MeshInstance3D
	_check(hdoor.position == Vector3(10, 0, 20) and is_equal_approx(hdoor.rotation.y, 0.0), "a door with a panel_yaw ignores the entity's angles (270) and sits on the hinge")
	_check(is_equal_approx((hpanel.mesh as BoxMesh).size.z, 1.2) and is_equal_approx(hpanel.position.z, -0.6), "its panel is as wide as the hinge-to-origin line says and starts at the hinge")
	# A game's own model (origin mid-panel, built at the hinge with the entity's yaw) is hung under a pivot on the
	# hinge, half a width along the panel, so it swings about the hinge and not about its own middle.
	var wld := DotMapWorld.new()
	var model := Node3D.new()
	model.position = hm.origin
	var pivot := wld._hung_model(model, hm, 270.0)
	add_child(pivot)
	_check(pivot.position == Vector3(10, 0, 20) and model.get_parent() == pivot, "a custom door model hangs under a pivot at the hinge")
	_check(model.position.is_equal_approx(Vector3(0, 0, -0.6)) and is_equal_approx(model.rotation.y, deg_to_rad(270.0)), "armed: the model sits half a width along the panel with the entity's yaw, not on the hinge")
	_check(pivot.to_global(model.position).is_equal_approx(Vector3(10, 0, 19.4)), "its origin is mid-panel in the map")
	var own := Node3D.new()
	_check(wld._hung_model(own, _door_rec(0, "rotate", {"model": null, "classname": "prop_door_rotating", "targetname": "x", "origin": [0, 0, 0], "axis": [0, 1, 0], "degrees": 90.0}), 0.0) == own, "a door whose origin is the hinge keeps the game's node as built")
	own.free()
	wld.free()
	var bare_rec := hrec.duplicate()
	bare_rec.erase("panel_yaw")
	var plain := DotMapDoorStandIn.build(_door_rec(0, "rotate", bare_rec), 270.0)
	_check(is_equal_approx(plain.rotation.y, deg_to_rad(270.0)) and is_equal_approx((plain.get_node("Panel").mesh as BoxMesh).size.z, DotMapDoorStandIn.SIZE.x), "armed: without panel_yaw the same record takes the angles and the standard width")
	plain.free()
	var hio := _io([_rec(0, "prop_door_rotating", "hd", [["angles", "0 270 0"]])])
	hio.bind_movers([hm])
	var he := hio.entity_of(0) as DotMapMoverNode
	he.set_hit_box(Transform3D(), Vector3.ONE)
	he.bind_node(hdoor)
	hio.start()
	for opener: Array in [[Vector3(11, 0, 20), -1.0], [Vector3(9, 0, 20), 1.0]]:
		he.accept(hio, "Close", "", null, null)
		hio.advance(80)
		he.accept(hio, "Open", "", opener[0], null)
		hio.advance(int(hio.rate * hm.travel_time * 0.5))
		var tip := hdoor.global_transform * Vector3(0, 0, -1.2)
		_check(hdoor.position.is_equal_approx(Vector3(10, 0, 20)) and (tip.x - 10.0) * opener[1] > 0.5,
				"half open for an opener on %s, the tip at %s: swung about the hinge, away from the opener" % [opener[0], tip])
	_check(not is_equal_approx(DotMapMover.from_record({"kind": "rotate", "yaw": 180.0, "open_dir": 0}).side_away_from(Vector3(1, 0, 0)), DotMapMover.from_record({"kind": "rotate", "yaw": 0.0, "open_dir": 0}).side_away_from(Vector3(1, 0, 0))),
			"armed: the yaw decides which side is the front, so a wrong yaw would swing the door the wrong way")
	hdoor.free()
	var nodoor := DotMapDoorStandIn.build(_door_rec(0, "rotate", {"solid": false}), 0.0)
	_check(nodoor.get_node_or_null("col_solid") == null, "a passable door gets no body")
	nodoor.free()


func _test_door_sides() -> void:
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
