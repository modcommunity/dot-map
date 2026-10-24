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
## Starting pitch and volume for a spin-up or fade-in, and the fade and spin times in seconds (0 = none).
var pitch_start := 0.0
var volume_start := 0.0
var fade_in := 0.0
var fade_out := 0.0
var spin_up := 0.0
var spin_down := 0.0


func _configure() -> void:
	source = key("message")
	volume = key_float("health", 10.0) / 10.0
	pitch = key_float("pitch", 100.0)
	radius = key_float("radius", 0.0)
	everywhere = has_spawnflag(1)
	looped = not has_spawnflag(32)
	playing = not has_spawnflag(16)
	pitch_start = key_float("pitchstart", pitch)
	volume_start = key_float("volstart", 0.0) / 10.0
	fade_in = key_float("fadeinsecs")
	fade_out = key_float("fadeoutsecs")
	spin_up = key_float("spinup")
	spin_down = key_float("spindown")


func on_map_spawn(io: DotMapIO) -> void:
	if playing:
		_play(io, true)


func _play(io: DotMapIO, on: bool) -> void:
	playing = on
	if stand_in.is_empty():
		io.missing_callables["sound.silent"] = int(io.missing_callables.get("sound.silent", 0)) + 1
		return
	io.effect("sound", self, on)
	var secs := fade_in if on else fade_out
	if secs > 0.0:
		io.event("sound_fade", {"entity": index, "name": targetname, "in": on, "seconds": secs, "from": volume_start if on else volume, "to": volume if on else 0.0})
	if on and spin_up > 0.0:
		io.event("sound_spin", {"entity": index, "name": targetname, "seconds": spin_up, "from": pitch_start, "to": pitch})
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
