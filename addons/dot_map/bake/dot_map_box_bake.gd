class_name DotMapBoxBake
extends RefCounted

## Baked light for a map a game draws from boxes in code: the half of dot-lighting's
## [code]DotLightBake[/code] every box-document game repeats.

const CHANNEL := "dot.map.box_bake"

## Bump when what a bake means changes here (the bake scene's lamps, emission and sky): every fingerprint includes it.
const VERSION := 1

## dot-lighting's API level that has [code]DotLightBake[/code] and [code]DotLightmapSheet[/code].
const MIN_LEVEL := 5

const BAKE_SCRIPT := "res://addons/dot_lighting/bake/dot_light_bake.gd"
const SHEET_SCRIPT := "res://addons/dot_lighting/bake/dot_lightmap_sheet.gd"

## A mesh that carries a lightmap UV2 and goes into the bake scene.
const META_BAKEABLE := &"dot_bakeable"

## The default bake: a sky term that stands in for the live ambient, and how much of the ambient each surface emits (a lightmap ignores the
## environment's ambient, and a closed room has no sky to see). A game overrides either per map through the settings it passes.
const DEFAULTS := {"quality": LightmapGI.BAKE_QUALITY_MEDIUM, "bounces": 3, "texel_scale": 1.0, "ambient_gain": 4.0, "bounce_energy": 0.7, "emit": 0.4}


## Whether this host's dot-lighting can lay a bake.
static func can_bake() -> bool:
	return DotAddonApi.build_level("dot_lighting") >= MIN_LEVEL and ResourceLoader.exists(BAKE_SCRIPT) and ResourceLoader.exists(SHEET_SCRIPT)


## A fresh UV2 sheet for one batch, or null where this host cannot bake.
static func new_sheet() -> RefCounted:
	return (load(SHEET_SCRIPT) as GDScript).new() if can_bake() else null


## The six faces of a box into [param sheet], with the winding the games' own box builders write. [param frame] is the box's transform.
static func add_faces(sheet: RefCounted, frame: Transform3D, size: Vector3) -> void:
	var h := size * 0.5
	var faces := [
		[Vector3.RIGHT, Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, -h.y, h.z)],
		[Vector3.LEFT, Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, h.y, -h.z), Vector3(-h.x, -h.y, -h.z)],
		[Vector3.UP, Vector3(-h.x, h.y, -h.z), Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, h.y, -h.z)],
		[Vector3.DOWN, Vector3(-h.x, -h.y, h.z), Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z)],
		[Vector3.BACK, Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, -h.y, h.z)],
		[Vector3.FORWARD, Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, -h.y, -h.z)],
	]
	for face: Array in faces:
		var n: Vector3 = frame.basis * (face[0] as Vector3)
		sheet.face(frame * (face[1] as Vector3), frame * (face[2] as Vector3), frame * (face[3] as Vector3), frame * (face[4] as Vector3), n)


## The finished mesh of a batch built through [param sheet]: its faces and UV2 committed into [param tool], sized for the baker.
static func commit(tool: SurfaceTool, sheet: RefCounted) -> ArrayMesh:
	sheet.commit(tool)
	var mesh := tool.commit()
	mesh.lightmap_size_hint = sheet.size
	return mesh


## What a bake must have been made from, from [param parts] (the document's boxes, lamps, environment: anything JSON can hold).
static func fingerprint(parts: Dictionary) -> String:
	if not can_bake():
		return ""
	var mine := parts.duplicate()
	mine["dot_map_box_bake"] = VERSION
	return (load(BAKE_SCRIPT) as GDScript).call(&"fingerprint", mine)


