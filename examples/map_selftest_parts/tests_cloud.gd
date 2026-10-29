extends "tests_sync.gd"

## Delivered maps, workshop maps and the commands sections.

## The whole point of "maps are content", run end to end. dot-cloud is loaded by path, not named. This addon
## must compile in a project that does not have it — that is why [DotMapLoader] duck-types through
## [DotRegistry] — and a `class_name` in this file would take the whole suite down with it.
func _test_sync_a_delivered_map() -> void:
	_section("a map the peer has to download")

	var client_script: Variant = load(
		"res://addons/dot_cloud/client/dot_cloud_client.gd"
	)

	if client_script == null:
		# A legitimate configuration: dot-cloud is optional and the symlink is
		# gitignored. Said out loud rather than skipped silently, because "0 failures"
		# from a suite that quietly ran nothing is how this family got here.
		_check(false, "dot-cloud is present so the delivered path can be run",
			"addons/dot_cloud is not linked; the interface below is NOT covered")
		return

	var data := "user://dot_map_delivered_test"
	DotPaths.remove_tree(data)

	var pair_keys := _publish_delivered_pack(data)
	if pair_keys.is_empty():
		return

	var cloud: Node = await _add_cloud(client_script, data, pair_keys)

	# The interface, asserted directly. Cheaper than a socket and it is what was
	# missing: reading the two sides side by side is the whole check.
	_check(
		cloud.has_method("ensure") and cloud.has_method("is_mounted"),
		"the cloud client speaks the interface DotMapLoader calls",
		"ensure/is_mounted — it offered acquire/is_ready and nothing noticed"
	)

	var delivered := DotMapDef.new()
	delivered.id = &"surf_pack_map"
	delivered.version = "1.0.0"
	delivered.content_id = &"surf_pack"
	delivered.scene_path = "res://dot_cloud/surf_pack/1.0.0/world.tscn"

	var host_catalogue := DotMapCatalogue.new()
	host_catalogue.add(delivered)

	# The client's catalogue is EMPTY, which is the realistic case: a records server
	# carries two hundred maps and a client ships none of them. Everything the client
	# knows about this map, it learns from the announce.
	var pair: SyncPair = await _make_pair(self, host_catalogue, DotMapCatalogue.new())

	var loader := pair.client_session.loader
	_check(loader != null and not loader.is_ready(delivered), "the peer does not have the map yet")

	var fetched: Array[String] = []
	pair.client.fetching.connect(
		func(map: DotMapDef) -> void: fetched.append(String(map.id))
	)
	var failures: Array[String] = []
	pair.client.fetch_failed.connect(
		func(_map: DotMapDef, error: DotError) -> void:
			failures.append(error.message)
	)

	var host_progress: Array[float] = []
	pair.host.peer_progress.connect(
		func(_peer: int, fraction: float) -> void: host_progress.append(fraction)
	)

	var changed := await _change_and_pump(pair, &"surf_pack_map", 20.0)

	_check_delivered_pair(cloud, pair, host_progress, fetched, failures, changed)

	pair.host.queue_free()
	pair.client.queue_free()
	pair.host_session.queue_free()
	pair.client_session.queue_free()
	cloud.queue_free()
	await get_tree().process_frame
	DotPaths.remove_tree(data)
	_done()


