class_name DotMapNpcStub
extends DotMapEntity

## npc_metropolice, npc_combine_s, npc_citizen as the map's I/O sees them: a health value the map may set. There is no
## AI here; [code]SetHealth[/code] stores the value, reports it as state and sends an [code]npc_health[/code] event so a
## game that spawns the NPC can apply it. A game with real NPCs registers its own class or handler instead.

var health := -1.0


func _input(io: DotMapIO, name: String, param: String, _activator: Variant, _caller: Variant) -> bool:
	match name:
		"sethealth":
			health = param.to_float()
			io.event("npc_health", {"entity": index, "name": targetname, "classname": classname, "health": health})
			io.report_state(self, "health", health)
		_:
			return false
	return true


func _apply(_io: DotMapIO, key: String, value: Variant, _tick: int) -> bool:
	if key != "health":
		return false
	health = float(value)
	return true
