extends RefCounted

## The see-through looks of a converted map (glass, cutouts, glow) and the two-sided copy of a material; the base of [DotMapBspMesh]'s script chain, split out only to keep each file small.

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
