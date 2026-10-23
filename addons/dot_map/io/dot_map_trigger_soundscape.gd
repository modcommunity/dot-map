class_name DotMapTriggerSoundscape
extends DotMapEntity

## trigger_soundscape: a body that enters the volume hears the [code]env_soundscape_triggerable[/code]
## its [code]soundscape[/code] key names, wherever it stands, until it leaves. [DotMapVolumes] then reports
## the change through the usual [code]soundscape[/code] event.


func body_enter(io: DotMapIO, info: Dictionary) -> void:
	if enabled:
		_listen(io, info, true)


func body_leave(io: DotMapIO, info: Dictionary) -> void:
	_listen(io, info, false)


func _enabled_changed(_io: DotMapIO, on: bool) -> void:
	if not on:
		for e: DotMapEntity in _targets(_io):
			(e as DotMapSoundscape).listeners.clear()


func _targets(io: DotMapIO) -> Array:
	var out: Array = []
	for e: DotMapEntity in io.find(key("soundscape")):
		if e is DotMapSoundscape:
			out.append(e)
	return out


func _listen(io: DotMapIO, info: Dictionary, on: bool) -> void:
	for e: DotMapSoundscape in _targets(io):
		if on:
			e.listeners[info["id"]] = true
		else:
			e.listeners.erase(info["id"])
