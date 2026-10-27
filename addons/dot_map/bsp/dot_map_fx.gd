class_name DotMapFx
extends RefCounted

## Draws a converted map's sprite-like entities cheaply: [code]env_sprite[/code] and [code]env_lightglow[/code]
## as additive billboards, [code]point_spotlight[/code] as a faint additive cone (a few also a real SpotLight3D),
## [code]infodecal[/code] as Decal nodes laid on the nearest surface. Textures are generated here, so no art ships.
## Every kind has a per-map cap, spread evenly over the entities when the map has more, and a view range.
## Input is the source document's entity records ([code]classname[/code], [code]pairs[/code]); nothing is gameplay.

const CHANNEL := "dot_map.fx"

var unit_scale := 0.0254
var world_offset := Vector3.ZERO
## [code](from, to) -> {position, normal}[/code] or {} when nothing is hit; decals need it, cones use it to stop at a wall.
var ray_fn := Callable()
## Sprites and cones are billboards and meshes the engine culls past [member view_range], so their caps only guard a runaway map.
var max_sprites := 400
var max_cones := 120
## Real SpotLight3D nodes lit at once; unlike the rest these cost per pixel, so they stay few.
var max_lights := 6
var max_decals := 120
var max_trails := 24
## [code](parentname) -> Node3D[/code] or null: the thing a trail follows. Without it a trail follows itself.
var trail_target_fn := Callable()
## Metres beyond which a sprite, cone or light is not drawn.
var view_range := 60.0
var decal_range := 22.0
var stats := {}

var _tex := {}
var _mats := {}
var _quads := {}


## Builds the nodes for [param records]; [member stats] says what was drawn and what was left out.
func build(records: Array) -> Node3D:
	var root := Node3D.new()
	root.name = "Fx"
	var sprites: Array = []
	var cones: Array = []
	var decals: Array = []
	var trails: Array = []
	for r: Variant in records:
		if not r is Dictionary:
			continue
		var rec: Dictionary = r
		match str(rec.get("classname", "")):
			"env_sprite", "env_lightglow":
				sprites.append(rec)
			"env_spritetrail":
				trails.append(rec)
			"point_spotlight":
				cones.append(rec)
			"infodecal":
				decals.append(rec)
	stats = {"sprites": 0, "cones": 0, "lights": 0, "decals": 0, "decals_unplaced": 0, "decals_unknown": 0, "trails": 0, "skipped": 0}
	_sprites(root, sprites)
	_cones(root, cones)
	_decals(root, decals)
	_trails(root, trails)
	DotLog.info(CHANNEL, "drawn", stats)
	return root


static func _keys(rec: Dictionary) -> Dictionary:
	var out := {}
	for p: Variant in rec.get("pairs", []):
		if p is Array and (p as Array).size() >= 2:
			out[str(p[0]).to_lower()] = str(p[1])
	return out


func _origin(k: Dictionary) -> Variant:
	var f: PackedFloat64Array = str(k.get("origin", "")).split_floats(" ", false)
	if f.size() < 3:
		return null
	return Vector3(f[0], f[2], -f[1]) * unit_scale + world_offset


static func _colour(k: Dictionary, fallback: Color = Color.WHITE) -> Color:
	var f: PackedFloat64Array = str(k.get("rendercolor", "")).split_floats(" ", false)
	if f.size() < 3:
		return fallback
	var amount := clampf(float(k.get("renderamt", "255")) / 255.0, 0.0, 1.0)
	return Color(f[0] / 255.0, f[1] / 255.0, f[2] / 255.0, amount)


## Every n-th of [param items] so that at most [param cap] remain, the same ones every run.
static func _spread(items: Array, cap: int) -> Array:
	if items.size() <= cap:
		return items
	var out: Array = []
	var step := float(items.size()) / float(cap)
	for i in cap:
		out.append(items[int(i * step)])
	return out


# --- sprites -----------------------------------------------------------------------------------

