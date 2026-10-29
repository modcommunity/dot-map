extends "mesh_solids.gd"

## The environment, sound and prop half of [DotMapBspMesh].

## The map's breakable brush entities: [code]{model, entity, classname, targetname, health, glass, material}[/code]
## ([code]glass[/code] is the kind when every drawn surface is glass, else empty).
func breakables() -> Array:
	return manifest.get("breakables", [])


## A [DotMapGlass] for each breakable glass model of [param root] (a [method build_node] result): its hulls
## as the body on [param collision_layer], the model's node as what it hides.
func build_breakables(root: Node3D, collision_layer: int = 1, authoritative: bool = true) -> Array[DotMapGlass]:
	var out: Array[DotMapGlass] = []
	for rec: Dictionary in breakables():
		if rec.get("glass") == null or str(rec.get("glass")).is_empty() or rec.get("model") == null:
			continue
		var model := int(rec["model"])
		var visual: Node3D = null
		for c in root.get_children():
			if c.has_meta(&"model") and int(c.get_meta(&"model")) == model:
				visual = c as Node3D
		var pane := DotMapGlass.new()
		pane.name = "breakable_%d" % model
		pane.model = model
		pane.kind = StringName(str(rec["glass"]))
		pane.health = float(rec.get("health", 1.0))
		pane.authoritative = authoritative
		pane.visual = visual
		pane.collision_layer = collision_layer
		pane.collision_mask = 0
		pane.position = model_origin(model)
		for h: Dictionary in hull_shapes(model):
			var cs := CollisionShape3D.new()
			cs.shape = h["shape"]
			pane.add_child(cs)
		root.add_child(pane)
		out.append(pane)
	return out


## Where [method build_sounds] and [method build_props] look for a stand-in by id when the
## game gives no callable: this addon's own free Kenney set, then dot-audio's stock beds.
const DEFAULT_SOUND_DIRS: PackedStringArray = [
	"res://addons/dot_map/sounds", "res://addons/dot_audio/stock/ambience"]
const DEFAULT_PROP_DIRS: PackedStringArray = ["res://addons/dot_map/props"]

## The stand-in models face +Z; a Source model faces +X at yaw 0.
const PROP_FACING_DEGREES := 90.0


## The manifest's [code]licence[/code] block (every free replacement with URL, author, licence), or {}.
func licence() -> Dictionary:
	return manifest.get("licence", {})


## True when the map went through the licence pass: a licence block and [code]free[/code] on every surface.
func is_free() -> bool:
	if licence().is_empty():
		return false
	for rec: Dictionary in surfaces:
		if not rec.has("free"):
			return false
	return true


static func _col(v: Variant, fallback: Color) -> Color:
	if v is Array and (v as Array).size() >= 3 and float(v[0]) >= 0.0 and float(v[1]) >= 0.0 and float(v[2]) >= 0.0:
		return Color(float(v[0]), float(v[1]), float(v[2]))
	return fallback


static func _key(keys: Dictionary, name: String, fallback: float) -> float:
	for k: String in keys:
		if k.to_lower() == name:
			return float(str(keys[k]).split(" ")[0])
	return fallback


## Which free sky panorama (`addons/dot_map/sky/<kind>.jpg`) stands in for the map's sky name, or
## &"" for a night, space or unnamed sky (those stay the procedural sky and its stars).
static func sky_kind(sky_name: String) -> StringName:
	var n := sky_name.to_lower()
	if n.is_empty():
		return &""
	for w in ["night", "dark", "black", "space", "star", "moon"]:
		if n.contains(w):
			return &""
	for w in ["borealis", "ep01", "ep02", "cloudy", "storm", "overcast", "verystill", "grey", "gray"]:
		if n.contains(w):
			return &"overcast"
	if n.contains("day03") or n.contains("sunset") or n.contains("dusk") or n.contains("day01_09") or n.contains("day02_09"):
		return &"dusk"
	if n.contains("day01_01") or n.contains("day01_02") or n.contains("day01_03") or n.contains("clear"):
		return &"clear"
	return &"cloudy"


## The manifest's sky as a panorama texture from [param root] (a folder holding the four kinds), or null.
func sky_panorama(root: String = "res://addons/dot_map/sky") -> Texture2D:
	var kind := sky_kind(str(environment_data().get("sky", {}).get("name", "")))
	if kind == &"":
		return null
	var path := root.path_join("%s.jpg" % kind)
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


