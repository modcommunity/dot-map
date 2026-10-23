class_name DotMapScript
extends DotMapEntity

## lua_run: the map's script text is never read here. The converter matched the snippet against its
## templates and wrote [code]script: {status, ops}[/code] into the record; RunCode replays those
## operations as events, each re-checked against [constant OPS]. Anything else is counted and logged.

## Operation name to its arguments: a [code][min, max][/code] range or an Array of allowed strings.
const OPS := {
	"set_player_speed": {"kind": ["run", "walk"], "value": [1.0, 5000.0]},
	"kill_players": {},
	"cleanup_map": {"delay": [0.0, 60.0]},
}


## True when [param op] is a whitelisted operation with every argument in range.
static func valid_op(op: Variant) -> bool:
	if not op is Dictionary:
		return false
	var d: Dictionary = op
	var spec: Variant = OPS.get(str(d.get("op", "")))
	if not spec is Dictionary:
		return false
	var s: Dictionary = spec
	if d.size() != s.size() + 1:
		return false
	for k: String in s:
		if not d.has(k):
			return false
		var rule: Array = s[k]
		var v: Variant = d[k]
		if rule[0] is String:
			if not (v is String and rule.has(v)):
				return false
		elif not ((v is float or v is int) and float(v) >= float(rule[0]) and float(v) <= float(rule[1])):
			return false
	return true


func _input(io: DotMapIO, name: String, _param: String, _activator: Variant, _caller: Variant) -> bool:
	if name != "runcode":
		return false
	io.run_script(self)
	return true
