@tool
class_name DotAreaPortal
extends Node3D

## A door-sized box that blocks the view while closed: place it in a doorway or window, call [method
## set_open] from the door. Godot's [OccluderInstance3D] is static, so a door that opens cannot be an
## occluder on its own. This node owns one and swaps its shape in and out.

## Emitted when the state changes.
signal toggled(open: bool)

const GROUP := &"dot_area_portal"

## The doorway, in metres; the node's origin is the centre. Make it fill the opening and no more.
@export var size: Vector3 = Vector3(1.2, 2.2, 0.2):
	set(v):
		size = v.max(Vector3(0.01, 0.01, 0.01))
		_refresh()
## Open lets the view through. A door that starts shut leaves this off.
@export var open: bool = false:
	set(v):
		if v == open:
			return
		open = v
		_refresh()
		toggled.emit(open)
## An area portal key of a converted BSP map; -1 for none.
@export var key: int = -1
## A door name of a converted BSP map (its `target`); empty for none.
@export var door: String = ""

var _occluder: OccluderInstance3D = null
var _box := BoxOccluder3D.new()
var _gizmo: MeshInstance3D = null


func _ready() -> void:
	add_to_group(GROUP)
	_occluder = OccluderInstance3D.new()
	_occluder.name = "PortalOccluder"
	add_child(_occluder, false, Node.INTERNAL_MODE_FRONT)
	if Engine.is_editor_hint():
		_gizmo = MeshInstance3D.new()
		_gizmo.name = "PortalGizmo"
		add_child(_gizmo, false, Node.INTERNAL_MODE_FRONT)
	_refresh()


## Opens or closes the portal.
func set_open(value: bool) -> void:
	open = value


## True while the portal hides what is behind it.
func is_blocking() -> bool:
	return _occluder != null and _occluder.occluder != null


func describe() -> Dictionary:
	return {"size": size, "open": open, "key": key, "door": door, "blocking": is_blocking()}


func _refresh() -> void:
	if _occluder == null:
		return
	_box.size = size
	_occluder.occluder = null if open else _box
	if _gizmo != null:
		_gizmo.mesh = _gizmo_mesh()


func _gizmo_mesh() -> ArrayMesh:
	var h := size * 0.5
	var c: Array[Vector3] = []
	for i in 8:
		c.append(Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z))
	var pts := PackedVector3Array()
	for e: Array in [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]:
		pts.append(c[e[0]])
		pts.append(c[e[1]])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.3, 1.0, 0.4) if open else Color(1.0, 0.45, 0.2)
	mesh.surface_set_material(0, mat)
	return mesh