## The map's outdoors as nodes: a [WorldEnvironment] (procedural sky from the sun and ambient colours, fog,
## filmic tonemap) and a [DirectionalLight3D] sun, plus with [param max_probes] above 0 a [ReflectionProbe]
## at that many cubemap points. Null when the map carries no environment.
func build_environment(max_probes: int = 8, sun_shadows: bool = true) -> Node3D:
	var env := environment_data()
	if env.is_empty():
		return null
	var root := Node3D.new()
	root.name = "MapEnvironment"
	var sun: Dictionary = env.get("sun", {})
	var amb := _col(sun.get("ambient_hdr"), _col(sun.get("ambient"), Color(0.4, 0.42, 0.46)))
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	var sky_name := str(env.get("sky", {}).get("name", "")).to_lower()
	var night := false
	for w in ["night", "dark", "black", "space", "star"]:
		night = night or sky_name.contains(w)
	if night:
		sm.sky_top_color = Color(0.02, 0.03, 0.08)
		sm.sky_horizon_color = Color(0.06, 0.07, 0.12)
		sm.ground_bottom_color = Color(0.01, 0.01, 0.02)
	else:
		sm.sky_top_color = Color(0.25, 0.45, 0.75).lerp(amb, 0.2)
		sm.sky_horizon_color = Color(0.65, 0.72, 0.8).lerp(amb, 0.2)
		sm.ground_bottom_color = Color(0.2, 0.19, 0.17)
	sm.ground_horizon_color = sm.sky_horizon_color
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = amb.lerp(Color(0.4, 0.4, 0.4), 0.25)
	if has_lightmap():
		e.ambient_light_color = e.ambient_light_color.lerp(light_floor(), 0.5)
	e.ambient_light_energy = 0.35 if night else 0.8
	if env.has("tonemap") or env.has("sun"):
		e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		var tm: Dictionary = env.get("tonemap", {}).get("keys", {})
		e.tonemap_exposure = clampf(_key(tm, "tonemapscale", 1.0), 0.5, 2.0)
	for f: Dictionary in env.get("fog", []):
		if not f.get("enabled", false):
			continue
		e.fog_enabled = true
		e.fog_light_color = _col(f.get("colour"), Color(0.5, 0.5, 0.5))
		e.fog_density = clampf(3.0 / maxf(float(f.get("end", 60.0)), 1.0), 0.002, 0.2) * float(f.get("max_density", 1.0))
		break
	var we := WorldEnvironment.new()
	we.name = "Environment"
	we.environment = e
	root.add_child(we)
	if not sun.is_empty():
		var light := DirectionalLight3D.new()
		light.name = "Sun"
		light.rotation_degrees = Vector3(float(sun.get("pitch", -45.0)), float(sun.get("yaw", 0.0)) - 90.0, 0.0)
		var lc: Variant = sun.get("colour_hdr")
		if not (lc is Array and float(lc[0]) >= 0.0):
			lc = sun.get("colour")
		light.light_color = _col(lc, Color(1, 0.96, 0.9))
		var power := 200.0
		if lc is Array and (lc as Array).size() > 3:
			power = float(lc[3])
		light.light_energy = clampf(power / 200.0, SUN_MIN_LIT if has_lightmap() else 0.2, 2.0)
		light.shadow_enabled = sun_shadows and not bool(env.get("shadows", {}).get("disabled", false))
		root.add_child(light)
	var cubes: Array = env.get("cubemaps", [])
	if max_probes > 0 and not cubes.is_empty():
		var probes := Node3D.new()
		probes.name = "Probes"
		root.add_child(probes)
		for i in mini(max_probes, cubes.size()):
			var at: Array = cubes[i].get("at", [0, 0, 0])
			var p := ReflectionProbe.new()
			p.position = Vector3(at[0], at[1], at[2])
			p.size = Vector3(16, 8, 16)
			p.update_mode = ReflectionProbe.UPDATE_ONCE
			probes.add_child(p)
	return root


## The first resource named [param id] with one of [param exts] in [param dirs], or null.
static func find_resource(id: String, dirs: PackedStringArray, exts: PackedStringArray) -> Resource:
	if id.is_empty():
		return null
	for d in dirs:
		for x in exts:
			var path := d.path_join(id + x)
			if ResourceLoader.exists(path):
				return load(path)
	return null


