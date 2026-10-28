extends Node
## Proves DotMapCredits and DotMapStore on a hand-written manifest and a stand-in cloud client.
## godot --headless --path . res://examples/store_demo.tscn

const CHECKS := 60
const SECTIONS := 7

var _passed := 0
var _failed := 0
var _entered := 0
var _completed := 0

const MANIFEST := {
	"credit": {"author": "Mapper"},
	"licence": {
		"textures": [
			{"kind": "pbr", "generic": "Bricks", "author": "ambientCG", "licence": "CC0-1.0", "url": "u/b", "surfaces": 4},
			{"kind": "pbr", "generic": "Moss", "author": "Jane", "licence": "CC-BY-4.0", "url": "u/m", "surfaces": 2},
			{"kind": "generated", "generic": "flat", "key": "k"},
		],
		"model_stand_ins": [
			{"stand_in": "lib/chair", "author": "Poly", "licence": "CC-BY-4.0", "url": "u/c", "count": 3},
			{"stand_in": "lib/chair2", "author": "Poly", "licence": "CC-BY-4.0", "url": "u/c", "count": 2},
		],
		"sounds": [{"stand_in": "wind", "author": "K", "licence": "CC0-1.0", "url": "u/w", "count": 1}],
		"store_pack": {"id": "gamemann/store-x", "version": "h1234abcd"},
	},
}


class FakeCloud:
	extends RefCounted
	var mounted := {}
	var ensured := 0

	func dependency_prefix(id: StringName, version: String) -> String:
		return mounted.get("%s@%s" % [id, version], "")

	func ensure(id: StringName, version: String, _groups: PackedStringArray, _url: String) -> DotResult:
		ensured += 1
		mounted["%s@%s" % [id, version]] = "res://dot_cloud/%s/%s/" % [id, version]
		return DotResult.success(null)


## A cloud that knows manifests: the root names two slices (one cached, one 3 MB) under it, and a shared one it shares with a mounted map.
class PlanCloud:
	extends FakeCloud
	var resolved := PackedStringArray()
	const DEPS := {"r@1": ["a@1", "b@1"], "a@1": ["s@1"], "b@1": ["s@1"], "s@1": []}
	const MISSING := {"r@1": 1 << 20, "a@1": 0, "b@1": 2 << 20, "s@1": 5 << 20}

	func is_mounted(id: StringName, version: String) -> bool:
		return mounted.has("%s@%s" % [id, version])

	func resolve_manifest(id: StringName, version: String, _url: String = "") -> DotResult:
		resolved.append("%s@%s" % [id, version])
		var m := PlanManifest.new()
		m.key = "%s@%s" % [id, version]
		for d: String in DEPS[m.key]:
			m.dependencies.append({"id": d.get_slice("@", 0), "version": d.get_slice("@", 1)})
		return DotResult.success(m)

	func plan_for(m: Object, _groups: PackedStringArray = PackedStringArray()) -> Dictionary:
		return {"missing_bytes": MISSING[m.key]}


class PlanManifest:
	extends RefCounted
	var key := ""
	var dependencies: Array = []


## A cloud that cannot reach any server: what a bootstrapped checkout without the slices has.
class OfflineCloud:
	extends RefCounted

	func dependency_prefix(_id: StringName, _version: String) -> String:
		return ""

	func ensure(id: StringName, _version: String, _groups: PackedStringArray, _url: String) -> DotResult:
		return DotResult.fail(DotError.CODE_IO, "Could not get %s's manifest." % id)


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL ", label)


func _run() -> void:
	_credits()
	await _store()
	await _plan()
	_surfaces()
	await _missing_slices()
	_stand_ins()
	_missing_models()
	print("%d checks, %d failed, %d/%d sections" % [_passed + _failed, _failed, _completed, SECTIONS])
	var bad := _failed > 0 or _passed + _failed != CHECKS or _completed != SECTIONS or _entered != SECTIONS
	get_tree().quit(1 if bad else 0)


