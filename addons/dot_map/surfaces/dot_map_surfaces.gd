class_name DotMapSurfaces
extends "dot_map_surfaces_kinds.gd"

## A surface kind ([code]&"brick"[/code]) to a world-space triplanar [StandardMaterial3D]: a code-built box has no UVs, and this keeps texel density equal on every wall.
## Textures load by path under [member root] (or [member path_fn]), never referenced by a scene, so a delivered pack that mounts elsewhere still finds them.
## Albedo is untouched ([param tint] multiplies it); normal maps are the OpenGL (Y+) convention. Credits: [code]surfaces/CREDITS.md[/code].

## A `material_for` callable for [method DotMapBspMesh.build_node] that draws a converted map with its free
## textures: a surface's `free` key names a surface kind, or a generated flat colour the pack carries as a file
## beside [param dir] (the pack's directory).
func world_material_for(world: DotMapBspMesh, dir: String) -> Callable:
	var sets := _note_sets(world, dir)
	_prefetch(world, sets["generated"], sets["library"], sets["stand_in"])
	return _material_callable(world, sets["generated"], sets["library"], sets["stand_in"], dir)


## [method world_material_for] whose texture decode yields a frame whenever [param slice_ms] has passed ([method prefetch]), so the decode never holds one frame.
## Each surface's material is then made here, a frame yielded before one that might not fit in what is left of [param slice_ms] (the dearest yet is the guess): making one uploads its textures (6-12 ms for a large set), and the mesh build that follows finds them all made.
func world_material_for_async(world: DotMapBspMesh, dir: String, slice_ms: int = 8) -> Callable:
	var sets := _note_sets(world, dir)
	_tell("materials: sets noted")
	await _prefetch_async(world, sets["generated"], sets["library"], slice_ms, sets["stand_in"])
	_tell("materials: prefetched")
	await _warm_textures_async(world, sets, dir, slice_ms)
	var material_for := _material_callable(world, sets["generated"], sets["library"], sets["stand_in"], dir)
	await _make_materials_async(world, material_for, slice_ms)
	return material_for


## Reads each texture file the surfaces use that the prefetch left (no loader threads, or one it could not take), one file per step, a frame yielded before one that might not fit in what is left of [param slice_ms]. A set's albedo, normal, roughness and AO decode (and mip and compress) 4-18 ms together: made inside one material they held one frame. [method _file_texture] caches by path, so the material built later finds each and looks the same.
func _warm_textures_async(world: DotMapBspMesh, sets: Dictionary, dir: String, slice_ms: int) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var files := PackedStringArray()
	var used := {}
	for rec: Dictionary in world.surfaces:
		if rec.has("glass") or rec.get("water", false):
			continue
		used[str(rec.get("free", ""))] = true
		used[str(rec.get("free2", ""))] = true
		if use_original_textures and str(rec.get("orig", "")) != "":
			files.append(dir.path_join(str(rec["orig"])))
	var lit := use_lightmap and world.has_lightmap()
	var library: Dictionary = sets["library"]
	var generated: Dictionary = sets["generated"]
	var stand_in: Dictionary = sets["stand_in"]
	for key: String in used:
		if library.has(key):
			for part in ["albedo", "normal", "roughness", "ao"]:
				var found := _set_file(library[key], part)
				if not found.is_empty():
					files.append(found)
		elif lit and generated.has(key):
			files.append(generated[key])
		elif stand_in.has(key) and (stand_in[key] as Dictionary).has("file"):
			files.append(str(stand_in[key]["file"]))
	var pace := {"since": Time.get_ticks_usec() - slice_ms * 1000, "guess": 0}
	if lit:    # the first lit material builds the baked light's atlas pages: one per step here, and the floor light's scan
		var pages: Array = (world.manifest.get("lightmap", {}) as Dictionary).get("pages", [])
		for i in pages.size():
			await _pace(pace, slice_ms, tree)
			var t := Time.get_ticks_usec()
			world.lightmap_page(i)
			pace["guess"] = maxi(pace["guess"], Time.get_ticks_usec() - t)
		await _pace(pace, slice_ms, tree)
		world.light_floor()
	var seen := {}
	for p in files:
		if seen.has(p) or _textures.has(p):
			continue
		seen[p] = true
		await _warm_file_async(p, pace, slice_ms, tree)


