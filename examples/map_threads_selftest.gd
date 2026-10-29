extends Node

## [DotMapParallelBuild]: the threaded load stages give byte-identical output to the inline ones.

const CHECKS := 47
const SECTIONS := 6
const FIXTURE := "res://examples/bsp_mesh/fixture"
const COPIES := 40
## A section that has not finished by then is a hang: a blocked main thread cannot time itself out, so a thread watches.
const SECTION_DEADLINE_MS := 90000

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()
var _entered := 0
var _completed := 0
var _frames := 0
var _section := "start"
var _section_since := Time.get_ticks_msec()
var _watching := true
var _watchdog := Thread.new()


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	print("dot-map threaded load")
	_watchdog.start(_watch)
	var world := _big_world()
	_test_defaults(world)
	_test_meshes(world)
	_test_shapes(world)
	_test_textures()
	_test_bake()
	await _test_async()
	_watching = false
	_watchdog.wait_to_finish()
	print("")
	print("%d passed, %d failed" % [_passed, _failed])
	for line in _failures:
		print("  FAIL  %s" % line)
	print("%d of %d sections ran to their last line" % [_completed, _entered])
	var bad := _entered != SECTIONS or _completed != _entered or _passed + _failed != CHECKS
	if bad:
		print("ERROR: %d checks in %d sections ran, %d in %d expected." % [_passed + _failed, _completed, CHECKS, SECTIONS])
	get_tree().quit(1 if bad or _failed > 0 else 0)


func _watch() -> void:
	while _watching:
		OS.delay_msec(250)
		var stuck := Time.get_ticks_msec() - _section_since
		if _watching and stuck > SECTION_DEADLINE_MS:
			print("HANG: section '%s' has run %d s without finishing, %d checks done; killing the run" % [_section, stuck / 1000, _passed + _failed])
			OS.kill(OS.get_process_id())


## Names the section now running and restarts its deadline.
func _enter(section: String) -> void:
	_entered += 1
	_section = section
	_section_since = Time.get_ticks_msec()


func _process(_delta: float) -> void:
	_frames += 1


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
	_enter("defaults")
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
	_enter("meshes")
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
	_enter("shapes")
	var base := _shape_digest(world, 0)
	_check(base[0] == 2 * COPIES and base[1] > 0, "%d hulls, %d concave shapes" % [base[0], base[1]])
	for workers in [1, 2, 4, -1]:
		var got := _shape_digest(world, workers)
		_check(got[0] == base[0] and got[1] == base[1], "shape counts with %d workers" % workers)
		_check(got[2] == base[2] and got[3] == base[3], "hull points and faces with %d workers" % workers)
	_completed += 1


func _test_textures() -> void:
	_enter("textures")
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
	var half_n := DotMapParallelBuild.textures(parts, 2, 0, false, true)
	var formats := []
	for p in parts:
		formats.append((slim[p] as Texture2D).get_image().get_format())
		DirAccess.remove_absolute(p)
	var want_formats := [Image.FORMAT_RGB8, Image.FORMAT_RG8, Image.FORMAT_R8, Image.FORMAT_R8]
	if DotMapSurfaces.baked_variant() == "s3tc":
		want_formats = [Image.FORMAT_DXT1, Image.FORMAT_RGTC_RG, Image.FORMAT_RGTC_R, Image.FORMAT_RGTC_R]
	_check(formats == want_formats, "a set keeps only the channels it samples: albedo RGB, normal RG, roughness and AO R (%s)" % str(formats))
	var widths := []
	for p in parts:
		widths.append([(slim[p] as Texture2D).get_width(), (half[p] as Texture2D).get_width()])
	_check(widths == [[32, 32], [32, 32], [32, 16], [32, 16]], "half_res_masks halves roughness and AO only (%s)" % str(widths))
	var widths_n := []
	for p in parts:
		widths_n.append((half_n[p] as Texture2D).get_width())
	_check(widths_n == [32, 16, 32, 32], "half_res_normals halves the normal map only (%s)" % str(widths_n))
	_check(DotMapSurfaces.halves("normal", true, false) == false and DotMapSurfaces.halves("normal", false, true), "halves() reads each option for its own parts")
	_test_model_halving()
	_completed += 1



