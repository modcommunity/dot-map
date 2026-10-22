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
const VERSION := 1

## The renderer's limit on surfaces in one mesh; a chunk with more is split over meshes.
const MAX_SURFACES := 256

## Model 0 is the world; the rest are brush entities, one model each.
const WORLD := 0

var manifest: Dictionary = {}
var surfaces: Array = []
var hulls: Array = []
var source_path: String = ""

var _blob: PackedByteArray = PackedByteArray()
var _movers: Dictionary = {}


## Reads [code]<prefix>.json[/code] and [code]<prefix>.bin[/code].
static func load_prefix(prefix: String) -> DotResult:
	var json_path := prefix + ".json"
	if not FileAccess.file_exists(json_path):
		return DotResult.fail(DotError.CODE_IO, "no mesh manifest", json_path)
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
	for rec: Dictionary in doc.get("movers", []):
		var mi: Variant = rec.get("model")
		if mi is float or mi is int:        # a mover with no brushes of its own has a null model
			m._movers[int(mi)] = rec
	for rec: Dictionary in m.surfaces:
		if not m._fits(rec, 3 * 4 * int(rec.get("vertex_count", 0)), "position_offset") \
				or not m._fits(rec, 3 * 4 * int(rec.get("vertex_count", 0)), "normal_offset") \
				or not m._fits(rec, 2 * 4 * int(rec.get("vertex_count", 0)), "uv_offset") \
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
	var i := int(rec["index_offset"])
	arrays[Mesh.ARRAY_INDEX] = _blob.slice(i, i + 4 * int(rec["index_count"])).to_int32_array()
	return arrays


## A model's surfaces as meshes, grouped by chunk (the converter's columns of the world), each
## mesh under [constant MAX_SURFACES]. [param material_for] takes a surface record, returns a
## [Material] or null. Returns [code][{mesh: ArrayMesh, chunk: Array, sky3d: bool}][/code].
func build_meshes(model: int, material_for: Callable = Callable()) -> Array[Dictionary]:
	var groups := {}
	for rec: Dictionary in surfaces:
		if int(rec["model"]) != model:
			continue
		var key := "%s|%s" % [str(rec.get("chunk", [])), rec.get("sky3d", false)]
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(rec)
	var out: Array[Dictionary] = []
	for key: String in groups:
		var mesh: ArrayMesh = null
		for rec: Dictionary in groups[key]:
			if mesh == null or mesh.get_surface_count() >= MAX_SURFACES:
				mesh = ArrayMesh.new()
				out.append({"mesh": mesh, "chunk": rec.get("chunk", []), "sky3d": bool(rec.get("sky3d", false))})
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_arrays(rec))
			var s := mesh.get_surface_count() - 1
			mesh.surface_set_name(s, str(rec.get("material", "")))
			if material_for.is_valid():
				var mat: Variant = material_for.call(rec)
				if mat is Material:
					mesh.surface_set_material(s, mat)
	return out


## Convex shapes of a model's player-solid brushes, relative to [method model_origin].
## [param kinds] filters (empty is every kind). Returns [code][{shape, kind, brush}][/code].
func hull_shapes(model: int, kinds: PackedStringArray = PackedStringArray()) -> Array[Dictionary]:
	var origin := model_origin(model)
	var out: Array[Dictionary] = []
	for rec: Dictionary in hulls:
		if int(rec["model"]) != model or (not kinds.is_empty() and not str(rec["kind"]) in kinds):
			continue
		var p := int(rec["point_offset"])
		var pts := _blob.slice(p, p + 12 * int(rec["point_count"])).to_vector3_array()
		for k in pts.size():
			pts[k] -= origin
		var shape := ConvexPolygonShape3D.new()
		shape.points = pts
		out.append({"shape": shape, "kind": str(rec["kind"]), "brush": int(rec["brush"])})
	return out


## Triangle shapes for the surfaces that collide as drawn (displacements: terrain has no
## brushes), relative to [method model_origin].
func concave_shapes(model: int) -> Array[ConcavePolygonShape3D]:
	var origin := model_origin(model)
	var out: Array[ConcavePolygonShape3D] = []
	for rec: Dictionary in surfaces:
		if int(rec["model"]) != model or not rec.get("collide", false):
			continue
		var a := surface_arrays(rec)
		var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var index: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		var faces := PackedVector3Array()
		faces.resize(index.size())
		for k in index.size():
			faces[k] = verts[index[k]] - origin
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		out.append(shape)
	return out


## Every drawn model as a node tree: a [code]world[/code] child with one [MeshInstance3D] per
## chunk, and one [Node3D] per brush entity at its origin (named by its targetname when it has
## one, else [code]model_<n>[/code]), meta [code]model[/code] and [code]mover[/code] set.
## Drawing only: collision is [method hull_shapes] and [method concave_shapes], because which
## body and layer each goes on is the game's.
func build_node(material_for: Callable = Callable()) -> Node3D:
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
		for g: Dictionary in build_meshes(model, material_for):
			var mi := MeshInstance3D.new()
			mi.mesh = g["mesh"]
			mi.position = -parent.position
			var c: Array = g["chunk"]
			mi.name = "sky3d" if g["sky3d"] else ("chunk_%d_%d" % [c[0], c[1]] if c.size() == 2 else "mesh")
			parent.add_child(mi)
	return root


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
