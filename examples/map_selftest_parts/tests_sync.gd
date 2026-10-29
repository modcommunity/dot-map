extends "tests_change.gd"

## The sync host and client sections that need no download.

func _test_sync_a_local_map() -> void:
	_section("changing the map for everybody")

	var pair: SyncPair = await _make_pair(self, _catalogue(3), _catalogue(3))

	var seen: Array[String] = []
	pair.client.changed.connect(
		func(map: DotMapDef) -> void: seen.append(String(map.id))
	)
	pair.client.content_ready.connect(
		func(map: DotMapDef) -> void: seen.append("ready:" + String(map.id))
	)

	# The change is a coroutine that waits on the peer, and the peer only answers when
	# the pump runs — so the pump has to be running while the change is in flight.
	var changed := await _change_and_pump(pair, &"surf_0")

	_check(bool(changed["ok"]), "the host changes map", str(changed["reason"]))
	_check(
		pair.host_session.current != null
			and pair.host_session.current.id == &"surf_0",
		"and is on it"
	)

	_check(
		pair.client_session.current != null
			and pair.client_session.current.id == &"surf_0",
		"the client is on the same map (%s)" % [
			String(pair.client_session.current.id)
				if pair.client_session.current != null else "-"
		]
	)
	_check(
		pair.client_session.world != null,
		"with its world in the tree",
		"nothing in this addon used to tell a client a map had changed at all"
	)
	_check(
		seen.size() == 2 and seen[0] == "ready:surf_0" and seen[1] == "surf_0",
		"and reported ready before it loaded, not after (%s)" % [seen]
	)
	_check(pair.host.ready_count() == 1, "the host counted it as ready")

	# The ordering the whole protocol exists for: the host does not swap until the
	# peer can. A client on the old map while the host is on the new one is the state
	# a map change must never leave anybody in.
	var order: Array[String] = []
	pair.host_session.changed.connect(
		func(map: DotMapDef, _w: Node) -> void: order.append("host:" + String(map.id))
	)
	pair.client.content_ready.connect(
		func(map: DotMapDef) -> void: order.append("peer:" + String(map.id))
	)

	var second := await _change_and_pump(pair, &"surf_1")

	_check(bool(second["ok"]), "a second change works", str(second["reason"]))
	_check(
		order.size() == 2 and order[0] == "peer:surf_1" and order[1] == "host:surf_1",
		"and the peer had the map before the host swapped (%s)" % [order]
	)

	pair.host.queue_free()
	pair.client.queue_free()
	pair.host_session.queue_free()
	pair.client_session.queue_free()
	_done()


func _test_sync_refuses_what_a_host_may_not_send() -> void:
	_section("what a host may not tell a client to load")

	var client := DotMapSyncClient.new()
	var session := DotMapSession.new()
	add_child(session)
	await get_tree().process_frame
	session.catalogue = DotMapCatalogue.new()
	client.session = session
	add_child(client)

	var refused: Array[String] = []
	client.fetch_failed.connect(
		func(_map: DotMapDef, error: DotError) -> void:
			refused.append(error.message)
	)

	# A map this client does not have, that ships in a build rather than in a pack.
	# Accepting it would mean loading a path of the host's choosing out of THIS build.
	var local := _map(&"surf_evil")
	client.handle(DotMapMessage.announce(local))
	_check(
		refused.size() == 1,
		"a host may not send a map that is not delivered content",
		str(refused)
	)

	# Delivered, but with a scene outside its own mount — the addons directory.
	var escaping := _map(&"surf_escape")
	escaping.content_id = &"a_pack"
	escaping.scene_path = "res://addons/dot_map/plugin.cfg"
	client.handle(DotMapMessage.announce(escaping))
	_check(refused.size() == 2, "nor one whose scene is outside its own content")

	# The traversal that a plain begins_with() lets through. dot-cloud learned this
	# exact one with a version of "../..".
	var traversing := _map(&"surf_traverse")
	traversing.content_id = &"a_pack"
	traversing.scene_path = "res://dot_cloud/a_pack/1.0.0/../../../addons/x.tscn"
	client.handle(DotMapMessage.announce(traversing))
	_check(
		refused.size() == 3,
		"nor one that climbs out of it with .."
	)

	# The legitimate case, so the refusals above are not just "everything is refused".
	var delivered := _map(&"surf_delivered_ok")
	delivered.content_id = &"a_pack"
	delivered.scene_path = "res://dot_cloud/a_pack/1.0.0/map.tscn"
	client.handle(DotMapMessage.announce(delivered))
	_check(
		refused.size() == 3,
		"a properly delivered map is accepted (%s)" % [refused]
	)
	_check(
		client.announced != null and client.announced.id == &"surf_delivered_ok",
		"and becomes the announced map"
	)
	_check(
		session.catalogue.has(&"surf_delivered_ok"),
		"and is remembered, so the next announce is a catalogue hit"
	)

	# With accept_unknown_maps off, even a well-formed delivered map is refused.
	client.accept_unknown_maps = false
	var another := _map(&"surf_delivered_two")
	another.content_id = &"a_pack"
	another.scene_path = "res://dot_cloud/a_pack/1.0.0/two.tscn"
	client.handle(DotMapMessage.announce(another))
	_check(
		refused.size() == 4,
		"a client that ships all its maps can refuse to be sent anywhere else"
	)

	client.queue_free()
	session.queue_free()
	_done()


