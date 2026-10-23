class_name DotMapBranch
extends DotMapEntity

## logic_branch: a boolean; Test fires OnTrue or OnFalse.

var value := false


func _configure() -> void:
	value = flag("initialvalue")


func _input(io: DotMapIO, name: String, param: String, activator: Variant, _caller: Variant) -> bool:
	match name:
		"setvalue":
			value = param.to_float() != 0.0
		"setvaluetest":
			value = param.to_float() != 0.0
			_test(io, activator)
		"toggle":
			value = not value
		"toggletest":
			value = not value
			_test(io, activator)
		"test":
			_test(io, activator)
		_:
			return false
	return true


func _test(io: DotMapIO, activator: Variant) -> void:
	fire(io, "OnTrue" if value else "OnFalse", activator)


func state() -> Dictionary:
	var s := super.state()
	s["value"] = value
	return s
