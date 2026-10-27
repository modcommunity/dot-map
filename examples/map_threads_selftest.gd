extends Node

## [DotMapParallelBuild]: the threaded load stages give byte-identical output to the inline ones.
##
## [codeblock]
## godot --headless --path . res://examples/map_threads_selftest.tscn
## [/codeblock]

const CHECKS := 28
const SECTIONS := 4
const FIXTURE := "res://examples/bsp_mesh/fixture"
const COPIES := 40

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()
var _entered := 0
var _completed := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	print("dot-map threaded load")
	var world := _big_world()
	_test_defaults(world)
	_test_meshes(world)
	_test_shapes(world)
	_test_textures()
	print("")
	print("%d passed, %d failed" % [_passed, _failed])
	for line in _failures:
		print("  FAIL  %s" % line)
	print("%d of %d sections ran to their last line" % [_completed, _entered])
	var bad := _entered != SECTIONS or _completed != _entered or _passed + _failed != CHECKS
	if bad:
		print("ERROR: %d checks in %d sections ran, %d in %d expected." % [_passed + _failed, _completed, CHECKS, SECTIONS])
	get_tree().quit(1 if bad or _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		_failures.append(what)


## The fixture's records repeated with other chunks, so a build has many groups, entries and batches.
func _big_world() -> DotMapBspMesh:
	var world: DotMapBspMesh = DotMapBspMesh.load_prefix(FIXTURE).value
	var surfaces: Array = []
	var hulls: Array = []
	for c in COPIES:
		for rec: Dictionary in world.surfaces:
			var copy := rec.duplicate()
			copy["chunk"] = [c % 7, -1]
			copy["collide"] = c % 2 == 0
			copy["material"] = "%s_%d" % [rec["material"], c % 3]
			surfaces.append(copy)
		hulls.append_array(world.hulls)
	world.surfaces = surfaces
	world.hulls = hulls
	return world


func _hash(v: Variant) -> String:
	return var_to_bytes(v).hex_encode().sha256_text()


func _mesh_digest(world: DotMapBspMesh, workers: int) -> Dictionary:
	world.load_threads = workers
	var mats: Array[Material] = [StandardMaterial3D.new(), StandardMaterial3D.new(), StandardMaterial3D.new()]
	var groups := world.build_meshes(0, func(rec: Dictionary) -> Material: return mats[int(str(rec["material"]).right(1))])
	var digest := []
	var verts := 0
	for g: Dictionary in groups:
		var mesh: ArrayMesh = g["mesh"]
		for s in mesh.get_surface_count():
			digest.append([mesh.surface_get_name(s), _hash(mesh.surface_get_arrays(s)), mats.find(mesh.surface_get_material(s))])
			verts += (mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		digest.append([g["chunk"], g["clusters"]])
	return {"hash": _hash(digest), "groups": groups.size(), "verts": verts}


func _test_defaults(world: DotMapBspMesh) -> void:
	_entered += 1
	_check(DotMapParallelBuild.default_workers == 0, "default is off")
	_check(world.load_threads == 0, "a new world is inline")
	_check(DotMapSurfaces.new().load_threads == 0, "new surfaces are inline")
	_check(DotParallel.resolve_workers(0) == 0, "0 resolves to no workers")
	DotParallel.reset_stats()
	_mesh_digest(world, 0)
	var stats: Dictionary = DotParallel.describe()["labels"]
	_check(stats.has("map.mesh") and int(stats["map.mesh"]["pooled"]) == 0, "cvar 0 never reaches the pool")
	_completed += 1


func _test_meshes(world: DotMapBspMesh) -> void:
	_entered += 1
	var base := _mesh_digest(world, 0)
	_check(int(base["groups"]) >= 7 and int(base["verts"]) > 1000, "the synthetic world has %d groups, %d vertices" % [base["groups"], base["verts"]])
	for workers in [1, 2, 4, -1]:
		var got := _mesh_digest(world, workers)
		_check(got["hash"] == base["hash"], "meshes with %d workers equal inline" % workers)
		_check(got["groups"] == base["groups"] and got["verts"] == base["verts"], "mesh and vertex counts with %d workers" % workers)
	if DotParallel.available():
		var stats: Dictionary = DotParallel.describe()["labels"]
		_check(int(stats["map.mesh"]["pooled"]) > 0, "a worker count above 0 runs on the pool")
	else:
		_check(true, "no pool on this machine; the inline path ran for every count")
	_completed += 1


func _shape_digest(world: DotMapBspMesh, workers: int) -> Array:
	world.load_threads = workers
	var hulls := world.hull_shapes(0)
	var points := hulls.map(func(h: Dictionary) -> Variant: return [(h["shape"] as ConvexPolygonShape3D).points, h["kind"], h["brush"]])
	var faces := world.concave_shapes(0).map(func(s: ConcavePolygonShape3D) -> Variant: return s.get_faces())
	return [hulls.size(), faces.size(), _hash(points), _hash(faces)]


func _test_shapes(world: DotMapBspMesh) -> void:
	_entered += 1
	var base := _shape_digest(world, 0)
	_check(base[0] == 2 * COPIES and base[1] > 0, "%d hulls, %d concave shapes" % [base[0], base[1]])
	for workers in [1, 2, 4, -1]:
		var got := _shape_digest(world, workers)
		_check(got[0] == base[0] and got[1] == base[1], "shape counts with %d workers" % workers)
		_check(got[2] == base[2] and got[3] == base[3], "hull points and faces with %d workers" % workers)
	_completed += 1


func _test_textures() -> void:
	_entered += 1
	var paths := PackedStringArray()
	for i in 11:
		var img := Image.create(64 + 8 * i, 64, false, Image.FORMAT_RGB8)
		img.fill(Color(i / 11.0, 0.5, 1.0 - i / 11.0))
		img.set_pixel(i, i, Color.WHITE)
		var path := "user://map_threads_%d.png" % i
		img.save_png(path)
		paths.append(path)
	var base := DotMapParallelBuild.textures(paths, 0)
	_check(base.size() == 11, "eleven files decode (%d)" % base.size())
	var same := true
	for workers in [2, 4]:
		var got := DotMapParallelBuild.textures(paths, workers)
		same = same and got.size() == base.size()
		for p: String in base:
			var a: Image = (base[p] as Texture2D).get_image()
			var b: Image = (got[p] as Texture2D).get_image()
			same = same and a.get_data() == b.get_data() and a.get_mipmap_count() == b.get_mipmap_count() and a.get_format() == b.get_format()
	_check(same, "decoded and mip-mapped pixels equal inline with 2 and 4 workers")
	for p in paths:
		DirAccess.remove_absolute(p)
	var parts := PackedStringArray()
	for part in ["albedo", "normal", "roughness", "ao"]:
		DirAccess.make_dir_recursive_absolute("user://map_threads_set")
		var path := "user://map_threads_set/%s.png" % part
		var img := Image.create(32, 32, false, Image.FORMAT_RGB8)
		img.fill(Color(0.6, 0.3, 0.9))
		img.save_png(path)
		parts.append(path)
	var slim := DotMapParallelBuild.textures(parts, 2)
	var half := DotMapParallelBuild.textures(parts, 2, 0, true)
	var formats := []
	for p in parts:
		formats.append((slim[p] as Texture2D).get_image().get_format())
		DirAccess.remove_absolute(p)
	_check(formats == [Image.FORMAT_RGB8, Image.FORMAT_RG8, Image.FORMAT_R8, Image.FORMAT_R8], "a set keeps only the channels it samples: albedo RGB, normal RG, roughness and AO R (%s)" % str(formats))
	var widths := []
	for p in parts:
		widths.append([(slim[p] as Texture2D).get_width(), (half[p] as Texture2D).get_width()])
	_check(widths == [[32, 32], [32, 32], [32, 16], [32, 16]], "half_res_masks halves roughness and AO only, and is off by default (%s)" % str(widths))
	_completed += 1
