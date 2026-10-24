class_name DotMapWinLose
extends DotMapEntity

## logic_winlose: a map's own ending. Win and Lose ask the game to decide the round with the [code]round_decide[/code] event;
## [method decided] (the game calls it once the round is decided, by this entity or anything else) fires OnWin or OnLose and
## tells the game how to dress the ending with [code]round_end[/code]: a time scale and how long it lasts, and a camera point.
## No music plays. The slow motion and camera come from [member slowmo_scale], [member slowmo_seconds] and the keys
## [code]slowmo[/code], [code]slowmoseconds[/code]; a scale of 1 means none, the camera is the entity's origin when it has one.

var slowmo_scale := 1.0
var slowmo_seconds := 2.0
## The longest slow motion taken, so a stray key cannot leave a game crawling.
const MAX_SECONDS := 15.0

var _scale := 1.0
var _seconds := 2.0


func _configure() -> void:
	_scale = clampf(key_float("slowmo", slowmo_scale), 0.05, 1.0)
	_seconds = clampf(key_float("slowmoseconds", slowmo_seconds), 0.0, MAX_SECONDS)


func _input(io: DotMapIO, name: String, _param: String, _activator: Variant, _caller: Variant) -> bool:
	match name:
		"win", "humanswin":
			io.event("round_decide", {"entity": index, "won": true, "why": "the map ended it"})
		"lose", "zombieswin", "humanslose":
			io.event("round_decide", {"entity": index, "won": false, "why": "the map ended it"})
		_:
			return false
	return true


func decided(io: DotMapIO, won: bool) -> void:
	fire(io, "OnWin" if won else "OnLose", null)
	var camera: Variant = null
	if key("origin") != "":
		camera = origin(io)
	io.event("round_end", {"entity": index, "won": won, "time_scale": _scale, "seconds": _seconds, "camera": camera})
