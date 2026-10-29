class_name DotMapNavLinks
extends RefCounted

## What a converted map's own logic adds to a navigation mesh: the doors and teleports a body cannot just walk through, and the buttons, triggers and shots that make each usable.
## Data, not behaviour: [method read] takes a built map world by duck typing and returns [code]{teleports, doors, openers}[/code] dictionaries a bake or an AI reads; a baked mesh sees a shut door as a wall, this says which a path may cross.
## [code]opened_by[/code] lists openers (walk, use, shoot) nearest hop first, each with [code]hops[/code]; a chain needing a carried item or a count of presses, or an opener with no box, is left out.

## Inputs that close, lock or disable: a chain through one of them never helps a runner get through.
const NEGATIVE_INPUTS := ["disable", "turnoff", "kill", "killhierarchy", "close", "lock"]
## Outputs a shot fires.
const SHOT_OUTPUTS := ["ondamaged", "onhealthchanged"]
## Source's trigger spawnflag for "clients".
const FLAG_CLIENTS := 1
## Longest output chain followed back from a door or teleport.
const MAX_HOPS := 10

## Bumped when a key changes meaning.
const FORMAT := 1


## Reads [param world]'s doors, teleports and openers. See the class doc for the shape.
static func read(world: Object) -> Dictionary:
	var out := {"format": FORMAT, "doors": [], "teleports": [], "openers": {}, "skipped": {}}
	if world == null:
		return out
	var io: Object = world.get("io")
	if io == null:
		return out
	var volumes: Object = world.get("volumes")
	var nodes: Array = volumes.get("nodes") if volumes != null else []
	var openers := _openers(io, nodes)
	out["openers"] = openers
	var feeders := _feeders(io)
	var destinations: Dictionary = io.get("destinations")
	for node: Object in nodes:
		var volume: Object = node.get("volume")
		if volume == null or str(volume.get("kind")) != "teleport":
			continue
		var flags := int(volume.get("spawnflags")) & 15
		if flags != 0 and flags & FLAG_CLIENTS == 0:
			_skip(out, "flags")
			continue
		if str(volume.get("filter")) != "":
			_skip(out, "filtered")
			continue
		var name := str(volume.get("target"))
		var entity: Object = node.get("entity")
		if name == "" and entity != null and entity.has_method("key"):
			name = str(entity.call("key", "target"))
		var dest: Variant = destinations.get(name)
		if not dest is Dictionary or not (dest as Dictionary).get("at") is Array:
			_skip(out, "no_destination")
			continue
		var at: Array = (dest as Dictionary)["at"]
		var index := int(volume.get("entity"))
		var enabled := not node.has_method("active") or bool(node.call("active"))
		(out["teleports"] as Array).append({"entity": index, "name": str(volume.get("targetname")), "box": volume.call("bounds"),
			"to": Vector3(at[0], at[1], at[2]), "enabled": enabled, "opened_by": [] if enabled else _sources(index, feeders, openers)})
	for e: Object in io.get("entities"):
		var door := _door(e, feeders, openers)
		if not door.is_empty():
			(out["doors"] as Array).append(door)
	return out


## The chain of an opener back to [param index] as entity indices, nearest hop first, for a consumer that wants to
## print why: `[opener, ..., target]`. Empty when it does not reach.
static func chain(io: Object, from: int, to: int) -> PackedInt32Array:
	var feeders := _feeders(io)
	var came := {to: -1}
	var frontier: Array = [to]
	for _depth in MAX_HOPS:
		var next: Array = []
		for at: int in frontier:
			for f: int in feeders.get(at, []):
				if came.has(f):
					continue
				came[f] = at
				next.append(f)
				if f == from:
					var path := PackedInt32Array()
					var cur := from
					while cur != -1:
						path.append(cur)
						cur = int(came[cur])
					return path
		frontier = next
	return PackedInt32Array()


static func _skip(out: Dictionary, why: String) -> void:
	var skipped: Dictionary = out["skipped"]
	skipped[why] = int(skipped.get(why, 0)) + 1


