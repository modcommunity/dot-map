extends "map_selftest_parts/tests_cloud.gd"

## Proves the catalogue, the rotation, the vote and the map change do what a server depends on. The most
## important test here is [method _test_change_survives_a_failure].

const CHECKS := 365

## Sections entered against sections that ran to their last line, and against this. A runtime error inside a
## section aborts that function and nothing says so; a section that bailed out early after a failed guard is
## counted as not finished on purpose. The CHECKS total is the other half — see docs/testing.md.
const SECTIONS := 36


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
	await _test_sync_a_joiner_is_told_to_load()
	await _test_sync_a_joiner_mid_change()
	await _test_sync_template_trust()
	await _test_sync_refused_load_adopts_nothing()
	await _test_sync_progress_is_throttled()
	await _test_sync_a_delivered_map()
	await _test_sync_a_delivered_template_and_a_straggler()
	await _test_commands()
	_test_command_names()
	_test_workshop_maps()
	_test_rotation_file()
	await _test_rotation_paths()
	_test_rotation_file_layout()
	_test_zero_config_rotation()
	_test_rotation_play()
	_test_map_config()
	_test_supports()

	print("")
	print("%d passed, %d failed" % [_passed, _failed])

	for line in _failures:
		print("  FAIL  %s" % line)

	print("%d of %d sections ran to their last line" % [_completed, _entered])
	if _entered != SECTIONS or _completed != _entered:
		print("ERROR: %d sections entered and %d completed, %d expected. One aborted or was skipped." % [
			_entered, _completed, SECTIONS
		])
		get_tree().quit(1)
		return
	# The total the section counter cannot be. A runtime error inside a section aborts
	# that function, and the counter is satisfied because the section had already
	# announced itself. See docs/testing.md.
	if _passed + _failed != CHECKS:
		print("ERROR: %d checks ran, %d expected. A section aborted part-way." % [
			_passed + _failed, CHECKS
		])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)


## A catalogue of named maps, three of them owned (`owner/<id>` content ids).
func _named_catalogue(ids: Array) -> DotMapCatalogue:
	var catalogue := DotMapCatalogue.new()
	for id: Variant in ids:
		var map := _map(StringName(str(id)))
		if str(id).begins_with("bhop_"):
			map.content_id = StringName("zed/%s" % str(id))
		catalogue.add(map)
	return catalogue


func _file(trees: Array, game: String = "game-x") -> DotMapRotationFile:
	return DotMapRotationFile.from_trees(trees, game).value