## The map's ambient sounds as nodes under [code]Sounds[/code]: each [code]ambient_generic[/code] with a free
## [code]stand_in[/code] becomes a player at its place with its radius, volume and pitch, started unless the
## map starts it silent.
func build_sounds(stream_for: Callable = Callable(), make_node: Callable = Callable(), level: float = 1.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Sounds"
	for rec: Dictionary in sounds_data().get("ambient", []):
		var id := str(rec.get("stand_in", ""))
		if id.is_empty():
			continue
		var found: Variant = stream_for.call(id) if stream_for.is_valid() \
				else find_resource(id, DEFAULT_SOUND_DIRS, PackedStringArray([".ogg", ".wav"]))
		if not found is AudioStream:
			continue
		var stream := (found as AudioStream).duplicate() as AudioStream
		if bool(rec.get("looped", true)):
			if "loop" in stream:
				stream.set("loop", true)
			elif "loop_mode" in stream:
				stream.set("loop_mode", AudioStreamWAV.LOOP_FORWARD)
		var node: Node = null
		if make_node.is_valid():
			node = make_node.call(rec, stream)
		if node == null:
			node = _default_player(rec, stream, level)
		var at: Array = rec.get("at", [0, 0, 0])
		if node is Node3D:
			(node as Node3D).position = Vector3(at[0], at[1], at[2])
		root.add_child(node)
	return root


func _default_player(rec: Dictionary, stream: AudioStream, level: float) -> Node:
	var db := linear_to_db(clampf(float(rec.get("volume", 1.0)) * level, 0.001, 4.0))
	var pitch := clampf(float(rec.get("pitch", 100.0)) / 100.0, 0.25, 4.0)
	var autoplay := not bool(rec.get("start_silent", false))
	var p: Node
	if bool(rec.get("everywhere", false)):
		var g := AudioStreamPlayer.new()
		g.stream = stream
		g.volume_db = db
		g.pitch_scale = pitch
		g.autoplay = autoplay
		p = g
	else:
		var a := AudioStreamPlayer3D.new()
		a.stream = stream
		a.volume_db = db
		a.pitch_scale = pitch
		a.max_distance = maxf(float(rec.get("radius", 20.0)), 1.0)
		a.unit_size = clampf(a.max_distance * 0.25, 1.0, 20.0)
		a.autoplay = autoplay
		p = a
	var tn := str(rec.get("targetname", ""))
	p.name = (tn if not tn.is_empty() else "amb_%d" % int(rec.get("entity", 0))).validate_node_name()
	p.set_meta(&"dot_map_entity", int(rec.get("entity", -1)))
	p.set_meta(&"dot_map_gain_scale", level)
	return p


## Library models ([code]lib/[/code]) [method build_props] could not load last time; [member missing_proxied] of them were drawn as boxes.
var missing_models: int = 0
## How many of [member missing_models] were drawn as low-detail boxes of the original's measured bounds.
var missing_proxied: int = 0
## Source paths already warned about missing library models: one WARN per map per process.
static var _models_warned: Dictionary = {}


## Leaves out the props the importer marked `loose` (free physics barrels): the game simulates those as toys
## ([method loose_toys]) and draws and collides with them there. Off, they are static props like any other.
var skip_loose: bool = false


## The props marked `loose` as dot-props toy placements ([code]{toy, at, yaw}[/code]), in manifest order.
func loose_toys() -> Array:
	var out: Array = []
	for rec: Dictionary in manifest.get("props", []):
		if rec.has("loose"):
			out.append({"toy": str(rec["loose"]), "at": rec["at"], "yaw": float(rec.get("yaw", 0.0))})
	return out


## The breakables that hold loose props up, as [method DotMapSupport.build_all] takes them; each `holds` is an index
## into [method loose_toys] (not into the manifest's props).
func supports() -> Array:
	var order := {}
	var i := 0
	var props: Array = manifest.get("props", [])
	for k in props.size():
		if (props[k] as Dictionary).has("loose"):
			order[k] = i
			i += 1
	var out: Array = []
	for rec: Dictionary in breakables():
		var held: Array = []
		for h: Variant in rec.get("holds", []):
			if order.has(int(h)):
				held.append(order[int(h)])
		if not held.is_empty() and rec.has("bounds"):
			out.append({"bounds": rec["bounds"], "health": maxf(float(rec.get("health", 1.0)), 1.0), "holds": held, "model": int(rec["model"])})
	return out


## The free stand-in models the converter placed for the map's own, as nodes under [code]Props[/code]. [param
## scene_for] takes the stand-in id and returns a [PackedScene] (default: [constant DEFAULT_PROP_DIRS],
## [code].glb[/code]).
func build_props(scene_for: Callable = Callable(), collide_fn: Callable = Callable()) -> Node3D:
	var root := Node3D.new()
	root.name = "Props"
	var cache := {}
	var longest_of := {}
	missing_models = 0
	missing_proxied = 0
	_unseen.clear()
	var lib_ids := {}
	for rec: Dictionary in manifest.get("props", []):
		if not rec.has("box") and str(rec.get("stand_in", "")).begins_with("lib/") and not (skip_loose and rec.has("loose")):
			lib_ids[str(rec["stand_in"])] = true
	_preload_library_models(lib_ids.keys(), scene_for, cache)
	for rec: Dictionary in manifest.get("props", []):
		if skip_loose and rec.has("loose"):
			continue
		if rec.has("box"):
			var block := _support_block(rec)
			root.add_child(block)
			if collide_fn.is_valid() and int(rec.get("solid", 0)) in SOLID_BOX:
				var cb := _solid_shape(rec, null)
				if not cb.is_empty():
					var bb := _body_for(cb)
					root.add_child(bb)
					collide_fn.call(bb)
			continue
		var n := _place_prop(rec, scene_for, cache, longest_of)
		if n == null and str(rec.get("stand_in", "")).begins_with("lib/"):
			missing_models += 1
			n = _proxy_for(rec)
			if n == null:
				_unseen.append(rec)
			else:
				missing_proxied += 1
				root.add_child(n)
				if collide_fn.is_valid() and int(rec.get("solid", 0)) in SOLID_BOX:
					var pb := _solid_shape(rec, null)
					if not pb.is_empty():
						var body := _body_for(pb)
						root.add_child(body)
						collide_fn.call(body)
			continue
		if n == null:
			continue
		if prop_view_per_metre > 0.0:
			var end := maxf(prop_view_min, float(longest_of[str(rec.get("stand_in", ""))]) * n.scale.x * prop_view_per_metre)
			for g in n.find_children("*", "GeometryInstance3D", true, false):
				(g as GeometryInstance3D).visibility_range_end = end
				(g as GeometryInstance3D).visibility_range_end_margin = end * 0.1
		root.add_child(n)
		if collide_fn.is_valid() and int(rec.get("solid", 0)) in SOLID_BOX:
			for box in _solid_boxes(rec, n):
				var body := _body_for(box)
				root.add_child(body)
				collide_fn.call(body)
	DotLog.info(CHANNEL, "props built", {"models": cache.get(OWNED_KEY, []).size(), "model_ms": cache.get("__ms", 0), "static_mb": OS.get_static_memory_usage() / 1048576})
	_free_templates(cache)
	_decompose_cache.clear()
	_warn_missing_models()
	return root


## A low-detail box of a missing library model's measured bounds (`collide`, else `bounds`), or null without them.
func _proxy_for(rec: Dictionary) -> Node3D:
	var src: Variant = rec.get("collide", rec.get("bounds", null))
	if not src is Dictionary or not (src as Dictionary).has("box"):
		return null
	var d: Array = src["box"]
	if float(d[0]) <= 0.001 or float(d[1]) <= 0.001 or float(d[2]) <= 0.001:
		return null
	var at: Array = src.get("at", rec.get("at", [0, 0, 0]))
	var yaw: Variant = src.get("yaw", rec.get("yaw", 0.0))
	var block: MeshInstance3D
	if is_tree(rec):
		var trunk: Dictionary = _solid_shape({"stand_in": rec["stand_in"], "collide": src}, null)
		var w: float = (trunk["size"] as Vector3).x if not trunk.is_empty() else clampf(minf(d[0], d[2]) * TRUNK_SHARE, TRUNK_MIN, TRUNK_MAX)
		block = _support_block({"box": [w, d[1], w], "at": at, "yaw": yaw}, Color(0.36, 0.27, 0.18))
		block.add_child(_crown_blob(Vector3(d[0], d[1] * 0.65, d[2]), Vector3(0, d[1] * 0.175, 0)))
	else:
		block = _support_block({"box": d, "at": at, "yaw": yaw})
	block.name = "Proxy"
	block.set_meta(&"dot_map_proxy", str(rec.get("stand_in", "")))
	return block


## Library prop records [method build_props] could neither load nor measure, for [method draw_unseen_boxes].
var _unseen: Array[Dictionary] = []


## Blocks for a game's own world-space collision boxes ([code][x, y, z, sx, sy, sz, yaw][/code]) that stand where
## [method build_props] drew nothing (a missing, unmeasured library model), so no box collides unseen; null when none.
func draw_unseen_boxes(boxes: Array) -> Node3D:
	if _unseen.is_empty():
		return null
	var at_xz := {}
	for rec in _unseen:
		var at: Array = rec.get("at", [0, 0, 0])
		var key := Vector2i(floori(float(at[0])), floori(float(at[2])))
		if not at_xz.has(key):
			at_xz[key] = []
		at_xz[key].append(rec)
	var root := Node3D.new()
	root.name = "UnseenProps"
	for b: Variant in boxes:
		if not b is Array or (b as Array).size() < 7:
			continue
		var rec: Variant = null
		# A library model sits bottom-centre on its origin, so its box is centred over `at` and starts at its height.
		var cells := {}
		for dx in [-0.05, 0.05]:
			for dz in [-0.05, 0.05]:
				cells[Vector2i(floori(float(b[0]) + dx), floori(float(b[2]) + dz))] = true
		for cell: Vector2i in cells:
			for r: Dictionary in at_xz.get(cell, []):
				if absf(float(r["at"][0]) - float(b[0])) < 0.05 and absf(float(r["at"][2]) - float(b[2])) < 0.05 \
						and absf(float(b[1]) - float(b[4]) * 0.5 - float(r["at"][1])) <= 0.25:
					rec = r
		if rec == null:
			continue
		var tint := Color(0.36, 0.27, 0.18) if is_tree(rec) else Color(0.62, 0.6, 0.57)
		var block := _support_block({"box": [b[3], b[4], b[5]], "at": [b[0], b[1], b[2]], "yaw": b[6]}, tint)
		block.name = "Proxy"
		block.set_meta(&"dot_map_proxy", str(rec.get("stand_in", "")))
		root.add_child(block)
	if root.get_child_count() == 0:
		root.free()
		return null
	return root


func _warn_missing_models() -> void:
	if missing_models == 0 or _models_warned.has(source_path):
		return
	_models_warned[source_path] = true
	DotLog.warn(CHANNEL, "a map's library models are not installed; %d drawn as low-detail boxes, %d left out. To get them: %s" % [missing_proxied, missing_models - missing_proxied, DotMapStore.HOW_TO_GET],
			{"map": source_path.get_file(), "store_pack": str(DotMapStore.pack_of(licence()).get("id", "none"))})


## Key in a prop cache for the library templates [method _place_prop] made, which only the caller's end can free.
const OWNED_KEY := &"__owned"


## Frees the library templates a prop pass loaded; they are orphan nodes, so dropping the cache leaks their meshes and textures.
func _free_templates(cache: Dictionary) -> void:
	for n: Node in cache.get(OWNED_KEY, []):
		n.free()
	cache.erase(OWNED_KEY)


## One prop record as an instanced, placed and scaled stand-in (not yet in the tree); null when its stand-in has no scene.
func _place_prop(rec: Dictionary, scene_for: Callable, cache: Dictionary, longest_of: Dictionary) -> Node3D:
	var id := str(rec.get("stand_in", ""))
	if not cache.has(id):
		cache[id] = scene_for.call(id) if scene_for.is_valid() \
				else find_resource(id, DEFAULT_PROP_DIRS, PackedStringArray([".glb", ".tscn"]))
	if cache[id] == null and id.begins_with("lib/"):
		var started := Time.get_ticks_msec()
		cache[id] = _library_model(id)
		cache["__ms"] = int(cache.get("__ms", 0)) + Time.get_ticks_msec() - started
		if cache[id] != null:
			cache.get_or_add(OWNED_KEY, []).append(cache[id])
	var scene: Variant = cache[id]
	var n: Node3D = null
	if scene is PackedScene:
		n = (scene as PackedScene).instantiate() as Node3D
	elif scene is Node3D:
		n = (scene as Node3D).duplicate() as Node3D
	if n == null:
		return null
	var at: Array = rec.get("at", [0, 0, 0])
	n.position = Vector3(at[0], at[1], at[2])
	n.rotation_degrees.y = float(rec.get("yaw", 0.0)) + PROP_FACING_DEGREES
	n.scale = Vector3.ONE * float(rec.get("scale", 1.0))
	var size := float(rec.get("size", 0.0))
	if not longest_of.has(id):
		longest_of[id] = _longest_side(n)
	var longest: float = longest_of[id]
	if size > 0.0 and longest > 0.001:
		# A small thing (a can, a phone) on a furniture-sized stand-in: fit its longest side to `size`.
		n.scale *= size / longest
	return n


## The folder holding the pack's shared model library (default: the licence block's [code]model_store[/code] beside the mesh).
var model_library: String = ""
## Folders searched for a model before [member model_library], in order: a map's own slice and the shared slices it depends on.
var model_libraries: PackedStringArray = PackedStringArray()


## Library models this mesh found damaged ([method gltf_defect]); each is drawn as its measured box.
var defective_models := PackedStringArray()


## Why the glTF at [param path] cannot load ("" when it can): a .bin longer than its declared byteLength, which the engine
## refuses with an error per read and no name. Checked up front so the model is named once instead.
static func gltf_defect(path: String) -> String:
	if path.get_extension() != "gltf":
		return ""
	var json: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not json is Dictionary:
		return "not readable as JSON"
	for buf: Variant in (json as Dictionary).get("buffers", []):
		var uri := str((buf as Dictionary).get("uri", ""))
		if uri == "" or uri.begins_with("data:"):
			continue
		var bin := path.get_base_dir().path_join(uri.uri_decode())
		if not FileAccess.file_exists(bin):
			return "%s is missing" % uri
		var file := FileAccess.open(bin, FileAccess.READ)
		if file != null and file.get_length() > int((buf as Dictionary).get("byteLength", 0)):
			return "%s is %d bytes but the glTF declares %d" % [uri, file.get_length(), int((buf as Dictionary).get("byteLength", 0))]
	return ""


## A shipped library model (stand-in id [code]lib/<name>[/code]) loaded from the pack, re-rooted so its bottom centre sits at
## the origin; null when the pack lacks it. A glTF outside the project has no import, so it is read with [GLTFDocument].
func _library_model(id: String, parsed: GLTFState = null) -> Node3D:
	var path := _library_path(id)
	if path == "":
		return null
	var model: Node3D = null
	if path.begins_with("res://") and ResourceLoader.exists(path):
		var packed := (_imported_scenes[path] if _imported_scenes.has(path) else load(path)) as PackedScene
		model = packed.instantiate() as Node3D if packed != null else null
	elif FileAccess.file_exists(path):
		var defect := gltf_defect(path)
		if defect != "":
			_note_defect(path, defect)
			return null
		var state := parsed
		var doc := GLTFDocument.new()
		if state == null:
			state = GLTFState.new()
			if doc.append_from_file(path, state) != OK:
				state = null
		if state != null:
			model = doc.generate_scene(state) as Node3D
			if model != null:
				add_mesh_lods(model, model_lod_min_tris, model_max_tris)
				if model_texture_max >= 0:
					slim_model_textures(model, model_texture_max)
	if model == null:
		return null
	var box := _local_aabb(model)
	model.position -= Vector3(box.get_center().x, box.position.y, box.get_center().z)
	var holder := Node3D.new()
	holder.add_child(model)
	return holder


## Where library model [param id] is on disk ("" when the pack does not list it).
func _library_path(id: String) -> String:
	var row := {}
	for r: Dictionary in licence().get("model_stand_ins", []):
		if str(r.get("stand_in", "")) == id:
			row = r
	if row.is_empty() or not row.has("store_file"):
		return ""
	var root := model_library if not model_library.is_empty() \
			else source_path.get_base_dir().path_join(str(licence().get("model_store", "model-library"))).simplify_path()
	var path := root.path_join(str(row["store_file"]))
	for lib in model_libraries:
		var cand := lib.path_join(str(row["store_file"]))
		if ResourceLoader.exists(cand) or FileAccess.file_exists(cand):
			path = cand
			break
	return path


func _note_defect(path: String, defect: String) -> void:
	if not defective_models.has(path):
		defective_models.append(path)
		DotLog.warn(CHANNEL, "a library model is damaged and drawn as a box instead: " + defect, {"model": path})


## Imported library scenes already loaded by [method _preload_library_models], by path.
var _imported_scenes := {}


## Loads the library models in [param ids] that are not yet in [param cache] ahead of the build: imported [code]res://[/code] scenes with
## [method ResourceLoader.load_threaded_request], plain glTF files (also under [code]res://[/code], when never imported) parsed on workers
## ([member load_threads], never the web), then builds each scene here, so the ~85 ms parse of every model is not serial.
func _preload_library_models(ids: Array, scene_for: Callable, cache: Dictionary) -> void:
	if DotParallel.resolve_workers(load_threads) <= 1 or not DotParallel.available():
		return
	var todo: Array = []
	var imported := {}
	for id: String in ids:
		if cache.has(id):
			continue
		cache[id] = scene_for.call(id) if scene_for.is_valid() \
				else find_resource(id, DEFAULT_PROP_DIRS, PackedStringArray([".glb", ".tscn"]))
		if cache[id] == null and id.begins_with("lib/"):
			var path := _library_path(id)
			if path.begins_with("res://") and ResourceLoader.exists(path) and not imported.has(path):
				imported[path] = true
				ResourceLoader.load_threaded_request(path)
			if path != "" and not imported.has(path) and not ResourceLoader.exists(path) and FileAccess.file_exists(path) and gltf_defect(path) == "":
				todo.append([id, path])
	var started := Time.get_ticks_msec()
	for path: String in imported:  # request order, so the result does not depend on which worker finished first
		_imported_scenes[path] = ResourceLoader.load_threaded_get(path)
	var step := DotMapParallelBuild.batch_size(load_threads)
	for from in range(0, todo.size(), step):
		var n := mini(step, todo.size() - from)
		var states := DotParallel.run(func(i: int) -> Variant:
			var st := GLTFState.new()
			return st if GLTFDocument.new().append_from_file(todo[from + i][1], st) == OK else null, n, &"map.gltf", load_threads)
		for i in n:
			var id: String = todo[from + i][0]
			cache[id] = _library_model(id, states[i]) if states[i] != null else null
			if cache[id] != null:
				cache.get_or_add(OWNED_KEY, []).append(cache[id])
	cache["__ms"] = int(cache.get("__ms", 0)) + Time.get_ticks_msec() - started


## Triangles a library model's mesh must have before [method add_mesh_lods] simplifies it (the engine then picks a coarser level by
## screen size); 0 leaves every mesh whole. A scanned tree is over a million triangles, and a street of them was the frame.
static var model_lod_min_tris: int = 20000

## Most triangles a library model's mesh keeps at full detail: a mesh over it starts from the coarsest simplification that fits, so a 1.6 million triangle tree is drawn at about this size when near. 0 keeps the model's own.
static var model_max_tris: int = 150000


## Sets [member model_lod_min_tris] and [member model_max_tris] for a caller that reaches this script by path.
static func set_model_lod(min_tris: int, max_tris: int = 0) -> void:
	model_lod_min_tris = maxi(min_tris, 0)
	model_max_tris = maxi(max_tris, 0)


## Longest side a library model's texture keeps (a glTF read at run time decodes to raw RGBA with mips, 85 MB for a 4k map); 0 keeps the model's own size, and every one is VRAM-compressed either way; below 0 leaves the textures as the glTF made them.
static var model_texture_max: int = -1


## Whether [method slim_model_textures] halves a model's roughness, metallic and AO maps (the glTF ORM image); the diff against full size is in docs/surfaces.md.
static var model_half_masks: bool = true

## Whether [method slim_model_textures] halves a model's normal maps.
static var model_half_normals: bool = true


## Whether a material slot is cut to half size under the two options; albedo and emission never are.
static func slot_halves(slot: int, masks: bool, normals: bool) -> bool:
	return (masks and slot in [BaseMaterial3D.TEXTURE_ROUGHNESS, BaseMaterial3D.TEXTURE_METALLIC, BaseMaterial3D.TEXTURE_AMBIENT_OCCLUSION]) \
			or (normals and slot == BaseMaterial3D.TEXTURE_NORMAL)


## [param tex] at half size: a decoded image is resized before it is capped, mip-mapped and compressed; a compressed one loses its top mip, with no re-encode.
static func half_model_texture(tex: ImageTexture, max_size: int) -> ImageTexture:
	var img := tex.get_image()
	if img.is_compressed():
		return DotMapSurfaces.without_top_mip(tex) as ImageTexture
	if mini(img.get_width(), img.get_height()) >= 8:
		img.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_LANCZOS)
	DotMapSurfaces.prepare_image(img, "model.png", max_size)
	return ImageTexture.create_from_image(img)


