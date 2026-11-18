class_name DotMapTeleport
extends DotMapEntity

## trigger_teleport as logic: where it sends a body is its live [code]target[/code] key, so
## [code]SetRemoteDestination[/code] and [code]AddOutput target ...[/code] re-aim it as in the engine.
## The move itself is [method DotMapVolumeNode._teleport] (the volume carries the touch).


func _input(io: RefCounted, name: String, param: String, _activator: Variant, _caller: Variant) -> bool:
	if name == "setremotedestination":
		keys["target"] = param.strip_edges()
		_key_changed(io, "target", keys["target"])
		io.report_state(self, "target", keys["target"])
		return true
	return false
