class_name DotMapPhysbox
extends DotMapBreakable

## func_physbox: a brush that is a physics object. [DotMapWorld] gives its model a [RigidBody3D]
## (convex hulls, the drawn meshes riding on it) and binds it with [method bind_body]; the
## authority simulates it and a client keeps it frozen. EnableMotion / DisableMotion freeze and
## free it, Wake / Sleep put it to sleep, and [code]damagetoenablemotion[/code] /
## [code]forcetoenablemotion[/code] above zero start it frozen until one hit of that size.
## Breaking (health, Break) works as for any breakable. Not done: replicating the pose to a client.

var body: RigidBody3D = null
var motion := true
var _wake_damage := 0.0


func _configure() -> void:
	super._configure()
	_wake_damage = maxf(key_float("damagetoenablemotion"), key_float("forcetoenablemotion"))
	motion = _wake_damage <= 0.0


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
	return s
