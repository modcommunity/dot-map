class_name DotMapBspMesh
extends RefCounted

## A converted map's drawn world and collision: the [code]dot-bsp-mesh[/code] files that
## [code]tools/bsp/bsp.py mesh[/code] writes ([code]<id>.json[/code] + [code]<id>.bin[/code]),
## read back into meshes, convex shapes and the mover and volume records.
##
## [codeblock]
## var res := DotMapBspMesh.load_prefix("res://world/zm_4way_tunnel")
## if res.ok:
##     var world: DotMapBspMesh = res.value
##     add_child(world.build_node(func(rec: Dictionary) -> Material: return my_material(rec)))
## [/codeblock]
##
## [b]Game-neutral on purpose.[/b] What a surface looks like is the game's: [method build_node]
## asks a callback for each surface's [Material] with the surface's record (its generic id,
## source material name, tint, average colour, texel size, water and displacement flags).
## Which collision layer a hull goes on is the game's too: [method hull_shapes] hands back
## shapes with their kind (solid, clip, glass, sky) and the game makes the bodies.
##
## [b]Positions are in metres and Godot axes already[/b]; a brush entity's triangles are where
## the map put it. [method build_node] gives every brush entity (model above 0) its own node at
## the entity's origin with the geometry offset back under it, so a game turns a rotating door
## about its own hinge by turning that node.
##
## [b]The .bin is planar and gzip'd[/b]: every block is sliced straight into a typed array, no
## per-vertex script loop, and reading is synchronous with no thread, so it runs the same in a
## browser. The stored file's sha256 is checked against the manifest before anything is built.

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


## Pulls [param c] toward its own grey until its channels are within [constant MAX_TINT_RATIO]; the author's warm or cool cast stays, a saturated one does not.
static func _limit_tint(c: Vector3) -> Color:
	var g := (c.x + c.y + c.z) / 3.0
	var hi := maxf(c.x, maxf(c.y, c.z))
	var lo := minf(c.x, minf(c.y, c.z))
	var denom := hi + (MAX_TINT_RATIO - 1.0) * g - MAX_TINT_RATIO * lo
	if g > 0.0 and denom > 0.0:
		var k := minf(1.0, (MAX_TINT_RATIO - 1.0) * g / denom)
		c = Vector3(g, g, g) + (c - Vector3(g, g, g)) * k
	return Color(c.x, c.y, c.z)


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


## A model's surfaces as meshes, grouped by chunk (the converter's columns of the world), each
## mesh under [constant MAX_SURFACES]. [param material_for] takes a surface record, returns a
## [Material] or null; a glass surface (record key [code]glass[/code]) never asks it and gets
## [member glass_material_for] or the built-in glass, in meshes of their own so they can skip shadows.
## Records of a chunk that get the same material are one surface: one draw, not one per brush face.
## Returns [code][{mesh: ArrayMesh, chunk: Array, sky3d: bool, glass: bool, clusters: Variant}][/code]:
## [code]clusters[/code] is every visibility cluster the mesh touches, null when it must always be drawn.
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


## Every drawn model as a node tree: a [code]world[/code] child with one [MeshInstance3D] per
## chunk, and one [Node3D] per brush entity at its origin (named by its targetname when it has
## one, else [code]model_<n>[/code]), meta [code]model[/code] and [code]mover[/code] set.
## Drawing only: collision is [method hull_shapes] and [method concave_shapes], because which
## body and layer each goes on is the game's.
func build_node(material_for: Callable = Callable(), draw: bool = true) -> Node3D:
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
		if not draw:
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


## The map's breakable brush entities: [code]{model, entity, classname, targetname, health, glass, material}[/code]
## ([code]glass[/code] is the kind when every drawn surface is glass, else empty).
func breakables() -> Array:
	return manifest.get("breakables", [])


## A [DotMapGlass] for each breakable glass model of [param root] (a [method build_node] result): its
## hulls as the body on [param collision_layer], the model's node as what it hides. Non-breaking glass
## is no different from a wall: its hulls have kind [code]glass[/code] from [method hull_shapes], and a
## game leaves that kind off the layer its bullets and projectiles collide with.
func build_breakables(root: Node3D, collision_layer: int = 1, authoritative: bool = true) -> Array[DotMapGlass]:
	var out: Array[DotMapGlass] = []
	for rec: Dictionary in breakables():
		if rec.get("glass") == null or str(rec.get("glass")).is_empty() or rec.get("model") == null:
			continue
		var model := int(rec["model"])
		var visual: Node3D = null
		for c in root.get_children():
			if c.has_meta(&"model") and int(c.get_meta(&"model")) == model:
				visual = c as Node3D
		var pane := DotMapGlass.new()
		pane.name = "breakable_%d" % model
		pane.model = model
		pane.kind = StringName(str(rec["glass"]))
		pane.health = float(rec.get("health", 1.0))
		pane.authoritative = authoritative
		pane.visual = visual
		pane.collision_layer = collision_layer
		pane.collision_mask = 0
		pane.position = model_origin(model)
		for h: Dictionary in hull_shapes(model):
			var cs := CollisionShape3D.new()
			cs.shape = h["shape"]
			pane.add_child(cs)
		root.add_child(pane)
		out.append(pane)
	return out


## Where [method build_sounds] and [method build_props] look for a stand-in by id when the
## game gives no callable: this addon's own free Kenney set, then dot-audio's stock beds.
const DEFAULT_SOUND_DIRS: PackedStringArray = [
	"res://addons/dot_map/sounds", "res://addons/dot_audio/stock/ambience"]
const DEFAULT_PROP_DIRS: PackedStringArray = ["res://addons/dot_map/props"]

## The stand-in models face +Z; a Source model faces +X at yaw 0.
const PROP_FACING_DEGREES := 90.0

## A prop_dynamic `solid` value that collides as a box around its drawn model (2 bbox, 3 and 4 obb, 6 vphysics); 0, 1 and 5 do not.
const SOLID_BOX := [2, 3, 4, 6]

