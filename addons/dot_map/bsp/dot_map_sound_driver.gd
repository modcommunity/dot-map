class_name DotMapSoundDriver
extends Node
## Drives the players [method DotMapBspMesh.build_sounds] made from a map's [code]sound_fade[/code] and [code]sound_spin[/code] events.

const MAX_SECONDS := 60.0
const MIN_GAIN := 0.001

## The [code]Sounds[/code] node the players live under.
var root: Node = null

var _tweens: Dictionary = {}


## Handles one logic event; returns true when it was a sound event that found a player. Unknown or oversized values are clamped, never trusted.
func handle(kind: String, data: Dictionary) -> bool:
	if kind != "sound_fade" and kind != "sound_spin":
		return false
	var player := _find(int(data.get("entity", -1)), str(data.get("name", "")))
	if player == null:
		return false
	var secs := _finite(data.get("seconds", 0.0), 0.0)
	secs = clampf(secs, 0.0, MAX_SECONDS)
	_prune()
	var key := "%d:%s" % [player.get_instance_id(), kind]
	if _tweens.has(key) and (_tweens[key] as Tween) != null and (_tweens[key] as Tween).is_valid():
		(_tweens[key] as Tween).kill()
	if kind == "sound_fade":
		var scale := float(player.get_meta(&"dot_map_gain_scale", 1.0))
		var from := _gain(_finite(data.get("from", 1.0), 1.0), scale)
		var to := _gain(_finite(data.get("to", 1.0), 1.0), scale)
		player.set("volume_db", linear_to_db(from))
		_tween(key, player, "volume_db", linear_to_db(to), secs)
	else:
		var from_p := _pitch(_finite(data.get("from", 100.0), 100.0))
		player.set("pitch_scale", from_p)
		_tween(key, player, "pitch_scale", _pitch(_finite(data.get("to", 100.0), 100.0)), secs)
	return true


func _tween(key: String, player: Node, prop: String, to: Variant, secs: float) -> void:
	if secs <= 0.0 or not player.is_inside_tree():
		player.set(prop, to)
		return
	var t := player.create_tween()
	t.tween_property(player, prop, to, secs)
	_tweens[key] = t


## A number from event data, [param fallback] when it is NaN or infinite (a malformed event must not reach a tween).
func _finite(v: Variant, fallback: float) -> float:
	var f := float(v)
	return f if is_finite(f) else fallback


## Forgets the tweens of players that were freed or whose tween ended.
func _prune() -> void:
	for key: String in _tweens.keys():
		var t := _tweens[key] as Tween
		var id := int(key.get_slice(":", 0))

		if t == null or not t.is_valid() or not is_instance_id_valid(id):
			_tweens.erase(key)


func _gain(v: float, scale: float) -> float:
	return clampf(v * scale, MIN_GAIN, 4.0)


func _pitch(percent: float) -> float:
	return clampf(percent / 100.0, 0.25, 4.0)


func _find(entity: int, targetname: String) -> Node:
	if root == null:
		return null
	for c in root.get_children():
		if entity >= 0 and int(c.get_meta(&"dot_map_entity", -2)) == entity:
			return c
	if targetname != "":
		return root.get_node_or_null(NodePath(targetname.validate_node_name()))
	return null
