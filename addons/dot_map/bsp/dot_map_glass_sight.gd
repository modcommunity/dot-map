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


## Splits a map's legacy hulls and, when it has a jail cell, returns the rule for it (null otherwise).
##
## [param mesh] is the loaded [DotMapBspMesh], [param body] its legacy world body, [param clip_mask] the layer clip and fence hulls move to,
## [param glass_bit] glass's own extra bit. Thin horizontal glass (floors) goes to a sibling body that is also on [param floor_mask] (the world layer),
## because a downward ray must still find the floor; sight and shots only care about the walls. Bodies keep `hull_kind`, so [method is_exempt]
## tells a game's blanket layer reset to leave them alone. The rule's [member world_mask] is [param world_mask]; check [method problem].
static func install(mesh: Object, body: StaticBody3D, clip_mask: int, glass_bit: int, floor_mask: int, world_mask: int) -> DotMapGlassSight:
	var cell: Dictionary = DotMapOneWayGlass.cell_of(mesh.manifest)
	var layers := {"clip": clip_mask, "fence": clip_mask}
	if not cell.is_empty():
		layers["glass"] = clip_mask | glass_bit
	var moved: Dictionary = mesh.split_legacy_hulls(body, layers)
	if cell.is_empty() or int(moved.get("glass", 0)) == 0:
		return null
	var glass_body := body.find_child("ImportedGlass", true, false) as StaticBody3D
	if glass_body != null:
		var floors := StaticBody3D.new()
		floors.name = "ImportedGlassFloor"
		floors.collision_layer = floor_mask | clip_mask
		floors.collision_mask = 0
		floors.set_meta(&"hull_kind", "glass_floor")
		floors.set_meta(&"dot_material", &"glass")
		for c in glass_body.get_children():
			var shape := (c as CollisionShape3D).shape as ConvexPolygonShape3D if c is CollisionShape3D else null
			if shape == null or shape.points.is_empty():
				continue
			var box := AABB(shape.points[0], Vector3.ZERO)
			for p in shape.points:
				box = box.expand(p)
			if box.size.y < 0.5 * minf(box.size.x, box.size.z):
				glass_body.remove_child(c)
				floors.add_child(c)
		if floors.get_child_count() > 0:
			glass_body.get_parent().add_child(floors)
		else:
			floors.free()
	var rules := DotMapGlassSight.new(cell["centre"], float(cell["radius"]), glass_bit)
	rules.world_mask = world_mask
	return rules


## Whether [param node] is an importer fence or glass body whose layers a game's blanket layer reset must keep.
## Clip bodies are left out on purpose: bots' surf rides depend on a clip brush being solid to the world layer.
static func is_exempt(node: Node) -> bool:
	return node.get_meta(&"hull_kind", "") in ["fence", "glass", "glass_floor"]


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
