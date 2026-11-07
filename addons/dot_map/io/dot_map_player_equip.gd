class_name DotMapPlayerEquip
extends DotMapEntity

## game_player_equip: gives a player the weapons and items its keys list (every key but the engine's own, whose value
## is the ammunition count). The game owns inventories, so this only says what and to whom through the
## [code]equip[/code] event: [code]items[/code] (class to count), [code]to[/code] ("activator" or "all"), [code]strip_first[/code]
## (spawnflag 2, "strip all weapons first") and [code]use_only[/code] (spawnflag 1, only when the activator is the holder).

const ENGINE_KEYS := ["origin", "angles", "targetname", "spawnflags", "classname", "parentname", "hammerid", "globalname",
		"startdisabled", "filtername", "renderfx", "rendercolor", "renderamt", "rendermode", "disableshadows", "disablereceiveshadows"]


func _input(io: DotMapIO, name: String, _param: String, activator: Variant, _caller: Variant) -> bool:
	var to := ""
	match name:
		"equipactivator":
			to = "activator"
		"equipallplayers":
			to = "all"
		_:
			return false
	if not enabled:
		return true
	io.event("equip", {"entity": index, "to": to, "items": items(), "strip_first": has_spawnflag(2),
			"use_only": has_spawnflag(1), "activator": activator})
	return true


## {class: count} of what this entity hands out.
func items() -> Dictionary:
	var out := {}
	for k: String in keys:
		if ENGINE_KEYS.has(k) or k.begins_with("on"):
			continue
		out[k] = maxi(1, int(keys[k]))
	return out