func _credits() -> void:
	_entered += 1
	var all := DotMapCredits.works(MANIFEST)
	_check("generated textures are skipped, same url merges", all.size() == 4)
	var chair := all.filter(func(w: Dictionary) -> bool: return w["url"] == "u/c")
	_check("merged uses add up", chair.size() == 1 and chair[0]["uses"] == 5)
	var need := DotMapCredits.works(MANIFEST, true)
	_check("attribution filter keeps CC-BY only", need.size() == 2)
	_check("CC0 never needs a credit", not need.any(func(w: Dictionary) -> bool: return w["licence"] == "CC0-1.0"))
	var line := DotMapCredits.line(MANIFEST)
	_check("line names the map author", line.begins_with("Map by Mapper"))
	_check("line names the art authors", line.contains("Jane") and line.contains("Poly") and not line.contains("ambientCG"))
	_check("empty manifest gives an empty line", DotMapCredits.line({}) == "")
	_completed += 1


func _store() -> void:
	_entered += 1
	var lic: Dictionary = MANIFEST["licence"]
	var cloud := FakeCloud.new()
	_check("pack_of reads the slice", DotMapStore.pack_of(lic)["version"] == "h1234abcd")
	_check("no slice, no pack", DotMapStore.pack_of({}).is_empty())
	_check("not mounted gives no dir", DotMapStore.mount_dir(lic, cloud) == "")
	var res: DotResult = await DotMapStore.ensure(lic, cloud, "")
	_check("ensure with no manifest url lets the client resolve it", res.ok and cloud.ensured == 1)
	res = await DotMapStore.ensure(lic, cloud, "https://x/manifest.json")
	_check("ensure mounts it", res.ok and cloud.ensured == 1 and str(res.value).begins_with("res://dot_cloud/gamemann/store-x"))
	await DotMapStore.ensure(lic, cloud, "https://x/manifest.json")
	_check("a second ensure downloads nothing", cloud.ensured == 1)
	_completed += 1


func _plan() -> void:
	_entered += 1
	var lic := {"store_pack": {"id": "r", "version": "1"}}
	var cloud := PlanCloud.new()
	var res: DotResult = await DotMapStore.plan(lic, cloud)
	_check("plan adds the root and every dependency", res.ok and int(res.value["bytes"]) == 8 << 20)
	_check("a slice two others share is counted once", cloud.resolved.count("s@1") == 1 and res.value["slices"] == 3)
	cloud.mounted["s@1"] = "res://x/"
	res = await DotMapStore.plan(lic, cloud)
	_check("a mounted slice costs nothing", int(res.value["bytes"]) == 3 << 20)
	res = await DotMapStore.plan({}, cloud)
	_check("a map with no slices costs nothing", res.ok and int(res.value["bytes"]) == 0)
	res = await DotMapStore.plan(lic, FakeCloud.new())
	_check("a client that cannot plan is not an error", res.ok and int(res.value["bytes"]) == 0)
	_completed += 1


