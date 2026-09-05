@tool
class_name DotMapSession
extends Node

## The node a game adds: which map is loaded, what plays next, and the switch between
## them.
##
## [codeblock]
## var session := DotMapSession.new()
## session.world_ref = DotNodeRef.of_path(^"../World")
## add_child(session)
## session.load_catalogue("res://maps/catalogue.json")
## await session.change_to(&"surf_beginner")
## [/codeblock]
##
## [b]A map change is the most dangerous thing a server does.[/b] Everything is
## mid-flight at once: players are in runs, entities are replicated, content may still
## be downloading, and the scene about to be freed is the one everything holds a
## reference to. The order here is the one that survives all of it, and each step is
## in it because leaving it out breaks something specific:
##
## 1. announce the change [i]before[/i] anything is torn down, so a timer can abandon
##    its runs and a netcode can stop replicating entities that are about to vanish;
## 2. fetch and load the new scene [i]before[/i] freeing the old one, so a failed
##    download leaves the server on a working map rather than on nothing;
## 3. free the old world and add the new one in the same frame;
## 4. announce that it is done, so listeners can rebuild.
##
## Step 2 is the one people skip. Freeing first is simpler, uses less memory, and
## turns a CDN having a bad day into a server with no map and no way back.

const CHANNEL := "map.session"

## About to change. Emitted before anything is freed. Abandon runs here.
signal changing(from: DotMapDef, to: DotMapDef)

## The new map is in the tree. [param world] is its root node.
signal changed(map: DotMapDef, world: Node)

## A change failed. The session is still on the map named by [member current].
signal change_failed(map: DotMapDef, reason: String)

## The map is over — its time ran out, or enough players rocked the vote.
##
## [b]The session does NOT change the map itself here.[/b] What happens when a map
## ends is a game's decision: run a vote, go to the next in the rotation, end the
## round first, or show a scoreboard for ten seconds. A session that changed the map
## on its own would have to be fought by every game that wanted any of those.
signal map_over(map: DotMapDef, reason: StringName)

## The map is nearly over. For a chat message or a HUD.
signal time_warning(seconds_left: float)

## Content is being fetched. For a progress screen.
signal fetching(map: DotMapDef)

@export_group("Content")

## A catalogue file to load on ready.
@export var catalogue_path: String = ""

## The map to load on ready, or empty to load nothing.
@export var initial_map: StringName = &""

@export_group("Wiring")

## Where the loaded map's root node is added.
##
## [b]A [DotNodeRef], not a hardcoded path[/b] — the family rule, and here it earns
## its keep immediately: a dedicated server puts the world under its game root, a
## client puts it under a scene that also holds the camera and the HUD, and a replay
## viewer puts two of them side by side.
@export var world_ref: DotNodeRef = null

@export_group("Rotation")

@export var rotation_mode: DotMapRotation.Mode = DotMapRotation.Mode.RANDOM

@export_range(0, 32, 1) var rotation_cooldown: int = 5

@export_group("Time limit")

## Seconds a map runs before the session asks for the next one. 0 disables it.
##
## A server that never changes map is not a server: somebody joins, plays the map
## they arrived on and leaves, and the rotation, the catalogue and the vote all exist
## and are never reached.
@export_range(0.0, 86400.0, 30.0) var map_seconds: float = 1800.0

## Seconds left when [signal time_warning] fires. 0 disables it.
@export_range(0.0, 3600.0, 10.0) var warn_seconds: float = 120.0

var catalogue: DotMapCatalogue = null
var rotation: DotMapRotation = null
var loader: DotMapLoader = null

## The map clock, rock-the-vote tally and extensions.
##
## Advanced by the host with [method advance], never by a wall clock — a server that
## stalls should not lose that time off its map, and a test must be able to run an
## hour of it in a millisecond.
var time_limit := DotMapTimeLimit.new()

## The map currently loaded, or null.
var current: DotMapDef = null

## The root node of the loaded map, or null.
var world: Node = null

## The zone file's text for the current map, for a host that has dot-timer.
##
## Text rather than a parsed `DotTimerZoneSet`, because dot-timer is optional and
## naming the class here would make every map load in a game without a timer fail to
## parse. The host parses it.
var zones_json: String = ""

## Whether a change is in progress. A second one is refused while it is.
var changing_now: bool = false

var _world_node: Node = null


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	loader = DotMapLoader.new()

	if catalogue == null:
		catalogue = DotMapCatalogue.new()

	rotation = DotMapRotation.of(catalogue)
	rotation.mode = rotation_mode
	rotation.cooldown = rotation_cooldown

	time_limit.duration = map_seconds
	time_limit.warn_at = warn_seconds
	time_limit.expired.connect(_on_time_expired)
	time_limit.warning.connect(func(left: float) -> void: time_warning.emit(left))

	if catalogue_path != "":
		var loaded := load_catalogue(catalogue_path)
		DotLog.result(CHANNEL, "loading the map catalogue", loaded)

	if initial_map != &"":
		var started: DotResult = await change_to(initial_map)
		DotLog.result(CHANNEL, "loading the initial map", started)


func load_catalogue(path: String) -> DotResult:
	var loaded := DotMapCatalogue.load_json(path)

	if not loaded.ok:
		return loaded

	catalogue = loaded.value

	if rotation != null:
		rotation.catalogue = catalogue

	for problem in catalogue.problems():
		DotLog.warn(CHANNEL, "catalogue problem", {"problem": problem})

	return DotResult.success(catalogue)


