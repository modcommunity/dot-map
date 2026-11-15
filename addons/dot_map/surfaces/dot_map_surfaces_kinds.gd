extends "dot_map_surfaces_files.gd"

## The kinds, tunables, plain materials and colour helpers of [DotMapSurfaces] (its base script); the world-material pipeline is built on top in [DotMapSurfaces].

const CHANNEL := "dot_map.surfaces"

const DEFAULT_ROOT := "res://addons/dot_map/surfaces"
const LIGHTMAPPED := preload("lightmapped.gdshader")
const BLENDED := preload("blended.gdshader")
const LIQUID := preload("liquid.gdshader")
## Liquid kind to its shader colours: tint, deep tint, sky tint, alpha looking down, glow.
const LIQUIDS := {
	&"water": [Color(0.10, 0.34, 0.42), Color(0.03, 0.12, 0.20), Color(0.62, 0.78, 0.92), 0.5, 0.0],
	&"slime": [Color(0.30, 0.48, 0.08), Color(0.08, 0.18, 0.02), Color(0.70, 0.85, 0.45), 0.8, 0.15],
	&"lava": [Color(1.0, 0.42, 0.05), Color(0.45, 0.04, 0.0), Color(1.0, 0.75, 0.35), 1.0, 2.5],
}

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

## A word in a texture's name to the kind that stands in for it when its PBR set is not installed; first match wins.
## The same table as the converter's `nearest.py`, so a stand-in is what the converter would have chosen.
const NAME_RULES := [
	["snow", &"snow"], ["carpet|carp|crpt|rug", &"carpet_grey"], ["brick|bricks|brk", &"brick"],
	["rust|rusty|corrod", &"rust"], ["corrug|container|shutter", &"corrugated"], ["asphalt|road|street|tarmac|highway", &"asphalt"],
	["checker", &"tile_checker"], ["tile|tiles|tilefloor|bathroom|kitchen", &"tile_white"],
	["parquet|woodfloor|wood_floor|hardwood", &"wood_floor"], ["plank|wood|door|crate|barrel|log|bark|timber|board", &"wood_planks"],
	["grass|lawn|moss|leaf|leaves|foliage|ivy|hedge|bush", &"grass"], ["sand", &"sand"],
	["rock|cliff|stone|cave", &"rock"], ["dirt|mud|gravel|ground|soil|path|terrain", &"ground"],
	["metal|steel|iron|pipe|grate|vent|duct|rail|girder|catwalk|plate|alum|chrome|panel", &"metal"],
	["concrete|cement|conc|cinder|pavement|sidewalk|curb", &"concrete"],
	["plaster|stucco|wallpaper|paint|drywall|wall|ceiling|trim", &"plaster"],
]

## Where the textures are. A folder per kind with albedo.jpg, normal.jpg and roughness.jpg.
var root: String = DEFAULT_ROOT

## Optional: maps the path to load onto another one, for a game that rebases paths onto a mount
## ([code]func(path: String) -> String[/code]).
var path_fn: Callable = Callable()

## Folders (each laid out like [member root]) a texture under [member root] or [constant DEFAULT_ROOT] is looked for in when this build does not carry it.
## The client shell leaves the textures out of its pck and a host adds the mounted surfaces pack's folder here.
static var fallback_roots: PackedStringArray = PackedStringArray()
## One material per world shader, kept so [method warm_shaders_async] compiles each only once.
static var _warm_materials: Array[ShaderMaterial] = []

## Whether a headless build swaps each kind texture for a 4x4 bilinear downsample as it loads. The dummy
## renderer keeps a decoded copy of every texture it never draws: 55 MB for FC's six built-in kinds.
## Collision and navigation read only geometry. False keeps the full textures.
static var shrink_textures_headless := true
## Resolved path -> the 4x4 texture headless hands out, so every material of a kind shares one.
static var _small: Dictionary = {}

## Scales every kind's metallic value. A game that lays baked light over its map sets this to 0
## on the instance it bakes with: a lightmap holds diffuse light only, and a metallic surface has
## almost no diffuse, so a baked corrugated roof drew nearly black.
var metallic_scale: float = 1.0

## [method world_material_for] tints each replacement towards the original texture's average
## colour; off draws every kind's photo as it is (which read pale beside dark source wood and rock).
var match_original: bool = true

## Draw a surface with the map's own texture where its record names one (`orig`, written by `dot-map-convert` `regen --orig-textures` into an internal `_orig` pack): the file beside the pack, at the mesh's own UVs (source coordinate over source size, so one repeat is the original's). A surface without one, or whose file is missing, keeps its free replacement. INTERNAL packs only: never published.
var use_original_textures: bool = false

## What [method world_material_for] draws water faces with (a game's own water shader); null is [method liquid_material] by the face's name.
var water_material: Material = null

## Told [code]func(label: String)[/code] as [method world_material_for_async] passes its steps and of each material dearer than [constant SLOW_MATERIAL_USEC]; a game's frame trace hangs them on its frames. Unset tells no one.
var on_step: Callable = Callable()
const SLOW_MATERIAL_USEC := 8000
## Workers that decode the world's texture files ahead of the material pass ([code]map_load_threads[/code]): 0 inline, -1 automatic.
var load_threads: int = DotMapParallelBuild.default_workers
## Draws a map that carries its author's baked lighting with it (the lightmapped shader, unshaded);
## off draws every map with [method try_material]'s lit materials.
var use_lightmap: bool = true