## [method _file_texture] for a file only a raw decode can give, in its three steps (decode, mip, compress) each its own piece of the budget; the same calls in the same order, so the texture is the same. An imported or pre-baked file is one cheap load: left to [method _file_texture].
func _warm_file_async(path: String, pace: Dictionary, slice_ms: int, tree: SceneTree) -> void:
	if (path.begins_with("res://") and ResourceLoader.exists(path)) or _baked_texture(path) != null:
		await _pace(pace, slice_ms, tree)
		var t := Time.get_ticks_usec()
		_file_texture(path)
		pace["guess"] = maxi(pace["guess"], Time.get_ticks_usec() - t)
		return
	await _pace(pace, slice_ms, tree)
	var t0 := Time.get_ticks_usec()
	var img := Image.load_from_file(path)
	pace["guess"] = maxi(pace["guess"], Time.get_ticks_usec() - t0)
	if img == null:
		return
	await _pace(pace, slice_ms, tree)
	t0 = Time.get_ticks_usec()
	var shrunk := DotMapImagePrep.shrink_image(img, path, max_texture_size, half_res_masks, half_res_normals)
	pace["guess"] = maxi(pace["guess"], Time.get_ticks_usec() - t0)
	if shrunk:
		await _pace(pace, slice_ms, tree)
		t0 = Time.get_ticks_usec()
		DotMapImagePrep.compress_image(img, -1)
		pace["guess"] = maxi(pace["guess"], Time.get_ticks_usec() - t0)
	await _pace(pace, slice_ms, tree)
	_textures[path] = ImageTexture.create_from_image(img)


## Yields a frame when what [param pace] says was spent this frame plus its dearest step yet would pass [param slice_ms].
func _pace(pace: Dictionary, slice_ms: int, tree: SceneTree) -> void:
	var spent := Time.get_ticks_usec() - int(pace["since"])
	if spent > 1000 and spent + int(pace["guess"]) >= slice_ms * 1000:
		await tree.process_frame
		pace["since"] = Time.get_ticks_usec()


func _tell(label: String) -> void:
	if on_step.is_valid():
		on_step.call(label)


## Calls [param material_for] on each surface ahead of the mesh build. One already made is a cache hit: it costs microseconds and never raises the guess.
func _make_materials_async(world: DotMapBspMesh, material_for: Callable, slice_ms: int) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var since := Time.get_ticks_usec() - slice_ms * 1000    # the decode before used this frame: the first one starts a new one
	var guess := 0    # the dearest material yet, the guess for the next one
	for rec: Dictionary in world.surfaces:
		if rec.has("glass") or rec.get("water", false):
			continue    # glass is the mesh's own; water is shared
		var spent := Time.get_ticks_usec() - since
		# Over 1 ms spent: when the guess alone is over the budget, a run of cache hits must not pause before each.
		if spent > 1000 and spent + guess >= slice_ms * 1000:
			await tree.process_frame
			since = Time.get_ticks_usec()
		var t := Time.get_ticks_usec()
		material_for.call(rec)
		var took := Time.get_ticks_usec() - t
		guess = maxi(guess, took)
		if took > SLOW_MATERIAL_USEC:
			_tell("materials: %s took %.1f ms" % [str(rec.get("free", "")), took / 1000.0])
	await tree.process_frame    # the mesh build that follows starts a frame of its own
	DotLog.debug(CHANNEL, "world materials made ahead", {"surfaces": world.surfaces.size(), "dearest_ms": guess / 1000.0})


func _note_sets(world: DotMapBspMesh, dir: String) -> Dictionary:
	var sets := _resolve_sets(world, dir)
	for key: String in sets["missing"]:
		if not missing_sets.has(key):
			missing_sets.append(key)
	if not (sets["stand_in"] as Dictionary).is_empty():
		DotLog.debug(CHANNEL, "PBR sets not installed; each is drawn as a stand-in kind in its faces' own colour", {"sets": (sets["stand_in"] as Dictionary).size()})
	return sets