## A library model's roughness, metallic, AO and normal maps are halved; albedo is not, and a shared ORM image stays shared.
func _test_model_halving() -> void:
	var raw := func(): return ImageTexture.create_from_image(Image.create(32, 32, false, Image.FORMAT_RGB8))
	var packed: ImageTexture = raw.call()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = raw.call()
	mat.normal_enabled = true
	mat.normal_texture = raw.call()
	mat.roughness_texture = packed
	mat.metallic_texture = packed
	mat.ao_enabled = true
	mat.ao_texture = packed
	var mi := MeshInstance3D.new()
	mi.mesh = QuadMesh.new()
	mi.mesh.surface_set_material(0, mat)
	var holder := Node3D.new()
	holder.add_child(mi)
	var kept := DotMapBspMesh.model_half_masks
	var kept_n := DotMapBspMesh.model_half_normals
	DotMapBspMesh.model_half_masks = true
	DotMapBspMesh.model_half_normals = true
	DotMapBspMesh.slim_model_textures(holder, 0)
	var ws := [mat.albedo_texture.get_width(), mat.normal_texture.get_width(), mat.roughness_texture.get_width(), mat.ao_texture.get_width()]
	_check(ws == [32, 16, 16, 16], "slim_model_textures halves normal, roughness and AO but not albedo (%s)" % str(ws))
	_check(mat.roughness_texture == mat.ao_texture and mat.ao_texture == mat.metallic_texture, "a shared ORM image is still one texture after halving")
	_check(DotMapBspMesh.slot_halves(BaseMaterial3D.TEXTURE_ALBEDO, true, true) == false and DotMapBspMesh.slot_halves(BaseMaterial3D.TEXTURE_EMISSION, true, true) == false,
			"albedo and emission are never halved")
	DotMapBspMesh.slim_model_textures(holder, 0)
	_check(mat.normal_texture.get_width() == 8, "an already compressed map loses its top mip without a re-encode (%d)" % mat.normal_texture.get_width())
	var second := StandardMaterial3D.new()
	second.roughness_texture = raw.call()
	second.normal_enabled = true
	second.normal_texture = raw.call()
	mi.mesh = QuadMesh.new()
	mi.mesh.surface_set_material(0, second)
	DotMapBspMesh.model_half_masks = false
	DotMapBspMesh.model_half_normals = false
	DotMapBspMesh.slim_model_textures(holder, 0)
	_check(second.roughness_texture.get_width() == 32 and second.normal_texture.get_width() == 32, "both options off leave the maps at full size (%d, %d)" % [second.roughness_texture.get_width(), second.normal_texture.get_width()])
	DotMapBspMesh.model_half_masks = kept
	DotMapBspMesh.model_half_normals = kept_n
	holder.free()