## Writes and signs a one-map pack under [param data]; returns its key pair, or empty when a step failed.
func _publish_delivered_pack(data: String) -> Dictionary:
	var source := data.path_join("src")
	var out := "%s/dist/%s/%s" % [data, "surf_pack", "1.0.0"]

	var scene := (
		"[gd_scene format=3]\n\n"
		+ "[node name=\"DeliveredMap\" type=\"Node\"]\n"
	)
	var written := DotPaths.write_text(source.path_join("world.tscn"), scene)
	_check(written.ok, "a map scene is written to publish")

	var signature: Variant = load(
		"res://addons/dot_cloud/verify/dot_cloud_signature.gd"
	)
	var keys: DotResult = signature.generate_keypair()
	_check(keys.ok, "a signing key pair is generated")

	if not keys.ok:
		return {}

	var pair_keys: Dictionary = keys.value

	var publisher_script: Variant = load(
		"res://addons/dot_cloud/publish/dot_cloud_publisher.gd"
	)
	var publisher: Variant = publisher_script.new()
	publisher.content_id = "surf_pack"
	publisher.version = "1.0.0"
	publisher.entry_scene = "world.tscn"
	publisher.signing_key_pem = str(pair_keys["private"])
	publisher.signing_key_id = "test"

	var published: DotResult = publisher.publish(source, out)
	_check(published.ok, "the map pack publishes", str(published.error))

	if not published.ok:
		return {}
	return pair_keys


## A dot-cloud client that trusts the test key and finds the published pack in [param data].
func _add_cloud(client_script: Variant, data: String, pair_keys: Dictionary) -> Node:
	var config_script: Variant = load("res://addons/dot_cloud/dot_cloud_config.gd")

	var cloud: Node = client_script.new()
	cloud.name = "MapCloud"
	var config: Variant = config_script.new()
	config.cache_dir = data.path_join("cache")
	config.require_signed_manifests = true
	config.trusted_keys = {"test": str(pair_keys["public"])}
	cloud.config = config
	cloud.config_file = ""
	# The id-and-version form, which is what a catalogue of two hundred maps needs: the
	# client builds the URL, so no map repeats the host.
	cloud.local_search_dirs = PackedStringArray([data.path_join("dist")])
	cloud.manifest_url_template = "{base}/{id}/{version}/manifest.json"
	add_child(cloud)
	await get_tree().process_frame
	return cloud


func _check_delivered_pair(cloud: Node, pair: SyncPair, host_progress: Array[float], fetched: Array[String], failures: Array[String], changed: Dictionary) -> void:
	_check(bool(changed["ok"]), "the host changes to it", str(changed["reason"]))
	_check(failures.is_empty(), "the peer had no trouble getting it", str(failures))
	_check(
		fetched.size() == 1,
		"and had to fetch it rather than already having it (%s)" % [fetched]
	)
	_check(
		bool(cloud.call("is_mounted", &"surf_pack", "1.0.0")),
		"the pack is mounted"
	)

	_check(
		pair.client_session.current != null
			and pair.client_session.current.id == &"surf_pack_map",
		"and the peer is on the downloaded map"
	)
	_check(
		pair.client_session.world != null,
		"with its world — out of the pack, not out of the build"
	)
	_check(
		pair.client_session.catalogue.has(&"surf_pack_map"),
		"and it kept the definition it was sent"
	)

	# Progress reached the host, which means the client subscribed to dot-cloud on its own. `report_progress`
	# was public and called by nobody — a value produced correctly and consumed by nothing, which in this family
	# is the shape that costs a week because the symptom points at the producer.
	_check(
		host_progress.size() > 0,
		"the host heard progress from the peer (%d reports)" % host_progress.size(),
		"the client has to subscribe to dot-cloud itself; nothing else knows to"
	)
	_check(
		cloud.get_signal_connection_list("progress_changed").size() == 1,
		"and subscribed exactly once (%d)"
			% cloud.get_signal_connection_list("progress_changed").size()
	)

	# What a peer that arrives between two changes is sent first — by `admit_peer`, or by a
	# host that sends it itself. The load that has to follow it is
	# `_test_sync_a_joiner_is_told_to_load`'s.
	var joining := pair.host.join_payload()
	_check(
		DotMapMessage.kind_of(joining) == DotMapMessage.KIND_ANNOUNCE,
		"a peer joining now would be sent an announce"
	)
	_check(
		str((joining.get("map", {}) as Dictionary).get("id", "")) == "surf_pack_map",
		"naming the map the host is actually on"
	)