func _surfaces() -> void:
	_entered += 1
	var cloud := FakeCloud.new()
	cloud.mounted["gamemann/store-x@h1234abcd"] = "res://dot_cloud/gamemann/store-x/h1234abcd/"
	var s := DotMapSurfaces.new()
	var w := DotMapBspMesh.new()
	_check("apply points both at the slice", DotMapStore.apply(MANIFEST["licence"], cloud, s, w)
			and s.pbr_library.ends_with("h1234abcd/pbr") and w.model_library.ends_with("h1234abcd/models"))
	_check("apply is false when unmounted", not DotMapStore.apply(MANIFEST["licence"], FakeCloud.new(), s, w))
	_check("one mounted dir without shared slices", s.pbr_libraries.size() == 1 and w.model_libraries.size() == 1)
	var lic: Dictionary = MANIFEST["licence"].duplicate(true)
	lic["store_pack"]["shared"] = [{"id": "gamemann/store-shared-aa", "version": "h1"}, {"id": "gamemann/store-shared-bb", "version": "h2"}]
	cloud.mounted["gamemann/store-shared-aa@h1"] = "res://dot_cloud/gamemann/store-shared-aa/h1/"
	var s2 := DotMapSurfaces.new()
	var w2 := DotMapBspMesh.new()
	DotMapStore.apply(lic, cloud, s2, w2)
	_check("mounted shared slices are searched after the map's own", s2.pbr_libraries.size() == 2 and w2.model_libraries.size() == 2
			and s2.pbr_libraries[1] == "res://dot_cloud/gamemann/store-shared-aa/h1/pbr" and w2.model_libraries[0].ends_with("h1234abcd/models"))
	_check("an unmounted shared slice is skipped", DotMapStore.mount_dirs(lic, cloud).size() == 2)
	s2.pbr_libraries = PackedStringArray(["res://nothing_a/pbr", "res://nothing_b/pbr"])
	_check("a set in no shared folder falls back to the single library", s2._pbr_dir("res://m", "", {"file": "pbr/x", "tier": "2k"}) == "res://dot_cloud/gamemann/store-x/h1234abcd/pbr/x/2k")
	_completed += 1


func _missing_slices() -> void:
	_entered += 1
	var lic: Dictionary = MANIFEST["licence"].duplicate(true)
	lic["store_pack"]["shared"] = [{"id": "gamemann/store-shared-aa", "version": "h1"}]
	DotMapStore.reset()
	var warns: Array[Dictionary] = []
	var sink := func(rec: Dictionary) -> void:
		if rec["channel"] == DotMapStore.CHANNEL and rec["level"] == DotLog.Level.WARN:
			warns.append(rec)
	DotLog.set_level(DotLog.Level.WARN)
	DotLog.add_sink(sink)
	_check("no notice before anything was tried", DotMapStore.notice(lic) == "")
	var res: DotResult = await DotMapStore.ensure(lic, OfflineCloud.new())
	_check("an unreachable slice fails ensure", not res.ok)
	_check("both slices are named missing", DotMapStore.missing(lic, OfflineCloud.new()) == PackedStringArray(["gamemann/store-x@h1234abcd", "gamemann/store-shared-aa@h1"]))
	_check("the notice says the art is low-detail", DotMapStore.notice(lic).begins_with("Low-detail art: 2"))
	_check("the credits line carries the notice", DotMapCredits.line({"licence": lic}).contains("Low-detail art"))
	var w := DotMapBspMesh.new()
	w.source_path = "res://nowhere/m.json"
	_check("apply is false without the slices", not DotMapStore.apply(lic, OfflineCloud.new(), DotMapSurfaces.new(), w))
	DotMapStore.apply(lic, null, DotMapSurfaces.new(), w)
	_check("one warning however often it is applied", warns.size() == 1)
	_check("the warning names every slice and how to get them", warns.size() == 1 and str(warns[0]["fields"].get("slices", "")).contains("store-shared-aa@h1")
			and str(warns[0]["message"]).contains("stage_stores.sh"))
	DotMapStore.reset()
	await DotMapStore.ensure(lic, null)
	_check("no cloud at all is a notice too, and ensure stays ok", DotMapStore.notice(lic) != "")
	var art := lic.duplicate(true)
	art["pbr_store"] = "stores/pbr-library"
	art["textures"] = [{"kind": "pbr", "file": "pbr/Bricks", "tier": "1k"}]
	var base := ProjectSettings.globalize_path("user://store_demo_art")
	DotMapStore.reset()
	await DotMapStore.ensure(art, null, "", base)
	_check("no cloud and no staged art is a notice that names the stager", DotMapStore.notice(art).contains("stage_stores.sh"))
	DirAccess.make_dir_recursive_absolute(base.path_join("stores/pbr-library/Bricks/1k"))
	DotMapStore.reset()
	res = await DotMapStore.ensure(art, null, "", base)
	_check("no cloud but the raw stores staged beside the pack is installed art", res.ok and DotMapStore.notice(art) == "")
	DirAccess.remove_absolute(base.path_join("stores/pbr-library/Bricks/1k"))
	DotMapStore.reset()
	var cloud := FakeCloud.new()
	await DotMapStore.ensure(lic, cloud)
	_check("a later fetch clears the notice", DotMapStore.notice(lic) == "")
	DotLog.remove_sink(sink)
	DotLog.set_level(DotLog.Level.ERROR)
	DotMapStore.reset()
	_completed += 1


