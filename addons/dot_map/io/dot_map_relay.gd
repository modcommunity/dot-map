class_name DotMapRelay
extends DotMapEntity

## logic_relay: Trigger fires OnTrigger (once only with spawnflag 1); CancelPending drops the
## delayed outputs it queued, which a timed sequence uses to restart.

var _spent := false


func _input(io: DotMapIO, name: String, _param: String, activator: Variant, _caller: Variant) -> bool:
	match name:
		"trigger":
			if enabled and not _spent:
				fire(io, "OnTrigger", activator)
				_spent = has_spawnflag(1)
			return true
		"cancelpending":
			io.cancel_pending(self)
			return true
	return false


func on_map_spawn(io: DotMapIO) -> void:
	fire(io, "OnSpawn", null)


func state() -> Dictionary:
	var s := super.state()
	s["spent"] = _spent
	return s
