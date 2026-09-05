extends Node

## Proves the catalogue, the rotation, the vote and the map change do what a server
## depends on.
##
## [codeblock]
## godot --headless --path . res://examples/map_selftest.tscn
## [/codeblock]
##
## [b]The most important test here is [method _test_change_survives_a_failure].[/b]
## Everything else checks bookkeeping; that one checks the property a live server
## rests on — a map that fails to load leaves the server on the map it was already
## running, rather than on nothing. It is the reason the load happens before the
## teardown, and it is the step that is easiest to "simplify" back out.

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("dot-map self-test")
	print("")

	_test_map_validation()
	_test_catalogue()
	_test_catalogue_round_trip()
	_test_catalogue_tolerates_a_bad_entry()
	_test_search()
	_test_rotation_sequential()
	_test_rotation_cooldown()
	_test_rotation_determinism()
	_test_rotation_player_counts()
	_test_vote()
	_test_vote_ties()
	_test_time_limit()
	_test_rock_the_vote()
	await _test_change_maps()
	await _test_change_survives_a_failure()
	await _test_loader_without_cloud()
	await _test_sync_a_local_map()
	await _test_sync_refuses_what_a_host_may_not_send()
	await _test_sync_waits_and_times_out()
	await _test_sync_a_delivered_map()

	print("")
	print("%d passed, %d failed" % [_passed, _failed])

	for line in _failures:
		print("  FAIL  %s" % line)

	get_tree().quit(1 if _failed > 0 else 0)


func _check_near(
	value: float, expected: float, epsilon: float, what: String
) -> void:
	_check(
		absf(value - expected) <= epsilon, what,
		"%.4f vs %.4f" % [value, expected]
	)


