extends "tests_defs.gd"

## Changing maps, and the host and client pair every sync section builds.

## Stands in for a dot-server DotServer: the signal and the question
## [method DotMapSession.follow_hibernation] duck-types.
class FakeHibernatingServer extends Node:
	signal hibernation_changed(hibernating: bool)

	var asleep := false

	func is_hibernating() -> bool:
		return asleep

	func sleep(on: bool) -> void:
		asleep = on
		hibernation_changed.emit(on)


func _test_change_maps() -> void:
	_section("changing maps")

	var session := DotMapSession.new()
	add_child(session)
	await get_tree().process_frame

	session.catalogue = _catalogue(3)
	session.rotation = DotMapRotation.of(session.catalogue)

	var announced: Array[String] = []
	session.changing.connect(
		func(_from: DotMapDef, to: DotMapDef) -> void:
			announced.append("changing:" + (String(to.id) if to else "-"))
	)
	session.changed.connect(
		func(map: DotMapDef, _world: Node) -> void:
			announced.append("changed:" + String(map.id))
	)

	var loaded: DotResult = await session.change_to(&"surf_0")

	_check(loaded.ok, "a map loads", loaded.error.message if not loaded.ok else "")
	_check(session.current != null and session.current.id == &"surf_0", "and is current")
	_check(session.world != null, "and its world is in the tree")
	_check(
		session.world != null and session.world.get_parent() == session,
		"under the configured parent"
	)

	# The order is the point: announced before the teardown, so a timer can abandon
	# its runs while the old world still exists.
	_check(
		announced.size() == 2 and announced[0].begins_with("changing"),
		"the change is announced before it happens",
		str(announced)
	)

	var first_world := session.world

	var second: DotResult = await session.change_to(&"surf_1")

	_check(second.ok, "a second map loads")
	_check(
		not is_instance_valid(first_world),
		"and the first world is freed rather than left in the tree"
	)
	_check(session.world != first_world, "and replaced")

	_check(
		not (await session.change_to(&"nothing_here")).ok,
		"an unknown map id is refused"
	)
	_check(
		session.current.id == &"surf_1",
		"and the session stays on the map it was running"
	)

	_test_map_clock(session)

	session.unload()
	_check(session.world == null and session.current == null, "and can be unloaded")

	session.queue_free()
	_done()


func _test_map_clock(session: DotMapSession) -> void:
	# The clock restarts on every map, and the session reports the map being over
	# rather than changing it — what happens then is a game's decision.
	_check(session.time_limit.running, "the map clock is running")

	var over := PackedStringArray()
	session.map_over.connect(
		func(_map: DotMapDef, reason: StringName) -> void:
			over.append(String(reason))
	)

	# A hibernating server's map clock waits, and starts again from the map's own limit
	# when somebody joins. Followed through the duck-typed signal a DotServer emits.
	_check(session.restart_on_wake, "waking starts the map's clock again by default")
	var server := FakeHibernatingServer.new()
	add_child(server)
	_check(session.follow_hibernation(server), "a server's hibernation can be followed")

	for _i in range(30):
		session.advance(1.0)

	session.rock_the_vote(&"p1", 10)
	var left := session.time_limit.remaining
	server.sleep(true)

	for _i in range(100000):
		session.advance(1.0)

	_check(
		is_equal_approx(session.time_limit.remaining, left) and over.is_empty(),
		"a day asleep does not move the map's clock (%.0f left, was %.0f)" % [session.time_limit.remaining, left]
	)

	server.sleep(false)
	_check(
		is_equal_approx(session.time_limit.remaining, session.time_limit.duration),
		"and waking starts it again at the map's limit (%.0f of %.0f)" % [session.time_limit.remaining, session.time_limit.duration]
	)
	_check(session.time_limit.rtv_votes() == 0, "with nobody's rock-the-vote carried over")
	server.queue_free()

	for _i in range(int(session.time_limit.remaining) + 2):
		session.advance(1.0)

	_check(over.size() == 1, "and the map ends exactly once", str(over))
	_check(
		session.current != null,
		"with the session still on it — ending a map is not changing it"
	)


