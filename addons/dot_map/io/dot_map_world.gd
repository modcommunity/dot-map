class_name DotMapWorld
extends Node3D

## A converted map's whole world from one call: the drawn mesh with its glass, the collision hulls,
## the I/O runtime loaded from the stored source document, every entity class, the volumes,
## effects, sounds, the map-command allow-list, per-map settings and server-authoritative state
## replication. The game plugs its callables in once.
##
## [codeblock]
## var res := DotMapWorld.build("res://worlds/wo_office_course", {
##     "damage_fn": _damage, "move_fn": _move, "event_fn": _event, "effect_fn": _effect,
##     "ladder_fn": func(boxes): ladder_mode.volumes = boxes,
##     "swim_fn": func(boxes): swim_mode.volumes = boxes,
##     "send_fn": _send_to_peer,
## }, {"command_allow": ["sv_airaccelerate"]})
## if res.ok:
##     world = res.value
##     add_child(world)
## # every game tick, with the bodies volumes should test (see DotMapVolumeNode.step):
## world.step(bodies)
## [/codeblock]
##
## Nothing here names dot-player-controller: ladders and water reach it through [code]ladder_fn[/code]
## and [code]swim_fn[/code], which get an [code]Array[AABB][/code] at build and whenever a ladder or
## water volume is enabled or disabled.

const CHANNEL := "map.world"
const HOOKS := ["damage_fn", "move_fn", "event_fn", "effect_fn", "actor_fn", "propdata_fn", "player_fn"]

var mesh: DotMapBspMesh
var io: DotMapIO
var volumes: DotMapVolumes
## The host's state broadcaster (null on a client).
var sync: DotMapStateSync
## Per-map settings; null when the options named none.
var config: DotMapConfig
var config_result: DotResult = null
## The drawn tree from [method DotMapBspMesh.build_node]; collision bodies sit under each model's node.
var visual: Node3D
var glass: Array[DotMapGlass] = []
## Drives the ambient from the bake; null until [method light_with] finds a lightmapped world.
var lit: DotMapLitWorld = null
## The drawn stand-in of each prop_door_rotating.
var doors: Array[Node3D] = []
var sounds: Node3D
var map_id := ""
var ladder_fn := Callable()
var swim_fn := Callable()
## The game's effect callable, called after the world has started or stopped a sound stand-in.
var effect_fn := Callable()

var _boxes_dirty := false


## Builds the world of the mesh at [param prefix] (the [code].json]/[code].bin[/code] pair) or from an already
## loaded [DotMapBspMesh]. [param hooks]: [code]damage_fn, move_fn, event_fn, effect_fn, actor_fn, propdata_fn,
## player_fn, send_fn, ladder_fn, swim_fn, material_for[/code] (callables). [param options]: [code]doc[/code]
## (the source document), [code]doc_path[/code], [code]store[/code] (store root), [code]authoritative[/code]
## (true), [code]rate[/code] (60), [code]seed[/code], [code]command_allow[/code], [code]map_id[/code],
## [code]environment, props, sounds, collision[/code] (true), [code]surfaces[/code] (a [DotMapSurfaces]; with no
## [code]material_for[/code] hook the world is drawn through it, lightmapped, else through a default one), [code]lightmap[/code] (true), [code]layers[/code] ({solid, clip, glass} to
## a collision layer, default 1), [code]config[/code] ({game, config_dir, allow, defaults, get_fn, set_fn};
## the weakest layer is the manifest's [code]settings[/code], the cvars the map's own entities set, then
## [code]defaults[/code]; a key the game did not [code]allow[/code] is still refused).
## The source document is found beside the mesh as [code]<prefix>.doc.json[/code], else in the store by the
## sha256 the manifest records.
static func build(source: Variant, hooks: Dictionary = {}, options: Dictionary = {}) -> DotResult:
	var m: DotMapBspMesh
	if source is DotMapBspMesh:
		m = source
	else:
		var loaded := DotMapBspMesh.load_prefix(str(source))
		if not loaded.ok:
			return loaded.wrap("building a map world")
		m = loaded.value
	var doc_res := _find_document(m, options)
	if not doc_res.ok:
		return doc_res.wrap("building a map world")
	var w := DotMapWorld.new()
	w.mesh = m
	w.map_id = str(options.get("map_id", m.manifest.get("name", "")))
	w.name = "World_" + w.map_id.validate_node_name()
	var res := w._assemble(doc_res.value, hooks, options)
	if not res.ok:
		w.free()
		return res.wrap("building a map world")
	return DotResult.success(w)


