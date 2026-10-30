extends RefCounted

## The reading, caching, lightmap and mesh-building half of [DotMapBspMesh]; split out only to keep each file small.

const CHANNEL := "dot_map.bsp_mesh"

const FORMAT := "dot-bsp-mesh"
## Version 2 adds a second UV set per surface and the manifest's [code]lightmap[/code] atlas pages; version 1 maps read as before.
const VERSION := 2

## The renderer's limit on surfaces in one mesh; a chunk with more is split over meshes.
const MAX_SURFACES := 256

## Model 0 is the world; the rest are brush entities, one model each.
const WORLD := 0

var manifest: Dictionary = {}
var surfaces: Array = []
var hulls: Array = []
var source_path: String = ""
## Takes a glass surface record, returns its [Material]; the built-in [method glass_material] when unset.
var glass_material_for: Callable = Callable()
## Metres a stand-in prop is drawn to per metre of its longest side, never under
## [member prop_view_min]: a can is gone at 30 m, a shelf at 120. 0 draws every prop at any range.
var prop_view_per_metre: float = 60.0
var prop_view_min: float = 30.0
## Workers for the pure-CPU build stages ([code]map_load_threads[/code]): 0 inline, -1 automatic, never on the web. The output is identical.
var load_threads: int = DotMapParallelBuild.default_workers

var _blob: PackedByteArray = PackedByteArray()
var _movers: Dictionary = {}
var _pages: Dictionary = {}
var _ambient: PackedFloat32Array = PackedFloat32Array()
var _floor_mean: Dictionary = {}
var _entities: DotMapEntities = null
## Built shapes by model (and kinds), shared by every body made from this mesh: a shape is a read-only resource.
var _hull_cache: Dictionary = {}
var _concave_cache: Dictionary = {}


## Loaded meshes kept per prefix so a round-start rebuild of the same stage skips the read, hash and
## decompress; keyed on both files' modification times so a regenerated map is read again.
static var cache_meshes := true
static var cache_limit := 24
static var _cache: Dictionary = {}


## Forgets every cached mesh (and the shapes each holds).
static func clear_cache() -> void:
	_cache.clear()


## Reads [code]<prefix>.json[/code] and [code]<prefix>.bin[/code]; the result is shared with every
## other caller of the same prefix while [member cache_meshes] is on, so treat it as read-only.
static func load_prefix(prefix: String) -> DotResult:
	var json_path := prefix + ".json"
	if not FileAccess.file_exists(json_path):
		return DotResult.fail(DotError.CODE_IO, "no mesh manifest", json_path)
	var stamp := str(FileAccess.get_modified_time(json_path)) + ":" + str(FileAccess.get_modified_time(prefix + ".bin"))
	var hit: Dictionary = _cache.get(prefix, {})
	if cache_meshes and hit.get("stamp") == stamp:
		return DotResult.success(hit["mesh"])
	var res := _read_prefix(prefix, json_path)
	if res.ok and cache_meshes:
		if _cache.size() >= cache_limit and not _cache.has(prefix):
			_cache.erase(_cache.keys()[0])
		_cache[prefix] = {"stamp": stamp, "mesh": res.value}
	return res


static func _read_prefix(prefix: String, json_path: String) -> DotResult:
	var text := FileAccess.get_file_as_string(json_path)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return DotResult.fail(DotError.CODE_PARSE, "mesh manifest is not a JSON object", json_path)
	var bin_name: String = str((parsed as Dictionary).get("bin", {}).get("file", prefix.get_file() + ".bin"))
	var bin_path := prefix.get_base_dir().path_join(bin_name)
	if not FileAccess.file_exists(bin_path):
		return DotResult.fail(DotError.CODE_IO, "no mesh data", bin_path)
	var res := from_data(parsed, FileAccess.get_file_as_bytes(bin_path))
	if res.ok:
		(res.value as DotMapBspMesh).source_path = prefix
	return res if res.ok else res.wrap("loading " + prefix)


