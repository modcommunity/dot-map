class_name DotMapGameScore
extends DotMapEntity

## game_score: ApplyScore awards [code]points[/code] to the activator (spawnflag 2: to the activator's team), the team inputs
## to a team. The game owns scores, so this only says who gets what through the [code]score[/code] event.


func _input(io: DotMapIO, name: String, _param: String, activator: Variant, _caller: Variant) -> bool:
	var team := 0
	match name:
		"applyscore":
			pass
		"addscorect":
			team = 3
		"addscoreterrorist":
			team = 2
		_:
			return false
	if not enabled:
		return true
	io.event("score", {"entity": index, "points": int(key_float("points", 1.0)), "to_team": has_spawnflag(2),
			"team": team, "allow_negative": has_spawnflag(1), "activator": activator})
	return true
