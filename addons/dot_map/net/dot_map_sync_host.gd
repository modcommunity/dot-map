@tool
class_name DotMapSyncHost
extends Node

## Changes the map for everybody, not only this process: announce, wait for each peer's download, swap, then tell all to load.
## Transport-agnostic: set [member send_fn] to anything that puts a [Dictionary] in front of one peer.
## A peer joining between changes is announced the map and told to load it once; one joining during a change is not part of it.

const CHANNEL := "map.sync"

## Where a change is.
enum Phase {
	IDLE,
	## Peers have been told to fetch and are being waited for.
	SYNCING,
	## Everyone is ready; the world is being replaced.
	SWAPPING,
}

## A peer reported how far through the fetch it is. For a HUD or a console listing.
signal peer_progress(peer_id: int, fraction: float)

## Readiness during a change, for a progress display.
signal sync_progress(ready_count: int, total: int)

## A peer did not get the content in time. The host decides what to do about it. This addon does not
## disconnect anybody — it has no transport and no session list, and a game may perfectly well want to leave
## a slow client downloading. Connect [member on_timeout_fn] or this signal to whatever does the dropping.
signal peer_timed_out(peer_id: int)

## The map is live here and every peer has been told to show it.
signal change_finished(map: DotMapDef)

## The change was abandoned. The session is still on the map it was running.
signal change_failed(map: DotMapDef, reason: String)

@export_group("Wiring")

## The session this drives. Required.
@export var session_ref: DotNodeRef = null

@export_group("Waiting")

## Seconds to wait for every peer to have the new map's content. Generous, because it covers a download.
## Shorter than dot-server's equivalent because a map is one world, not a whole game.
@export_range(5.0, 3600.0, 5.0) var sync_timeout_sec: float = 300.0

## Swap as soon as everyone is ready rather than waiting out the timeout.
@export var swap_when_all_ready: bool = true

## Change the map even though some peers never got the content. On, and the reason is the one dot-server
## gives: the players who did get the map should not be denied the change by the ones who could not. Off
## holds the whole server on the current map for one client with a bad connection.
@export var swap_without_stragglers: bool = true

## Seconds between polls of the readiness set. Not a frame: a map change is a once-every-few-minutes event
## and a peer answering 200 ms later than it might costs nothing anybody can perceive.
@export_range(0.05, 2.0, 0.05) var poll_interval_sec: float = 0.25

## The session this drives, assigned directly when there is no [member session_ref].
var session: DotMapSession = null

## Sends one payload to one peer. Set by the host. One peer, never a broadcast address. A [code]send(payload,
## 0)[/code] convention is how this family last shipped a private per-player message to every client at once,
## and the peer that caused it was a bot registered with id 0.
var send_fn: Callable = Callable()

## Called with a peer id that ran out of time. Optional; the signal carries the same.
var on_timeout_fn: Callable = Callable()

var phase: Phase = Phase.IDLE

## Peers expected to follow a map change, in the order they were added.
var peers: PackedInt64Array = PackedInt64Array()

## The peers the change in flight was announced to, fixed when it began. Snapshotted, not read live. The wait
## counted [member peers] on every poll, so a peer admitted mid-change was waited on for a map it had never
## been announced — which held the change to its timeout and then reported the joiner as a straggler.
var _participants: PackedInt64Array = PackedInt64Array()
## Peers added while a change was in flight, announced the current map once it settles.
var _joined_mid_change: PackedInt64Array = PackedInt64Array()
## peer_id -> "id@version" the peer was last told to load. So a ready is answered once.
var _told_to_load: Dictionary = {}

var _pending: DotMapDef = null
## peer_id -> "id@version" the peer last said it had.
var _ready_keys: Dictionary = {}
## peer_id -> 0..1
var _progress: Dictionary = {}
var _deadline_ms: int = 0


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	if session == null and session_ref != null:
		var resolved := session_ref.resolve(self)
		if resolved.ok:
			session = resolved.value as DotMapSession


