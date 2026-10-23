class_name DotMapPhysbox
extends DotMapBreakable

## func_physbox: a brush that is a physics object. [DotMapWorld] gives its model a [RigidBody3D]
## (convex hulls, the drawn meshes riding on it) and binds it with [method bind_body]; the
## authority simulates it and a client keeps it frozen. EnableMotion / DisableMotion freeze and
## free it, Wake / Sleep put it to sleep, and [code]damagetoenablemotion[/code] /
## [code]forcetoenablemotion[/code] above zero start it frozen until one hit of that size.
## Breaking (health, Break) works as for any breakable. The authority reports the body's pose as the
## [code]pose[/code] state ([code][x, y, z, qx, qy, qz, qw][/code], local to the model node) ten times a second
## while it moves, and a client eases its frozen body toward the last one.

var body: RigidBody3D = null
var motion := true
var _wake_damage := 0.0
var _pose_sent := Transform3D()
var _pose_tick := -1000000
var _pose_target := Transform3D()
var _has_target := false


func _configure() -> void:
	super._configure()
	_wake_damage = maxf(key_float("damagetoenablemotion"), key_float("forcetoenablemotion"))
	motion = _wake_damage <= 0.0
	animated = true


## Takes the world's rigid body for this model; mass follows [code]massscale[/code].
func bind_body(rb: RigidBody3D, authoritative: bool) -> void:
	body = rb
	rb.mass = maxf(key_float("massscale", 1.0), 0.01) * rb.mass
	_apply_motion(authoritative)


func _apply_motion(authoritative := true) -> void:
	if body == null:
		return
	body.freeze = not (motion and authoritative)
	body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC


## Authority: reports a moved body's pose (tenth of a second apart, and once more when it stops).
## Client: eases the frozen body toward the last pose received.
func tick_view(io: DotMapIO) -> void:
	if body == null or not alive:
		return
	if io.authoritative:
		if io.now - _pose_tick < maxi(io.rate / 10, 1):
			return
		var t := body.transform
		if t.origin.distance_to(_pose_sent.origin) < 0.002 and t.basis.get_rotation_quaternion().angle_to(_pose_sent.basis.get_rotation_quaternion()) < 0.002:
			return
		_pose_tick = io.now
		_pose_sent = t
		io.report_state(self, "pose", _pose_array(t))
	elif _has_target:
		body.transform = body.transform.interpolate_with(_pose_target, 0.4)


static func _pose_array(t: Transform3D) -> Array:
	var q := t.basis.get_rotation_quaternion()
	return [t.origin.x, t.origin.y, t.origin.z, q.x, q.y, q.z, q.w]


func hurt(io: DotMapIO, amount: float, at: Vector3 = Vector3.ZERO, by: Variant = null) -> bool:
	if not motion and _wake_damage > 0.0 and amount >= _wake_damage:
		_set_motion(io, true, by)
	return super.hurt(io, amount, at, by)


func _set_motion(io: DotMapIO, on: bool, by: Variant) -> void:
	if motion == on:
		return
	motion = on
	_apply_motion(io.authoritative)
	io.report_state(self, "motion", on)
	if on:
		fire(io, "OnMotionEnabled", by)


func _input(io: DotMapIO, name: String, param: String, activator: Variant, caller: Variant) -> bool:
	match name:
		"enablemotion":
			_set_motion(io, true, activator)
		"disablemotion":
			_set_motion(io, false, activator)
		"wake":
			if body != null:
				body.sleeping = false
			fire(io, "OnAwakened", activator)
		"sleep":
			if body != null:
				body.sleeping = true
		"disablefloating", "forcedrop":
			pass
		_:
			return super._input(io, name, param, activator, caller)
	return true


func _apply(io: DotMapIO, key_: String, value: Variant, tick: int) -> bool:
	if key_ == "pose":
		if not value is Array or (value as Array).size() != 7:
			return false
		var a: Array = value
		_pose_target = Transform3D(Basis(Quaternion(float(a[3]), float(a[4]), float(a[5]), float(a[6])).normalized()),
				Vector3(float(a[0]), float(a[1]), float(a[2])))
		if not _has_target and body != null:
			body.transform = _pose_target
		_has_target = true
		return true
	if key_ == "motion":
		motion = bool(value)
		_apply_motion(io.authoritative)
		return true
	return super._apply(io, key_, value, tick)


func _break(io: DotMapIO, by: Variant, at: Vector3) -> void:
	super._break(io, by, at)
	if body != null:
		body.freeze = true


func _view_changed(key_: String, value: Variant) -> void:
	super._view_changed(key_, value)
	if body != null and (key_ == "broken" or key_ == "alive") and (key_ == "broken") == bool(value):
		body.freeze = true


func state() -> Dictionary:
	var s := super.state()
	s["motion"] = motion
	if body != null:
		s["pose"] = _pose_array(body.transform)
	return s
