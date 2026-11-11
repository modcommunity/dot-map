class_name DotMapClientCommand
extends DotMapEntity

## point_clientcommand: Command is recorded as kind "clientcommand" for the game to read and is never executed, not even for an allow-listed name.


func _input(io: DotMapIO, name: String, param: String, _activator: Variant, _caller: Variant) -> bool:
	match name:
		"command":
			io.record_client_command(self, param)
		_:
			return false
	return true