## Registers a peer that must follow map changes. Sends nothing on its own; [method admit_peer] is the one-
## call join. A peer added while a change is in flight is not waited on by it (see [member _participants])
## and is announced the current map once that change settles, whoever added it.
func add_peer(peer_id: int) -> void:
	if peers.has(peer_id):
		return
	peers.append(peer_id)

	if phase != Phase.IDLE:
		_joined_mid_change.append(peer_id)
		DotLog.debug(CHANNEL, "peer joined during a change; it follows once it settles", {
			"peer": peer_id
		})


## Registers a peer and tells it the map the host is on. Announced now when no change is running, and once
## the change settles when one is. The [code]load[/code] follows the peer's [code]ready[/code] — see the
## class note — so a joiner goes through the same fetch, and the same trust rules, as everybody else.
func admit_peer(peer_id: int) -> void:
	if peers.has(peer_id):
		return
	add_peer(peer_id)
	if phase == Phase.IDLE:
		_announce_current_to(peer_id)


func remove_peer(peer_id: int) -> void:
	var index := peers.find(peer_id)
	if index >= 0:
		peers.remove_at(index)
	index = _joined_mid_change.find(peer_id)
	if index >= 0:
		_joined_mid_change.remove_at(index)
	_ready_keys.erase(peer_id)
	_progress.erase(peer_id)
	_told_to_load.erase(peer_id)


## What a joining peer should be told, or an empty dictionary when there is no map. A peer admitted mid-
## session needs the same announce everybody else got. Without it a client joins into a host that is on its
## fourth map and is never told which one — the announce it needed happened before it existed.
func join_payload() -> Dictionary:
	if session == null or session.current == null:
		return {}
	return DotMapMessage.announce(session.current)


## Changes the map for the host and every peer. Returns when the new map is live here and every peer has been
## told to show it, or with a failure that leaves the current map running.
func change_to(id: StringName) -> DotResult:
	if session == null:
		return DotResult.fail(DotError.CODE_STATE, "No map session.")

	if session.catalogue == null:
		return DotResult.fail(DotError.CODE_STATE, "No catalogue has been loaded.")

	var map := session.catalogue.get_map(id)

	if map == null:
		return DotResult.fail(
			DotError.CODE_IO, "No such map in the catalogue.", String(id)
		)

	return await change_to_map(map)


## Changes to the next map the session's rotation offers.
func change_to_next(players: int = 0) -> DotResult:
	if session == null or session.rotation == null:
		return DotResult.fail(DotError.CODE_STATE, "No rotation.")

	var next := session.rotation.choose(players)

	if next == null:
		return DotResult.fail(
			DotError.CODE_STATE, "The rotation has nothing to offer."
		)

	return await change_to_map(next)


## Refuses a change that cannot start (no session, a change running, an invalid map); otherwise records it and counts the peers it waits on.
func _begin_change(map: DotMapDef) -> DotResult:
	if session == null:
		return DotResult.fail(DotError.CODE_STATE, "No map session.")

	if map == null:
		return DotResult.fail(DotError.CODE_INVALID, "No map.")

	if phase != Phase.IDLE:
		# Refused rather than queued, for the reason DotMapSession gives about two
		# overlapping changes: the second one's await resumes into a world the first
		# has already rebuilt.
		return DotResult.fail(
			DotError.CODE_STATE,
			"A map change is already in progress.",
			String(_pending.id) if _pending != null else ""
		)

	var valid := map.validate()

	if not valid.ok:
		return valid

	_pending = map
	_ready_keys.clear()
	_progress.clear()
	_participants = peers.duplicate()

	DotLog.info(CHANNEL, "changing map", {
		"to": String(map.id), "version": map.version, "peers": peers.size()
	})
	return DotResult.success()


