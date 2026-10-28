class_name DotMapBrush
extends RefCounted

## Map-building solids as data: a spec in, a mesh and collision out.
##
## [codeblock]
## {"kind": "stairs", "size": [4, 3, 6], "params": {"steps": 6}, "uv_metres": 1.0}
## [/codeblock]
##
## [b]Every brush is a set of convex pieces.[/b] The collision is one
## [ConvexPolygonShape3D] per piece, never a trimesh: a concave solid (an arch, a
## quarter-pipe, a slab with holes) is several convex ones, which the solver handles and a
## character walks over without catching on an inside edge. The mesh is the pieces' faces,
## minus the faces two pieces share (same corners) (they would be inside the solid).
##
## [b]UVs are in metres.[/b] Each face is laid out on its own plane (a horizontal face by
## x and z; any other by its horizontal tangent and its slope), one UV unit per
## [code]uv_metres[/code]. A brush twice as big shows twice the texture rather than a
## stretched one, and a slope's texture is the size of a wall's. Pair it with a plain
## tiling material; [DotMapSurfaces] is already triplanar and needs no UVs, either works.
##
## The brush is centred on its bounding box, like a box of the maps in this family, and
## climbs, leans or opens toward +x where a direction matters (turn it with the node).
## Kinds: box, wedge (alias ramp), stairs, cylinder, cone, spike, arch, quarter_pipe, slab_holes.
## Params: [code]steps[/code] (stairs), [code]segments[/code] (cylinder, cone, spike, arch,
## quarter_pipe), [code]thickness[/code] (arch, metres), [code]holes[/code] (slab_holes:
## [code][[x, z, width, depth], ...][/code] from the slab's centre, metres).

const META_KIND := &"dot_map_brush"

const KINDS: PackedStringArray = [
	"box", "wedge", "stairs", "cylinder", "cone", "spike", "arch", "quarter_pipe", "slab_holes",
]
const ALIASES := {"ramp": "wedge"}

const MIN_SIZE := 0.05
const MAX_PIECES := 64
const MAX_SEGMENTS := 48
const MAX_STEPS := 32


static func kinds() -> PackedStringArray:
	return KINDS


static func resolve(kind: String) -> String:
	return String(ALIASES.get(kind, kind))


static func has_kind(kind: String) -> bool:
	return KINDS.has(resolve(kind))


## Checks a spec without building it. The failure says what is wrong and carries
## [constant DotError.CODE_INVALID].
static func validate(spec: Dictionary) -> DotResult:
	var kind := resolve(str(spec.get("kind", "")))
	if not KINDS.has(kind):
		return DotResult.fail(DotError.CODE_INVALID, "unknown brush kind '%s'" % kind, ", ".join(KINDS))
	var size_v: Variant = spec.get("size", null)
	if not (size_v is Array or size_v is Vector3) or (size_v is Array and (size_v as Array).size() != 3):
		return DotResult.fail(DotError.CODE_INVALID, "brush size must be [x, y, z]")
	var size := size_of(spec)
	if size.x < MIN_SIZE or size.y < MIN_SIZE or size.z < MIN_SIZE or not size.is_finite():
		return DotResult.fail(DotError.CODE_INVALID, "brush size %s is under %s m" % [size, MIN_SIZE])
	var params: Variant = spec.get("params", {})
	if not params is Dictionary:
		return DotResult.fail(DotError.CODE_INVALID, "params must be a dictionary")
	var p: Dictionary = params
	if int(p.get("steps", 1)) < 1 or int(p.get("steps", 1)) > MAX_STEPS:
		return DotResult.fail(DotError.CODE_INVALID, "steps must be 1 to %d" % MAX_STEPS)
	if int(p.get("segments", 8)) < 3 or int(p.get("segments", 8)) > MAX_SEGMENTS:
		return DotResult.fail(DotError.CODE_INVALID, "segments must be 3 to %d" % MAX_SEGMENTS)
	if float(spec.get("uv_metres", 1.0)) <= 0.0:
		return DotResult.fail(DotError.CODE_INVALID, "uv_metres must be above zero")
	if kind == "slab_holes":
		var holes: Variant = p.get("holes", [])
		if not holes is Array:
			return DotResult.fail(DotError.CODE_INVALID, "holes must be a list of [x, z, width, depth]")
		for h: Variant in holes:
			if not h is Array or (h as Array).size() != 4:
				return DotResult.fail(DotError.CODE_INVALID, "a hole is [x, z, width, depth]")
		if (holes as Array).size() > 8:
			return DotResult.fail(DotError.CODE_INVALID, "at most 8 holes")
	return DotResult.success(spec)