## Brightness of a light-emitting surface (SURF_LIGHT) in the lightmapped path.
var emissive_energy: float = 1.5

## The tint range [method original_tint] keeps to: a black original still shows its kind.
const TINT_MIN := 0.25
const TINT_MAX := 1.3
## Darkest albedo a stand-in surface gets; an author's black face is lit by the baked light, so a true black would stay black however bright the room.
const STAND_IN_FLOOR := 0.2

## Triplanar blend sharpness: higher is a harder seam on a bevel, lower a smeared one.
var sharpness: float = 4.0

var _cache: Dictionary = {}
var _warned: Dictionary = {}
var _rules: Array = []
## Keys of the PBR sets [method world_material_for] found no files for, drawn with [method stand_in_kind] instead.
var missing_sets: PackedStringArray = PackedStringArray()


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


## Pulls [param c] toward its own mean until its brightest and dimmest channels are within [param ratio] (0 or less: unchanged); the mean, so the luminance, is kept. The shader's twin, and the floor light's and an actor's ambient's one helper.
static func limit_chroma(c: Vector3, ratio: float) -> Vector3:
	if ratio <= 0.0:
		return c
	var g := (c.x + c.y + c.z) / 3.0
	var denom := maxf(c.x, maxf(c.y, c.z)) + (ratio - 1.0) * g - ratio * minf(c.x, minf(c.y, c.z))
	if g <= 0.0 or denom <= 0.0:
		return c
	var k := minf(1.0, (ratio - 1.0) * g / denom)
	return Vector3(g, g, g) + (c - Vector3(g, g, g)) * k


## CPU twin of the roll-off in lightmapped.gdshader (a baked value above 1 eases toward 1.5 and bleaches); the demo pins both.
static func light_rolloff(light: Vector3) -> Vector3:
	var peak := maxf(light.x, maxf(light.y, light.z))
	if peak <= 1.0:
		return light
	var bleach := clampf((peak - 1.0) / 3.0, 0.0, 0.6)
	var out := light * ((1.0 + 0.5 * (1.0 - exp(-(peak - 1.0) / 0.5))) / peak)
	var grey := (out.x + out.y + out.z) * 0.3333
	return out.lerp(Vector3(grey, grey, grey), bleach)


## The liquid a surface named [param name] is: &"lava", &"slime" or &"water".
static func liquid_kind(name: String) -> StringName:
	var n := name.to_lower()
	if n.contains("lava") and not n.contains("lavator"):
		return &"lava"
	if n.contains("slime") or n.contains("sludge") or n.contains("toxic") or n.contains("acid"):
		return &"slime"
	return &"water"


## The moving, translucent surface (liquid.gdshader) a converted map's [param kind] faces are drawn with,
## one per kind. A flat tinted sheet read as a blue floor, not water. [param lip] is the foam width at a volume's edge.
func liquid_material(kind: StringName = &"water", lip: float = 0.0) -> ShaderMaterial:
	var key := "liquid|%s|%s" % [kind, lip]
	if not _cache.has(key):
		var look: Array = LIQUIDS.get(kind, LIQUIDS[&"water"])
		var m := ShaderMaterial.new()
		m.resource_name = String(kind)
		m.shader = LIQUID
		m.set_shader_parameter("tint", look[0])
		m.set_shader_parameter("deep_tint", look[1])
		m.set_shader_parameter("sky_tint", look[2])
		m.set_shader_parameter("alpha_down", look[3])
		m.set_shader_parameter("alpha_grazing", maxf(look[3], 0.9))
		m.set_shader_parameter("glow", look[4])
		m.set_shader_parameter("lip_width", lip)
		if kind == &"lava":
			m.set_shader_parameter("flow_speed", 0.25)
			m.set_shader_parameter("roughness_base", 0.6)
		_cache[key] = m
	return _cache[key]


## [method liquid_material] for water, kept for callers of the old name.
func default_water() -> ShaderMaterial:
	return liquid_material(&"water")


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
		path = _from_fallback(path)
		if path.is_empty():
			return null
	if not (shrink_textures_headless and DotPlatform.is_headless()):
		return load(path) as Texture2D
	if _small.has(path):
		return _small[path] as Texture2D
	var tex := load(path) as Texture2D
	if tex == null:
		return null
	_small[path] = _shrunk(tex)
	return _small[path] as Texture2D


## [param tex] as a 4x4 bilinear downsample, or itself when it is that small already or its image cannot be read.
static func _shrunk(tex: Texture2D) -> Texture2D:
	if tex.get_width() <= 4 and tex.get_height() <= 4:
		return tex
	var img := tex.get_image()
	if img == null or img.is_empty() or (img.is_compressed() and img.decompress() != OK):
		return tex
	img.resize(4, 4, Image.INTERPOLATE_BILINEAR)
	return ImageTexture.create_from_image(img)


func _from_fallback(path: String) -> String:
	var base := root if path.begins_with(root + "/") else DEFAULT_ROOT
	if not path.begins_with(base + "/"):
		return ""
	var rel := path.substr(base.length())
	for r in fallback_roots:
		var cand := r.trim_suffix("/") + rel
		if ResourceLoader.exists(cand):
			return cand
	return ""