func _stand_ins() -> void:
	_entered += 1
	var dir := "user://store_demo_pack"
	DirAccess.make_dir_recursive_absolute(dir + "/textures")
	var img := Image.create(8, 8, false, Image.FORMAT_RGB8)
	img.fill(Color(0.2, 0.6, 0.3))
	img.save_webp(dir + "/textures/fb_Moss.webp")
	var w := DotMapBspMesh.new()
	w.source_path = dir + "/m.json"
	w.manifest = {"licence": {"pbr_store": "../.stores/pbr-library", "textures": [
		{"kind": "pbr", "key": "pbr:pbr_Bricks059", "file": "pbr/Bricks059", "tier": "1k", "colour": [0.5, 0.3, 0.2], "sources": ["walls/red01"]},
		{"kind": "pbr", "key": "pbr:pbr_Xq7", "file": "pbr/Xq7", "tier": "1k", "colour": [0.25, 0.5, 0.75], "sources": ["models/blank"]},
		{"kind": "pbr", "key": "pbr:pbr_Moss", "file": "pbr/Moss", "tier": "1k", "fallback_file": "textures/fb_Moss.webp"},
	]}}
	var s := DotMapSurfaces.new()
	s.use_lightmap = false
	var mat_for := s.world_material_for(w, dir)
	_check("every missing set is listed", s.missing_sets.size() == 3)
	var brick: Material = mat_for.call({"free": "pbr:pbr_Bricks059", "colour": [0.4, 0.2, 0.1]})
	_check("a named set stands in as its kind's photo", brick is StandardMaterial3D and (brick as StandardMaterial3D).albedo_texture != null
			and (brick as StandardMaterial3D).resource_name == "brick")
	_check("tinted to the face's own colour, never white", (brick as StandardMaterial3D).albedo_color != Color.WHITE)
	var flat: Material = mat_for.call({"free": "pbr:pbr_Xq7", "colour": [0.25, 0.5, 0.75]})
	var fc: Color = (flat as StandardMaterial3D).albedo_color if flat is StandardMaterial3D else Color.BLACK
	_check("an unnamed set is neutral grey at the face's luma, never its own hue",
			flat is StandardMaterial3D and is_equal_approx(fc.r, fc.g) and is_equal_approx(fc.g, fc.b) and absf(fc.r - 0.4538) < 0.002)
	var saturated: Material = mat_for.call({"free": "pbr:pbr_Xq7", "colour": [0.0, 0.0, 1.0]})
	var sc: Color = (saturated as StandardMaterial3D).albedo_color
	_check("a saturated blue average is grey, floored at STAND_IN_FLOOR", is_equal_approx(sc.r, sc.b) and is_equal_approx(sc.g, sc.b)
			and is_equal_approx(sc.b, DotMapSurfaces.STAND_IN_FLOOR))
	var small: Material = mat_for.call({"free": "pbr:pbr_Moss"})
	_check("the pack's small albedo wins over a guess", small is StandardMaterial3D and (small as StandardMaterial3D).albedo_texture != null
			and (small as StandardMaterial3D).albedo_texture.get_width() == 8)
	_check("nothing is drawn the blank grey", not [brick, flat, small].any(func(m: Material) -> bool:
			return m is StandardMaterial3D and (m as StandardMaterial3D).albedo_color.is_equal_approx(Color(0.55, 0.55, 0.55))))
	w.manifest["lightmap"] = {"pages": [{"width": 1, "height": 1, "offset": 0}]}
	w._blob = PackedByteArray([0, 0, 0, 0])
	var lit_s := DotMapSurfaces.new()
	var lit_for := lit_s.world_material_for(w, dir)
	var lit_flat: Material = lit_for.call({"free": "pbr:pbr_Xq7", "colour": [0.25, 0.5, 0.75], "lightmap_page": 0})
	_check("a lit map keeps its lightmap on a flat stand-in", lit_flat is ShaderMaterial and (lit_flat as ShaderMaterial).get_shader_parameter("lightmap") != null
			and (lit_flat as ShaderMaterial).get_shader_parameter("albedo_tex") != null)
	var lit_brick: Material = lit_for.call({"free": "pbr:pbr_Bricks059", "colour": [0.4, 0.2, 0.1], "lightmap_page": 0})
	_check("and on a kind stand-in, tinted", lit_brick is ShaderMaterial and (lit_brick as ShaderMaterial).get_shader_parameter("tint") != Vector3.ONE)
	_check("stand_in_kind reads the converter's words", s.stand_in_kind("Bricks059") == &"brick" and s.stand_in_kind("nature/grass01") == &"grass"
			and s.stand_in_kind("models/blank") == &"")
	_completed += 1


