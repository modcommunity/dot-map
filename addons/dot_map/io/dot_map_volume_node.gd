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
		for info: Dictionary in bodies:
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
	return volume.touches_column(info["position"], float(info.get("height", 1.8)))


func _admits(io: DotMapIO, info: Dictionary) -> bool:
	if not TRIGGER_KINDS.has(volume.kind):
		return true
	var flags := volume.spawnflags & 15
	if flags != 0 and (flags & int(KIND_FLAG.get(str(info.get("kind", "player")), 1))) == 0:
		return false
	return _filter_passes(io, info)


## A filter entity named by [code]filtername[/code]: filter_activator_name and
## filter_activator_class are understood (and [code]negated[/code]); another class admits everyone and is counted.
func _filter_passes(io: DotMapIO, info: Dictionary) -> bool:
	if volume.filter.is_empty():
		return true
	var found := io.find(volume.filter)
	if found.is_empty():
		return true
	return _entity_passes(io, found[0], info, 0)


## One filter entity against a body: activator name and class, and filter_multi (filtertype 0 all, 1 any
## of filter01..20, which may name other filters). Another class admits everyone and is counted.
func _entity_passes(io: DotMapIO, f: DotMapEntity, info: Dictionary, depth: int) -> bool:
	var match_: bool
	match f.classname.to_lower():
		"filter_activator_name":
			match_ = str(info.get("name", "")).matchn(f.key("filtername"))
		"filter_activator_class":
			match_ = str(info.get("class", "")).matchn(f.key("filterclass"))
		"filter_multi":
			var any := f.key("filtertype") == "1"
			match_ = not any
			if depth < 4:
				for i in range(1, 21):
					var nm := f.key("filter%02d" % i)
					if nm.is_empty():
						continue
					var sub := io.find(nm)
					if sub.is_empty():
						continue
					var ok := _entity_passes(io, sub[0], info, depth + 1)
					if any and ok:
						match_ = true
						break
					if not any and not ok:
						match_ = false
						break
		_:
			var k := "filter|" + f.classname.to_lower()
			io.unhandled[k] = int(io.unhandled.get(k, 0)) + 1
			return true
	return match_ != f.flag("negated")


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
		if v != Vector3.ZERO:
			io.move_body(info.get("body"), v)


func _teleport(io: DotMapIO, info: Dictionary) -> void:
	var dest_name := volume.target
	if entity != null and dest_name.is_empty():
		dest_name = entity.key("target")
	var dest: Variant = io.destinations.get(dest_name)
	if not dest is Dictionary:
		io.unresolved["teleport:" + dest_name] = int(io.unresolved.get("teleport:" + dest_name, 0)) + 1
		return
	var at: Array = (dest as Dictionary)["at"]
	var pos := Vector3(at[0], at[1], at[2])
	var yaw := float((dest as Dictionary).get("yaw", 0.0))
	var landmark := entity.key("landmark") if entity != null else ""
	if not landmark.is_empty() and io.destinations.get(landmark) is Dictionary:
		var lm: Array = (io.destinations[landmark] as Dictionary)["at"]
		pos += (info["position"] as Vector3) - Vector3(lm[0], lm[1], lm[2])
	io.move_body(info.get("body"), Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), pos))
	io.event("teleport", {"body": info.get("body"), "to": dest_name, "position": pos})
