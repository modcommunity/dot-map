class_name DotMapSoundscape
extends DotMapEntity

## env_soundscape and its proxy/triggerable variants: a named ambience that a player within
## [member radius] hears. Each step [DotMapVolumes] picks, per player, the nearest enabled
## soundscape that covers it and tells the game through a [code]soundscape[/code] event
## ([code]body, name, entity, positions[/code]) when the choice changes; the game owns the audio.

## Source units; -1 covers the whole map.
var radius := 128.0
var scape := ""
## True for env_soundscape_triggerable, which a player must be told to hear (inputs only).
var triggerable := false
## Body ids a [DotMapTriggerSoundscape] has put inside, which hear a triggerable scape wherever they stand.
var listeners: Dictionary = {}
var _heard := false


func _configure() -> void:
	radius = key_float("radius", 128.0)
	scape = key("soundscape")
	triggerable = classname.to_lower() == "env_soundscape_triggerable"


## The soundscape name the game should play: a proxy uses the one it points at.
func resolved_name(io: DotMapIO) -> String:
	if classname.to_lower() == "env_soundscape_proxy":
		for e: DotMapEntity in io.find(key("mainsoundscapename")):
			if e is DotMapSoundscape:
				return (e as DotMapSoundscape).scape
	return scape


## Named positions (metres) the soundscape's sounds are placed at.
func positions(io: DotMapIO) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var src: DotMapEntity = self
	if classname.to_lower() == "env_soundscape_proxy":
		for e: DotMapEntity in io.find(key("mainsoundscapename")):
			src = e
			break
	for i in 8:
		var nm := src.key("position%d" % i)
		if nm.is_empty():
			continue
		for e: DotMapEntity in io.find(nm):
			out.append(e.origin(io))
			break
	return out


## Whether [param at] (metres) is inside the radius, or body [param id] was put inside by a trigger_soundscape.
func covers(io: DotMapIO, at: Vector3, id: Variant = null) -> bool:
	if triggerable and listeners.has(id):
		return true
	if triggerable and not _heard:
		return false
	return radius < 0.0 or at.distance_to(origin(io)) <= radius * io.unit_scale





func _input(_io: DotMapIO, name: String, _param: String, _activator: Variant, _caller: Variant) -> bool:
	match name:
		"startplay", "play":
			_heard = true
			return true
		"stopplay":
			_heard = false
			return true
	return false
