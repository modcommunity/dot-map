extends "../suite_base.gd"

## The manifest-volume helpers and the Office and jail-glass sections of the volumes suite.

const OFFICE := "res://examples/io/office_io.doc.json"


## A manifest volume record for a box from [param lo] to [param hi] (metres).
func _vol(entity: int, kind: String, cls: String, lo: Vector3, hi: Vector3, extra: Dictionary = {}) -> Dictionary:
	var planes: Array = [[1, 0, 0, hi.x], [-1, 0, 0, -lo.x], [0, 1, 0, hi.y], [0, -1, 0, -lo.y], [0, 0, 1, hi.z], [0, 0, -1, -lo.z]]
	var r := {"entity": entity if entity >= 0 else null, "model": 1, "classname": cls, "kind": kind,
			"targetname": "", "spawnflags": 1, "disabled": false, "outputs": [], "brushes": [planes]}
	r.merge(extra, true)
	return r


func _body(id: int, pos: Vector3, kind: String = "player", name: String = "") -> Dictionary:
	return {"id": id, "body": "b%d" % id, "position": pos, "kind": kind, "name": name, "height": 1.8}


## Runs [param ticks] rounds of advance then step; [param bodies] is a Callable(tick) -> Array.
func _run_ticks(io: DotMapIO, vols: DotMapVolumes, ticks: int, bodies: Callable) -> void:
	for i in ticks:
		io.advance(1)
		vols.step(bodies.call(io.now))


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


func _test_jail_glass_cell() -> void:
	_section("jail glass: the cell is found by shape, seen solid from inside only")
	var dests := {
		"cell": {"at": [0, -40, 0]}, "cell_b": {"at": [2, -40, 1]}, "far_low": {"at": [200, -40, 0]},
		"top": {"at": [0, 20, 100]},
	}
	var vols: Array = []
	for i in 3:
		vols.append({"kind": "teleport", "target": "cell"})
	vols.append({"kind": "teleport", "target": "cell_b"})
	vols.append({"kind": "teleport", "target": "top"})
	vols.append({"kind": "teleport", "target": "top"})
	vols.append({"kind": "teleport", "target": "top"})
	var cell := DotMapOneWayGlass.cell_of({"destinations": dests, "volumes": vols})
	_check(not cell.is_empty(), "the low destination three pits aim at is the jail cell")
	var centre: Vector3 = cell["centre"]
	_check(centre.distance_to(Vector3(1, -39, 0.5)) < 0.01, "its centre averages the destinations within 5 m, a metre up: %s" % [centre])
	_check(DotMapOneWayGlass.sees_solid(centre + Vector3(2, 0, 0), centre, 6.0), "a camera inside the cell sees the glass solid")
	_check(not DotMapOneWayGlass.sees_solid(centre + Vector3(20, 0, 0), centre, 6.0), "a camera outside sees through it")
	var ramp := DotMapOneWayGlass.cell_of({"destinations": {"a": {"at": [0, 0, 0]}, "t": {"at": [0, 5, 0]}}, "volumes": vols.slice(0, 3).map(func(v): return {"kind": "teleport", "target": "a"}) + [{"kind": "teleport", "target": "t"}]})
	_check(ramp.is_empty(), "a destination less than 10 m under the top is a ramp, not a cell")
	_check(DotMapOneWayGlass.cell_of({}).is_empty(), "a manifest without teleports has no cell")
	var m := DotMapOneWayGlass.material(&"glass", [0.5, 0.6, 0.7, 0.4], centre, 6.0)
	_check(m != null and m.get_shader_parameter("cell_centre") == centre, "the glass material carries the cell centre")
	_check(m.get_shader_parameter("cell_radius") == 6.0, "and the radius")
	_done()


func _test_jail_glass_rays() -> void:
	_section("jail glass: rays from inside are stopped, from outside pass, per cvar")
	var layer := 1 << 9
	var body := StaticBody3D.new()
	body.collision_layer = layer
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.2, 4, 8)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(4, 0, 0)
	add_child(body)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := body.get_world_3d().direct_space_state
	var sight := DotMapGlassSight.new(Vector3.ZERO, 3.0, layer)
	var inside := Vector3(0, 0, 0)
	var outside := Vector3(10, 0, 0)
	_check(sight.blocks(space, inside, outside), "a ray from inside the cell is stopped by the glass")
	_check(not sight.blocks(space, outside, inside), "the same line from outside passes")
	_check(not sight.blocks(space, inside, Vector3(2, 0, 0)), "inside, a ray that stops short of the glass is clear")
	_check(not sight.blocks(space, Vector3(20, 0, 0), Vector3(30, 0, 0)), "outside to outside is clear")
	var los := sight.sight_fn(func() -> PhysicsDirectSpaceState3D: return space, func(_a: Vector3, _b: Vector3) -> bool: return true)
	_check(not los.call(inside, outside), "a bot inside cannot see out")
	_check(los.call(outside, inside), "a bot outside sees in")
	_check(sight.shot_mask(inside, 1) == (1 | layer), "a shot from inside counts the glass layer")
	_check(sight.shot_mask(outside, 1 | layer) == 1, "a shot from outside never does")
	var shared := DotMapGlassSight.new(Vector3.ZERO, 3.0, 1)
	shared.world_mask = 1
	_check(shared.shot_mask(outside, 1) == 1, "a glass bit shared with the world is never stripped from an outside shot")
	_check(shared.problem() != "" and sight.problem() == "", "a shared glass layer is reported, an own one is not")
	var q := PhysicsRayQueryParameters3D.create(inside, outside, sight.shot_mask(inside, 1))
	_check(not space.intersect_ray(q).is_empty(), "the masked ray from inside hits the glass")
	q = PhysicsRayQueryParameters3D.create(outside, inside, sight.shot_mask(outside, 1))
	_check(space.intersect_ray(q).is_empty(), "the masked ray from outside passes through to the inside")
	sight.set_cvar("sv_glass_block_sight", "0")
	_check(los.call(inside, outside), "sv_glass_block_sight 0 lets the bot see out")
	_check(sight.shot_mask(inside, 1) == (1 | layer), "and leaves shots blocked")
	sight.set_cvar("sv_glass_block_shots", "0")
	_check(sight.shot_mask(inside, 1) == 1, "sv_glass_block_shots 0 lets a shot out")
	_check(not sight.set_cvar("sv_other", "1"), "a foreign cvar name is refused")
	_check(sight.cvar_specs().size() == 2, "two cvars are offered")
	_check(not DotMapGlassSight.new(Vector3.ZERO, 3.0, 0).blocks(space, inside, outside), "with no glass layer nothing blocks")
	body.free()
	_done()
