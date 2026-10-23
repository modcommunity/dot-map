class_name DotMapServerCommand
extends DotMapEntity

## point_servercommand: Command is recorded on the runtime (a chat line
## goes to the game's event callable; a cvar only if allow-listed) and never executed.


func _input(io: DotMapIO, name: String, param: String, _activator: Variant, _caller: Variant) -> bool:
	if name != "command":
		return false
	io.record_command(self, param)
	return true