func _test_change_survives_a_failure() -> void:
	_section("a failed change leaves the server on a working map")

	# The property a live server rests on, and the reason the new scene is loaded
	# BEFORE the old one is freed. Freeing first is simpler, uses less memory, and
	# turns a bad download into a server with no map and no way back.
	var session := DotMapSession.new()
	add_child(session)
	await get_tree().process_frame

	session.catalogue = _catalogue(2)
	session.rotation = DotMapRotation.of(session.catalogue)

	await session.change_to(&"surf_0")

	var working := session.world
	_check(working != null, "a map is running")

	var broken := _map(&"surf_broken")
	broken.scene_path = "res://examples/does_not_exist.tscn"
	session.catalogue.add(broken)

	var failures := PackedStringArray()
	session.change_failed.connect(
		func(_map: DotMapDef, reason: String) -> void: failures.append(reason)
	)

	var result: DotResult = await session.change_to(&"surf_broken")

	_check(not result.ok, "a map whose scene is missing fails to load")
	_check(failures.size() == 1, "and the failure is announced", str(failures))
	_check(
		session.current != null and session.current.id == &"surf_0",
		"the session is still on the working map"
	)
	_check(
		session.world == working and is_instance_valid(working),
		"and its world was never torn down"
	)

	# And it can still change afterwards, so the failure left nothing latched.
	var recovered: DotResult = await session.change_to(&"surf_1")
	_check(recovered.ok, "and a later change still works")
	_check(not session.changing_now, "with nothing left latched")

	session.queue_free()
	_done()


func _test_loader_without_cloud() -> void:
	_section("the loader without dot-cloud")

	var loader := DotMapLoader.new()
	var delivered := _map(&"surf_delivered")
	delivered.content_id = &"a_pack"

	# No cloud client registered. The permissive default treats it as "this map
	# ships in the build" — which is a legitimate configuration and is also exactly
	# what a cloud client that failed to register looks like.
	var permissive: DotResult = await loader.ensure_content(delivered)
	_check(permissive.ok, "with no cloud client the loader falls back to the disk")

	loader.require_cloud = true
	var strict: DotResult = await loader.ensure_content(delivered)

	_check(
		not strict.ok,
		"and require_cloud turns that ambiguity into a loud failure"
	)
	_check(
		strict.ok or strict.code() == DotError.CODE_STATE,
		"reported as a state error rather than as a missing file"
	)

	_check(
		loader.is_ready(_map(&"local")),
		"a local map whose scene exists is ready"
	)
	_done()



## A loopback pair: whatever the host sends, the client handles, and back. Not a mock.
class SyncPair:
	extends RefCounted

	var host: DotMapSyncHost = null
	var client: DotMapSyncClient = null
	var host_session: DotMapSession = null
	var client_session: DotMapSession = null

	## Payloads held back instead of delivered, so a straggler can be simulated.
	var deaf: bool = false

	var to_client: Array[Dictionary] = []
	var to_host: Array[Dictionary] = []

	## Peers other than 1: peer -> DotMapSyncClient. A peer with no entry never answers.
	var others: Dictionary = {}
	var other_sessions: Array[DotMapSession] = []
	## [peer, payload] in flight to and from those peers.
	var to_others: Array = []
	var from_others: Array = []
	## Every message the host sent, as "peer kind map", in order.
	var sent: Array[String] = []

	## The messages the host sent one peer, as "kind map".
	func sent_to(peer: int) -> Array[String]:
		var out: Array[String] = []
		for line in sent:
			var parts := line.split(" ")
			if int(parts[0]) == peer:
				out.append("%s %s" % [parts[1], parts[2]])
		return out


func _make_pair(
	parent: Node,
	host_catalogue: DotMapCatalogue,
	client_catalogue: DotMapCatalogue
) -> SyncPair:
	var pair := SyncPair.new()

	pair.host_session = DotMapSession.new()
	pair.host_session.name = "HostSession"
	parent.add_child(pair.host_session)

	pair.client_session = DotMapSession.new()
	pair.client_session.name = "ClientSession"
	parent.add_child(pair.client_session)

	await parent.get_tree().process_frame

	pair.host_session.catalogue = host_catalogue
	pair.host_session.rotation = DotMapRotation.of(host_catalogue)
	pair.client_session.catalogue = client_catalogue

	pair.host = DotMapSyncHost.new()
	pair.host.session = pair.host_session
	pair.host.poll_interval_sec = 0.05
	parent.add_child(pair.host)

	pair.client = DotMapSyncClient.new()
	pair.client.session = pair.client_session
	parent.add_child(pair.client)

	# The loopback. Delivered on the next frame rather than inline: a receive path that
	# re-enters the sender is not what a socket does, and a protocol that only works
	# when it does is one that will not survive contact with one.
	pair.host.send_fn = func(peer: int, payload: Dictionary) -> void:
		var named: Variant = payload.get("map", "")
		var map_id := str((named as Dictionary).get("id", "")) if named is Dictionary else str(named)
		pair.sent.append("%d %s %s" % [peer, DotMapMessage.kind_of(payload), map_id])
		if peer == 1:
			pair.to_client.append(payload)
		else:
			pair.to_others.append([peer, payload])

	pair.client.send_fn = func(payload: Dictionary) -> void:
		pair.to_host.append(payload)

	pair.host.add_peer(1)

	return pair


