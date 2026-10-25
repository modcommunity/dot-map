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
const LIGHTMAPPED := preload("lightmapped.gdshader")

## Kind to what draws it. [code]meters[/code] is the width one texture covers in the world.
## [code]rough[/code] scales the roughness map (a photo's own roughness is a little glossy for
## a mid-2000s look under one hard light); [code]metal[/code] is the metallic value.
const KINDS := {
	&"concrete": {"meters": 2.5, "rough": 1.0, "metal": 0.0, "mean": [0.567, 0.531, 0.452]},
	&"concrete_clean": {"meters": 3.0, "rough": 1.0, "metal": 0.0, "mean": [0.723, 0.723, 0.723]},
	&"plaster": {"meters": 2.5, "rough": 1.0, "metal": 0.0, "mean": [0.745, 0.748, 0.732]},
	&"brick": {"meters": 3.0, "rough": 1.0, "metal": 0.0, "mean": [0.522, 0.415, 0.327]},
	&"tile_white": {"meters": 2.4, "rough": 1.0, "metal": 0.0, "mean": [0.973, 0.972, 0.971]},
	&"tile_dark": {"meters": 3.0, "rough": 1.0, "metal": 0.0, "mean": [0.209, 0.211, 0.214]},
	&"tile_checker": {"meters": 3.0, "rough": 1.0, "metal": 0.0, "mean": [0.333, 0.295, 0.265]},
	&"wood_floor": {"meters": 1.6, "rough": 1.0, "metal": 0.0, "mean": [0.359, 0.294, 0.224]},
	&"wood_planks": {"meters": 1.2, "rough": 1.0, "metal": 0.0, "mean": [0.724, 0.596, 0.411]},
	&"asphalt": {"meters": 3.0, "rough": 1.0, "metal": 0.0, "mean": [0.271, 0.265, 0.264]},
	&"metal": {"meters": 2.0, "rough": 1.0, "metal": 0.6, "mean": [0.433, 0.429, 0.418]},
	&"rust": {"meters": 2.0, "rough": 1.0, "metal": 0.3, "mean": [0.547, 0.299, 0.152]},
	&"corrugated": {"meters": 3.0, "rough": 1.0, "metal": 0.5, "mean": [0.509, 0.508, 0.506]},
	&"grass": {"meters": 2.0, "rough": 1.0, "metal": 0.0, "mean": [0.378, 0.426, 0.190]},
	&"ground": {"meters": 3.0, "rough": 1.0, "metal": 0.0, "mean": [0.598, 0.576, 0.343]},
	&"carpet_grey": {"meters": 2.0, "rough": 1.0, "metal": 0.0, "mean": [0.578, 0.569, 0.544]},
	&"carpet_pattern": {"meters": 2.0, "rough": 1.0, "metal": 0.0, "mean": [0.448, 0.451, 0.454]},
	&"carpet_red": {"meters": 2.0, "rough": 1.0, "metal": 0.0, "mean": [0.657, 0.359, 0.353]},
	&"carpet_blue": {"meters": 2.0, "rough": 1.0, "metal": 0.0, "mean": [0.205, 0.231, 0.284]},
	&"snow": {"meters": 3.0, "rough": 1.0, "metal": 0.0, "mean": [0.928, 0.953, 0.977]},
	&"rock": {"meters": 4.0, "rough": 1.0, "metal": 0.0, "mean": [0.550, 0.546, 0.537]},
	&"sand": {"meters": 3.0, "rough": 1.0, "metal": 0.0, "mean": [0.709, 0.620, 0.443]},
	&"stone_block": {"meters": 3.0, "rough": 1.0, "metal": 0.0, "mean": [0.440, 0.426, 0.376]},
	&"roof_clay": {"meters": 2.0, "rough": 1.0, "metal": 0.0, "mean": [0.562, 0.358, 0.265]},
	&"ceiling_tile": {"meters": 2.4, "rough": 1.0, "metal": 0.0, "mean": [0.942, 0.942, 0.942]},
	&"plaster_worn": {"meters": 2.5, "rough": 1.0, "metal": 0.0, "mean": [0.843, 0.830, 0.817]},
	&"wallpaper": {"meters": 2.0, "rough": 1.0, "metal": 0.0, "mean": [0.877, 0.881, 0.861]},
	&"wallpaper_decrepit": {"meters": 2.0, "rough": 1.0, "metal": 0.0, "mean": [0.466, 0.418, 0.367]},
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

## [method world_material_for] tints each replacement towards the original texture's average
## colour; off draws every kind's photo as it is (which read pale beside dark source wood and rock).
var match_original: bool = true

## What [method world_material_for] draws water faces with (a game's own water shader); null is [method default_water].
var water_material: Material = null

## Draws a map that carries its author's baked lighting with it (the lightmapped shader, unshaded);
## off draws every map with [method try_material]'s lit materials.
var use_lightmap: bool = true

## Brightness of a light-emitting surface (SURF_LIGHT) in the lightmapped path.
var emissive_energy: float = 1.5

## The tint range [method original_tint] keeps to: a black original still shows its kind.
const TINT_MIN := 0.25
const TINT_MAX := 1.3

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
		if rec.get("water", false):
			return water_material if water_material != null else default_water()
		var lit := use_lightmap and world.has_lightmap() and rec.has("lightmap_page") and not rec.has("glass")
		var free := str(rec.get("free", ""))
		var tint := Color.WHITE
		# A blend's average is two textures' (grass and rock), never the one drawn: left untinted.
		var blend := str(rec.get("material", "")).get_file().to_lower().begins_with("blend")
		if match_original and not generated.has(free) and not blend:
			tint = original_tint(StringName(free.get_slice(":", 0)), rec.get("colour", []))
		var key := "%s|%s|%s|%s" % [free, tint.to_html(), rec.get("lightmap_page", -1) if lit else -1, rec.get("emissive", false)]
		if cache.has(key):
			return cache[key]
		var m: Material
		if lit:
			m = _lightmapped(world, rec, free, tint, generated.get(free, ""))
		elif generated.has(free):
			var sm := StandardMaterial3D.new()
			sm.albedo_texture = ImageTexture.create_from_image(Image.load_from_file(generated[free]))
			sm.uv1_triplanar = true
			sm.uv1_world_triplanar = true
			sm.uv1_scale = Vector3.ONE * 0.4
			m = sm
		else:
			m = material(StringName(free.get_slice(":", 0)), tint)
		cache[key] = m
		return m


func _lightmapped(world: DotMapBspMesh, rec: Dictionary, free: String, tint: Color, generated_file: String) -> Material:
	var kind := StringName(free.get_slice(":", 0))
	var tex: Texture2D = null
	var metres := 2.5
	if not generated_file.is_empty():
		tex = ImageTexture.create_from_image(Image.load_from_file(generated_file))
	else:
		var k := resolve(kind)
		if k != &"":
			tex = _load("%s/%s/albedo.jpg" % [root, k])
			metres = float(KINDS[k]["meters"])
	if tex == null:
		return material(kind, tint)
	var m := ShaderMaterial.new()
	m.resource_name = free
	m.shader = LIGHTMAPPED
	m.set_shader_parameter("albedo_tex", tex)
	m.set_shader_parameter("lightmap", world.lightmap_page(int(rec["lightmap_page"])))
	m.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	m.set_shader_parameter("metres", metres)
	m.set_shader_parameter("sharpness", sharpness)
	m.set_shader_parameter("exposure", world.lightmap_scale())
	if rec.get("emissive", false):
		m.set_shader_parameter("emissive", emissive_energy)
	return m


## The sea a converted map's water faces are drawn with when [member water_material] is not set:
## a water texture's average is a grey dummy, and drawn opaque it was a pale gravel floor.
func default_water() -> StandardMaterial3D:
	if not _cache.has("water"):
		var m := StandardMaterial3D.new()
		m.resource_name = "water"
		m.albedo_color = Color(0.06, 0.24, 0.28, 0.88)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.08
		m.metallic_specular = 0.7
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_cache["water"] = m
	return _cache["water"]


## The tint that brings [param kind]'s photo to the original texture's average [param colour]
## (sRGB, the converter's `colour`): its brightness fully, its hue half way, so a blend texture's
## average does not turn grass grey. White for an unknown kind or no colour.
func original_tint(kind: StringName, colour: Variant) -> Color:
	var k := resolve(kind)
	if k == &"" or not colour is Array or (colour as Array).size() < 3:
		return Color.WHITE
	var mean: Array = KINDS[k]["mean"]
	var want := Color(float(colour[0]), float(colour[1]), float(colour[2]))
	var have := Color(float(mean[0]), float(mean[1]), float(mean[2]))
	var lum_w := maxf(want.get_luminance(), 0.01)
	var lum_h := maxf(have.get_luminance(), 0.01)
	var gain := clampf(lum_w / lum_h, TINT_MIN, TINT_MAX)
	var out := Color.WHITE
	for i in 3:
		var hue: float = (want[i] / lum_w) / maxf(have[i] / lum_h, 0.01)
		# Quantised so a map's few hundred surfaces share a few dozen materials.
		out[i] = snappedf(clampf(gain * lerpf(1.0, hue, 0.5), TINT_MIN, TINT_MAX), 1.0 / 32.0)
	return out


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