## A content client that answers the first fetch late and counts how many were running. Stands in front of a
## real [code]DotCloudClient[/code], so what is mounted is a real signed pack; the delay is the suite's, so
## the host's timeout can be made to pass while the peer is still downloading — a straggler, on demand.
class SlowContent:
	extends Node

	signal progress_changed(progress: Dictionary)

	var real: Node = null
	var delay_first: float = 0.0
	## How many fetches were already running when each call arrived, in call order.
	var calls: Array[int] = []
	var _running := 0
	var _delayed := false

	func ensure(
		content_id: StringName, version: String = "",
		groups: PackedStringArray = PackedStringArray(), manifest_url: String = ""
	) -> DotResult:
		calls.append(_running)
		_running += 1
		if delay_first > 0.0 and not _delayed:
			_delayed = true
			await get_tree().create_timer(delay_first).timeout
		var got: Variant = await real.call("ensure", content_id, version, groups, manifest_url)
		_running -= 1
		return got

	func is_mounted(content_id: StringName, version: String = "") -> bool:
		return bool(real.call("is_mounted", content_id, version))


## Publishes one signed pack of data files under [param data]/dist.
func _publish_pack(
	data: String, id: String, version: String, files: Dictionary, keys: Dictionary
) -> DotResult:
	var source := data.path_join("src_%s" % id)
	for name in files:
		var written := DotPaths.write_text(source.path_join(str(name)), str(files[name]))
		if not written.ok:
			return written
	var publisher: Variant = load("res://addons/dot_cloud/publish/dot_cloud_publisher.gd").new()
	publisher.content_id = id
	publisher.version = version
	publisher.signing_key_pem = str(keys["private"])
	publisher.signing_key_id = "test"
	return publisher.publish(source, "%s/dist/%s/%s" % [data, id, version])


## The template shape end to end, and the straggler's load that overtakes its fetch. The first half is what
## `trusted_template_scenes` is for: a scene in the build, data in a real signed pack, and a peer with an
## empty catalogue that fetches and loads it.
func _test_sync_a_delivered_template_and_a_straggler() -> void:
	_section("a delivered template map, and a straggler")

	var client_script: Variant = load("res://addons/dot_cloud/client/dot_cloud_client.gd")
	if client_script == null:
		_check(false, "dot-cloud is present so the delivered path can be run",
			"addons/dot_cloud is not linked; the template and straggler paths are NOT covered")
		return

	var data := "user://dot_map_template_test"
	DotPaths.remove_tree(data)

	var keys: DotResult = load("res://addons/dot_cloud/verify/dot_cloud_signature.gd").generate_keypair()
	if not keys.ok:
		_check(false, "a signing key pair is generated", str(keys.error))
		return

	var body := "{\"hello\": \"from the pack\"}"
	var first := _publish_pack(data, "surf_data", "1.0.0", {"surf_data_map.json": body}, keys.value)
	var second := _publish_pack(data, "slow_data", "1.0.0", {"slow_map.json": body}, keys.value)
	_check(first.ok and second.ok, "two data-only packs publish",
		"%s %s" % [first.error, second.error])
	if not (first.ok and second.ok):
		return

	var slow := await _add_slow_cloud(client_script, data, str((keys.value as Dictionary)["public"]))
	var real: Node = slow.real

	var template := "res://fixtures/test_world.tscn"
	var host_catalogue := DotMapCatalogue.new()
	for id in ["surf_data", "slow_data"]:
		var map := DotMapDef.new()
		map.id = StringName(id.replace("_data", "_map") if id == "slow_data" else id + "_map")
		map.content_id = StringName(id)
		map.scene_path = template
		map.meta["manifest"] = "res://dot_cloud/%s/1.0.0/%s.json" % [id, String(map.id)]
		host_catalogue.add(map)

	var pair: SyncPair = await _make_pair(self, host_catalogue, DotMapCatalogue.new())
	pair.client.trusted_template_scenes = PackedStringArray([template])

	var fetched: Array[String] = []
	pair.client.fetching.connect(func(m: DotMapDef) -> void: fetched.append(String(m.id)))
	var failures: Array[String] = []
	pair.client.fetch_failed.connect(func(_m: DotMapDef, e: DotError) -> void:
		failures.append("%s %s" % [e.message, e.detail]))

	var changed := await _change_and_pump(pair, &"surf_data_map", 20.0)
	_check(bool(changed["ok"]) and failures.is_empty(),
		"a template map whose data is delivered is changed to", "%s %s" % [changed["reason"], failures])
	_check(fetched == ["surf_data_map"], "the peer had to fetch it (%s)" % [fetched])
	var here := pair.client_session.current
	_check(here != null and here.id == &"surf_data_map" and pair.client_session.world != null,
		"and is on it: the template scene out of the build")
	var manifest := str(here.meta.get("manifest", "")) if here != null else ""
	_check(FileAccess.get_file_as_string(manifest) == body,
		"reading its data out of the pack (%s)" % manifest)

	await _test_straggler(pair, slow, failures)

	await _free_pair(pair)
	DotRegistry.unregister_instance(&"dot_cloud_client", slow)
	slow.queue_free()
	real.queue_free()
	await get_tree().process_frame
	DotPaths.remove_tree(data)
	_done()