func _sprites(root: Node3D, recs: Array) -> void:
	var keep: Array = []
	for rec: Dictionary in recs:
		var k := _keys(rec)
		var cls := str(rec["classname"])
		var model := str(k.get("model", k.get("spritename", ""))).to_lower()
		var glow := cls == "env_lightglow" or _is_glow(model)
		var start_on := (int(k.get("spawnflags", "0")) & 1) != 0
		var named := str(k.get("targetname", "")) != ""
		if not glow or str(k.get("parentname", "")) != "" or (named and not start_on and cls == "env_sprite"):
			stats["skipped"] += 1
			continue
		if _origin(k) == null:
			continue
		keep.append([rec, k])
	for pair: Array in _spread(keep, max_sprites):
		var rec: Dictionary = pair[0]
		var k: Dictionary = pair[1]
		var lightglow := str(rec["classname"]) == "env_lightglow"
		var size: float
		var reach := view_range
		if lightglow:
			size = clampf(float(k.get("horizontalglowsize", "30")) * unit_scale * 3.0, 0.4, 3.0)
			reach = minf(view_range, maxf(float(k.get("outermaxdist", "2000")) * unit_scale, 8.0))
		else:
			size = clampf(float(k.get("scale", "1")) * 90.0 * unit_scale, 0.25, 4.0)
		var col := _colour(k)
		col.a = 0.55 if not lightglow else 0.5
		root.add_child(_glow(_origin(k), size, col, reach))
		stats["sprites"] += 1


static func _is_glow(model: String) -> bool:
	for word in ["glow", "flare", "light", "halo", "lamp", "fire", "spark", "sun", "star"]:
		if model.contains(word):
			return true
	return false


func _glow(at: Vector3, size: float, col: Color, reach: float) -> MeshInstance3D:
	var qkey := int(size * 20.0)
	if not _quads.has(qkey):
		var q := QuadMesh.new()
		q.size = Vector2.ONE * (qkey / 20.0)
		_quads[qkey] = q
	var m := MeshInstance3D.new()
	m.mesh = _quads[qkey]
	m.position = at
	m.material_override = _glow_material(col)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.visibility_range_end = reach
	m.visibility_range_end_margin = reach * 0.15
	return m


func _glow_material(col: Color) -> StandardMaterial3D:
	var key := "%d_%d_%d_%d" % [int(col.r * 8.0), int(col.g * 8.0), int(col.b * 8.0), int(col.a * 4.0)]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.no_depth_test = false
	m.albedo_texture = _glow_texture()
	m.albedo_color = Color(col.r, col.g, col.b, col.a)
	# Close to the eye a glow would fill the screen: it fades out inside 2 m.
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	m.distance_fade_min_distance = 0.6
	m.distance_fade_max_distance = 2.5
	_mats[key] = m
	return m


func _glow_texture() -> Texture2D:
	if _tex.has("glow"):
		return _tex["glow"]
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5).length() / (n * 0.5)
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * (0.35 + 0.65 * a)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_tex["glow"] = ImageTexture.create_from_image(img)
	return _tex["glow"]


func _trails(root: Node3D, recs: Array) -> void:
	var keep: Array = []
	for rec: Dictionary in recs:
		var k := _keys(rec)
		if _origin(k) == null:
			stats["skipped"] += 1
			continue
		keep.append([rec, k])
	for pair: Array in _spread(keep, max_trails):
		var k: Dictionary = pair[1]
		var t := DotMapTrail.new()
		t.position = _origin(k)
		t.lifetime = clampf(float(k.get("lifetime", "0.5")), 0.05, 10.0)
		t.start_width = clampf(float(k.get("startwidth", "8")) * unit_scale, 0.02, 2.0)
		t.end_width = clampf(float(k.get("endwidth", "1")) * unit_scale, 0.0, 2.0)
		t.colour = _colour(k)
		var parent_name := str(k.get("parentname", ""))
		if parent_name != "" and trail_target_fn.is_valid():
			var target: Variant = trail_target_fn.call(parent_name)
			if target is Node3D:
				t.follow = target
		root.add_child(t)
		stats["trails"] += 1


# --- spotlights --------------------------------------------------------------------------------

