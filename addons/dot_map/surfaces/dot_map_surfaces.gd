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

## Scales every kind's metallic value. A game that lays baked light over its map sets this to 0
## on the instance it bakes with: a lightmap holds diffuse light only, and a metallic surface has
## almost no diffuse, so a baked corrugated roof drew nearly black.
var metallic_scale: float = 1.0

## [method world_material_for] tints each replacement towards the original texture's average
## colour; off draws every kind's photo as it is (which read pale beside dark source wood and rock).
var match_original: bool = true

## What [method world_material_for] draws water faces with (a game's own water shader); null is [method liquid_material] by the face's name.
var water_material: Material = null

## Draws a map that carries its author's baked lighting with it (the lightmapped shader, unshaded);
## off draws every map with [method try_material]'s lit materials.
var _textures: Dictionary = {}
## Workers that decode the world's texture files ahead of the material pass ([code]map_load_threads[/code]): 0 inline, -1 automatic.
var load_threads: int = DotMapParallelBuild.default_workers
var use_lightmap: bool = true
## Folder of the shared PBR sets (`<id>/<tier>/*.webp`) when the game delivers them apart from the pack; empty reads the folder the manifest names, beside the pack.
var pbr_library: String = ""
## Folders searched for a set before [member pbr_library], in order: a map's own slice and the shared slices it depends on.
var pbr_libraries: PackedStringArray = PackedStringArray()
var _set_roots: Dictionary = {}

## Brightness of a light-emitting surface (SURF_LIGHT) in the lightmapped path.
var emissive_energy: float = 1.5

## The tint range [method original_tint] keeps to: a black original still shows its kind.
const TINT_MIN := 0.25
const TINT_MAX := 1.3
## Darkest albedo a stand-in surface gets; an author's black face is lit by the baked light, so a true black would stay black however bright the room.
const STAND_IN_FLOOR := 0.2

## The strongest brightest-to-dimmest channel ratio a flat stand-in keeps: a face's average can be a saturated blue that reads as a missing-texture error.
const STAND_IN_MAX_RATIO := 1.6

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


## A `material_for` callable for [method DotMapBspMesh.build_node] that draws a converted map with its free
## textures: a surface's `free` key names a surface kind, or a generated flat colour the pack carries as a file
## beside [param dir] (the pack's directory).
func world_material_for(world: DotMapBspMesh, dir: String) -> Callable:
	var generated := {}
	var library := {}
	var store := str(world.licence().get("pbr_store", ""))
	for t: Dictionary in world.licence().get("textures", []):
		if str(t["kind"]) == "generated":
			generated[str(t["key"])] = dir.path_join(str(t["file"]))
		elif str(t["kind"]) == "pbr":
			library[str(t["key"])] = _pbr_dir(dir, store, t)
	var stand_in := {}
	for key: String in library.keys():
		if not _has_set(library[key]):
			stand_in[key] = _pack_fallback(dir, key, world.licence())
			library.erase(key)
			if not missing_sets.has(key):
				missing_sets.append(key)
	if not stand_in.is_empty():
		DotLog.debug(CHANNEL, "PBR sets not installed; each is drawn as a stand-in kind in its faces' own colour", {"sets": stand_in.size()})
	_prefetch(world, generated, library)
	var cache := {}
	return func(rec: Dictionary) -> Material:
		if rec.get("water", false):
			return water_material if water_material != null else liquid_material(liquid_kind(str(rec.get("material", ""))))
		var lit := use_lightmap and world.has_lightmap() and rec.has("lightmap_page") and not rec.has("glass")
		var free := str(rec.get("free", ""))
		var tint := Color.WHITE
		# A blend's average is two textures' (grass and rock), never the one drawn: left untinted.
		var blend := str(rec.get("material", "")).get_file().to_lower().begins_with("blend")
		if match_original and not generated.has(free) and not library.has(free) and not blend:
			tint = original_tint(StringName(free.get_slice(":", 0)), rec.get("colour", []))
		if stand_in.has(free):
			return _stand_in_material(world, rec, stand_in[free], cache)
		var free2 := str(rec.get("free2", ""))
		if not library.has(free2):
			free2 = ""
		var key := "%s|%s|%s|%s|%s" % [free, free2, tint.to_html(), rec.get("lightmap_page", -1) if lit else -1, rec.get("emissive", false)]
		if cache.has(key):
			return cache[key]
		var m: Material
		if lit:
			var file: String = generated.get(free, "")
			m = _lightmapped(world, rec, free, tint, file, library.get(free, ""))
			if not free2.is_empty() and m is ShaderMaterial:
				m.set_shader_parameter("albedo2_tex", _set_texture(library[free2], "albedo"))
				m.set_shader_parameter("has_blend", true)
		elif library.has(free):
			m = _pbr_material(library[free], free)
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


