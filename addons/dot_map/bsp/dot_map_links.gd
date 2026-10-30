class_name DotMapLinks
extends RefCounted

## The output to input graph between a converted map's entities (a button opens a door, a
## trigger starts a timer). It resolves names; running the inputs is the game's.

var _links: Array = []
var _by_source: Dictionary = {}
var _by_target: Dictionary = {}
var _names: Dictionary = {}


## Builds from the manifest's [code]links[/code] and the entity names it knows
## ([code]{entity index: targetname}[/code]); names are optional and only used by [method named].
static func from_records(records: Array, names: Dictionary = {}) -> DotMapLinks:
	var g := DotMapLinks.new()
	g._links = records
	g._names = names
	for rec: Dictionary in records:
		var ids: Array = []
		for t in rec.get("to", []):
			ids.append(int(t))          # JSON hands numbers back as floats; `in` wants ints
		rec["to"] = ids
		var src := int(rec["from"])
		if not g._by_source.has(src):
			g._by_source[src] = []
		(g._by_source[src] as Array).append(rec)
		for t in rec.get("to", []):
			if not g._by_target.has(int(t)):
				g._by_target[int(t)] = []
			(g._by_target[int(t)] as Array).append(rec)
	return g


## The game-neutral command an input name means: open, close, toggle, lock, unlock, press (a button), enable or disable (a volume
## or logic entity), trigger, or empty for any other input (a game reads [code]input[/code] itself).
static func command_of(input: String) -> StringName:
	match input.to_lower():
		"open", "setpositionopen", "unlockandopen":
			return &"open"
		"close":
			return &"close"
		"toggle", "togglepause":
			return &"toggle"
		"lock":
			return &"lock"
		"unlock":
			return &"unlock"
		"press", "use":
			return &"press"
		"enable", "enablerefire":
			return &"enable"
		"disable":
			return &"disable"
		"trigger", "fire", "fireuser1":
			return &"trigger"
	return &""


## What drives [param entity] as game-neutral commands, by delay:
## [code][{from, from_name, output, command, input, param, delay, times, special}][/code], only the inputs [method command_of] knows.
func commands_for(entity: int) -> Array:
	var out: Array = []
	for rec: Dictionary in driving(entity):
		var cmd := command_of(str(rec["input"]))
		if cmd == &"":
			continue
		out.append({"from": int(rec["from"]), "from_name": str(rec.get("from_name", "")), "output": str(rec["output"]), "command": cmd,
				"input": str(rec["input"]), "param": str(rec.get("param", "")), "delay": float(rec["delay"]),
				"times": int(rec.get("times", -1)), "special": bool(rec.get("special", false))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["delay"]) < float(b["delay"]))
	return out


func size() -> int:
	return _links.size()


## The links an entity's [param output] fires (every output when empty), by delay.
func fired_by(entity: int, output: String = "") -> Array:
	var out: Array = []
	for rec: Dictionary in _by_source.get(entity, []):
		if output.is_empty() or str(rec["output"]) == output:
			out.append(rec)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["delay"]) < float(b["delay"]))
	return out


## The links that drive an entity, optionally only one [param input] ("Open", "Lock").
func driving(entity: int, input: String = "") -> Array:
	var out: Array = []
	for rec: Dictionary in _by_target.get(entity, []):
		if input.is_empty() or str(rec["input"]).to_lower() == input.to_lower():
			out.append(rec)
	return out


## Entity indices whose targetname is [param name], case-insensitively.
func named(name: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i: Variant in _names:
		if str(_names[i]).to_lower() == name.to_lower():
			out.append(int(i))
	out.sort()
	return out


## Links aimed at a name nothing carries (and not a special like [code]!activator[/code]).
func unresolved() -> Array:
	var out: Array = []
	for rec: Dictionary in _links:
		if (rec.get("to", []) as Array).is_empty() and not bool(rec.get("special", false)):
			out.append(rec)
	return out


func describe() -> Dictionary:
	return {"links": _links.size(), "sources": _by_source.size(), "targets": _by_target.size(),
			"unresolved": unresolved().size()}
