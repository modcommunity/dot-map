extends Node3D

## [DotMapVisibility]: a hand-made three-cluster map, then real converted maps ray-cast for holes.

const SYNTH_CHECKS := 16
const SUN_CHECKS := 3
const LIGHT_CHECKS := 5
const MAP_CHECKS := 4

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()
var _entered := 0
var _completed := 0
var _expected_sections := 3
var _expected_checks := SYNTH_CHECKS + SUN_CHECKS + LIGHT_CHECKS


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _arg(key: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.split("=", true, 1)[1]
	return fallback


func _run() -> void:
	print("dot-map visibility")
	_test_synthetic()
	_test_sun_reach()
	_test_light_cache()
	var maps := _arg("maps", "")
	for prefix in (maps.split(",", false) if not maps.is_empty() else PackedStringArray()):
		_expected_sections += 1
		_expected_checks += MAP_CHECKS
		await _test_map(prefix, int(_arg("points", "40")), int(_arg("rays", "300")))
	print("")
	print("%d passed, %d failed" % [_passed, _failed])
	for line in _failures:
		print("  FAIL  %s" % line)
	print("%d of %d sections ran to their last line" % [_completed, _entered])
	if _entered != _expected_sections or _completed != _entered:
		print("ERROR: %d sections entered and %d completed, %d expected." % [_entered, _completed, _expected_sections])
		get_tree().quit(1)
		return
	if _passed + _failed != _expected_checks:
		print("ERROR: %d checks ran, %d expected. A section aborted part-way." % [_passed + _failed, _expected_checks])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		_failures.append(what)


## A hidden chunk casts sun shadow when its swept box lands on a drawn one: the grid never misses one the exact
## sweep finds, and thousands of hidden chunks against a thousand drawn ones stay cheap (a pair loop took 90 ms).
func _test_sun_reach() -> void:
	_entered += 1
	print("  sun reach: conservative grid, cost")
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var receivers: Array[AABB] = []
	for i in 200:
		receivers.append(AABB(Vector3(rng.randf_range(-300, 300), rng.randf_range(-50, 50), rng.randf_range(-300, 300)),
				Vector3(rng.randf_range(0.5, 40), rng.randf_range(0.5, 10), rng.randf_range(0.5, 40))))
	var grid := DotMapVisibility.ReceiverGrid.new(receivers)
	var dir := Vector3(0.4, -0.8, 0.2).normalized()
	var lost := 0
	var misses := 0
	for i in 2000:
		var b := AABB(Vector3(rng.randf_range(-400, 400), rng.randf_range(-100, 100), rng.randf_range(-400, 400)), Vector3(4, 4, 4))
		var swept := b.merge(AABB(b.position + dir * DotMapVisibility.SUN_SWEEP, b.size))
		var exact := false
		for r in receivers:
			exact = exact or swept.intersects(r)
		var got := grid.touches(swept)
		lost += int(exact and not got)
		misses += int(not got)
	_check(lost == 0, "the grid finds every receiver the exact sweep finds (%d lost)" % lost)
	_check(misses > 0, "and still answers no for some (%d of 2000)" % misses)
	var floor_tiles: Array[AABB] = []
	for x in 40:
		for z in 40:
			floor_tiles.append(AABB(Vector3(x * 10, -1, z * 10), Vector3(10, 1, 10)))
	var vis := DotMapVisibility.new()
	var lights: Array[Dictionary] = [{"at": Vector3.ZERO, "reach": INF, "dir": Vector3.RIGHT, "grid": DotMapVisibility.ReceiverGrid.new(floor_tiles)}]
	var t := Time.get_ticks_usec()
	var reached := 0
	for i in 3000:
		reached += int(vis._reached(AABB(Vector3(i % 400, 10, i / 8.0), Vector3.ONE), lights))
	var ms := (Time.get_ticks_usec() - t) / 1000.0
	_check(reached == 0 and ms < 60.0, "3000 hidden chunks over 1600 drawn ones: %d reached in %.1f ms (under 60)" % [reached, ms])
	vis.free()
	_completed += 1


func _test_light_cache() -> void:
	_entered += 1
	print("  light cache: found once, then kept by the tree signals")
	var holder := Node3D.new()
	add_child(holder)
	var vis := DotMapVisibility.new()
	vis.root = holder
	add_child(vis)
	var sun := OmniLight3D.new()
	sun.shadow_enabled = true
	holder.add_child(sun)
	_check(vis._all_lights().has(sun), "a light in the tree is found")
	var first := vis._all_lights()
	_check(vis._all_lights() == first and first.size() == 1, "a second ask returns the same list")
	var second := OmniLight3D.new()
	holder.add_child(second)
	_check(vis._all_lights().has(second), "a light added later is found")
	holder.remove_child(second)
	_check(not vis._all_lights().has(second), "a light removed is gone")
	second.free()
	remove_child(vis)
	_check(vis._all_lights().is_empty(), "leaving the tree drops the watch and the list")
	vis.free()
	holder.queue_free()
	_completed += 1


## Space split at x = 0, 10 and 20: cluster 1 west of 0, cluster 0 to 10, solid to 20, cluster 2 past it.
## Clusters 0 and 1 see each other through a portal (key 5, door "door"); cluster 2 sees itself only.
func _synthetic_mesh(with_vis: bool) -> DotMapBspMesh:
	var m := DotMapBspMesh.new()
	if not with_vis:
		return m
	var blob := PackedByteArray()
	var vis := {"clusters": 3, "head": 0, "portals": [[5, 1, 2]],
			"portal_entities": [{"key": 5, "target": "door", "start_open": false, "window": false}]}
	var put := func(key: String, bytes: PackedByteArray, count: int) -> void:
		vis[key] = {"offset": blob.size(), "count": count}
		blob.append_array(bytes)
	put.call("planes", PackedFloat32Array([1, 0, 0, 0, 1, 0, 0, 10, 1, 0, 0, 20]).to_byte_array(), 3)
	# node 0: x>=0 -> node 1, else leaf 1; node 1: x>=10 -> node 2, else leaf 0; node 2: x>=20 -> leaf 3, else leaf 2
	put.call("nodes", PackedInt32Array([0, 1, -2, 1, 2, -1, 2, -4, -3]).to_byte_array(), 3)
	put.call("leaf_cluster", PackedInt32Array([0, 1, -1, 2]).to_byte_array(), 4)
	put.call("cluster_area", PackedInt32Array([1, 2, 3]).to_byte_array(), 3)
	put.call("pvs_offsets", PackedInt32Array([0, 1, 2]).to_byte_array(), 3)
	put.call("pvs", PackedByteArray([3, 3, 4]), 3)
	m.manifest = {"vis": vis}
	m._blob = blob
	return m


func _test_synthetic() -> void:
	_entered += 1
	print("  synthetic: leaves, PVS, portals, solid, off")
	var drawn := Node3D.new()
	add_child(drawn)
	var parts: Array[Node3D] = []
	for c: Array in [[0], [1], [2], [-1]]:
		var n := Node3D.new()
		n.set_meta(&"vis_clusters", PackedInt32Array(c))
		drawn.add_child(n)
		parts.append(n)
	var vis := DotMapVisibility.new()
	vis.run_headless = true
	vis.margin = 0.5
	add_child(vis)
	_check(vis.setup(_synthetic_mesh(true), drawn).ok, "setup on a map with visibility")
	_check(vis.leaf_at(Vector3(-5, 0, 0)) == 1 and vis.leaf_at(Vector3(5, 0, 0)) == 0, "leaf_at either side of x = 0")
	_check(vis.leaf_at(Vector3(15, 0, 0)) == 2 and vis.leaf_at(Vector3(25, 0, 0)) == 3, "leaf_at in the wall and past it")
	_check(vis.clusters_in_box(AABB(Vector3(9, -1, -1), Vector3(12, 2, 2))) == PackedInt32Array([0, 2]),
			"a box across the wall touches clusters 0 and 2")
	var shown := func() -> Array: return parts.map(func(p: Node3D) -> bool: return p.visible)
	vis.update_from(Vector3(5, 0, 0))
	_check(shown.call() == [true, true, false, true], "from cluster 0: 0 and 1 drawn, 2 hidden, the unclustered drawn (%s)" % [shown.call()])
	vis.update_from(Vector3(25, 0, 0))
	_check(shown.call() == [false, false, true, true], "from cluster 2: only 2 (%s)" % [shown.call()])
	vis.update_from(Vector3(15, 0, 0))
	_check(shown.call() == [true, true, true, true], "a camera in solid draws everything (%s)" % [shown.call()])
	vis.update_from(Vector3(19.8, 0, 0))
	_check(shown.call() == [false, false, true, true], "a camera just inside the wall takes the cluster past it (%s)" % [shown.call()])
	_check(vis.portal_doors() == PackedStringArray(["door"]), "the portal's door is listed")
	vis.set_door_open("door", false)
	vis.update_from(Vector3(5, 0, 0))
	_check(shown.call() == [true, false, false, true], "a shut door hides the area behind it (%s)" % [shown.call()])
	vis.set_door_open("door", true)
	vis.update_from(Vector3(5, 0, 0))
	_check(shown.call() == [true, true, false, true], "opening it shows it again (%s)" % [shown.call()])
	vis.set_mode(DotMapVisibility.Mode.OFF)
	_check(shown.call() == [true, true, true, true], "mode off draws everything")
	vis.update_from(Vector3(25, 0, 0))
	_check(shown.call() == [true, true, true, true], "mode off ignores the camera")
	_check(DotMapVisibility.parse_mode(" PVS ") == DotMapVisibility.Mode.PVS and DotMapVisibility.parse_mode("x") == DotMapVisibility.Mode.BOTH,
			"modes parse, an unknown one is both")
	var none := DotMapVisibility.new()
	add_child(none)
	_check(not none.setup(_synthetic_mesh(false), drawn).ok, "a map with no visibility data fails setup")
	_check(vis.describe().has("clusters") and vis.describe_lines().size() == 1, "describe")
	none.queue_free()
	vis.queue_free()
	drawn.queue_free()
	_completed += 1


func _test_map(prefix: String, points: int, rays: int) -> void:
	_entered += 1
	print("  %s" % prefix)
	var read := DotMapBspMesh.load_prefix(prefix)
	_check(read.ok, "%s loads" % prefix)
	if not read.ok:
		_failed += MAP_CHECKS - 1
		_failures.append("%s: not tested" % prefix)
		_completed += 1
		return
	var world: DotMapBspMesh = read.value
	var node := world.build_node()
	var props := world.build_props()
	node.add_child(props)
	add_child(node)
	var vis := DotMapVisibility.new()
	vis.run_headless = true
	add_child(vis)
	vis.setup(world, node)
	_check(vis.has_pvs(), "%s carries visibility data (%d clusters)" % [prefix, int(world.manifest.get("vis", {}).get("clusters", 0))])
	var built := _collide_items(vis)
	var bodies: Dictionary = built["bodies"]
	var space_box: AABB = built["box"]
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var done := 0
	var tries := 0
	var holes := PackedStringArray()
	var gaps := 0
	var shown_sum := 0.0
	var probe := SphereShape3D.new()
	probe.radius = 0.4
	while done < points and tries < points * 400:
		tries += 1
		var p := space_box.position + Vector3(rng.randf(), rng.randf(), rng.randf()) * space_box.size
		var leaf := vis.leaf_at(p)
		if leaf < 0 or leaf >= vis._leaf_cluster.size() or vis._leaf_cluster[leaf] < 0:
			continue
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = probe
		q.transform = Transform3D(Basis(), p)
		if not space.intersect_shape(q, 1).is_empty():
			continue
		# open space that a ray straight down finds a floor under within 40 m: inside the map, not over the void
		var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(p, p + Vector3.DOWN * 40.0))
		if down.is_empty():
			continue
		done += 1
		vis._last_pos = Vector3.INF
		vis.update_from(p)
		var sc := vis.shown_count()
		shown_sum += float(sc.x) / maxf(1.0, float(sc.y))
		for r in rays:
			var z := rng.randf_range(-1.0, 1.0)
			var a := rng.randf_range(0.0, TAU)
			var d := Vector3(sqrt(1.0 - z * z) * cos(a), z, sqrt(1.0 - z * z) * sin(a))
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p, p + d * 300.0))
			if hit.is_empty():
				continue
			var item: Variant = bodies.get((hit["collider"] as Object).get_instance_id())
			if item != null and not item["shown"]:
				if _crosses_solid(vis, p, hit["position"]):
					gaps += 1
					continue
				holes.append("%s from %s hits hidden %s at %.1f m" % [prefix.get_file(), p.snapped(Vector3.ONE * 0.1),
						(item["node"] as Node).name, p.distance_to(hit["position"])] + " camera %s hit %s item %s" % [
						vis._camera_clusters, vis.clusters_in_box(AABB(hit["position"] - Vector3.ONE * 0.05, Vector3.ONE * 0.1)),
						item["clusters"]])
	_report_map(prefix, vis, points, rays, done, shown_sum, gaps, holes)
	vis.queue_free()
	node.queue_free()
	for id: int in bodies:
		(instance_from_id(id) as Node).queue_free()
	_completed += 1