## Advances the logic one tick, then steps the volumes with [param bodies] (host only: a client's
## clock is set by [method apply_state] and it runs no volumes).
func step(bodies: Array = []) -> void:
	io.advance(1)
	if io.authoritative:
		volumes.step(bodies)
	if _boxes_dirty:
		_boxes_dirty = false
		_push_boxes()


## Lights the actors from the author's bake: the ambient at the camera drives [param environment] ([DotMapLitWorld]), and [param lamps] (the lights the bake already holds) are freed. Returns null for a world without a lightmap. Call once the game's environment exists.
func light_with(environment: Environment, lamps: Array = [], sun: DirectionalLight3D = null) -> DotMapLitWorld:
	lit = DotMapLitWorld.attach(self, mesh, environment, lamps, true, visual)
	if lit != null:
		lit.sun = sun
	return lit


## A bullet along [param from] to [param to] against the map's own breakables, buttons and doors: the
## first body on the ray (on [param mask]) that belongs to one takes [param amount] through [method DotMapIO.hurt].
## Returns the entity index it hurt, or -1. Pass the nearest hit's distance in [param limit] (negative: none)
## so a player in front of the panel is not shot through. Host only.
func shoot(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, amount: float, by: Variant = null,
		mask: int = 0xFFFFFFFF, limit: float = -1.0) -> int:
	if not io.authoritative or space == null or amount <= 0.0:
		return -1
	var query := PhysicsRayQueryParameters3D.create(from, to, mask)
	var hit := space.intersect_ray(query)
	if hit.is_empty() or (limit >= 0.0 and from.distance_to(hit["position"] as Vector3) > limit + 0.01):
		return -1
	var node: Node = hit["collider"] as Node
	var model := -1
	while node != null and node != self:
		if node is DotMapGlass:
			model = (node as DotMapGlass).model
			break
		if node.has_meta(&"model"):
			model = int(node.get_meta(&"model"))
			break
		node = node.get_parent()
	if model <= 0:
		return -1
	for e: DotMapEntity in io.entities:
		if (e is DotMapBreakable or e is DotMapMoverNode) and e.key("model") == "*%d" % model:
			io.hurt(e.index, amount, hit["position"] as Vector3, by)
			return e.index
	return -1


## Lets a joining peer in: it gets the whole state now and every change after (host only).
func add_peer(peer: Variant) -> void:
	if sync != null:
		sync.add_peer(peer)


func remove_peer(peer: Variant) -> void:
	if sync != null:
		sync.remove_peer(peer)


## A client takes one [code]io_state[/code] or [code]io_snapshot[/code] message from the host.
func apply_state(msg: Dictionary) -> DotResult:
	return DotMapStateSync.new().apply(io, msg)


## The boxes of every active ladder brush, for dot-player-controller's ladder mode.
func ladder_boxes() -> Array[AABB]:
	return volumes.ladder_boxes()


func water_boxes() -> Array[AABB]:
	return volumes.water_boxes()


## The map's start points: every [code]info_player_*[/code] as [code]{classname, targetname, origin (metres), yaw (degrees, source axes), enabled (false when the map starts it disabled)}[/code].
func spawn_points() -> Array:
	var out: Array = []
	for e: DotMapEntity in io.entities:
		if e.classname.begins_with("info_player"):
			var ang := e.key("angles").split(" ")
			out.append({"classname": e.classname, "targetname": e.targetname, "origin": e.origin(io), "enabled": e.enabled,
					"yaw": ang[1].to_float() if ang.size() > 1 else 0.0})
	return out


func describe() -> Dictionary:
	return {"map": map_id, "mesh": mesh.describe(), "io": io.describe(), "volumes": volumes.describe(),
			"glass": glass.size(), "bodies": find_children("*", "CollisionObject3D", true, false).size(),
			"config": config.applied() if config != null else {}}


