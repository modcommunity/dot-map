class_name DotMapVolumeNode
extends RefCounted

## One trigger, hurt, push, teleport, gravity, water or ladder volume of a map, joined to the
## [DotMapEntity] that carries its outputs. [method step] finds who is inside and tells the entity
## (and, for push, teleport and gravity, the game) about entries, exits and bodies that stay.

const TRIGGER_KINDS := ["multiple", "once", "teleport", "push", "hurt", "gravity", "soundscape"]
## Body kind to the trigger spawnflag that admits it (clients, NPCs, pushables, physics objects).
const KIND_FLAG := {"player": 1, "npc": 2, "pushable": 4, "physics": 8}

var volume: DotMapVolume
var entity: DotMapEntity = null
var inside: Dictionary = {}
## Parent follow: the movers the volume hangs from (nearest first) for the parent name in [member _parent_of],
## and their pose when it was attached (identity for the map's own parent, the pose then for a SetParent).
var _parent_of := "\u0001"
var _chain: Array[DotMapMoverNode] = []
var _attach := Transform3D.IDENTITY
## The parent's motion this step: brush frame to world, and back. Identity when nothing carries the volume.
var _frame := Transform3D.IDENTITY
var _inv := Transform3D.IDENTITY


func _init(v: DotMapVolume, e: DotMapEntity) -> void:
	volume = v
	entity = e
	if e is DotMapPush:
		(e as DotMapPush).direction = v.direction
		(e as DotMapPush).speed = v.speed


## Whether the volume does anything now: its entity is alive and enabled.
func active() -> bool:
	if entity != null:
		return entity.alive and entity.enabled
	return not volume.disabled


## One step: [param bodies] are dictionaries [code]{id, body, position (feet), height, kind, name, class}[/code].
func step(io: DotMapIO, bodies: Array) -> void:
	var now_in := {}
	if active():
		_follow(io)
		var turned := not _frame.basis.is_equal_approx(Basis.IDENTITY)
		# A body whose column lies outside the volume's box touches none of it: most volumes of a map are far from most
		# bodies, and the exact test below costs a call per brush plane.
		var culls := volume.culls_columns() and not turned
		var box := volume.column_box()
		var lo := box.position
		var hi := box.end
		for info: Dictionary in bodies:
			if culls:
				var at: Vector3 = (info["position"] as Vector3) - _frame.origin
				if at.x < lo.x or at.x > hi.x or at.z < lo.z or at.z > hi.z or at.y > hi.y \
						or at.y + float(info.get("height", 1.8)) < lo.y:
					continue
			if _admits(io, info) and _touches(info):
				now_in[info["id"]] = info
	else:
		inside.clear()
		return
	for id: Variant in now_in:
		if not inside.has(id):
			inside[id] = now_in[id]
			_enter(io, now_in[id])
	for id: Variant in inside.keys():
		if not now_in.has(id):
			var gone: Dictionary = inside[id]
			inside.erase(id)
			_leave(io, gone)
	for id: Variant in now_in:
		if not inside.has(id):
			continue    # an output the entry fired disabled the volume
		inside[id] = now_in[id]
		_stay(io, now_in[id])


func _touches(info: Dictionary) -> bool:
	if _frame == Transform3D.IDENTITY:
		return volume.touches_column(info["position"], float(info.get("height", 1.8)))
	var feet := (info["position"] as Vector3) - Vector3(0.0, DotMapVolume.COLUMN_SLACK, 0.0)
	var span := Vector3(0.0, float(info.get("height", 1.8)) + DotMapVolume.COLUMN_SLACK, 0.0)
	return volume.touches_segment(_inv * feet, _inv.basis * span)


## A volume parented to a door, lift, train or spinner goes where it goes, as in the engine: the brushes stay in
## their own frame and each body is looked at from it. The chain is walked through parents that do not move
## themselves (a func_brush on a train) and composed nearest first. Found again only when the parent name changes.
func _follow(io: DotMapIO) -> void:
	var pname := entity.parentname if entity != null else str(volume.record.get("parentname", ""))
	if pname != _parent_of:
		_parent_of = pname
		_chain = _movers_above(io, pname)
		_attach = Transform3D.IDENTITY
		var original := str(volume.record.get("parentname", entity.record.get("parentname", "") if entity != null else ""))
		if pname.to_lower() != original.to_lower():
			_attach = _pose(io)    # SetParent: the volume keeps where it is now and moves from here
	if _chain.is_empty():
		_frame = Transform3D.IDENTITY
		_inv = _frame
		return
	_frame = _pose(io) * _attach.affine_inverse()
	_inv = _frame.affine_inverse()


func _pose(io: DotMapIO) -> Transform3D:
	var t := Transform3D.IDENTITY
	for m in _chain:
		if m.alive:
			t = m.pose_delta(io.now, io.rate) * t
	return t


