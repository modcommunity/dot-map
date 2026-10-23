class_name DotMapMoverNode
extends DotMapEntity

## Doors, lifts, buttons, spinners and trains as entities of the I/O runtime, driving the
## converter's [DotMapMover] record from inputs.
##
## [b]Motion is a function of the tick.[/b] Each move is stored as where it started, where it is
## going and the tick it began; the pose at any tick is computed from those, so the server, a
## client and a replay agree and a joiner needs only the stored numbers ([method state]). Arrival
## (OnFullyOpen, an automatic close, a corner passed) is a self-scheduled event at the exact tick.
## Without a record ([method set_mover]) the entity is inert and counted as unbound.
##
## Not done: blocked-damage and pushing bodies (the game's [member DotMapIO.move_fn]), spin-up
## ramps, a train's rotation to follow its path, tank trains.

var mover: DotMapMover = null
var locked := false
## Slide, hinge and button: fraction at the move's start, its target, the start tick, and seconds a full travel takes.
var _from := 0.0
var _to := 0.0
var _t0 := 0
var _tt := 1.0
var _in := false
var _gen := 0
## Spin: angle (radians) at the start tick and the signed turn rate; a train: distance along its path and signed speed.
var _a0 := 0.0
var _v := 0.0
var _last_dir := 1.0
var _base := Transform3D.IDENTITY
var _cum: PackedFloat64Array = PackedFloat64Array()
var _corners: Array = []
var _ring := false
var _length := 0.0
var _shown := -1.0e30


## Gives the entity its record; the starting pose and a train's path are read from it.
func set_mover(m: DotMapMover) -> void:
	mover = m
	animated = true
	locked = m.locked
	_tt = m.travel_time if m.travel_time > 0.0 else 0.0
	_from = m.rest_fraction()
	_to = _from
	_in = false
	if m.kind == DotMapMover.KIND_PATH:
		_build_path()
	elif m.is_spinner():
		_v = m.spin_rate() if m.start_open else 0.0


func is_bound() -> bool:
	return mover != null


## The slide/hinge fraction at [param tick].
func fraction_at(tick: int, rate: int) -> float:
	if _to == _from or _tt <= 0.0:
		return _to
	var step := float(tick - _t0) / float(rate) / _tt
	var d := absf(_to - _from)
	if step >= d:
		return _to
	return _from + signf(_to - _from) * step


## A spinner's angle in radians at [param tick].
func angle_at(tick: int, rate: int) -> float:
	return _a0 + _v * float(tick - _t0) / float(rate)


## A train's distance along its path (metres) at [param tick].
func path_at(tick: int, rate: int) -> float:
	return _wrap(_a0 + _v * float(tick - _t0) / float(rate))


## Where a train's path point is at [param s] metres along it, in the map's own coordinates.
func path_point(s: float) -> Vector3:
	var n := _corners.size()
	if n == 0:
		return Vector3.ZERO
	if n == 1:
		return _corners[0]
	var ss := _wrap(s)
	var segs := n if _ring else n - 1
	for i in segs:
		var a: float = _cum[i]
		var b: float = _cum[i + 1] if i + 1 < _cum.size() else _length
		if ss <= b or i == segs - 1:
			var p0: Vector3 = _corners[i]
			var p1: Vector3 = _corners[(i + 1) % n]
			return p0.lerp(p1, clampf((ss - a) / (b - a), 0.0, 1.0) if b > a else 0.0)
	return _corners[n - 1]


func on_map_spawn(io: DotMapIO) -> void:
	if mover == null:
		return
	if mover.kind == DotMapMover.KIND_PATH and float(mover.record.get("start_speed", 0.0)) > 0.0:
		_drive(io, 1.0, float(mover.record["start_speed"]))
	_view(io)


func _input(io: DotMapIO, name: String, param: String, activator: Variant, _caller: Variant) -> bool:
	if mover == null:
		return false
	match mover.kind:
		DotMapMover.KIND_SPIN:
			return _spin_input(io, name, param)
		DotMapMover.KIND_PATH:
			return _path_input(io, name, param, activator)
		DotMapMover.KIND_BUTTON, DotMapMover.KIND_HINGE_BUTTON:
			if name == "press":
				_press(io, activator)
				return true
	match name:
		"open":
			_open(io, activator)
		"close":
			_close(io, activator)
		"toggle":
			if _to >= 1.0:
				_close(io, activator)
			else:
				_open(io, activator)
		"lock":
			_set_locked(io, true)
		"unlock":
			_set_locked(io, false)
		"setposition":
			_move_to(io, clampf(param.to_float(), 0.0, 1.0))
		"setspeed":
			_set_speed(io, param.to_float())
		"__arrive":
			if int(param) == _gen:
				_arrived(io, activator)
		"__autoclose":
			if int(param) == _gen and _to > 0.0:
				if not mover.kind.ends_with("button"):
					fire(io, "OnClose", null)
				_move_to(io, 0.0)
		_:
			return false
	return true