func _exit_tree() -> void:
	if config != null:
		config.restore()


static func _find_document(m: DotMapBspMesh, options: Dictionary) -> DotResult:
	if options.get("doc") is Dictionary:
		return DotResult.success(options["doc"])
	var paths: Array[String] = []
	if options.has("doc_path"):
		paths.append(str(options["doc_path"]))
	if not m.source_path.is_empty():
		paths.append(m.source_path + ".doc.json")
	var sha := str(m.manifest.get("source", {}).get("sha256", ""))
	if not sha.is_empty():
		var root := str(options.get("store", OS.get_environment("DOTBSP_STORE")))
		if root.is_empty():
			root = OS.get_environment("HOME").path_join("mapsrc/store")
		paths.append(root.path_join(sha).path_join("doc.json"))
	for p in paths:
		if not FileAccess.file_exists(p):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
		if parsed is Dictionary:
			return DotResult.success(parsed)
		return DotResult.fail(DotError.CODE_PARSE, "source document is not a JSON object", p)
	return DotResult.fail(DotError.CODE_IO, "no source document for the map's logic",
			"tried: " + ", ".join(paths))


func _assemble(doc: Dictionary, hooks: Dictionary, options: Dictionary) -> DotResult:
	var units: Dictionary = mesh.manifest.get("units", {})
	io = DotMapIO.new()
	io.rate = int(options.get("rate", 60))
	io.rng_seed = int(options.get("seed", 0))
	io.authoritative = bool(options.get("authoritative", true))
	io.unit_scale = float(units.get("metres_per_unit", io.unit_scale))
	io.command_allow = PackedStringArray(options.get("command_allow", PackedStringArray()))
	for h: String in HOOKS:
		if hooks.get(h) is Callable:
			io.set(h, hooks[h])
	effect_fn = hooks.get("effect_fn", Callable()) if hooks.get("effect_fn") is Callable else Callable()
	io.effect_fn = _effect
	ladder_fn = hooks.get("ladder_fn", Callable()) if hooks.get("ladder_fn") is Callable else Callable()
	swim_fn = hooks.get("swim_fn", Callable()) if hooks.get("swim_fn") is Callable else Callable()
	var cat := io.load_catalogue()
	if not cat.ok:
		DotLog.warn(CHANNEL, "no class catalogue, coverage cannot tell typos from engine inputs", {"error": cat.error})
	var loaded := io.load_document(doc)
	if not loaded.ok:
		return loaded
	var ents := DotMapEntities.from_manifest(mesh.manifest)
	var mat_for: Callable = hooks.get("material_for", Callable()) if hooks.get("material_for") is Callable else Callable()
	if not mat_for.is_valid():
		var surfaces: DotMapSurfaces = options.get("surfaces") if options.get("surfaces") is DotMapSurfaces else DotMapSurfaces.new()
		surfaces.use_lightmap = bool(options.get("lightmap", true))
		mat_for = surfaces.world_material_for(mesh, mesh.source_path.get_base_dir())
	visual = mesh.build_node(mat_for)
	add_child(visual)
	var layers: Dictionary = options.get("layers", {})
	if bool(options.get("environment", true)):
		var env := mesh.build_environment()
		if env != null:
			add_child(env)
			var we := env.find_children("*", "WorldEnvironment", true, false)
			var suns := env.find_children("*", "DirectionalLight3D", true, false)
			if not we.is_empty():
				light_with((we[0] as WorldEnvironment).environment, [], suns[0] as DirectionalLight3D if not suns.is_empty() else null)
	if bool(options.get("props", true)):
		add_child(mesh.build_props())
	if bool(options.get("sounds", true)):
		sounds = mesh.build_sounds()
		add_child(sounds)
	glass = mesh.build_breakables(visual, int(layers.get("glass", 1)), io.authoritative)
	if bool(options.get("collision", true)):
		_build_collision(ents, layers)
	io.bind_movers(ents.movers)
	io.bind_breakables(mesh.breakables())
	io.attach_sounds(mesh.sounds_data().get("ambient", []))
	volumes = DotMapVolumes.build(ents, io, mesh.manifest.get("destinations", {}))
	io.bind_world(visual)
	_build_doors(ents, hooks, layers)
	io.state_changed.connect(_on_state)
	if io.authoritative:
		if hooks.get("send_fn") is Callable:
			sync = DotMapStateSync.new()
			sync.attach_host(io, hooks["send_fn"])
		_apply_config(options.get("config", {}))
		io.start()
	_push_boxes()
	DotLog.info(CHANNEL, "map world built", {"map": map_id, "entities": io.entities.size(),
			"volumes": volumes.nodes.size(), "glass": glass.size()})
	return DotResult.success(self)