## A signature-checking dot-cloud client in front of a [SlowContent], registered as the cloud for this test.
func _add_slow_cloud(client_script: Variant, data: String, public_key: String) -> SlowContent:
	var config: Variant = load("res://addons/dot_cloud/dot_cloud_config.gd").new()
	config.cache_dir = data.path_join("cache")
	config.require_signed_manifests = true
	config.trusted_keys = {"test": str(public_key)}

	var real: Node = client_script.new()
	real.name = "TemplateCloud"
	real.config = config
	real.config_file = ""
	real.local_search_dirs = PackedStringArray([data.path_join("dist")])
	real.manifest_url_template = "{base}/{id}/{version}/manifest.json"
	real.register_service = false
	add_child(real)

	var slow := SlowContent.new()
	slow.name = "SlowContent"
	slow.real = real
	add_child(slow)
	DotRegistry.register(&"dot_cloud_client", slow)
	await get_tree().process_frame
	return slow


## A peer that is still downloading when the host's timeout passes, and what it is sent afterwards.
func _test_straggler(pair: SyncPair, slow: SlowContent, failures: Array[String]) -> void:
	pair.host.sync_timeout_sec = 0.5
	slow.calls.clear()
	slow.delay_first = 1.5
	var timed_out: Array[int] = []
	pair.host.peer_timed_out.connect(func(peer: int) -> void: timed_out.append(peer))

	var late := await _change_and_pump(pair, &"slow_map", 20.0)
	_check(bool(late["ok"]) and timed_out == [1],
		"the host changes without the peer still downloading", "%s %s" % [late["reason"], timed_out])

	await _pump_for(pair, 4.0, func() -> bool:
		return pair.client_session.current != null and pair.client_session.current.id == &"slow_map")
	_check(pair.client_session.current != null and pair.client_session.current.id == &"slow_map",
		"and the peer follows once its download lands", str(failures))
	_check(slow.calls == [0, 1, 0],
		"its load waited for its own fetch rather than asking for the pack again mid-download (%s)"
			% [slow.calls])
	_check(pair.sent_to(1).count("map.load slow_map") == 1,
		"and its late ready was not answered with a second load (%s)" % [pair.sent_to(1)])