## Builds from a parsed manifest and the stored .bin bytes (as delivered: gzip'd or not).
static func from_data(doc: Dictionary, stored: PackedByteArray) -> DotResult:
	if str(doc.get("format", "")) != FORMAT:
		return DotResult.fail(DotError.CODE_INVALID, "not a %s manifest" % FORMAT, str(doc.get("format", "")))
	if int(doc.get("version", 0)) > VERSION:
		return DotResult.fail(DotError.CODE_VERSION, "mesh manifest is newer than this reader",
				"%s > %d" % [doc.get("version"), VERSION])
	var info: Dictionary = doc.get("bin", {})
	var want := str(info.get("sha256", ""))
	if not want.is_empty():
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update(stored)
		var got := ctx.finish().hex_encode()
		if got != want:
			return DotResult.fail(DotError.CODE_INTEGRITY, "mesh data does not match its manifest",
					"%s != %s" % [got, want])
	var blob := stored
	if str(info.get("compression", "")) == "gzip":
		blob = stored.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	if blob.size() != int(info.get("bytes", blob.size())):
		return DotResult.fail(DotError.CODE_PARSE, "mesh data is the wrong size",
				"%d != %s" % [blob.size(), info.get("bytes")])
	var m := DotMapBspMesh.new()
	m.manifest = doc
	m.surfaces = doc.get("surfaces", [])
	m.hulls = doc.get("hulls", [])
	m._blob = blob
	for page: Dictionary in doc.get("lightmap", {}).get("pages", []):
		var bytes := 4 * int(page.get("width", 0)) * int(page.get("height", 0))
		if not m._fits(page, bytes, "offset"):
			return DotResult.fail(DotError.CODE_PARSE, "a lightmap page points outside the mesh data")
	for rec: Dictionary in doc.get("movers", []):
		var mi: Variant = rec.get("model")
		if mi is float or mi is int:        # a mover with no brushes of its own has a null model
			m._movers[int(mi)] = rec
	for rec: Dictionary in m.surfaces:
		if not m._fits(rec, 3 * 4 * int(rec.get("vertex_count", 0)), "position_offset") \
				or not m._fits(rec, 3 * 4 * int(rec.get("vertex_count", 0)), "normal_offset") \
				or not m._fits(rec, 2 * 4 * int(rec.get("vertex_count", 0)), "uv_offset") \
				or (rec.has("uv2_offset") and not m._fits(rec, 2 * 4 * int(rec.get("vertex_count", 0)), "uv2_offset")) \
				or not m._fits(rec, 4 * int(rec.get("index_count", 0)), "index_offset"):
			return DotResult.fail(DotError.CODE_PARSE, "a surface points outside the mesh data", str(rec.get("material")))
	for rec: Dictionary in m.hulls:
		if not m._fits(rec, 12 * int(rec.get("point_count", 0)), "point_offset"):
			return DotResult.fail(DotError.CODE_PARSE, "a hull points outside the mesh data", str(rec.get("brush")))
	DotLog.debug(CHANNEL, "mesh read", {"name": doc.get("name"), "surfaces": m.surfaces.size(),
			"hulls": m.hulls.size(), "bytes": blob.size()})
	return DotResult.success(m)


func _fits(rec: Dictionary, length: int, key: String) -> bool:
	var at := int(rec.get(key, -1))
	return at >= 0 and at + length <= _blob.size()


## Every model with something drawn or solid, world first.
func models() -> PackedInt32Array:
	var seen := {}
	for rec: Dictionary in surfaces:
		seen[int(rec["model"])] = true
	for rec: Dictionary in hulls:
		seen[int(rec["model"])] = true
	var out := PackedInt32Array(seen.keys())
	out.sort()
	return out


## The entities of this map (movers, volumes, links, data), built on first use.
func entities() -> DotMapEntities:
	if _entities == null:
		_entities = DotMapEntities.from_manifest(manifest)
	return _entities


## The mover record for a brush entity (direction, distance, speed, what opens it), or {}.
func mover(model: int) -> Dictionary:
	return _movers.get(model, {})


