class_name DotMapTrail
extends Node3D

## An [code]env_spritetrail[/code]: a camera-facing additive ribbon behind a moving point. It samples [member follow] (or its own
## position) each frame, keeps the samples younger than [member lifetime], and tapers [member start_width] to [member end_width]
## with the alpha fading to nothing. A trail that never moves draws nothing. Nothing ships: the ribbon is untextured.

var lifetime := 0.5
var start_width := 0.2
var end_width := 0.0
var colour := Color(1, 1, 1, 1)
## Node whose position is trailed; null trails this node itself.
var follow: Node3D = null
## Most samples kept, so a fast follower cannot grow the mesh without bound.
var max_samples := 48
## Smallest move that adds a sample, in metres.
var min_step := 0.03

var _pts: Array = []
var _times: Array = []
var _mesh := ImmediateMesh.new()
var _clock := 0.0
var _view: MeshInstance3D


func _ready() -> void:
	_view = MeshInstance3D.new()
	_view.mesh = _mesh
	_view.top_level = true
	_view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_view.material_override = m
	add_child(_view)


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var at := follow.global_position if follow != null and is_instance_valid(follow) else global_position
	advance(delta, at, cam.global_position if cam != null else at + Vector3.UP * 10.0)


## Moves the clock on by [param delta], samples [param at] and rebuilds the ribbon facing [param eye]. Returns the sample count.
func advance(delta: float, at: Vector3, eye: Vector3) -> int:
	_clock += delta
	if _pts.is_empty() or (_pts.back() as Vector3).distance_to(at) >= min_step:
		_pts.append(at)
		_times.append(_clock)
	while not _times.is_empty() and (_clock - float(_times[0]) > lifetime or _pts.size() > max_samples):
		_pts.remove_at(0)
		_times.remove_at(0)
	_mesh.clear_surfaces()
	if _pts.size() < 2:
		return _pts.size()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in _pts.size():
		var age := clampf((_clock - float(_times[i])) / maxf(lifetime, 0.001), 0.0, 1.0)
		var p: Vector3 = _pts[i]
		var prev: Vector3 = _pts[maxi(i - 1, 0)]
		var next: Vector3 = _pts[mini(i + 1, _pts.size() - 1)]
		var side := (next - prev).cross(eye - p)
		side = side.normalized() if side.length() > 0.0001 else Vector3.RIGHT
		var half := lerpf(start_width, end_width, age) * 0.5
		var c := Color(colour.r, colour.g, colour.b, colour.a * (1.0 - age))
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(p + side * half)
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(p - side * half)
	_mesh.surface_end()
	return _pts.size()


func sample_count() -> int:
	return _pts.size()
