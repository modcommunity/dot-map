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
## Takes a glass surface record, returns its [Material]; the built-in [method glass_material] when unset.
var glass_material_for: Callable = Callable()
## Metres a stand-in prop is drawn to per metre of its longest side, never under
## [member prop_view_min]: a can is gone at 30 m, a shelf at 120. 0 draws every prop at any range.
var prop_view_per_metre: float = 60.0
var prop_view_min: float = 30.0

var _blob: PackedByteArray = PackedByteArray()
var _movers: Dictionary = {}
var _entities: DotMapEntities = null


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


## The entities of this map (movers, volumes, links, data), built on first use.
func entities() -> DotMapEntities:
	if _entities == null:
		_entities = DotMapEntities.from_manifest(manifest)
	return _entities


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


## The look of each glass kind: colour with alpha, roughness.
const GLASS_LOOKS := {
	&"glass": {"colour": Color(0.72, 0.86, 0.92, 0.22), "roughness": 0.05},
	&"glass_frosted": {"colour": Color(0.85, 0.9, 0.93, 0.55), "roughness": 0.55},
}
static var _glass_cache: Dictionary = {}


## The shared transparent material of a glass kind (an unknown kind is clear glass), multiplied by
## [param tint] (r, g, b) when the map gave one. Alpha-blended, so it sorts and shows what is behind.
static func glass_material(glass_kind: StringName, tint: Array = []) -> StandardMaterial3D:
	if not GLASS_LOOKS.has(glass_kind):
		glass_kind = &"glass"
	var key := "%s|%s" % [glass_kind, tint]
	if _glass_cache.has(key):
		return _glass_cache[key]
	var look: Dictionary = GLASS_LOOKS[glass_kind]
	var c: Color = look["colour"]
	if tint.size() >= 3:
		c = Color(c.r * float(tint[0]), c.g * float(tint[1]), c.b * float(tint[2]), c.a)
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = float(look["roughness"])
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.resource_name = str(glass_kind)
	_glass_cache[key] = m
	return m


func _glass_for(rec: Dictionary) -> Material:
	if glass_material_for.is_valid():
		var m: Variant = glass_material_for.call(rec)
		if m is Material:
			return m
	return glass_material(StringName(str(rec["glass"])), rec.get("tint", []))


## A model's surfaces as meshes, grouped by chunk (the converter's columns of the world), each
## mesh under [constant MAX_SURFACES]. [param material_for] takes a surface record, returns a
## [Material] or null; a glass surface (record key [code]glass[/code]) never asks it and gets
## [member glass_material_for] or the built-in glass, in meshes of their own so they can skip shadows.
## Records of a chunk that get the same material are one surface: one draw, not one per brush face.
## Returns [code][{mesh: ArrayMesh, chunk: Array, sky3d: bool, glass: bool}][/code].
func build_meshes(model: int, material_for: Callable = Callable()) -> Array[Dictionary]:
	var groups := {}
	for rec: Dictionary in surfaces:
		if int(rec["model"]) != model:
			continue
		var key := "%s|%s|%s" % [str(rec.get("chunk", [])), rec.get("sky3d", false), rec.has("glass")]
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(rec)
	var out: Array[Dictionary] = []
	for key: String in groups:
		# Material instance id -> {material, recs}, in first-seen order so the build is stable.
		var by_material := {}
		for rec: Dictionary in groups[key]:
			var mat: Material = null
			if rec.has("glass"):
				mat = _glass_for(rec)
			elif material_for.is_valid():
				var m: Variant = material_for.call(rec)
				mat = m as Material if m is Material else null
			var id := mat.get_instance_id() if mat != null else 0
			if not by_material.has(id):
				by_material[id] = {"material": mat, "recs": []}
			(by_material[id]["recs"] as Array).append(rec)
		var mesh: ArrayMesh = null
		for entry: Dictionary in by_material.values():
			var first: Dictionary = entry["recs"][0]
			if mesh == null or mesh.get_surface_count() >= MAX_SURFACES:
				mesh = ArrayMesh.new()
				out.append({"mesh": mesh, "chunk": first.get("chunk", []), "sky3d": bool(first.get("sky3d", false)),
						"glass": first.has("glass")})
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _merged_arrays(entry["recs"]))
			var s := mesh.get_surface_count() - 1
			mesh.surface_set_name(s, str(first.get("material", "")))
			if entry["material"] != null:
				mesh.surface_set_material(s, entry["material"])
	return out


## [method surface_arrays] of several records as one, the indices offset onto the joined vertices.
func _merged_arrays(recs: Array) -> Array:
	if recs.size() == 1:
		return surface_arrays(recs[0])
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var index := PackedInt32Array()
	for rec: Dictionary in recs:
		var a := surface_arrays(rec)
		var base := verts.size()
		var part: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		for k in part.size():
			part[k] += base
		verts.append_array(a[Mesh.ARRAY_VERTEX])
		normals.append_array(a[Mesh.ARRAY_NORMAL])
		uvs.append_array(a[Mesh.ARRAY_TEX_UV])
		index.append_array(part)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = index
	return arrays


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
			if g["glass"]:
				mi.name = "glass_" + str(mi.name)
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(mi)
	return root


