extends Node3D

## [DotMapEntities] on a real converted map's entity data.
##
## [codeblock]
## godot --headless --path . res://examples/bsp_entities_demo.tscn
## [/codeblock]
##
## The data is [code]examples/bsp_mesh/zm_4way_tunnel.entities.json[/code], written by
## [code]tools/bsp/tests/entities_fixture.py[/code] from a community map with three lifts
## (toggle doors moved by buttons that lock and unlock one another), hinged doors, shutters, and
## classes the converter keeps as data.

const CHECKS := 44
const SECTIONS := 7
const REAL := "res://examples/bsp_mesh/zm_4way_tunnel.entities.json"

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()
var _entered := 0
var _completed := 0
var _doc: Dictionary = {}


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("dot-map bsp entities")
	_doc = JSON.parse_string(FileAccess.get_file_as_string(REAL))
	if _doc is Dictionary and not _doc.is_empty():
		var ents := DotMapEntities.from_manifest(_doc)
		_test_parse(ents)
		_test_travel(ents)
		_test_links(ents)
		_test_generic(ents)
		_test_push()
	_test_trails()
	_test_decal_kinds()
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


func _test_parse(ents: DotMapEntities) -> void:
	_section("parses a real converted map")
	var d := ents.describe()
	_check(d["movers"] == 34 and d["volumes"] == 2 and d["links"] == 113 and d["generic"] == 21, "section sizes: %s" % d)
	var plate := ents.mover_named("LIFT02_PLATE")
	_check(plate != null and plate.kind == "slide" and plate.toggle, "the lift plate, found case-insensitively")
	_check(ents.mover_for_model(plate.model) == plate, "mover_for_model finds it")
	_check(ents.mover_of(plate.entity) == plate, "mover_of finds it")
	var kinds := {}
	for m in ents.movers:
		kinds[m.kind] = true
	_check(kinds.has("button") and kinds.has("rotate") and kinds.has("path") and kinds.has("slide"), "kinds: %s" % [kinds.keys()])
	var locked := ents.mover_named("lift02_button_down")
	_check(locked != null and locked.locked and locked.kind == "button", "a button that starts locked")
	var shut := ents.mover_named("Shutter_left01")
	_check(shut != null and shut.kind == "path" and shut.path().size() == 1, "a train carries its path")
	_check(ents.volumes_of("hurt").size() == 2, "two hurt volumes")
	_done()


func _test_travel(ents: DotMapEntities) -> void:
	_section("door and lift travel comes from the brush bounds")
	var plate := ents.mover_named("lift02_plate")
	var rec := plate.record
	var height: float = rec["maxs"][1] - rec["mins"][1]
	_check(is_equal_approx(plate.distance, height - 2 * 0.01905 - float(rec["lip"])), "distance is size less 2 units less lip: %f vs %f" % [plate.distance, height])
	_check(plate.direction.is_equal_approx(Vector3.UP), "it moves up: %s" % plate.direction)
	_check(plate.is_animatable() and plate.transform_at(1.0).origin.is_equal_approx(Vector3.UP * plate.distance), "transform_at(1) is the full travel")
	_check(plate.transform_at(0.5).origin.is_equal_approx(Vector3.UP * plate.distance * 0.5), "transform_at(0.5) is half")
	_check(is_equal_approx(plate.travel_time, plate.distance / plate.speed) and plate.travel_time > 1.0, "travel_time is distance over speed: %f" % plate.travel_time)
	_check(is_equal_approx(plate.advance(0.0, true, plate.travel_time / 4.0), 0.25) and plate.advance(0.9, false, 1e6) == 0.0, "advance moves a quarter, and stops at closed")
	var hinge: DotMapMover = null
	for m in ents.movers:
		if m.kind == "rotate":
			hinge = m
			break
	_check(hinge != null and is_equal_approx(hinge.degrees, 90.0) and is_equal_approx(hinge.travel_time, 0.9), "a hinge door turns 90 degrees at 100 a second")
	var turned := hinge.transform_at(1.0).basis * Vector3.RIGHT
	_check(turned.is_equal_approx(Basis(hinge.axis, deg_to_rad(90.0)) * Vector3.RIGHT), "its transform turns about its axis")
	var button := ents.mover_named("lift02_button_up")
	_check(button.distance == 0.0 and not button.is_animatable(), "a button that does not move says so")
	var hurt := ents.volumes_of("hurt")[0]
	var box := hurt.bounds()
	_check(box.size.x > 0.0 and hurt.contains(box.get_center()) and not hurt.contains(box.end + Vector3.ONE), "a hurt volume contains its middle and not past its corner: %s" % box)
	_done()


func _test_links(ents: DotMapEntities) -> void:
	_section("the link graph resolves")
	var plate := ents.mover_named("lift02_plate")
	var up := ents.mover_named("lift02_button_up")
	var fired := ents.links.fired_by(up.entity, "OnPressed")
	var opens := fired.filter(func(l: Dictionary) -> bool: return l["input"] == "Open" and plate.entity in l["to"])
	_check(opens.size() == 1, "pressing the up button opens the plate: %s" % [fired])
	_check(ents.links.driving(plate.entity, "close").size() == 2, "two links close the plate")
	_check(ents.links.driving(plate.entity).size() == plate.opened_by.size(), "the graph and opened_by agree")
	var sorted := ents.links.fired_by(ents.mover_named("lift01_button_up").entity)
	var ordered := true
	for i in range(1, sorted.size()):
		ordered = ordered and float(sorted[i - 1]["delay"]) <= float(sorted[i]["delay"])
	_check(not sorted.is_empty() and ordered, "fired_by orders by delay")
	var delayed := ents.links.driving(ents.mover_named("lift01_button_down").entity, "Unlock").filter(func(l: Dictionary) -> bool: return l["delay"] == 10.0)
	_check(delayed.size() == 2, "the down button unlocks ten seconds later")
	_check(ents.links.named("lift02_PLATE") == PackedInt32Array([plate.entity]), "named() is case-insensitive")
	var stray := ents.links.unresolved()
	_check(stray.size() == 1 and stray[0]["target"] == "phys_prp", "one link aims at a name nothing carries: %s" % [stray])
	var bad := false
	for l: Dictionary in _doc["links"]:
		for t in l["to"]:
			bad = bad or str(ents.links._names.get(int(t), l["target"])).to_lower() != str(l["target"]).to_lower()
	_check(not bad, "every resolved link points at an entity of that name")
	_done()