func _test_rotation_file() -> void:
	_section("maps.yml rotations")
	var cat := _named_catalogue(["surf_a", "surf_b", "surf_c", "bhop_x", "bhop_y", "lobby"])
	var rotation := DotMapRotation.of(cat)

	# The reader is dot-core's: the file's own text, not a hand-built tree.
	var parsed := DotYaml.parse("defaults:\n  maps: [surf_*]\n")
	var comment := DotYaml.parse("name: Bob's map # c\ntabbed: x\t# t\nquoted: \"a # b\" # c\nmaps:\n- a\n- b\nafter: 1\n")
	var tree: Dictionary = comment.value if comment.ok else {}
	_check(comment.ok and tree.get("name") == "Bob's map" and tree.get("tabbed") == "x" and tree.get("quoted") == "a # b",
		"an apostrophe inside a plain scalar opens no quote, a tab before # starts a comment, a quoted # is data (%s)" % [tree])
	_check(tree.get("maps") == ["a", "b"] and tree.get("after") == 1, "a list at the key's own indent is that key's list (%s)" % [tree])
	var plain := _file([parsed.value])
	plain.apply(rotation)
	_check(plain.active_name() == "main" and rotation.order.size() == 3 and not cat.get_map(&"bhop_x").in_rotation,
		"a plain maps: list is the main rotation, a glob matched by name")
	_check(cat.get_map(&"bhop_x") != null and cat.has(&"lobby"), "and the others stay installed")

	var named := _file([{"defaults": {"rotation": "party", "mode": "random", "cooldown": 2,
		"rotations": {"main": {"maps": ["surf_a"]}, "party": {"mode": "cycle", "maps": ["surf_c", "bhop_y", "surf_a"]}}}}])
	named.apply(rotation)
	_check(rotation.mode == DotMapRotation.Mode.SEQUENTIAL and rotation.cooldown == 2,
		"named rotations: the rotation: key picks one, its mode and the shared cooldown apply")
	var order := PackedStringArray()
	for i in range(4):
		var next := rotation.choose()
		order.append(String(next.id))
		rotation.note_played(next.id)
	_check(order == PackedStringArray(["surf_c", "bhop_y", "surf_a", "surf_c"]), "cycle order is the written order, and wraps", str(order))
	_check(named.switch(rotation, "main").ok and rotation.order == [&"surf_a"] and cat.get_map(&"surf_c").in_rotation == false,
		"switching live changes the list")
	_check(not named.switch(rotation, "nope").ok and named.active_name() == "main", "an unknown rotation name changes nothing")

	# Layering: shipped < server defaults < games:<game>; a list replaces a list, scalars merge.
	var shipped := {"defaults": {"mode": "cycle", "maps": ["surf_a", "surf_b"]}, "games": {"game-x": {"cooldown": 9}}}
	var server := {"defaults": {"maps": ["surf_c"]}, "games": {"gamemann/game-x": {"rotations": {"main": {"maps": ["bhop_*"]}}}}}
	var layered := _file([shipped, server])
	layered.apply(rotation)
	_check(rotation.order == [&"bhop_x", &"bhop_y"] and rotation.mode == DotMapRotation.Mode.SEQUENTIAL and rotation.cooldown == 9,
		"layering: the game's section wins, the list replaced, the shipped mode and cooldown kept (owner/name and name half match)")
	_file([shipped, server], "game-other").apply(rotation)
	_check(rotation.order == [&"surf_c"], "another game sees only the defaults")

	# Wildcard shapes.
	var shapes := _file([{"defaults": {"maps": ["zed/bhop_x", "lobby", "zed/*", "*_y", "zed/pack/*", "nothing_*"]}}])
	shapes.collections = {"zed/pack": ["zed/bhop_x", "zed/bhop_y"]}
	shapes.apply(rotation)
	var ids := shapes.resolve(cat)
	_check(ids == PackedStringArray(["bhop_x", "lobby", "bhop_y"]), "owner/map, a bare name, owner/*, a name glob and owner/collection/* all resolve, once each, in written order", str(ids))
	_check(shapes.resolve(cat, "main").size() == 3, "and an entry matching nothing is only skipped")
	_check(_file([{"defaults": {"maps": ["*"]}}]).resolve(cat).size() == 6, "* is every installed map")

	# Empty falls back to the whole catalogue; maps: with rotations: main, main wins.
	var empty := _file([{"defaults": {"maps": ["zzz_*"]}}])
	empty.apply(rotation)
	_check(rotation.pool().size() == 6 and rotation.order.is_empty(), "an empty result plays every installed map")
	var both := DotMapRotationFile.from_trees([{"defaults": {"maps": ["surf_a"], "rotations": {"main": {"maps": ["surf_b"]}}}}], "g")
	_check(both.value.warnings.size() == 1 and both.value.resolve(cat) == PackedStringArray(["surf_b"]),
		"maps: beside rotations: main warns once and rotations: main wins")
	var none := _file([{}])
	none.apply(rotation)
	_check(not none.has_rotations() and rotation.pool().size() == 6, "no file content is today's behaviour: everything plays")
	_check(plain.describe_lines().size() == 1 and plain.describe().has("active"), "describe works")
	_done()


## Every way a map is offered or picked: a map installed but outside the active rotation
## must appear in none of them, and must still load by name.
func _test_command_names() -> void:
	_section("maps.yml renames the commands")
	var file := _file([
		{"defaults": {"commands": {"prefix": "sv_", "names": {"maps": ["maplist", "ml"], "mapinfo": "where"}}}},
		{"games": {"game-x": {"commands": {"names": {"maps": "listmaps"}}}}},
	])
	var spec := file.commands()
	_check(spec.get("prefix") == "sv_", "the prefix reads from defaults")
	_check(Array(spec["names"]["maps"]) == ["listmaps"], "a game's list replaces the default list (%s)" % [spec["names"]["maps"]])
	_check(Array(spec["names"]["mapinfo"]) == ["where"], "and a name that is not repeated survives the layering")

	var session := DotMapSession.new()
	session.catalogue = _catalogue(2)
	session.initial_map = &""
	add_child(session)

	var wide := _file([{"defaults": {"commands": {"prefix": "sv_", "names": {"maps": ["maplist", "ml"], "mapinfo": "where"}}}}])
	var host := FakeHost.new()
	var commands := DotMapCommands.new()
	commands.session = session
	commands.spec_fn = wide.commands
	commands.bind(host)
	_check(host.commands.has("sv_maplist") and host.commands.has("sv_ml"), "a rename registers the name and its alias, behind the prefix (%s)" % [host.commands.keys()])
	_check(host.commands.has("sv_where") and host.commands.has("sv_map") and not host.commands.has("maps"), "the prefix moves every command, and the old name is gone")
	_check(commands.command_name("maps") == "sv_maplist" and commands.typed("maps") == "!sv_maplist", "help and hints show the first name behind the chat prefix (%s)" % commands.typed("maps"))
	commands.chat_prefix = "/"
	_check(commands.typed("maps") == "/sv_maplist", "and the server's first chat prefix, whichever it is")

	# A collision is a WARN and a skip, never a steal.
	var held := FakeHost.new()
	held.taken = ["maplist"]
	var clash := DotMapCommands.new()
	clash.session = session
	clash.names = {"maps": ["maplist", "ml"]}
	clash.bind(held)
	_check(not held.commands.has("maplist") and held.commands.has("ml"), "a name another command holds is skipped and the alias still registers")
	_check(clash.skipped == PackedStringArray(["maplist"]), "and the skip is recorded (%s)" % [clash.skipped])
	var twice := DotMapCommands.new()
	twice.session = session
	twice.names = {"maps": "mapinfo"}
	var dup := FakeHost.new()
	twice.bind(dup)
	_check(twice.skipped.has("mapinfo") and dup.commands["mapinfo"].handler == twice._cmd_maps, "two roles on one name: the first keeps it")

	# A DotModule host has no has_name of its own; the check must go through its console.
	var mod := ModuleHost.new()
	mod.console.taken = ["status"]
	var grab := DotMapCommands.new()
	grab.session = session
	grab.names = {"maps": ["status", "ml"]}
	grab.bind(mod)
	_check(not mod.console.commands.has("status") and mod.console.commands.has("ml"), "a host without has_name is checked through its console: the server's own name is not taken")
	_check(grab.skipped.has("status"), "and the skip is recorded for it")
	session.free()
	_done()


