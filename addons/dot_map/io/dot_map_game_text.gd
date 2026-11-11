class_name DotMapGameText
extends DotMapEntity

## game_text: Display sends a [code]game_text[/code] event (message, channel, position, colours, timing, effect,
## and whether it goes to every player) for the game's HUD; SetText changes the message. Nothing is drawn here.


func _input(io: DotMapIO, name: String, param: String, activator: Variant, _caller: Variant) -> bool:
	match name:
		"display":
			io.event("game_text", {"entity": index, "name": targetname, "message": key("message"),
					"channel": int(key_float("channel")), "x": key_float("x", -1.0), "y": key_float("y", -1.0),
					"effect": int(key_float("effect")), "color": key("color", "100 100 100"),
					"color2": key("color2", "240 110 0"), "fadein": key_float("fadein", 1.5),
					"fadeout": key_float("fadeout", 0.5), "holdtime": key_float("holdtime", 1.2),
					"all_players": has_spawnflag(1), "activator": activator})
		"settext":
			keys["message"] = param
		_:
			return false
	return true