## Where a brush entity's node goes: its origin, so turning the node turns it about it.
func model_origin(model: int) -> Vector3:
	var o: Variant = mover(model).get("origin")
	if model == WORLD or not o is Array or (o as Array).size() < 3:
		return Vector3.ZERO
	return Vector3(o[0], o[1], o[2])


## The engine arrays of one surface ([constant Mesh.ARRAY_MAX] long), world positions.
func surface_arrays(rec: Dictionary) -> Array:
	var n := int(rec["vertex_count"])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	var p := int(rec["position_offset"])
	arrays[Mesh.ARRAY_VERTEX] = _blob.slice(p, p + 12 * n).to_vector3_array()
	var q := int(rec["normal_offset"])
	arrays[Mesh.ARRAY_NORMAL] = _blob.slice(q, q + 12 * n).to_vector3_array()
	var u := int(rec["uv_offset"])
	arrays[Mesh.ARRAY_TEX_UV] = _blob.slice(u, u + 8 * n).to_vector2_array()
	if rec.has("uv2_offset"):
		var u2 := int(rec["uv2_offset"])
		arrays[Mesh.ARRAY_TEX_UV2] = _blob.slice(u2, u2 + 8 * n).to_vector2_array()
	if rec.has("alpha_offset"):
		var a0 := int(rec["alpha_offset"])
		var alpha := _blob.slice(a0, a0 + 4 * n).to_float32_array()
		var cols := PackedColorArray()
		cols.resize(n)
		for k in n:
			cols[k] = Color(alpha[k], 0.0, 0.0, 1.0)
		arrays[Mesh.ARRAY_COLOR] = cols
	var i := int(rec["index_offset"])
	arrays[Mesh.ARRAY_INDEX] = _blob.slice(i, i + 4 * int(rec["index_count"])).to_int32_array()
	return arrays


## Whether the map carries its author's baked lighting (a [code]lightmap[/code] record).
func has_lightmap() -> bool:
	return not (manifest.get("lightmap", {}) as Dictionary).get("pages", []).is_empty()


## Linear-light exposure of the baked lighting, 1.0 as the author compiled it.
func lightmap_scale() -> float:
	return float((manifest.get("lightmap", {}) as Dictionary).get("scale", 1.0))


## Atlas page [param index] as an RGB9E5 texture, or null; built once.
func lightmap_page(index: int) -> Texture2D:
	if _pages.has(index):
		return _pages[index]
	var pages: Array = (manifest.get("lightmap", {}) as Dictionary).get("pages", [])
	if index < 0 or index >= pages.size():
		return null
	var rec: Dictionary = pages[index]
	var w := int(rec["width"])
	var h := int(rec["height"])
	var at := int(rec["offset"])
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RGBE9995, _blob.slice(at, at + 4 * w * h))
	_pages[index] = ImageTexture.create_from_image(img)
	return _pages[index]


## The author's per-leaf ambient at [param point] (the nearest sample's cube, weighted by [param normal]), linear;
## black when the map has none. For a prop or a character the lightmap cannot reach. Scans every sample.
func ambient_at(point: Vector3, normal: Vector3 = Vector3.UP) -> Color:
	var rec: Variant = (manifest.get("lightmap", {}) as Dictionary).get("ambient")
	if not rec is Dictionary:
		return Color.BLACK
	var n := int(rec["count"])
	var at := int(rec["offset"])
	if n <= 0 or at < 0 or at + 84 * n > _blob.size():
		return Color.BLACK
	if _ambient.is_empty():
		_ambient = _blob.slice(at, at + 84 * n).to_float32_array()
	var best := 0
	var best_d := INF
	for i in n:
		var d := point.distance_squared_to(Vector3(_ambient[21 * i], _ambient[21 * i + 1], _ambient[21 * i + 2]))
		if d < best_d:
			best_d = d
			best = i
	var nn := normal.normalized()
	var w := [nn.x * nn.x, nn.x * nn.x, nn.y * nn.y, nn.y * nn.y, nn.z * nn.z, nn.z * nn.z]
	var c := Vector3.ZERO
	for face in 6:
		# faces are +x, -x, +y, -y, +z, -z; only the side the normal points at counts
		var sign_ok: bool = (face % 2 == 0) == ([nn.x, nn.x, nn.y, nn.y, nn.z, nn.z][face] >= 0.0)
		if sign_ok:
			var o := 21 * best + 3 + 3 * face
			c += Vector3(_ambient[o], _ambient[o + 1], _ambient[o + 2]) * float(w[face])
	return Color(c.x, c.y, c.z)