func _check(ok: bool, what: String, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    %s" % what)
	else:
		_failed += 1
		var line := what if detail == "" else "%s (%s)" % [what, detail]
		_failures.append(line)
		print("  FAIL  %s" % line)


## A map that points at a scene which really exists, so a load can be tried.
func _map(id: StringName, tier: int = 1) -> DotMapDef:
	var map := DotMapDef.new()
	map.id = id
	map.display_name = String(id).capitalize()
	map.scene_path = "res://fixtures/test_world.tscn"
	map.tier = tier
	map.kind = DotMapDef.KIND_SURF
	return map


func _catalogue(count: int) -> DotMapCatalogue:
	var catalogue := DotMapCatalogue.new()

	for i in range(count):
		catalogue.add(_map(StringName("surf_%d" % i), (i % 10) + 1))

	return catalogue


# --- Definitions -----------------------------------------------------------

func _test_map_validation() -> void:
	print("map definitions")

	var good := _map(&"surf_beginner")
	_check(good.validate().ok, "a well-formed map validates")

	var no_id := _map(&"")
	_check(not no_id.validate().ok, "a map with no id is refused")

	var spaced := _map(&"surf beginner")
	_check(not spaced.validate().ok, "and one with a space in its id")

	var no_scene := _map(&"x")
	no_scene.scene_path = ""
	_check(not no_scene.validate().ok, "and one with no scene")

	var bad_version := _map(&"x")
	bad_version.version = "banana"
	_check(not bad_version.validate().ok, "and one with a version that is not semantic")

	var impossible := _map(&"x")
	impossible.min_players = 20
	impossible.max_players = 4
	_check(
		not impossible.validate().ok,
		"and one whose player range can never be satisfied"
	)

	_check(good.is_local(), "a map with no content id ships in the build")

	good.content_id = &"surf_pack"
	_check(not good.is_local(), "and one with a content id is delivered")
	_check(
		good.effective_content_version() == good.version,
		"whose pack version defaults to the map's"
	)

	good.content_version = "2.0.0"
	_check(
		good.effective_content_version() == "2.0.0",
		"and can differ when several maps share a pack"
	)


func _test_catalogue() -> void:
	print("the catalogue")

	var catalogue := _catalogue(12)

	_check(catalogue.size() == 12, "twelve maps go in")
	_check(catalogue.has(&"surf_3"), "and can be found by id")
	_check(catalogue.get_map(&"nothing") == null, "an unknown id finds nothing")
	_check(catalogue.problems().is_empty(), "and there are no problems")

	# Adding an id that is already there replaces rather than duplicates: a
	# catalogue reloaded after an edit must end up with the edited entry.
	var corrected := _map(&"surf_3", 9)
	catalogue.add(corrected)

	_check(catalogue.size() == 12, "re-adding an id does not duplicate it")
	_check(catalogue.get_map(&"surf_3").tier == 9, "and the new entry wins")

	catalogue.remove(&"surf_3")
	_check(catalogue.size() == 11, "and a map can be removed")
	_check(not catalogue.has(&"surf_3"), "and is then gone")


func _test_catalogue_round_trip() -> void:
	print("catalogues survive JSON")

	var catalogue := _catalogue(5)
	catalogue.get_map(&"surf_1").content_id = &"pack_a"
	catalogue.get_map(&"surf_2").enabled = false
	catalogue.get_map(&"surf_3").zones_path = "res://zones/surf_3.json"
	catalogue.meta["maintainer"] = "somebody"

	var parsed := DotMapCatalogue.from_json(catalogue.to_json())

	_check(parsed.ok, "a catalogue round-trips")

	if not parsed.ok:
		return

	var back: DotMapCatalogue = parsed.value

	_check(back.size() == 5, "with every map")
	_check(back.get_map(&"surf_1").content_id == &"pack_a", "and the content id")
	_check(not back.get_map(&"surf_2").enabled, "and the enabled flag")
	_check(
		back.get_map(&"surf_3").zones_path == "res://zones/surf_3.json",
		"and the zone path"
	)
	_check(str(back.meta.get("maintainer", "")) == "somebody", "and the metadata")

	var newer := DotMapCatalogue.from_dictionary({"format": 999, "maps": []})
	_check(not newer.ok, "and a newer format is refused")


func _test_catalogue_tolerates_a_bad_entry() -> void:
	print("one bad entry does not condemn the file")

	# The property that matters on a community server: a hundred and ninety-nine
	# good maps and one typo should boot on the hundred and ninety-nine.
	var parsed := DotMapCatalogue.from_dictionary({
		"format": 1,
		"maps": [
			{"id": "good_one", "scene": "res://a.tscn"},
			{"id": "", "scene": "res://b.tscn"},
			{"id": "bad version", "scene": "res://c.tscn"},
			{"id": "good_two", "scene": "res://d.tscn"},
		],
	})

	_check(parsed.ok, "a catalogue with two bad entries still loads")

	if parsed.ok:
		var catalogue: DotMapCatalogue = parsed.value
		_check(catalogue.size() == 2, "with the good entries", "%d" % catalogue.size())
		_check(catalogue.has(&"good_two"), "including the one after the bad ones")


func _test_search() -> void:
	print("searching")

	var catalogue := DotMapCatalogue.new()
	catalogue.add(_map(&"surf_kitsune"))
	catalogue.add(_map(&"surf_kitsune2"))
	catalogue.add(_map(&"bhop_arcane"))

	var partial := catalogue.search("kitsune")
	_check(partial.size() == 2, "a substring finds both", "%d" % partial.size())

	# The one that matters: typing the full name of a map must get that map.
	var exact := catalogue.search("surf_kitsune")
	_check(exact.size() == 1, "an exact id returns only that map")
	_check(
		exact.size() == 1 and exact[0].id == &"surf_kitsune",
		"and it is the right one"
	)

	_check(catalogue.search("").is_empty(), "an empty search finds nothing")
	_check(catalogue.search("zzz").is_empty(), "and so does a miss")


# --- Rotation --------------------------------------------------------------

func _test_rotation_sequential() -> void:
	print("sequential rotation")

	var catalogue := _catalogue(4)
	var rotation := DotMapRotation.of(catalogue)
	rotation.mode = DotMapRotation.Mode.SEQUENTIAL
	rotation.cooldown = 0

	var seen := PackedStringArray()

	for _i in range(4):
		var next := rotation.choose()
		seen.append(String(next.id))
		rotation.note_played(next.id)

	_check(seen.size() == 4, "four maps are chosen")

	var unique := {}
	for id in seen:
		unique[id] = true

	_check(unique.size() == 4, "and every one is different", str(seen))

	# Choosing twice without playing gives the same answer, so a HUD can show
	# "next map" without changing it every frame.
	var a := rotation.choose()
	var b := rotation.choose()
	_check(a == b, "choosing does not consume")


func _test_rotation_cooldown() -> void:
	print("the cooldown")

	var catalogue := _catalogue(10)
	var rotation := DotMapRotation.of(catalogue)
	rotation.cooldown = 3

	rotation.note_played(&"surf_0")
	rotation.note_played(&"surf_1")

	_check(rotation.on_cooldown(&"surf_0", 10), "a just-played map is on cooldown")
	_check(rotation.on_cooldown(&"surf_1", 10), "and so is the one before it")
	_check(not rotation.on_cooldown(&"surf_5", 10), "an unplayed one is not")

	for _i in range(60):
		var next := rotation.choose()
		_check_silent(next != null, "the rotation always offers something")
		_check_silent(
			not rotation.on_cooldown(next.id, 10),
			"and never one on cooldown"
		)
		rotation.note_played(next.id)

	_check(true, "sixty consecutive choices avoid the cooldown")

	# The clamp: a cooldown longer than the pool must not exclude everything, or the
	# server sits on its current map for ever with nothing in the log to say why.
	var tiny := DotMapRotation.of(_catalogue(2))
	tiny.cooldown = 8
	tiny.note_played(&"surf_0")
	tiny.note_played(&"surf_1")

	_check(tiny.choose() != null, "a cooldown longer than the pool still chooses")

	var single := DotMapRotation.of(_catalogue(1))
	single.cooldown = 5
	single.note_played(&"surf_0")

	_check(
		single.choose() != null,
		"and a pool of one repeats rather than stopping"
	)


func _check_silent(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		_failures.append(what)


func _test_rotation_determinism() -> void:
	print("rotation determinism")

	# A client showing the next map must reach the same answer the server will, so
	# the random mode is seeded and the seed advances deterministically.
	var first := PackedStringArray()
	var second := PackedStringArray()

	for run in range(2):
		var rotation := DotMapRotation.of(_catalogue(8))
		rotation.seed_value = 12345

		for _i in range(10):
			var next := rotation.choose()
			(first if run == 0 else second).append(String(next.id))
			rotation.note_played(next.id)

	_check(first == second, "the same seed gives the same sequence", str(first))

	var different := DotMapRotation.of(_catalogue(8))
	different.seed_value = 999
	var other := PackedStringArray()

	for _i in range(10):
		var next := different.choose()
		other.append(String(next.id))
		different.note_played(next.id)

	_check(other != first, "and a different seed gives a different one")


func _test_rotation_player_counts() -> void:
	print("player-count limits")

	var catalogue := DotMapCatalogue.new()

	var big := _map(&"surf_big")
	big.min_players = 10
	catalogue.add(big)

	var small := _map(&"surf_small")
	small.max_players = 4
	catalogue.add(small)

	var any := _map(&"surf_any")
	catalogue.add(any)

	var rotation := DotMapRotation.of(catalogue)

	var quiet := rotation.pool(2)
	_check(quiet.size() == 2, "a quiet server is offered two maps", "%d" % quiet.size())

	var busy := rotation.pool(20)
	_check(busy.size() == 2, "and a busy one a different two", "%d" % busy.size())

	var ids := PackedStringArray()
	for map in busy:
		ids.append(String(map.id))

	_check(
		not ids.has("surf_small"),
		"the small map is not offered to twenty players"
	)

	any.enabled = false
	_check(rotation.pool(2).size() == 1, "and a disabled map is offered to nobody")


# --- Voting ----------------------------------------------------------------

func _test_vote() -> void:
	print("map votes")

	var catalogue := _catalogue(10)
	var vote := DotMapVote.new()
	vote.max_options = 5
	vote.reserved_for_nominations = 2

	_check(vote.nominate(&"surf_7"), "a map can be nominated")
	_check(not vote.nominate(&"surf_7"), "and not twice")
	_check(vote.withdraw(&"surf_7"), "and can be withdrawn")

	vote.nominate(&"surf_7")
	vote.nominate(&"surf_8")
	vote.nominate(&"surf_9")

	var extra := DotMapRotation.of(catalogue).pool()
	var opened := vote.begin(catalogue, extra)

	_check(opened.ok, "the ballot opens")
	_check(vote.options.size() == 5, "with five options", "%d" % vote.options.size())

	# Only two of the three nominations get in: the rest of the ballot comes from
	# the rotation, so one organised group cannot fill it.
	var nominated := 0
	for map in vote.options:
		if map.id in [&"surf_7", &"surf_8", &"surf_9"]:
			nominated += 1

	_check(nominated == 2, "two of which are nominations", "%d" % nominated)

	_check(vote.cast_vote(&"alice", vote.options[0].id), "a vote is cast")
	_check(not vote.cast_vote(&"bob", &"not_on_the_ballot"), "an invalid one is refused")

	vote.cast_vote(&"bob", vote.options[1].id)
	vote.cast_vote(&"carol", vote.options[1].id)

	# Changeable until the ballot closes.
	vote.cast_vote(&"alice", vote.options[1].id)

	_check(vote.voter_count() == 3, "three voters", "%d" % vote.voter_count())

	var counts := vote.tally()
	_check(int(counts[vote.options[1].id]) == 3, "and the changed vote moved")
	_check(int(counts[vote.options[0].id]) == 0, "off its first choice")

	var winner := vote.finish()
	_check(winner != null and winner.id == vote.options[1].id, "and the winner is right")
	_check(not vote.open, "the ballot is closed")


func _test_vote_ties() -> void:
	print("vote tie-breaks")

	var catalogue := _catalogue(6)
	var vote := DotMapVote.new()
	vote.allow_extend = true

	vote.nominate(&"surf_1")
	vote.nominate(&"surf_2")
	vote.begin(catalogue, [])

	vote.cast_vote(&"a", &"surf_1")
	vote.cast_vote(&"b", &"surf_2")

	# Deterministic, and toward the front: a client's live tally and the server's
	# result must not disagree, and everybody watching can see the rule coming.
	var winner := vote.finish()
	_check(
		winner != null and winner.id == &"surf_1",
		"a tie goes to the option nominated first",
		String(winner.id) if winner else "-"
	)

	var extend := DotMapVote.new()
	extend.nominate(&"surf_1")
	extend.begin(catalogue, [])
	extend.cast_vote(&"a", &"surf_1")
	extend.cast_vote(&"b", DotMapVote.EXTEND)

	_check(
		extend.finish() != null,
		"and a tie with extend goes to the new map, not the status quo"
	)

	var extended := DotMapVote.new()
	extended.nominate(&"surf_1")
	extended.begin(catalogue, [])
	extended.cast_vote(&"a", DotMapVote.EXTEND)
	extended.cast_vote(&"b", DotMapVote.EXTEND)
	extended.cast_vote(&"c", &"surf_1")

	_check(extended.finish() == null, "while an outright extend wins")


func _test_time_limit() -> void:
	print("the map time limit")

	var limit := DotMapTimeLimit.of(600.0)
	limit.warn_at = 60.0

	var warnings := PackedFloat32Array()
	var expiries := PackedStringArray()

	limit.warning.connect(func(left: float) -> void: warnings.append(left))
	limit.expired.connect(
		func(reason: StringName) -> void: expiries.append(String(reason))
	)

	limit.start()
	_check(limit.running, "the clock starts")
	_check_near(limit.remaining, 600.0, 0.001, "with the full duration")

	# Simulated seconds, advanced by the host — never a wall clock, so a whole map
	# runs in a millisecond here and a server that stalls does not lose the time off
	# its map.
	for _i in range(539):
		limit.advance(1.0)

	_check(warnings.is_empty(), "no warning before the threshold")

	limit.advance(1.0)
	_check(warnings.size() == 1, "one warning at the threshold", "%d" % warnings.size())

	for _i in range(100):
		limit.advance(1.0)

	_check(warnings.size() == 1, "and only one, however long it runs")
	_check(expiries.size() == 1, "the map expires once", "%d" % expiries.size())
	_check(expiries[0] == "time", "for the right reason", str(expiries))

	# The latch. The host's response is to run a vote and change the map, and both
	# take time; without it the limit would fire on every tick until it did — a vote
	# opened a hundred and twenty times a second.
	_check(limit.is_expired(), "and stays expired")
	_check(not limit.running, "with the clock stopped")

	# Extending.
	_check(limit.extend(300.0), "an expired map can be extended")
	_check(not limit.is_expired(), "which un-expires it")
	_check_near(limit.remaining, 300.0, 0.001, "with the added time")
	_check(limit.running, "and the clock running again")

	limit.max_extends = 2
	limit.extends_used = 2
	_check(not limit.can_extend(), "extends are bounded")
	_check(not limit.extend(), "and refused past the bound")

	# Zero is a real configuration and is not "a very long limit".
	var unlimited := DotMapTimeLimit.of(0.0)
	unlimited.start()
	_check(not unlimited.running, "a duration of zero disables the limit")

	for _i in range(100000):
		unlimited.advance(1.0)

	_check(not unlimited.is_expired(), "and it never expires")


func _test_rock_the_vote() -> void:
	print("rock the vote")

	var limit := DotMapTimeLimit.of(3600.0)
	limit.rtv_fraction = 0.6
	limit.rtv_min_players = 2
	limit.start()

	var passed := [false]
	limit.expired.connect(
		func(reason: StringName) -> void:
			if reason == DotMapTimeLimit.REASON_RTV:
				passed[0] = true
	)

	_check(limit.rtv_needed(10) == 6, "six of ten are needed", "%d" % limit.rtv_needed(10))
	_check(limit.rtv_needed(1) == 0, "and on a one-player server it does nothing")

	_check(not limit.rock_the_vote(&"a", 5), "one of five is not enough")
	_check(limit.rtv_votes() == 1, "and is counted")

	# Idempotent. Typing it twice is what a player does when nothing visible
	# happened, and counting it twice would let two people end a map for six.
	_check(not limit.rock_the_vote(&"a", 5), "the same player twice does not count twice")
	_check(limit.rtv_votes() == 1, "the tally is unchanged", "%d" % limit.rtv_votes())

	# Three of five is the threshold — ceil(5 x 0.6) — so the second vote is still
	# short and the third carries it.
	_check(not limit.rock_the_vote(&"b", 5), "two of five is still short")
	_check(limit.rock_the_vote(&"c", 5), "and the third passes it")
	_check(passed[0], "firing the expiry with the right reason")

	# A departing player's vote goes with them. Without it, a server whose players
	# trickle away keeps their votes while the threshold falls with the player
	# count — so a map ends on the votes of people who are not there.
	var leaving := DotMapTimeLimit.of(3600.0)
	leaving.rtv_fraction = 0.6
	leaving.start()

	leaving.rock_the_vote(&"a", 10)
	leaving.rock_the_vote(&"b", 10)
	leaving.unrock(&"a")

	_check(leaving.rtv_votes() == 1, "unrocking removes a vote")
	_check(not leaving.is_expired(), "and does not pass the vote by shrinking it")

	# Below the minimum it does nothing at all, so one person on a quiet server does
	# not change the map at will unless the operator configured that.
	var quiet := DotMapTimeLimit.of(3600.0)
	quiet.rtv_min_players = 2
	quiet.start()

	_check(not quiet.rock_the_vote(&"a", 1), "one player alone cannot rock the vote")
	_check(quiet.rtv_votes() == 0, "and is not even counted")

	quiet.rtv_min_players = 1
	_check(quiet.rock_the_vote(&"a", 1), "unless the server allows it")


# --- Changing maps ---------------------------------------------------------

func _test_change_maps() -> void:
	print("changing maps")

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

	# The clock restarts on every map, and the session reports the map being over
	# rather than changing it — what happens then is a game's decision.
	_check(session.time_limit.running, "the map clock is running")

	var over := PackedStringArray()
	session.map_over.connect(
		func(_map: DotMapDef, reason: StringName) -> void:
			over.append(String(reason))
	)

	for _i in range(int(session.time_limit.remaining) + 2):
		session.advance(1.0)

	_check(over.size() == 1, "and the map ends exactly once", str(over))
	_check(
		session.current != null,
		"with the session still on it — ending a map is not changing it"
	)

	session.unload()
	_check(session.world == null and session.current == null, "and can be unloaded")

	session.queue_free()


func _test_change_survives_a_failure() -> void:
	print("a failed change leaves the server on a working map")

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


func _test_loader_without_cloud() -> void:
	print("the loader without dot-cloud")

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


# --- Changing the map for everybody ---------------------------------------

## A loopback pair: whatever the host sends, the client handles, and back.
##
## [b]Not a mock.[/b] Both halves are the real classes with their real sessions; the
## only stand-in is the wire, and that is the one part deliberately left to the game —
## dot-map depends on nothing but dot-core, so it cannot know what carries a dictionary.
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
	pair.host.send_fn = func(_peer: int, payload: Dictionary) -> void:
		pair.to_client.append(payload)

	pair.client.send_fn = func(payload: Dictionary) -> void:
		pair.to_host.append(payload)

	pair.host.add_peer(1)

	return pair


## Drains both directions until nothing more is in flight.
##
## Called from a poll loop rather than driven by a timer, because the host waits on
## [method SceneTree.create_timer] and the pump has to run while it does.
func _pump(pair: SyncPair) -> void:
	while not pair.to_client.is_empty() or not pair.to_host.is_empty():
		var for_client := pair.to_client.duplicate()
		var for_host := pair.to_host.duplicate()
		pair.to_client.clear()
		pair.to_host.clear()

		for payload in for_client:
			if not pair.deaf:
				pair.client.handle(payload)

		for payload in for_host:
			pair.host.handle(1, payload)

		await get_tree().process_frame


## Runs a change to completion while pumping the loopback.
##
## [b]The GDScript fan-out trap, in its third form.[/b] Neither obvious spelling works:
## a coroutine cannot be stored and awaited later — `var c := host.change_to(x)` is a
## parse error, "is a coroutine, so it must be called with await" — and awaiting it
## outright deadlocks, because the change waits on a peer that only answers when this
## pump runs. So the call is a bare STATEMENT and the outcome comes back through the
## host's own signals, which is the same shape `DotCloudDownloader.sync` uses and for
## the same reason.
func _change_and_pump(
	pair: SyncPair, id: StringName, seconds: float = 10.0
) -> Dictionary:
	var outcome := {"done": false, "ok": false, "reason": ""}

	var on_finished := func(_map: DotMapDef) -> void:
		outcome["done"] = true
		outcome["ok"] = true
	var on_failed := func(_map: DotMapDef, reason: String) -> void:
		outcome["done"] = true
		outcome["reason"] = reason

	pair.host.change_finished.connect(on_finished)
	pair.host.change_failed.connect(on_failed)

	pair.host.change_to(id)

	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)

	while Time.get_ticks_msec() < deadline and not bool(outcome["done"]):
		await _pump(pair)
		await get_tree().process_frame

	# Drained once more so the load the host broadcast on its way out is delivered.
	await _pump(pair)

	pair.host.change_finished.disconnect(on_finished)
	pair.host.change_failed.disconnect(on_failed)

	return outcome


func _test_sync_a_local_map() -> void:
	print("changing the map for everybody")

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


func _test_sync_refuses_what_a_host_may_not_send() -> void:
	print("what a host may not tell a client to load")

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


func _test_sync_waits_and_times_out() -> void:
	print("a peer that never answers")

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


# --- A map that has to be downloaded ---------------------------------------

## The whole point of "maps are content", run end to end.
##
## [b]dot-cloud is loaded by path, not named.[/b] This addon must compile in a project
## that does not have it — that is why [DotMapLoader] duck-types through [DotRegistry] —
## and a `class_name` in this file would take the whole suite down with it. `load()` of a
## script path is the escape hatch the family already uses for exactly this, and it also
## proves the thing that matters: what dot-map calls is what dot-cloud actually provides.
##
## It has not been, for the life of both addons. [DotMapLoader] has called
## `ensure(content_id, version)` and `is_mounted(content_id, version)` since it was
## written and [code]DotCloudClient[/code] offered `acquire(url)` and `is_ready(key)`.
## Every delivered map failed with "the registered cloud client does not speak the
## content interface", and the only loader test here ran with no cloud client at all —
## the branch that falls back to the disk and passes.
func _test_sync_a_delivered_map() -> void:
	print("a map the peer has to download")

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
		return

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
		return

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
	_check(
		loader != null and not loader.is_ready(delivered),
		"the peer does not have the map yet"
	)

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

	# Progress reached the host, which means the client subscribed to dot-cloud on its
	# own. `report_progress` was public and called by nobody — a value produced correctly
	# and consumed by nothing, which in this family is the shape that costs a week
	# because the symptom points at the producer.
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

	# What a peer that arrives between two changes has to be sent. Nothing in this addon
	# consumes it — a host's session list is the host's — so it is asserted here rather
	# than left to be discovered wrong.
	var joining := pair.host.join_payload()
	_check(
		DotMapMessage.kind_of(joining) == DotMapMessage.KIND_ANNOUNCE,
		"a peer joining now would be sent an announce"
	)
	_check(
		str((joining.get("map", {}) as Dictionary).get("id", "")) == "surf_pack_map",
		"naming the map the host is actually on"
	)

	pair.host.queue_free()
	pair.client.queue_free()
	pair.host_session.queue_free()
	pair.client_session.queue_free()
	cloud.queue_free()
	await get_tree().process_frame
	DotPaths.remove_tree(data)
