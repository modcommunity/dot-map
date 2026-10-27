class_name DotMapSupport
extends StaticBody3D

## A breakable that holds something up (the importer's `holds` on a manifest breakable): a frame, a pillar or a ledge
## with a barrel on it. It is a box on the layer the game's loose bodies rest on and people walk through, so the
## server needs no world to have it; shoot it until [member health] runs out and it is gone, and [signal broken] says
## which loose bodies stood on it ([member holds]) so the game can wake them: they fall, and a barrel rolls.
##
## Server decides, clients follow, as [DotMapGlass]: [method hurt] does nothing unless [member authoritative]; the host
## tells clients with [method apply_broken] (the [member index] is the id on the wire).

## [param held] are the loose bodies that stood on it (the indexes in [member holds]); [param at] the hit point.
signal broken(held: PackedInt32Array, at: Vector3)
signal damaged(remaining: float)

var index: int = -1
var health: float = 20.0
var authoritative: bool = true
## The loose bodies resting on it, as indexes into the game's list of them.
var holds: PackedInt32Array = PackedInt32Array()
## The brush model it replaces on screen, hidden when it breaks; the drawn world's node, set by the game.
var model: int = -1
var visual: Node3D = null

## The box it fills (metres, world axes).
var box := AABB()

var _broken := false


## Supports for each record of [param records]: [code]{bounds: [x0,y0,z0,x1,y1,z1], health, holds, model}[/code] (metres,
## Godot axes; a manifest breakable with `holds`, or the game document's copy). [param hold_offset] is added to every
## `holds` index. The bodies sit on [param layer] and collide with nothing.
static func build_all(records: Array, layer: int, is_authoritative: bool, hold_offset: int = 0) -> Array[DotMapSupport]:
	var out: Array[DotMapSupport] = []
	for raw: Variant in records:
		var rec: Dictionary = raw
		var b: Array = rec.get("bounds", [])
		if b.size() != 6:
			continue
		var s := DotMapSupport.new()
		s.name = "Support%d" % out.size()
		s.index = out.size()
		s.health = maxf(float(rec.get("health", 20.0)), 1.0)
		s.authoritative = is_authoritative
		s.model = int(rec.get("model", -1))
		for h: Variant in rec.get("holds", []):
			s.holds.append(int(h) + hold_offset)
		s.collision_layer = layer
		s.collision_mask = 0
		var lo := Vector3(b[0], b[1], b[2])
		var size := Vector3(b[3], b[4], b[5]) - lo
		var shape := BoxShape3D.new()
		shape.size = size.max(Vector3.ONE * 0.05)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		s.add_child(cs)
		s.position = lo + size * 0.5
		s.box = AABB(lo, size)
		out.append(s)
	return out


func is_broken() -> bool:
	return _broken


## Damage from the game's hit scan. Returns true when it broke. A client's call does nothing.
func hurt(amount: float, at: Vector3 = Vector3.ZERO) -> bool:
	if not authoritative or _broken or amount <= 0.0:
		return false
	health -= amount
	if health > 0.0:
		damaged.emit(health)
		return false
	_go(at)
	return true


## The host said it broke.
func apply_broken(at: Vector3 = Vector3.ZERO) -> void:
	if not _broken:
		_go(at)


func _go(at: Vector3) -> void:
	_broken = true
	health = 0.0
	collision_layer = 0
	if visual != null and is_instance_valid(visual):
		visual.visible = false
	broken.emit(holds, at)


## The nearest intact support one of [param supports] lies on along [param from] and [param direction] ([param reach]
## metres), hurt by [param amount]; the index of it, or -1.
## [param wall_distance] (the distance to the first wall, or INF) keeps a shot behind a wall out.
static func shoot(supports: Array, from: Vector3, direction: Vector3, reach: float, amount: float, wall_distance: float = INF) -> int:
	var best: DotMapSupport = null
	var best_t := minf(reach, wall_distance)
	for s: DotMapSupport in supports:
		if s._broken:
			continue
		var t := 0.0
		if not s.box.has_point(from):
			var hit: Variant = s.box.intersects_ray(from, direction)
			if hit == null:
				continue
			t = from.distance_to(hit as Vector3)
		if t < best_t:
			best_t = t
			best = s
	if best == null:
		return -1
	var _broke := best.hurt(amount, from + direction * best_t)
	return best.index
