class_name DotMapTimer
extends DotMapEntity

## logic_timer: fires OnTimer every RefireTime seconds (or a random time between two bounds),
## alternating OnTimerHigh and OnTimerLow, while enabled.

var _gen := 0
var _high := false
var _armed := false
var _lo := 0.0
var _hi := 0.0
var _refire := 0.0
var _random := false


func _configure() -> void:
	_refire = key_float("refiretime", 1.0)
	_random = flag("userandomtime")
	_lo = key_float("lowerrandombound")
	_hi = key_float("upperrandombound")


func on_map_spawn(io: DotMapIO) -> void:
	if enabled:
		_arm(io)


func _input(io: DotMapIO, name: String, param: String, activator: Variant, _caller: Variant) -> bool:
	match name:
		"__timer":
			if enabled and _armed and param == str(_gen):
				_beat(io, activator)
			return true
		"refiretime":
			_refire = param.to_float()
			return true
		"lowerrandombound":
			_lo = param.to_float()
			return true
		"upperrandombound":
			_hi = param.to_float()
			return true
		"firetimer":
			_beat_once(io, activator)
			return true
		"resettimer":
			if enabled:
				_arm(io)
			return true
	return false


func _enabled_changed(io: DotMapIO, on: bool) -> void:
	if on:
		_arm(io)
	else:
		_gen += 1
		_armed = false


func _arm(io: DotMapIO) -> void:
	_gen += 1
	_armed = true
	io.schedule_self(self, "__timer", str(_gen), _interval(io))


func _interval(io: DotMapIO) -> float:
	if _random:
		return io.stream_for(self).next_range_f(minf(_lo, _hi), maxf(_lo, _hi))
	return _refire


func _beat(io: DotMapIO, activator: Variant) -> void:
	_beat_once(io, activator)
	if enabled and _armed:
		_arm(io)


func _beat_once(io: DotMapIO, activator: Variant) -> void:
	fire(io, "OnTimer", activator)
	fire(io, "OnTimerHigh" if _high else "OnTimerLow", activator)
	_high = not _high


func state() -> Dictionary:
	var s := super.state()
	s["high"] = _high
	return s