## A body used or touched it: a button presses, a door toggles; locked ones fire OnLockedUse.
func touched(io: DotMapIO, activator: Variant, use: bool) -> bool:
	if mover == null or not alive:
		return false
	if (use and not mover.use) or (not use and not mover.touch):
		return false
	if locked:
		fire(io, "OnUseLocked" if mover.kind.ends_with("button") else "OnLockedUse", activator)
		return true
	if mover.kind in [DotMapMover.KIND_BUTTON, DotMapMover.KIND_HINGE_BUTTON]:
		_press(io, activator)
	elif _to < 1.0 or mover.toggle or mover.wait < 0.0:
		accept(io, "Toggle", "", activator, null)
	return true


func _press(io: DotMapIO, activator: Variant) -> void:
	if locked:
		fire(io, "OnUseLocked", activator)
		return
	if _in and mover.toggle:
		_in = false
		io.report_state(self, "in", false)
		_move_to(io, 0.0)
		return
	if _in:
		return
	_in = true
	io.report_state(self, "in", true)
	fire(io, "OnPressed", activator)
	_move_to(io, 1.0)


func _open(io: DotMapIO, activator: Variant) -> void:
	if locked or _to >= 1.0:
		return
	fire(io, "OnOpen", activator)
	_move_to(io, 1.0)


func _close(io: DotMapIO, activator: Variant) -> void:
	if locked or _to <= 0.0:
		return
	fire(io, "OnClose", activator)
	_move_to(io, 0.0)


func _set_locked(io: DotMapIO, on: bool) -> void:
	if locked != on:
		locked = on
		io.report_state(self, "locked", on)


func _set_speed(io: DotMapIO, units_per_second: float) -> void:
	if units_per_second <= 0.0 or mover == null:
		return
	var full := absf(mover.degrees) if mover.kind in [DotMapMover.KIND_HINGE, DotMapMover.KIND_HINGE_BUTTON] else mover.distance
	var per_second := units_per_second if full == absf(mover.degrees) else units_per_second * 0.0254
	if full <= 0.0:
		return
	var f := fraction_at(io.now, io.rate)
	_tt = full / per_second
	_start_move(io, f, _to)


func _move_to(io: DotMapIO, target: float) -> void:
	_start_move(io, fraction_at(io.now, io.rate), target)


func _start_move(io: DotMapIO, from: float, target: float) -> void:
	_from = from
	_to = target
	_t0 = io.now
	_gen += 1
	var ticks := 0
	if _tt > 0.0:
		ticks = int(ceil(absf(_to - _from) * _tt * float(io.rate) - 1.0e-6))
	io.schedule_self(self, "__arrive", str(_gen), float(ticks) / float(io.rate))
	io.report_state(self, "motion", [_from, _to, _t0, _tt])


func _arrived(io: DotMapIO, activator: Variant) -> void:
	if _to >= 1.0:
		fire(io, "OnFullyOpen" if not mover.kind.ends_with("button") else "OnIn", activator)
		var button := mover.kind.ends_with("button")
		if not mover.toggle and (mover.wait >= 0.0 if button else mover.wait > 0.0):
			io.schedule_self(self, "__autoclose", str(_gen), mover.wait)
	else:
		fire(io, "OnFullyClosed" if not mover.kind.ends_with("button") else "OnOut", activator)
		if _in:
			_in = false
			io.report_state(self, "in", false)


func _spin_input(io: DotMapIO, name: String, param: String) -> bool:
	var top := mover.spin_rate()
	match name:
		"start":
			_spin(io, absf(top) * _last_dir)
		"stop":
			_spin(io, 0.0)
		"toggle":
			_spin(io, 0.0 if _v != 0.0 else absf(top) * _last_dir)
		"reverse":
			_last_dir = -_last_dir
			_spin(io, -_v if _v != 0.0 else 0.0)
		"setspeed":
			_spin(io, clampf(param.to_float(), 0.0, 1.0) * absf(top) * _last_dir)
		_:
			return false
	return true


func _spin(io: DotMapIO, rate_rad: float) -> void:
	_a0 = angle_at(io.now, io.rate)
	_t0 = io.now
	_v = rate_rad
	io.report_state(self, "spin", [_a0, _v, _t0, _last_dir])


func _build_path() -> void:
	_corners = []
	_ring = false
	var cs: Array = []
	for c: Variant in mover.path():
		if (c as Dictionary).has("loop"):
			_ring = true
		else:
			cs.append(c)
	_cum = PackedFloat64Array()
	var total := 0.0
	var prev := Vector3.ZERO
	for i in cs.size():
		var p := DotMapMover._vec((cs[i] as Dictionary).get("at"))
		_corners.append(p)
		if i > 0:
			total += prev.distance_to(p)
		_cum.append(total)
		prev = p
	if _ring and _corners.size() > 1:
		total += prev.distance_to(_corners[0])
	_length = total
	_a0 = 0.0
	_v = 0.0


func _max_speed() -> float:
	return mover.speed if mover.speed > 0.0 else float(mover.record.get("start_speed", 0.0))


func _wrap(s: float) -> float:
	if _length <= 0.0:
		return 0.0
	return fposmod(s, _length) if _ring else clampf(s, 0.0, _length)


