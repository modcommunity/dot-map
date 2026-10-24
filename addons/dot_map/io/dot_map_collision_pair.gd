class_name DotMapCollisionPair
extends DotMapEntity

## logic_collision_pair: stops two named entities colliding with each other (it starts doing so unless StartDisabled is 0).
## Bodies are the game's, so each change is told as a [code]collision_pair[/code] event: [code]collide[/code] false means
## the pair must pass through each other.

var collide := false


func _configure() -> void:
	collide = key_float("startdisabled", 1.0) == 0.0


func on_map_spawn(io: DotMapIO) -> void:
	_tell(io)


func _input(io: DotMapIO, name: String, _param: String, _activator: Variant, _caller: Variant) -> bool:
	match name:
		"enablecollisions":
			collide = true
		"disablecollisions":
			collide = false
		_:
			return false
	_tell(io)
	return true


func _tell(io: DotMapIO) -> void:
	io.event("collision_pair", {"entity": index, "a": key("attach1"), "b": key("attach2"), "collide": collide})