## Replaces every texture of the materials under [param root] with a capped, mip-mapped, compressed copy (once per texture, so a
## texture two materials share stays shared) and frees the raw image; returns how many were replaced. Roughness, metallic, AO and
## normal maps are halved first under [member model_half_masks] and [member model_half_normals].
static func slim_model_textures(root: Node, max_size: int) -> int:
	var done := {}
	var halved := {}
	var meshes := {}
	var changed := 0
	for found in root.find_children("*", "MeshInstance3D", true, false):
		var mi := found as MeshInstance3D
		if mi.mesh == null or meshes.has(mi.mesh):
			continue
		meshes[mi.mesh] = true
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i) as BaseMaterial3D
			if m == null or done.has(m):
				continue
			done[m] = true
			for slot in BaseMaterial3D.TEXTURE_MAX:
				var tex := m.get_texture(slot as BaseMaterial3D.TextureParam) as ImageTexture
				if tex == null:
					continue
				var half := slot_halves(slot, model_half_masks, model_half_normals)
				var seen := halved if half else done
				if not seen.has(tex):
					var img := tex.get_image()
					if img == null:
						seen[tex] = tex
					elif half:
						seen[tex] = half_model_texture(tex, max_size)
					elif img.is_compressed():
						seen[tex] = tex
					else:
						DotMapSurfaces.prepare_image(img, "model.png", max_size)  # a part-less name: every channel stays
						seen[tex] = ImageTexture.create_from_image(img)
				if seen[tex] != tex:
					m.set_texture(slot as BaseMaterial3D.TextureParam, seen[tex])
					changed += 1
	return changed