## A fixture pack as the index holds it after a mount: the dictionary DotCloudClient hands
## add_pack. Two maps of two kinds, a weapon, and a map of a kind no game here accepts.
func _workshop_pack(cid: String, version: String, session: StringName, map_id := "utopia_one") -> Dictionary:
	return {
		"content_id": cid, "version": version, "session": session, "source": "subscription",
		"prefix": "res://dot_cloud/%s/%s" % [cid, version],
		"provides": {
			"schema": 1, "title": "Utopia surf maps", "kinds": ["map", "weapon"],
			"entries": [
				{"kind": "map", "id": map_id, "name": "Utopia One", "scene": "maps/one.tscn",
					"map_kind": "surf", "tier": 4, "max_players": 12},
				{"kind": "map", "id": "utopia_bhop", "name": "Utopia Hop", "scene": "maps/hop.tscn",
					"map_kind": "bhop", "zones": "maps/hop_zones.json"},
				{"kind": "map", "id": "utopia_odd", "name": "Odd", "scene": "maps/odd.tscn",
					"map_kind": "teleporter_golf"},
				{"kind": "weapon", "id": "utopia_gun", "name": "Gun", "def": "gun.tres"},
			],
		},
	}


func _test_workshop_maps() -> void:
	print("")
	_section("-- Workshop maps follow the content index")

	var index := DotContentIndex.new()
	index.set_session(DotContentIndex.SESSION_SOLO)
	var catalogue := _catalogue(3)
	catalogue.follow_content(index, PackedStringArray(["surf", "bhop"]))
	_check(catalogue.size() == 3, "an empty index adds nothing")

	index.add_pack(_workshop_pack("alice/utopia", "1.0.0", DotContentIndex.SESSION_SOLO))
	var one := catalogue.get_map(&"utopia_one")
	var hop := catalogue.get_map(&"utopia_bhop")
	_check(one != null and hop != null and catalogue.size() == 5,
		"a pack mounted afterwards adds its maps, only the kinds the game accepts",
		"%d maps" % catalogue.size())
	_check(catalogue.get_map(&"utopia_odd") == null and catalogue.get_map(&"utopia_gun") == null,
		"a map kind the game does not accept, and a weapon, are offered to nobody")
	_check(one.scene_path == "res://dot_cloud/alice/utopia/1.0.0/maps/one.tscn"
			and hop.zones_path.ends_with("/maps/hop_zones.json")
			and one.kind == &"surf" and one.tier == 4 and one.max_players == 12
			and String(one.content_id) == "alice/utopia" and one.content_version == "1.0.0"
			and not one.is_local(),
		"the entry's paths resolve onto the mount and its fields carry over")
	_check(one.pack_title == "Utopia surf maps" and one.label() == "Utopia One [Utopia surf maps]"
			and catalogue.get_map(&"surf_0").label() == "Surf 0",
		"a pack map is marked with its pack and the game's own maps are not")

	# The places a player sees the list.
	var vote := DotMapVote.new()
	vote.max_options = 5
	vote.begin(catalogue, [one, hop])
	_check("Utopia One [Utopia surf maps]" in vote.option_labels(),
		"the vote ballot shows the pack name")
	var session := DotMapSession.new()
	session.catalogue = catalogue
	session.initial_map = &""
	add_child(session)
	var host := FakeHost.new()
	DotMapCommands.install(host, session)
	var ctx := FakeCtx.new()
	(host.commands["maps"] as FakeCommand).handler.call(ctx)
	_check(ctx.replies.size() == 1 and ctx.replies[0].contains("utopia_one [Utopia surf maps]")
			and ctx.replies[0].contains("surf_0,"),
		"/maps lists them marked, the game's own bare")
	session.queue_free()

	# A pack cannot take a map's id from the game.
	index.add_pack(_workshop_pack("bob/clash", "1.0.0", DotContentIndex.SESSION_SOLO, "surf_1"))
	_check(catalogue.get_map(&"surf_1").pack_title == "",
		"a pack map under an id the game already holds does not replace it")

	_test_workshop_sessions(index, catalogue)

	# A map the operator replaced under a followed id is not removed with the followers.
	catalogue.add(_map(&"utopia_one"))
	catalogue.refresh_content()
	_check(catalogue.get_map(&"utopia_one") != null and catalogue.get_map(&"utopia_one").pack_title == "",
		"a row the operator replaced is theirs and survives a refresh")

	catalogue.unfollow_content()
	index.add_pack(_workshop_pack("carol/late", "1.0.0", DotContentIndex.SESSION_SOLO, "late_map"))
	_check(catalogue.get_map(&"late_map") == null and catalogue.get_map(&"utopia_bhop") == null,
		"an unfollowed catalogue drops the pack maps and hears no more")
	_done()


