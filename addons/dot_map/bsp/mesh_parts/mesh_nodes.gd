extends "mesh_core.gd"

## The scene-node half of [DotMapBspMesh]: a drawn model as a node tree of mesh instances and shadow proxies.


## Every drawn model as a node tree: a [code]world[/code] child with a [MeshInstance3D] per chunk and a [Node3D] per
## brush entity at its origin, meta [code]model[/code] and [code]mover[/code] set. [param movers_only] leaves the
## [code]world[/code] child empty, for a caller that draws the world model itself.
func build_node(material_for: Callable = Callable(), draw: bool = true, movers_only: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "BspMesh"
	for model in models():
		var parent := _model_parent(model, root)
		if not draw or (movers_only and model == WORLD):
			continue
		_add_model_meshes(parent, model, build_meshes(model, material_for))
	return root


## [method build_node] that pauses on [param slice] between batches of surfaces and between models.
func build_node_async(material_for: Callable, draw: bool, movers_only: bool, slice: DotFrameSlice) -> Node3D:
	var root := Node3D.new()
	root.name = "BspMesh"
	for model in models():
		var parent := _model_parent(model, root)
		if not draw or (movers_only and model == WORLD):
			continue
		var built: Array[Dictionary] = await build_meshes_async(model, material_for, slice)
		await _add_model_meshes_async(parent, model, built, slice)
		if slice.due():
			await slice.pause()
	return root


func _model_parent(model: int, root: Node3D) -> Node3D:
	var parent := Node3D.new()
	parent.set_meta(&"model", model)
	if model == WORLD:
		parent.name = "world"
	else:
		var tn := str(mover(model).get("targetname", ""))
		parent.name = ("%s_%d" % [tn.validate_node_name(), model]) if not tn.is_empty() else "model_%d" % model
		parent.position = model_origin(model)
		parent.set_meta(&"mover", mover(model))
	root.add_child(parent)
	return parent


func _add_model_meshes(parent: Node3D, model: int, built: Array[Dictionary]) -> void:
	for g: Dictionary in built:
		_add_one_mesh(parent, model, g)


func _add_model_meshes_async(parent: Node3D, model: int, built: Array[Dictionary], slice: DotFrameSlice) -> void:
	for g: Dictionary in built:
		_add_one_mesh(parent, model, g)
		if slice.due():
			await slice.pause()


func _add_one_mesh(parent: Node3D, model: int, g: Dictionary) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = g["mesh"]
	mi.position = -parent.position
	var c: Array = g["chunk"]
	mi.name = "sky3d" if g["sky3d"] else ("chunk_" + "_".join(PackedStringArray(c.map(str))) if c.size() >= 2 else "mesh")
	if g["clusters"] != null and model == WORLD:
		mi.set_meta(&"vis_clusters", g["clusters"])
	var decal: bool = g.get("decal", false)
	if g["glass"] or decal:
		mi.name = ("decal_" if decal else "glass_") + str(mi.name)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	if shadow_proxy and model == WORLD and not g["glass"] and not decal and not g["sky3d"]:
		_add_shadow_proxy(parent, mi)


## Whether [method build_node] draws a world chunk's sun shadow from a second, position-only, single-surface instance instead of the visual mesh (one draw per chunk per cascade, not one per material).
static var shadow_proxy: bool = true

## Camera distance (metres) beyond which a chunk's shadow proxy is not drawn into any cascade; 0 draws all. Wire a cvar to this before [method build_node].
static var shadow_range: float = 0.0


## Whether translucent surfaces (foliage, glass cards) are copied into the shadow proxy; off by default as a card's alpha is costly in the shadow pass.
static var shadow_translucent: bool = false


## Sets [member shadow_proxy] and [member shadow_range] for a caller that reaches this script by path.
static func set_shadow_cost(proxy: bool, range_m: float) -> void:
	shadow_proxy = proxy
	shadow_range = maxf(range_m, 0.0)


## Sets [member shadow_translucent] for a caller that reaches this script by path.
static func set_shadow_translucent(on: bool) -> void:
	shadow_translucent = on


## Moves [param visual]'s shadow onto a shadows-only sibling holding its opaque surfaces as one; translucent surfaces (foliage, glass) cast none unless [member shadow_translucent].
func _add_shadow_proxy(parent: Node3D, visual: MeshInstance3D) -> void:
	var mesh := visual.mesh
	var verts := PackedVector3Array()
	var index := PackedInt32Array()
	for s in mesh.get_surface_count():
		var m := mesh.surface_get_material(s) as BaseMaterial3D
		if not shadow_translucent and m != null and m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			continue
		var a := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var base := verts.size()
		verts.append_array(v)
		for i: int in a[Mesh.ARRAY_INDEX]:
			index.append(base + i)
	if index.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = index
	var proxy_mesh := ArrayMesh.new()
	proxy_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var proxy := MeshInstance3D.new()
	proxy.name = "shadow_" + str(visual.name)
	proxy.mesh = proxy_mesh
	proxy.position = visual.position
	proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	if shadow_range > 0.0:
		proxy.visibility_range_end = shadow_range
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.set_meta(&"shadow_proxy", proxy)
	parent.add_child(proxy)
