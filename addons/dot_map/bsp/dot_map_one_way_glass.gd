class_name DotMapOneWayGlass
extends RefCounted

## One-way glass for a jail cell: clear from outside, opaque from inside.
##
## A shader, not a second wall or a culling rule: the glass shows through (its own alpha) unless
## the camera is within [param radius] of the cell, in which case glass within that radius plus a
## margin is drawn solid. Everyone outside sees in, the prisoner sees a wall, and nothing is added
## to the physics or the draw call count. Install it as [member DotMapBspMesh.glass_material_for].

const SHADER_CODE := """
shader_type spatial;
render_mode cull_disabled, depth_draw_alpha_prepass;
uniform vec4 tint : source_color = vec4(0.72, 0.86, 0.92, 0.22);
uniform float roughness_value = 0.05;
uniform vec3 cell_centre = vec3(0.0);
uniform float cell_radius = 6.0;
uniform float margin = 2.0;
varying vec3 world_pos;
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	bool inside = distance(CAMERA_POSITION_WORLD, cell_centre) < cell_radius;
	bool cell_glass = distance(world_pos, cell_centre) < cell_radius + margin;
	ALBEDO = tint.rgb;
	ROUGHNESS = roughness_value;
	ALPHA = (inside && cell_glass) ? 1.0 : tint.a;
}
"""

## Glass kinds that are see-through sheets; cutouts and glow are left to the default look.
const KINDS: Array[StringName] = [&"glass", &"glass_frosted"]

static var _shader: Shader


## A [Callable] for [member DotMapBspMesh.glass_material_for]: a cell shader for clear glass, null for the rest.
static func hook(centre: Vector3, radius: float = 6.0) -> Callable:
	return func(rec: Dictionary) -> Variant:
		var kind := StringName(str(rec.get("glass", "")))
		if kind in KINDS:
			return material(kind, rec.get("tint", []), centre, radius)
		return null


## The shader material for one glass kind and tint around the cell at [param centre].
static func material(kind: StringName, tint: Array, centre: Vector3, radius: float) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	var look: Dictionary = DotMapBspMesh.GLASS_LOOKS.get(kind, DotMapBspMesh.GLASS_LOOKS[&"glass"])
	var colour: Color = look["colour"]
	if tint.size() >= 3:
		colour = Color(colour.r * float(tint[0]), colour.g * float(tint[1]), colour.b * float(tint[2]), colour.a)
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("tint", colour)
	m.set_shader_parameter("roughness_value", float(look["roughness"]))
	m.set_shader_parameter("cell_centre", centre)
	m.set_shader_parameter("cell_radius", radius)
	m.render_priority = 1
	m.resource_name = "one_way_%s" % kind
	return m


## Whether the camera at [param eye] is inside the cell (the glass draws solid for it).
static func sees_solid(eye: Vector3, centre: Vector3, radius: float) -> bool:
	return eye.distance_to(centre) < radius


## The jail cell of a world manifest as `{centre, radius}`, or {} when it has none. A cell is a
## destination that two or more teleport volumes aim at and that lies well below the highest such
## destination (a ramp's top); found by shape, never by a destination's name.
static func cell_of(manifest: Dictionary, radius: float = 6.0) -> Dictionary:
	var dests: Dictionary = manifest.get("destinations", {})
	var aimed: Dictionary = {}
	for vol: Variant in manifest.get("volumes", []):
		var v: Dictionary = vol as Dictionary
		if str(v.get("kind", "")) == "teleport" and dests.has(str(v.get("target", ""))):
			aimed[str(v["target"])] = int(aimed.get(str(v["target"]), 0)) + 1
	var top := -INF
	var best := ""
	for name: String in aimed:
		top = maxf(top, float((dests[name]["at"] as Array)[1]))
	for name: String in aimed:
		var y := float((dests[name]["at"] as Array)[1])
		if int(aimed[name]) >= 3 and y < top - 10.0 and (best == "" or int(aimed[name]) > int(aimed[best])):
			best = name
	if best == "":
		return {}
	var home := _vec(dests[best]["at"])
	var sum := Vector3.ZERO
	var count := 0
	for name: String in aimed:
		var at := _vec(dests[name]["at"])
		if at.distance_to(home) <= 5.0:
			sum += at
			count += 1
	return {"centre": sum / float(count) + Vector3(0, 1.0, 0), "radius": radius}


static func _vec(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
