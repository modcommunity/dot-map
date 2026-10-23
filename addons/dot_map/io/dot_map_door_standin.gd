class_name DotMapDoorStandIn
extends RefCounted

## The drawn panel of a prop_door_rotating, which is a placed model with no brush: a node at the
## hinge, yawed by the entity's [code]angles[/code], with a box panel that lies along the entity's
## local +Y (source axes) and a body of its own. [DotMapMoverNode] swings the node, so the panel
## and its collision turn with it. A door hung off an authored hinge ([code]panel_yaw[/code]) lies along the line from it. A real model replaces the panel through [code]door_fn[/code].

## Width, height, thickness in metres.
const SIZE := Vector3(1.02, 2.13, 0.07)


## The node for [param mover] (a prop_door_rotating record) with [param yaw_degrees] from the
## entity's angles. [param size] overrides [constant SIZE]; [param layer] is the collision layer.
static func build(mover: DotMapMover, yaw_degrees: float, size: Vector3 = SIZE, layer: int = 1) -> Node3D:
	if not is_nan(mover.panel_yaw):
		yaw_degrees = mover.panel_yaw
		if mover.panel_width > 0.1:
			size.x = mover.panel_width
	var root := Node3D.new()
	root.name = ("Door_%d" % mover.entity)
	root.position = mover.origin
	root.rotation.y = deg_to_rad(yaw_degrees)
	var panel := MeshInstance3D.new()
	panel.name = "Panel"
	var box := BoxMesh.new()
	box.size = Vector3(size.z, size.y, size.x)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.31, 0.19)
	mat.roughness = 0.8
	box.material = mat
	panel.mesh = box
	panel.position = Vector3(0.0, size.y * 0.5, -size.x * 0.5)
	root.add_child(panel)
	if mover.solid:
		var body := AnimatableBody3D.new()
		body.name = "col_solid"
		body.collision_layer = layer
		body.collision_mask = 0
		body.set_meta(&"hull_kind", "solid")
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = box.size
		cs.shape = shape
		cs.position = panel.position
		body.add_child(cs)
		root.add_child(body)
	return root