## Announces, waits for the peers, swaps the host's own world, then tells everyone to load.
func change_to_map(map: DotMapDef) -> DotResult:
	var begun := _begin_change(map)
	if not begun.ok:
		return begun

	# Announced before any fetch: the peers have the furthest to go, so the host's own fetch
	# overlaps theirs. A map is only a world, unlike a game change, so a host that then fails
	# costs the peers a download they reuse when the map comes round.
	_broadcast(DotMapMessage.announce(map))

	if not _participants.is_empty():
		var proceed: bool = await _wait_for_peers(map)

		if not proceed:
			# `swap_without_stragglers` is off and somebody did not make it. Nothing has been torn down, so this is a
			# change that did not happen rather than a half-done one — the same property [method
			# DotMapSession.change_to_map] gets from loading before it frees.
			var why := "Not every peer could get the map in time."
			_broadcast(DotMapMessage.abort(map.id, why))
			_settle()
			change_failed.emit(map, why)
			return DotResult.fail(DotError.CODE_TIMEOUT, why, String(map.id))

	phase = Phase.SWAPPING

	var changed: DotResult = await session.change_to_map(map)

	if not changed.ok:
		_broadcast(DotMapMessage.abort(map.id, changed.error.message))
		_settle()
		change_failed.emit(map, changed.error.message)
		return changed

	# Only now. A peer told to show a map the host then failed to load is a peer in a
	# world the host is not in — which is the failure the session's own load-before-
	# teardown ordering exists to prevent, undone from the other end.
	var key := _key_of(map)
	for peer in _live_participants():
		_told_to_load[int(peer)] = key
	_broadcast(DotMapMessage.load_now(map.id, map.version))

	_settle()

	change_finished.emit(map)

	return changed


## Waits for every peer to report the new map. Returns whether to go ahead. The return value is the point.
func _wait_for_peers(map: DotMapDef) -> bool:
	phase = Phase.SYNCING
	_deadline_ms = Time.get_ticks_msec() + int(sync_timeout_sec * 1000.0)

	var wanted := _key_of(map)

	while true:
		await get_tree().create_timer(poll_interval_sec).timeout

		if not is_inside_tree():
			return false

		# The peers this change was announced to and that are still here: one that left
		# is not waited for, and one that joined since was never told.
		var waiting_on := _live_participants()
		var ready_count := 0

		for peer in waiting_on:
			if str(_ready_keys.get(peer, "")) == wanted:
				ready_count += 1

		sync_progress.emit(ready_count, waiting_on.size())

		if ready_count >= waiting_on.size() and swap_when_all_ready:
			DotLog.info(CHANNEL, "all peers have the map", {"peers": ready_count})
			return true

		if Time.get_ticks_msec() >= _deadline_ms:
			var stragglers := PackedInt64Array()

			for peer in waiting_on:
				if str(_ready_keys.get(peer, "")) != wanted:
					stragglers.append(peer)

			DotLog.warn(CHANNEL, "map content sync timed out", {
				"ready": ready_count, "waiting": stragglers.size()
			})

			for peer in stragglers:
				peer_timed_out.emit(peer)
				if on_timeout_fn.is_valid():
					on_timeout_fn.call(int(peer))

			return swap_without_stragglers

	# Unreachable; GDScript wants every path to return a bool.
	return false


## Feeds one payload from one peer in. Returns whether it was a map message. A host sharing a channel with
## its own traffic uses that to decide whether to keep looking.
func handle(peer_id: int, payload: Dictionary) -> bool:
	if not DotMapMessage.is_map_message(payload):
		return false

	match DotMapMessage.kind_of(payload):
		DotMapMessage.KIND_READY:
			var key := "%s@%s" % [
				str(payload.get("map", "")), str(payload.get("version", ""))
			]
			_ready_keys[peer_id] = key
			_progress[peer_id] = 1.0
			DotLog.debug(CHANNEL, "peer is ready", {"peer": peer_id, "map": key})
			_load_if_joining(peer_id, key)
			return true

		DotMapMessage.KIND_PROGRESS:
			var fraction := clampf(float(payload.get("fraction", 0.0)), 0.0, 1.0)
			_progress[peer_id] = fraction
			peer_progress.emit(peer_id, fraction)
			return true

	# An announce or a load arriving here is a peer talking like a host. Reported
	# rather than acted on: it is either a wiring mistake or a client trying to change
	# everybody's map, and both are worth seeing in a log.
	DotLog.warn(CHANNEL, "a peer sent a host-only message", {
		"peer": peer_id, "kind": String(DotMapMessage.kind_of(payload))
	})
	return true