## Reads the texture files the world's surfaces use before the serial material pass: disk files decoded on workers, imported ones through [ResourceLoader]'s own threads. Nothing happens inline.
func _prefetch(world: DotMapBspMesh, generated: Dictionary, library: Dictionary) -> void:
	if DotParallel.resolve_workers(load_threads) == 0:
		return
	var used := {}
	for rec: Dictionary in world.surfaces:
		used[str(rec.get("free", ""))] = true
		used[str(rec.get("free2", ""))] = true
	var files := PackedStringArray()
	for key: String in generated:
		if used.has(key) and use_lightmap and world.has_lightmap():    # the unlit branch decodes its own, unmipped
			files.append(generated[key])
	for key: String in library:
		if used.has(key):
			for part in ["albedo", "normal", "roughness", "ao"]:
				var found := _set_file(library[key], part)
				if not found.is_empty():
					files.append(found)
	var disk := PackedStringArray()
	var imported := PackedStringArray()
	for p in files:
		if _textures.has(p):
			continue
		if p.begins_with("res://") and ResourceLoader.exists(p):
			imported.append(p)
			ResourceLoader.load_threaded_request(p)
		else:
			disk.append(p)
	_textures.merge(DotMapParallelBuild.textures(disk, load_threads))
	for p in imported:
		_textures[p] = ResourceLoader.load_threaded_get(p) as Texture2D


## The first existing file of the set's [param part] (webp, then jpg), or "".
func _set_file(dir: String, part: String) -> String:
	for ext in ["webp", "jpg"]:
		var p := dir.path_join("%s.%s" % [part, ext])
		if FileAccess.file_exists(p) or ResourceLoader.exists(p):
			return p
	return ""


## The kind that stands in for a texture named [param name] (a PBR set id or a source path) when its files are missing; &"" when no word fits.
func stand_in_kind(name: String) -> StringName:
	if _rules.is_empty():
		for r: Array in NAME_RULES:
			var re := RegEx.new()
			re.compile("(?<![a-z])(?:%s)" % r[0])
			_rules.append([re, r[1]])
	var parts := name.to_lower().replace("\\", "/").split("/")
	var text := "/".join(parts.slice(maxi(parts.size() - 2, 0)))
	for r: Array in _rules:
		if (r[0] as RegEx).search(text) != null:
			return r[1]
	return &""


## What a missing set is drawn as: `{file}` for the pack's own low-resolution albedo, else `{kind}` (a photo kind, or &"" for flat colour).
func _pack_fallback(dir: String, key: String, licence: Dictionary) -> Dictionary:
	for t: Dictionary in licence.get("textures", []):
		if str(t.get("key", "")) != key:
			continue
		var small := str(t.get("fallback_file", ""))
		if not small.is_empty() and (FileAccess.file_exists(dir.path_join(small)) or ResourceLoader.exists(dir.path_join(small))):
			return {"file": dir.path_join(small), "colour": t.get("colour", [])}
		var kind := stand_in_kind(str(t.get("file", "")).get_file())
		for src: Variant in t.get("sources", []):
			if kind == &"":
				kind = stand_in_kind(str(src))
		if kind != &"" and _load("%s/%s/albedo.jpg" % [root, resolve(kind)]) == null:
			kind = &""
		return {"kind": kind, "colour": t.get("colour", [])}
	return {"kind": &"", "colour": []}