## A drawn panel and body for each prop_door_rotating (no brush model); [code]door_fn(mover, yaw) -> Node3D[/code]
## in the hooks replaces the stand-in with the game's own model.
func _build_doors(ents: DotMapEntities, hooks: Dictionary, layers: Dictionary) -> void:
	for m: DotMapMover in ents.movers:
		if m.model >= 0 or m.classname.to_lower() != "prop_door_rotating":
			continue
		var e: DotMapEntity = io.entity_of(m.entity)
		if not e is DotMapMoverNode:
			continue
		var ang := e.key("angles").split_floats(" ", false)
		var yaw := float(ang[1]) if ang.size() > 1 else 0.0
		var entity_yaw := yaw
		if not is_nan(m.panel_yaw):
			yaw = m.panel_yaw
		var door: Node3D = null
		if hooks.get("door_fn") is Callable:
			door = _hung_model((hooks["door_fn"] as Callable).call(m, entity_yaw), m, entity_yaw)
		if door == null:
			door = DotMapDoorStandIn.build(m, yaw, DotMapDoorStandIn.SIZE, int(layers.get("solid", 1)))
		visual.add_child(door)
		var width := m.panel_width if not is_nan(m.panel_yaw) and m.panel_width > 0.1 else DotMapDoorStandIn.SIZE.x
		var half := Vector3(DotMapDoorStandIn.SIZE.z, DotMapDoorStandIn.SIZE.y, width) * 0.5
		var yaw_basis := Basis(Vector3.UP, deg_to_rad(yaw))
		(e as DotMapMoverNode).set_hit_box(Transform3D(yaw_basis, m.origin + yaw_basis * Vector3(0.0, half.y, -half.z)), half)
		e.bind_node(door)
		e.tick_view(io)
		doors.append(door)


## A game's model is built with its origin where the model's is (mid-panel on a door hung off an authored
## hinge) and the entity's yaw, but [DotMapMoverNode] swings the node about its own origin, which must be the
## hinge. So it goes under a pivot on the hinge, [member DotMapMover.panel_offset] along the panel.
func _hung_model(model: Node3D, m: DotMapMover, entity_yaw: float) -> Node3D:
	if model == null or is_nan(m.panel_yaw) or m.panel_offset <= 0.0:
		return model
	var pivot := Node3D.new()
	pivot.name = model.name if model.name != &"" else &"Door"
	pivot.position = m.origin
	pivot.rotation.y = deg_to_rad(m.panel_yaw)
	model.position = Vector3(0.0, 0.0, -m.panel_offset)
	model.rotation = Vector3(0.0, deg_to_rad(entity_yaw - m.panel_yaw), 0.0)
	pivot.add_child(model)
	return pivot


func _apply_config(opts: Dictionary) -> void:
	if opts.is_empty():
		return
	config = DotMapConfig.new()
	config.game = str(opts.get("game", ""))
	config.config_dir = str(opts.get("config_dir", ""))
	config.defaults = (mesh.manifest.get("settings", {}) as Dictionary).duplicate()
	config.defaults.merge(opts.get("defaults", {}), true)
	var allow: Variant = opts.get("allow", {})
	if allow is Dictionary:
		for k: String in allow:
			config.allow(k, allow[k])
	else:
		config.allow_all(PackedStringArray(allow))
	config.get_fn = opts.get("get_fn", Callable())
	config.set_fn = opts.get("set_fn", Callable())
	if config.get_fn.is_valid() and config.set_fn.is_valid():
		config_result = config.apply(map_id)