static func size_of(spec: Dictionary) -> Vector3:
	var s: Variant = spec.get("size", Vector3.ONE)
	if s is Vector3:
		return s
	var a: Array = s
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## The convex pieces of a brush, each an [code]Array[PackedVector3Array][/code] of faces
## (outward winding), or an empty array for an invalid spec.
static func pieces(spec: Dictionary) -> Array:
	if not validate(spec).ok:
		return []
	var kind := resolve(str(spec["kind"]))
	var size := size_of(spec)
	var p: Dictionary = spec.get("params", {})
	var out: Array = []
	var h := size * 0.5
	match kind:
		"box":
			out.append(_extrude_z(PackedVector2Array([Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)]), -h.z, h.z))
		"wedge":
			out.append(_extrude_z(PackedVector2Array([Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y)]), -h.z, h.z))
		"stairs":
			var n := int(p.get("steps", 5))
			for i in n:
				var x0 := -h.x + size.x * float(i) / n
				var x1 := -h.x + size.x * float(i + 1) / n
				var top := -h.y + size.y * float(i + 1) / n
				out.append(_extrude_z(PackedVector2Array([Vector2(x0, -h.y), Vector2(x1, -h.y), Vector2(x1, top), Vector2(x0, top)]), -h.z, h.z))
		"cylinder":
			out.append(_prism_y(_ellipse(h.x, h.z, int(p.get("segments", 16))), -h.y, h.y))
		"cone":
			out.append(_pyramid(_ellipse(h.x, h.z, int(p.get("segments", 16))), -h.y, h.y))
		"spike":
			out.append(_pyramid(_ellipse(h.x, h.z, int(p.get("segments", 4))), -h.y, h.y))
		"arch":
			var n := int(p.get("segments", 10))
			var t := clampf(float(p.get("thickness", minf(size.x, size.y) * 0.25)), 0.02, minf(h.x, size.y) * 0.95)
			for i in n:
				var a0 := PI * float(i) / n
				var a1 := PI * float(i + 1) / n
				var q := PackedVector2Array([
					_arc(h.x, size.y, a0, -h.y), _arc(h.x, size.y, a1, -h.y),
					_arc(h.x - t, size.y - t, a1, -h.y), _arc(h.x - t, size.y - t, a0, -h.y)])
				out.append(_extrude_z(q, -h.z, h.z))
		"quarter_pipe":
			# The floor is flat at -x and the curve climbs to a vertical face at +x.
			var n := int(p.get("segments", 8))
			var prev := Vector2(-h.x, -h.y)
			for i in range(1, n + 1):
				var a := (PI * 0.5) * float(i) / n
				var cur := Vector2(-h.x + size.x * sin(a), h.y - size.y * cos(a))
				var q := PackedVector2Array([Vector2(prev.x, -h.y), Vector2(cur.x, -h.y), cur, prev])
				out.append(_extrude_z(q, -h.z, h.z))
				prev = cur
		"slab_holes":
			out = _slab_pieces(size, p.get("holes", []))
	return out