func _cones(root: Node3D, recs: Array) -> void:
	var keep: Array = []
	for rec: Dictionary in recs:
		var k := _keys(rec)
		if _origin(k) == null or str(k.get("parentname", "")) != "" or (int(k.get("spawnflags", "0")) & 1) == 0:
			stats["skipped"] += 1
			continue
		keep.append([rec, k])
	var drawn := _spread(keep, max_cones)
	var light_every := maxi(int(ceil(float(drawn.size()) / float(maxi(max_lights, 1)))), 1)
	var i := 0
	for pair: Array in drawn:
		var k: Dictionary = pair[1]
		var at: Vector3 = _origin(k)
		var f: PackedFloat64Array = str(k.get("angles", "0 0 0")).split_floats(" ", false)
		var pitch := deg_to_rad(f[0] if f.size() > 0 else 0.0)
		var yaw := deg_to_rad(f[1] if f.size() > 1 else 0.0)
		var dir := Vector3(cos(pitch) * cos(yaw), -sin(pitch), -cos(pitch) * sin(yaw)).normalized()
		var length := clampf(float(k.get("spotlightlength", "500")) * unit_scale, 2.0, 24.0)
		if ray_fn.is_valid():
			var hit: Dictionary = ray_fn.call(at + dir * 0.1, at + dir * length)
			if not hit.is_empty():
				length = maxf(at.distance_to(hit["position"]) - 0.05, 0.5)
		else:
			length = minf(length, 8.0)
		var col := _colour(k)
		root.add_child(_cone(at, dir, length, col))
		root.add_child(_glow(at, 0.35, Color(col.r, col.g, col.b, 0.8), view_range))
		stats["cones"] += 1
		if i % light_every == 0 and stats["lights"] < max_lights:
			root.add_child(_spot(at, dir, length, col))
			stats["lights"] += 1
		i += 1


