extends "tests_data_remote.gd"

## The rotation file tests of map_selftest.gd: the file, its paths, a refresh, the fallbacks and the layout.


class _FakeCtx extends RefCounted:
	var args := PackedStringArray()
	var out: Array
	func _init(sink: Array) -> void:
		out = sink
	func reply(text: String) -> void:
		out.append(text)


func _test_rotation_file() -> void:
	_section("maps.yml rotations")
	var cat := _named_catalogue(["surf_a", "surf_b", "surf_c", "bhop_x", "bhop_y", "lobby"])
	var rotation := DotMapRotation.of(cat)

	# The reader is GameSpice Core's: the file's own text, not a hand-built tree.
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


func _ids_in(cat: DotMapCatalogue) -> Array:
	var out: Array = []
	for m in cat.maps:
		if m.in_rotation:
			out.append(String(m.id))
	out.sort()
	return out


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