func _test_rotation_paths() -> void:
	_section("paths obey the rotation")
	var cat := _named_catalogue(["surf_a", "surf_b", "surf_c", "surf_off"])
	var session := DotMapSession.new()
	session.catalogue = cat
	session.rotation = DotMapRotation.of(cat)
	session.rotation.mode = DotMapRotation.Mode.RANDOM
	session.rotation.cooldown = 0
	var file := _file([{"defaults": {"maps": ["surf_a", "surf_b", "surf_c"]}}])
	file.apply(session.rotation)
	var off := cat.get_map(&"surf_off")

	_check(not off.in_rotation and cat.has(&"surf_off"), "surf_off is installed and not in rotation")
	_check(not session.rotation.pool().has(off) and not cat.available().has(off), "the pool and the available list leave it out")

	var picked := {}
	for i in range(30):
		session.rotation.seed_value = i * 7919
		picked[String(session.rotation.choose().id)] = true
	_check(not picked.has("surf_off"), "next map, over 30 seeds, is never it")

	_check(not session.rotation.set_next(&"surf_off") and session.rotation.set_next(&"surf_a"), "a vote result cannot force it as the next map")
	session.rotation.clear_next()

	var vote := DotMapVote.new()
	vote.nominate(&"surf_off")
	vote.nominate(&"surf_b")
	var opened := vote.begin(cat, session.rotation.pool())
	var on_ballot := false
	for m in vote.options:
		if m.id == &"surf_off":
			on_ballot = true
	_check(opened.ok and not on_ballot and vote.options.size() == 3, "a nomination of it is dropped and the ballot never lists it")
	var raw := DotMapVote.new()
	raw.begin(cat, cat.maps)
	var raw_has := false
	for m in raw.options:
		raw_has = raw_has or m.id == &"surf_off"
	_check(not raw_has, "even a ballot fed the whole catalogue drops it")

	var host := DotMapSyncHost.new()
	host.session = session
	var next := session.rotation.choose()
	_check(next != null and next.in_rotation, "the sync host's and session's next map come from the same choose()")

	var commands := DotMapCommands.new()
	commands.session = session
	commands.rotation_file = file
	_check(commands.map_ids().has("surf_off"), "the map list and completer still offer it (map <id> works)")
	var lines := []
	var ctx := _FakeCtx.new(lines)
	commands._cmd_maps(ctx)
	_check(lines.size() == 1 and str(lines[0]).contains("surf_off (not in rotation)") and not str(lines[0]).contains("surf_a (not"),
		"and marks only it as not in rotation")
	lines.clear()
	commands._cmd_rotations(ctx)
	_check(lines.size() == 1 and str(lines[0]).contains("main"), "maps_rotations lists the rotations")
	host.free()

	_test_rotation_fallbacks()

	_test_rotation_refresh()

	# A leading "!" or "/" on a command name is the chat prefix, not part of the name.
	var bang := _file([{"defaults": {"commands": {"names": {"maps": ["!ml", "/listmaps", "Bad-Name", "!"]}}}}]).commands()
	_check(Array(bang["names"]["maps"]) == ["ml", "listmaps"], "a leading ! or / is stripped from a command name, bad names dropped (%s)" % [bang["names"].get("maps")])

	# find() looks in the host's config directory first, and says nothing is there otherwise.
	var dir := OS.get_temp_dir().path_join("dot_map_find_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("maps.yml"), FileAccess.WRITE)
	f.store_string("maps: [a]\n")
	f.close()
	_check(DotMapRotationFile.find("cfg/maps.yml", dir) == dir.path_join("maps.yml"), "find() prefers the --config directory")
	_check(DotMapRotationFile.find("cfg/nothing_here.yml", dir) == "", "and returns nothing for a file no directory has")
	DirAccess.remove_absolute(dir.path_join("maps.yml"))
	DirAccess.remove_absolute(dir)
	session.free()
	_done()


func _test_rotation_refresh() -> void:
	# A content refresh makes fresh defs (in_rotation true); the file's marks must follow them.
	var rf_index := DotContentIndex.new()
	rf_index.set_session(DotContentIndex.SESSION_SOLO)
	var rf_cat := _named_catalogue(["m_a", "m_b"])
	rf_cat.follow_content(rf_index, PackedStringArray(["surf", "bhop"]))
	var rf_rot := DotMapRotation.of(rf_cat)
	var rf_file := _file([{"defaults": {"rotation": "main", "rotations": {
		"main": {"maps": ["m_a", "utopia_one"]}, "alt": {"maps": ["m_b"]}}}}])
	rf_file.apply(rf_rot)
	rf_index.add_pack(_workshop_pack("alice/utopia", "1.0.0", DotContentIndex.SESSION_SOLO))
	_check(rf_cat.get_map(&"utopia_one").in_rotation and not rf_cat.get_map(&"utopia_bhop").in_rotation
		and not rf_cat.get_map(&"m_b").in_rotation,
		"a pack added after the rotation was applied is in rotation only where the file lists it")
	rf_index.set_session(DotContentIndex.SESSION_ONLINE)
	rf_index.set_session(DotContentIndex.SESSION_SOLO)
	_check(not rf_cat.get_map(&"utopia_bhop").in_rotation and rf_cat.get_map(&"utopia_one").in_rotation,
		"and a session change keeps the marks")
	rf_file.switch(rf_rot, "alt")
	rf_cat.refresh_content()
	_check(rf_cat.get_map(&"m_b").in_rotation and not rf_cat.get_map(&"utopia_one").in_rotation,
		"a switched rotation still wins after a refresh")
	var rf_other := _named_catalogue(["o_a"])
	var rf_other_rot := DotMapRotation.of(rf_other)
	rf_file.apply(rf_other_rot)
	rf_cat.refresh_content()
	_check(rf_cat.get_map(&"utopia_bhop").in_rotation,
		"a file applied to another catalogue stops marking the first")
	rf_file.apply(rf_rot)
	# fallback_in applies to maps a refresh adds when the rotation is empty.
	var rf_empty := _file([{"defaults": {"maps": ["nothing_*"]}}])
	rf_empty.fallback_in = func(m: DotMapDef) -> bool: return m.id != &"utopia_bhop"
	var rf_cat2 := _named_catalogue(["m_a"])
	rf_cat2.follow_content(rf_index, PackedStringArray(["surf", "bhop"]))
	var rf_rot2 := DotMapRotation.of(rf_cat2)
	rf_empty.apply(rf_rot2)
	rf_cat2.refresh_content()
	_check(rf_cat2.get_map(&"utopia_one").in_rotation and not rf_cat2.get_map(&"utopia_bhop").in_rotation,
		"fallback_in decides pack maps a refresh adds under an empty rotation")
	var rf_none := _file([])
	var rf_cat3 := _named_catalogue(["m_a"])
	rf_cat3.follow_content(rf_index, PackedStringArray(["surf", "bhop"]))
	var rf_rot3 := DotMapRotation.of(rf_cat3)
	rf_none.apply(rf_rot3)
	rf_cat3.refresh_content()
	_check(rf_cat3.get_map(&"utopia_bhop").in_rotation and rf_cat3.get_map(&"m_a").in_rotation,
		"no file still means every map after a refresh")


func _test_rotation_fallbacks() -> void:
	# A sequential cycle never plays the map it just played, even when a forced map moved it.
	var seq_cat := _named_catalogue(["a", "b", "c", "d"])
	var seq := DotMapRotation.of(seq_cat)
	seq.mode = DotMapRotation.Mode.SEQUENTIAL
	seq.cooldown = 0
	seq.note_played(&"a")
	_check(seq.choose().id == &"b", "the cycle continues with the next map")
	seq.set_next(&"c")
	seq.note_played(seq.choose().id)
	_check(seq.choose().id != &"c", "after a forced c at cursor 2 the cycle does not offer c again (%s)" % seq.choose().id)

	# An empty rotation uses the game's own fallback rule, on every re-apply.
	var fb_cat := _named_catalogue(["m_a", "m_b"])
	fb_cat.get_map(&"m_b").kind = DotMapDef.KIND_ARENA
	var fb := DotMapRotation.of(fb_cat)
	var empty := _file([{"defaults": {"maps": ["nothing_*"]}}])
	empty.fallback_in = func(m: DotMapDef) -> bool: return m.kind != DotMapDef.KIND_ARENA
	empty.apply(fb)
	_check(fb_cat.get_map(&"m_a").in_rotation and not fb_cat.get_map(&"m_b").in_rotation and empty.fell_back(),
		"an empty rotation applies the game's fallback rule instead of admitting every map")


func _put(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _test_rotation_file_layout() -> void:
	_section("maps.yml: tiers, replace by default, merge: true, remove:, the legacy shims")
	var base := OS.get_temp_dir().path_join("dot_map_layout_%d" % Time.get_ticks_usec())
	var addon_f := base.path_join("addons/dot_map/maps.yml")
	var game_f := base.path_join("game/g/dot_map/maps.yml")
	var server_f := base.path_join("server/addons/dot_map/maps.yml")
	var server_game_f := base.path_join("server/game/g/dot_map/maps.yml")
	var old_server_f := base.path_join("server/dot_map/maps.yml")
	var flat_f := base.path_join("maps.yml")
	DotCfgLegacy.reset()
	_check(DotMapRotationFile.find("cfg/maps.yml", base) == "" or not DotMapRotationFile.find("cfg/maps.yml", base).begins_with(base), "nothing in an empty config directory")
	_check(DotMapRotationFile.find_layers(base).is_empty(), "find_layers is empty with no file (the default: every installed map)")
	_put(flat_f, "defaults:\n  maps: [a]\n")
	_check(DotMapRotationFile.find("cfg/maps.yml", base) == flat_f, "the flat file is still found")
	_check(DotCfgLegacy.warned_count() == 1, "and warned once through the shim")
	DotMapRotationFile.find("cfg/maps.yml", base)
	_check(DotCfgLegacy.warned_count() == 1, "not twice")
	_put(addon_f, "defaults:\n  maps: [b]\n")
	_check(DotMapRotationFile.find("cfg/maps.yml", base) == addon_f, "cfg/addons/dot_map/maps.yml beats the flat file")
	_put(game_f, "defaults:\n  maps: [g]\n")
	_check(DotMapRotationFile.find_layers(base).size() == 1, "a game's file is not read until the game is known")
	var layers := DotMapRotationFile.find_layers(base, "g")
	_check(layers.size() == 1 and layers[0] == game_f, "the game's file replaces the addon's (new path wins)")
	_put(server_f, "defaults:\n  maps: [c]\n")
	layers = DotMapRotationFile.find_layers(base, "g")
	_check(layers.size() == 1 and layers[0] == server_f, "the operator's cfg/server/addons/dot_map/maps.yml replaces the shipped lists")
	_check(DotMapRotationFile.find("cfg/maps.yml", base) == server_f, "and find() returns it")
	_put(server_f, "merge: true\ndefaults:\n  maps: [c]\n")
	layers = DotMapRotationFile.find_layers(base, "g")
	_check(layers.size() == 2 and layers[0] == game_f and layers[1] == server_f, "merge: true keeps the shipped file under it, weakest first")
	_put(server_game_f, "merge: true\ndefaults:\n  maps: [d]\n")
	_check(DotMapRotationFile.find_layers(base, "g").size() == 3, "the operator's per-game file is the strongest layer")
	var loaded := DotMapRotationFile.load_files(DotMapRotationFile.find_layers(base, "g"), "g")
	_check(loaded.ok and (loaded.value as DotMapRotationFile).sources.size() == 3, "the layers load")
	# Legacy operator path: read, warned once, new path wins whole when both exist.
	DirAccess.remove_absolute(server_f)
	DirAccess.remove_absolute(server_game_f)
	DirAccess.remove_absolute(addon_f)
	DotCfgLegacy.reset()
	_put(old_server_f, "defaults:\n  maps: [old]\n")
	layers = DotMapRotationFile.find_layers(base, "g")
	_check(layers.size() == 1 and layers[0] == old_server_f, "the old cfg/server/dot_map/maps.yml is still read")
	DotMapRotationFile.find_layers(base, "g")
	_check(DotCfgLegacy.warned_count() == 1, "and warns once")
	_put(server_f, "defaults:\n  maps: [c]\n")
	_check(DotMapRotationFile.find_layers(base, "g")[0] == server_f, "the new path wins over the old when both exist")
	_check(DotMapRotationFile.find("cfg/other.yml", base) == "", "another stem is not routed through the new layout")
	# remove: drops ids from every rotation.
	var rm := DotMapRotationFile.from_trees([{"defaults": {"maps": ["m_a", "m_b", "m_c"]}}, {"merge": true, "remove": ["m_b"]}], "g").value as DotMapRotationFile
	var rm_cat := _named_catalogue(["m_a", "m_b", "m_c"])
	_check(Array(rm.resolve(rm_cat)) == ["m_a", "m_c"], "remove: takes a map out of the rotation (%s)" % [rm.resolve(rm_cat)])
	_put(addon_f, "defaults:\n\tmaps: [b\n  - broken: [\n")
	DirAccess.remove_absolute(game_f)
	DirAccess.remove_absolute(server_f)
	DirAccess.remove_absolute(old_server_f)
	var bad := DotMapRotationFile.load_files(DotMapRotationFile.find_layers(base), "g")
	_check(not bad.ok, "a bad maps.yml fails to load rather than rotating nothing")
	DotCfgLegacy.reset()
	for p in [addon_f, game_f, server_f, server_game_f, old_server_f, flat_f]:
		DirAccess.remove_absolute(p)
	for d in ["addons/dot_map", "addons", "game/g/dot_map", "game/g", "game", "server/addons/dot_map", "server/addons", "server/game/g/dot_map", "server/game/g", "server/game", "server/dot_map", "server", ""]:
		DirAccess.remove_absolute(base.path_join(d) if d != "" else base)
	_done()


func _test_zero_config_rotation() -> void:
	_section("no rotation file: installed maps rotate sorted by id")
	var cat := _named_catalogue(["m_c", "m_a", "m_b"])
	var rot := DotMapRotation.of(cat)
	rot.mode = DotMapRotation.Mode.SEQUENTIAL
	DotMapRotationFile.from_trees([]).value.apply(rot)
	var ids: Array = rot.pool().map(func(m: DotMapDef) -> String: return String(m.id))
	_check(ids == ["m_a", "m_b", "m_c"], "pool is sorted by id (%s)" % [ids])
	rot.sort_unordered = false
	ids = rot.pool().map(func(m: DotMapDef) -> String: return String(m.id))
	_check(ids == ["m_c", "m_a", "m_b"], "sort_unordered = false keeps catalogue order (%s)" % [ids])
	_done()


func _test_rotation_play() -> void:
	_section("rotation entries carry per-map settings")
	var cat := _named_catalogue(["zz_camp_a", "zz_camp_b", "zz_plain", "other"])
	var rot := DotMapRotation.of(cat)
	var f := _file([{"defaults": {"maps": ["zz_plain", {"zz_camp_*": {"waves": "camp_nights"}}, {"map": "other", "waves": "hard", "profile": "night"}]}}])
	f.apply(rot)
	_check(cat.get_map(&"zz_camp_a").play == {"waves": "camp_nights"} and cat.get_map(&"zz_camp_b").play == {"waves": "camp_nights"},
		"a glob entry carries its settings to every match (%s)" % [cat.get_map(&"zz_camp_a").play])
	_check(cat.get_map(&"other").play == {"waves": "hard", "profile": "night"}, "the single-key form carries several keys")
	_check(cat.get_map(&"zz_plain").play.is_empty() and rot.order.size() == 4, "a bare string entry has none and still rotates")
	var d := cat.get_map(&"other")
	_check(d.play_candidates("waves", "admin", "doc") == ["admin", "hard", "doc"], "override > entry > fallback")
	_check(cat.get_map(&"zz_plain").play_candidates("waves", "", "default") == ["default"], "empty ones are skipped")
	_check(f.settings_for(cat, &"other") == {"waves": "hard", "profile": "night"}, "settings_for on the file answers per id")
	_file([{"defaults": {"maps": ["zz_plain"]}}]).apply(rot)
	_check(cat.get_map(&"zz_camp_a").play.is_empty(), "applying another rotation clears the settings")
	_done()


const CFG_ROOT := "user://mapcfg_test"


func _cfg_file(tier: String, name: String, body: String) -> void:
	var dir := CFG_ROOT.path_join(tier).path_join("dot_map/map")
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join(name + ".yml"), FileAccess.WRITE)
	f.store_string(body)
	f.close()


func _cfg_clear() -> void:
	if not DirAccess.dir_exists_absolute(CFG_ROOT):
		return
	var stack := [CFG_ROOT]
	var dirs: Array = []
	while not stack.is_empty():
		var d: String = stack.pop_back()
		dirs.append(d)
		for sub in DirAccess.get_directories_at(d):
			stack.append(d.path_join(sub))
		for f in DirAccess.get_files_at(d):
			DirAccess.remove_absolute(d.path_join(f))
	dirs.reverse()
	for d: String in dirs:
		DirAccess.remove_absolute(d)


func _test_map_config() -> void:
	_section("per-map settings: precedence, whitelist, restore")
	_cfg_clear()
	_cfg_file("addons", "surf_*", "arena_air: 100\narena_gravity: 800\n")
	_cfg_file("addons", "surf_ab*", "arena_air: 120\n")
	_cfg_file("addons", "surf_abc", "arena_air: 130\nnot_a_cvar: 1\n")
	_cfg_file("addons", "SURF_?", "arena_gravity: 700\n")
	_cfg_file("server/addons", "surf_*", "arena_air: 50\n")
	_cfg_file("server/addons", "surf_exact", "arena_gravity: 400\n")
	_cfg_file("addons", "bad_type", "arena_air: fast\nrm: \"quit\"\narena_gravity: -5\n")

	var cfg := DotMapConfig.new()
	cfg.config_dir = CFG_ROOT
	cfg.allow("arena_air", {"type": "float"}).allow("arena_gravity", {"type": "float", "min": 0.0})
	cfg.defaults = {"arena_air": 10, "arena_extra": 1}
	cfg.allow("arena_extra")
	var s: Dictionary = cfg.resolve("surf_zzz").value["settings"]
	_check(s["arena_air"] == 50.0 and s["arena_gravity"] == 800.0, "a server wildcard beats the shipped one, the rest comes from the shipped wildcard (%s)" % [s])
	s = cfg.resolve("surf_abc").value["settings"]
	_check(s["arena_air"] == 50.0, "a server wildcard beats a shipped exact file (%s)" % [s])
	_check(cfg.resolve("surf_exact").value["settings"]["arena_gravity"] == 400.0, "a server exact file wins")
	DirAccess.remove_absolute(CFG_ROOT.path_join("server/addons/dot_map/map/surf_*.yml"))
	DirAccess.remove_absolute(CFG_ROOT.path_join("server/addons/dot_map/map/surf_exact.yml"))
	s = cfg.resolve("surf_zzz").value["settings"]
	_check(s["arena_air"] == 100.0 and s["arena_gravity"] == 800.0, "the wildcard sets a surf map's keys (%s)" % [s])
	_check(cfg.resolve("surf_abx").value["settings"]["arena_air"] == 120.0, "the more specific wildcard wins")
	var abc: Dictionary = cfg.resolve("surf_abc").value
	_check(abc["settings"]["arena_air"] == 130.0, "the exact file beats every wildcard")
	_check(abc["settings"]["arena_gravity"] == 800.0, "a key the exact file lacks falls through to the wildcard")
	_check(not (abc["settings"] as Dictionary).has("not_a_cvar") and abc["rejected"].size() == 1 and abc["rejected"][0]["key"] == "not_a_cvar", "an unknown key is reported and not applied (%s)" % [abc["rejected"]])
	_check(cfg.resolve("SURF_1").value["settings"]["arena_gravity"] == 700.0, "`?` matches one character, case does not matter, equal literals break on the longer pattern")
	var plain: Dictionary = cfg.resolve("dm_plain").value
	_check(plain["settings"].size() == 2 and plain["settings"]["arena_air"] == 10.0 and plain["settings"]["arena_extra"] == 1, "a map no file matches gets the converter default only (%s)" % [plain["settings"]])
	var bad: Dictionary = cfg.resolve("bad_type").value
	_check(bad["settings"].get("arena_gravity") == 0.0, "a minimum clamps (%s)" % [bad["settings"]])
	_check(bad["rejected"].size() == 2 and not bad["settings"].has("arena_air") and not bad["settings"].has("rm"), "a non-number and an unlisted command key are both refused (%s)" % [bad["rejected"]])
	_check(cfg.resolve("surf_abc").value["sources"]["arena_air"].ends_with("surf_abc.yml"), "each key records its file")

	_test_map_config_restore(cfg)
	_cfg_clear()
	_cfg_file("addons", "pf_%", "arena_air: 11\narena_gravity: 22\n")
	_cfg_file("addons", "pf_ab%", "arena_air: 33\n")
	_cfg_file("addons", "PF_@", "arena_gravity: 44\n")
	_cfg_file("addons", "pf_abc", "arena_air: 55\n")
	_cfg_file("server/addons", "pf_%", "arena_air: 66\n")
	var pc := DotMapConfig.new()
	pc.config_dir = CFG_ROOT
	pc.allow("arena_air", {"type": "float"}).allow("arena_gravity", {"type": "float"})
	var ps: Dictionary = pc.resolve("pf_zzz").value["settings"]
	_check(ps["arena_air"] == 66.0 and ps["arena_gravity"] == 22.0, "`%%` spells `*`: a server pf_%% beats the shipped one (%s)" % [ps])
	DirAccess.remove_absolute(CFG_ROOT.path_join("server/addons/dot_map/map/pf_%.yml"))
	_check(pc.resolve("pf_zzz").value["settings"]["arena_air"] == 11.0, "the shipped `%` file applies")
	_check(pc.resolve("pf_abx").value["settings"]["arena_air"] == 33.0, "a longer literal prefix beats a shorter one")
	_check(pc.resolve("pf_abc").value["settings"]["arena_air"] == 55.0, "an exact file beats a `%` glob")
	_check(pc.resolve("PF_1").value["settings"]["arena_gravity"] == 44.0, "`@` spells `?`, case does not matter")
	_check(not pc.resolve("pf_").value["settings"].has("arena_gravity") or pc.resolve("pf_").value["settings"]["arena_gravity"] == 22.0, "`@` needs exactly one character")
	_cfg_clear()
	_done()


func _test_map_config_restore(cfg: DotMapConfig) -> void:
	var live := {"arena_air": 150.0, "arena_gravity": 800.0, "arena_extra": 0}
	cfg.defaults = {}
	cfg.get_fn = func(k: String) -> Variant: return live.get(k)
	cfg.set_fn = func(k: String, v: Variant) -> bool:
		live[k] = v
		return true
	_check(cfg.apply("surf_zzz").ok and live["arena_air"] == 100.0, "apply sets the surf map's key")
	_check(cfg.apply("dm_plain").ok and live["arena_air"] == 150.0 and live["arena_gravity"] == 800.0, "the next, non-surf map has the defaults back")
	cfg.apply("surf_zzz")
	live["arena_air"] = 77.0
	cfg.apply("dm_plain")
	_check(live["arena_air"] == 77.0, "a value changed since is not stomped on restore")
	var clamped := {"arena_air": 150.0, "arena_gravity": 800.0, "arena_extra": 0}
	var cfg2 := DotMapConfig.new()
	cfg2.config_dir = CFG_ROOT
	cfg2.allow("arena_air", {"type": "float"}).allow("arena_gravity", {"type": "float", "min": 0.0}).allow("arena_extra")
	cfg2.get_fn = func(k: String) -> Variant: return clamped.get(k)
	cfg2.set_fn = func(k: String, v: Variant) -> bool:
		clamped[k] = 90.0 if k == "arena_air" and float(v) < 140.0 else v
		return true
	cfg2.apply("surf_zzz")
	_check(clamped["arena_air"] == 90.0, "the cvar clamped what the map asked for")
	cfg2.apply("dm_plain")
	_check(clamped["arena_air"] == 150.0, "restore still puts back a value the cvar clamped or reformatted")
	_check(not cfg2._check("arena_air", INF).ok and not cfg2._check("arena_air", NAN).ok and not cfg2._check("arena_air", "inf").ok, "inf and nan are refused")
	_check(cfg2._check("arena_extra", 1.0e30).ok, "a huge value is accepted")
	cfg2.allow("arena_int", {"type": "int"})
	_check(cfg2._check("arena_int", 1.0e30).value == 9000000000000000, "an int clamps instead of overflowing")
	var bare := DotMapConfig.new()
	_check(not bare.apply("x").ok, "apply without hooks fails")


class _FakeCtx extends RefCounted:
	var args := PackedStringArray()
	var out: Array
	func _init(sink: Array) -> void:
		out = sink
	func reply(text: String) -> void:
		out.append(text)


func _test_supports() -> void:
	_section("supports: a shot breaks a breakable that holds a barrel up, and says what stood on it")
	var recs := [
		{"bounds": [0.0, 0.0, 0.0, 1.0, 1.0, 1.0], "health": 30.0, "holds": [0, 1], "model": 7},
		{"bounds": [5.0, 0.0, 0.0, 6.0, 1.0, 1.0], "health": 10.0, "holds": [2], "model": 8},
		{"health": 5.0},
	]
	var made := DotMapSupport.build_all(recs, 8, true, 10)
	_check(made.size() == 2, "a record without bounds is no support", str(made.size()))
	var s: DotMapSupport = made[0]
	_check(s.holds == PackedInt32Array([10, 11]) and s.collision_layer == 8 and s.collision_mask == 0, "it holds the offset indexes and collides with nothing", str(s.holds))
	_check(DotMapSupport.shoot(made, Vector3(-3, 0.5, 0.5), Vector3.RIGHT, 20.0, 10.0) == 0 and absf(s.health - 20.0) < 0.01, "a shot along the ray hurts the nearest, not the one behind it")
	_check(DotMapSupport.shoot(made, Vector3(-3, 0.5, 0.5), Vector3.RIGHT, 20.0, 10.0, 2.0) == -1, "a wall nearer than the support keeps the shot off it")
	_check(DotMapSupport.shoot(made, Vector3(-3, 3.5, 0.5), Vector3.RIGHT, 20.0, 10.0) == -1, "a miss hurts nothing")
	var told := []
	var _c := s.broken.connect(func(held: PackedInt32Array, _at: Vector3) -> void: told.append(held))
	var _hit := DotMapSupport.shoot(made, Vector3(-3, 0.5, 0.5), Vector3.RIGHT, 20.0, 25.0)
	_check(s.is_broken() and told.size() == 1 and told[0] == PackedInt32Array([10, 11]) and s.collision_layer == 0, "when its health runs out it breaks, tells what stood on it and stops being a body")
	var mesh := DotMapBspMesh.new()
	mesh.manifest = {"props": [{"model": "a", "stand_in": "x", "at": [0, 0, 0]}, {"model": "b", "stand_in": "x", "loose": "barrel", "at": [1, 0.1, 2], "yaw": 30.0}, {"model": "c", "stand_in": "x", "loose": "barrel", "at": [3, 0, 4]}],
			"breakables": [{"model": 5, "health": 1.0, "holds": [2], "bounds": [0, 0, 0, 1, 1, 1]}, {"model": 6, "holds": [0], "bounds": [0, 0, 0, 1, 1, 1]}, {"model": 7, "holds": []}]}
	_check(mesh.loose_toys().size() == 2 and mesh.loose_toys()[0]["toy"] == "barrel", "the manifest's loose props are toy placements", str(mesh.loose_toys()))
	var sup := mesh.supports()
	_check(sup.size() == 1 and sup[0]["holds"] == [1] and sup[0]["model"] == 5, "a support's holds are renumbered into the loose list, and one holding no loose prop is no support", str(sup))
	var one := PackedScene.new()
	var leaf := Node3D.new()
	var _p := one.pack(leaf)
	leaf.free()
	var drawn := mesh.build_props(func(_id: Variant) -> PackedScene: return one)
	var plain := drawn.get_child_count()
	drawn.free()
	mesh.skip_loose = true
	var drawn_less := mesh.build_props(func(_id: Variant) -> PackedScene: return one)
	_check(plain == 3 and drawn_less.get_child_count() == 1, "skip_loose leaves the loose props to the game", "%d then %d" % [plain, drawn_less.get_child_count()])
	drawn_less.free()
	var client := DotMapSupport.build_all(recs, 8, false)
	_check(not client[1].hurt(500.0) and not client[1].is_broken(), "a client's hurt does nothing")
	client[1].apply_broken()
	_check(client[1].is_broken(), "but the host's word breaks it there")
	for n in made + client:
		n.free()
	_done()
