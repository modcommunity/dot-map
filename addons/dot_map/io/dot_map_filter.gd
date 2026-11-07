class_name DotMapFilter
extends DotMapEntity

## filter_activator_name, filter_activator_class, filter_activator_team, filter_damage_type and filter_multi.
## [method passes] answers for one body or hit described by an info dictionary ([code]name[/code], [code]class[/code],
## [code]team[/code], [code]damage_type[/code]); [code]TestActivator[/code] asks the same of an input's activator and
## fires [code]OnPass[/code] or [code]OnFail[/code]. A key the host's info does not carry admits everyone and is counted
## in [member DotMapIO.unhandled] as [code]filter|<class>[/code], so a missing answer is visible, never a silent block.

const MAX_DEPTH := 4


func _input(io: DotMapIO, name: String, _param: String, activator: Variant, _caller: Variant) -> bool:
	if name != "testactivator":
		return false
	var info: Dictionary = activator if activator is Dictionary else {"name": str(activator) if activator != null else ""}
	fire(io, "OnPass" if passes(io, info) else "OnFail", activator)
	return true


## True when [param info] passes this filter; [code]negated[/code] flips the answer.
func passes(io: DotMapIO, info: Dictionary, depth: int = 0) -> bool:
	var match_: bool
	match classname.to_lower():
		"filter_activator_name":
			match_ = str(info.get("name", "")).matchn(key("filtername"))
		"filter_activator_class":
			match_ = str(info.get("class", "")).matchn(key("filterclass"))
		"filter_activator_team":
			if not info.has("team"):
				return _admit_unknown(io)
			match_ = int(info["team"]) == int(key("filterteam"))
		"filter_damage_type":
			if not info.has("damage_type"):
				return _admit_unknown(io)
			match_ = int(info["damage_type"]) == int(key("damagetype"))
		"filter_multi":
			var any := key("filtertype") == "1"
			match_ = not any
			if depth < MAX_DEPTH:
				for i in range(1, 21):
					var nm := key("filter%02d" % i)
					if nm.is_empty():
						continue
					var sub := io.find(nm)
					if sub.is_empty():
						continue
					var ok := entity_passes(io, sub[0], info, depth + 1)
					if any and ok:
						match_ = true
						break
					if not any and not ok:
						match_ = false
						break
		_:
			return _admit_unknown(io)
	return match_ != flag("negated")


func _admit_unknown(io: DotMapIO) -> bool:
	var k := "filter|" + classname.to_lower()
	io.unhandled[k] = int(io.unhandled.get(k, 0)) + 1
	return true


## Any filter entity against [param info]: a [DotMapFilter] answers, another class admits everyone and is counted.
static func entity_passes(io: DotMapIO, f: DotMapEntity, info: Dictionary, depth: int = 0) -> bool:
	if f is DotMapFilter:
		return (f as DotMapFilter).passes(io, info, depth)
	var k := "filter|" + f.classname.to_lower()
	io.unhandled[k] = int(io.unhandled.get(k, 0)) + 1
	return true