func _path_input(io: DotMapIO, name: String, param: String, activator: Variant) -> bool:
	var top := _max_speed()
	match name:
		"startforward", "resume":
			_drive(io, 1.0, top)
		"startbackward":
			_drive(io, -1.0, top)
		"stop":
			_drive(io, _last_dir, 0.0)
		"toggle":
			_drive(io, _last_dir, 0.0 if _v != 0.0 else top)
		"setspeed":
			_drive(io, _last_dir, top * clampf(param.to_float(), 0.0, 1.0))
		"setspeedreal":
			_drive(io, _last_dir, maxf(param.to_float() * 0.0254, 0.0))
		"teleporttopathtrack":
			var at := _corner_distance(param)
			if at < 0.0:
				return true
			_a0 = at
			_t0 = io.now
			_drive(io, _last_dir, absf(_v))
		"__pass":
			if int(param.get_slice(":", 0)) == _gen:
				_passed(io, int(param.get_slice(":", 1)), activator)
		_:
			return false
	return true


func _corner_distance(corner_name: String) -> float:
	for i in _corners.size():
		if str((mover.path()[i] as Dictionary).get("name", "")).to_lower() == corner_name.strip_edges().to_lower():
			return _cum[i]
	return -1.0


func _drive(io: DotMapIO, dir: float, speed: float) -> void:
	_a0 = path_at(io.now, io.rate)
	_t0 = io.now
	if speed > 0.0:
		_last_dir = dir
	_v = dir * speed
	_gen += 1
	_schedule_pass(io)
	io.report_state(self, "spin", [_a0, _v, _t0, _last_dir])


func _schedule_pass(io: DotMapIO) -> void:
	if _v == 0.0 or _corners.size() < 2:
		return
	var s := _a0
	var best := -1
	var best_d := INF
	var n := _corners.size()
	for k in n + (1 if _ring else 0):
		var c: float = _cum[k] if k < n else _length
		var d := (c - s) * signf(_v)
		if d > 1.0e-6 and d < best_d:
			best_d = d
			best = k
	if best < 0:
		return
	var ticks := int(ceil(best_d / absf(_v) * float(io.rate) - 1.0e-6))
	io.schedule_self(self, "__pass", "%d:%d" % [_gen, best], float(maxi(ticks, 1)) / float(io.rate))


func _passed(io: DotMapIO, k: int, activator: Variant) -> void:
	var n := _corners.size()
	var corner: Dictionary = mover.path()[k % n]
	_a0 = path_at(io.now, io.rate)
	_t0 = io.now
	for e: DotMapEntity in io.find(str(corner.get("name", ""))):
		e.fire(io, "OnPass", self)
		break
	var at_end := not _ring and ((_v > 0.0 and k == n - 1) or (_v < 0.0 and k == 0))
	if at_end:
		_v = 0.0
		_gen += 1
		io.report_state(self, "spin", [_a0, _v, _t0, _last_dir])
		return
	if corner.has("speed") and float(corner["speed"]) > 0.0:
		_v = signf(_v) * float(corner["speed"])
	_gen += 1
	_schedule_pass(io)
	io.report_state(self, "spin", [_a0, _v, _t0, _last_dir])


func _apply(_io: DotMapIO, key_: String, value: Variant, _tick: int) -> bool:
	match key_:
		"motion":
			var m: Array = value
			_from = float(m[0])
			_to = float(m[1])
			_t0 = int(m[2])
			_tt = float(m[3])
		"spin":
			var m: Array = value
			_a0 = float(m[0])
			_v = float(m[1])
			_t0 = int(m[2])
			_last_dir = float(m[3])
		"locked":
			locked = bool(value)
		"in":
			_in = bool(value)
		_:
			return false
	return true


func _bound() -> void:
	if node != null:
		_base = node.transform
		if mover != null and mover.kind == DotMapMover.KIND_PATH and _corners.size() > 0:
			_base = Transform3D(_base.basis, _base.origin - _corners[0])


func tick_view(io: DotMapIO) -> void:
	_view(io)


func _view(io: DotMapIO) -> void:
	if node == null or mover == null or not alive:
		return
	var f: float
	var pose: Transform3D
	match mover.kind:
		DotMapMover.KIND_SPIN:
			f = angle_at(io.now, io.rate)
			pose = Transform3D(Basis(mover.axis.normalized(), f) * _base.basis, _base.origin)
		DotMapMover.KIND_PATH:
			f = path_at(io.now, io.rate)
			pose = Transform3D(_base.basis, _base.origin + path_point(f))
		_:
			f = fraction_at(io.now, io.rate)
			if not mover.is_animatable():
				return
			var t := mover.transform_at(f)
			pose = Transform3D(t.basis * _base.basis, _base.origin + t.origin)
	if f != _shown:
		_shown = f
		node.transform = pose


func state() -> Dictionary:
	var s := super.state()
	s["locked"] = locked
	s["in"] = _in
	s["motion"] = [_from, _to, _t0, _tt]
	s["spin"] = [_a0, _v, _t0, _last_dir]
	return s