## Reads the map's textures ahead of [method world_material_for] without holding the main thread: decoded in batches on workers, a frame yielded whenever [param slice_ms] has passed, so dot-cloud's fetch callbacks and the loading cover keep running. The later [method world_material_for] finds them cached. Inline (no yield) when there are no workers.
func prefetch(world: DotMapBspMesh, dir: String, slice_ms: int = 8) -> void:
	var sets := _resolve_sets(world, dir)
	await _prefetch_async(world, sets["generated"], sets["library"], slice_ms, sets["stand_in"])


func _resolve_sets(world: DotMapBspMesh, dir: String) -> Dictionary:
	var generated := {}
	var library := {}
	var store := str(world.licence().get("pbr_store", ""))
	for t: Dictionary in world.licence().get("textures", []):
		if str(t["kind"]) == "generated":
			generated[str(t["key"])] = dir.path_join(str(t["file"]))
		elif str(t["kind"]) == "pbr":
			library[str(t["key"])] = _pbr_dir(dir, store, t)
	var stand_in := {}
	var missing := []
	for key: String in library.keys():
		if not _has_set(library[key]):
			stand_in[key] = _pack_fallback(dir, key, world.licence())
			library.erase(key)
			missing.append(key)
	return {"generated": generated, "library": library, "stand_in": stand_in, "missing": missing}


func _material_callable(world: DotMapBspMesh, generated: Dictionary, library: Dictionary, stand_in: Dictionary, dir: String = "") -> Callable:
	var cache := {}
	return func(rec: Dictionary) -> Material:
		if rec.get("water", false):
			return water_material if water_material != null else liquid_material(liquid_kind(str(rec.get("material", ""))))
		var lit := use_lightmap and world.has_lightmap() and rec.has("lightmap_page") and not rec.has("glass")
		if rec.has("decal"):
			return _decal_material(world, rec, dir, lit)
		if use_original_textures and not rec.has("glass") and str(rec.get("orig", "")) != "":
			var own := _original_material(world, rec, dir, lit, cache)
			if own != null:
				return own
		var free := str(rec.get("free", ""))
		var tint := Color.WHITE
		# A blend's average is two textures' (grass and rock), never the one drawn: left untinted.
		var blend := str(rec.get("material", "")).get_file().to_lower().begins_with("blend")
		if match_original and not generated.has(free) and not library.has(free) and not blend:
			tint = original_tint(StringName(free.get_slice(":", 0)), rec.get("colour", []))
		if stand_in.has(free):
			return _stand_in_material(world, rec, stand_in[free], cache)
		var free2 := str(rec.get("free2", ""))
		if not library.has(free2):
			free2 = ""
		var key := "%s|%s|%s|%s|%s" % [free, free2, tint.to_html(), rec.get("lightmap_page", -1) if lit else -1, rec.get("emissive", false)]
		if cache.has(key):
			return cache[key]
		var m: Material
		if lit:
			var file: String = generated.get(free, "")
			m = _lightmapped(world, rec, free, tint, file, library.get(free, ""))
			if not free2.is_empty() and m is ShaderMaterial:
				m.set_shader_parameter("albedo2_tex", _set_texture(library[free2], "albedo"))
				m.set_shader_parameter("has_blend", true)
		elif library.has(free) and not free2.is_empty():
			m = _blended_material(library[free], library[free2], free)
		elif library.has(free):
			m = _pbr_material(library[free], free)
		elif generated.has(free):
			var sm := StandardMaterial3D.new()
			sm.albedo_texture = ImageTexture.create_from_image(Image.load_from_file(generated[free]))
			sm.uv1_triplanar = true
			sm.uv1_world_triplanar = true
			sm.uv1_scale = Vector3.ONE * 0.4
			m = sm
		else:
			m = material(StringName(free.get_slice(":", 0)), tint)
		cache[key] = m
		return m