func _test_sync_waits_and_times_out() -> void:
	_section("a peer that never answers")

	var pair: SyncPair = await _make_pair(self, _catalogue(3), _catalogue(3))
	pair.host.sync_timeout_sec = 5.0
	pair.deaf = true

	var timed_out: Array[int] = []
	pair.host.peer_timed_out.connect(
		func(peer: int) -> void: timed_out.append(peer)
	)

	var changed := await _change_and_pump(pair, &"surf_2", 12.0)

	_check(
		timed_out.size() == 1 and timed_out[0] == 1,
		"the host reports the peer that never got there (%s)" % [timed_out]
	)
	_check(
		bool(changed["ok"]),
		"and changes anyway",
		"the players who did get the map should not be denied it by the one who "
		+ "did not"
	)
	_check(
		pair.host_session.current.id == &"surf_2",
		"so the host is on the new map"
	)
	_check(
		pair.client_session.current == null,
		"and the peer is on none, which is what its host will act on"
	)

	# The other policy, which a game that would rather stay put can ask for.
	pair.host.swap_without_stragglers = false
	var refused := await _change_and_pump(pair, &"surf_0", 12.0)

	_check(
		not bool(refused["ok"]),
		"with swap_without_stragglers off the change is refused instead",
		str(refused)
	)
	_check(
		pair.host_session.current.id == &"surf_2",
		"and the host stays on the map it was running (%s)"
			% String(pair.host_session.current.id)
	)

	pair.host.queue_free()
	pair.client.queue_free()
	pair.host_session.queue_free()
	pair.client_session.queue_free()
	_done()


