class_name DotMapVisibility
extends Node

## Draws only what the camera could see, from a converted map's precomputed visibility: [code]vis.setup(world, world_node)[/code] in the scene, [code]vis.set_door_open(name, true)[/code] opens a door's area portals.
## The camera's cluster, not the frustum: a chunk is drawn when one of its clusters is in the union of the PVS rows around the camera and in an area reachable through open portals; the set is looked up again every [member move_step]. Occluders hide props and characters behind walls.
## Nothing runs on a headless host unless [member run_headless] is set.

const CHANNEL := "dot_map.visibility"

enum Mode { OFF, PVS, OCCLUDERS, BOTH }
enum Shadows { NONE, ALL, REACHING }

## Metres a chunk is assumed to throw a sun shadow.
const SUN_SWEEP := 2000.0
const MODE_NAMES := {"off": Mode.OFF, "pvs": Mode.PVS, "occluders": Mode.OCCLUDERS, "both": Mode.BOTH}

signal clusters_changed(camera_clusters: PackedInt32Array)

## off, pvs, occluders or both ([method parse_mode]); a part the map has no data for is skipped.
@export var mode: Mode = Mode.BOTH
## The camera to follow; unset follows the viewport's current camera.
@export var camera_ref: DotNodeRef = null
## Metres round the camera whose clusters count as its own, so crossing a leaf never shows a frame late.
@export var margin: float = 1.0
## Metres the camera moves before its clusters are looked up again.
@export var move_step: float = 0.25
## What a chunk hidden by the PVS still does: NONE disappears (light leaks where it shaded), ALL is drawn shadow-only, REACHING is drawn
## shadow-only only while a shadow-casting light that touches a drawn chunk reaches it.
@export var shadows: Shadows = Shadows.REACHING
## Metres past which a world chunk is not drawn: below 0 the map's own fog far plane, 0 never.
@export var chunk_view_distance: float = -1.0
@export var run_headless: bool = false

var world: DotMapBspMesh = null
var root: Node3D = null

var _planes := PackedFloat32Array()
var _nodes := PackedInt32Array()
var _leaf_cluster := PackedInt32Array()
var _cluster_area := PackedInt32Array()
var _pvs_offsets := PackedInt32Array()
var _pvs := PackedByteArray()
var _head: int = -1
var _clusters: int = 0
var _row_bytes: int = 0
## [{node, clusters: PackedInt32Array, shown: bool}]
var _items: Array[Dictionary] = []
var _portals: Array = []
var _portal_open := {}
var _portal_targets := {}
var _occluder: OccluderInstance3D = null
var _viewport_had_occlusion: bool = false
var _last_pos := Vector3.INF
var _camera_clusters := PackedInt32Array()
var _visible_bits := PackedByteArray()
var _updates: int = 0
var _dirty: bool = true


static func parse_mode(text: String) -> Mode:
	return MODE_NAMES.get(text.strip_edges().to_lower(), Mode.BOTH)