## The material of a surface drawn with the map's own texture at the mesh UVs, or null when the pack has no such file. One per texture and lightmap page.
func _original_material(world: DotMapBspMesh, rec: Dictionary, dir: String, lit: bool, cache: Dictionary) -> Material:
	var file := dir.path_join(str(rec["orig"]))
	var key := "orig|%s|%s|%s" % [file, rec.get("lightmap_page", -1) if lit else -1, rec.get("emissive", false)]
	if cache.has(key):
		return cache[key]
	var tex := _file_texture(file)
	if tex == null:
		return null
	var m: Material
	if lit:
		var sm := _lightmapped(world, rec, "orig", Color.WHITE, "", "", tex)
		if sm is ShaderMaterial:
			(sm as ShaderMaterial).set_shader_parameter("use_uv", true)
		m = sm
	else:
		var st := StandardMaterial3D.new()
		st.albedo_texture = tex
		st.texture_repeat = true
		m = st
	cache[key] = m
	return m


## A decal surface's alpha-blended material: the map's own texture in an internal pack (use_original_textures),
## else the kind's drawn pattern; lit by the bake's page when [param lit]. One per kind, texture and page.
func _decal_material(world: DotMapBspMesh, rec: Dictionary, dir: String, lit: bool) -> Material:
	var tex: Texture2D = null
	if use_original_textures and str(rec.get("orig", "")) != "":
		tex = _file_texture(dir.path_join(str(rec["orig"])))
	var light := {}
	if lit:
		light = {"lightmap": world.lightmap_page(int(rec["lightmap_page"])), "exposure": world.lightmap_scale(),
				"floor": world.light_floor(), "emissive": emissive_energy if rec.get("emissive", false) else 0.0}
	return DotMapBspMesh.decal_material(StringName(str(rec["decal"])), rec.get("colour", []), tex, light)


## Splits the files the world's surfaces use into those still to decode from disk and the imported ones (already requested); a pre-baked file is taken here.
func _prefetch_plan(world: DotMapBspMesh, generated: Dictionary, library: Dictionary, stand_in: Dictionary = {}) -> Dictionary:
	var used := {}
	for rec: Dictionary in world.surfaces:
		used[str(rec.get("free", ""))] = true
		used[str(rec.get("free2", ""))] = true
	var files := PackedStringArray()
	for key: String in generated:
		if used.has(key) and use_lightmap and world.has_lightmap():    # the unlit branch decodes its own, unmipped
			files.append(generated[key])
	for key: String in library:
		if used.has(key):
			for part in ["albedo", "normal", "roughness", "ao"]:
				var found := _set_file(library[key], part)
				if not found.is_empty():
					files.append(found)
	for key: String in stand_in:    # a stand-in's webp decodes 5-15 ms: on a worker, not in the material
		if used.has(key) and (stand_in[key] as Dictionary).has("file"):
			files.append(str(stand_in[key]["file"]))
	var disk := PackedStringArray()
	var imported := PackedStringArray()
	var baked := 0
	for p in files:
		if _textures.has(p):
			continue
		if p.begins_with("res://") and ResourceLoader.exists(p):
			imported.append(p)
			ResourceLoader.load_threaded_request(p)
			continue
		var b := _baked_texture(p)
		if b != null:
			_textures[p] = _masked(p, b)
			baked += 1
		else:
			disk.append(p)
	return {"disk": disk, "imported": imported, "baked": baked}


func _prefetch(world: DotMapBspMesh, generated: Dictionary, library: Dictionary, stand_in: Dictionary = {}) -> void:
	if DotParallel.resolve_workers(load_threads) == 0:
		return
	var plan := _prefetch_plan(world, generated, library, stand_in)
	var started := Time.get_ticks_msec()
	_textures.merge(DotMapParallelBuild.textures(plan["disk"], load_threads, max_texture_size, half_res_masks, half_res_normals))
	_prefetch_done(plan, Time.get_ticks_msec() - started)


func _prefetch_async(world: DotMapBspMesh, generated: Dictionary, library: Dictionary, slice_ms: int, stand_in: Dictionary = {}) -> void:
	if DotParallel.resolve_workers(load_threads) == 0:
		return
	var plan := _prefetch_plan(world, generated, library, stand_in)
	var started := Time.get_ticks_msec()
	_textures.merge(await DotMapParallelBuild.textures_async(plan["disk"], load_threads, max_texture_size, half_res_masks, slice_ms, half_res_normals))
	# load_threaded_get blocks until its load is done: wait for the imported ones a frame at a time instead.
	var tree := Engine.get_main_loop() as SceneTree
	for p: String in plan["imported"]:
		while tree != null and ResourceLoader.load_threaded_get_status(p) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await tree.process_frame
	_prefetch_done(plan, Time.get_ticks_msec() - started)