## [param c] pulled toward its grey until its channels are within [param max_ratio].
static func _desaturated(c: Color, max_ratio: float) -> Color:
	var hi := maxf(c.r, maxf(c.g, c.b))
	var lo := minf(c.r, minf(c.g, c.b))
	if hi <= max_ratio * lo:
		return c
	var g := (c.r + c.g + c.b) / 3.0
	var k := clampf((max_ratio - 1.0) * g / maxf(hi - max_ratio * lo + (max_ratio - 1.0) * g, 0.0001), 0.0, 1.0)
	return Color(g + (c.r - g) * k, g + (c.g - g) * k, g + (c.b - g) * k)


## A face whose PBR set is missing: the pack's small albedo, else the stand-in kind tinted to the face's average colour, else that colour flat; lit by the map's lightmap when it has one.
func _stand_in_material(world: DotMapBspMesh, rec: Dictionary, fb: Dictionary, cache: Dictionary) -> Material:
	var colour: Variant = rec.get("colour", fb.get("colour", []))
	if not colour is Array or (colour as Array).size() < 3:
		colour = [0.5, 0.5, 0.5]
	var kind: StringName = fb.get("kind", &"")
	var tint := Color.WHITE
	if not fb.has("file"):
		tint = original_tint(kind, colour) if kind != &"" else Color(float(colour[0]), float(colour[1]), float(colour[2]))
		if kind == &"":
			tint = _desaturated(tint, STAND_IN_MAX_RATIO)
			tint = Color(maxf(tint.r, STAND_IN_FLOOR), maxf(tint.g, STAND_IN_FLOOR), maxf(tint.b, STAND_IN_FLOOR))
	var lit := use_lightmap and world.has_lightmap() and rec.has("lightmap_page") and not rec.has("glass")
	var key := "stand_in|%s|%s|%s|%s" % [fb.get("file", kind), tint.to_html(), rec.get("lightmap_page", -1) if lit else -1, rec.get("emissive", false)]
	if cache.has(key):
		return cache[key]
	var m: Material
	if lit:
		if fb.has("file"):
			m = _lightmapped(world, rec, "stand_in", tint, str(fb["file"]))
		elif kind != &"":
			m = _lightmapped(world, rec, String(kind), tint, "")
		else:
			m = _lightmapped(world, rec, "flat", tint, "", "", _white())
	elif fb.has("file"):
		var sm := StandardMaterial3D.new()
		sm.albedo_texture = _file_texture(str(fb["file"]))
		sm.uv1_triplanar = true
		sm.uv1_world_triplanar = true
		sm.uv1_scale = Vector3.ONE * 0.5
		m = sm
	elif kind != &"":
		m = material(kind, tint)
	else:
		var flat := StandardMaterial3D.new()
		flat.albedo_color = tint
		flat.roughness = 0.9
		m = flat
	cache[key] = m
	return m


func _white() -> Texture2D:
	if not _textures.has("white"):
		var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
		img.fill(Color.WHITE)
		_textures["white"] = ImageTexture.create_from_image(img)
	return _textures["white"]


## A library set shipped in the pack (`pbr/<id>/`): albedo, normal, roughness and AO, world-triplanar.
func _pbr_material(dir: String, key: String) -> StandardMaterial3D:
	var sm := StandardMaterial3D.new()
	sm.resource_name = key
	sm.uv1_triplanar = true
	sm.uv1_world_triplanar = true
	sm.uv1_scale = Vector3.ONE * 0.5
	sm.albedo_texture = _set_texture(dir, "albedo")
	var n := _set_texture(dir, "normal")
	if n != null:
		sm.normal_enabled = true
		sm.normal_texture = n
	var r := _set_texture(dir, "roughness")
	if r != null:
		sm.roughness_texture = r
		sm.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	var ao := _set_texture(dir, "ao")
	if ao != null:
		sm.ao_enabled = true
		sm.ao_texture = ao
		sm.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	return sm