## The light no lit surface falls below: the mean sky-facing ambient cube of the map (lump 56), or the sun entity's ambient, never under [member visibility_floor] so an outdoor frame is never black.
func light_floor() -> Color:
	var c := Vector3.ZERO
	var rec: Variant = (manifest.get("lightmap", {}) as Dictionary).get("ambient")
	if rec is Dictionary and int(rec["count"]) > 0:
		var n := int(rec["count"])
		var at := int(rec["offset"])
		if at >= 0 and at + 84 * n <= _blob.size():
			if _ambient.is_empty():
				_ambient = _blob.slice(at, at + 84 * n).to_float32_array()
			if not _floor_mean.has(n):    # every material of the map asks, and the scan is 1 ms
				_floor_mean[n] = DotMapParallelBuild.sky_mean(_ambient, n)
			c = _floor_mean[n]
	var sun: Dictionary = environment_data().get("sun", {})
	var a: Variant = sun.get("ambient_hdr", sun.get("ambient"))
	if a is Array and (a as Array).size() >= 3:
		c = c.max(Vector3(float(a[0]), float(a[1]), float(a[2])))
	var lum := (c.x + c.y + c.z) / 3.0
	if visibility_floor > 0.0 and lum < visibility_floor:
		c = c * (visibility_floor / lum) if lum > 0.0 else Vector3.ONE * visibility_floor
	return _limit_tint(c)


## The strongest ratio of brightest to dimmest channel a floor keeps: a sky-lit map's blue floor (0.1, 0.1, 0.5) tinted every pale surface of it.
const MAX_TINT_RATIO := 2.5


## Pulls [param c] toward its own grey until its channels are within [constant MAX_TINT_RATIO] (and [member lightmap_max_chroma_ratio] when set); the author's warm or cool cast stays, a saturated one does not.
static func _limit_tint(c: Vector3) -> Color:
	c = DotMapSurfaces.limit_chroma(c, MAX_TINT_RATIO)
	c = DotMapSurfaces.limit_chroma(c, lightmap_max_chroma_ratio)
	return Color(c.x, c.y, c.z)


## Strongest brightest/dimmest channel ratio the lightmap, floor light and actor ambient keep; 0 (default) = off.
## Process-wide. The actor ambient and floor light read it live, but the world shader gets a copy only
## when its materials are built, so set it before building the world.
static var lightmap_max_chroma_ratio: float = 0.0


## Sets [member lightmap_max_chroma_ratio] (process-wide; set before the world's materials are built) for a caller that reaches this script by path.
static func set_lightmap_max_chroma_ratio(value: float) -> void:
	lightmap_max_chroma_ratio = maxf(value, 0.0)


## The default [member visibility_floor].
const MIN_FLOOR := 0.3

## Mean luminance a lit surface (and an actor's ambient, [DotMapLitWorld]) never falls below, tinted by the author's ambient, so a map the author lit darkly stays playable. 0 turns the floor off; a game wires its cvar to this before the world's materials are built.
static var visibility_floor: float = MIN_FLOOR


## Sets [member visibility_floor] for a caller that reaches this script by path.
static func set_visibility_floor(value: float) -> void:
	visibility_floor = maxf(value, 0.0)
## The sun's least energy over a baked world: the bake of a weak outdoor sun is near black and this is what shows the outdoors.
const SUN_MIN_LIT := 1.0

