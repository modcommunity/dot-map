class_name DotMapBeats
extends DotMapEntity

## logic_beats: a map's music-beat cue as a plain beat signal, so no track has to ship. With a tempo it fires OnBeat and the
## [code]beat[/code] event on the map's own tick (bar, beat in the bar, downbeat); without one it is silent. The tempo comes
## from the key [code]bpm[/code], the input SetBPM or [member default_bpm]. [member announcer_off] is the map's DisableAnnoucner
## (that key's own spelling) for a game that has a wave announcer.

## Used when the map names no tempo; 0 leaves the beat off.
var default_bpm := 0.0
## The fastest tempo taken; a faster one would re-queue at the same tick and spin the event queue.
const MAX_BPM := 600.0
var beats_per_bar := 4

var _bpm := 0.0
var _gen := 0
var _count := 0


func _configure() -> void:
	_bpm = minf(key_float("bpm", default_bpm), MAX_BPM)
	beats_per_bar = maxi(int(key_float("beatsperbar", float(beats_per_bar))), 1)


func on_map_spawn(io: DotMapIO) -> void:
	_arm(io)


func announcer_off() -> bool:
	return enabled and flag("disableannoucner")


## Seconds between beats, or 0 when the beat is off.
func interval() -> float:
	return 60.0 / _bpm if _bpm > 0.0 else 0.0


func _input(io: DotMapIO, name: String, param: String, activator: Variant, _caller: Variant) -> bool:
	match name:
		"__beat":
			if enabled and param == str(_gen) and interval() > 0.0:
				_count += 1
				var in_bar := (_count - 1) % beats_per_bar
				io.event("beat", {"entity": index, "beat": _count, "bar": (_count - 1) / beats_per_bar, "in_bar": in_bar,
						"downbeat": in_bar == 0, "bpm": _bpm})
				fire(io, "OnBeat", activator, str(_count))
				io.schedule_self(self, "__beat", str(_gen), interval())
			return true
		"setbpm":
			_bpm = clampf(param.to_float(), 0.0, MAX_BPM)
			_arm(io)
			return true
		"start":
			_arm(io)
			return true
		"stop":
			_gen += 1
			return true
	return false


func _enabled_changed(io: DotMapIO, on: bool) -> void:
	if on:
		_arm(io)
	else:
		_gen += 1


func _arm(io: DotMapIO) -> void:
	_gen += 1
	_count = 0
	if enabled and interval() > 0.0:
		io.schedule_self(self, "__beat", str(_gen), interval())
