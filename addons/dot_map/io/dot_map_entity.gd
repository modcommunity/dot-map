class_name DotMapEntity
extends RefCounted

## One entity of the map's input/output runtime: a name, its keys, its output links and the inputs
## every class has. A class with more behaviour extends this and overrides [method _input].

var index := -1
var classname := ""
var targetname := ""
var parentname := ""
## Lower-cased key to its last written value; output keys are not here, they are [member links].
var keys: Dictionary = {}
## Outputs as written: [code]{output (lower case), target, input, param, delay, times}[/code].
var links: Array = []
var enabled := true
var alive := true
var color := ""
## The record this was built from, so a template can make a copy.
var record: Dictionary = {}


## Fills from one entity record of the source document ([code]pairs[/code] and [code]outputs[/code]).
func load_record(rec: Dictionary) -> void:
	record = rec
	index = int(rec.get("index", -1))
	classname = str(rec.get("classname", ""))
	targetname = str(rec.get("targetname", ""))
	parentname = str(rec.get("parentname", ""))
	var out_names := {}
	links = []
	for o: Variant in rec.get("outputs", []):
		var od: Dictionary = o
		out_names[str(od["output"]).to_lower()] = true
		links.append({"output": str(od["output"]).to_lower(), "target": str(od["target"]),
				"input": str(od["input"]), "param": str(od.get("param", "")),
				"delay": float(od.get("delay", 0.0)), "times": int(od.get("times", -1))})
	keys = {}
	for p: Variant in rec.get("pairs", []):
		var k := str((p as Array)[0]).to_lower()
		if not out_names.has(k):
			keys[k] = str((p as Array)[1])
	enabled = not flag("startdisabled")
	_configure()


## A key's value, or [param default] when the entity does not have it.
func key(name: String, default: String = "") -> String:
	return str(keys.get(name.to_lower(), default))


## True for a key written as a non-zero number.
func flag(name: String) -> bool:
	return key(name, "0").to_float() != 0.0


func key_float(name: String, default: float = 0.0) -> float:
	var v := key(name)
	return default if v.is_empty() else v.to_float()


func has_spawnflag(bit: int) -> bool:
	return (int(key("spawnflags", "0").to_float()) & bit) != 0


## Runs one input. Returns false when this class has no such input, so the runtime can count it.
func accept(io: DotMapIO, input: String, param: String, activator: Variant, caller: Variant) -> bool:
	if not alive:
		return false
	var name := input.to_lower()
	if _input(io, name, param, activator, caller):
		return true
	match name:
		"kill":
			io.kill(self)
		"killhierarchy":
			io.kill_hierarchy(self)
		"addoutput":
			add_output(io, param)
		"fireuser1", "fireuser2", "fireuser3", "fireuser4":
			fire(io, "OnUser" + name.right(1), activator)
		"enable", "turnon":
			set_enabled(io, true)
		"disable", "turnoff":
			set_enabled(io, false)
		"toggle":
			set_enabled(io, not enabled)
		"color":
			color = param.strip_edges()
			io.report_state(self, "color", color)
		_:
			return false
	return true


## Fires an output: queues every link of that name on the runtime.
func fire(io: DotMapIO, output: String, activator: Variant, param: String = "") -> int:
	return io.fire(self, output, activator, param)


func set_enabled(io: DotMapIO, on: bool) -> void:
	if enabled == on:
		return
	enabled = on
	_enabled_changed(io, on)
	io.report_state(self, "enabled", on)


## [code]AddOutput[/code]: "key value" sets a key, "OnX target:input:param:delay:times" adds a link.
func add_output(io: DotMapIO, param: String) -> void:
	var text := param.strip_edges()
	var sp := text.find(" ")
	if sp < 0:
		return
	var k := text.substr(0, sp)
	var v := text.substr(sp + 1).strip_edges()
	if k.to_lower().begins_with("on") and (v.count(":") >= 4 or v.count(",") >= 4):
		var f := v.split(":" if v.count(":") >= 4 else ",")
		links.append({"output": k.to_lower(), "target": f[0], "input": f[1], "param": f[2],
				"delay": f[3].to_float(), "times": int(f[4].to_float())})
		return
	keys[k.to_lower()] = v
	if k.to_lower() == "targetname":
		io.rename(self, v)
	else:
		_key_changed(io, k.to_lower(), v)


## Called once the keys are read.
func _configure() -> void:
	pass


## A class's own inputs (lower-cased name); return true when handled.
func _input(_io: DotMapIO, _name: String, _param: String, _activator: Variant, _caller: Variant) -> bool:
	return false


## Called at map start, after every entity is built.
func on_map_spawn(_io: DotMapIO) -> void:
	pass


func _enabled_changed(_io: DotMapIO, _on: bool) -> void:
	pass


func _key_changed(_io: DotMapIO, _name: String, _value: String) -> void:
	pass


## Per-entity state a client would need; logic classes add their own values.
func state() -> Dictionary:
	return {"enabled": enabled, "alive": alive, "color": color}


func describe() -> Dictionary:
	return {"index": index, "classname": classname, "targetname": targetname, "links": links.size(),
			"enabled": enabled, "alive": alive}
