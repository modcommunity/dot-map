class_name DotMapGlobal
extends DotMapEntity

## env_global: a named on/off flag with a counter, shared through [member DotMapIO.globals] by every
## entity that names the same globalstate. The map reads it back with the counter outputs.


func on_map_spawn(io: DotMapIO) -> void:
	var g := _state(io)
	if not g.get("init", false):
		g["init"] = true
		g["on"] = key_float("initialstate") != 0.0
		g["counter"] = int(key_float("counter"))


func _state(io: DotMapIO) -> Dictionary:
	var name := key("globalstate", targetname)
	if not io.globals.has(name):
		io.globals[name] = {"on": false, "counter": 0}
	return io.globals[name]


func _input(io: DotMapIO, name: String, param: String, activator: Variant, _caller: Variant) -> bool:
	var g := _state(io)
	match name:
		"turnon":
			g["on"] = true
		"turnoff":
			g["on"] = false
		"toggle":
			g["on"] = not g["on"]
		"remove":
			io.globals.erase(key("globalstate", targetname))
			return true
		"setcounter":
			g["counter"] = int(param.to_float())
			fire(io, "OutCounter", activator, str(g["counter"]))
		"addtocounter":
			g["counter"] = int(g["counter"]) + int(param.to_float())
			fire(io, "OutCounter", activator, str(g["counter"]))
		"getcounter":
			fire(io, "OnGetCounter", activator, str(g["counter"]))
			return true
		_:
			return false
	io.report_state(self, "global", g.duplicate())
	return true
