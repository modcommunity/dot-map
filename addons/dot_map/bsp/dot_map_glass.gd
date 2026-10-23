class_name DotMapGlass
extends StaticBody3D

## A breakable glass brush entity from a converted map: solid until its health runs out, then
## gone with a burst of shards. Built by [method DotMapBspMesh.build_breakables].
##
## [b]Server decides, clients follow.[/b] [method hurt] does nothing unless [member authoritative];
## the host tells clients with [method apply_broken] (the entity [member model] is the id), and a
## joiner is told the same for every pane already broken. Both ends emit [signal broken], which
## is where a game plays a sound or spawns its own effect; damage itself is the game's (wire
## [code]DotCombat[/code] or a hit scan to [method hurt]), so this needs nothing but dot-core.

## Health reached zero (or [method apply_broken] came from the host). [param at] is the hit point.
signal broken(at: Vector3, by: StringName)
## A pane took damage and survived.
signal damaged(remaining: float, by: StringName)

## The kind, a generic id of the converter's table (glass, glass_frosted).
@export var kind: StringName = &"glass"
@export var health: float = 1.0
## Whether this end decides breakage; false on a client.
@export var authoritative: bool = true
## Shards in the burst; 0 for none.
@export var shard_count: int = 16
## Played at the break point when set.
@export var break_sound: AudioStream = null

## The brush entity's model number in the map, the same on every peer.
var model: int = -1
## What is hidden when this breaks: the model's drawn node.
var visual: Node3D = null
## Material of the shards; the converter's glass look when null.
var shard_material: Material = null

var _broken := false


func is_broken() -> bool:
	return _broken


## Takes [param amount] off health on the authoritative end; breaks at zero. Returns whether it broke.
func hurt(amount: float, at: Vector3 = Vector3.ZERO, by: StringName = &"") -> bool:
	if _broken or not authoritative or amount <= 0.0:
		return false
	health -= amount
	if health > 0.0:
		damaged.emit(health, by)
		return false
	_shatter(at if at != Vector3.ZERO else global_position, by)
	return true


## Breaks it outright without checking authority: the host's word, or a map's own trigger.
func apply_broken(at: Vector3 = Vector3.ZERO, by: StringName = &"") -> void:
	if not _broken:
		_shatter(at if at != Vector3.ZERO else global_position, by)


func _shatter(at: Vector3, by: StringName) -> void:
	_broken = true
	health = 0.0
	set_deferred(&"collision_layer", 0)
	set_deferred(&"collision_mask", 0)
	if visual != null:
		visual.visible = false
	if is_inside_tree():
		_burst(at)
	broken.emit(at, by)


func _burst(at: Vector3) -> void:
	if shard_count > 0:
		var p := CPUParticles3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(0.07, 0.07)
		quad.material = shard_material if shard_material != null else DotMapBspMesh.glass_material(kind)
		p.mesh = quad
		p.amount = shard_count
		p.one_shot = true
		p.explosiveness = 1.0
		p.lifetime = 1.4
		p.direction = Vector3.DOWN
		p.spread = 70.0
		p.initial_velocity_min = 0.6
		p.initial_velocity_max = 2.5
		p.gravity = Vector3(0, -9.8, 0)
		p.angular_velocity_min = -360.0
		p.angular_velocity_max = 360.0
		p.emitting = true
		get_parent().add_child(p)
		p.global_position = at
		get_tree().create_timer(p.lifetime + 0.5).timeout.connect(p.queue_free)
	if break_sound != null:
		var a := AudioStreamPlayer3D.new()
		a.stream = break_sound
		get_parent().add_child(a)
		a.global_position = at
		a.finished.connect(a.queue_free)
		a.play()


func describe() -> Dictionary:
	return {"model": model, "kind": kind, "health": health, "broken": _broken, "authoritative": authoritative}