## A [StaticBody3D] with the brush's collision, its mesh and [param material] on it.
## [param material] is the slot; null gets a plain grey one. The body carries
## [constant META_KIND], the resolved kind.
static func build_body(spec: Dictionary, material: Material = null) -> StaticBody3D:
	var parts := pieces(spec)
	if parts.is_empty():
		return null
	var body := StaticBody3D.new()
	body.name = "Brush_%s" % resolve(str(spec["kind"]))
	body.set_meta(META_KIND, StringName(resolve(str(spec["kind"]))))
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = mesh_of(parts, float(spec.get("uv_metres", 1.0)))
	if material == null:
		var plain := StandardMaterial3D.new()
		plain.albedo_color = Color(0.6, 0.6, 0.62)
		material = plain
	mi.material_override = material
	body.add_child(mi)
	for piece: Array in parts:
		var cs := CollisionShape3D.new()
		var shape := ConvexPolygonShape3D.new()
		shape.points = _unique_points(piece)
		cs.shape = shape
		body.add_child(cs)
	return body


## The pieces' faces as one mesh with world-scale UVs. See the class doc.
static func mesh_of(parts: Array, uv_metres: float = 1.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face: PackedVector3Array in _visible_faces(parts):
		var n := _normal(face)
		var axes := _uv_basis(n)
		for i in range(1, face.size() - 1):
			for idx: int in [0, i + 1, i]:
				var v := face[idx]
				st.set_normal(n)
				st.set_uv(Vector2(v.dot(axes[0]), v.dot(axes[1])) / uv_metres)
				st.add_vertex(v)
	st.generate_tangents()
	return st.commit()


## Horizontal faces by x and z; others by their horizontal tangent and slope direction, so
## texels are square on a slope.
static func _uv_basis(n: Vector3) -> Array[Vector3]:
	if absf(n.y) > 0.999:
		return [Vector3.RIGHT, Vector3.BACK]
	var u := Vector3.UP.cross(n).normalized()
	var v := n.cross(u).normalized()
	return [u, v]


static func _normal(face: PackedVector3Array) -> Vector3:
	var n := Vector3.ZERO
	for i in face.size():
		var a := face[i]
		var b := face[(i + 1) % face.size()]
		n += Vector3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y))
	return n.normalized()


static func _unique_points(piece: Array) -> PackedVector3Array:
	var seen := {}
	var pts := PackedVector3Array()
	for face: PackedVector3Array in piece:
		for v in face:
			var key := _key(v)
			if not seen.has(key):
				seen[key] = true
				pts.append(v)
	return pts


static func _key(v: Vector3) -> String:
	return "%d,%d,%d" % [roundi(v.x * 1000.0), roundi(v.y * 1000.0), roundi(v.z * 1000.0)]


## Makes each face wind outward (about the piece's centre), whatever order it was written in.
static func _oriented(faces: Array) -> Array:
	var pts := _unique_points(faces)
	var c := Vector3.ZERO
	for v in pts:
		c += v
	c /= maxf(pts.size(), 1)
	var out: Array = []
	for face: PackedVector3Array in faces:
		var mid := Vector3.ZERO
		for v in face:
			mid += v
		mid /= face.size()
		if _normal(face).dot(mid - c) < 0.0:
			var r := PackedVector3Array()
			for i in range(face.size() - 1, -1, -1):
				r.append(face[i])
			face = r
		out.append(face)
	return out


## The faces of [param parts] minus those two pieces share (same corners): inside the solid.
static func _visible_faces(parts: Array) -> Array:
	var count := {}
	for piece: Array in parts:
		for face: PackedVector3Array in piece:
			var k := _face_key(face)
			count[k] = int(count.get(k, 0)) + 1
	var out: Array = []
	for piece: Array in parts:
		for face: PackedVector3Array in piece:
			if int(count[_face_key(face)]) == 1:
				out.append(face)
	return out


static func _face_key(face: PackedVector3Array) -> String:
	var keys: Array = []
	for v in face:
		keys.append(_key(v))
	keys.sort()
	return "|".join(keys)


