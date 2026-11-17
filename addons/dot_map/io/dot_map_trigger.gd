class_name DotMapTrigger
extends DotMapEntity

## trigger_multiple and trigger_once as logic: a body entering fires OnStartTouch, then OnTrigger when
## enabled, then waits [code]wait[/code] seconds (once: never again). A body that stays in fires OnTrigger
## again each time the wait is over.

var _blocked_until := 0
var _wait := 1.0
var _touching: Dictionary = {}


func _configure() -> void:
	_wait = key_float("wait", 1.0)


## A body touched the trigger: OnStartTouch and OnTrigger, then the wait.
func touch(io: RefCounted, activator: Variant) -> void:
	if not enabled:
		return
	fire(io, "OnStartTouch", activator)
	_activate(io, activator)


func end_touch(io: RefCounted, activator: Variant) -> void:
	if enabled:
		fire(io, "OnEndTouch", activator)


func body_enter(io: RefCounted, info: Dictionary) -> void:
	if not enabled:
		return
	if _touching.is_empty():
		fire(io, "OnStartTouchAll", info.get("body"))
	_touching[info["id"]] = info
	touch(io, info.get("body"))


func body_leave(io: RefCounted, info: Dictionary) -> void:
	if not _touching.has(info["id"]):
		return
	_touching.erase(info["id"])
	end_touch(io, info.get("body"))
	if _touching.is_empty():
		fire(io, "OnEndTouchAll", info.get("body"))


func body_inside(io: RefCounted, info: Dictionary) -> void:
	if enabled and alive:
		_activate(io, info.get("body"))


func _enabled_changed(_io: RefCounted, on: bool) -> void:
	if not on:
		_touching.clear()


func _activate(io: RefCounted, activator: Variant) -> void:
	if io.now < _blocked_until:
		return
	fire(io, "OnTrigger", activator)
	if classname.to_lower() == "trigger_once":
		io.kill(self)
	elif _wait > 0.0:
		_blocked_until = io.now + io.ticks_for(_wait)
	io.report_state(self, "triggered", io.now)


func _input(io: RefCounted, name: String, _param: String, activator: Variant, _caller: Variant) -> bool:
	if name == "touch":
		touch(io, activator)
		return true
	return false