## The look of each glass kind: colour with alpha, roughness.
const GLASS_LOOKS := {
	&"glass": {"colour": Color(0.72, 0.86, 0.92, 0.22), "roughness": 0.05},
	&"glass_frosted": {"colour": Color(0.85, 0.9, 0.93, 0.55), "roughness": 0.55},
	&"fence": {"colour": Color(0.62, 0.64, 0.66), "roughness": 0.5, "pattern": &"diamond", "mode": &"cut"},
	&"grate": {"colour": Color(0.38, 0.39, 0.4), "roughness": 0.6, "pattern": &"grid", "mode": &"cut"},
	&"bars": {"colour": Color(0.22, 0.22, 0.24), "roughness": 0.6, "pattern": &"bars", "mode": &"cut"},
	&"ladder": {"colour": Color(0.5, 0.42, 0.3), "roughness": 0.7, "pattern": &"ladder", "mode": &"cut"},
	&"foliage_card": {"colour": Color(1, 1, 1), "roughness": 0.9, "pattern": &"leaves", "mode": &"cut"},
	&"shield": {"colour": Color(0.25, 0.55, 1.0, 0.45), "roughness": 0.2, "mode": &"glow"},
	&"glow": {"colour": Color(1, 1, 1, 0.5), "roughness": 0.2, "mode": &"glow"},
}
## `mode` cut is an alpha-scissor card with a drawn pattern, glow an additive sheet; both are drawn only.
static var _glass_cache: Dictionary = {}


## The shared transparent material of a glass kind (an unknown kind is clear glass), multiplied by
## [param tint] (r, g, b) when the map gave one. Alpha-blended, so it sorts and shows what is behind.
static func glass_material(glass_kind: StringName, tint: Array = []) -> StandardMaterial3D:
	if not GLASS_LOOKS.has(glass_kind):
		glass_kind = &"glass"
	var key := "%s|%s" % [glass_kind, tint]
	if _glass_cache.has(key):
		return _glass_cache[key]
	var look: Dictionary = GLASS_LOOKS[glass_kind]
	var c: Color = look["colour"]
	if tint.size() >= 3:
		c = Color(c.r * float(tint[0]), c.g * float(tint[1]), c.b * float(tint[2]), c.a)
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = float(look["roughness"])
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mode: StringName = look.get("mode", &"glass")
	if mode == &"cut":
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		m.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
		m.albedo_texture = cutout_texture(StringName(look["pattern"]))
	elif mode == &"glow":
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(c.r, c.g, c.b, 1.0) * c.a
	m.resource_name = str(glass_kind)
	_glass_cache[key] = m
	return m


static var _cutouts: Dictionary = {}