## The folder of the PBR set [param t] names: `<library>/<id>/<tier>` for a shared store, the pack's own `pbr/<id>` for an older one.
func _pbr_dir(dir: String, store: String, t: Dictionary) -> String:
	var id := str(t["file"]).get_file()
	if store.is_empty() and pbr_library.is_empty() and pbr_libraries.is_empty():
		return dir.path_join(str(t["file"]))
	var tier := str(t.get("tier", "1k"))
	for lib in pbr_libraries:
		var cand := lib.path_join(id).path_join(tier)
		if _has_set(cand):
			return cand
	var root := pbr_library if not pbr_library.is_empty() else dir.path_join(store).simplify_path()
	return root.path_join(id).path_join(tier)


func _has_set(dir: String) -> bool:
	if not _set_roots.has(dir):
		var found := false
		for ext in ["webp", "jpg"]:
			var p := dir.path_join("albedo." + ext)
			found = found or FileAccess.file_exists(p) or ResourceLoader.exists(p)
		_set_roots[dir] = found
	return _set_roots[dir]


func _set_texture(dir: String, name: String) -> Texture2D:
	var p := _set_file(dir, name)
	return _file_texture(p) if not p.is_empty() else null


func _file_texture(path: String) -> Texture2D:
	if _textures.has(path):
		return _textures[path]
	# A mounted store slice holds the engine's import (VRAM-compressed, mipmapped), never the source file.
	if path.begins_with("res://") and ResourceLoader.exists(path):
		var imported := load(path) as Texture2D
		_textures[path] = imported
		return imported
	var img := Image.load_from_file(path)
	if img == null:
		return null
	slim_image(img, path)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_textures[path] = tex
	return tex


## Drops the channels a set's [param path] part never samples: roughness and AO keep red, a normal map red and green
## (both shaders rebuild z). A raw 1k set decodes to 4 MB per map, and a big map draws hundreds of sets.
static func slim_image(img: Image, path: String) -> void:
	if img.is_compressed():
		return
	var part := path.get_file().get_basename()
	if part in ["roughness", "ao"] and img.get_format() != Image.FORMAT_R8:
		img.convert(Image.FORMAT_R8)
	elif part == "normal" and img.get_format() != Image.FORMAT_RG8:
		img.convert(Image.FORMAT_RG8)


func _lightmapped(world: DotMapBspMesh, rec: Dictionary, free: String, tint: Color, generated_file: String, set_dir: String = "", texture: Texture2D = null) -> Material:
	var kind := StringName(free.get_slice(":", 0))
	var tex: Texture2D = texture
	var metres := 2.5
	if tex == null and not set_dir.is_empty():
		tex = _set_texture(set_dir, "albedo")
		metres = 2.0
	elif tex == null and not generated_file.is_empty():
		tex = _file_texture(generated_file)
	elif tex == null:
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
	if not set_dir.is_empty():
		for pair in [["normal", "normal_tex"], ["roughness", "rough_tex"], ["ao", "ao_tex"]]:
			var pt := _set_texture(set_dir, pair[0])
			if pt != null:
				m.set_shader_parameter(pair[1], pt)
				m.set_shader_parameter("has_" + pair[0], true)
	m.set_shader_parameter("sharpness", sharpness)
	m.set_shader_parameter("exposure", world.lightmap_scale())
	var fl := world.light_floor()
	m.set_shader_parameter("floor_light", Vector3(fl.r, fl.g, fl.b))
	if rec.get("emissive", false):
		m.set_shader_parameter("emissive", emissive_energy)
	return m


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
		return null
	return load(path) as Texture2D
