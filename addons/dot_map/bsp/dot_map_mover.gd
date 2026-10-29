class_name DotMapMover
extends RefCounted

## A brush entity that moves, from the converter's mover record: duck-typed data a game animates. It owns no
## node and moves nothing.

const KIND_SLIDE := "slide"
const KIND_BUTTON := "button"
const KIND_HINGE := "rotate"
const KIND_HINGE_BUTTON := "rotate_button"
const KIND_SPIN := "spin"
const KIND_PATH := "path"
const KIND_PLAT := "plat"
const KIND_CONVEYOR := "conveyor"

var record: Dictionary = {}
var entity: int = -1
var model: int = -1
var kind: String = ""
var classname: String = ""
var targetname: String = ""
## Where the model's node goes (metres, Godot axes): the hinge for a rotating door.
var origin: Vector3 = Vector3.ZERO
## Unit direction a slide, button or platform moves along.
var direction: Vector3 = Vector3.ZERO
## Unit axis a hinge or spinner turns about.
var axis: Vector3 = Vector3.UP
## Metres along [member direction] for a full travel.
var distance: float = 0.0
## Degrees about [member axis] for a full hinge travel (negative turns the other way).
var degrees: float = 0.0
## Metres a second for slides, degrees a second for hinges.
var speed: float = 0.0
## Seconds one full travel takes.
var travel_time: float = 0.0
## Seconds it stays open before closing; -1 stays until told to close.
var wait: float = 0.0
var locked: bool = false
var toggle: bool = false
var start_open: bool = false
## A prop_door_rotating's opendir: 0 swings away from whoever opens it, 1 forward only, 2 back only (the sign of [member degrees]).
var open_dir: int = 1
## The yaw (degrees, source angles) whose local +X is the door's front; only [member open_dir] 0 reads it.
var yaw: float = 0.0
## A prop_door_rotating hung off an authored hinge: the yaw (degrees) its panel lies along and its width in metres, NAN and 0 when the model's own origin is the hinge.
var panel_yaw: float = NAN
var panel_width: float = 0.0
## Metres from the hinge to the model's origin along the panel (0 when the origin is the hinge): a real model is placed this far along it.
var panel_offset: float = 0.0
## 1 or -1: the side a door that starts open stands on (spawnpos), 0 for none.
var spawn_side: float = 0.0
var use: bool = false
var touch: bool = false
var solid: bool = true
var outputs: Array = []
## Who drives it: [code][{entity, classname, targetname, output, input, delay}][/code].
var opened_by: Array = []


## Builds from a record of the manifest's [code]movers[/code].
static func from_record(rec: Dictionary) -> DotMapMover:
	var m := DotMapMover.new()
	m.record = rec
	m.entity = int(rec.get("entity", -1))
	m.model = int(rec["model"]) if rec.get("model") != null else -1
	m.kind = str(rec.get("kind", ""))
	m.classname = str(rec.get("classname", ""))
	m.targetname = str(rec.get("targetname", ""))
	m.origin = _vec(rec.get("origin"))
	m.direction = _vec(rec.get("direction"))
	m.axis = _vec(rec.get("axis"), Vector3.UP)
	m.distance = float(rec.get("distance", 0.0))
	m.degrees = float(rec.get("degrees", 0.0))
	m.speed = float(rec.get("speed", 0.0))
	m.travel_time = float(rec.get("travel_time", 0.0))
	m.wait = float(rec.get("wait", 0.0))
	m.locked = bool(rec.get("locked", false))
	m.toggle = bool(rec.get("toggle", false))
	m.start_open = bool(rec.get("start_open", rec.get("start_on", false)))
	m.open_dir = int(rec.get("open_dir", 1))
	m.yaw = float(rec.get("yaw", 0.0))
	m.spawn_side = float(rec.get("spawn_side", 0.0))
	if typeof(rec.get("panel_yaw")) in [TYPE_FLOAT, TYPE_INT]:
		m.panel_yaw = float(rec["panel_yaw"])
		m.panel_width = float(rec.get("panel_width", 0.0))
		m.panel_offset = float(rec.get("panel_offset", 0.0))
	m.use = bool(rec.get("use", false))
	m.touch = bool(rec.get("touch", false))
	m.solid = bool(rec.get("solid", true))
	m.outputs = rec.get("outputs", [])
	m.opened_by = rec.get("opened_by", [])
	return m


static func _vec(v: Variant, fallback := Vector3.ZERO) -> Vector3:
	if v is Array and (v as Array).size() >= 3:
		return Vector3(v[0], v[1], v[2])
	return fallback


## Whether the mover has a travel a game can animate with [method transform_at].
func is_animatable() -> bool:
	return (kind in [KIND_SLIDE, KIND_BUTTON, KIND_PLAT] and distance > 0.0 and direction != Vector3.ZERO) \
			or (kind in [KIND_HINGE, KIND_HINGE_BUTTON] and degrees != 0.0)


## Whether the model turns forever ([constant KIND_SPIN]).
func is_spinner() -> bool:
	return kind == KIND_SPIN


## The side (1 or -1) a door swings to for an opener at [param opener] (map metres): away from
## it. A door with a fixed direction, or no known opener, keeps 1.
func side_away_from(opener: Variant) -> float:
	if open_dir != 0 or not opener is Vector3:
		return 1.0
	var front := Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3.RIGHT
	return 1.0 if (opener as Vector3 - origin).dot(front) >= 0.0 else -1.0


## Where the node's rest pose is along its travel: 1 for a door that starts open, else 0.
func rest_fraction() -> float:
	return 1.0 if start_open else 0.0


## The node's transform relative to the closed pose at [param fraction] (0 closed, 1 fully
## travelled); [param side] (1 or -1) turns a hinge the other way. A hinge turns about the node's own origin, so the node must sit at [member origin].
func transform_at(fraction: float, side: float = 1.0) -> Transform3D:
	var f := clampf(fraction, 0.0, 1.0)
	if kind in [KIND_HINGE, KIND_HINGE_BUTTON]:
		return Transform3D(Basis(axis.normalized(), deg_to_rad(degrees) * f * side), Vector3.ZERO)
	return Transform3D(Basis.IDENTITY, direction * distance * f)


## Radians a second a spinner turns about [member axis].
func spin_rate() -> float:
	return deg_to_rad(float(record.get("degrees_per_second", 0.0)))


## Radians a second squared a spinner speeds up and slows down at; 0 (instant) unless the map sets
## [code]fanfriction[/code]. 20 reaches full speed in a second, 100 in a fifth: an approximation of the engine's friction.
func spin_acceleration() -> float:
	var f := float(record.get("fan_friction", 0.0))
	return absf(spin_rate()) * f / 20.0 if f > 0.0 else 0.0


## Corners of a train's path, [code][{name, at, speed?, wait?}][/code]; empty for others.
func path() -> Array:
	return record.get("path", [])


## The fraction after [param seconds] of travel toward 1 (open) or 0 (closed) from [param from].
func advance(from: float, opening: bool, seconds: float) -> float:
	if travel_time <= 0.0:
		return 1.0 if opening else 0.0
	var step := seconds / travel_time
	return clampf(from + (step if opening else -step), 0.0, 1.0)


func describe() -> Dictionary:
	return {"entity": entity, "model": model, "kind": kind, "name": targetname, "distance": distance,
			"degrees": degrees, "travel_time": travel_time, "wait": wait, "locked": locked}
