class_name DotMapTerrain
extends RefCounted
## A converted map's displacement ground as a heightfield (tools/bsp/dotbsp/terrain.py writes
## it): one triangle shape to collide with, a mesh to draw, and the points an AI graph walks.
##
## A stepped field of boxes cannot be climbed past a step per cell, so hilly ground ended at the
## first hill; this surface is the same one the converter's flood walked. Every cell is split
## along its (i, j)-(i+1, j+1) diagonal here and in the converter; keep the two in step.

const CHANNEL := "map.terrain"
const FORMAT := 1
## The steepest terrain a walker climbs, rise per metre (dotbsp.terrain.WALK_RISE).
const WALK_RISE := 1.0
const MAX_SAMPLES := 4_000_000

## The (x, z) of sample (0, 0); doubles, so a point lands on the sample the converter chose.
var origin_x: float = 0.0
var origin_z: float = 0.0
var cell: float = 1.0
var nx: int = 0
var nz: int = 0
## Row-major, x fastest; NAN is a hole.
var heights := PackedFloat64Array()
## 1 where a walker reached the sample, per sample; empty when the converter wrote no mask.
var walk := PackedByteArray()
## The surface kind the converter named (`grass`), or empty.
var mat: String = ""
## Height the outer rim's skirt drops to; NAN when the converter wrote none (no skirt).
var skirt_y: float = NAN


## Reads [param d] (the converter's dictionary). Fails on a newer format or damaged data.
static func from_dict(d: Dictionary) -> DotResult:
	if int(d.get("format", 0)) > FORMAT:
		return DotResult.fail(DotError.CODE_VERSION, "terrain format %s is newer than %d" % [d.get("format"), FORMAT])
	var size: Array = d.get("size", [])
	var org: Array = d.get("origin", [])
	if size.size() != 2 or org.size() != 2:
		return DotResult.fail(DotError.CODE_PARSE, "terrain has no size or origin")
	var t := DotMapTerrain.new()
	t.nx = int(size[0])
	t.nz = int(size[1])
	t.cell = float(d.get("cell", 0.0))
	t.origin_x = float(org[0])
	t.origin_z = float(org[1])
	t.mat = str(d.get("mat", ""))
	if d.has("skirt"):
		t.skirt_y = float(d["skirt"])
	var n := t.nx * t.nz
	if t.nx < 2 or t.nz < 2 or n > MAX_SAMPLES or t.cell <= 0.0:
		return DotResult.fail(DotError.CODE_PARSE, "terrain grid %dx%d of %s m is not usable" % [t.nx, t.nz, t.cell])
	var raw_size := int(d.get("bytes", 0))
	var mask_bytes := (n + 7) / 8
	if raw_size < mask_bytes or raw_size > mask_bytes + n * 2:
		return DotResult.fail(DotError.CODE_PARSE, "terrain says it is %d bytes" % raw_size)
	var raw := Marshalls.base64_to_raw(str(d.get("data", ""))).decompress(raw_size, FileAccess.COMPRESSION_DEFLATE)
	if raw.size() != raw_size:
		return DotResult.fail(DotError.CODE_PARSE, "terrain data would not decompress")
	var base := float(d.get("base", 0.0))
	var step := float(d.get("step", 0.05))
	var q := PackedInt32Array()
	q.resize(n)
	var known := PackedByteArray()
	known.resize(n)
	t.heights.resize(n)
	var off := mask_bytes
	for k in n:
		if (raw[k >> 3] >> (k & 7)) & 1 == 0:
			t.heights[k] = NAN
			continue
		if off + 2 > raw.size():
			return DotResult.fail(DotError.CODE_PARSE, "terrain data is short")
		var v := raw.decode_s16(off) + _predict(q, known, t.nx, k)
		off += 2
		q[k] = v
		known[k] = 1
		t.heights[k] = base + v * step
	if d.has("walk"):
		var wm := Marshalls.base64_to_raw(str(d["walk"])).decompress(mask_bytes, FileAccess.COMPRESSION_DEFLATE)
		if wm.size() != mask_bytes:
			return DotResult.fail(DotError.CODE_PARSE, "terrain walk mask would not decompress")
		t.walk.resize(n)
		for k in n:
			t.walk[k] = (wm[k >> 3] >> (k & 7)) & 1
	return DotResult.success(t)


