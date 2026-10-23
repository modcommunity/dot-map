class_name DotMapTrigger
extends DotMapEntity

## trigger_multiple and trigger_once as logic: [method touch] fires OnStartTouch and OnTrigger
## when enabled, then waits [code]wait[/code] seconds (once: never again). Where bodies overlap
## the volume is the game's; it calls [method DotMapIO.touch].

var _blocked_until := 0
var _wait := 1.0


func _configure() -> void:
	_wait = key_float("wait", 1.0)


func touch(io: DotMapIO, activator: Variant) -> void:
	if not enabled or io.now < _blocked_until:
		return
	fire(io, "OnStartTouch", activator)
	fire(io, "OnTrigger", activator)
	if classname.to_lower() == "trigger_once":
		io.kill(self)
	elif _wait > 0.0:
		_blocked_until = io.now + io.ticks_for(_wait)
	io.report_state(self, "triggered", io.now)


func end_touch(io: DotMapIO, activator: Variant) -> void:
	if enabled:
		fire(io, "OnEndTouch", activator)


func _input(io: DotMapIO, name: String, _param: String, activator: Variant, _caller: Variant) -> bool:
	if name == "touch":
		touch(io, activator)
		return true
	return false
