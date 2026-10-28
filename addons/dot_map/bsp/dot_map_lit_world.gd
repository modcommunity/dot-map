class_name DotMapLitWorld
extends Node
## Keeps a lightmapped world's actors lit like the baked scene: the author's per-leaf ambient at the camera drives the Environment's ambient, and the live lamps that only duplicated the bake are freed.

## Seconds between ambient samples; each scans every sample of the map.
const INTERVAL := 0.2
const BLEND := 0.4

var world: DotMapBspMesh = null
var environment: Environment = null
## The node the world is drawn under when it is moved: the camera is sampled in its frame.
var frame: Node3D = null
## The scene's sun, raised to [member min_sun_energy] so shadowed interiors of a dim map still read; null leaves it alone.
var sun: DirectionalLight3D = null
## Least energy [member sun] keeps (0: no floor).
var min_sun_energy: float = 0.0
var _clock: float = 0.0


## Whether [param world] is drawn from its lightmap with [param enabled] on (a cvar or setting); the same test [member DotMapSurfaces.use_lightmap] applies.
static func wanted(world: DotMapBspMesh, enabled: bool = true) -> bool:
	return enabled and world != null and world.has_lightmap()


## Adds the driver under [param parent] for a world drawn lightmapped, freeing every node of [param lamps] (the lights the bake already holds; keep dynamic ones out of the list). [param p_frame] is the world's node when it is not at the origin. Returns null when the world is not lit this way.
static func attach(parent: Node, world: DotMapBspMesh, environment: Environment, lamps: Array = [], enabled: bool = true, p_frame: Node3D = null) -> DotMapLitWorld:
	if not wanted(world, enabled):
		return null
	for lamp: Node in lamps:
		if is_instance_valid(lamp):
			lamp.queue_free()
	var node := DotMapLitWorld.new()
	node.name = "LitWorld"
	node.world = world
	node.environment = environment
	node.frame = p_frame
	parent.add_child(node)
	return node


## An actor's ambient [param c] after the visibility floor and, when set, [member DotMapBspMesh.lightmap_max_chroma_ratio].
static func lifted(c: Color) -> Color:
	var floor_lum := DotMapBspMesh.visibility_floor
	var lum := c.get_luminance()
	if floor_lum > 0.0 and lum < floor_lum:
		c = c * (floor_lum / lum) if lum > 0.0 else Color(floor_lum, floor_lum, floor_lum)
	if DotMapBspMesh.lightmap_max_chroma_ratio > 0.0:
		var v := DotMapSurfaces.limit_chroma(Vector3(c.r, c.g, c.b), DotMapBspMesh.lightmap_max_chroma_ratio)
		c = Color(v.x, v.y, v.z)
	return c


func _process(delta: float) -> void:
	if sun != null and is_instance_valid(sun) and sun.light_energy < min_sun_energy:
		sun.light_energy = min_sun_energy
	_clock -= delta
	if _clock > 0.0 or world == null or environment == null:
		return
	_clock = INTERVAL
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var at := cam.global_position
	if frame != null and frame.is_inside_tree():
		at = frame.global_transform.affine_inverse() * at
	var c := world.ambient_at(at, Vector3.UP)
	c = lifted(c)
	if c.get_luminance() <= 0.0:
		return
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = environment.ambient_light_color.lerp(c, BLEND)
	environment.ambient_light_energy = 1.0