static func _predict(q: PackedInt32Array, known: PackedByteArray, width: int, k: int) -> int:
	var i := k % width
	var has_left := i > 0 and known[k - 1] == 1
	var has_up := k >= width and known[k - width] == 1
	if has_left and has_up and known[k - width - 1] == 1:
		return clampi(q[k - 1] + q[k - width] - q[k - width - 1], 0, 10000)
	if has_left:
		return q[k - 1]
	if has_up:
		return q[k - width]
	return 0


## The height of sample (i, j), NAN for a hole or outside.
func sample(i: int, j: int) -> float:
	if i < 0 or j < 0 or i >= nx or j >= nz:
		return NAN
	return heights[j * nx + i]


## The surface's height at (x, z), NAN over a hole or outside the grid.
func height_at(x: float, z: float) -> float:
	var fx := (x - origin_x) / cell
	var fz := (z - origin_z) / cell
	var i := floori(fx)
	var j := floori(fz)
	if i == nx - 1 and fx - i < 1e-9:
		i -= 1
	if j == nz - 1 and fz - j < 1e-9:
		j -= 1
	if i < 0 or j < 0 or i >= nx - 1 or j >= nz - 1:
		return NAN
	fx -= i
	fz -= j
	var h00 := sample(i, j)
	var h11 := sample(i + 1, j + 1)
	if fx >= fz:
		var h10 := sample(i + 1, j)
		return h00 + fx * (h10 - h00) + fz * (h11 - h10)
	var h01 := sample(i, j + 1)
	return h00 + fz * (h01 - h00) + fx * (h11 - h01)


## The triangles over every cell half whose three samples exist, wound so they face up.
func faces() -> PackedVector3Array:
	var out := PackedVector3Array()
	for j in nz - 1:
		for i in nx - 1:
			var p00 := _point(i, j)
			var p11 := _point(i + 1, j + 1)
			var p10 := _point(i + 1, j)
			var p01 := _point(i, j + 1)
			if not is_nan(p00.y) and not is_nan(p10.y) and not is_nan(p11.y):
				out.append_array([p00, p10, p11])
			if not is_nan(p00.y) and not is_nan(p01.y) and not is_nan(p11.y):
				out.append_array([p00, p11, p01])
	return out


## The skirt: a wall under every edge where the field's outer rim meets open air (not a hole
## the field surrounds, which holds a building), down to [member skirt_y], so no rim floats
## with sky under it. Empty without a skirt. Walls are one quad, 6 vertices, per edge.
func skirt_faces() -> PackedVector3Array:
	var out := PackedVector3Array()
	if is_nan(skirt_y):
		return out
	var edges := skirt_edges()
	for e in range(0, edges.size(), 4):
		var a := _point(edges[e], edges[e + 1])
		var b := _point(edges[e + 2], edges[e + 3])
		var low := minf(skirt_y, minf(a.y, b.y))
		var a0 := Vector3(a.x, low, a.z)
		var b0 := Vector3(b.x, low, b.z)
		out.append_array([a, b, b0, a, b0, a0])
	return out


## Sample pairs (i, j, i, j) of the rim's edges, four ints each: an edge of a present triangle
## whose other side is outside the grid or a missing triangle open to it (dotbsp.terrain.outer_edges).
func skirt_edges() -> PackedInt32Array:
	var out := PackedInt32Array()
	var w := nx - 1
	var h := nz - 1
	var count := w * h * 2
	var present := PackedByteArray()
	present.resize(count)
	for j in h:
		for i in w:
			var k := (j * w + i) * 2
			present[k] = 1 if not is_nan(sample(i, j)) and not is_nan(sample(i + 1, j)) and not is_nan(sample(i + 1, j + 1)) else 0
			present[k + 1] = 1 if not is_nan(sample(i, j)) and not is_nan(sample(i, j + 1)) and not is_nan(sample(i + 1, j + 1)) else 0
	# open[k]: a missing triangle the outside reaches through missing triangles.
	var open := PackedByteArray()
	open.resize(count)
	var stack := PackedInt32Array()
	for k in count:
		if present[k] == 0 and open[k] == 0 and _tri_neighbours(k, w, h).has(-1):
			open[k] = 1
			stack.append(k)
		while not stack.is_empty():
			var cur := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			for nb in _tri_neighbours(cur, w, h):
				if nb >= 0 and present[nb] == 0 and open[nb] == 0:
					open[nb] = 1
					stack.append(nb)
	for k in count:
		if present[k] == 0:
			continue
		var i := (k >> 1) % w
		var j := (k >> 1) / w
		var nbs := _tri_neighbours(k, w, h)
		# Edge order matches _tri_neighbours: for A top, right, diagonal; for B bottom, left, diagonal.
		var ends: Array
		if k & 1 == 0:
			ends = [[i, j, i + 1, j], [i + 1, j, i + 1, j + 1], [i, j, i + 1, j + 1]]
		else:
			ends = [[i, j + 1, i + 1, j + 1], [i, j, i, j + 1], [i, j, i + 1, j + 1]]
		for e in 3:
			var nb: int = nbs[e]
			if nb == -1 or open[nb] == 1:
				out.append_array(PackedInt32Array(ends[e]))
	return out