## A peer that arrives between two changes has to be told to LOAD, not only which map. [method
## DotMapSyncHost.join_payload] is an announce, and a host sent `load` only at the end of a change — so a
## joiner fetched the map, said ready, and waited for ever.
func _test_sync_a_joiner_is_told_to_load() -> void:
	_section("a peer that joins between changes")

	var pair: SyncPair = await _make_pair(self, _catalogue(3), _catalogue(3))
	var first := await _change_and_pump(pair, &"surf_0")
	_check(bool(first["ok"]), "the first peer is on the map", str(first["reason"]))

	var joiner := await _add_peer_client(pair, 2, _catalogue(3))
	pair.host.admit_peer(2)
	await _pump_for(pair, 2.0, func() -> bool:
		return joiner.session.current != null)

	_check(
		joiner.session.current != null and joiner.session.current.id == &"surf_0",
		"a peer admitted between changes ends up on the host's map",
		"it said ready and nothing told it to load: %s" % [pair.sent_to(2)]
	)
	_check(
		pair.sent_to(2) == ["map.announce surf_0", "map.load surf_0"],
		"announced, then told to load once it said it had it (%s)" % [pair.sent_to(2)]
	)

	# The host that joins peers by hand, as every caller did before admit_peer existed.
	var by_hand := await _add_peer_client(pair, 3, _catalogue(3))
	pair.host.add_peer(3)
	pair.host.send_fn.call(3, pair.host.join_payload())
	await _pump_for(pair, 2.0, func() -> bool:
		return by_hand.session.current != null)
	_check(
		by_hand.session.current != null and by_hand.session.current.id == &"surf_0",
		"and so does one a host added and sent join_payload itself"
	)

	# Answered once. A second ready for the same map — a peer re-reporting, or a straggler
	# that was already sent the change's load — must not rebuild its world.
	pair.host.handle(2, DotMapMessage.ready(&"surf_0", "1.0.0"))
	pair.host.handle(1, DotMapMessage.ready(&"surf_0", "1.0.0"))
	await _pump(pair)
	_check(
		pair.sent_to(2).count("map.load surf_0") == 1
			and pair.sent_to(1).count("map.load surf_0") == 1,
		"and told to load once per map, not once per ready (%s / %s)"
			% [pair.sent_to(2), pair.sent_to(1)]
	)

	# And the next change is an ordinary one for all three.
	var next := await _change_and_pump(pair, &"surf_1")
	_check(
		bool(next["ok"]) and joiner.session.current.id == &"surf_1"
			and by_hand.session.current.id == &"surf_1"
			and pair.client_session.current.id == &"surf_1",
		"the joiners follow the next change with everybody else", str(next["reason"])
	)

	await _free_pair(pair)
	_done()


## A peer admitted mid-change is not part of that change. `add_peer` said so and `_wait_for_peers` did not
## agree: it counted every entry of `peers` on every poll, so a joiner was waited on for a map it had never
## been announced, the change was held to its timeout, and the joiner was reported as a straggler.
func _test_sync_a_joiner_mid_change() -> void:
	_section("a peer that joins during a change")

	var pair: SyncPair = await _make_pair(self, _catalogue(3), _catalogue(3))
	pair.host.sync_timeout_sec = 5.0
	var opening := await _change_and_pump(pair, &"surf_0")
	_check(bool(opening["ok"]), "the host is on a map", str(opening["reason"]))

	var timed_out: Array[int] = []
	pair.host.peer_timed_out.connect(func(peer: int) -> void: timed_out.append(peer))

	var joiner := await _add_peer_client(pair, 5, _catalogue(3))

	# Peer 4 has no client at all: a peer that would never answer. Peer 5 does.
	var mid_change := func() -> void:
		pair.host.add_peer(4)
		pair.host.admit_peer(5)

	var changed := await _change_and_pump(pair, &"surf_1", 12.0, mid_change)

	_check(bool(changed["ok"]), "the change goes ahead", str(changed["reason"]))
	_check(
		int(changed["ms"]) < 2500,
		"as soon as the peers it was announced to were ready, not at the timeout (%d ms)"
			% int(changed["ms"])
	)
	_check(timed_out.is_empty(), "and nobody who joined during it is called a straggler (%s)"
		% [timed_out])
	_check(
		pair.sent_to(4) == ["map.announce surf_1"],
		"a joiner is sent no part of the change it missed, then the map it settled on (%s)"
			% [pair.sent_to(4)]
	)

	await _pump_for(pair, 2.0, func() -> bool:
		return joiner.session.current != null)
	_check(
		joiner.session.current != null and joiner.session.current.id == &"surf_1",
		"and a joiner that answers ends up on it"
	)
	_check(pair.host.peers.has(4) and pair.host.peers.has(5), "both follow changes from now on")

	await _free_pair(pair)
	_done()