static func _movers_above(io: DotMapIO, pname: String) -> Array[DotMapMoverNode]:
	var out: Array[DotMapMoverNode] = []
	var seen := {}
	var name := pname.strip_edges().split(",", false, 1)[0] if not pname.strip_edges().is_empty() else ""
	while not name.is_empty() and not seen.has(name.to_lower()):
		seen[name.to_lower()] = true
		var found := io.find(name)
		if found.is_empty():
			break
		var p: DotMapEntity = found[0]
		if p is DotMapMoverNode:
			out.append(p)
		name = p.parentname.split(",", false, 1)[0] if not p.parentname.is_empty() else ""
	return out


func _admits(io: DotMapIO, info: Dictionary) -> bool:
	if not TRIGGER_KINDS.has(volume.kind):
		return true
	var flags := volume.spawnflags & 15
	if flags != 0 and (flags & int(KIND_FLAG.get(str(info.get("kind", "player")), 1))) == 0:
		return false
	return _filter_passes(io, info)


## A filter entity named by [code]filtername[/code]: filter_activator_name, filter_activator_class and
## filter_activator_team (the body's "team", Source's 2 and 3) are understood (and [code]negated[/code]); another class admits everyone and is counted.
func _filter_passes(io: DotMapIO, info: Dictionary) -> bool:
	if volume.filter.is_empty():
		return true
	var found := io.find(volume.filter)
	if found.is_empty():
		return true
	return _entity_passes(io, found[0], info, 0)


## One filter entity against a body: [method DotMapFilter.entity_passes] (activator name, class and team, damage type,
## filter_multi). Another class admits everyone and is counted.
func _entity_passes(io: DotMapIO, f: DotMapEntity, info: Dictionary, depth: int) -> bool:
	return DotMapFilter.entity_passes(io, f, info, depth)


func _enter(io: DotMapIO, info: Dictionary) -> void:
	if entity != null:
		entity.body_enter(io, info)
	match volume.kind:
		"teleport":
			_teleport(io, info)
		"gravity":
			io.event("gravity", {"body": info.get("body"), "scale": float(volume.record.get("gravity", 1.0)), "inside": true})


func _leave(io: DotMapIO, info: Dictionary) -> void:
	if entity != null:
		entity.body_leave(io, info)
	if volume.kind == "gravity" and not (entity != null and entity.flag("persist")):
		io.event("gravity", {"body": info.get("body"), "scale": 1.0, "inside": false})


func _stay(io: DotMapIO, info: Dictionary) -> void:
	if entity != null:
		entity.body_inside(io, info)
	if volume.kind == "push":
		var v := volume.push_velocity() if not entity is DotMapPush else (entity as DotMapPush).velocity()
		v = _frame.basis * v    # a parent that turned the volume turned its push
		if v != Vector3.ZERO:
			io.move_body(info.get("body"), v)


## trigger_teleport as the engine runs it: the destination is the entity's live [code]target[/code]
## (SetRemoteDestination and AddOutput re-aim it), found by name ignoring case. Without a landmark the
## body lands on the destination facing its yaw (spawnflag 32 keeps the body's own yaw); with a
## landmark it keeps its offset from the landmark and its own yaw, unless UseLandmarkAngles snaps it
## to the destination's. Velocity is kept either way. A body reports its own yaw (degrees) as
## [code]yaw[/code] in [param info]; one that does not gets the destination's.
func _teleport(io: DotMapIO, info: Dictionary) -> void:
	var dest_name := volume.target
	if entity != null:
		var live := entity.key("target")
		# A converter retarget (retargeted_from) stands while the key still holds what the author wrote.
		if not live.is_empty() and live != str(volume.record.get("retargeted_from", "")):
			dest_name = live
	var dest := _destination(io, dest_name)
	if dest.is_empty():
		io.unresolved["teleport:" + dest_name] = int(io.unresolved.get("teleport:" + dest_name, 0)) + 1
		return
	var at: Array = dest["at"]
	var pos := Vector3(at[0], at[1], at[2])
	var yaw := float(dest.get("yaw", 0.0))
	var landmark := entity.key("landmark") if entity != null else ""
	if landmark.is_empty():
		landmark = str(volume.record.get("landmark", ""))
	var lm := _destination(io, landmark) if not landmark.is_empty() else {}
	var own_yaw: Variant = info.get("yaw")
	if not lm.is_empty():
		var la: Array = lm["at"]
		pos += (info["position"] as Vector3) - Vector3(la[0], la[1], la[2])
		var snap := entity.flag("uselandmarkangles") if entity != null else bool(volume.record.get("landmark_angles", false))
		if not snap and own_yaw != null:
			yaw = float(own_yaw)
	elif (volume.spawnflags & 32) != 0 and own_yaw != null:
		yaw = float(own_yaw)
	io.move_body(info.get("body"), Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), pos))
	io.event("teleport", {"body": info.get("body"), "to": dest_name, "position": pos})


## A destination by name as the engine finds it: exact first, then ignoring case.
static func _destination(io: DotMapIO, name: String) -> Dictionary:
	var d: Variant = io.destinations.get(name)
	if d is Dictionary:
		return d
	var lo := name.to_lower()
	for k: Variant in io.destinations:
		if str(k).to_lower() == lo and io.destinations[k] is Dictionary:
			return io.destinations[k]
	return {}