## Reads [param mesh]'s visibility and takes over [param drawn] (its [method DotMapBspMesh.build_node]
## tree, with [code]Props[/code] anywhere below it). Fails when the map has no visibility data;
## the world is then drawn as it was.
func setup(mesh: DotMapBspMesh, drawn: Node3D) -> DotResult:
	world = mesh
	root = drawn
	var info: Dictionary = mesh.manifest.get("vis", {})
	_clusters = int(info.get("clusters", 0))
	if _clusters > 0:
		_planes = mesh.vis_bytes("planes", 16).to_float32_array()
		_nodes = mesh.vis_bytes("nodes", 12).to_int32_array()
		_leaf_cluster = mesh.vis_bytes("leaf_cluster").to_int32_array()
		_cluster_area = mesh.vis_bytes("cluster_area").to_int32_array()
		_pvs_offsets = mesh.vis_bytes("pvs_offsets").to_int32_array()
		_pvs = mesh.vis_bytes("pvs", 1)
		_head = int(info.get("head", 0))
		if _pvs_offsets.size() != _clusters or _nodes.is_empty() or _leaf_cluster.is_empty():
			_clusters = 0
	_row_bytes = (_clusters + 7) / 8
	_portals = info.get("portals", [])
	for e: Dictionary in info.get("portal_entities", []):
		var t := str(e.get("target", ""))
		if not t.is_empty() and not bool(e.get("window", false)):
			if not _portal_targets.has(t):
				_portal_targets[t] = []
			(_portal_targets[t] as Array).append(int(e["key"]))
	_collect(drawn)
	_build_occluder(mesh)
	_apply_view_distance(mesh)
	_last_pos = Vector3.INF
	DotLog.debug(CHANNEL, "visibility set up", describe())
	if _clusters == 0 and _occluder == null:
		return DotResult.fail(DotError.CODE_UNSUPPORTED, "the map has no visibility data", str(mesh.manifest.get("name", "")))
	_apply_mode()
	return DotResult.success(self)


func set_mode(m: Mode) -> void:
	mode = m
	_apply_mode()


## Opens or closes one area portal by its key; a portal nobody set is open, so an unbound door never hides anything.
func set_portal_open(key: int, open: bool) -> void:
	_portal_open[key] = open
	_last_pos = Vector3.INF
	_dirty = true


## Opens or closes every area portal that follows the door named [param targetname].
func set_door_open(targetname: String, open: bool) -> void:
	for key: int in _portal_targets.get(targetname, []):
		_portal_open[key] = open
	_last_pos = Vector3.INF
	_dirty = true


## Follows every [DotAreaPortal] under [param under] (key or door set): their state is applied now and on each change. Returns how many were bound.
func bind_area_portals(under: Node) -> int:
	var n := 0
	for p in under.find_children("*", "DotAreaPortal", true, false):
		var portal := p as DotAreaPortal
		if portal.key < 0 and portal.door.is_empty():
			continue
		if not portal.toggled.is_connected(_on_area_portal.bind(portal)):
			portal.toggled.connect(_on_area_portal.bind(portal))
		_on_area_portal(portal.open, portal)
		n += 1
	return n


func _on_area_portal(open: bool, portal: DotAreaPortal) -> void:
	if portal.key >= 0:
		set_portal_open(portal.key, open)
	if not portal.door.is_empty():
		set_door_open(portal.door, open)


## Door names that have area portals following them, for a game to bind.
func portal_doors() -> PackedStringArray:
	return PackedStringArray(_portal_targets.keys())


func has_pvs() -> bool:
	return _clusters > 0


func _pvs_on() -> bool:
	return _clusters > 0 and (mode == Mode.PVS or mode == Mode.BOTH)


func _apply_mode() -> void:
	var occl := _occluder != null and (mode == Mode.OCCLUDERS or mode == Mode.BOTH)
	if _occluder != null:
		_occluder.visible = occl
		if is_inside_tree():
			if occl:
				_viewport_had_occlusion = get_viewport().use_occlusion_culling or _viewport_had_occlusion
				get_viewport().use_occlusion_culling = true
			elif not _viewport_had_occlusion:
				get_viewport().use_occlusion_culling = false
	if not _pvs_on():
		_show_all()
	_last_pos = Vector3.INF


func _collect(drawn: Node3D) -> void:
	_items.clear()
	if _clusters == 0:
		return
	var stack: Array[Node] = [drawn]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.has_meta(&"vis_clusters"):
			_items.append({"node": n, "clusters": n.get_meta(&"vis_clusters"), "shown": true, "cast": false, "box": _aabb_under(n as Node3D, drawn) if n is Node3D else AABB()})
			continue
		if n.name == &"Props":
			for p in n.get_children():
				if p is Node3D:
					var box := _aabb_under(p as Node3D, drawn)
					if box.size != Vector3.ZERO:
						_items.append({"node": p, "clusters": clusters_in_box(box.grow(0.05)), "shown": true, "cast": false, "box": box})
			continue
		stack.append_array(n.get_children())
	for item in _items:
		if (item["clusters"] as PackedInt32Array).is_empty():
			item["clusters"] = PackedInt32Array([-1])   # touches no cluster: always drawn