func _cone(at: Vector3, dir: Vector3, length: float, col: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.04
	mesh.bottom_radius = clampf(length * 0.12, 0.2, 2.2)
	mesh.height = length
	mesh.radial_segments = 10
	mesh.rings = 1
	mesh.cap_top = false
	mesh.cap_bottom = false
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = _cone_material(col)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The cylinder's +Y is the narrow end; that end sits on the lamp, so +Y points back along the beam.
	var up := -dir
	var side := up.cross(Vector3.UP if absf(up.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT).normalized()
	m.basis = Basis(side, up, side.cross(up).normalized())
	m.position = at + dir * length * 0.5
	m.visibility_range_end = view_range
	m.visibility_range_end_margin = view_range * 0.15
	return m


const BEAM_SHADER := """shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color = vec4(1.0);
void fragment() {
	float edge = pow(clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 2.0);
	float along = pow(1.0 - clamp(UV.y, 0.0, 1.0), 1.5);
	ALBEDO = tint.rgb;
	ALPHA = tint.a * edge * along;
}
"""


func _cone_material(col: Color) -> ShaderMaterial:
	var key := "cone_%d_%d_%d" % [int(col.r * 6.0), int(col.g * 6.0), int(col.b * 6.0)]
	if _mats.has(key):
		return _mats[key]
	if not _tex.has("beam_shader"):
		var sh := Shader.new()
		sh.code = BEAM_SHADER
		_tex["beam_shader"] = sh
	var m := ShaderMaterial.new()
	m.shader = _tex["beam_shader"]
	m.set_shader_parameter("tint", Color(col.r, col.g, col.b, 0.35))
	_mats[key] = m
	return m


func _spot(at: Vector3, dir: Vector3, length: float, col: Color) -> SpotLight3D:
	var l := SpotLight3D.new()
	l.light_color = Color(col.r, col.g, col.b)
	l.light_energy = 1.2
	l.spot_range = maxf(length, 4.0)
	l.spot_angle = 30.0
	l.shadow_enabled = false
	l.distance_fade_enabled = true
	l.distance_fade_begin = 25.0
	l.distance_fade_length = 10.0
	l.position = at
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	l.basis = Basis.looking_at(dir, up)
	return l


# --- decals ------------------------------------------------------------------------------------

const DIRS := [Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK, Vector3.UP]

## Texture name fragment -> [kind, width m, height m].
const KINDS := [
	["blood", "blood", 1.0, 1.0], ["gore", "blood", 1.0, 1.0],
	["ivy", "ivy", 1.5, 1.5], ["vine", "ivy", 1.5, 1.5], ["moss", "ivy", 1.2, 1.2], ["leaf", "ivy", 1.2, 1.2],
	["trash", "trash", 0.9, 0.9], ["litter", "trash", 0.9, 0.9], ["paper", "trash", 0.7, 0.7],
	["graffiti", "graffiti", 1.1, 0.8], ["spray", "graffiti", 1.1, 0.8],
	["poster", "poster", 0.7, 1.0], ["bills", "poster", 0.7, 1.0], ["painting", "poster", 0.8, 0.8],
	["sign", "sign", 0.7, 0.5], ["warn", "sign", 0.7, 0.5], ["caution", "sign", 0.7, 0.5], ["danger", "sign", 0.7, 0.5],
	["grate", "grate", 0.9, 0.9], ["vent", "grate", 0.7, 0.5], ["drain", "grate", 0.9, 0.9],
	["outlet", "plate", 0.18, 0.18], ["switch", "plate", 0.18, 0.18], ["button", "plate", 0.18, 0.18],
	["puddle", "puddle", 1.2, 1.2],
	["stain", "stain", 0.9, 0.9], ["grime", "stain", 0.9, 0.9], ["dirt", "stain", 0.9, 0.9], ["splat", "stain", 0.9, 0.9], ["oil", "stain", 0.9, 0.9],
	["crack", "crack", 0.8, 0.8], ["bullet", "crack", 0.25, 0.25], ["scorch", "crack", 0.8, 0.8], ["burn", "crack", 0.8, 0.8],
]


func _decals(root: Node3D, recs: Array) -> void:
	var keep: Array = []
	for rec: Dictionary in recs:
		var k := _keys(rec)
		if _origin(k) != null:
			keep.append([rec, k])
	if not ray_fn.is_valid():
		stats["decals_unplaced"] = keep.size()
		return
	for pair: Array in _spread(keep, max_decals):
		var rec: Dictionary = pair[0]
		var k: Dictionary = pair[1]
		var at: Vector3 = _origin(k)
		var best: Dictionary = {}
		var best_d := 0.7
		for d: Vector3 in DIRS:
			var hit: Dictionary = ray_fn.call(at - d * 0.05, at + d * 0.6)
			if not hit.is_empty():
				var dist := at.distance_to(hit["position"])
				if dist < best_d:
					best_d = dist
					best = hit
		if best.is_empty():
			stats["decals_unplaced"] += 1
			continue
		var n: Vector3 = (best["normal"] as Vector3).normalized()
		var spec := _kind_of(str(k.get("texture", "")).to_lower())
		if spec.is_empty():
			stats["decals_unknown"] = int(stats.get("decals_unknown", 0)) + 1
			continue
		var index := int(rec.get("index", 0))
		var decal := Decal.new()
		decal.texture_albedo = _decal_texture(str(spec[0]), index % 2)
		decal.size = Vector3(float(spec[1]), 0.3, float(spec[2]))
		decal.normal_fade = 0.4
		decal.distance_fade_enabled = true
		decal.distance_fade_begin = decal_range
		decal.distance_fade_length = 6.0
		var up := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
		var side := up.cross(n).normalized()
		var b := Basis(side, n, side.cross(n).normalized())
		decal.basis = b.rotated(n, float(index % 4) * 0.05) if str(spec[0]) in ["blood", "stain", "trash", "puddle", "crack"] else b
		if str(spec[0]) in ["blood", "stain", "puddle"]:
			decal.basis = b.rotated(n, float(index % 7) * 0.9)
		decal.position = best["position"] + n * 0.03
		root.add_child(decal)
		stats["decals"] += 1


## Kind, width and height of a decal from its texture name; empty when the name says nothing we can draw.
func _kind_of(name: String) -> Array:
	for row: Array in KINDS:
		if name.contains(str(row[0])):
			return [row[1], row[2], row[3]]
	return []   # an unknown decal is left out: a dark stain stood in for each one and read as a black blob on the wall


func _decal_texture(kind: String, variant: int) -> Texture2D:
	var key := "decal_%s_%d" % [kind, variant]
	if _tex.has(key):
		return _tex[key]
	var n := 96
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	match kind:
		"blood":
			_blobs(img, rng, Color(0.38, 0.03, 0.03), 9, 0.30, 0.9)
			_blobs(img, rng, Color(0.25, 0.02, 0.02), 14, 0.08, 0.95)
		"puddle":
			_blobs(img, rng, Color(0.18, 0.2, 0.24), 3, 0.38, 0.55)
		"ivy":
			_vines(img, rng, Color(0.15, 0.32, 0.1))
		"trash":
			_blobs(img, rng, Color(0.35, 0.33, 0.3), 6, 0.1, 0.9)
			_blobs(img, rng, Color(0.6, 0.58, 0.5), 5, 0.06, 0.9)
		"graffiti":
			_strokes(img, rng, Color(rng.randf(), rng.randf(), rng.randf()).lightened(0.3), 5)
		"poster":
			_panel(img, Color(0.78, 0.74, 0.62).darkened(rng.randf() * 0.2), Color(0.25, 0.2, 0.15), 3)
			_strokes(img, rng, Color(0.2, 0.2, 0.25), 3)
		"sign":
			_panel(img, Color(0.9, 0.75, 0.1), Color(0.1, 0.1, 0.1), 5)
			_strokes(img, rng, Color(0.1, 0.1, 0.1), 2)
		"grate":
			_panel(img, Color(0.05, 0.05, 0.06, 0.8), Color(0.35, 0.35, 0.37), 6)
			for i in range(14, n - 8, 14):
				_line(img, Vector2(i, 6), Vector2(i, n - 6), 1.2, Color(0.35, 0.35, 0.37))
		"plate":
			_panel(img, Color(0.82, 0.8, 0.74), Color(0.3, 0.3, 0.3), 5)
		"crack":
			_strokes(img, rng, Color(0.08, 0.08, 0.08), 3)
			_blobs(img, rng, Color(0.05, 0.05, 0.05), 3, 0.12, 0.7)
		_:
			_blobs(img, rng, Color(0.12, 0.1, 0.07), 7, 0.28, 0.55)
	_tex[key] = ImageTexture.create_from_image(img)
	return _tex[key]


static func _blend(img: Image, x: int, y: int, c: Color, a: float) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	var o := img.get_pixel(x, y)
	var oa := o.a
	var na := oa + a * (1.0 - oa)
	if na <= 0.0:
		return
	var rgb := (Vector3(o.r, o.g, o.b) * oa * (1.0 - a) + Vector3(c.r, c.g, c.b) * a) / na
	img.set_pixel(x, y, Color(rgb.x, rgb.y, rgb.z, na))


static func _disc(img: Image, centre: Vector2, radius: float, c: Color, strength: float) -> void:
	var r := int(ceil(radius))
	for y in range(int(centre.y) - r, int(centre.y) + r + 1):
		for x in range(int(centre.x) - r, int(centre.x) + r + 1):
			var d := Vector2(x + 0.5, y + 0.5).distance_to(centre) / radius
			if d < 1.0:
				_blend(img, x, y, c, strength * (1.0 - d * d))


func _blobs(img: Image, rng: RandomNumberGenerator, c: Color, count: int, size: float, strength: float) -> void:
	var n := img.get_width()
	for i in count:
		var centre := Vector2(n * 0.5, n * 0.5) + Vector2(rng.randfn(0.0, n * 0.18), rng.randfn(0.0, n * 0.18))
		_disc(img, centre, maxf(n * size * rng.randf_range(0.5, 1.0), 2.0), c, strength)


static func _line(img: Image, a: Vector2, b: Vector2, width: float, c: Color) -> void:
	var steps := int(a.distance_to(b)) + 1
	for i in steps + 1:
		_disc(img, a.lerp(b, float(i) / float(steps)), width + 0.5, c, 0.95)


func _strokes(img: Image, rng: RandomNumberGenerator, c: Color, count: int) -> void:
	var n := img.get_width()
	for i in count:
		var p := Vector2(rng.randf_range(n * 0.15, n * 0.85), rng.randf_range(n * 0.15, n * 0.85))
		for s in 4:
			var q := p + Vector2(rng.randf_range(-n * 0.3, n * 0.3), rng.randf_range(-n * 0.3, n * 0.3))
			_line(img, p, q.clamp(Vector2.ZERO, Vector2(n, n)), 1.6, c)
			p = q.clamp(Vector2.ZERO, Vector2(n, n))


func _vines(img: Image, rng: RandomNumberGenerator, c: Color) -> void:
	var n := img.get_width()
	for v in 3:
		var p := Vector2(rng.randf_range(n * 0.2, n * 0.8), n - 2.0)
		while p.y > 6.0:
			var q := p + Vector2(rng.randf_range(-8.0, 8.0), -rng.randf_range(6.0, 12.0))
			_line(img, p, q, 1.0, c.darkened(0.3))
			_disc(img, q + Vector2(rng.randf_range(-5.0, 5.0), 0.0), rng.randf_range(3.0, 5.5), c.lightened(rng.randf() * 0.25), 0.95)
			p = q


func _panel(img: Image, fill: Color, edge: Color, border: int) -> void:
	var n := img.get_width()
	var inset := 4
	for y in range(inset, n - inset):
		for x in range(inset, n - inset):
			var on_edge := x < inset + border or y < inset + border or x >= n - inset - border or y >= n - inset - border
			img.set_pixel(x, y, edge if on_edge else fill)


func describe() -> String:
	return str(stats)
