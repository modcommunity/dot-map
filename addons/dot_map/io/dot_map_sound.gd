class_name DotMapSound
extends DotMapEntity

## ambient_generic: PlaySound, StopSound, ToggleSound, Volume, Pitch and the fades, played through
## [member DotMapIO.effect_fn] as [code]("sound", entity, on)[/code]. What plays is [member stand_in],
## the free replacement the converter's sound rules chose ([method DotMapIO.attach_sounds]); a
## sound with none stays silent, because music and voices are never replaced.

## Id of the free stand-in, or empty.
var stand_in := ""
## Source sound path the map named (not played).
var source := ""
var playing := false
var volume := 1.0
var pitch := 100.0
var radius := 0.0
var everywhere := false
var looped := true


func _configure() -> void:
	source = key("message")
	volume = key_float("health", 10.0) / 10.0
	pitch = key_float("pitch", 100.0)
	radius = key_float("radius", 0.0)
	everywhere = has_spawnflag(1)
	looped = not has_spawnflag(32)
	playing = not has_spawnflag(16)


func on_map_spawn(io: DotMapIO) -> void:
	if playing:
		_play(io, true)


func _play(io: DotMapIO, on: bool) -> void:
	playing = on
	if stand_in.is_empty():
		io.missing_callables["sound.silent"] = int(io.missing_callables.get("sound.silent", 0)) + 1
		return
	io.effect("sound", self, on)
	io.report_state(self, "playing", on)


func _input(io: DotMapIO, name: String, param: String, _activator: Variant, _caller: Variant) -> bool:
	match name:
		"playsound":
			_play(io, true)
		"stopsound":
			_play(io, false)
		"togglesound":
			_play(io, not playing)
		"volume":
			volume = clampf(param.to_float() / 10.0, 0.0, 1.0)
			io.report_state(self, "volume", volume)
		"pitch":
			pitch = clampf(param.to_float(), 1.0, 255.0)
			io.report_state(self, "pitch", pitch)
		"fadein", "fadeout":
			io.event("sound_fade", {"entity": index, "name": targetname, "in": name == "fadein", "seconds": param.to_float()})
		_:
			return false
	return true


func state() -> Dictionary:
	var s := super.state()
	s["playing"] = playing
	s["volume"] = volume
	s["pitch"] = pitch
	return s