func _missing_models() -> void:
	_entered += 1
	var w := DotMapBspMesh.new()
	w.source_path = "user://store_demo_models/m.json"
	w.manifest = {"licence": {"model_store": "../.stores/model-library", "model_stand_ins": [
		{"stand_in": "lib/ph_shelf", "store_file": "polyhaven/ph_shelf/ph_shelf.gltf"},
		{"stand_in": "lib/ph_lamp", "store_file": "polyhaven/ph_lamp/ph_lamp.gltf"},
		{"stand_in": "lib/ph_truck", "store_file": "polyhaven/ph_truck/ph_truck.gltf"},
		{"stand_in": "lib/sf_pine_tree_d45218", "store_file": "sketchfab/pine/pine.glb"},
	]}, "props": [
		{"stand_in": "lib/ph_shelf", "at": [2, 0, 3], "yaw": 90.0, "size": 1.6, "solid": 6,
			"collide": {"box": [1.0, 1.5, 0.4], "at": [2, 0.75, 3], "yaw": 90.0}},
		{"stand_in": "lib/ph_lamp", "at": [-4, 0, 1], "yaw": 0.0, "size": 0.6,
			"bounds": {"box": [0.3, 0.6, 0.3], "at": [-4, 0.3, 1], "yaw": 0.0}},
		{"stand_in": "lib/ph_truck", "at": [9, 0, 9], "yaw": 0.0, "size": 5.0, "solid": 6},
		{"stand_in": "lib/ph_shelf", "at": [6, 0, -2], "yaw": 0.0, "size": 1.6, "solid": 6,
			"collide": {"box": [1.0, 1.5, 0.4], "at": [6, 0.75, -2], "yaw": 0.0}},
		{"stand_in": "lib/sf_pine_tree_d45218", "at": [20, 0, 20], "yaw": 0.0, "size": 11.7, "solid": 6,
			"collide": {"box": [3.6, 11.7, 3.6], "at": [20, 5.85, 20], "yaw": 0.0}},
	]}
	var warns: Array[Dictionary] = []
	var sink := func(rec: Dictionary) -> void:
		if rec["channel"] == DotMapBspMesh.CHANNEL and rec["level"] == DotLog.Level.WARN:
			warns.append(rec)
	DotLog.set_level(DotLog.Level.WARN)
	DotLog.add_sink(sink)
	var bodies: Array[StaticBody3D] = []
	var props := w.build_props(Callable(), func(b: StaticBody3D) -> void: bodies.append(b))
	var proxies := props.get_children().filter(func(c: Node) -> bool: return c.has_meta(&"dot_map_proxy"))
	_check("a missing library model with measured bounds is drawn as a box", proxies.size() == 4 and w.missing_proxied == 4)
	_check("one with no measure is left out, and counted", w.missing_models == 5)
	var shelf := proxies[0] as MeshInstance3D
	_check("the box is the original's measured size", (shelf.mesh as BoxMesh).size.is_equal_approx(Vector3(1.0, 1.5, 0.4))
			and shelf.position.is_equal_approx(Vector3(2, 0.75, 3)))
	_check("only the solid proxies collide", bodies.size() == 3)
	var drawn := proxies.map(func(p: MeshInstance3D) -> AABB: return p.global_transform * p.get_aabb() if p.is_inside_tree() else p.transform * p.get_aabb())
	var server := w.build_prop_collision()
	var unseen := 0
	for cs: Node in server.get_children():
		var c := (cs as CollisionShape3D).transform.origin
		if not drawn.any(func(b: AABB) -> bool: return b.grow(0.01).has_point(c)):
			unseen += 1
	_check("no invisible solid: every collision box has a drawn box around it", server.get_child_count() == 3 and unseen == 0)
	_check("nothing collides where nothing is drawn (the unmeasured truck)", not bodies.any(func(b: StaticBody3D) -> bool: return b.position.distance_to(Vector3(9, 0, 9)) < 3.0))
	w.build_props().free()
	var unseen_root := w.draw_unseen_boxes([[9.02, 1.5, 9.0, 2.0, 3.0, 5.0, 0.0], [9.0, 10.0, 9.0, 2.0, 3.0, 5.0, 0.0], [-40.0, 1.0, -40.0, 1.0, 2.0, 1.0, 0.0]])
	_check("a game's own box at the unmeasured truck is drawn, and only that one", unseen_root != null and unseen_root.get_child_count() == 1
			and (unseen_root.get_child(0) as Node3D).position.is_equal_approx(Vector3(9.02, 1.5, 9.0)))
	if unseen_root != null:
		unseen_root.free()
	_check("one warning per map, however often it is built", warns.size() == 1)
	_check("the warning counts the boxes and says how to get the models", warns.size() == 1 and str(warns[0]["message"]).contains("4 drawn as low-detail boxes, 1 left out")
			and str(warns[0]["message"]).contains("stage_stores.sh"))
	_check("a map without a store_pack warns too", warns.size() == 1 and str(warns[0]["fields"].get("store_pack", "")) == "none")
	var tree_box := (bodies[2].get_child(0) as CollisionShape3D).shape as BoxShape3D
	_check("a tree collides as its trunk, not its crown", tree_box.size.is_equal_approx(Vector3(0.54, 11.7, 0.54)))
	var server_tree := ((server.get_child(2) as CollisionShape3D).shape as BoxShape3D).size
	_check("and the same on a server", server_tree.is_equal_approx(Vector3(0.54, 11.7, 0.54)))
	_check("its proxy is a trunk with a crown that does not collide", (proxies[3] as MeshInstance3D).get_aabb().size.x < 1.0 and proxies[3].get_child_count() == 1)
	_check("a street lamp is not a tree", DotMapBspMesh.is_tree({"stand_in": "lib/ph_street_lamp_01"}) == false
			and DotMapBspMesh.is_tree({"stand_in": "tree"}) and DotMapBspMesh.is_tree({"stand_in": "lib/kenney_retro-urban-kit_tree-large"}))
	DotLog.remove_sink(sink)
	DotLog.set_level(DotLog.Level.ERROR)
	server.free()
	props.free()
	DotMapBspMesh._support_material = null
	DotMapBspMesh._tinted.clear()
	_completed += 1