## Drains both directions until nothing more is in flight. Called from a poll loop rather than driven by a
## timer, because the host waits on [method SceneTree.create_timer] and the pump has to run while it does.
func _pump(pair: SyncPair) -> void:
	while not pair.to_client.is_empty() or not pair.to_host.is_empty() \
			or not pair.to_others.is_empty() or not pair.from_others.is_empty():
		var for_client := pair.to_client.duplicate()
		var for_host := pair.to_host.duplicate()
		var for_others := pair.to_others.duplicate()
		var from_others := pair.from_others.duplicate()
		pair.to_client.clear()
		pair.to_host.clear()
		pair.to_others.clear()
		pair.from_others.clear()

		for payload in for_client:
			if not pair.deaf:
				pair.client.handle(payload)

		for payload in for_host:
			pair.host.handle(1, payload)

		for item in for_others:
			var other: DotMapSyncClient = pair.others.get(int(item[0]))
			if other != null:
				other.handle(item[1])

		for item in from_others:
			pair.host.handle(int(item[0]), item[1])

		await get_tree().process_frame


## A second (third, ...) peer with its own session, answering through the pair's pump.
func _add_peer_client(pair: SyncPair, peer: int, catalogue: DotMapCatalogue) -> DotMapSyncClient:
	var session := DotMapSession.new()
	session.name = "PeerSession%d" % peer
	add_child(session)
	await get_tree().process_frame
	session.catalogue = catalogue
	pair.other_sessions.append(session)

	var client := DotMapSyncClient.new()
	client.name = "PeerClient%d" % peer
	client.session = session
	add_child(client)
	client.send_fn = func(payload: Dictionary) -> void:
		pair.from_others.append([peer, payload])
	pair.others[peer] = client
	return client


## Pumps for [param seconds], for a peer that answers on its own time.
func _pump_for(pair: SyncPair, seconds: float, until: Callable = Callable()) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if until.is_valid() and bool(until.call()):
			break
		await _pump(pair)
		await get_tree().process_frame
	await _pump(pair)


func _free_pair(pair: SyncPair) -> void:
	for client in pair.others.values():
		(client as Node).queue_free()
	for session in pair.other_sessions:
		session.queue_free()
	pair.host.queue_free()
	pair.client.queue_free()
	pair.host_session.queue_free()
	pair.client_session.queue_free()
	await get_tree().process_frame


## Runs a change to completion while pumping the loopback. The GDScript fan-out trap, in its third form.
func _change_and_pump(
	pair: SyncPair, id: StringName, seconds: float = 10.0, during: Callable = Callable()
) -> Dictionary:
	var outcome := {"done": false, "ok": false, "reason": "", "ms": 0}
	var started := Time.get_ticks_msec()

	var on_finished := func(_map: DotMapDef) -> void:
		outcome["done"] = true
		outcome["ok"] = true
		outcome["ms"] = Time.get_ticks_msec() - started
	var on_failed := func(_map: DotMapDef, reason: String) -> void:
		outcome["done"] = true
		outcome["reason"] = reason
		outcome["ms"] = Time.get_ticks_msec() - started

	pair.host.change_finished.connect(on_finished)
	pair.host.change_failed.connect(on_failed)

	pair.host.change_to(id)

	# While the host is waiting on its peers: the moment a joiner arrives mid-change.
	if during.is_valid():
		await during.call()

	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)

	while Time.get_ticks_msec() < deadline and not bool(outcome["done"]):
		await _pump(pair)
		await get_tree().process_frame

	# Drained once more so the load the host broadcast on its way out is delivered.
	await _pump(pair)

	pair.host.change_finished.disconnect(on_finished)
	pair.host.change_failed.disconnect(on_failed)

	return outcome
