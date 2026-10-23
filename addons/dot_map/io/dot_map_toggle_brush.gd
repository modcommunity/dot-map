class_name DotMapToggleBrush
extends DotMapEntity

## func_brush, func_wall_toggle and func_illusionary: a brush that is shown or hidden, and solid
## or not, by Enable/Disable/Toggle. [member alpha] and [member color] are state for the game.

## Whether a drawn brush also blocks bodies: [code]toggle[/code] follows enabled, [code]never[/code]
## and [code]always[/code] ignore it (func_illusionary is never solid).
var solidity := "toggle"
## 0 to 255, the Alpha input; shown as the node's transparency.
var alpha := 255


func _configure() -> void:
	match classname.to_lower():
		"func_illusionary":
			solidity = "never"
		"func_wall_toggle":
			enabled = not has_spawnflag(1)
			if has_spawnflag(2):
				solidity = "never"
		_:
			match int(key_float("solidity")):
				1:
					solidity = "never"
				2:
					solidity = "always"
	alpha = int(key_float("renderamt", 255.0))
	color = key("rendercolor") if key("rendercolor") != "255 255 255" else ""


## Whether bodies are blocked right now.
func is_solid() -> bool:
	match solidity:
		"never":
			return false
		"always":
			return alive
	return enabled and alive


func _input(io: DotMapIO, name: String, param: String, _activator: Variant, _caller: Variant) -> bool:
	match name:
		"alpha":
			alpha = clampi(int(param.to_float()), 0, 255)
			io.report_state(self, "alpha", alpha)
		"setsolid":
			solidity = "always" if param.strip_edges() != "0" else "never"
			io.report_state(self, "solidity", solidity)
		_:
			return false
	return true


func _apply(_io: DotMapIO, key_: String, value: Variant, _tick: int) -> bool:
	match key_:
		"alpha":
			alpha = int(value)
		"solidity":
			solidity = str(value)
		_:
			return false
	return true


func _view_changed(key_: String, value: Variant) -> void:
	super._view_changed(key_, value)
	if node == null:
		return
	match key_:
		"enabled", "solidity", "alive":
			node.visible = enabled and alive
			set_solid(node, is_solid())
		"alpha":
			for m in node.find_children("*", "GeometryInstance3D", true, false):
				(m as GeometryInstance3D).transparency = 1.0 - float(alpha) / 255.0


func state() -> Dictionary:
	var s := super.state()
	s["alpha"] = alpha
	s["solidity"] = solidity
	return s
