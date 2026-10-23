class_name DotMapSurfaces
extends RefCounted

## A map generator's answer to "what is this surface made of": it asks for a kind
## ([code]&"brick"[/code], [code]&"asphalt"[/code]) and gets a [StandardMaterial3D].
##
## [codeblock]
## var surfaces := DotMapSurfaces.new()          # or .new("res://assets/surfaces")
## wall_mesh.material_override = surfaces.material(&"brick")
## floor_mesh.material_override = surfaces.material(&"tile_dark", Color(0.8, 0.85, 0.9))
## [/codeblock]
##
## [b]World-space triplanar, because a code-built box has no authored UVs.[/b] A map is
## hundreds of boxes of every size; per-box UVs would stretch a brick across a two-metre wall
## and a twenty-metre one alike. Mapped in world space a brick is the same size on every wall,
## and [constant KINDS] says how many metres one texture covers, so texel density is the same
## across the map too. Triplanar is a plain [StandardMaterial3D] flag, so it draws the same in
## Forward+ and in the browser's Compatibility renderer.
##
## [b]Files, not generated, and loaded by path rather than referenced by a scene[/b], for the
## delivered pack: an imported material records the AUTHORED location of its textures, and a
## pack mounts elsewhere (dot-cloud's publishing.md, "Binary imports are fixed at mount"). A
## material built here is given the textures [method ResourceLoader.load] opened at the path
## [member root] plus the file name, so a game that ships the textures in its own pack points
## [member root] at the mounted copy, or sets [member path_fn] to its path rebasing function.
## [b]The default [member root] is this addon's own folder[/b], which is the host build's copy:
## a pack that must carry the textures needs them inside its own tree.
##
## [b]Albedo is photographic and untouched[/b]; [param tint] multiplies it. A tint is what lets
## one concrete be a cold street and a warm basement, and it is also what the lightmap baker
## reads, because it bakes from albedo.
##
## [b]Normal maps are the OpenGL (Y+) convention[/b], which is what Godot reads. A DirectX map
## looks fine on a flat wall and inside out on a bevel.
##
## Credits for every texture are in [code]surfaces/CREDITS.md[/code] beside the files.

const CHANNEL := "dot_map.surfaces"

const DEFAULT_ROOT := "res://addons/dot_map/surfaces"

## Kind to what draws it. [code]meters[/code] is the width one texture covers in the world.
## [code]rough[/code] scales the roughness map (a photo's own roughness is a little glossy for
## a mid-2000s look under one hard light); [code]metal[/code] is the metallic value.
const KINDS := {
	&"concrete": {"meters": 2.5, "rough": 1.0, "metal": 0.0},
	&"concrete_clean": {"meters": 3.0, "rough": 1.0, "metal": 0.0},
	&"plaster": {"meters": 2.5, "rough": 1.0, "metal": 0.0},
	&"brick": {"meters": 3.0, "rough": 1.0, "metal": 0.0},
	&"tile_white": {"meters": 2.4, "rough": 1.0, "metal": 0.0},
	&"tile_dark": {"meters": 3.0, "rough": 1.0, "metal": 0.0},
	&"tile_checker": {"meters": 3.0, "rough": 1.0, "metal": 0.0},
	&"wood_floor": {"meters": 1.6, "rough": 1.0, "metal": 0.0},
	&"wood_planks": {"meters": 1.2, "rough": 1.0, "metal": 0.0},
	&"asphalt": {"meters": 3.0, "rough": 1.0, "metal": 0.0},
	&"metal": {"meters": 2.0, "rough": 1.0, "metal": 0.6},
	&"rust": {"meters": 2.0, "rough": 1.0, "metal": 0.3},
	&"corrugated": {"meters": 3.0, "rough": 1.0, "metal": 0.5},
	&"grass": {"meters": 2.0, "rough": 1.0, "metal": 0.0},
	&"ground": {"meters": 3.0, "rough": 1.0, "metal": 0.0},
	&"carpet_grey": {"meters": 2.0, "rough": 1.0, "metal": 0.0},
	&"carpet_pattern": {"meters": 2.0, "rough": 1.0, "metal": 0.0},
	&"carpet_red": {"meters": 2.0, "rough": 1.0, "metal": 0.0},
	&"carpet_blue": {"meters": 2.0, "rough": 1.0, "metal": 0.0},
	&"snow": {"meters": 3.0, "rough": 1.0, "metal": 0.0},
	&"rock": {"meters": 4.0, "rough": 1.0, "metal": 0.0},
	&"sand": {"meters": 3.0, "rough": 1.0, "metal": 0.0},
	&"stone_block": {"meters": 3.0, "rough": 1.0, "metal": 0.0},
	&"roof_clay": {"meters": 2.0, "rough": 1.0, "metal": 0.0},
	&"ceiling_tile": {"meters": 2.4, "rough": 1.0, "metal": 0.0},
	&"plaster_worn": {"meters": 2.5, "rough": 1.0, "metal": 0.0},
}

## Names a generator already uses for a surface, to the kind that draws it. A map document that
## says "wall" or "road" needs no table of its own.
const ALIASES := {
	&"wall": &"plaster", &"floor": &"concrete", &"road": &"asphalt", &"street": &"asphalt",
	&"pavement": &"concrete_clean", &"sidewalk": &"concrete_clean", &"dirt": &"ground",
	&"earth": &"ground", &"lawn": &"grass", &"wood": &"wood_floor", &"planks": &"wood_planks",
	&"tile": &"tile_white", &"tiles": &"tile_white", &"steel": &"metal", &"container": &"rust",
	&"roof": &"corrugated", &"ceiling": &"concrete_clean", &"stone": &"concrete", &"carpet": &"carpet_grey",
}