func _test_workshop_sessions(index: DotContentIndex, catalogue: DotMapCatalogue) -> void:
	# Online never sees a solo entry; solo again brings them back.
	index.set_session(DotContentIndex.SESSION_ONLINE)
	_check(catalogue.get_map(&"utopia_one") == null and catalogue.size() == 3,
		"in an online session no solo entry appears")
	index.set_session(DotContentIndex.SESSION_SOLO)
	_check(catalogue.get_map(&"utopia_one") != null,
		"and solo shows them again, since nothing was ever removed")

	# A pack the server also requires is tagged online; tag_pack is silent, so refresh.
	index.tag_pack(&"alice/utopia", "1.0.0", DotContentIndex.SESSION_ONLINE)
	index.set_session(DotContentIndex.SESSION_ONLINE)
	catalogue.refresh_content()
	_check(catalogue.get_map(&"utopia_one") != null, "a pack the server also requires shows online")
	index.set_session(DotContentIndex.SESSION_SOLO)

	# Accepts: none by default, "*" for all.
	var none := _catalogue(1)
	none.follow_content(index)
	_check(none.size() == 1, "a game that states no map kinds takes no subscribed maps")
	var all := _catalogue(1)
	all.follow_content(index, PackedStringArray(["*"]))
	_check(all.get_map(&"utopia_odd") != null, "and a star takes every kind")


class FakeCommand:
	extends RefCounted

	var name := ""
	var help := ""
	var permission := ""
	var handler: Callable = Callable()
	## Tri-state, like DotConCommand.ChatPolicy: "" is the host server's default, and the
	## other two are the command's own word. A plain bool here would have hidden the
	## difference the real console now draws.
	var chat := ""
	var usage := ""
	var completer: Callable = Callable()

	func with_chat(allowed: bool = true) -> FakeCommand:
		chat = "allowed" if allowed else "refused"
		return self

	func no_chat() -> FakeCommand:
		chat = "refused"
		return self

	func with_usage(text: String) -> FakeCommand:
		usage = text
		return self

	func with_completer(fn: Callable) -> FakeCommand:
		completer = fn
		return self


## A `DotModule`-shaped host and nothing else, not a real `DotConsole`: dot-server is not linked here
## and `DotMapCommands` names no dot-server class, so a fake proves the duck-typing.
class FakeHost:
	extends RefCounted

	var commands: Dictionary = {}

	## Names some other command already holds, as a console's has_name would say.
	var taken: Array = []

	func has_name(name: String) -> bool:
		return commands.has(name) or taken.has(name)

	func add_command(
		name: String, handler: Callable, help: String, permission: String
	) -> FakeCommand:
		var c := FakeCommand.new()
		c.name = name
		c.handler = handler
		c.help = help
		c.permission = permission
		commands[name] = c
		return c


## What a DotModule looks like to a commands class: add_command, a console, and no has_name.
class ModuleHost:
	extends RefCounted

	var console := FakeHost.new()

	func add_command(
		name: String, handler: Callable, help: String, permission: String
	) -> FakeCommand:
		return console.add_command(name, handler, help, permission)


class FakeCtx:
	extends RefCounted

	var args := PackedStringArray()
	var replies := PackedStringArray()

	func reply(text: String) -> void:
		replies.append(text)

	func reply_lines(lines: PackedStringArray) -> void:
		for l in lines:
			replies.append(l)


