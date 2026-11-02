class_name DotMapGlassSight
extends RefCounted

## The jail glass rule for gameplay queries: a ray that starts inside the cell is stopped by the glass, one that starts outside passes.
##
## [DotMapOneWayGlass] only draws the rule. This applies it to sight and hitscan without a second body: a query whose
## origin is within [member radius] of the cell centre counts the glass layer as solid, any other query ignores it.
## Defaults: bots inside cannot see out ([member block_sight]), a shooter inside cannot hit out ([member block_shots]),
## everyone outside sees and shoots in. Spectator and dev cameras never ask, so they are unaffected.

const _SPECS := [
	["sv_glass_block_sight", "block_sight", "1: bot sight and line_of_sight from inside the jail cell is blocked by its glass; 0: sees through"],
	["sv_glass_block_shots", "block_shots", "1: a hitscan shot fired from inside the jail cell is stopped by its glass; 0: passes"],
]

## Cell centre and radius, as [method DotMapOneWayGlass.cell_of] returns them.
var centre := Vector3.ZERO
var radius := 6.0
## Extra metres beyond [member radius] where glass still belongs to the cell (as the shader's margin).
var margin := 2.0
## Collision layer bit mask the glass hulls are on ([method DotMapBspMesh.split_legacy_hulls]).
var glass_mask := 0
## Layer bits of everything else a shot must hit (world, clip, props). A glass bit shared with these is never stripped from an outside shot.
## The BSP world defaults the glass hulls to layer 1, so a game must give glass its own bit via the `layers` option and check [method problem].
var world_mask := 0
var block_sight := true
var block_shots := true


func _init(cell_centre: Vector3 = Vector3.ZERO, cell_radius: float = 6.0, glass_layers: int = 0) -> void:
	centre = cell_centre
	radius = cell_radius
	glass_mask = glass_layers


## Whether a query starting at [param from] is inside the cell.
func from_inside(from: Vector3) -> bool:
	return DotMapOneWayGlass.sees_solid(from, centre, radius)


## The mask for a hitscan from [param from]: [param mask] plus the glass layer from inside (when shots are blocked), minus it elsewhere.
func shot_mask(from: Vector3, mask: int) -> int:
	if block_shots and from_inside(from):
		return mask | glass_mask
	return mask & ~(glass_mask & ~world_mask)


## Empty when the glass layer is its own; otherwise why it is not (shared with [member world_mask], so sight and shots from inside would hit walls).
func problem() -> String:
	if glass_mask != 0 and glass_mask & world_mask != 0:
		return "glass layer mask %d shares bits with the world mask %d; give glass its own layer" % [glass_mask, world_mask]
	return ""


## Whether the glass stops a ray from [param from] to [param to] (false for any origin outside the cell).
func blocks(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, exclude: Array[RID] = []) -> bool:
	if space == null or glass_mask == 0 or not from_inside(from):
		return false
	var q := PhysicsRayQueryParameters3D.create(from, to, glass_mask)
	q.exclude = exclude
	var hit := space.intersect_ray(q)
	return not hit.is_empty() and (hit["position"] as Vector3).distance_to(centre) < radius + margin


## [param inner] (a `line_of_sight(from, to) -> bool`) with the sight rule in front; [param space_fn] returns the current space state.
## Install it as the bot world's `line_of_sight_fn`.
func sight_fn(space_fn: Callable, inner: Callable = Callable()) -> Callable:
	return func(from: Vector3, to: Vector3) -> bool:
		if block_sight and blocks(space_fn.call() as PhysicsDirectSpaceState3D, from, to):
			return false
		return bool(inner.call(from, to)) if inner.is_valid() else true


func cvar_specs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for spec in _SPECS:
		out.append({"name": spec[0], "description": spec[2], "value": "1" if get(spec[1]) else "0"})
	return out


## Registers both settings as cvars through [param add] (`name, value, description, flags`) and keeps them on their values.
func bind_cvars(add: Callable, flags: int = 0) -> Array:
	var made: Array = []
	for spec in cvar_specs():
		var cv: Variant = add.call(spec["name"], String(spec["value"]), String(spec["description"]), flags)
		if not (cv is Object) or cv == null:
			continue
		var o := cv as Object
		if o.has_signal(&"changed"):
			o.connect(&"changed", func(_old: String, new_value: String) -> void: var _ok := set_cvar(spec["name"], new_value))
		made.append(o)
	return made


## Sets one setting from a cvar's text; false when the name is not ours.
func set_cvar(cvar_name: String, text: String) -> bool:
	for spec in _SPECS:
		if spec[0] == cvar_name:
			set(spec[1], text.strip_edges() not in ["0", "false", ""])
			return true
	return false
