class_name DotMapDrawnWorld
extends RefCounted
## A converted world pack drawn over a game's own collision: the pack's meshes, lightmap, probes and culling, and nothing that collides, moves or plays.
##
## For a game whose map is its own document (boxes, doors, props) and wants the converted art on top: the document stays what everything stands on, this is only what is seen.

const CHANNEL := "dot_map.drawn"

## The pack drawn; null until [method attach].
var world: DotMapBspMesh = null
## The drawn node ("World"), its transform the pack's frame in the game's.
var root: Node3D = null
## Drives the ambient from the bake; null when the world is not drawn lightmapped.
var lit: DotMapLitWorld = null
## The culling node; null headless or for a pack without visibility data.
var visibility: DotMapVisibility = null
## [method DotMapCredits.line] of the pack: its author and the art whose licence asks for a name.
var credits: String = ""


## Reads the pack at [param prefix] and fetches the art slice its licence names ([DotMapStore]); the value is the [DotMapBspMesh]. A slice that cannot be had is only a warning: generic art is drawn.
static func read(prefix: String, cloud: Object = null) -> DotResult:
	var got := DotMapBspMesh.load_prefix(prefix)
	if not got.ok:
		return got
	var world: DotMapBspMesh = got.value
	var stored: DotResult = await DotMapStore.ensure(world.licence(), cloud)
	if not stored.ok:
		DotLog.warn(CHANNEL, "a world's art slice could not be fetched; generic art is drawn", {"at": prefix, "why": stored.error.message})
	return DotResult.success(world)


## Draws [param world] under [param parent]. [param options]:
## `transform` (Transform3D, the pack's frame in the parent's), `surfaces_root` (the game's vendored kinds, rebased; "" is the addon's),
## `lightmap` (true), `only_world` (true: brush entities are movers and breakables the game may not have kept, so drawing them would show what is not there),
## `props` (false: the pack's stand-ins collide with nothing), `probes` (8; 0 none), `cull` (true; never headless), `environment` and `lamps` (for [DotMapLitWorld]), `cloud`.
static func attach(parent: Node3D, world: DotMapBspMesh, options: Dictionary = {}) -> DotMapDrawnWorld:
	var drawn := DotMapDrawnWorld.new()
	drawn.world = world
	drawn.credits = DotMapCredits.line(world.manifest)
	var surfaces := DotMapSurfaces.new(str(options.get("surfaces_root", DotMapSurfaces.DEFAULT_ROOT)))
	surfaces.use_lightmap = bool(options.get("lightmap", true))
	DotMapStore.apply(world.licence(), options.get("cloud"), surfaces, world)
	var node := world.build_node(surfaces.world_material_for(world, world.source_path.get_base_dir()))
	node.name = "World"
	if bool(options.get("only_world", true)):
		for child in node.get_children():
			if String(child.name) != "world":
				node.remove_child(child)
				child.free()
	node.transform = options.get("transform", Transform3D.IDENTITY)
	parent.add_child(node)
	drawn.root = node

	var probes := int(options.get("probes", 8))
	if probes > 0:
		var env_node := world.build_environment(probes, false)
		if env_node != null:
			var found := env_node.get_node_or_null("Probes")
			if found != null:
				env_node.remove_child(found)
				node.add_child(found)
			env_node.free()

	if bool(options.get("props", false)):
		var props := world.build_props()
		if props.get_child_count() > 0:
			node.add_child(props)
		else:
			props.free()

	var env: Environment = options.get("environment")
	if env != null:
		drawn.lit = DotMapLitWorld.attach(parent, world, env, options.get("lamps", []), surfaces.use_lightmap, node)

	if bool(options.get("cull", true)) and DisplayServer.get_name() != "headless":
		var vis := DotMapVisibility.new()
		vis.name = "Visibility"
		parent.add_child(vis)
		var res := vis.setup(world, node)
		if res.ok:
			drawn.visibility = vis
		else:
			DotLog.debug(CHANNEL, "the world is drawn without culling", {"why": res.error.message})
			vis.queue_free()

	DotLog.debug(CHANNEL, "world drawn", {"name": str(world.manifest.get("name", "")), "lit": drawn.lit != null, "culled": drawn.visibility != null})
	return drawn


## Takes the drawn world out again: the node, the ambient driver and the culling.
func detach() -> void:
	for n: Node in [root, lit, visibility]:
		if is_instance_valid(n):
			n.queue_free()
	root = null
	lit = null
	visibility = null


func describe() -> String:
	return "drawn world %s: %s, lit %s, culled %s" % [
		str(world.manifest.get("name", "")) if world != null else "none",
		"attached" if is_instance_valid(root) else "detached", lit != null, visibility != null]
