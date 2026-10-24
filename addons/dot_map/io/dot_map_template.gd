class_name DotMapTemplate
extends DotMapEntity

## point_template: ForceSpawn makes a copy of each named template entity (Template01..16) and fires
## OnEntitySpawned for the set. The copies keep their names (preserve-names, spawnflag 2) or take a
## numbered suffix; the game places geometry from the [code]template_spawn[/code] event ([code]maker[/code] is the entity that asked, -1 when an output did: a maker puts the copies at itself).

var _copies := 0


func _input(io: DotMapIO, name: String, _param: String, activator: Variant, caller: Variant) -> bool:
	var maker: int = (caller as DotMapEntity).index if caller is DotMapEntity else -1
	match name:
		"forcespawn":
			_spawn(io, _names(), activator, maker)
		"forcespawnrandomtemplate":
			var names := _names()
			if not names.is_empty():
				_spawn(io, [names[io.stream_for(self).next_range_i(0, names.size() - 1)]], activator, maker)
			return true
		_:
			return false
	return true


func _names() -> Array:
	var out := []
	for i in range(1, 17):
		var n := key("template%02d" % i)
		if not n.is_empty():
			out.append(n)
	return out


func _spawn(io: DotMapIO, names: Array, activator: Variant, maker: int) -> void:
	_copies += 1
	var keep := has_spawnflag(2)
	for n: String in names:
		for src: DotMapEntity in io.find(n):
			var rec := src.record.duplicate(true)
			if not keep and not src.targetname.is_empty():
				rec["targetname"] = "%s&%04d" % [src.targetname, _copies]
			var e := io.spawn_record(rec)
			io.event("template_spawn", {"template": index, "source": src.index, "entity": e.index, "maker": maker})
	fire(io, "OnEntitySpawned", activator)