## A solid prop whose box would be wider than this (metres) is a room, a roof or a hull the map's own brushes already cover; a box would seal it.
const SOLID_MAX_SIDE := 6.0
## ...and one smaller than this on its longest side is a pebble that only snags a body.
const SOLID_MIN_SIDE := 0.25


## The manifest's [code]licence[/code] block (every free replacement with URL, author, licence), or {}.
func licence() -> Dictionary:
	return manifest.get("licence", {})


## True when the map went through the licence pass: a licence block and [code]free[/code] on every surface.
func is_free() -> bool:
	if licence().is_empty():
		return false
	for rec: Dictionary in surfaces:
		if not rec.has("free"):
			return false
	return true


## The [code]environment[/code] block (sky, sun, fog, tonemap, cubemaps), or {}.
func environment_data() -> Dictionary:
	return manifest.get("environment", {})


## The [code]sounds[/code] block (ambient, soundscapes, triggers, files), or {}.
func sounds_data() -> Dictionary:
	return manifest.get("sounds", {})


static func _col(v: Variant, fallback: Color) -> Color:
	if v is Array and (v as Array).size() >= 3 and float(v[0]) >= 0.0 and float(v[1]) >= 0.0 and float(v[2]) >= 0.0:
		return Color(float(v[0]), float(v[1]), float(v[2]))
	return fallback


static func _key(keys: Dictionary, name: String, fallback: float) -> float:
	for k: String in keys:
		if k.to_lower() == name:
			return float(str(keys[k]).split(" ")[0])
	return fallback


## Which free sky panorama (`addons/dot_map/sky/<kind>.jpg`) stands in for the map's sky name, or
## &"" for a night, space or unnamed sky (those stay the procedural sky and its stars).
static func sky_kind(sky_name: String) -> StringName:
	var n := sky_name.to_lower()
	if n.is_empty():
		return &""
	for w in ["night", "dark", "black", "space", "star", "moon"]:
		if n.contains(w):
			return &""
	for w in ["borealis", "ep01", "ep02", "cloudy", "storm", "overcast", "verystill", "grey", "gray"]:
		if n.contains(w):
			return &"overcast"
	if n.contains("day03") or n.contains("sunset") or n.contains("dusk") or n.contains("day01_09") or n.contains("day02_09"):
		return &"dusk"
	if n.contains("day01_01") or n.contains("day01_02") or n.contains("day01_03") or n.contains("clear"):
		return &"clear"
	return &"cloudy"


## The manifest's sky as a panorama texture from [param root] (a folder holding the four kinds), or null.
func sky_panorama(root: String = "res://addons/dot_map/sky") -> Texture2D:
	var kind := sky_kind(str(environment_data().get("sky", {}).get("name", "")))
	if kind == &"":
		return null
	var path := root.path_join("%s.jpg" % kind)
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


## The map's outdoors as nodes: a [WorldEnvironment] (procedural sky from the sun and ambient
## colours, fog, filmic tonemap) and a [DirectionalLight3D] sun, plus with [param max_probes]
## above 0 a [ReflectionProbe] at that many cubemap points. Null when the map carries no
## environment. Nodes are named [code]Environment[/code], [code]Sun[/code], [code]Probes[/code];
## the caller places the result and may edit anything in it.
func build_environment(max_probes: int = 8, sun_shadows: bool = true) -> Node3D:
	var env := environment_data()
	if env.is_empty():
		return null
	var root := Node3D.new()
	root.name = "MapEnvironment"
	var sun: Dictionary = env.get("sun", {})
	var amb := _col(sun.get("ambient_hdr"), _col(sun.get("ambient"), Color(0.4, 0.42, 0.46)))
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	var sky_name := str(env.get("sky", {}).get("name", "")).to_lower()
	var night := false
	for w in ["night", "dark", "black", "space", "star"]:
		night = night or sky_name.contains(w)
	if night:
		sm.sky_top_color = Color(0.02, 0.03, 0.08)
		sm.sky_horizon_color = Color(0.06, 0.07, 0.12)
		sm.ground_bottom_color = Color(0.01, 0.01, 0.02)
	else:
		sm.sky_top_color = Color(0.25, 0.45, 0.75).lerp(amb, 0.2)
		sm.sky_horizon_color = Color(0.65, 0.72, 0.8).lerp(amb, 0.2)
		sm.ground_bottom_color = Color(0.2, 0.19, 0.17)
	sm.ground_horizon_color = sm.sky_horizon_color
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = amb.lerp(Color(0.4, 0.4, 0.4), 0.25)
	if has_lightmap():
		e.ambient_light_color = e.ambient_light_color.lerp(light_floor(), 0.5)
	e.ambient_light_energy = 0.35 if night else 0.8
	if env.has("tonemap") or env.has("sun"):
		e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		var tm: Dictionary = env.get("tonemap", {}).get("keys", {})
		e.tonemap_exposure = clampf(_key(tm, "tonemapscale", 1.0), 0.5, 2.0)
	for f: Dictionary in env.get("fog", []):
		if not f.get("enabled", false):
			continue
		e.fog_enabled = true
		e.fog_light_color = _col(f.get("colour"), Color(0.5, 0.5, 0.5))
		e.fog_density = clampf(3.0 / maxf(float(f.get("end", 60.0)), 1.0), 0.002, 0.2) * float(f.get("max_density", 1.0))
		break
	var we := WorldEnvironment.new()
	we.name = "Environment"
	we.environment = e
	root.add_child(we)
	if not sun.is_empty():
		var light := DirectionalLight3D.new()
		light.name = "Sun"
		light.rotation_degrees = Vector3(float(sun.get("pitch", -45.0)), float(sun.get("yaw", 0.0)) - 90.0, 0.0)
		var lc: Variant = sun.get("colour_hdr")
		if not (lc is Array and float(lc[0]) >= 0.0):
			lc = sun.get("colour")
		light.light_color = _col(lc, Color(1, 0.96, 0.9))
		var power := 200.0
		if lc is Array and (lc as Array).size() > 3:
			power = float(lc[3])
		light.light_energy = clampf(power / 200.0, SUN_MIN_LIT if has_lightmap() else 0.2, 2.0)
		light.shadow_enabled = sun_shadows and not bool(env.get("shadows", {}).get("disabled", false))
		root.add_child(light)
	var cubes: Array = env.get("cubemaps", [])
	if max_probes > 0 and not cubes.is_empty():
		var probes := Node3D.new()
		probes.name = "Probes"
		root.add_child(probes)
		for i in mini(max_probes, cubes.size()):
			var at: Array = cubes[i].get("at", [0, 0, 0])
			var p := ReflectionProbe.new()
			p.position = Vector3(at[0], at[1], at[2])
			p.size = Vector3(16, 8, 16)
			p.update_mode = ReflectionProbe.UPDATE_ONCE
			probes.add_child(p)
	return root


