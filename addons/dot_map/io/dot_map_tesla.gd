class_name DotMapTesla
extends DotMapEntity

## point_tesla: DoSpark sends one [code]tesla_spark[/code] event (origin, radius, beam count, lifetime, colour) for the
## game to draw; a disabled one does not spark. Nothing is simulated here.


func _input(io: DotMapIO, name: String, _param: String, _activator: Variant, _caller: Variant) -> bool:
	match name:
		"dospark":
			if enabled:
				io.event("tesla_spark", {"entity": index, "name": targetname, "origin": origin(io),
						"radius": key_float("m_flradius", 200.0) * io.unit_scale,
						"beams_min": int(key_float("beamcount_min", 4.0)), "beams_max": int(key_float("beamcount_max", 6.0)),
						"lifetime_min": key_float("lifetime_min", 0.3), "lifetime_max": key_float("lifetime_max", 0.3),
						"color": key("m_color", "255 255 255"), "keys": keys})
		_:
			return false
	return true