## A door or slide that starts shut: its box at rest and what opens it.
static func _door(e: Object, feeders: Dictionary, openers: Dictionary) -> Dictionary:
	var mover: Object = e.get("mover")
	if mover == null or bool(mover.get("start_open")) or not bool(mover.get("solid")):
		return {}
	if not str(mover.get("kind")) in ["slide", "rotate", "rotate_button"] or mover.get("hit_half") == Vector3.ZERO and e.get("hit_half") == Vector3.ZERO:
		return {}
	if str(mover.get("kind")) == "rotate_button" or bool(mover.get("use")) and str(e.get("classname")).contains("button"):
		return {}
	var index := int(e.get("index"))
	var opens := "touch" if bool(mover.get("touch")) else ("use" if bool(mover.get("use")) else "output")
	return {"entity": index, "name": str(e.get("targetname")), "classname": str(e.get("classname")), "box": _box_of(e),
		"opens": opens, "locked": bool(e.get("locked")), "opened_by": _sources(index, feeders, openers)}


## The openers whose output chains reach [param index], nearest first.
static func _sources(index: int, feeders: Dictionary, openers: Dictionary) -> Array:
	var found: Array = []
	var seen := {index: true}
	var frontier: Array = [index]
	for hops in range(1, MAX_HOPS + 1):
		var next: Array = []
		for at: int in frontier:
			for from: int in feeders.get(at, []):
				if seen.has(from):
					continue
				seen[from] = true
				next.append(from)
				if openers.has(from):
					var o: Dictionary = (openers[from] as Dictionary).duplicate()
					o["hops"] = hops
					found.append(o)
		frontier = next
		if frontier.is_empty():
			break
	return found


## `{target entity index: [entity indices with an output that reaches it by a positive input]}`.
static func _feeders(io: Object) -> Dictionary:
	var feeders := {}
	for e: Object in io.get("entities"):
		for link: Dictionary in e.get("links") if e.get("links") != null else []:
			if str(link["input"]).to_lower() in NEGATIVE_INPUTS:
				continue
			for target: Object in io.call("resolve", str(link["target"]), e, null):
				var list: Array = feeders.get(int(target.get("index")), [])
				var from := int(e.get("index"))
				if not list.has(from):
					list.append(from)
				feeders[int(target.get("index"))] = list
	return feeders


## Every runner action that can start a chain: trigger volumes, buttons, and anything with a shot output and a box.
static func _openers(io: Object, nodes: Array) -> Dictionary:
	var out := {}
	for node: Object in nodes:
		var volume: Object = node.get("volume")
		var kind := str(volume.get("kind"))
		var flags := int(volume.get("spawnflags")) & 15
		if (kind != "multiple" and kind != "once") or (flags != 0 and flags & FLAG_CLIENTS == 0) or str(volume.get("filter")) != "":
			continue
		var index := int(volume.get("entity"))
		out[index] = {"index": index, "name": str(volume.get("targetname")), "kind": "walk", "box": volume.call("bounds")}
	for e: Object in io.get("entities"):
		var mover: Object = e.get("mover")
		var index := int(e.get("index"))
		if mover == null or str(mover.get("kind")) in ["spin", "path"] or e.get("hit_half") == Vector3.ZERO:
			continue
		var shot := false
		for link: Dictionary in e.get("links") if e.get("links") != null else []:
			if str(link["output"]).to_lower() in SHOT_OUTPUTS:
				shot = true
		if bool(mover.get("use")):
			out[index] = {"index": index, "name": str(e.get("targetname")), "kind": "use", "box": _box_of(e)}
		elif shot:
			out[index] = {"index": index, "name": str(e.get("targetname")), "kind": "shoot", "box": _box_of(e)}
	return out


## An entity's rest-pose solid as a world box.
static func _box_of(e: Object) -> AABB:
	var half: Vector3 = e.get("hit_half")
	var frame: Transform3D = e.get("hit_frame")
	var box := AABB(frame.origin, Vector3.ZERO)
	for corner in 8:
		box = box.expand(frame * Vector3(
			half.x if corner & 1 else -half.x, half.y if corner & 2 else -half.y, half.z if corner & 4 else -half.z))
	return box