## A 128 px tileable alpha-cutout image drawn in code (so it has no licence): wire diamonds, a grid,
## vertical bars with rails, ladder rungs or leaf blobs. Colour is in the texture only for foliage.
static func cutout_texture(pattern: StringName) -> ImageTexture:
	if _cutouts.has(pattern):
		return _cutouts[pattern]
	var n := 128
	var img := Image.create(n, n, true, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var solid := Color.WHITE
	match pattern:
		&"diamond":
			for y in n:
				for x in n:
					var d := (x + y) % 16
					var e := (x - y + n) % 16
					if d < 2 or e < 2:
						img.set_pixel(x, y, solid)
		&"grid":
			for y in n:
				for x in n:
					if x % 16 < 3 or y % 16 < 3:
						img.set_pixel(x, y, solid)
		&"bars":
			for y in n:
				for x in n:
					if x % 16 < 4 or y < 6 or (y >= 61 and y < 67) or y >= n - 6:
						img.set_pixel(x, y, solid)
		&"ladder":
			for y in n:
				for x in n:
					if x < 10 or x >= n - 10 or y % 24 < 6:
						img.set_pixel(x, y, solid)
		&"leaves":
			# Many small overlapping leaves, the shade varying per leaf: a few big blobs left the sky showing as black patches.
			var rng := RandomNumberGenerator.new()
			rng.seed = 7
			for k in 420:
				var c := Vector2(rng.randf() * n, rng.randf() * n)
				var r := rng.randf_range(3.0, 7.0)
				var shade := rng.randf_range(0.45, 1.0)
				var col := Color(0.17 * shade, 0.4 * shade, 0.1 * shade, 1.0)
				var ext := int(ceilf(r * 1.3)) + 1
				for dy in range(-ext, ext + 1):
					for dx in range(-ext, ext + 1):
						if Vector2(dx * 0.7, dy * 1.2).length() <= r:
							img.set_pixel(posmod(int(c.x) + dx, n), posmod(int(c.y) + dy, n), col)
	img.generate_mipmaps()
	img = keep_coverage(img)
	var tex := ImageTexture.create_from_image(img)
	_cutouts[pattern] = tex
	return tex


## [param img] (RGBA8, with mipmaps) with each mip's alpha scaled so the share of texels past the 0.5
## scissor threshold equals the top level's. Averaged alpha of a thin line falls under 0.5 a mip or
## two down, so a fence would vanish at distance; this keeps it as a thinner, fainter-edged line.
static func keep_coverage(img: Image) -> Image:
	var top := img.duplicate() as Image
	top.clear_mipmaps()
	var want := 0
	for y in top.get_height():
		for x in top.get_width():
			if top.get_pixel(x, y).a >= 0.5:
				want += 1
	var share := float(want) / float(top.get_width() * top.get_height())
	var data := img.get_data()
	var w := img.get_width()
	var h := img.get_height()
	for level in range(1, img.get_mipmap_count() + 1):
		w = maxi(w >> 1, 1)
		h = maxi(h >> 1, 1)
		var base := img.get_mipmap_offset(level)
		var count := w * h
		var alphas := PackedFloat32Array()
		alphas.resize(count)
		for i in count:
			alphas[i] = float(data[base + i * 4 + 3]) / 255.0
		if share <= 0.0 or share >= 1.0:
			continue
		var sorted := alphas.duplicate()
		sorted.sort()
		# The lowest alpha that lets no more than ~30% over the wanted share past the threshold. A level
		# gone near-uniform (no line left to keep) has none and is left to alpha-to-coverage.
		var cut := -1.0
		var k := count - 1
		while k >= 0:
			var v := sorted[k]
			var j := k
			while j > 0 and sorted[j - 1] == v:
				j -= 1
			if float(count - j) > float(count) * share * 1.3:
				break
			cut = v
			k = j - 1
		if cut < 0.004:
			continue
		var scale := 0.5 / cut
		if scale <= 1.0:
			continue
		for i in count:
			data[base + i * 4 + 3] = int(round(minf(alphas[i] * scale, 1.0) * 255.0))
	return Image.create_from_data(img.get_width(), img.get_height(), true, img.get_format(), data)


## One shared back-face-visible copy of [param mat] for a surface the source drew from both sides (rope, leaves); a
## shader material keeps its own culling, which is a render mode and cannot be switched per instance.
func _two_sided(mat: Material) -> Material:
	if not (mat is BaseMaterial3D) or (mat as BaseMaterial3D).cull_mode == BaseMaterial3D.CULL_DISABLED:
		return mat
	if not _two_sided_cache.has(mat):
		var copy := mat.duplicate() as BaseMaterial3D
		copy.cull_mode = BaseMaterial3D.CULL_DISABLED
		_two_sided_cache[mat] = copy
	return _two_sided_cache[mat]


var _two_sided_cache: Dictionary = {}


func _glass_for(rec: Dictionary) -> Material:
	if glass_material_for.is_valid():
		var m: Variant = glass_material_for.call(rec)
		if m is Material:
			return m
	return glass_material(StringName(str(rec["glass"])), rec.get("tint", []))


## A model's surfaces as meshes, grouped by chunk (the converter's columns of the world), each mesh under
## [constant MAX_SURFACES].
func build_meshes(model: int, material_for: Callable = Callable()) -> Array[Dictionary]:
	var groups := {}
	for rec: Dictionary in surfaces:
		if int(rec["model"]) != model:
			continue
		var key := "%s|%s|%s" % [str(rec.get("chunk", [])), rec.get("sky3d", false), rec.has("glass")]
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(rec)
	var plan: Array = []    # [group key, entry]
	for key: String in groups:
		# Material instance id -> {material, recs}, in first-seen order so the build is stable.
		var by_material := {}
		for rec: Dictionary in groups[key]:
			var mat: Material = null
			if rec.has("glass"):
				mat = _glass_for(rec)
			elif material_for.is_valid():
				var m: Variant = material_for.call(rec)
				mat = m as Material if m is Material else null
				if mat != null and rec.get("two_sided", false):
					mat = _two_sided(mat)
			var id := mat.get_instance_id() if mat != null else 0
			if not by_material.has(id):
				by_material[id] = {"material": mat, "recs": []}
			(by_material[id]["recs"] as Array).append(rec)
		for entry: Dictionary in by_material.values():
			plan.append([key, entry])
	var out: Array[Dictionary] = []
	var mesh: ArrayMesh = null
	var mesh_key := ""
	var step := DotMapParallelBuild.batch_size(load_threads)
	for from in range(0, plan.size(), step):
		var chunk := plan.slice(from, from + step)
		var arrays := DotMapParallelBuild.merged(self, chunk.map(func(p: Array) -> Array: return p[1]["recs"]), load_threads)
		for i in chunk.size():
			var key: String = chunk[i][0]
			var entry: Dictionary = chunk[i][1]
			var first: Dictionary = entry["recs"][0]
			if key != mesh_key or mesh.get_surface_count() >= MAX_SURFACES:
				mesh_key = key
				mesh = ArrayMesh.new()
				out.append({"mesh": mesh, "chunk": first.get("chunk", []), "sky3d": bool(first.get("sky3d", false)),
						"glass": first.has("glass"), "clusters": _clusters_of(groups[key])})
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays[i])
			var s := mesh.get_surface_count() - 1
			mesh.surface_set_name(s, str(first.get("material", "")))
			if entry["material"] != null:
				mesh.surface_set_material(s, entry["material"])
	return out


