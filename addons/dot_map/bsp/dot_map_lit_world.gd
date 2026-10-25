class_name DotMapLitWorld
extends Node
## Keeps a lightmapped world's actors lit like the baked scene: the author's per-leaf ambient at the camera drives the Environment's ambient, and the live lamps that only duplicated the bake are freed.

## Seconds between ambient samples; each scans every sample of the map.
const INTERVAL := 0.2
const BLEND := 0.4

var world: DotMapBspMesh = null
var environment: Environment = null
var _clock: float = 0.0


## Whether [param world] is drawn from its lightmap with [param enabled] on (a cvar or setting); the same test [member DotMapSurfaces.use_lightmap] applies.
static func wanted(world: DotMapBspMesh, enabled: bool = true) -> bool:
	return enabled and world != null and world.has_lightmap()


## Adds the driver under [param parent] for a world drawn lightmapped, freeing every node of [param lamps] (the lights the bake already holds; keep dynamic ones out of the list). Returns null when the world is not lit this way.
static func attach(parent: Node, world: DotMapBspMesh, environment: Environment, lamps: Array = [], enabled: bool = true) -> DotMapLitWorld:
	if not wanted(world, enabled):
		return null
	for lamp: Node in lamps:
		if is_instance_valid(lamp):
			lamp.queue_free()
	var node := DotMapLitWorld.new()
	node.name = "LitWorld"
	node.world = world
	node.environment = environment
	parent.add_child(node)
	return node


func _process(delta: float) -> void:
	_clock -= delta
	if _clock > 0.0 or world == null or environment == null:
		return
	_clock = INTERVAL
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var c := world.ambient_at(cam.global_position, Vector3.UP)
	if c.get_luminance() <= 0.0:
		return
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = environment.ambient_light_color.lerp(c, BLEND)
	environment.ambient_light_energy = 1.0
