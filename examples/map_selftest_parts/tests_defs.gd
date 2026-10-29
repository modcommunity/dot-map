extends "harness.gd"

## Definitions, catalogue, search, rotation and voting sections of the map self-test.

func _test_map_validation() -> void:
	_section("map definitions")

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
	_done()


func _test_catalogue() -> void:
	_section("the catalogue")

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

	# A delivered map by its pack key, the way a game descriptor's maps: list names it.
	var delivered := catalogue.add_delivered("gamemann/surf_mesa@0.0.0-d99eeea9e490", "map.tscn")
	var mesa := catalogue.get_map(&"surf_mesa")
	_check(delivered.ok and mesa != null and String(mesa.content_id) == "gamemann/surf_mesa"
			and mesa.content_version == "0.0.0-d99eeea9e490" and not mesa.is_local()
			and mesa.scene_path == "res://dot_cloud/gamemann/surf_mesa/0.0.0-d99eeea9e490/map.tscn",
		"a delivered map is added by its pack key, under the id a player types")
	_check(not catalogue.add_delivered("gamemann/surf_mesa", "map.tscn").ok
			and not catalogue.add_delivered("surf_mesa@1.0.0", "map.tscn").ok
			and DotMapDef.from_content_key("gamemann/@1.0.0") == null,
		"and a key with no version, no owner or no name is refused")
	_check(not catalogue.add_delivered("gamemann/surf_tidewater@1.0.0", "").ok,
		"and a delivered map still needs a scene to load")
	_done()


func _test_catalogue_round_trip() -> void:
	_section("catalogues survive JSON")

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
	_done()


func _test_catalogue_tolerates_a_bad_entry() -> void:
	_section("one bad entry does not condemn the file")

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
	_done()


func _test_search() -> void:
	_section("searching")

	var catalogue := DotMapCatalogue.new()
	catalogue.add(_map(&"surf_tidewater"))
	catalogue.add(_map(&"surf_tidewater2"))
	catalogue.add(_map(&"bhop_arcane"))

	var partial := catalogue.search("tidewater")
	_check(partial.size() == 2, "a substring finds both", "%d" % partial.size())

	# The one that matters: typing the full name of a map must get that map.
	var exact := catalogue.search("surf_tidewater")
	_check(exact.size() == 1, "an exact id returns only that map")
	_check(
		exact.size() == 1 and exact[0].id == &"surf_tidewater",
		"and it is the right one"
	)

	_check(catalogue.search("").is_empty(), "an empty search finds nothing")
	_check(catalogue.search("zzz").is_empty(), "and so does a miss")
	_done()



func _test_rotation_sequential() -> void:
	_section("sequential rotation")

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
	_done()


func _test_rotation_cooldown() -> void:
	_section("the cooldown")

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
	_done()


func _check_silent(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		_failures.append(what)


func _test_rotation_determinism() -> void:
	_section("rotation determinism")

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
	_done()


func _test_rotation_player_counts() -> void:
	_section("player-count limits")

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
	_done()



func _test_vote() -> void:
	_section("map votes")

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
	_done()


func _test_vote_ties() -> void:
	_section("vote tie-breaks")

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
	_done()


func _test_time_limit() -> void:
	_section("the map time limit")

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
	_done()


func _test_rock_the_vote() -> void:
	_section("rock the vote")

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
	_done()
