extends Node

## Press-E on a real converted map: the look ray finds a func_button, a press in reach moves its target door, and the
## refusals (too far, cooling down, a wall between, nothing under the eye) leave the door alone. Prints SKIP without the world.

const CHECKS := 15
const SECTIONS := 3
const WORLD := "godot/arena-surf-dm-maps/worlds/surf_forbidden_ways_2nd/surf_forbidden_ways_2nd"
const BUTTON := 39

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()
var _entered := 0
var _completed := 0
var _dw: DotMapWorld
var _use: DotMapUse
var _button: DotMapMoverNode
var _door: DotMapMoverNode
var _eye := Vector3.ZERO
var _dir := Vector3.ZERO


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("dot-map use")
	var prefix := OS.get_environment("HOME").path_join(WORLD)
	var res := DotMapBspMesh.load_prefix(prefix)
	if not res.ok:
		print("SKIP: no converted world at " + prefix)
		get_tree().quit(0)
		return
	var built := DotMapWorld.build(res.value as DotMapBspMesh, {})
	if not built.ok:
		printerr("cannot build: ", built.error)
		get_tree().quit(3)
		return
	_dw = built.value
	add_child(_dw)
	_use = DotMapUse.new(_dw)
	_button = _dw.io.entity_of(BUTTON) as DotMapMoverNode
	for c: DotMapEntity in _dw.io.entities:
		if _button != null and c is DotMapMoverNode and c.targetname == "jaildoor":
			_door = c
	await get_tree().physics_frame
	await get_tree().physics_frame
	await _test_aim()
	await _test_press()
	await _test_refusals()
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


func _space() -> PhysicsDirectSpaceState3D:
	return _dw.get_world_3d().direct_space_state


## An eye 1.2 m from the button along the first axis from which the look ray reaches it.
func _find_eye() -> bool:
	var centre := _button_centre()
	for d: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK, Vector3.UP, Vector3.DOWN]:
		var info := _use.aim(_space(), centre + d * 1.2, -d)
		if not info.is_empty() and info["index"] == BUTTON:
			_eye = centre + d * 1.2
			_dir = -d
			return true
	return false


func _button_centre() -> Vector3:
	var box := AABB()
	var first := true
	for holder in _dw.visual.get_children():
		if holder.has_meta(&"model") and str(_button.key("model")) == "*%d" % int(holder.get_meta(&"model")):
			for cs in holder.find_children("*", "CollisionShape3D", true, false):
				var s: Shape3D = (cs as CollisionShape3D).shape
				if s == null:
					continue
				var b: AABB = (cs as CollisionShape3D).global_transform * s.get_debug_mesh().get_aabb()
				box = b if first else box.merge(b)
				first = false
	return box.get_center()


func _test_aim() -> void:
	_section("the look ray finds the button")
	_check(_button != null and _button.use_state() == &"ready", "button 39 is a usable mover")
	_check(_door != null, "its target is a mover")
	_check(_find_eye(), "a spot exists from which the ray reaches the button")
	var info := _use.aim(_space(), _eye, _dir)
	_check(info.get("index", -1) == BUTTON and bool(info.get("in_range", false)), "aim reports the button in reach")
	_check(info.get("label", "") == "Use", "the prompt says Use")
	_check(_use.aim(_space(), _eye, -_dir).is_empty(), "looking away finds nothing")
	_completed += 1


func _test_press() -> void:
	_section("a press moves the target")
	var before := _door.fraction_at(_dw.io.now, _dw.io.rate)
	var res := _use.press(_space(), _eye, _dir, "p1")
	_check(res.ok, "the press succeeds")
	_dw.io.advance(int(_door.mover.travel_time * _dw.io.rate) + 5)
	var after := _door.fraction_at(_dw.io.now, _dw.io.rate)
	_check(absf(after - before) > 0.5, "the door moved (%.2f to %.2f)" % [before, after])
	_check(_button.use_state() == &"pressed" or _button.use_state() == &"ready", "the button has a state after the press")
	_completed += 1


func _test_refusals() -> void:
	_section("what must not press")
	_dw.io.advance(_dw.io.ticks_for(30.0))
	var far := _use.press(_space(), _eye - _dir * 5.0, _dir, "p2")
	_check(not far.ok, "out of reach is refused")
	_check(not _use.press(_space(), _eye, -_dir, "p2").ok, "nothing under the eye is refused")
	var first := _use.press(_space(), _eye, _dir, "p3")
	var again := _use.press(_space(), _eye, _dir, "p3")
	_check(first.ok or _button.use_state() == &"pressed", "a first press is taken or the button is still in")
	_check(not again.ok, "the same user pressing again at once is refused")
	_use.reach = 0.1
	_check(not _use.press(_space(), _eye, _dir, "p4").ok, "a shorter sv_use_reach refuses the same press")
	_check(_use.set_cvar("sv_use_reach", "3.5") and is_equal_approx(_use.reach, 3.5), "the cvar sets reach")
	_completed += 1
