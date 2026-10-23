class_name DotMapCompare
extends DotMapEntity

## logic_compare: holds a value and a comparison value; Compare fires OnLessThan, OnEqualTo,
## OnNotEqualTo or OnGreaterThan.

var value := 0.0
var against := 0.0


func _configure() -> void:
	value = key_float("initialvalue")
	against = key_float("comparevalue")


func _input(io: DotMapIO, name: String, param: String, activator: Variant, _caller: Variant) -> bool:
	match name:
		"setvalue":
			value = param.to_float()
		"setvaluecompare":
			value = param.to_float()
			_compare(io, activator)
		"setcomparevalue":
			against = param.to_float()
		"compare":
			_compare(io, activator)
		_:
			return false
	return true


func _compare(io: DotMapIO, activator: Variant) -> void:
	if value < against:
		fire(io, "OnLessThan", activator, str(value))
	elif value > against:
		fire(io, "OnGreaterThan", activator, str(value))
	else:
		fire(io, "OnEqualTo", activator, str(value))
	if value != against:
		fire(io, "OnNotEqualTo", activator, str(value))


func state() -> Dictionary:
	var s := super.state()
	s["value"] = value
	return s