## The bounds of every [VisualInstance3D] under [param n], in [param base]'s space.
static func _aabb_under(n: Node3D, base: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for v in n.find_children("*", "VisualInstance3D", true, false) + ([n] if n is VisualInstance3D else []):
		var xf := Transform3D.IDENTITY
		var at: Node = v
		while at != null and at != base:
			if at is Node3D:
				xf = (at as Node3D).transform * xf
			at = at.get_parent()
		var box: AABB = xf * (v as VisualInstance3D).get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


func _build_occluder(mesh: DotMapBspMesh) -> void:
	var verts := mesh.vis_bytes("occluder_vertices", 12).to_vector3_array()
	var index := mesh.vis_bytes("occluder_indices").to_int32_array()
	if verts.is_empty() or index.size() < 3:
		return
	var occ := ArrayOccluder3D.new()
	occ.set_arrays(verts, index)
	_occluder = OccluderInstance3D.new()
	_occluder.name = "Occluders"
	_occluder.occluder = occ
	root.add_child(_occluder)


func _apply_view_distance(mesh: DotMapBspMesh) -> void:
	var far := chunk_view_distance
	if far < 0.0:
		far = 0.0
		for f: Variant in mesh.environment_data().get("fog", []):
			if f is Dictionary and bool(f.get("enabled", false)) and float(f.get("far_z", -1)) > 0.0:
				far = maxf(far, float(f["far_z"]))
	if far <= 0.0:
		return
	for item in _items:
		var gi := item["node"] as GeometryInstance3D
		if gi != null and gi.visibility_range_end == 0.0:
			gi.visibility_range_end = far + 0.5 * gi.get_aabb().size.length()


func _process(_delta: float) -> void:
	if not _pvs_on() or (DotPlatform.is_headless() and not run_headless) or root == null:
		return
	var cam := _camera()
	if cam == null:
		return
	update_from(root.global_transform.affine_inverse() * cam.global_position)


func _camera() -> Camera3D:
	if camera_ref != null:
		return camera_ref.resolve_or_null(self, CHANNEL) as Camera3D
	return get_viewport().get_camera_3d()


## Shows and hides for a camera at [param local] (the drawn tree's space). Cheap when it has not moved.
func update_from(local: Vector3) -> void:
	if not _pvs_on() or local.distance_to(_last_pos) < move_step:
		return
	_last_pos = local
	var cams := clusters_in_box(AABB(local - Vector3.ONE * margin, Vector3.ONE * margin * 2.0))
	if cams == _camera_clusters and not _dirty:
		return
	_dirty = false
	_camera_clusters = cams
	_updates += 1
	if cams.is_empty():
		_show_all()
		clusters_changed.emit(cams)
		return
	_visible_bits = PackedByteArray()
	_visible_bits.resize(_row_bytes)
	for c in cams:
		_or_row(c)
	_mask_areas(cams)
	for item in _items:
		var show := false
		for c: int in item["clusters"]:
			if c < 0 or (_visible_bits[c >> 3] & (1 << (c & 7))) != 0:
				show = true
				break
		item["want"] = show
	_apply_shown(local)
	clusters_changed.emit(cams)


## Whether cluster [param c] is drawn for the camera's last position.
func is_cluster_visible(c: int) -> bool:
	if not _pvs_on() or _camera_clusters.is_empty() or c < 0 or c >= _clusters:
		return true
	return (_visible_bits[c >> 3] & (1 << (c & 7))) != 0


func _or_row(c: int) -> void:
	var at := _pvs_offsets[c]
	if at < 0 or at >= _pvs.size():
		_visible_bits.fill(255)
		return
	var o := 0
	while o < _row_bytes and at < _pvs.size():
		var b := _pvs[at]
		if b != 0:
			_visible_bits[o] |= b
			o += 1
			at += 1
		else:
			o += _pvs[at + 1] if at + 1 < _pvs.size() else _row_bytes
			at += 2


## Clears the clusters of areas the camera cannot reach through an open portal.
func _mask_areas(cams: PackedInt32Array) -> void:
	if _portals.is_empty() or not _portal_open.values().has(false):
		return
	var reach := {}
	var todo: Array[int] = []
	for c in cams:
		var a := _cluster_area[c]
		if not reach.has(a):
			reach[a] = true
			todo.append(a)
	while not todo.is_empty():
		var a: int = todo.pop_back()
		for p: Array in _portals:
			if not bool(_portal_open.get(int(p[0]), true)):
				continue
			var other := -1
			if int(p[1]) == a:
				other = int(p[2])
			elif int(p[2]) == a:
				other = int(p[1])
			if other >= 0 and not reach.has(other):
				reach[other] = true
				todo.append(other)
	for c in _clusters:
		if not reach.has(_cluster_area[c]):
			_visible_bits[c >> 3] &= ~(1 << (c & 7))


## The leaf a point (the drawn tree's space) is in.
func leaf_at(p: Vector3) -> int:
	var node := _head
	while node >= 0:
		var pl := _nodes[node * 3] * 4
		var front := _planes[pl] * p.x + _planes[pl + 1] * p.y + _planes[pl + 2] * p.z - _planes[pl + 3] >= 0.0
		node = _nodes[node * 3 + (1 if front else 2)]
	return -1 - node


## Every cluster whose leaves a box (the drawn tree's space) touches.
func clusters_in_box(box: AABB) -> PackedInt32Array:
	var out := {}
	if _clusters == 0:
		return PackedInt32Array()
	var c := box.get_center()
	var h := box.size * 0.5
	var stack := PackedInt32Array([_head])
	while not stack.is_empty():
		var node := stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		if node < 0:
			var leaf := -1 - node
			if leaf < _leaf_cluster.size() and _leaf_cluster[leaf] >= 0:
				out[_leaf_cluster[leaf]] = true
			continue
		var pl := _nodes[node * 3] * 4
		var nx := _planes[pl]
		var ny := _planes[pl + 1]
		var nz := _planes[pl + 2]
		var d := nx * c.x + ny * c.y + nz * c.z - _planes[pl + 3]
		var r := absf(nx) * h.x + absf(ny) * h.y + absf(nz) * h.z
		if d > -r:
			stack.append(_nodes[node * 3 + 1])
		if d < r:
			stack.append(_nodes[node * 3 + 2])
	var keys := PackedInt32Array(out.keys())
	keys.sort()
	return keys


## Applies each item's "want" (drawn or not), then lets hidden ones keep casting shadows per [member shadows].
func _apply_shown(local: Vector3) -> void:
	var lights: Array[Dictionary] = []
	if shadows == Shadows.REACHING:
		lights = _active_lights(local)
	for item in _items:
		var show: bool = item["want"]
		var cast := false
		if not show:
			cast = shadows == Shadows.ALL or (shadows == Shadows.REACHING and _reached(item["box"], lights))
		_set_shown(item, show, cast)


## Shadow-casting lights, in the drawn tree's space, whose reach touches a drawn chunk: only those can put a hidden chunk's shadow on screen.
func _active_lights(local: Vector3) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if root == null or not root.is_inside_tree():
		return out
	var inv := root.global_transform.affine_inverse()
	for l in root.get_tree().root.find_children("*", "Light3D", true, false):
		var light := l as Light3D
		if not light.shadow_enabled or not light.is_visible_in_tree():
			continue
		var reach := INF
		var at := local
		if light is OmniLight3D:
			reach = (light as OmniLight3D).omni_range
			at = inv * light.global_position
		elif light is SpotLight3D:
			reach = (light as SpotLight3D).spot_range
			at = inv * light.global_position
		elif light is DirectionalLight3D:
			reach = (light as DirectionalLight3D).directional_shadow_max_distance
		var receivers: Array[AABB] = []
		for item in _items:
			if item["want"] and _box_distance(item["box"], at) <= reach:
				receivers.append(item["box"])
		if receivers.is_empty():
			continue
		var entry := {"at": at, "reach": reach}
		if light is DirectionalLight3D:
			entry["dir"] = (inv.basis * -light.global_basis.z).normalized()
			entry["receivers"] = receivers
		out.append(entry)
	return out


static func _box_distance(box: AABB, p: Vector3) -> float:
	var q := p.clamp(box.position, box.end)
	return p.distance_to(q)


func _reached(box: AABB, lights: Array[Dictionary]) -> bool:
	for l in lights:
		if l.has("dir"):
			# A sun's shadow falls along its direction from anywhere up-sun, however far: sweep the box and ask what it can land on.
			var swept := box.merge(AABB(box.position + (l["dir"] as Vector3) * SUN_SWEEP, box.size))
			for r: AABB in l["receivers"]:
				if swept.intersects(r):
					return true
		elif _box_distance(box, l["at"]) <= float(l["reach"]):
			return true
	return false


func _set_shown(item: Dictionary, show: bool, cast: bool = false) -> void:
	if item["shown"] == show and item["cast"] == cast:
		return
	item["shown"] = show
	item["cast"] = cast
	var n: Node = item["node"]
	if not is_instance_valid(n):
		return
	if n.has_meta(&"shadow_proxy"):
		var proxy: Variant = n.get_meta(&"shadow_proxy")
		if is_instance_valid(proxy):
			(proxy as Node3D).visible = show or cast
		(n as Node3D).visible = show
		return
	if cast:
		(n as Node3D).visible = true
		for g in ([n] if n is GeometryInstance3D else n.find_children("*", "GeometryInstance3D", true, false)):
			if not g.has_meta(&"vis_cast"):
				g.set_meta(&"vis_cast", (g as GeometryInstance3D).cast_shadow)
			(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		return
	for g in ([n] if n is GeometryInstance3D else n.find_children("*", "GeometryInstance3D", true, false)):
		if g.has_meta(&"vis_cast"):
			(g as GeometryInstance3D).cast_shadow = g.get_meta(&"vis_cast")
			g.remove_meta(&"vis_cast")
	(n as Node3D).visible = show


func _show_all() -> void:
	for item in _items:
		_set_shown(item, true)
	_camera_clusters = PackedInt32Array()
	_dirty = true


## How many registered nodes are drawn now, of how many.
func shown_count() -> Vector2i:
	var on := 0
	for item in _items:
		if item["shown"]:
			on += 1
	return Vector2i(on, _items.size())


func describe() -> Dictionary:
	var shown := shown_count()
	return {"mode": MODE_NAMES.find_key(mode), "clusters": _clusters, "items": shown.y, "shown": shown.x,
			"camera_clusters": _camera_clusters.size(), "portals": _portals.size(),
			"occluder_triangles": (_occluder.occluder as ArrayOccluder3D).indices.size() / 3 if _occluder != null else 0,
			"updates": _updates}


func describe_lines() -> PackedStringArray:
	var d := describe()
	return PackedStringArray(["visibility %s: %d clusters, %d/%d drawn, camera in %d, %d portals, %d occluder triangles" % [
		d["mode"], d["clusters"], d["shown"], d["items"], d["camera_clusters"], d["portals"], d["occluder_triangles"]]])


func _exit_tree() -> void:
	if _occluder != null and not _viewport_had_occlusion and get_viewport() != null:
		get_viewport().use_occlusion_culling = false
