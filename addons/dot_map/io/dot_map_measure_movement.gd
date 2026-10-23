class_name DotMapMeasureMovement
extends DotMapEntity

## logic_measure_movement: copies one entity's movement onto another. The runtime holds no
## positions, so it keeps the four names (which inputs can change) and tells the game through
## the [code]measure_movement[/code] event whenever the pairing or its enabled state changes.


func on_map_spawn(io: DotMapIO) -> void:
	if enabled:
		_announce(io)


func _input(io: DotMapIO, name: String, param: String, _activator: Variant, _caller: Variant) -> bool:
	var slot := ""
	match name:
		"setmeasurereference":
			slot = "measurereference"
		"setmeasuretarget":
			slot = "measuretarget"
		"settargetreference":
			slot = "targetreference"
		"settargetscale":
			slot = "targetscale"
		_:
			return false
	keys[slot] = param.strip_edges()
	if enabled:
		_announce(io)
	return true


func _enabled_changed(io: DotMapIO, on: bool) -> void:
	io.event("measure_movement", {"entity": index, "on": on, "pairing": pairing()})


func pairing() -> Dictionary:
	return {"measure": key("measuretarget"), "measure_reference": key("measurereference"),
			"target": key("target"), "target_reference": key("targetreference"),
			"scale": key_float("targetscale", 1.0), "position": flag("shouldoutputposition")}


func _announce(io: DotMapIO) -> void:
	io.event("measure_movement", {"entity": index, "on": true, "pairing": pairing()})