## Answers a peer that has the map the host is on, between changes, with a load. This is the half of a join
## that was missing.
func _load_if_joining(peer_id: int, key: String) -> void:
	if phase != Phase.IDLE or session == null or session.current == null:
		return                                # a change's own load is on its way
	if not peers.has(peer_id):
		return
	var current := session.current
	if key != _key_of(current) or str(_told_to_load.get(peer_id, "")) == key:
		return

	_told_to_load[peer_id] = key
	DotLog.debug(CHANNEL, "a joining peer has the map; telling it to load", {
		"peer": peer_id, "map": key
	})
	_send_to(peer_id, DotMapMessage.load_now(current.id, current.version))


## A change finished or was abandoned: back to idle, and announce to the joiners. Whichever way it ended. An
## abandoned change leaves the host on the map it was running, and a peer that joined during it still needs
## to be told that one.
func _settle() -> void:
	phase = Phase.IDLE
	_pending = null
	_participants = PackedInt64Array()

	var joined := _joined_mid_change
	_joined_mid_change = PackedInt64Array()

	for peer in joined:
		if peers.has(peer):
			_announce_current_to(int(peer))


func _announce_current_to(peer_id: int) -> void:
	var join := join_payload()
	if join.is_empty():
		return                                # no map yet; the first change tells everybody
	_send_to(peer_id, join)


## The peers this change was announced to that have not left since.
func _live_participants() -> PackedInt64Array:
	var out := PackedInt64Array()
	for peer in _participants:
		if peers.has(peer):
			out.append(peer)
	return out


## Sends a change's message to the peers taking part in it — not to every peer. A peer admitted after the
## announce went out has not been told this map, so its [code]load[/code] or [code]abort[/code] means nothing
## to it; it gets the post-change join instead (see [method _settle]).
func _broadcast(payload: Dictionary) -> void:
	if not send_fn.is_valid():
		DotLog.warn(CHANNEL, "no send_fn; peers will not hear about this change")
		return

	for peer in _live_participants():
		send_fn.call(int(peer), payload)


func _send_to(peer_id: int, payload: Dictionary) -> void:
	if not send_fn.is_valid():
		DotLog.warn(CHANNEL, "no send_fn; a joining peer will not hear which map this is")
		return
	send_fn.call(peer_id, payload)


static func _key_of(map: DotMapDef) -> String:
	return "%s@%s" % [String(map.id), map.version]


## How far a peer is through its fetch, 0..1.
func progress_of(peer_id: int) -> float:
	return float(_progress.get(peer_id, 0.0))


## Whether a peer has the map currently being changed to.
func is_peer_ready(peer_id: int) -> bool:
	if _pending == null:
		return true
	return str(_ready_keys.get(peer_id, "")) == _key_of(_pending)


func ready_count() -> int:
	if _pending == null:
		return peers.size()

	var wanted := _key_of(_pending)
	var count := 0

	for peer in _live_participants():
		if str(_ready_keys.get(peer, "")) == wanted:
			count += 1

	return count


func describe() -> Dictionary:
	return {
		"phase": Phase.keys()[phase].to_lower(),
		"pending": String(_pending.id) if _pending != null else "-",
		"peers": peers.size(),
		"ready": ready_count(),
	}


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()

	out.append("phase     %s" % Phase.keys()[phase].to_lower())
	out.append("map       %s" % (
		String(session.current.id) if session != null and session.current != null
		else "-"
	))
	out.append("pending   %s" % (String(_pending.id) if _pending != null else "-"))
	out.append("peers     %d ready of %d" % [
		ready_count(), _live_participants().size() if _pending != null else peers.size()
	])

	if phase == Phase.SYNCING:
		for peer in _live_participants():
			if not is_peer_ready(int(peer)):
				out.append("  waiting %d  %d%%" % [
					peer, int(progress_of(int(peer)) * 100.0)
				])

	return out