## Changes to a map by id.
func change_to(id: StringName) -> DotResult:
	if catalogue == null:
		return DotResult.fail(
			DotError.CODE_STATE, "No catalogue has been loaded."
		)

	var map := catalogue.get_map(id)

	if map == null:
		return DotResult.fail(
			DotError.CODE_IO, "No such map in the catalogue.", String(id)
		)

	return await change_to_map(map)


## Changes to the next map the rotation offers.
func change_to_next(players: int = 0) -> DotResult:
	if rotation == null:
		return DotResult.fail(DotError.CODE_STATE, "No rotation.")

	var next := rotation.choose(players)

	if next == null:
		return DotResult.fail(
			DotError.CODE_STATE, "The rotation has nothing to offer."
		)

	return await change_to_map(next)


func change_to_map(map: DotMapDef) -> DotResult:
	if map == null:
		return DotResult.fail(DotError.CODE_INVALID, "No map.")

	if changing_now:
		# Refused rather than queued. Two overlapping changes free the same node
		# twice, and the second one's `await` resumes into a tree the first has
		# already rebuilt — which is a crash whose stack trace points at neither.
		return DotResult.fail(
			DotError.CODE_STATE,
			"A map change is already in progress.",
			String(map.id)
		)

	changing_now = true

	var previous := current

	# Announced BEFORE anything is torn down, so a timer can abandon its runs and a
	# netcode can stop replicating entities that are about to be freed.
	changing.emit(previous, map)

	if not loader.is_ready(map):
		fetching.emit(map)

	var loaded: DotResult = await loader.load_map(map)

	if not loaded.ok:
		# Nothing has been freed yet, so the server is still on a working map. This
		# is the whole reason the load happens before the teardown.
		changing_now = false
		change_failed.emit(map, loaded.error.message)
		return loaded

	var zones := loader.load_zones(map)

	if not zones.ok:
		changing_now = false
		change_failed.emit(map, zones.error.message)
		return zones

	var resolved := _resolve_world_parent()

	if not resolved.ok:
		changing_now = false
		change_failed.emit(map, resolved.error.message)
		return resolved

	var parent: Node = resolved.value

	if world != null and is_instance_valid(world):
		# free() rather than queue_free(): the new world is added in this same call,
		# and a deferred free would leave both in the tree for a frame — two maps'
		# worth of collision geometry, and any group lookup finding the old one.
		world.get_parent().remove_child(world)
		world.free()

	world = (loaded.value as PackedScene).instantiate()
	world.name = "Map_" + String(map.id)
	parent.add_child(world)

	current = map
	zones_json = str(zones.value) if zones.value != null else ""

	rotation.note_played(map.id)

	# The clock restarts on every map, with the map's own length when it has one.
	# A long map deserves a longer limit and that is a property of the map rather
	# than of the server, which is why `expected_seconds` is on `DotMapDef`.
	time_limit.start(
		float(map.expected_seconds) * 3.0 if map.expected_seconds > 0 else -1.0
	)

	changing_now = false

	DotLog.info(CHANNEL, "map loaded", {
		"map": String(map.id), "version": map.version
	})

	changed.emit(map, world)

	return DotResult.success(world)


## Advances the map clock. Call once per simulated tick.
##
## Separate from a timer inside this node because the host owns the tick — the same
## reason [DotPropSpawner.advance] takes one. A node that ran its own [Timer] would
## count wall-clock seconds, and a server that stalled would lose them off its map.
func advance(delta: float) -> void:
	time_limit.advance(delta)


## Registers a player's rock-the-vote. Returns whether it passed.
func rock_the_vote(player_id: StringName, player_count: int) -> bool:
	return time_limit.rock_the_vote(player_id, player_count)


## Extends the current map. False when it has been extended as often as it may be.
func extend_map(seconds: float = -1.0) -> bool:
	return time_limit.extend(seconds)


func _on_time_expired(reason: StringName) -> void:
	DotLog.info(CHANNEL, "the map is over", {
		"map": String(current.id) if current != null else "-",
		"reason": String(reason),
	})

	map_over.emit(current, reason)


## Unloads the current map without loading another.
func unload() -> void:
	if world != null and is_instance_valid(world):
		changing.emit(current, null)
		world.get_parent().remove_child(world)
		world.free()

	world = null
	current = null
	zones_json = ""
	time_limit.stop()


func _resolve_world_parent() -> DotResult:
	if world_ref == null:
		# The session itself. A sensible default rather than a refusal: a single-map
		# game that never configured this still works, and the map ends up somewhere
		# findable rather than nowhere.
		return DotResult.success(self)

	if _world_node != null and is_instance_valid(_world_node):
		return DotResult.success(_world_node)

	var resolved := world_ref.resolve(self)

	if not resolved.ok:
		return resolved.wrap("Could not find where to put the map.")

	_world_node = resolved.value

	return DotResult.success(_world_node)


func describe() -> Dictionary:
	return {
		"map": String(current.id) if current != null else "-",
		"version": current.version if current != null else "-",
		"loaded": world != null,
		"changing": changing_now,
		"catalogue": catalogue.size() if catalogue != null else 0,
		"rotation": rotation.describe() if rotation != null else {},
		"time_limit": time_limit.describe(),
	}


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()

	out.append("map          %s" % (String(current.id) if current != null else "-"))
	out.append("version      %s" % (current.version if current != null else "-"))
	out.append("catalogue    %d maps" % (catalogue.size() if catalogue != null else 0))

	if rotation != null:
		var next := rotation.choose()
		out.append("next         %s" % (String(next.id) if next != null else "-"))

	out.append("time left    %s" % time_limit.formatted_remaining())
	out.append("rtv          %d" % time_limit.rtv_votes())

	return out