## The union of the records' clusters, or null when any record has none (drawn from everywhere).
static func _clusters_of(recs: Array) -> Variant:
	var seen := {}
	for rec: Dictionary in recs:
		var c: Variant = rec.get("clusters")
		if not c is Array or (c as Array).is_empty():
			return null
		for k: Variant in c:
			seen[int(k)] = true
	return PackedInt32Array(seen.keys())


## Bytes of one block the manifest's [code]vis[/code] record points at ([code]{offset, count}[/code]
## of [param width]-byte items), empty when it is absent or outside the data.
func vis_bytes(key: String, width: int = 4) -> PackedByteArray:
	var rec: Variant = (manifest.get("vis", {}) as Dictionary).get(key)
	if not rec is Dictionary:
		return PackedByteArray()
	var at := int(rec.get("offset", -1))
	var length := int(rec.get("count", 0)) * width
	if at < 0 or at + length > _blob.size():
		return PackedByteArray()
	return _blob.slice(at, at + length)


## [method surface_arrays] of several records as one, the indices offset onto the joined vertices.
func _merged_arrays(recs: Array) -> Array:
	if recs.size() == 1:
		return surface_arrays(recs[0])
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var any_uv2 := false
	var cols := PackedColorArray()
	var index := PackedInt32Array()
	for rec: Dictionary in recs:
		var a := surface_arrays(rec)
		var base := verts.size()
		var part_uv2: Variant = a[Mesh.ARRAY_TEX_UV2]
		if part_uv2 != null:
			any_uv2 = true
		else:
			part_uv2 = PackedVector2Array()
			part_uv2.resize((a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
		uv2s.append_array(part_uv2)
		var part_col: Variant = a[Mesh.ARRAY_COLOR]
		if part_col == null:
			part_col = PackedColorArray()
			part_col.resize((a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
		cols.append_array(part_col)
		var part: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		for k in part.size():
			part[k] += base
		verts.append_array(a[Mesh.ARRAY_VERTEX])
		normals.append_array(a[Mesh.ARRAY_NORMAL])
		uvs.append_array(a[Mesh.ARRAY_TEX_UV])
		index.append_array(part)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	if any_uv2:
		arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	if recs.any(func(r: Dictionary) -> bool: return r.has("alpha_offset")):
		arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = index
	return arrays


## Convex shapes of a model's player-solid brushes, relative to [method model_origin].
## [param kinds] filters (empty is every kind). Returns [code][{shape, kind, brush}][/code].
func hull_shapes(model: int, kinds: PackedStringArray = PackedStringArray()) -> Array[Dictionary]:
	var key := "%d:%s" % [model, ",".join(kinds)]
	if not _hull_cache.has(key):
		_hull_cache[key] = _build_hull_shapes(model, kinds)
	return _hull_cache[key].duplicate()


func _build_hull_shapes(model: int, kinds: PackedStringArray) -> Array[Dictionary]:
	var recs: Array = hulls.filter(func(r: Dictionary) -> bool:
		return int(r["model"]) == model and (kinds.is_empty() or str(r["kind"]) in kinds))
	var points := DotMapParallelBuild.hull_points(self, recs, model_origin(model), load_threads)
	var out: Array[Dictionary] = []
	for i in recs.size():
		var shape := ConvexPolygonShape3D.new()
		shape.points = points[i]
		out.append({"shape": shape, "kind": str(recs[i]["kind"]), "brush": int(recs[i]["brush"])})
	return out


## Triangle shapes for the surfaces that collide as drawn (displacements: terrain has no
## brushes), relative to [method model_origin].
func concave_shapes(model: int) -> Array[ConcavePolygonShape3D]:
	if not _concave_cache.has(model):
		_concave_cache[model] = _build_concave_shapes(model)
	return _concave_cache[model].duplicate()


func _build_concave_shapes(model: int) -> Array[ConcavePolygonShape3D]:
	var recs: Array = surfaces.filter(func(r: Dictionary) -> bool: return int(r["model"]) == model and r.get("collide", false))
	var faces := DotMapParallelBuild.concave_faces(self, recs, model_origin(model), load_threads)
	var out: Array[ConcavePolygonShape3D] = []
	for f: PackedVector3Array in faces:
		out.append(ConcavePolygonShape3D.new())
		out[-1].set_faces(f)
	return out


## Every drawn model as a node tree: a [code]world[/code] child with one [MeshInstance3D] per chunk, and one
## [Node3D] per brush entity at its origin (named by its targetname when it has one, else
## [code]model_<n>[/code]), meta [code]model[/code] and [code]mover[/code] set. [param movers_only] leaves the
## [code]world[/code] child empty, for a caller that draws the world model itself.
func build_node(material_for: Callable = Callable(), draw: bool = true, movers_only: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "BspMesh"
	for model in models():
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
		if not draw or (movers_only and model == WORLD):
			continue
		for g: Dictionary in build_meshes(model, material_for):
			var mi := MeshInstance3D.new()
			mi.mesh = g["mesh"]
			mi.position = -parent.position
			var c: Array = g["chunk"]
			mi.name = "sky3d" if g["sky3d"] else ("chunk_" + "_".join(PackedStringArray(c.map(str))) if c.size() >= 2 else "mesh")
			if g["clusters"] != null and model == WORLD:
				mi.set_meta(&"vis_clusters", g["clusters"])
			if g["glass"]:
				mi.name = "glass_" + str(mi.name)
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(mi)
			if shadow_proxy and model == WORLD and not g["glass"] and not g["sky3d"]:
				_add_shadow_proxy(parent, mi)
	return root


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


## The [code]environment[/code] block (sky, sun, fog, tonemap, cubemaps), or {}.
func environment_data() -> Dictionary:
	return manifest.get("environment", {})


## The [code]sounds[/code] block (ambient, soundscapes, triggers, files), or {}.
func sounds_data() -> Dictionary:
	return manifest.get("sounds", {})