## Where the textures are. A folder per kind with albedo.jpg, normal.jpg and roughness.jpg.
var root: String = DEFAULT_ROOT

## Optional: maps the path to load onto another one, for a game that rebases paths onto a mount
## ([code]func(path: String) -> String[/code]).
var path_fn: Callable = Callable()

## Scales every kind's metallic value. A game that lays baked light over its map sets this to 0
## on the instance it bakes with: a lightmap holds diffuse light only, and a metallic surface has
## almost no diffuse, so a baked corrugated roof drew nearly black.
var metallic_scale: float = 1.0

## Triplanar blend sharpness: higher is a harder seam on a bevel, lower a smeared one.
var sharpness: float = 4.0

var _cache: Dictionary = {}
var _warned: Dictionary = {}


func _init(p_root: String = DEFAULT_ROOT) -> void:
	root = p_root


## Every kind, sorted.
func kinds() -> PackedStringArray:
	var out := PackedStringArray()
	for k: StringName in KINDS:
		out.append(String(k))
	out.sort()
	return out


## The kind a name resolves to, or empty when it is neither a kind nor an alias.
func resolve(kind: StringName) -> StringName:
	if KINDS.has(kind):
		return kind
	if ALIASES.has(kind):
		return ALIASES[kind]
	return &""


func has_kind(kind: StringName) -> bool:
	return resolve(kind) != &""


## The material for [param kind], or a failure naming the problem ([code]invalid[/code] for a
## kind nobody knows, [code]io[/code] for a texture that did not load).
func try_material(kind: StringName, tint: Color = Color.WHITE) -> DotResult:
	var k := resolve(kind)
	if k == &"":
		return DotResult.fail(DotError.CODE_INVALID, "unknown surface kind '%s'" % kind)
	var key := "%s|%s" % [k, tint.to_html()]
	if _cache.has(key):
		return DotResult.success(_cache[key])

	var spec: Dictionary = KINDS[k]
	var albedo := _load("%s/%s/albedo.jpg" % [root, k])
	var normal := _load("%s/%s/normal.jpg" % [root, k])
	var rough := _load("%s/%s/roughness.jpg" % [root, k])
	if albedo == null or normal == null or rough == null:
		return DotResult.fail(
			DotError.CODE_IO, "surface '%s': a texture did not load from %s" % [k, root]
		)

	var m := StandardMaterial3D.new()
	m.resource_name = String(k)
	m.albedo_texture = albedo
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = normal
	m.roughness_texture = rough
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.roughness = float(spec["rough"])
	m.metallic = float(spec["metal"]) * metallic_scale
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_triplanar_sharpness = sharpness
	# One texture covers [meters] metres: the triplanar UV is world metres times this scale.
	var s := 1.0 / float(spec["meters"])
	m.uv1_scale = Vector3(s, s, s)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_cache[key] = m
	return DotResult.success(m)


## The material for [param kind], and always a material: a kind that is unknown or whose
## texture is missing draws a flat grey and says so once, so one bad word in a map document
## costs a grey wall, not a map.
func material(kind: StringName, tint: Color = Color.WHITE) -> StandardMaterial3D:
	var res := try_material(kind, tint)
	if res.ok:
		return res.value
	if not _warned.has(kind):
		_warned[kind] = true
		DotLog.warn(CHANNEL, "%s; drawing flat grey" % res.error.message)
	var key := "fallback|%s" % tint.to_html()
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.55, 0.55, 0.55) * tint
		m.roughness = 0.8
		_cache[key] = m
	return _cache[key]


## A `material_for` callable for [method DotMapBspMesh.build_node] that draws a converted map with its free
## textures: a surface's `free` key names a surface kind, or a generated flat colour the pack carries as a file
## beside [param dir] (the pack's directory).
func world_material_for(world: DotMapBspMesh, dir: String) -> Callable:
	var generated := {}
	for t: Dictionary in world.licence().get("textures", []):
		if str(t["kind"]) == "generated":
			generated[str(t["key"])] = dir.path_join(str(t["file"]))
	var cache := {}
	return func(rec: Dictionary) -> Material:
		var key := str(rec.get("free", ""))
		if cache.has(key):
			return cache[key]
		var m: Material
		if generated.has(key):
			var sm := StandardMaterial3D.new()
			sm.albedo_texture = ImageTexture.create_from_image(Image.load_from_file(generated[key]))
			sm.uv1_triplanar = true
			sm.uv1_world_triplanar = true
			sm.uv1_scale = Vector3.ONE * 0.4
			m = sm
		else:
			m = material(StringName(key.get_slice(":", 0)))
		cache[key] = m
		return m


## Drops every cached material (a texture quality change, or a test).
func clear() -> void:
	_cache.clear()


func describe() -> Dictionary:
	return {
		"root": root,
		"kinds": kinds().size(),
		"cached": _cache.size(),
		"sharpness": sharpness,
	}


func _load(path: String) -> Texture2D:
	if path_fn.is_valid():
		path = String(path_fn.call(path))
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D