func _prefetch_done(plan: Dictionary, decode_ms: int) -> void:
	for p: String in plan["imported"]:
		var tex := ResourceLoader.load_threaded_get(p) as Texture2D
		if tex != null:    # a stray .import marker whose .ctex is not mounted loads null: leave it to the raw read in _file_texture
			_textures[p] = _masked(p, tex)
	DotLog.info(CHANNEL, "texture prefetch", {"disk": plan["disk"].size(), "baked": plan["baked"], "decode_ms": decode_ms, "imported": plan["imported"].size(), "formats": texture_report(_textures), "static_mb": OS.get_static_memory_usage() / 1048576})


## Compiles the world shaders (lightmapped, blended, liquid) one per frame of [param tree], so the first converted world drawn later does not stop a frame for the compile (about 85 ms for the lightmapped one on a desktop GPU). Call once at a quiet moment, e.g. under a boot cover; a second call returns at once.
static func warm_shaders_async(tree: SceneTree) -> void:
	if not _warm_materials.is_empty():
		return
	for shader: Shader in [LIGHTMAPPED, BLENDED, LIQUID]:
		var m := ShaderMaterial.new()
		m.shader = shader
		_warm_materials.append(m)
		await tree.process_frame


## Texture count and megabytes per image format, for the memory log.
static func texture_report(textures: Dictionary) -> Dictionary:
	var out := {}
	for t: Variant in textures.values():
		if t is CompressedTexture2D or t is ImageTexture:
			var img := (t as Texture2D).get_image()
			if img != null:
				var key := str(img.get_format())
				var e: Array = out.get(key, [0, 0])
				e[0] += 1
				e[1] += img.get_data().size() / 1048576.0
				out[key] = e
	return out


## The kind that stands in for a texture named [param name] (a PBR set id or a source path) when its files are missing; &"" when no word fits.
func stand_in_kind(name: String) -> StringName:
	if _rules.is_empty():
		for r: Array in NAME_RULES:
			var re := RegEx.new()
			re.compile("(?<![a-z])(?:%s)" % r[0])
			_rules.append([re, r[1]])
	var parts := name.to_lower().replace("\\", "/").split("/")
	var text := "/".join(parts.slice(maxi(parts.size() - 2, 0)))
	for r: Array in _rules:
		if (r[0] as RegEx).search(text) != null:
			return r[1]
	return &""


## What a missing set is drawn as: `{file}` for the pack's own low-resolution albedo, else `{kind}` (a photo kind, or &"" for flat colour).
func _pack_fallback(dir: String, key: String, licence: Dictionary) -> Dictionary:
	for t: Dictionary in licence.get("textures", []):
		if str(t.get("key", "")) != key:
			continue
		var small := str(t.get("fallback_file", ""))
		if not small.is_empty() and (FileAccess.file_exists(dir.path_join(small)) or ResourceLoader.exists(dir.path_join(small))):
			return {"file": dir.path_join(small), "colour": t.get("colour", [])}
		var kind := stand_in_kind(str(t.get("file", "")).get_file())
		for src: Variant in t.get("sources", []):
			if kind == &"":
				kind = stand_in_kind(str(src))
		if kind != &"" and _load("%s/%s/albedo.jpg" % [root, resolve(kind)]) == null:
			kind = &""
		return {"kind": kind, "colour": t.get("colour", [])}
	return {"kind": &"", "colour": []}


