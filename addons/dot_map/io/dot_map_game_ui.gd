class_name DotMapGameUi
extends DotMapEntity

## game_ui: Activate hands one player's controls to the map.

const BUTTONS := {"forward": "Forward", "back": "Back", "left": "MoveLeft", "right": "MoveRight", "attack": "Attack", "attack2": "Attack2"}
const FREEZE := 32
const HIDE_WEAPON := 64
const USE_DEACTIVATES := 128
const JUMP_DEACTIVATES := 256

## Who holds the controls: whatever the game passed as the activator, or null.
var player: Variant = null
var active := false
var _held := {}
var _axes := Vector2.ZERO


func _input(io: DotMapIO, name: String, _param: String, activator: Variant, _caller: Variant) -> bool:
	match name:
		"activate":
			if enabled and not active:
				active = true
				player = activator
				_held = {}
				_axes = Vector2.ZERO
				io.event("ui_active", {"entity": index, "on": true, "player": player, "freeze": has_spawnflag(FREEZE), "hide_weapon": has_spawnflag(HIDE_WEAPON)})
				fire(io, "PlayerOn", player)
		"deactivate":
			release(io)
		_:
			return false
	return true


## The buttons the holder has down now (names in [constant BUTTONS], plus [code]use[/code] and [code]jump[/code]); call each tick.
func feed(io: DotMapIO, held: Dictionary) -> void:
	if not active:
		return
	if (bool(held.get("use", false)) and has_spawnflag(USE_DEACTIVATES)) or (bool(held.get("jump", false)) and has_spawnflag(JUMP_DEACTIVATES)):
		release(io)
		return
	for b: String in BUTTONS:
		var now := bool(held.get(b, false))
		if now != bool(_held.get(b, false)):
			_held[b] = now
			fire(io, ("Pressed" if now else "Unpressed") + BUTTONS[b], player)
	var axes := Vector2(float(bool(held.get("right", false))) - float(bool(held.get("left", false))),
			float(bool(held.get("forward", false))) - float(bool(held.get("back", false))))
	if axes.x != _axes.x:
		fire(io, "XAxis", player, str(axes.x))
	if axes.y != _axes.y:
		fire(io, "YAxis", player, str(axes.y))
	_axes = axes


func release(io: DotMapIO) -> void:
	if not active:
		return
	active = false
	io.event("ui_active", {"entity": index, "on": false, "player": player, "freeze": false, "hide_weapon": false})
	fire(io, "PlayerOff", player)
	player = null