## One built-in scene reading a delivered document. The family's mount constraint — a pack's script cannot
## extend a class of the build it is mounted into — forces a game whose maps are data to keep the one scene
## that reads the data in its own build.
func _test_sync_template_trust() -> void:
	_section("a template scene reading delivered data")

	var session := DotMapSession.new()
	add_child(session)
	await get_tree().process_frame
	session.catalogue = DotMapCatalogue.new()

	var client := DotMapSyncClient.new()
	client.session = session
	client.send_fn = func(_p: Dictionary) -> void: pass
	add_child(client)

	var refused: Array[String] = []
	client.fetch_failed.connect(
		func(_map: DotMapDef, error: DotError) -> void:
			refused.append("%s | %s" % [error.message, error.detail])
	)

	var template := "res://fixtures/test_world.tscn"
	var templated := func(id: String) -> DotMapDef:
		var map := _map(StringName(id))
		map.content_id = &"data_pack"
		map.scene_path = template
		map.meta["manifest"] = "res://dot_cloud/data_pack/1.0.0/%s.json" % id
		return map

	client.handle(DotMapMessage.announce(templated.call("t_default")))
	_check(
		refused.size() == 1 and refused[0].contains("scene is outside"),
		"with no templates listed, a scene in the build is refused as before", str(refused)
	)

	client.trusted_template_scenes = PackedStringArray([template])
	client.handle(DotMapMessage.announce(templated.call("t_ok")))
	_check(refused.size() == 1, "a listed template with its data in the pack is accepted", str(refused))
	_check(
		client.announced != null and client.announced.id == &"t_ok"
			and session.catalogue.has(&"t_ok"),
		"and becomes the announced map, remembered"
	)

	# The same delivered map, republished: its own `version` unchanged, its pack's
	# `content_version` not. Compared nowhere, so the remembered (old) one was answered.
	var republished: DotMapDef = templated.call("t_ok")
	republished.content_version = "2.0.0"
	republished.meta["manifest"] = "res://dot_cloud/data_pack/2.0.0/t_ok.json"
	client.handle(DotMapMessage.announce(republished))
	_check(
		refused.size() == 1 and client.announced != null
			and client.announced.effective_content_version() == "2.0.0",
		"a remembered delivered map announced at another pack version is taken as announced",
		"%s %s" % [refused, client.announced.describe() if client.announced != null else "none"]
	)

	_test_template_refusals(client, refused, templated)

	client.queue_free()
	session.queue_free()
	await get_tree().process_frame
	_done()


func _test_template_refusals(client: DotMapSyncClient, refused: Array[String], templated: Callable) -> void:
	var outside: DotMapDef = templated.call("t_outside")
	outside.meta["manifest"] = "res://addons/dot_map/plugin.cfg"
	client.handle(DotMapMessage.announce(outside))
	_check(refused.size() == 2 and refused[1].contains("data is outside"),
		"its data may not be a file in this build", str(refused))

	var climbing: DotMapDef = templated.call("t_climb")
	climbing.meta["manifest"] = "res://dot_cloud/data_pack/1.0.0/../../other_pack/1.0.0/x.json"
	client.handle(DotMapMessage.announce(climbing))
	_check(refused.size() == 3, "nor another pack's, reached with ..", str(refused))

	var bare: DotMapDef = templated.call("t_bare")
	bare.meta.erase("manifest")
	client.handle(DotMapMessage.announce(bare))
	_check(refused.size() == 4 and refused[3].contains("no delivered data"),
		"a template with no data named is not a delivered map", str(refused))

	var stray: DotMapDef = templated.call("t_stray")
	stray.meta["extra"] = {"list": ["fine", "user://profile.json"]}
	client.handle(DotMapMessage.announce(stray))
	_check(refused.size() == 5 and refused[4].contains("meta.extra.list[1]"),
		"a path under a key nobody listed is held to the same rule, nested or not",
		str(refused))

	var local: DotMapDef = templated.call("t_local")
	local.content_id = &""
	client.handle(DotMapMessage.announce(local))
	_check(refused.size() == 6 and refused[5].contains("not delivered content"),
		"a template still has to name the content it reads from", str(refused))

	var escaping_version: DotMapDef = templated.call("t_version")
	escaping_version.content_version = ".."
	escaping_version.meta["manifest"] = "res://dot_cloud/other_pack/1.0.0/x.json"
	client.handle(DotMapMessage.announce(escaping_version))
	_check(refused.size() == 7 and refused[6].contains("plain id and version"),
		"and a version of .. cannot widen the mount to every pack", str(refused))

	var unlisted: DotMapDef = templated.call("t_unlisted")
	unlisted.scene_path = "res://examples/map_selftest.tscn"
	client.handle(DotMapMessage.announce(unlisted))
	_check(refused.size() == 8 and refused[7].contains("scene is outside"),
		"a scene that is not listed is refused however good its data", str(refused))