## A face whose PBR set is missing: the pack's small albedo, else the stand-in kind tinted to the face's average colour, else that colour flat; lit by the map's lightmap when it has one.
func _stand_in_material(world: DotMapBspMesh, rec: Dictionary, fb: Dictionary, cache: Dictionary) -> Material:
	var colour: Variant = rec.get("colour", fb.get("colour", []))
	if not colour is Array or (colour as Array).size() < 3:
		colour = [0.5, 0.5, 0.5]
	var kind: StringName = fb.get("kind", &"")
	var tint := Color.WHITE
	if not fb.has("file"):
		tint = original_tint(kind, colour) if kind != &"" else Color(float(colour[0]), float(colour[1]), float(colour[2]))
		if kind == &"":
			var g := maxf(0.299 * tint.r + 0.587 * tint.g + 0.114 * tint.b, STAND_IN_FLOOR)    # neutral grey: a face's own average hue read as flat blue and teal walls
			tint = Color(g, g, g)
	var lit := use_lightmap and world.has_lightmap() and rec.has("lightmap_page") and not rec.has("glass")
	var key := "stand_in|%s|%s|%s|%s" % [fb.get("file", kind), tint.to_html(), rec.get("lightmap_page", -1) if lit else -1, rec.get("emissive", false)]
	if cache.has(key):
		return cache[key]
	var m: Material
	if lit:
		if fb.has("file"):
			m = _lightmapped(world, rec, "stand_in", tint, str(fb["file"]))
		elif kind != &"":
			m = _lightmapped(world, rec, String(kind), tint, "")
		else:
			m = _lightmapped(world, rec, "flat", tint, "", "", _white())
	elif fb.has("file"):
		var sm := StandardMaterial3D.new()
		sm.albedo_texture = _file_texture(str(fb["file"]))
		sm.uv1_triplanar = true
		sm.uv1_world_triplanar = true
		sm.uv1_scale = Vector3.ONE * 0.5
		m = sm
	elif kind != &"":
		m = material(kind, tint)
	else:
		var flat := StandardMaterial3D.new()
		flat.albedo_color = tint
		flat.roughness = 0.9
		m = flat
	cache[key] = m
	return m


## A two-layer terrain without a bake: both sets' albedo, mixed by the vertex weight (the unlit twin of the lit blend).
func _blended_material(dir: String, dir2: String, key: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.resource_name = key
	m.shader = BLENDED
	m.set_shader_parameter("albedo_tex", _set_texture(dir, "albedo"))
	m.set_shader_parameter("albedo2_tex", _set_texture(dir2, "albedo"))
	m.set_shader_parameter("sharpness", sharpness)
	return m


func _lightmapped(world: DotMapBspMesh, rec: Dictionary, free: String, tint: Color, generated_file: String, set_dir: String = "", texture: Texture2D = null) -> Material:
	var kind := StringName(free.get_slice(":", 0))
	var tex: Texture2D = texture
	var metres := 2.5
	if tex == null and not set_dir.is_empty():
		tex = _set_texture(set_dir, "albedo")
		metres = 2.0
	elif tex == null and not generated_file.is_empty():
		tex = _file_texture(generated_file)
	elif tex == null:
		var k := resolve(kind)
		if k != &"":
			tex = _load("%s/%s/albedo.jpg" % [root, k])
			metres = float(KINDS[k]["meters"])
	if tex == null:
		return material(kind, tint)
	var m := ShaderMaterial.new()
	m.resource_name = free
	m.shader = LIGHTMAPPED
	m.set_shader_parameter("albedo_tex", tex)
	m.set_shader_parameter("lightmap", world.lightmap_page(int(rec["lightmap_page"])))
	m.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	m.set_shader_parameter("metres", metres)
	if not set_dir.is_empty():
		for pair in [["normal", "normal_tex"], ["roughness", "rough_tex"], ["ao", "ao_tex"]]:
			var pt := _set_texture(set_dir, pair[0])
			if pt != null:
				m.set_shader_parameter(pair[1], pt)
				m.set_shader_parameter("has_" + pair[0], true)
	m.set_shader_parameter("sharpness", sharpness)
	m.set_shader_parameter("exposure", world.lightmap_scale())
	var fl := world.light_floor()
	m.set_shader_parameter("floor_light", Vector3(fl.r, fl.g, fl.b))
	m.set_shader_parameter("max_chroma_ratio", DotMapBspMesh.lightmap_max_chroma_ratio)
	if rec.get("emissive", false):
		m.set_shader_parameter("emissive", emissive_energy)
	return m
