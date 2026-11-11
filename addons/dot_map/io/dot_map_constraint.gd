class_name DotMapConstraint
extends DotMapEntity

## phys_ballsocket, phys_hinge, phys_constraint, phys_lengthconstraint, phys_slideconstraint: Break fires OnBreak once,
## sends a [code]constraint_break[/code] event and, when a [Joint3D] is bound, lets its bodies go. No other input.

var broken := false


func _input(io: DotMapIO, name: String, _param: String, activator: Variant, _caller: Variant) -> bool:
	match name:
		"break":
			if not broken:
				broken = true
				_release()
				io.event("constraint_break", {"entity": index, "name": targetname, "classname": classname})
				fire(io, "OnBreak", activator)
				io.report_state(self, "broken", true)
		_:
			return false
	return true


func state() -> Dictionary:
	var st := super.state()
	if broken:
		st["broken"] = true
	return st


func _apply(_io: DotMapIO, key: String, value: Variant, _tick: int) -> bool:
	if key != "broken":
		return false
	broken = bool(value)
	if broken:
		_release()
	return true


func _release() -> void:
	if node is Joint3D:
		(node as Joint3D).node_a = NodePath()
		(node as Joint3D).node_b = NodePath()