## [b]A refused load must leave nothing behind.[/b] `_on_load` adopted the catalogue's
## map as `announced` before checking the version the host asked for, so after refusing
## it, `announced` named the refused map.
func _test_sync_refused_load_adopts_nothing() -> void:
	_section("a load the client refuses")

	var session := DotMapSession.new()
	add_child(session)
	await get_tree().process_frame
	session.catalogue = _catalogue(3)

	var client := DotMapSyncClient.new()
	client.session = session
	client.send_fn = func(_p: Dictionary) -> void: pass
	add_child(client)

	client.handle(DotMapMessage.load_now(&"surf_0", "2.0.0"))
	await get_tree().process_frame
	_check(client.announced == null,
		"a load for a version this client does not have adopts nothing (%s)"
			% [String(client.announced.id) if client.announced != null else "-"])
	_check(session.current == null, "and loads nothing")

	client.handle(DotMapMessage.load_now(&"surf_0", "1.0.0"))
	for _i in range(5):
		await get_tree().process_frame
	_check(
		session.current != null and session.current.id == &"surf_0"
			and client.announced != null and client.announced.id == &"surf_0",
		"while the right version is loaded and adopted"
	)

	client.queue_free()
	session.queue_free()
	await get_tree().process_frame
	_done()


## [b]Progress is throttled on the way out; ready is not.[/b] One message per dot-cloud
## progress signal, into a server that rate-limits a client and drops the excess without
## choosing, can cost the ready that follows it.
func _test_sync_progress_is_throttled() -> void:
	_section("progress is throttled, ready is not")

	var session := DotMapSession.new()
	add_child(session)
	await get_tree().process_frame
	session.catalogue = _catalogue(3)

	var sent: Array[String] = []
	var client := DotMapSyncClient.new()
	client.session = session
	client.send_fn = func(p: Dictionary) -> void:
		sent.append("%s %.2f" % [DotMapMessage.kind_of(p), float(p.get("fraction", -1.0))])
	add_child(client)

	var local_signals: Array[float] = []
	client.fetch_progress.connect(func(f: float) -> void: local_signals.append(f))

	client.handle(DotMapMessage.announce(session.catalogue.get_map(&"surf_0")))
	sent.clear()

	for i in range(50):
		client.report_progress(float(i) / 50.0)
	var burst := sent.filter(func(line: String) -> bool: return line.begins_with("map.progress"))
	_check(burst.size() == 1,
		"fifty progress reports in a burst send one (%d)" % burst.size())
	_check(local_signals.size() == 50, "while the local signal hears every one")

	client.report_progress(1.0)
	_check(sent.back() == "map.progress 1.00", "a report of 1.0 is never held back (%s)" % [sent.back()])

	client.handle(DotMapMessage.announce(session.catalogue.get_map(&"surf_1")))
	_check(sent.back().begins_with("map.ready"), "and neither is a ready (%s)" % [sent.back()])

	await get_tree().create_timer(client.progress_interval_sec + 0.05).timeout
	client.report_progress(0.5)
	_check(sent.back() == "map.progress 0.50", "the next report after the interval goes")

	client.progress_interval_sec = 0.0
	sent.clear()
	for i in range(5):
		client.report_progress(0.1 * i)
	_check(sent.size() == 5, "and an interval of 0 sends every one (%d)" % sent.size())

	client.queue_free()
	session.queue_free()
	await get_tree().process_frame
	_done()