## Offline: the scene dot-lighting's baker bakes, from a map the game built as a client builds it. [param drawn] holds the meshes marked
## [constant META_BAKEABLE] and the omni lamps; [param lighting] is the map's dot-lighting node (its sun is baked as bounce only and stays live).
## [param settings] override [constant DEFAULTS]; [param parts] are what [param fp] was made from.
static func bake_scene(drawn: Node3D, lighting: Node3D, fp: String, out_path: String, settings: Dictionary = {}, parts: Dictionary = {}) -> Node3D:
	var cfg := DEFAULTS.duplicate()
	cfg.merge(settings, true)
	var root := Node3D.new()
	root.name = "Bake"
	var held := Node3D.new()
	held.name = "Drawn"
	root.add_child(held)

	var world := _world_environment(lighting)
	var ambient := world.environment.ambient_light_color if world != null else Color.WHITE
	var energy := world.environment.ambient_light_energy if world != null else 1.0
	var emit := float(cfg["emit"]) * energy

	for child in drawn.get_children():
		if child is MeshInstance3D and child.has_meta(META_BAKEABLE):
			var mesh := MeshInstance3D.new()
			mesh.name = child.name
			mesh.mesh = (child as MeshInstance3D).mesh
			mesh.material_override = _with_emission((child as MeshInstance3D).material_override, ambient, emit)
			mesh.gi_mode = GeometryInstance3D.GI_MODE_STATIC
			held.add_child(mesh)
		elif child is OmniLight3D or child is SpotLight3D:
			var lamp := (child as Light3D).duplicate() as Light3D
			lamp.visible = true
			lamp.light_bake_mode = Light3D.BAKE_STATIC
			lamp.shadow_enabled = bool(cfg.get("lamp_shadow", true))
			lamp.light_size = 0.15
			held.add_child(lamp)

	var lit := lighting.duplicate() as Node3D
	root.add_child(lit)
	var first := true
	for node in lit.get_children():
		if node is DirectionalLight3D:
			(node as DirectionalLight3D).light_bake_mode = Light3D.BAKE_DYNAMIC if first else Light3D.BAKE_DISABLED
			first = false

	var gi: LightmapGI = (load(BAKE_SCRIPT) as GDScript).call(&"prepare", root, fp, out_path, cfg, parts)
	var sky := _world_environment(lit)
	if sky != null:
		# The sky term is the map's own ambient, not the sky: a deep blue sky bakes bluer and darker than the flat ambient the map is tuned under.
		gi.environment_mode = LightmapGI.ENVIRONMENT_MODE_CUSTOM_COLOR
		gi.environment_custom_color = sky.environment.ambient_light_color
		gi.environment_custom_energy = sky.environment.ambient_light_energy * float(cfg["ambient_gain"])
	gi.bounce_indirect_energy = float(cfg["bounce_energy"])
	_own(root, root)
	return root


## Runtime: lays the bake at [param path] over [param host], if it was made from [param fp]. On success the baked meshes lose their metal
## (a lightmap holds diffuse light only; baked, a metallic surface drew nearly black), [param lamps] turn static (the lightmap lights the
## boxes; they still light everything that moves) and the result carries the [LightmapGI].
static func attach(host: Node3D, path: String, fp: String, lamps: Array = []) -> DotResult:
	if not can_bake() or fp == "":
		return DotResult.fail(DotError.CODE_UNSUPPORTED, "this host cannot lay a bake")
	var res: DotResult = (load(BAKE_SCRIPT) as GDScript).call(&"attach", host, path, fp)
	if not res.ok:
		return res
	for lamp: Light3D in lamps:
		lamp.light_bake_mode = Light3D.BAKE_STATIC
	_dull_metal(host)
	DotLog.debug(CHANNEL, "a map is drawn with its baked light", {"path": path})
	return res


static func _dull_metal(node: Node) -> void:
	if node is MeshInstance3D and node.has_meta(META_BAKEABLE):
		var mesh := node as MeshInstance3D
		var mat := mesh.material_override as StandardMaterial3D
		if mat != null and mat.metallic > 0.0:
			var copy := mat.duplicate() as StandardMaterial3D
			copy.metallic = 0.0
			mesh.material_override = copy
	for child in node.get_children():
		_dull_metal(child)


static func _world_environment(root: Node) -> WorldEnvironment:
	for node in root.get_children():
		if node is WorldEnvironment:
			return node as WorldEnvironment
		var inner := _world_environment(node)
		if inner != null:
			return inner
	return null


## Every surface emits the ambient into the bake (a copy of its material; the lightmap holds only what a surface receives), so light bounces
## round a closed room the way the live ambient fills it, with its corners dark.
static func _with_emission(source: Material, colour: Color, energy: float) -> Material:
	if energy <= 0.0 or not (source is StandardMaterial3D):
		return source
	var copy := (source as StandardMaterial3D).duplicate() as StandardMaterial3D
	copy.emission_enabled = true
	copy.emission = colour
	copy.emission_energy_multiplier = energy
	copy.emission_texture = null
	return copy


static func _own(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_own(child, owner_node)