static func _extrude_z(profile: PackedVector2Array, z0: float, z1: float) -> Array:
	var faces: Array = []
	var front := PackedVector3Array()
	var back := PackedVector3Array()
	for p in profile:
		front.append(Vector3(p.x, p.y, z1))
		back.append(Vector3(p.x, p.y, z0))
	faces.append(front)
	faces.append(back)
	for i in profile.size():
		var j := (i + 1) % profile.size()
		faces.append(PackedVector3Array([back[i], back[j], front[j], front[i]]))
	return _oriented(faces)


static func _prism_y(poly: PackedVector2Array, y0: float, y1: float) -> Array:
	var faces: Array = []
	var top := PackedVector3Array()
	var bottom := PackedVector3Array()
	for p in poly:
		top.append(Vector3(p.x, y1, p.y))
		bottom.append(Vector3(p.x, y0, p.y))
	faces.append(top)
	faces.append(bottom)
	for i in poly.size():
		var j := (i + 1) % poly.size()
		faces.append(PackedVector3Array([bottom[i], bottom[j], top[j], top[i]]))
	return _oriented(faces)


static func _pyramid(poly: PackedVector2Array, y0: float, y1: float) -> Array:
	var faces: Array = []
	var base := PackedVector3Array()
	for p in poly:
		base.append(Vector3(p.x, y0, p.y))
	faces.append(base)
	var apex := Vector3(0.0, y1, 0.0)
	for i in poly.size():
		faces.append(PackedVector3Array([base[i], base[(i + 1) % poly.size()], apex]))
	return _oriented(faces)


static func _ellipse(rx: float, rz: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / n
		pts.append(Vector2(cos(a) * rx, sin(a) * rz))
	return pts


## A point on the half-ellipse of radii [param rx], [param ry] standing on [param base_y].
static func _arc(rx: float, ry: float, a: float, base_y: float) -> Vector2:
	return Vector2(cos(a) * rx, base_y + sin(a) * ry)


static func _slab_pieces(size: Vector3, holes_v: Variant) -> Array:
	var h := size * 0.5
	var holes: Array = holes_v
	var rects: Array[Rect2] = []
	if holes.is_empty():
		rects.append(Rect2(-size.x * 0.2, -size.z * 0.2, size.x * 0.4, size.z * 0.4))
	for hv: Array in holes:
		var r := Rect2(float(hv[0]) - float(hv[2]) * 0.5, float(hv[1]) - float(hv[3]) * 0.5, float(hv[2]), float(hv[3]))
		rects.append(r.intersection(Rect2(-h.x, -h.z, size.x, size.z)))
	var xs: Array[float] = [-h.x, h.x]
	for r in rects:
		if r.size.x > 0.0:
			xs.append(r.position.x)
			xs.append(r.end.x)
	xs.sort()
	var out: Array = []
	for i in xs.size() - 1:
		var x0 := xs[i]
		var x1 := xs[i + 1]
		if x1 - x0 < 0.001:
			continue
		var mid := (x0 + x1) * 0.5
		# The z intervals this x slice has no hole in.
		var cuts: Array = []
		for r in rects:
			if r.size.x > 0.0 and mid > r.position.x and mid < r.end.x:
				cuts.append([r.position.y, r.end.y])
		cuts.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		var z := -h.z
		for c: Array in cuts:
			if c[0] - z > 0.001:
				out.append(_slab_box(x0, x1, z, c[0], h.y))
			z = maxf(z, c[1])
		if h.z - z > 0.001:
			out.append(_slab_box(x0, x1, z, h.z, h.y))
	return out


static func _slab_box(x0: float, x1: float, z0: float, z1: float, hy: float) -> Array:
	return _extrude_z(PackedVector2Array([Vector2(x0, -hy), Vector2(x1, -hy), Vector2(x1, hy), Vector2(x0, hy)]), z0, z1)
