class_name DotMapCounter
extends DotMapEntity

## math_counter: a number with optional bounds; OutValue fires on every change, OnHitMax and
## OnHitMin when a bound is reached.

var value := 0.0
var _min := 0.0
var _max := 0.0
var _hit_max := false
var _hit_min := false


func _configure() -> void:
	_min = key_float("min")
	_max = key_float("max")
	value = key_float("startvalue")


func _input(io: DotMapIO, name: String, param: String, activator: Variant, _caller: Variant) -> bool:
	var v := param.to_float()
	match name:
		"add":
			_assign(io, value + v, activator, true)
		"subtract":
			_assign(io, value - v, activator, true)
		"multiply":
			_assign(io, value * v, activator, true)
		"divide":
			if v != 0.0:
				_assign(io, value / v, activator, true)
		"setvalue":
			_assign(io, v, activator, true)
		"setvaluenofire":
			_assign(io, v, activator, false)
		"sethitmax":
			_max = v
		"sethitmin":
			_min = v
		"getvalue":
			fire(io, "OnGetValue", activator, _fmt(value))
		_:
			return false
	return true


func _bounded() -> bool:
	return _min != 0.0 or _max != 0.0


func _assign(io: DotMapIO, v: float, activator: Variant, fire_outputs: bool) -> void:
	if not enabled:
		return
	var nv := clampf(v, _min, _max) if _bounded() else v
	value = nv
	io.report_state(self, "value", value)
	if not fire_outputs:
		return
	fire(io, "OutValue", activator, _fmt(value))
	if _bounded():
		if value >= _max:
			if not _hit_max:
				_hit_max = true
				fire(io, "OnHitMax", activator)
		else:
			_hit_max = false
		if value <= _min:
			if not _hit_min:
				_hit_min = true
				fire(io, "OnHitMin", activator)
		else:
			_hit_min = false


func _fmt(v: float) -> String:
	return str(int(v)) if v == floorf(v) else str(v)


func state() -> Dictionary:
	var s := super.state()
	s["value"] = value
	return s