## The first resource named [param id] with one of [param exts] in [param dirs], or null.
static func find_resource(id: String, dirs: PackedStringArray, exts: PackedStringArray) -> Resource:
	if id.is_empty():
		return null
	for d in dirs:
		for x in exts:
			var path := d.path_join(id + x)
			if ResourceLoader.exists(path):
				return load(path)
	return null


## The map's ambient sounds as nodes under [code]Sounds[/code]: each [code]ambient_generic[/code]
## with a free [code]stand_in[/code] becomes a player at its place with its radius, volume and
## pitch, started unless the map starts it silent. [param stream_for] takes the stand-in id and
## returns an [AudioStream] (default: [constant DEFAULT_SOUND_DIRS]). [param make_node] takes
## [code](record, stream)[/code] and returns the node to add, for a game that plays through its
## own audio layer; null falls back to an [AudioStreamPlayer3D]. A sound with no stand-in is
## silent on purpose: music and voices are never replaced.
func build_sounds(stream_for: Callable = Callable(), make_node: Callable = Callable(), level: float = 1.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Sounds"
	for rec: Dictionary in sounds_data().get("ambient", []):
		var id := str(rec.get("stand_in", ""))
		if id.is_empty():
			continue
		var found: Variant = stream_for.call(id) if stream_for.is_valid() \
				else find_resource(id, DEFAULT_SOUND_DIRS, PackedStringArray([".ogg", ".wav"]))
		if not found is AudioStream:
			continue
		var stream := (found as AudioStream).duplicate() as AudioStream
		if bool(rec.get("looped", true)):
			if "loop" in stream:
				stream.set("loop", true)
			elif "loop_mode" in stream:
				stream.set("loop_mode", AudioStreamWAV.LOOP_FORWARD)
		var node: Node = null
		if make_node.is_valid():
			node = make_node.call(rec, stream)
		if node == null:
			node = _default_player(rec, stream, level)
		var at: Array = rec.get("at", [0, 0, 0])
		if node is Node3D:
			(node as Node3D).position = Vector3(at[0], at[1], at[2])
		root.add_child(node)
	return root


func _default_player(rec: Dictionary, stream: AudioStream, level: float) -> Node:
	var db := linear_to_db(clampf(float(rec.get("volume", 1.0)) * level, 0.001, 4.0))
	var pitch := clampf(float(rec.get("pitch", 100.0)) / 100.0, 0.25, 4.0)
	var autoplay := not bool(rec.get("start_silent", false))
	var p: Node
	if bool(rec.get("everywhere", false)):
		var g := AudioStreamPlayer.new()
		g.stream = stream
		g.volume_db = db
		g.pitch_scale = pitch
		g.autoplay = autoplay
		p = g
	else:
		var a := AudioStreamPlayer3D.new()
		a.stream = stream
		a.volume_db = db
		a.pitch_scale = pitch
		a.max_distance = maxf(float(rec.get("radius", 20.0)), 1.0)
		a.unit_size = clampf(a.max_distance * 0.25, 1.0, 20.0)
		a.autoplay = autoplay
		p = a
	var tn := str(rec.get("targetname", ""))
	p.name = (tn if not tn.is_empty() else "amb_%d" % int(rec.get("entity", 0))).validate_node_name()
	p.set_meta(&"dot_map_entity", int(rec.get("entity", -1)))
	p.set_meta(&"dot_map_gain_scale", level)
	return p


## Library models ([code]lib/[/code]) [method build_props] could not load last time; [member missing_proxied] of them were drawn as boxes.
var missing_models: int = 0
## How many of [member missing_models] were drawn as low-detail boxes of the original's measured bounds.
var missing_proxied: int = 0
## Source paths already warned about missing library models: one WARN per map per process.
static var _models_warned: Dictionary = {}


## The free stand-in models the converter placed for the map's own, as nodes under
## [code]Props[/code]. [param scene_for] takes the stand-in id and returns a [PackedScene]
## (default: [constant DEFAULT_PROP_DIRS], [code].glb[/code]). An id with no scene is skipped, except a
## library model with measured bounds (`collide` or `bounds`), which is drawn as a box of them so nothing collides unseen.
func build_props(scene_for: Callable = Callable(), collide_fn: Callable = Callable()) -> Node3D:
	var root := Node3D.new()
	root.name = "Props"
	var cache := {}
	var longest_of := {}
	missing_models = 0
	missing_proxied = 0
	_unseen.clear()
	for rec: Dictionary in manifest.get("props", []):
		if rec.has("box"):
			var block := _support_block(rec)
			root.add_child(block)
			if collide_fn.is_valid() and int(rec.get("solid", 0)) in SOLID_BOX:
				var cb := _solid_shape(rec, null)
				if not cb.is_empty():
					var bb := _body_for(cb)
					root.add_child(bb)
					collide_fn.call(bb)
			continue
		var n := _place_prop(rec, scene_for, cache, longest_of)
		if n == null and str(rec.get("stand_in", "")).begins_with("lib/"):
			missing_models += 1
			n = _proxy_for(rec)
			if n == null:
				_unseen.append(rec)
			else:
				missing_proxied += 1
				root.add_child(n)
				if collide_fn.is_valid() and int(rec.get("solid", 0)) in SOLID_BOX:
					var pb := _solid_shape(rec, null)
					if not pb.is_empty():
						var body := _body_for(pb)
						root.add_child(body)
						collide_fn.call(body)
			continue
		if n == null:
			continue
		if prop_view_per_metre > 0.0:
			var end := maxf(prop_view_min, float(longest_of[str(rec.get("stand_in", ""))]) * n.scale.x * prop_view_per_metre)
			for g in n.find_children("*", "GeometryInstance3D", true, false):
				(g as GeometryInstance3D).visibility_range_end = end
				(g as GeometryInstance3D).visibility_range_end_margin = end * 0.1
		root.add_child(n)
		if collide_fn.is_valid() and int(rec.get("solid", 0)) in SOLID_BOX:
			for box in _solid_boxes(rec, n):
				var body := _body_for(box)
				root.add_child(body)
				collide_fn.call(body)
	_free_templates(cache)
	_decompose_cache.clear()
	_warn_missing_models()
	return root


## A low-detail box of a missing library model's measured bounds (`collide`, else `bounds`), or null without them.
func _proxy_for(rec: Dictionary) -> Node3D:
	var src: Variant = rec.get("collide", rec.get("bounds", null))
	if not src is Dictionary or not (src as Dictionary).has("box"):
		return null
	var d: Array = src["box"]
	if float(d[0]) <= 0.001 or float(d[1]) <= 0.001 or float(d[2]) <= 0.001:
		return null
	var at: Array = src.get("at", rec.get("at", [0, 0, 0]))
	var yaw: Variant = src.get("yaw", rec.get("yaw", 0.0))
	var block: MeshInstance3D
	if is_tree(rec):
		var trunk: Dictionary = _solid_shape({"stand_in": rec["stand_in"], "collide": src}, null)
		var w: float = (trunk["size"] as Vector3).x if not trunk.is_empty() else clampf(minf(d[0], d[2]) * TRUNK_SHARE, TRUNK_MIN, TRUNK_MAX)
		block = _support_block({"box": [w, d[1], w], "at": at, "yaw": yaw}, Color(0.36, 0.27, 0.18))
		block.add_child(_crown_blob(Vector3(d[0], d[1] * 0.65, d[2]), Vector3(0, d[1] * 0.175, 0)))
	else:
		block = _support_block({"box": d, "at": at, "yaw": yaw})
	block.name = "Proxy"
	block.set_meta(&"dot_map_proxy", str(rec.get("stand_in", "")))
	return block


## Library prop records [method build_props] could neither load nor measure, for [method draw_unseen_boxes].
var _unseen: Array[Dictionary] = []


## Blocks for a game's own world-space collision boxes ([code][x, y, z, sx, sy, sz, yaw][/code]) that stand where
## [method build_props] drew nothing (a missing, unmeasured library model), so no box collides unseen; null when none.
func draw_unseen_boxes(boxes: Array) -> Node3D:
	if _unseen.is_empty():
		return null
	var at_xz := {}
	for rec in _unseen:
		var at: Array = rec.get("at", [0, 0, 0])
		var key := Vector2i(floori(float(at[0])), floori(float(at[2])))
		if not at_xz.has(key):
			at_xz[key] = []
		at_xz[key].append(rec)
	var root := Node3D.new()
	root.name = "UnseenProps"
	for b: Variant in boxes:
		if not b is Array or (b as Array).size() < 7:
			continue
		var rec: Variant = null
		# A library model sits bottom-centre on its origin, so its box is centred over `at` and starts at its height.
		var cells := {}
		for dx in [-0.05, 0.05]:
			for dz in [-0.05, 0.05]:
				cells[Vector2i(floori(float(b[0]) + dx), floori(float(b[2]) + dz))] = true
		for cell: Vector2i in cells:
			for r: Dictionary in at_xz.get(cell, []):
				if absf(float(r["at"][0]) - float(b[0])) < 0.05 and absf(float(r["at"][2]) - float(b[2])) < 0.05 \
						and absf(float(b[1]) - float(b[4]) * 0.5 - float(r["at"][1])) <= 0.25:
					rec = r
		if rec == null:
			continue
		var tint := Color(0.36, 0.27, 0.18) if is_tree(rec) else Color(0.62, 0.6, 0.57)
		var block := _support_block({"box": [b[3], b[4], b[5]], "at": [b[0], b[1], b[2]], "yaw": b[6]}, tint)
		block.name = "Proxy"
		block.set_meta(&"dot_map_proxy", str(rec.get("stand_in", "")))
		root.add_child(block)
	if root.get_child_count() == 0:
		root.free()
		return null
	return root


func _warn_missing_models() -> void:
	if missing_models == 0 or _models_warned.has(source_path):
		return
	_models_warned[source_path] = true
	DotLog.warn(CHANNEL, "a map's library models are not installed; %d drawn as low-detail boxes, %d left out. To get them: %s" % [missing_proxied, missing_models - missing_proxied, DotMapStore.HOW_TO_GET],
			{"map": source_path.get_file(), "store_pack": str(DotMapStore.pack_of(licence()).get("id", "none"))})


## Key in a prop cache for the library templates [method _place_prop] made, which only the caller's end can free.
const OWNED_KEY := &"__owned"


## Frees the library templates a prop pass loaded; they are orphan nodes, so dropping the cache leaks their meshes and textures.
func _free_templates(cache: Dictionary) -> void:
	for n: Node in cache.get(OWNED_KEY, []):
		n.free()
	cache.erase(OWNED_KEY)


## One prop record as an instanced, placed and scaled stand-in (not yet in the tree); null when its stand-in has no scene.
func _place_prop(rec: Dictionary, scene_for: Callable, cache: Dictionary, longest_of: Dictionary) -> Node3D:
	var id := str(rec.get("stand_in", ""))
	if not cache.has(id):
		cache[id] = scene_for.call(id) if scene_for.is_valid() \
				else find_resource(id, DEFAULT_PROP_DIRS, PackedStringArray([".glb", ".tscn"]))
	if cache[id] == null and id.begins_with("lib/"):
		cache[id] = _library_model(id)
		if cache[id] != null:
			cache.get_or_add(OWNED_KEY, []).append(cache[id])
	var scene: Variant = cache[id]
	var n: Node3D = null
	if scene is PackedScene:
		n = (scene as PackedScene).instantiate() as Node3D
	elif scene is Node3D:
		n = (scene as Node3D).duplicate() as Node3D
	if n == null:
		return null
	var at: Array = rec.get("at", [0, 0, 0])
	n.position = Vector3(at[0], at[1], at[2])
	n.rotation_degrees.y = float(rec.get("yaw", 0.0)) + PROP_FACING_DEGREES
	n.scale = Vector3.ONE * float(rec.get("scale", 1.0))
	var size := float(rec.get("size", 0.0))
	if not longest_of.has(id):
		longest_of[id] = _longest_side(n)
	var longest: float = longest_of[id]
	if size > 0.0 and longest > 0.001:
		# A small thing (a can, a phone) on a furniture-sized stand-in: fit its longest side to `size`.
		n.scale *= size / longest
	return n


## The folder holding the pack's shared model library (default: the licence block's [code]model_store[/code] beside the mesh).
var model_library: String = ""
## Folders searched for a model before [member model_library], in order: a map's own slice and the shared slices it depends on.
var model_libraries: PackedStringArray = PackedStringArray()


## Library models this mesh found damaged ([method gltf_defect]); each is drawn as its measured box.
var defective_models := PackedStringArray()


## Why the glTF at [param path] cannot load ("" when it can): a .bin longer than its declared byteLength, which the engine
## refuses with an error per read and no name. Checked up front so the model is named once instead.
static func gltf_defect(path: String) -> String:
	if path.get_extension() != "gltf":
		return ""
	var json: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not json is Dictionary:
		return "not readable as JSON"
	for buf: Variant in (json as Dictionary).get("buffers", []):
		var uri := str((buf as Dictionary).get("uri", ""))
		if uri == "" or uri.begins_with("data:"):
			continue
		var bin := path.get_base_dir().path_join(uri.uri_decode())
		if not FileAccess.file_exists(bin):
			return "%s is missing" % uri
		var file := FileAccess.open(bin, FileAccess.READ)
		if file != null and file.get_length() > int((buf as Dictionary).get("byteLength", 0)):
			return "%s is %d bytes but the glTF declares %d" % [uri, file.get_length(), int((buf as Dictionary).get("byteLength", 0))]
	return ""


## A shipped library model (stand-in id [code]lib/<name>[/code]) loaded from the pack, re-rooted so its bottom centre sits at
## the origin; null when the pack lacks it. A glTF outside the project has no import, so it is read with [GLTFDocument].
func _library_model(id: String) -> Node3D:
	var row := {}
	for r: Dictionary in licence().get("model_stand_ins", []):
		if str(r.get("stand_in", "")) == id:
			row = r
	if row.is_empty() or not row.has("store_file"):
		return null
	var root := model_library if not model_library.is_empty() \
			else source_path.get_base_dir().path_join(str(licence().get("model_store", "model-library"))).simplify_path()
	var path := root.path_join(str(row["store_file"]))
	for lib in model_libraries:
		var cand := lib.path_join(str(row["store_file"]))
		if ResourceLoader.exists(cand) or FileAccess.file_exists(cand):
			path = cand
			break
	var model: Node3D = null
	if path.begins_with("res://") and ResourceLoader.exists(path):
		var packed := load(path) as PackedScene
		model = packed.instantiate() as Node3D if packed != null else null
	elif FileAccess.file_exists(path):
		var defect := gltf_defect(path)
		if defect != "":
			if not defective_models.has(path):
				defective_models.append(path)
				DotLog.warn(CHANNEL, "a library model is damaged and drawn as a box instead: " + defect, {"model": path})
			return null
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(path, state) == OK:
			model = doc.generate_scene(state) as Node3D
			if model != null:
				add_mesh_lods(model, model_lod_min_tris, model_max_tris)
	if model == null:
		return null
	var box := _local_aabb(model)
	model.position -= Vector3(box.get_center().x, box.position.y, box.get_center().z)
	var holder := Node3D.new()
	holder.add_child(model)
	return holder


## Triangles a library model's mesh must have before [method add_mesh_lods] simplifies it (the engine then picks a coarser level by
## screen size); 0 leaves every mesh whole. A scanned tree is over a million triangles, and a street of them was the frame.
static var model_lod_min_tris: int = 20000

## Most triangles a library model's mesh keeps at full detail: a mesh over it starts from the coarsest simplification that fits, so a 1.6 million triangle tree is drawn at about this size when near. 0 keeps the model's own.
static var model_max_tris: int = 150000


## Sets [member model_lod_min_tris] and [member model_max_tris] for a caller that reaches this script by path.
static func set_model_lod(min_tris: int, max_tris: int = 0) -> void:
	model_lod_min_tris = maxi(min_tris, 0)
	model_max_tris = maxi(max_tris, 0)


## Gives every unskinned [MeshInstance3D] mesh under [param root] with at least [param min_tris] triangles its LOD levels
## (meshoptimizer, as the editor's import does; a glTF read at run time has none), after cutting it to [param max_tris]
## (0: not cut). About a second for a million triangles, once per model. Returns how many meshes changed.
static func add_mesh_lods(root: Node, min_tris: int, max_tris: int = 0) -> int:
	if min_tris <= 0:
		return 0
	var done := {}
	var changed := 0
	for found in root.find_children("*", "MeshInstance3D", true, false):
		var mi := found as MeshInstance3D
		var mesh := mi.mesh as ArrayMesh
		if mesh == null or mi.skin != null or mesh.get_blend_shape_count() > 0:
			continue
		if not done.has(mesh):
			done[mesh] = _with_lods(mesh, min_tris, max_tris)
		if done[mesh] != mesh:
			mi.mesh = done[mesh]
			changed += 1
	return changed


static func _with_lods(mesh: ArrayMesh, min_tris: int, max_tris: int) -> Mesh:
	var tris := 0
	var all: Array = []
	for i in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(i) != Mesh.PRIMITIVE_TRIANGLES:
			return mesh
		var arrays := mesh.surface_get_arrays(i)
		var index: Variant = arrays[Mesh.ARRAY_INDEX]
		tris += (index as PackedInt32Array).size() / 3 if index != null else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		all.append(arrays)
	if tris < min_tris:
		return mesh
	var importer := _importer_of(mesh, all)
	importer.generate_lods(25.0, 60.0, [])
	if max_tris > 0 and tris > max_tris:
		# Each surface restarts from the first level small enough for its share, then gets its own levels again.
		var share := float(max_tris) / float(tris)
		for i in all.size():
			var arrays: Array = all[i]
			var base := (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3 if arrays[Mesh.ARRAY_INDEX] != null else 0
			for l in importer.get_surface_lod_count(i):
				var indices := importer.get_surface_lod_indices(i, l)
				if indices.size() / 3 <= int(base * share) or l == importer.get_surface_lod_count(i) - 1:
					arrays[Mesh.ARRAY_INDEX] = indices
					break
		importer = _importer_of(mesh, all)
		importer.generate_lods(25.0, 60.0, [])
	var out := importer.get_mesh()
	return out if out != null else mesh


static func _importer_of(mesh: ArrayMesh, all: Array) -> ImporterMesh:
	var importer := ImporterMesh.new()
	for i in all.size():
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, all[i], [], {}, mesh.surface_get_material(i), mesh.surface_get_name(i))
	return importer


## One static body with a box per solid prop (see [constant SOLID_BOX]), in world space and with no meshes, for a
## server that draws nothing and a client that draws [method build_props] without [code]collide_fn[/code].
## The boxes match [method build_props]'s own solid bodies. Null when no prop is solid.
func build_prop_collision(scene_for: Callable = Callable()) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "SolidProps"
	var cache := {}
	var longest_of := {}
	for rec: Dictionary in manifest.get("props", []):
		if not int(rec.get("solid", 0)) in SOLID_BOX:
			continue
		var n: Node3D = null
		if not rec.has("box"):
			n = _place_prop(rec, scene_for, cache, longest_of)
			if n == null and not rec.has("collide"):
				continue
		for box in _solid_boxes(rec, n):
			var shape := BoxShape3D.new()
			shape.size = box["size"]
			var cs := CollisionShape3D.new()
			cs.shape = shape
			cs.transform = box["transform"]
			body.add_child(cs)
		if n != null:
			n.free()
	_free_templates(cache)
	_decompose_cache.clear()
	if body.get_child_count() == 0:
		body.free()
		return null
	return body


## The boxes a solid prop collides as: its [method _solid_shape] box, or, when the drawn stand-in [param n] fills under
## [constant HOLLOW_FILL] of that box (a sofa's corner, an arch, a table), boxes that follow the model, so the collision is not an unseen wall.
func _solid_boxes(rec: Dictionary, n: Node3D) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var whole := _solid_shape(rec, n)
	if whole.is_empty():
		return out
	if n != null and not rec.has("box") and not is_tree(rec) and not _is_thin_original(rec, whole):
		var parts := _decomposed(rec, n)
		if not parts.is_empty():
			return parts
	out.append(whole)
	return out


## A stand-in fills less of its bounds than this and it is cut into boxes.
const HOLLOW_FILL := 0.6
## Cells along a stand-in's longest side, the most boxes a prop is cut into, and the most triangles read to do it.
static var decompose_cells: int = 12
static var decompose_max_boxes: int = 32
## A stand-in whose longest side is under this stays one box: a lamp is not worth thirty.
static var decompose_min_size: float = 0.8
const DECOMPOSE_MAX_TRIS := 400000


## [param n]'s meshes as boxes of occupied cells, in the same {size, transform} form as [method _solid_shape]; [] when the model is
## near enough a box already, too heavy to read, or would need more than [member decompose_max_boxes] at any grid.
func _decomposed(rec: Dictionary, n: Node3D) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var key := str(rec.get("stand_in", ""))
	if not _decompose_cache.has(key):
		_decompose_cache[key] = _cut_into_boxes(n)
	for local: AABB in _decompose_cache[key]:
		out.append({"size": local.size * n.scale, "transform": Transform3D(n.basis.orthonormalized(), n.position + n.basis * local.get_center())})
	return out


var _decompose_cache := {}


## The boxes (in [param n]'s local space) of the finest grid that needs at most [member decompose_max_boxes], or [] to keep one box.
## A cell is occupied where a triangle passes; an enclosed empty cell (a closed sofa) counts as occupied, the open space under a table does not.
static func _cut_into_boxes(n: Node3D) -> Array[AABB]:
	var none: Array[AABB] = []
	var tris := PackedVector3Array()
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var t := Transform3D.IDENTITY
		var p: Node = mi
		while p != null and p != n:
			t = (p as Node3D).transform * t
			p = p.get_parent()
		for v in mi.mesh.get_faces():
			tris.append(t * v)
		if tris.size() > DECOMPOSE_MAX_TRIS * 3:
			return none
	var box := _local_aabb(n)
	var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
	if tris.is_empty() or longest < maxf(0.001, decompose_min_size):
		return none
	for cells in range(decompose_cells, 2, -2):
		var cell := longest / cells
		var dims := Vector3i(maxi(1, ceili(box.size.x / cell - 0.001)), maxi(1, ceili(box.size.y / cell - 0.001)), maxi(1, ceili(box.size.z / cell - 0.001)))
		var solid := _fill_cells(tris, box.position, cell, dims)
		if cells == decompose_cells and float(solid.count(true)) / solid.size() >= HOLLOW_FILL:
			return none
		var boxes := _merge_cells(solid, dims, box, cell)
		if boxes.size() <= decompose_max_boxes:
			return boxes
	return none


static func _cell_index(c: Vector3i, dims: Vector3i) -> int:
	return (c.y * dims.z + c.z) * dims.x + c.x


## Occupancy of the grid ([param dims] cells of [param cell] metres from [param lo]): triangles sampled finer than a cell, then the
## empty cells that the outside cannot reach filled in.
static func _fill_cells(tris: PackedVector3Array, lo: Vector3, cell: float, dims: Vector3i) -> Array[bool]:
	var solid: Array[bool] = []
	solid.resize(dims.x * dims.y * dims.z)
	solid.fill(false)
	var top := Vector3i(dims.x - 1, dims.y - 1, dims.z - 1)
	for i in range(0, tris.size() - 2, 3):
		var a := tris[i]
		var b := tris[i + 1]
		var c := tris[i + 2]
		var edge := maxf((b - a).length(), maxf((c - b).length(), (a - c).length()))
		var k := clampi(ceili(edge / (cell * 0.5)), 1, 64)
		for u in k + 1:
			for v in k + 1 - u:
				var q := a + (b - a) * (float(u) / k) + (c - a) * (float(v) / k)
				var g := ((q - lo) / cell).floor()
				var cx := Vector3i(clampi(int(g.x), 0, top.x), clampi(int(g.y), 0, top.y), clampi(int(g.z), 0, top.z))
				solid[_cell_index(cx, dims)] = true
	# Flood the empty cells from every border cell; what stays unreached is enclosed.
	var outside: Array[bool] = []
	outside.resize(solid.size())
	outside.fill(false)
	var queue: Array[Vector3i] = []
	for y in dims.y:
		for z in dims.z:
			for x in dims.x:
				if (x == 0 or y == 0 or z == 0 or x == top.x or y == top.y or z == top.z) and not solid[_cell_index(Vector3i(x, y, z), dims)]:
					outside[_cell_index(Vector3i(x, y, z), dims)] = true
					queue.append(Vector3i(x, y, z))
	var at := 0
	while at < queue.size():
		var cur := queue[at]
		at += 1
		for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			var nx: Vector3i = cur + d
			if nx.x < 0 or nx.y < 0 or nx.z < 0 or nx.x > top.x or nx.y > top.y or nx.z > top.z:
				continue
			var ix := _cell_index(nx, dims)
			if not solid[ix] and not outside[ix]:
				outside[ix] = true
				queue.append(nx)
	for i in solid.size():
		solid[i] = solid[i] or not outside[i]
	return solid


## Occupied cells joined greedily into boxes: along x, then z while the whole run is occupied, then y while the whole slab is.
static func _merge_cells(solid: Array[bool], dims: Vector3i, box: AABB, cell: float) -> Array[AABB]:
	var taken: Array[bool] = solid.duplicate()
	var out: Array[AABB] = []
	for y in dims.y:
		for z in dims.z:
			for x in dims.x:
				if not taken[_cell_index(Vector3i(x, y, z), dims)]:
					continue
				var x2 := x
				while x2 + 1 < dims.x and taken[_cell_index(Vector3i(x2 + 1, y, z), dims)]:
					x2 += 1
				var z2 := z
				while z2 + 1 < dims.z and _run_taken(taken, dims, x, x2, y, z2 + 1):
					z2 += 1
				var y2 := y
				while y2 + 1 < dims.y and _slab_taken(taken, dims, x, x2, y2 + 1, z, z2):
					y2 += 1
				for yy in range(y, y2 + 1):
					for zz in range(z, z2 + 1):
						for xx in range(x, x2 + 1):
							taken[_cell_index(Vector3i(xx, yy, zz), dims)] = false
				var from := box.position + Vector3(x, y, z) * cell
				var to := box.position + Vector3(x2 + 1, y2 + 1, z2 + 1) * cell
				to = Vector3(minf(to.x, box.end.x), minf(to.y, box.end.y), minf(to.z, box.end.z))
				out.append(AABB(from, to - from))
	return out


static func _run_taken(taken: Array[bool], dims: Vector3i, x1: int, x2: int, y: int, z: int) -> bool:
	for x in range(x1, x2 + 1):
		if not taken[_cell_index(Vector3i(x, y, z), dims)]:
			return false
	return true


static func _slab_taken(taken: Array[bool], dims: Vector3i, x1: int, x2: int, y: int, z1: int, z2: int) -> bool:
	for z in range(z1, z2 + 1):
		if not _run_taken(taken, dims, x1, x2, y, z):
			return false
	return true


## {size, transform} (world space) of the box a solid prop record collides as, or {} for none. A `box` record (a
## support block) and a record with `collide` (the original model's measured bounds, written by the converter) use their
## own numbers, so the body is the size of what the map had; otherwise the drawn stand-in [param n] is boxed.
func _solid_shape(rec: Dictionary, n: Node3D) -> Dictionary:
	var size := Vector3.ZERO
	var xf := Transform3D.IDENTITY
	var src: Variant = rec.get("collide", rec) if rec.has("collide") or rec.has("box") else null
	if src != null:
		var d: Array = src["box"]
		var at: Array = src.get("at", rec.get("at", [0, 0, 0]))
		size = Vector3(d[0], d[1], d[2])
		xf = Transform3D(Basis(Vector3.UP, deg_to_rad(float(src.get("yaw", rec.get("yaw", 0.0))))), Vector3(at[0], at[1], at[2]))
	elif n != null:
		var box := _local_aabb(n)
		size = box.size * n.scale
		xf = Transform3D(n.basis.orthonormalized(), n.position + n.basis * box.get_center())
		var thin := _thin_bounds(rec, size)
		if not thin.is_empty():
			size = thin["size"]
			xf = thin["transform"]
	if size.x <= 0.001 or size.y <= 0.001 or size.z <= 0.001:
		return {}
	if maxf(size.x, maxf(size.y, size.z)) < SOLID_MIN_SIDE or maxf(size.x, size.z) > SOLID_MAX_SIDE:
		return {}
	if is_tree(rec):
		var w := clampf(minf(size.x, size.z) * TRUNK_SHARE, TRUNK_MIN, TRUNK_MAX)
		size = Vector3(w, size.y, w)
	return {"size": size, "transform": xf}


## A thin original (a handrail, a fence rail: under [constant THIN_SIDE] across) whose measure is known but not packed is
## drawn as a stand-in several times wider; this returns the measured box in its place when the stand-in's footprint is over
## [constant THIN_FOOTPRINT_RATIO] times the original's, else {}. Without it a rail seals a corridor its original left open.
func _thin_bounds(rec: Dictionary, stand_in_size: Vector3) -> Dictionary:
	var b: Variant = rec.get("bounds")
	if not (b is Dictionary) or not (b as Dictionary).has("box"):
		return {}
	var d: Array = b["box"]
	var at: Array = b.get("at", rec.get("at", [0, 0, 0]))
	var size := Vector3(d[0], d[1], d[2])
	if minf(size.x, size.z) >= THIN_SIDE or stand_in_size.x * stand_in_size.z < size.x * size.z * THIN_FOOTPRINT_RATIO:
		return {}
	return {"size": size, "transform": Transform3D(Basis(Vector3.UP, deg_to_rad(float(b.get("yaw", rec.get("yaw", 0.0))))), Vector3(at[0], at[1], at[2]))}


## Whether [param whole] (from [method _solid_shape]) is the measured box of a thin original, which the stand-in's own shape must not replace.
func _is_thin_original(rec: Dictionary, whole: Dictionary) -> bool:
	var b: Variant = rec.get("bounds")
	return b is Dictionary and (b as Dictionary).has("box") and (whole["size"] as Vector3).is_equal_approx(Vector3(b["box"][0], b["box"][1], b["box"][2]))


const THIN_SIDE := 0.15
const THIN_FOOTPRINT_RATIO := 4.0


## A tree collides as its trunk: a source tree's physics model is the trunk, and a box of the crown is an unseen wall round it.
const TRUNK_SHARE := 0.15
const TRUNK_MIN := 0.3
const TRUNK_MAX := 0.8
const TREE_WORDS: PackedStringArray = ["tree", "pine", "palm", "conifer", "spruce", "birch", "oak"]


## Whether a prop record's stand-in is a tree (a word of its id, so a street lamp is not).
static func is_tree(rec: Dictionary) -> bool:
	for w in str(rec.get("stand_in", "")).to_lower().replace("/", "_").replace("-", "_").split("_", false):
		if w in TREE_WORDS:
			return true
	return false


static func _body_for(box: Dictionary) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Solid"
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box["size"]
	cs.shape = shape
	body.add_child(cs)
	body.transform = box["transform"]
	return body


static var _support_material: StandardMaterial3D = null
static var _tinted: Dictionary = {}


## A neutral block of the measured size, for a model something rests on and no stand-in fits; [param tint] colours a proxy's part.
static func _support_block(rec: Dictionary, tint: Color = Color(0.62, 0.6, 0.57)) -> MeshInstance3D:
	var dims: Array = rec["box"]
	var box := BoxMesh.new()
	box.size = Vector3(dims[0], dims[1], dims[2])
	if _support_material == null:
		_support_material = StandardMaterial3D.new()
		_support_material.albedo_color = Color(0.62, 0.6, 0.57)
	if tint.is_equal_approx(_support_material.albedo_color):
		box.material = _support_material
	else:
		if not _tinted.has(tint):
			var m := StandardMaterial3D.new()
			m.albedo_color = tint
			_tinted[tint] = m
		box.material = _tinted[tint]
	var mi := MeshInstance3D.new()
	mi.mesh = box
	var at: Array = rec.get("at", [0, 0, 0])
	mi.position = Vector3(at[0], at[1], at[2])
	mi.rotation_degrees.y = float(rec.get("yaw", 0.0))
	return mi


## A leafy ellipsoid for a missing tree's crown: a box read as a flat dark wall, a rounded green blob reads as a tree.
static func _crown_blob(size: Vector3, at: Vector3) -> MeshInstance3D:
	var ball := SphereMesh.new()
	ball.radius = 0.5
	ball.height = 1.0
	ball.radial_segments = 12
	ball.rings = 6
	if not _tinted.has(&"crown"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.3, 0.45, 0.22)
		m.roughness = 1.0
		_tinted[&"crown"] = m
	ball.material = _tinted[&"crown"]
	var mi := MeshInstance3D.new()
	mi.mesh = ball
	mi.scale = size
	mi.position = at
	return mi


static func _local_aabb(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var t := Transform3D.IDENTITY
		var p: Node = mi
		while p != null and p != n:
			t = (p as Node3D).transform * t
			p = p.get_parent()
		var b := t * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## The longest side of the meshes under [param n], in the node's own space (its scale ignored).
static func _longest_side(n: Node3D) -> float:
	var box := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var t := Transform3D.IDENTITY
		var p: Node = mi
		while p != null and p != n:
			t = (p as Node3D).transform * t
			p = p.get_parent()
		var b := t * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return 0.0 if first else maxf(box.size.x, maxf(box.size.y, box.size.z))


func counts() -> Dictionary:
	var tris := 0
	var verts := 0
	for rec: Dictionary in surfaces:
		tris += int(rec["index_count"]) / 3
		verts += int(rec["vertex_count"])
	return {"surfaces": surfaces.size(), "vertices": verts, "triangles": tris, "hulls": hulls.size(),
			"movers": _movers.size(), "bytes": _blob.size()}


func describe() -> Dictionary:
	var d := counts()
	d["name"] = manifest.get("name")
	d["path"] = source_path
	return d


func describe_lines() -> PackedStringArray:
	var c := counts()
	return PackedStringArray([
		"bsp mesh %s (%s)" % [manifest.get("name"), source_path],
		"  %d surfaces, %d vertices, %d triangles, %d hulls, %d movers, %d bytes" % [
			c["surfaces"], c["vertices"], c["triangles"], c["hulls"], c["movers"], c["bytes"]],
	])