## Gives every unskinned [MeshInstance3D] mesh under [param root] with at least [param min_tris] triangles its LOD levels
## (meshoptimizer, as the editor's import does; a glTF read at run time has none), after cutting it to [param max_tris]
## (0: not cut). About a second for a million triangles, once per model. Returns how many meshes changed.
static func add_mesh_lods(root: Node, min_tris: int, max_tris: int = 0) -> int:
	if min_tris <= 0:
		return 0
	var done := {}
	var changed := 0
	for found in root.find_children("*", "MeshInstance3D", true, false):
		var mi := found as MeshInstance3D
		var mesh := mi.mesh as ArrayMesh
		if mesh == null or mi.skin != null or mesh.get_blend_shape_count() > 0:
			continue
		if not done.has(mesh):
			done[mesh] = _with_lods(mesh, min_tris, max_tris)
		if done[mesh] != mesh:
			mi.mesh = done[mesh]
			changed += 1
	return changed


static func _with_lods(mesh: ArrayMesh, min_tris: int, max_tris: int) -> Mesh:
	var tris := 0
	var all: Array = []
	for i in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(i) != Mesh.PRIMITIVE_TRIANGLES:
			return mesh
		var arrays := mesh.surface_get_arrays(i)
		var index: Variant = arrays[Mesh.ARRAY_INDEX]
		tris += (index as PackedInt32Array).size() / 3 if index != null else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		all.append(arrays)
	if tris < min_tris:
		return mesh
	var importer := _importer_of(mesh, all)
	importer.generate_lods(25.0, 60.0, [])
	if max_tris > 0 and tris > max_tris:
		# Each surface restarts from the first level small enough for its share, then gets its own levels again.
		var share := float(max_tris) / float(tris)
		for i in all.size():
			var arrays: Array = all[i]
			var base := (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3 if arrays[Mesh.ARRAY_INDEX] != null else 0
			for l in importer.get_surface_lod_count(i):
				var indices := importer.get_surface_lod_indices(i, l)
				if indices.size() / 3 <= int(base * share) or l == importer.get_surface_lod_count(i) - 1:
					arrays[Mesh.ARRAY_INDEX] = indices
					break
		importer = _importer_of(mesh, all)
		importer.generate_lods(25.0, 60.0, [])
	var out := importer.get_mesh()
	return out if out != null else mesh


static func _importer_of(mesh: ArrayMesh, all: Array) -> ImporterMesh:
	var importer := ImporterMesh.new()
	for i in all.size():
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, all[i], [], {}, mesh.surface_get_material(i), mesh.surface_get_name(i))
	return importer
