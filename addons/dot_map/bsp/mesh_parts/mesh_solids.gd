extends "mesh_core.gd"

## The solid-prop collision half of [DotMapBspMesh]: boxes cut from a stand-in, trunks and support blocks.

## A prop_dynamic `solid` value that collides as a box around its drawn model (2 bbox, 3 and 4 obb, 6 vphysics); 0, 1 and 5 do not.
const SOLID_BOX := [2, 3, 4, 6]

## A solid prop whose box would be wider than this (metres) is a room, a roof or a hull the map's own brushes already cover; a box would seal it.
const SOLID_MAX_SIDE := 6.0
## ...and one smaller than this on its longest side is a pebble that only snags a body.
const SOLID_MIN_SIDE := 0.25

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
## The thinnest a box cut back to its surface may be, in metres: a plane of triangles must still stop a body.
const MIN_BOX := 0.1
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
		var seen: Array[AABB] = []
		var solid := _fill_cells(tris, box.position, cell, dims, seen)
		if cells == decompose_cells and float(solid.count(true)) / solid.size() >= HOLLOW_FILL:
			return none
		var boxes := _merge_cells(solid, dims, box, cell, seen)
		if boxes.size() <= decompose_max_boxes:
			return boxes
	return none


static func _cell_index(c: Vector3i, dims: Vector3i) -> int:
	return (c.y * dims.z + c.z) * dims.x + c.x


## Occupancy of the grid ([param dims] cells of [param cell] metres from [param lo]): triangles sampled finer than a cell, then the
## empty cells that the outside cannot reach filled in.
## [param seen] gets, per cell, the bounds of the surface points that fell in it (size -1 where none did: an enclosed fill).
static func _fill_cells(tris: PackedVector3Array, lo: Vector3, cell: float, dims: Vector3i, seen: Array[AABB]) -> Array[bool]:
	var solid: Array[bool] = []
	solid.resize(dims.x * dims.y * dims.z)
	solid.fill(false)
	seen.resize(solid.size())
	seen.fill(AABB(Vector3.ZERO, Vector3(-1, -1, -1)))
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
				var ci := _cell_index(cx, dims)
				solid[ci] = true
				var prev := seen[ci]
				seen[ci] = AABB(q, Vector3.ZERO) if prev.size.x < 0.0 else prev.expand(q)
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
## A box whose cells all hold surface is cut back to that surface (at least [constant MIN_BOX] thick), so a shelf's post is not a cell wide.
static func _merge_cells(solid: Array[bool], dims: Vector3i, box: AABB, cell: float, seen: Array[AABB] = []) -> Array[AABB]:
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
				var tight := AABB()
				var first := true
				var all_seen := not seen.is_empty()
				for yy in range(y, y2 + 1):
					for zz in range(z, z2 + 1):
						for xx in range(x, x2 + 1):
							var ci := _cell_index(Vector3i(xx, yy, zz), dims)
							taken[ci] = false
							if all_seen:
								if seen[ci].size.x < 0.0:
									all_seen = false
								else:
									tight = seen[ci] if first else tight.merge(seen[ci])
									first = false
				var from := box.position + Vector3(x, y, z) * cell
				var to := box.position + Vector3(x2 + 1, y2 + 1, z2 + 1) * cell
				to = Vector3(minf(to.x, box.end.x), minf(to.y, box.end.y), minf(to.z, box.end.z))
				var whole := AABB(from, to - from)
				if all_seen:
					var grown := tight
					for axis in 3:
						if grown.size[axis] < MIN_BOX:
							var mid := grown.position[axis] + grown.size[axis] * 0.5
							grown.position[axis] = mid - MIN_BOX * 0.5
							grown.size[axis] = MIN_BOX
					whole = whole.intersection(grown)
					if whole.size.x <= 0.0 or whole.size.y <= 0.0 or whole.size.z <= 0.0:
						whole = AABB(from, to - from)
				out.append(whole)
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