## The triangles across each of triangle [param k]'s three edges (-1 outside the grid).
static func _tri_neighbours(k: int, w: int, h: int) -> Array:
	var c := k >> 1
	var i := c % w
	var j := c / w
	if k & 1 == 0:
		return [(((j - 1) * w + i) * 2 + 1) if j > 0 else -1, ((j * w + i + 1) * 2 + 1) if i < w - 1 else -1, c * 2 + 1]
	return [(((j + 1) * w + i) * 2) if j < h - 1 else -1, ((j * w + i - 1) * 2) if i > 0 else -1, c * 2]


func _point(i: int, j: int) -> Vector3:
	return Vector3(origin_x + i * cell, sample(i, j), origin_z + j * cell)


## One [ConcavePolygonShape3D] of [method faces], in world space. The skirt is never part of
## it unless [param with_skirt]: ground a body stands on is the field, not its curtain.
func build_shape(with_skirt: bool = false) -> ConcavePolygonShape3D:
	var shape := ConcavePolygonShape3D.new()
	var f := faces()
	if with_skirt:
		f.append_array(skirt_faces())
	shape.set_faces(f)
	return shape


## A drawable mesh of [method faces] with normals and UVs in metres (x, z), then the skirt
## (both sides, UVs along the edge and down).
func build_mesh() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in faces():
		tool.set_uv(Vector2(p.x, p.z))
		tool.add_vertex(p)
	var wall := skirt_faces()
	for k in range(0, wall.size(), 3):
		for side in 2:
			for v in 3:
				var p := wall[k + (v if side == 0 else 2 - v)]
				tool.set_uv(Vector2(p.x + p.z, p.y))
				tool.add_vertex(p)
	tool.generate_normals()
	return tool.commit()


## Points every [param spacing] metres whose nearest sample a walker reached, on the surface;
## dotbsp.terrain.walk_points places the same ones.
func walk_points(spacing: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	if walk.is_empty() or spacing <= 0.0:
		return out
	var count_x := int((nx - 1) * cell / spacing)
	var count_z := int((nz - 1) * cell / spacing)
	for b in count_z:
		var z := origin_z + (b + 0.5) * spacing
		var j := floori((z - origin_z) / cell + 0.5)
		for a in count_x:
			var x := origin_x + (a + 0.5) * spacing
			var i := floori((x - origin_x) / cell + 0.5)
			if i >= nx or j >= nz or walk[j * nx + i] == 0:
				continue
			var y := height_at(x, z)
			if not is_nan(y):
				out.append(Vector3(x, y, z))
	return out


## The grid's bounds in x and z, with y from the lowest to the highest sample.
func bounds() -> AABB:
	var lo := INF
	var hi := -INF
	for h in heights:
		if not is_nan(h):
			lo = minf(lo, h)
			hi = maxf(hi, h)
	if lo > hi:
		return AABB()
	return AABB(Vector3(origin_x, lo, origin_z), Vector3((nx - 1) * cell, hi - lo, (nz - 1) * cell))


func describe() -> Dictionary:
	var solid := 0
	for h in heights:
		if not is_nan(h):
			solid += 1
	var walked := 0
	for w in walk:
		walked += w
	return {"size": "%dx%d" % [nx, nz], "cell": cell, "samples": solid, "walk": walked, "mat": mat}