func _test_commands() -> void:
	print("")
	_section("-- `map` belongs here, not in dot-server")

	var session := DotMapSession.new()
	session.catalogue = _catalogue(4)
	session.initial_map = &""
	add_child(session)

	var host := FakeHost.new()
	var commands := DotMapCommands.install(host, session)

	_check(commands.registered.size() == 5, "five commands register on a duck-typed host")
	_check(host.commands.has("map"), "including the plain name dot-server used to hold")
	_check(host.commands.has("maps") and host.commands.has("mapinfo"), "and the two beside it")
	_check(not host.commands.has("nextmap") and not host.commands.has("timeleft"), "and NOT nextmap or timeleft, which dot-vote registers over the same maps")

	var map_cmd: FakeCommand = host.commands["map"]
	_check(map_cmd.permission == "changemap", "changing the map needs a permission")
	_check(map_cmd.chat == "", "and says nothing about chat, leaving `/map` to the permission and the host server")
	_check((host.commands["maps"] as FakeCommand).chat == "allowed", "while listing them is marked outright, since reading changes nothing")

	# The records-server deployment: a map change that no flag makes typable, because what
	# it destroys is every run in progress rather than anything about who is asking.
	var strict_host := FakeHost.new()
	var strict := DotMapCommands.new()
	strict.session = session
	strict.allow_chat_change = false
	strict.bind(strict_host)
	_check((strict_host.commands["map"] as FakeCommand).chat == "refused", "allow_chat_change off refuses chat outright, which no server setting overrules")
	_check(map_cmd.usage != "", "the change has a usage line")
	_check(Array(map_cmd.completer.call("", 0)) == ["surf_0", "surf_1", "surf_2", "surf_3"], "and completes from the catalogue, sorted as Strings rather than as StringNames")

	# The one an operator hits first: a typo.
	var ctx := FakeCtx.new()
	ctx.args = PackedStringArray(["surf_nine"])
	map_cmd.handler.call(ctx)
	_check(ctx.replies.size() == 1 and ctx.replies[0].contains("No map called"), "a map nothing has is refused by name")
	_check(ctx.replies[0].contains("surf_"), "with a suggestion, because 'no' is an argument and 'did you mean' is an answer")

	# With no argument it lists rather than refusing: an operator typing `map` to remind
	# themselves what there is should not be told the usage first.
	ctx = FakeCtx.new()
	map_cmd.handler.call(ctx)
	_check(ctx.replies.size() == 1 and ctx.replies[0].contains("surf_0"), "and `map` with no argument lists instead of complaining")

	ctx = FakeCtx.new()
	(host.commands["mapinfo"] as FakeCommand).handler.call(ctx)
	_check(ctx.replies.size() > 2, "`mapinfo` answers in lines")

	await _test_commands_change(session, map_cmd)

	_test_commands_naming(session)

	await _test_commands_fetch(session, map_cmd)

	session.queue_free()
	_done()


