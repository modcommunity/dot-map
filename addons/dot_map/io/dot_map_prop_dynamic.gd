class_name DotMapPropDynamic
extends DotMapEntity

## prop_dynamic and prop_dynamic_override: the shared inputs (Enable, Disable, Kill, Color, SetParent) plus
## SetAnimation and SetDefaultAnimation, which only send a [code]prop_animation[/code] event: the stand-in models have no
## animations, so the view does not change unless the game answers the event. No per-frame cost.


func _input(io: DotMapIO, name: String, param: String, _activator: Variant, _caller: Variant) -> bool:
	match name:
		"setanimation", "setdefaultanimation":
			io.event("prop_animation", {"entity": index, "name": targetname, "animation": param.strip_edges(),
					"default": name == "setdefaultanimation"})
		_:
			return false
	return true