func _test_generic(ents: DotMapEntities) -> void:
	_section("classes the converter does not know survive")
	_check(ents.generic_of("path_track").size() == 6 and ents.generic_of("logic_auto").size() == 1, "path and logic entities kept")
	_check(ents.unknown_classes().is_empty(), "the real map has none unknown")
	var doc := {"entities": [{"entity": 7, "classname": "made_up_entity", "targetname": "x", "treatment": "unknown", "keys": {"foo": "bar"}}],
			"links": [{"from": 7, "output": "OnThing", "target": "y", "input": "Go", "delay": 0.5, "to": [], "special": false}]}
	var e := DotMapEntities.from_manifest(doc)
	_check(e.unknown_classes() == PackedStringArray(["made_up_entity"]), "an unknown class is reported")
	_check(e.generic_of("made_up_entity")[0]["keys"]["foo"] == "bar", "with every key it had")
	_check(e.links.unresolved().size() == 1 and e.links.fired_by(7, "OnThing")[0]["delay"] == 0.5, "its outputs are in the graph")
	var empty := DotMapEntities.from_manifest({})
	_check(empty.movers.is_empty() and empty.links.size() == 0 and empty.mover_named("x") == null, "an old manifest with none of it reads as empty")
	_done()


func _test_decal_kinds() -> void:
	_section("a decal whose texture says nothing is left out, not drawn as a dark stain")
	var fx := DotMapFx.new()
	_check(fx._kind_of("props/decal_prison01a").is_empty(), "an unknown name draws nothing")
	_check(str(fx._kind_of("decals/blood3")[0]) == "blood" and str(fx._kind_of("decals/oilstain")[0]) == "stain", "known names keep their kind")
	_done()


func _test_trails() -> void:
	_section("env_spritetrail draws a ribbon behind what it follows")
	var mk := func(cls: String, pairs: Array) -> Dictionary: return {"classname": cls, "pairs": pairs}
	var fx := DotMapFx.new()
	var mover := Node3D.new()
	fx.trail_target_fn = func(n: String) -> Node3D: return mover if n == "rocket" else null
	var root := fx.build([mk.call("env_spritetrail", [["origin", "0 0 100"], ["lifetime", "1"], ["startwidth", "20"], ["endwidth", "0"],
			["rendercolor", "255 120 0"], ["parentname", "rocket"]]), mk.call("env_spritetrail", [["targetname", "no origin"]]),
			mk.call("env_sprite", [["origin", "0 0 0"], ["model", "sprites/glow01.vmt"]])])
	add_child(root)
	_check(int(fx.stats["trails"]) == 1 and int(fx.stats["skipped"]) == 1 and int(fx.stats["sprites"]) == 1, "one trail drawn, one without an origin skipped, sprites unchanged: %s" % [fx.stats])
	var t: DotMapTrail = null
	for c in root.get_children():
		if c is DotMapTrail:
			t = c
	_check(t.follow == mover and is_equal_approx(t.lifetime, 1.0) and t.start_width > t.end_width and t.colour.r > 0.99, "it follows its parent and takes the entity's lifetime, widths and colour")
	var eye := Vector3(0, 5, 5)
	var n := 0
	for i in 10:
		n = t.advance(0.05, Vector3(i * 0.2, 0, 0), eye)
	_check(n == 10, "a moving point adds a sample each step (%d)" % n)
	_check(t.advance(0.05, Vector3(1.8, 0, 0), eye) == 10, "standing still adds none")
	n = t.advance(2.0, Vector3(1.8, 0, 0), eye)
	_check(n == 0, "old samples expire past the lifetime (%d)" % n)
	root.free()
	mover.free()
	_done()


func _test_push() -> void:
	_section("a push volume carries its direction and speed")
	var planes := [[1, 0, 0, 1], [-1, 0, 0, 1], [0, 1, 0, 1], [0, -1, 0, 1], [0, 0, 1, 1], [0, 0, -1, 1]]
	var rec := {"entity": 3, "model": 2, "classname": "trigger_push", "kind": "push", "spawnflags": 65, "disabled": true,
			"direction": [0.0, 1.0, 0.0], "speed": 95.25, "brushes": [planes]}
	var ents := DotMapEntities.from_manifest({"volumes": [rec]})
	var v := ents.volumes_of("push")[0]
	_check(v.direction == Vector3.UP and is_equal_approx(v.speed, 95.25), "direction and speed read: %s %f" % [v.direction, v.speed])
	_check(v.push_velocity().is_equal_approx(Vector3.UP * 95.25), "push_velocity is direction times speed")
	_check(v.spawnflags == 65 and v.disabled, "spawnflags and the start-disabled state read")
	_check(v.contains(Vector3.ZERO) and v.bounds().size.is_equal_approx(Vector3(2, 2, 2)), "it contains its middle and boxes 2 m")
	_check(DotMapVolume.from_record({"kind": "hurt", "direction": [0, 1, 0], "speed": 3.0}).push_velocity() == Vector3.ZERO, "another kind pushes nothing")
	_done()