## Hulls as bodies under each model's node: one per kind, so a game gives clip and glass their own layers.
func _build_collision(ents: DotMapEntities, layers: Dictionary) -> void:
	var broken := {}
	for g in glass:
		broken[g.model] = true
	var by_model := {}
	for c in visual.get_children():
		if c.has_meta(&"model"):
			by_model[int(c.get_meta(&"model"))] = c
	var physboxes := {}
	for e: DotMapEntity in io.entities:
		if e is DotMapPhysbox and e.key("model").begins_with("*"):
			physboxes[int(e.key("model").substr(1))] = e
	for model in mesh.models():
		if broken.has(model) or not by_model.has(model):
			continue
		var parent: Node3D = by_model[model]
		var mv := ents.mover_for_model(model)
		if mv != null and not mv.solid:
			continue
		var moving := model != DotMapBspMesh.WORLD and mv != null
		for kind in ["solid", "clip", "glass"]:
			var shapes := mesh.hull_shapes(model, PackedStringArray([kind]))
			var concave: Array[ConcavePolygonShape3D] = []
			if kind == "solid":
				concave = mesh.concave_shapes(model)
			if shapes.is_empty() and concave.is_empty():
				continue
			var phys: DotMapPhysbox = physboxes.get(model) if kind == "solid" else null
			var body: PhysicsBody3D
			if phys != null:
				body = RigidBody3D.new()
				concave = []
				if shapes.is_empty():
					continue
			elif moving:
				body = AnimatableBody3D.new()
				# The io moves the parent. A synced body copies each physics step's pose back onto itself, which offsets
				# it from the parent by however far the parent moved since: a collider that drifts with frame timing.
				(body as AnimatableBody3D).sync_to_physics = false
			else:
				body = StaticBody3D.new()
			body.name = "col_" + kind
			body.collision_layer = int(layers.get(kind, 1))
			body.collision_mask = body.collision_layer if phys != null else 0
			body.set_meta(&"hull_kind", kind)
			for h: Dictionary in shapes:
				var cs := CollisionShape3D.new()
				cs.shape = h["shape"]
				body.add_child(cs)
			for s in concave:
				var cs2 := CollisionShape3D.new()
				cs2.shape = s
				body.add_child(cs2)
			parent.add_child(body)
			if phys != null:
				_make_physbox(phys, body as RigidBody3D, parent)


## The drawn meshes of a func_physbox ride its rigid body; its mass follows the hulls' size.
func _make_physbox(phys: DotMapPhysbox, rb: RigidBody3D, model_node: Node3D) -> void:
	var volume := 0.0
	for c in rb.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is ConvexPolygonShape3D:
			var box := AABB()
			var pts := ((c as CollisionShape3D).shape as ConvexPolygonShape3D).points
			for i in pts.size():
				box = box.expand(pts[i]) if i > 0 else AABB(pts[i], Vector3.ZERO)
			volume += box.get_volume() * 0.6
	rb.mass = clampf(volume * 150.0, 1.0, 2000.0)
	for c in model_node.get_children():
		if c is MeshInstance3D:
			c.reparent(rb, false)
	phys.bind_body(rb, io.authoritative)


func _on_state(e: DotMapEntity, key: String, _value: Variant, _tick: int) -> void:
	if key == "enabled" or key == "alive":
		_boxes_dirty = true


func _push_boxes() -> void:
	if ladder_fn.is_valid():
		ladder_fn.call(volumes.ladder_boxes())
	if swim_fn.is_valid():
		swim_fn.call(volumes.water_boxes())


## Plays and stops the sound stand-ins itself, then tells the game's own callable.
func _effect(kind: String, e: DotMapEntity, on: bool) -> void:
	if kind == "sound" and sounds != null:
		var tn := e.targetname
		var nm := (tn if not tn.is_empty() else "amb_%d" % e.index).validate_node_name()
		var node := sounds.get_node_or_null(nm)
		# Not in the tree yet (a spawn output during the build): play() errors; autoplay starts it on entry.
		if (node is AudioStreamPlayer3D or node is AudioStreamPlayer) and node.is_inside_tree():
			node.call("play" if on else "stop")
	if effect_fn.is_valid():
		effect_fn.call(kind, e, on)
