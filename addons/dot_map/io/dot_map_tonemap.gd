class_name DotMapTonemap
extends DotMapEntity

## env_tonemap_controller: SetAutoExposureMin/Max and SetBloomScale keep the value and send a [code]tonemap[/code] event
## ([code]{entity, name, setting, value}[/code]) for a game that has an environment to adjust. Its other inputs stay
## unlisted. [member values] is read back by [code]setting[/code].

var values: Dictionary = {}


func _input(io: DotMapIO, name: String, param: String, _activator: Variant, _caller: Variant) -> bool:
	var setting := ""
	match name:
		"setautoexposuremin":
			setting = "auto_exposure_min"
		"setautoexposuremax":
			setting = "auto_exposure_max"
		"setbloomscale":
			setting = "bloom_scale"
		_:
			return false
	values[setting] = param.to_float()
	io.event("tonemap", {"entity": index, "name": targetname, "setting": setting, "value": values[setting]})
	return true