## A static body of triangles per visibility item, so rays hit what the culler hides; returns {bodies, box}.
func _collide_items(vis: DotMapVisibility) -> Dictionary:
	var bodies := {}
	var space_box := AABB()
	for item in vis._items:
		var body := StaticBody3D.new()
		var target: Node = item["node"]
		for mi in ([target] if target is MeshInstance3D else target.find_children("*", "MeshInstance3D", true, false)):
			var mesh := (mi as MeshInstance3D).mesh
			if mesh == null:
				continue
			var shape := CollisionShape3D.new()
			var tri := ConcavePolygonShape3D.new()
			tri.set_faces(mesh.get_faces())
			tri.backface_collision = true
			shape.shape = tri
			shape.transform = (mi as Node3D).global_transform
			body.add_child(shape)
			if target is MeshInstance3D:
				space_box = space_box.merge((mi as MeshInstance3D).global_transform * mesh.get_aabb()) if space_box.size != Vector3.ZERO \
						else (mi as MeshInstance3D).global_transform * mesh.get_aabb()
		add_child(body)
		bodies[body.get_instance_id()] = item
	return {"bodies": bodies, "box": space_box}


## Prints the sampling summary and the first holes, then asserts there are none and that the PVS hides something.
func _report_map(prefix: String, vis: DotMapVisibility, points: int, rays: int, done: int, shown_sum: float, gaps: int, holes: PackedStringArray) -> void:
	print("    %d points, %d rays each, %.0f%% of %d chunks and props drawn on average, %d occluder triangles, %d rays through an undrawn solid" % [
			done, rays, 100.0 * shown_sum / maxf(1.0, done), vis._items.size(), vis.describe()["occluder_triangles"], gaps])
	for h in holes.slice(0, 10):
		print("    " + h)
	_check(holes.is_empty() and done >= points / 2, "%s: no ray from %d points meets a hidden chunk or prop (%d holes)" % [prefix, done, holes.size()])
	_check(shown_sum / maxf(1.0, done) < 0.95, "%s: the PVS hides something on average" % prefix)


## Whether the segment passes through a solid leaf: the drawn world has a gap there (a face the
## converter does not draw), which the map's own renderer would not see through either.
static func _crosses_solid(vis: DotMapVisibility, a: Vector3, b: Vector3) -> bool:
	var n := int(a.distance_to(b) / 0.05)
	for k in range(1, n):
		var leaf := vis.leaf_at(a.lerp(b, float(k) / n))
		if leaf >= 0 and leaf < vis._leaf_cluster.size() and vis._leaf_cluster[leaf] < 0:
			return true
	return false
