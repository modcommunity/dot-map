class_name DotMapVolumes
extends RefCounted

## Every volume of a converted map, stepped from the game's tick. Build it from the manifest's
## entities and the [DotMapIO] that runs the map's logic, then give it the bodies once a tick:
##
## [codeblock]
## var vols := DotMapVolumes.build(DotMapEntities.from_manifest(world.manifest), io)
## ladder.volumes = vols.ladder_boxes()      # dot-player-controller's DotFpsLadderMode
## swim.volumes = vols.water_boxes()         # and DotFpsSwimMode
## io.damage_fn = func(body, amount, kind, attacker): ...
## # every tick, after io.advance(1):
## vols.step([{"id": 1, "body": player, "position": feet, "kind": "player"}])
## [/codeblock]
##
## Ladders and water are data for the controller (boxes), not areas, so a client replaying
## prediction gets the answer the server had. Everything else reaches the game through the
## callables on [DotMapIO]: [member DotMapIO.damage_fn] for a hurt volume, [member DotMapIO.move_fn]
## for a push or teleport, [member DotMapIO.event_fn] for gravity.

var io: DotMapIO
var nodes: Array[DotMapVolumeNode] = []
## Seconds between hits from a burning fire, and its default radius (source units).
var fire_period := 0.5
var fire_radius_units := 64.0

var _mover_nodes: Array[DotMapMoverNode] = []
var _movers_checked := false
var _scapes: Array[DotMapSoundscape] = []
var _scapes_checked := false
var _heard: Dictionary = {}


## One node per volume of [param entities], each joined to its entity in [param io] by index.
static func build(entities: DotMapEntities, io: DotMapIO, destinations: Dictionary = {}) -> DotMapVolumes:
	var vols := DotMapVolumes.new()
	vols.io = io
	if not destinations.is_empty():
		io.destinations = destinations
	for v: DotMapVolume in entities.volumes:
		vols.nodes.append(DotMapVolumeNode.new(v, io.entity_of(v.entity) if v.entity >= 0 else null))
	return vols


## Runs one step for [param bodies] (see [method DotMapVolumeNode.step]), then the area damage
## explosions and fires queued.
func step(bodies: Array) -> void:
	for n in nodes:
		n.step(io, bodies)
	_fires(bodies)
	_blasts(bodies)
	_soundscapes(bodies)
	_movers(bodies)
	io.settle()


## The boxes of every active ladder brush, for [code]DotFpsLadderMode.volumes[/code].
func ladder_boxes() -> Array[AABB]:
	return _boxes("ladder")


## The boxes of every active water brush (slime too), for [code]DotFpsSwimMode.volumes[/code].
func water_boxes() -> Array[AABB]:
	return _boxes("water")


func _boxes(kind: String) -> Array[AABB]:
	var out: Array[AABB] = []
	for n in nodes:
		if n.volume.kind == kind and n.active():
			out.append_array(n.volume.brush_boxes())
	return out


## Bodies in the way of a moving door, lift or spinner are pushed, then hurt and turned back.
func _movers(bodies: Array) -> void:
	if not _movers_checked:
		_movers_checked = true
		for e: DotMapEntity in io.entities:
			if e is DotMapMoverNode:
				_mover_nodes.append(e)
	for m: DotMapMoverNode in _mover_nodes:
		m.push_bodies(io, bodies)


## The nearest enabled soundscape that covers each player; an event when it changes.
func _soundscapes(bodies: Array) -> void:
	if _scapes_checked and _scapes.is_empty():
		return
	if not _scapes_checked:
		_scapes_checked = true
		for e: DotMapEntity in io.entities:
			if e is DotMapSoundscape:
				_scapes.append(e)
		if _scapes.is_empty():
			return
	for info: Dictionary in bodies:
		if str(info.get("kind", "player")) != "player":
			continue
		var best: DotMapSoundscape = null
		var best_d := INF
		var at: Vector3 = info["position"]
		for s: DotMapSoundscape in _scapes:
			if not s.alive or not s.enabled or not s.covers(io, at):
				continue
			var d := at.distance_to(s.origin(io))
			if d < best_d:
				best_d = d
				best = s
		var id: Variant = info["id"]
		var prev: Variant = _heard.get(id)
		if best == prev:
			continue
		_heard[id] = best
		if best != null:
			best.fire(io, "OnPlay", info.get("body"))
		io.event("soundscape", {"body": info.get("body"), "name": best.resolved_name(io) if best != null else "",
				"entity": best, "positions": best.positions(io) if best != null else []})


func _blasts(bodies: Array) -> void:
	var queue := io.area_damage
	io.area_damage = []
	for b: Dictionary in queue:
		for info: Dictionary in bodies:
			var d := ((info["position"] as Vector3) + Vector3(0.0, 0.9, 0.0)).distance_to(b["origin"])
			var r: float = b["radius"]
			if d <= r:
				io.damage(info.get("body"), float(b["amount"]) * (1.0 - 0.5 * d / maxf(r, 0.001)), str(b["kind"]), b["source"])


func _fires(bodies: Array) -> void:
	if io.now % maxi(1, io.ticks_for(fire_period)) != 0:
		return
	for e: DotMapEntity in io.entities:
		if e is DotMapEffect and e.alive and e.enabled and e.classname.to_lower() == "env_fire" and e.key_float("damagescale", 1.0) > 0.0:
			var at := e.origin(io)
			var r := maxf(e.key_float("firesize", fire_radius_units), 1.0) * io.unit_scale
			for info: Dictionary in bodies:
				if ((info["position"] as Vector3) + Vector3(0.0, 0.9, 0.0)).distance_to(at) <= r:
					io.damage(info.get("body"), 10.0 * fire_period * e.key_float("damagescale", 1.0), "burn", e)


func describe() -> Dictionary:
	var counts := {}
	for n in nodes:
		counts[n.volume.kind] = int(counts.get(n.volume.kind, 0)) + 1
	return {"volumes": nodes.size(), "kinds": counts}
