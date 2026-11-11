class_name DotMapPropDynamic
extends DotMapEntity

## prop_dynamic and prop_dynamic_override: the shared inputs (Enable, Disable, Kill, Color, SetParent) plus
## SetAnimation and SetDefaultAnimation, which only send a [code]prop_animation[/code] event: the stand-in models have no
## animations, so the view does not change unless the game answers the event. Skin sends a [code]prop_skin[/code] event
## (the stand-in has one material, so the same holds). No per-frame cost.


func _input(io: DotMapIO, name: String, param: String, _activator: Variant, _caller: Variant) -> bool:
	match name:
		"setanimation", "setdefaultanimation":
			io.event("prop_animation", {"entity": index, "name": targetname, "animation": param.strip_edges(),
					"default": name == "setdefaultanimation"})
		"skin":
			io.event("prop_skin", {"entity": index, "name": targetname, "skin": int(param.strip_edges())})
		_:
			return false
	return true
