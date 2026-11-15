extends "mesh_solids.gd"

## The breakables, licence, sky, environment and sound part of [DotMapBspMesh]; the props are
## [code]mesh_props.gd[/code].

## Where [method build_sounds] and [method build_props] look for a stand-in by id when the
## game gives no callable: this addon's own free Kenney set, then dot-audio's stock beds.
const DEFAULT_SOUND_DIRS: PackedStringArray = [
	"res://addons/dot_map/sounds", "res://addons/dot_audio/stock/ambience"]
const DEFAULT_PROP_DIRS: PackedStringArray = ["res://addons/dot_map/props"]


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
	if n.contains("day02_09"):
		return &"twilight"
	if n.contains("day03") or n.contains("sunset") or n.contains("dusk") or n == "hav" or n.contains("day01_09"):
		return &"dusk"
	if n.contains("day01_01") or n.contains("day01_02") or n.contains("day01_03") or n.contains("clear"):
		return &"clear"
	return &"cloudy"


## A [PanoramaSkyMaterial] for a sky name from [param root], or null for a night, space or unnamed sky.
## For a game that lights its own map: `environment.sky.sky_material = DotMapBspMesh.sky_material_for(name)`.
static func sky_material_for(sky_name: String, root: String = "res://addons/dot_map/sky") -> PanoramaSkyMaterial:
	var kind := sky_kind(sky_name)
	var path := root.path_join("%s.jpg" % kind)
	if kind == &"" or not ResourceLoader.exists(path):
		return null
	var m := PanoramaSkyMaterial.new()
	m.panorama = load(path) as Texture2D
	return m


## The manifest's sky as a panorama texture from [param root] (a folder holding the kinds), or null.
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
	var path := find_resource_path(id, dirs, exts)
	return null if path.is_empty() else load(path)


## Where [method find_resource] loads [param id] from, or "".
static func find_resource_path(id: String, dirs: PackedStringArray, exts: PackedStringArray) -> String:
	if id.is_empty():
		return ""
	for d in dirs:
		for x in exts:
			var path := d.path_join(id + x)
			if ResourceLoader.exists(path):
				return path
	return ""


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
