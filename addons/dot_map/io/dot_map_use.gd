class_name DotMapUse
extends RefCounted

## The press-E path for a converted map's buttons and doors: what the eye is looking at, whether it is in reach, and the press itself.
## A client calls [method aim] each frame for the prompt; the host calls [method press] when a player's use bit rises, so the map's own `OnPressed` and friends run server-side.
## Any other usable thing (a weapon on the floor) can implement [method DotMapUse.usable_info]'s shape and share the same prompt.

const CHANNEL := "map.use"

## Metres from the eye to the surface the player may press.
var reach := 2.2
## Seconds one player must wait before pressing the same thing again (a mashed key presses once).
var cooldown := 0.3
## Physics layers the look ray hits; players are not on the map's layer.
var mask := 1
## Plays a press: [code](kind: StringName, entity: DotMapEntity, at: Vector3)[/code] with kind `press`, `locked` or `toggle`.
var effect_fn := Callable()
## Seconds an extra `button.ogg` click is audible when [member play_sounds] is on; the map's own sounds are the game's.
var play_sounds := true

var _world: DotMapWorld
var _by_model: Dictionary = {}
var _next_ok: Dictionary = {}

const _SPECS := [
	["sv_use_reach", "reach", "float:0.2:20", "Metres within which a button or door can be pressed with the use key"],
	["sv_use_cooldown", "cooldown", "float:0:30", "Seconds before the same player can press the same button again"],
]


func _init(world: DotMapWorld = null) -> void:
	_world = world


## Points this at another world (a game keeps one DotMapUse, and its cvars, across map changes).
func attach(world: DotMapWorld) -> void:
	_world = world
	_by_model.clear()
	_next_ok.clear()


## The prompt a game draws: `{index, label, state, distance, in_range, entity}` for the usable thing the ray from [param from] along [param dir] hits first, or an empty dictionary.
## [param state] is `ready`, `pressed` (a button waiting to come out) or `locked`.
func aim(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3, exclude: Array[RID] = []) -> Dictionary:
	if _world == null or space == null or dir == Vector3.ZERO:
		return {}
	var q := PhysicsRayQueryParameters3D.create(from, from + dir.normalized() * (reach + 4.0), mask)
	q.exclude = exclude
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return {}
	var e := _entity_of(hit["collider"] as Node)
	if e == null:
		return {}
	var state := e.use_state()
	if state == &"":
		return {}
	var d := from.distance_to(hit["position"] as Vector3)
	return {"index": e.index, "entity": e, "state": state, "distance": d, "in_range": d <= reach,
		"label": label_for(e, state), "at": hit["position"]}


## Presses what the ray hits for [param user] (any key; the cooldown is per user and entity). Host only.
## Fails with CODE_INVALID (nothing usable, or out of reach), CODE_STATE (cooling down or already in).
func press(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3, user: Variant, activator: Variant = null,
		exclude: Array[RID] = []) -> DotResult:
	if _world == null or not _world.io.authoritative:
		return DotResult.fail(DotError.CODE_INVALID, "a client runs no logic")
	var info := aim(space, from, dir, exclude)
	if info.is_empty():
		return DotResult.fail(DotError.CODE_INVALID, "nothing usable under the eye")
	if not bool(info["in_range"]):
		return DotResult.fail(DotError.CODE_INVALID, "out of reach")
	return press_entity(int(info["index"]), user, activator if activator != null else user, info["at"] as Vector3)


## The same press for an entity already chosen (a bot that knows which button it wants, or a test).
func press_entity(index: int, user: Variant, activator: Variant = null, at: Vector3 = Vector3.ZERO) -> DotResult:
	var io := _world.io
	var e := io.entity_of(index) as DotMapMoverNode
	if e == null or e.use_state() == &"":
		return DotResult.fail(DotError.CODE_INVALID, "entity %d cannot be used" % index)
	var key := "%s:%d" % [str(user), index]
	if io.now < int(_next_ok.get(key, -1)):
		return DotResult.fail(DotError.CODE_STATE, "cooling down")
	var state := e.use_state()
	if state == &"pressed":
		return DotResult.fail(DotError.CODE_STATE, "still in")
	_next_ok[key] = io.now + io.ticks_for(cooldown)
	var res := io.use(index, activator if activator != null else user)
	if res.ok and effect_fn.is_valid():
		effect_fn.call(&"locked" if state == &"locked" else (&"toggle" if e.mover.toggle else &"press"), e, at)
	return res


## "Use", "Open" or the like for the prompt, by what the entity is.
static func label_for(e: DotMapMoverNode, state: StringName) -> String:
	if state == &"locked":
		return "Locked"
	if state == &"pressed":
		return ""
	return "Use" if e.mover.kind.ends_with("button") else "Open"


func cvar_specs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for spec in _SPECS:
		var kind: PackedStringArray = String(spec[2]).split(":")
		out.append({"name": spec[0], "description": spec[3], "value": str(get(spec[1])),
			"min": kind[1].to_float(), "max": kind[2].to_float()})
	return out


## Registers [member reach] and [member cooldown] as cvars through [param add] (`name, value, description, flags` returning the cvar) and keeps them on their values.
func bind_cvars(add: Callable, flags: int = 0) -> Array:
	var made: Array = []
	for spec in cvar_specs():
		var cv: Variant = add.call(spec["name"], String(spec["value"]), String(spec["description"]), flags)
		if not (cv is Object) or cv == null:
			continue
		var o := cv as Object
		if o.has_method(&"with_range"):
			o.call(&"with_range", float(spec["min"]), float(spec["max"]))
		if o.has_signal(&"changed"):
			o.connect(&"changed", func(_old: String, new_value: String) -> void: var _ok := set_cvar(spec["name"], new_value))
		made.append(o)
	return made


## Sets one setting from a cvar's text; false when the name is not ours or the text is not a number.
func set_cvar(cvar_name: String, text: String) -> bool:
	for spec in _SPECS:
		if spec[0] == cvar_name and text.is_valid_float():
			var kind: PackedStringArray = String(spec[2]).split(":")
			set(spec[1], clampf(text.to_float(), kind[1].to_float(), kind[2].to_float()))
			return true
	return false


func _entity_of(node: Node) -> DotMapMoverNode:
	while node != null and node != _world:
		if node.has_meta(&"model"):
			var model := int(node.get_meta(&"model"))
			if _by_model.is_empty():
				for c: DotMapEntity in _world.io.entities:
					if c is DotMapMoverNode and c.key("model").begins_with("*"):
						_by_model[int(c.key("model").substr(1))] = c
			return _by_model.get(model) as DotMapMoverNode
		node = node.get_parent()
	return null
