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
	var stored: DotResult = await DotMapStore.ensure(world.licence(), cloud, "", world.source_path.get_base_dir())
	if not stored.ok:
		DotLog.debug(CHANNEL, "a world's art slice could not be fetched; DotMapStore.apply warns once", {"at": prefix, "why": stored.error.message})
	return DotResult.success(world)


## Draws [param world] under [param parent].
static func attach(parent: Node3D, world: DotMapBspMesh, options: Dictionary = {}) -> DotMapDrawnWorld:
	var surfaces := _surfaces_for(world, options)
	var node := world.build_node(surfaces.world_material_for(world, world.source_path.get_base_dir()))
	return _finish(parent, world, options, surfaces, node)


## [method attach] that pauses on [param slice] throughout: the texture decode, each surface's material, the mesh batches and each finishing step (probes, props, lighting, culling) yield a frame once the budget is spent, so a loading cover keeps animating and no one frame holds the build.
## Null when [param parent] was freed during the build (the map was swapped away); the built meshes are freed with it.
## [code]options["mark"][/code], a [code]func(label: String)[/code], is told as each step ends ("drawn: materials", "drawn: meshes", "drawn: hang" ...) and of any one material dearer than [constant DotMapSurfaces.SLOW_MATERIAL_USEC], so a game's frame trace can name the step a long frame was spent in.
static func attach_async(parent: Node3D, world: DotMapBspMesh, options: Dictionary, slice: DotFrameSlice) -> DotMapDrawnWorld:
	var mark: Callable = options.get("mark", Callable())
	var surfaces := _surfaces_for(world, options)
	surfaces.on_step = mark
	var material_for: Callable = await surfaces.world_material_for_async(world, world.source_path.get_base_dir(), slice.budget_ms)
	_tell(mark, "drawn: materials")
	var node: Node3D = await world.build_node_async(material_for, true, false, slice)
	_tell(mark, "drawn: meshes")
	if not is_instance_valid(parent):
		DotLog.debug(CHANNEL, "the world's parent went away during the build; dropped", {"name": str(world.manifest.get("name", ""))})
		if node != null:
			node.free()
		return null
	var drawn := DotMapDrawnWorld.new()
	var names := ["hang", "probes", "props", "lit", "culling"]
	var at := 0
	for step: Callable in _finish_steps(parent, world, options, surfaces, node, drawn, slice):
		if slice.due():
			await slice.pause()
		if not is_instance_valid(parent):
			DotLog.debug(CHANNEL, "the world's parent went away while it was finished; dropped", {"name": str(world.manifest.get("name", ""))})
			if is_instance_valid(node) and node.get_parent() == null:
				node.free()
			return null
		await step.call()
		_tell(mark, "drawn: " + names[at])
		at += 1
	if not is_instance_valid(parent):
		return null
	_log_drawn(drawn)
	return drawn


static func _tell(mark: Callable, label: String) -> void:
	if mark.is_valid():
		mark.call(label)


static func _surfaces_for(world: DotMapBspMesh, options: Dictionary) -> DotMapSurfaces:
	var surfaces := DotMapSurfaces.new(str(options.get("surfaces_root", DotMapSurfaces.DEFAULT_ROOT)))
	surfaces.use_lightmap = bool(options.get("lightmap", true))
	DotMapStore.apply(world.licence(), options.get("cloud"), surfaces, world)
	if bool(options.get("one_way_glass", true)) and not world.glass_material_for.is_valid():
		var cell := DotMapOneWayGlass.cell_of(world.manifest)
		if not cell.is_empty():
			world.glass_material_for = DotMapOneWayGlass.hook(cell["centre"], cell["radius"])
	return surfaces


static func _finish(parent: Node3D, world: DotMapBspMesh, options: Dictionary, surfaces: DotMapSurfaces, node: Node3D) -> DotMapDrawnWorld:
	var drawn := DotMapDrawnWorld.new()
	for step: Callable in _finish_steps(parent, world, options, surfaces, node, drawn):
		step.call()
	_log_drawn(drawn)
	return drawn


