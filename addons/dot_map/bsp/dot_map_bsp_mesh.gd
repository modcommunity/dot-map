class_name DotMapBspMesh
extends "mesh_parts/mesh_props.gd"

## A converted map's drawn world and collision: the [code]dot-bsp-mesh[/code] files [code]tools/bsp/bsp.py mesh[/code] writes ([code]<id>.json[/code] + [code]<id>.bin[/code]), read back into meshes, convex shapes and mover and volume records; start at [code]DotMapBspMesh.load_prefix(path)[/code] then [method build_node].
## Game-neutral: [method build_node] asks a callback for each surface's [Material]; [method hull_shapes] returns shapes with their kind and the game makes the bodies. Positions are metres in Godot axes, and every brush entity gets its own node at its origin so a door turns about its hinge.
## The .bin is planar and gzip'd, read synchronously with no thread (it runs in a browser), and its sha256 is checked against the manifest first.

## One static body with a box per solid prop (see [constant SOLID_BOX]), in world space and with no meshes, for a
## server that draws nothing and a client that draws [method build_props] without [code]collide_fn[/code].
## The boxes match [method build_props]'s own solid bodies. Null when no prop is solid.
func build_prop_collision(scene_for: Callable = Callable()) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "SolidProps"
	var cache := {}
	var longest_of := {}
	for rec: Dictionary in manifest.get("props", []):
		if not int(rec.get("solid", 0)) in SOLID_BOX or (skip_loose and rec.has("loose")):
			continue
		var n: Node3D = null
		if not rec.has("box"):
			n = _place_prop(rec, scene_for, cache, longest_of)
			if n == null and not rec.has("collide"):
				continue
		for box in _solid_boxes(rec, n):
			var shape := BoxShape3D.new()
			shape.size = box["size"]
			var cs := CollisionShape3D.new()
			cs.shape = shape
			cs.transform = box["transform"]
			body.add_child(cs)
		if n != null:
			n.free()
	_free_templates(cache)
	_decompose_cache.clear()
	if body.get_child_count() == 0:
		body.free()
		return null
	return body



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