func _test_commands_fetch(session: DotMapSession, map_cmd: FakeCommand) -> void:
	# A server whose maps arrive over the network holds what has been FETCHED, and the id a player just typed is
	# normally not in it. Refusing that id is refusing a map that exists -- and the refusal happened BEFORE
	# `change_fn`, so the one piece of code written to go and get it was never reached.
	var fetched := []
	var fetching := FakeHost.new()
	var fetcher := DotMapCommands.new()
	fetcher.session = session
	fetcher.may_fetch_unknown = true
	fetcher.change_fn = func(id: StringName) -> DotResult:
		fetched.append(id)
		return DotResult.success(null) if String(id).begins_with("surf_") \
			else DotResult.fail(DotError.CODE_INVALID, "Nothing to fetch.")
	fetcher.bind(fetching)
	var fetch_cmd := fetching.commands["map"] as FakeCommand

	var far_ctx := FakeCtx.new()
	far_ctx.args = PackedStringArray(["surf_tidewater"])
	await fetch_cmd.handler.call(far_ctx)
	_check(
		fetched == [&"surf_tidewater"],
		"an id the catalogue has never held reaches the changer that could fetch it"
	)
	_check(
		far_ctx.replies.size() == 2 and far_ctx.replies[1].contains("Now on"),
		"and is answered as a change rather than as a typo"
	)

	# The suggestion is not lost, only deferred. A typo is still a typo once the fetch
	# has failed to find it, and "did you mean" is worth the same then as before.
	fetched.clear()
	var typo_ctx := FakeCtx.new()
	typo_ctx.args = PackedStringArray(["nope_nine"])
	await fetch_cmd.handler.call(typo_ctx)
	_check(fetched == [&"nope_nine"], "a typo is tried too, because only the fetch can tell")
	_check(
		typo_ctx.replies.size() == 2 and typo_ctx.replies[1].contains("No map called"),
		"and is refused by name after it comes back empty"
	)

	# Off is the default and has to be: on a server whose maps are all on disk, an id the
	# catalogue does not hold IS a typo, and a round trip to find that out is waste.
	fetched.clear()
	var strict_fetch := FakeCtx.new()
	strict_fetch.args = PackedStringArray(["surf_tidewater"])
	await map_cmd.handler.call(strict_fetch)
	_check(
		strict_fetch.replies.size() == 1 and strict_fetch.replies[0].contains("No map called"),
		"while a catalogue-backed server still refuses an unknown id without asking anybody"
	)


func _test_commands_naming(session: DotMapSession) -> void:
	# Every name is configurable, for dot-vote's reason: a deployment may already have a
	# `map` of its own, and a second registration of one name is the first one gone.
	var renamed := DotMapCommands.new()
	renamed.session = session
	renamed.prefix = "sv_"
	renamed.names = {"maps": "maplist"}
	_check(renamed.command_name("maps") == "sv_maplist", "every command name is configurable")

	# The changer is duck-typed on `change_to` so a DotMapSyncHost can stand in front of
	# the session -- the two have the same three methods deliberately.
	var sync := DotMapSyncHost.new()
	sync.session = session
	add_child(sync)
	var synced_host := FakeHost.new()
	DotMapCommands.install(synced_host, session, sync)
	_check(
		synced_host.commands.has("map"),
		"and a sync host stands in for the session without dot-map caring which it got"
	)
	sync.queue_free()


func _test_commands_change(session: DotMapSession, map_cmd: FakeCommand) -> void:
	# The change itself, ACTUALLY PERFORMED. Both `change_to` methods are coroutines, so a handler that called
	# one without awaiting would get a GDScriptFunctionState back, skip its reply, and leave an operator with
	# "Changing to X…" and no answer -- while the map changed perfectly.
	var ctx := FakeCtx.new()
	ctx.args = PackedStringArray(["surf_2"])
	await map_cmd.handler.call(ctx)
	_check(
		session.current != null and session.current.id == &"surf_2",
		"`map <id>` actually changes the map"
	)
	_check(
		ctx.replies.size() == 2 and ctx.replies[1].contains("Now on"),
		"and answers when it is done, which needs the await a non-coroutine call would skip"
	)

	# `change_fn` wins over the changer, for a host whose change resets props and NPCs
	# first -- handing the session straight to the command would change the world out from
	# under all three.
	var routed := []
	var by_fn := FakeHost.new()
	DotMapCommands.install_with(by_fn, session, func(id: StringName) -> DotResult:
		routed.append(id)
		return DotResult.success(null)
	)
	var fn_ctx := FakeCtx.new()
	fn_ctx.args = PackedStringArray(["surf_1"])
	await (by_fn.commands["map"] as FakeCommand).handler.call(fn_ctx)
	_check(routed == [&"surf_1"], "a host's own change method is used instead of the session's")
	_check(
		session.current.id == &"surf_2",
		"and the session is not changed behind its back"
	)