## What follows the mesh build, one callable per step so [method attach_async] can yield between them: prune to the world and hang it under [param parent], the probes, the props, the lighting, the culling.
## With a [param slice] the props step also yields between props, so it must be awaited.
static func _finish_steps(parent: Node3D, world: DotMapBspMesh, options: Dictionary, surfaces: DotMapSurfaces, node: Node3D, drawn: DotMapDrawnWorld, slice: DotFrameSlice = null) -> Array[Callable]:
	return [
		func() -> void: _hang(parent, world, options, node, drawn),
		func() -> void: _add_probes(world, options, node),
		func() -> void: await _add_props(world, options, node, slice),
		func() -> void: _add_lit(parent, world, options, surfaces, node, drawn),
		func() -> void: _add_culling(parent, world, options, node, drawn),
	]


static func _hang(parent: Node3D, world: DotMapBspMesh, options: Dictionary, node: Node3D, drawn: DotMapDrawnWorld) -> void:
	drawn.world = world
	drawn.credits = DotMapCredits.line(world.manifest)
	node.name = "World"
	if bool(options.get("only_world", true)):
		var glass := {}
		# Drawn glass is solid only through a DotMapGlass pane; a caller that builds none must not draw it.
		for rec: Dictionary in (world.breakables() if bool(options.get("keep_glass", false)) else []):
			if rec.get("model") != null:
				glass[int(rec["model"])] = true
		for child in node.get_children():
			if String(child.name) == "world":
				continue
			if child.has_meta(&"model") and glass.has(int(child.get_meta(&"model"))):
				child.add_to_group(DotMapGlass.VISUAL_GROUP)
				continue
			node.remove_child(child)
			child.free()
	node.transform = options.get("transform", Transform3D.IDENTITY)
	parent.add_child(node)
	drawn.root = node


static func _add_probes(world: DotMapBspMesh, options: Dictionary, node: Node3D) -> void:
	var probes := int(options.get("probes", 8))
	if probes <= 0:
		return
	var env_node := world.build_environment(probes, false)
	if env_node == null:
		return
	var found := env_node.get_node_or_null("Probes")
	if found != null:
		env_node.remove_child(found)
		node.add_child(found)
	env_node.free()


static func _add_props(world: DotMapBspMesh, options: Dictionary, node: Node3D, slice: DotFrameSlice = null) -> void:
	if not bool(options.get("props", false)):
		return
	var props: Node3D
	if slice == null:
		props = world.build_props()
	else:
		props = await world.build_props_async(slice)
	if not is_instance_valid(node):
		props.free()
		return
	if props.get_child_count() > 0:
		node.add_child(props)
	else:
		props.free()


static func _add_lit(parent: Node3D, world: DotMapBspMesh, options: Dictionary, surfaces: DotMapSurfaces, node: Node3D, drawn: DotMapDrawnWorld) -> void:
	var env: Environment = options.get("environment")
	if env != null:
		drawn.lit = DotMapLitWorld.attach(parent, world, env, options.get("lamps", []), surfaces.use_lightmap, node)


static func _add_culling(parent: Node3D, world: DotMapBspMesh, options: Dictionary, node: Node3D, drawn: DotMapDrawnWorld) -> void:
	if not bool(options.get("cull", true)) or DisplayServer.get_name() == "headless":
		return
	var vis := DotMapVisibility.new()
	vis.name = "Visibility"
	parent.add_child(vis)
	var res := vis.setup(world, node)
	if res.ok:
		drawn.visibility = vis
	else:
		DotLog.debug(CHANNEL, "the world is drawn without culling", {"why": res.error.message})
		vis.queue_free()


static func _log_drawn(drawn: DotMapDrawnWorld) -> void:
	DotLog.debug(CHANNEL, "world drawn", {"name": str(drawn.world.manifest.get("name", "")), "lit": drawn.lit != null, "culled": drawn.visibility != null})


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