## The map's breakable brush entities: [code]{model, entity, classname, targetname, health, glass, material}[/code]
## ([code]glass[/code] is the kind when every drawn surface is glass, else empty).
func breakables() -> Array:
	return manifest.get("breakables", [])


## A [DotMapGlass] for each breakable glass model of [param root] (a [method build_node] result): its
## hulls as the body on [param collision_layer], the model's node as what it hides. Non-breaking glass
## is no different from a wall: its hulls have kind [code]glass[/code] from [method hull_shapes], and a
## game leaves that kind off the layer its bullets and projectiles collide with.
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


## The [code]environment[/code] block (sky, sun, fog, tonemap, cubemaps), or {}.
func environment_data() -> Dictionary:
	return manifest.get("environment", {})


## The [code]sounds[/code] block (ambient, soundscapes, triggers, files), or {}.
func sounds_data() -> Dictionary:
	return manifest.get("sounds", {})


static func _col(v: Variant, fallback: Color) -> Color:
	if v is Array and (v as Array).size() >= 3 and float(v[0]) >= 0.0 and float(v[1]) >= 0.0 and float(v[2]) >= 0.0:
		return Color(float(v[0]), float(v[1]), float(v[2]))
	return fallback


static func _key(keys: Dictionary, name: String, fallback: float) -> float:
	for k: String in keys:
		if k.to_lower() == name:
			return float(str(keys[k]).split(" ")[0])
	return fallback


## The map's outdoors as nodes: a [WorldEnvironment] (procedural sky from the sun and ambient
## colours, fog, filmic tonemap) and a [DirectionalLight3D] sun, plus with [param max_probes]
## above 0 a [ReflectionProbe] at that many cubemap points. Null when the map carries no
## environment. Nodes are named [code]Environment[/code], [code]Sun[/code], [code]Probes[/code];
## the caller places the result and may edit anything in it.
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
		light.light_energy = clampf(power / 200.0, 0.2, 2.0)
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


## The map's ambient sounds as nodes under [code]Sounds[/code]: each [code]ambient_generic[/code]
## with a free [code]stand_in[/code] becomes a player at its place with its radius, volume and
## pitch, started unless the map starts it silent. [param stream_for] takes the stand-in id and
## returns an [AudioStream] (default: [constant DEFAULT_SOUND_DIRS]). [param make_node] takes
## [code](record, stream)[/code] and returns the node to add, for a game that plays through its
## own audio layer; null falls back to an [AudioStreamPlayer3D]. A sound with no stand-in is
## silent on purpose: music and voices are never replaced.
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
	return p


## The free stand-in models the converter placed for the map's own, as nodes under
## [code]Props[/code]. [param scene_for] takes the stand-in id and returns a [PackedScene]
## (default: [constant DEFAULT_PROP_DIRS], [code].glb[/code]). Drawing only, no collision: the
## map's own hulls are what players stand on. An id with no scene is skipped.
func build_props(scene_for: Callable = Callable()) -> Node3D:
	var root := Node3D.new()
	root.name = "Props"
	var cache := {}
	var longest_of := {}
	for rec: Dictionary in manifest.get("props", []):
		if rec.has("box"):
			root.add_child(_support_block(rec))
			continue
		var id := str(rec.get("stand_in", ""))
		if not cache.has(id):
			cache[id] = scene_for.call(id) if scene_for.is_valid() \
					else find_resource(id, DEFAULT_PROP_DIRS, PackedStringArray([".glb", ".tscn"]))
		var scene: Variant = cache[id]
		if not scene is PackedScene:
			continue
		var n := (scene as PackedScene).instantiate() as Node3D
		if n == null:
			continue
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
		if prop_view_per_metre > 0.0:
			var end := maxf(prop_view_min, longest * n.scale.x * prop_view_per_metre)
			for g in n.find_children("*", "GeometryInstance3D", true, false):
				(g as GeometryInstance3D).visibility_range_end = end
				(g as GeometryInstance3D).visibility_range_end_margin = end * 0.1
		root.add_child(n)
	return root


static var _support_material: StandardMaterial3D = null


## A neutral block of the measured size, for a model something rests on and no stand-in fits.
static func _support_block(rec: Dictionary) -> MeshInstance3D:
	var dims: Array = rec["box"]
	var box := BoxMesh.new()
	box.size = Vector3(dims[0], dims[1], dims[2])
	if _support_material == null:
		_support_material = StandardMaterial3D.new()
		_support_material.albedo_color = Color(0.62, 0.6, 0.57)
	box.material = _support_material
	var mi := MeshInstance3D.new()
	mi.mesh = box
	var at: Array = rec.get("at", [0, 0, 0])
	mi.position = Vector3(at[0], at[1], at[2])
	mi.rotation_degrees.y = float(rec.get("yaw", 0.0))
	return mi


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