func _noise_webp(path: String, size: int, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			img.set_pixel(x, y, Color(rng.randf(), rng.randf(), rng.randf()))
	img.save_webp(path, true)


## The pre-baked files equal what the runtime builds, are capped, and are read from beside the source.
func _test_bake() -> void:
	_enter("bake")
	var store := "user://bake_store"
	var out := "user://bake_out"
	DirAccess.make_dir_recursive_absolute(store + "/set_a/1k")
	var parts := ["albedo", "normal", "roughness", "ao"]
	for i in 4:
		_noise_webp("%s/set_a/1k/%s.webp" % [store, parts[i]], 256 if i == 0 else 64, i + 1)
	var stats := DotMapTextureBake.bake_store(store, out, 128)
	_check(stats["baked"] == 4 and stats["failed"] == 0, "four files baked into a scratch directory (%s)" % str(stats))
	var again := DotMapTextureBake.bake_store(store, out, 128)
	_check(again["skipped"] == 4 and again["baked"] == 0, "a second bake skips what is current (%s)" % str(again))
	var both := FileAccess.file_exists(out + "/set_a/1k/albedo.s3tc.res") and FileAccess.file_exists(out + "/set_a/1k/albedo.etc2.res")
	_check(both and not FileAccess.file_exists(store + "/set_a/1k/albedo.s3tc.res"), "both variants written under --out, none beside the source")
	var tex := ResourceLoader.load(out + "/set_a/1k/albedo.s3tc.res") as Texture2D
	_check(tex != null and tex.get_width() == 128, "the 256 px albedo is capped to 128 (%s)" % str(tex.get_width() if tex != null else -1))
	var want := Image.load_from_file(store + "/set_a/1k/normal.webp")
	DotMapSurfaces.prepare_image(want, "normal.webp", 128, false, Image.COMPRESS_S3TC)
	var got := (ResourceLoader.load(out + "/set_a/1k/normal.s3tc.res") as Texture2D).get_image()
	_check(got.is_compressed() and got.get_mipmap_count() == want.get_mipmap_count() and got.get_format() == want.get_format() and got.get_data() == want.get_data(), "a baked normal map is the runtime's own compressed, mip-mapped RG image (format %d)" % got.get_format())
	DotMapTextureBake.bake_store(store, "", 128)
	var surfaces := DotMapSurfaces.new()
	var p := store + "/set_a/1k/albedo.webp"
	if DotMapSurfaces.baked_variant().is_empty():
		_check(true, "no VRAM format on this build: the runtime keeps decoding")
		_check(true, "-")
		_check(true, "-")
	else:
		surfaces.max_texture_size = 128
		var baked := surfaces._baked_texture(p)
		_check(baked != null and baked.get_width() == 128, "the runtime takes the baked file beside the source")
		surfaces.max_texture_size = 64
		_check(surfaces._baked_texture(p) == null, "a baked file larger than max_texture_size is refused")
		surfaces.max_texture_size = 2048
		surfaces.half_res_masks = true
		var rough_half := surfaces._file_texture(store + "/set_a/1k/roughness.webp")
		_check(rough_half != null and rough_half.get_width() == 32, "half_res_masks halves a baked roughness map too (%s)" % (rough_half.get_width() if rough_half != null else -1))
	surfaces.half_res_masks = false
	surfaces._textures.clear()
	var file_tex := surfaces._file_texture(store + "/set_a/1k/roughness.webp")
	_check(file_tex != null and file_tex.get_width() == 64, "_file_texture returns the texture either way")
	for dir in [store, out]:
		_remove_tree(dir)
	_completed += 1


## Frames advance while textures are decoded in slices, and the result equals the blocking call.
func _test_async() -> void:
	_enter("async")
	var paths := PackedStringArray()
	for i in 48:
		var path := "user://map_async_%d.png" % i
		var img := Image.create(256, 256, false, Image.FORMAT_RGB8)
		img.fill(Color(i / 48.0, 0.4, 0.8))
		img.save_png(path)
		paths.append(path)
	var base := DotMapParallelBuild.textures(paths, 2)
	var before := _frames
	var got: Dictionary = await DotMapParallelBuild.textures_async(paths, 2, 0, false, 0)
	_check(_frames - before >= 3, "the main loop ran %d frames during the prefetch" % (_frames - before))
	var same := got.size() == base.size()
	for p: String in base:
		same = same and got.has(p) and (base[p] as Texture2D).get_image().get_data() == (got[p] as Texture2D).get_image().get_data()
	_check(same, "the sliced prefetch decodes the same pixels as the blocking one")
	before = _frames
	await DotMapParallelBuild.textures_async(paths, 2, 0, false, 100000)
	_check(_frames == before, "a long slice does not yield")
	for p in paths:
		DirAccess.remove_absolute(p)
	_completed += 1


func _remove_tree(dir: String) -> void:
	for sub in DirAccess.get_directories_at(dir):
		_remove_tree(dir.path_join(sub))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
