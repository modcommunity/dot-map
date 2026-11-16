extends "map_selftest_parts/tests_rotation.gd"

## Proves the catalogue, the rotation, the vote and the map change do what a server depends on. The most
## important test here is [method _test_change_survives_a_failure].

const CHECKS := 495

## Sections entered against sections that ran to their last line, and against this. A runtime error inside a
## section aborts that function and nothing says so; a section that bailed out early after a failed guard is
## counted as not finished on purpose. The CHECKS total is the other half — see docs/testing.md.
const SECTIONS := 48


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
	_test_rotation_exempt()
	_test_rotation_play()
	_test_rotation_profile()
	_test_map_config()
	_test_model_texture_max()
	_test_supports()
	await _test_data_round_trip()
	await _test_data_layering()
	await _test_data_stale()
	_test_data_hostile_import()
	await _test_data_sql()
	await _test_data_sql_hostile_rows()
	await _test_data_http()
	await _test_data_http_hostile_reply()
	_test_data_config()

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


func _test_rotation_exempt() -> void:
	_section("exempt: every installed map except these, globs, per rotation, late packs")
	var ids := ["dm_a", "dm_b", "surf_x", "bhop_one", "m_z"]
	# Only exempt: everything else, sorted by id; the exempt map stays installed.
	var cat := _named_catalogue(ids)
	var rot := DotMapRotation.of(cat)
	var f := _file([{"exempt": ["m_z"]}])
	var res := f.apply(rot)
	_check(Array(res.value) == ["bhop_one", "dm_a", "dm_b", "surf_x"], "only exempt: all installed maps but m_z, sorted (%s)" % [res.value])
	_check(cat.get_map(&"m_z") != null and not cat.get_map(&"m_z").in_rotation and not f.fell_back(),
		"the exempt map stays installed and is marked out of rotation")
	_check(_file([{"remove": ["m_z"]}]).resolve(cat).size() == 4, "remove: is still an alias")
	# Globs, quoted leading star, and owner/map refs.
	f = _file([{"exempt": ["dm_*", "*_x", "zed/bhop_one"]}])
	f.apply(rot)
	_check(_ids_in(cat) == ["m_z"], "globs and an owner/map ref exempt (%s)" % [_ids_in(cat)])
	# Exempt beats an include in the same layer, and a merge layer adds exempts to a shipped list.
	f = _file([{"defaults": {"maps": ["dm_a", "dm_b", "surf_x"]}, "exempt": ["dm_b"]}])
	_check(Array(f.resolve(cat)) == ["dm_a", "surf_x"], "exempt wins over an include in the same layer")
	f = _file([{"defaults": {"maps": ["dm_a", "dm_b", "surf_x"]}}, {"merge": true, "exempt": ["surf_*"]}])
	_check(Array(f.resolve(cat)) == ["dm_a", "dm_b"], "a merge layer adds exempts to the shipped list")
	# Inside defaults: and games: sections, and per rotation.
	f = _file([{"defaults": {"exempt": ["dm_a"]}, "games": {"game-x": {"exempt": ["dm_b"]}, "other": {"exempt": ["m_z"]}}}])
	_check(_ids_in_after(f, rot, cat) == ["bhop_one", "m_z", "surf_x"], "exempt inside defaults: and the game's entry, not another game's")
	f = _file([{"defaults": {"rotation": "all", "rotations": {
		"all": {"maps": ["*"], "exempt": ["m_z"]}, "dm": {"maps": ["dm_*", "m_z"], "exempt": ["dm_b"]}}}}])
	_check(Array(f.resolve(cat, "all")) == ["bhop_one", "dm_a", "dm_b", "surf_x"], "per-rotation exempt (all)")
	_check(Array(f.resolve(cat, "dm")) == ["dm_a", "m_z"], "per-rotation exempt does not leak into another (dm)")
	f = _file([{"defaults": {"rotations": {"calm": {"exempt": ["surf_*"]}}}}])
	f.apply(rot, "calm")
	_check(_ids_in(cat) == ["bhop_one", "dm_a", "dm_b", "m_z"], "a rotation with only exempt: plays everything else")
	# A pack that arrives later is covered by a file with only exempt:.
	var index := DotContentIndex.new()
	index.set_session(DotContentIndex.SESSION_SOLO)
	var lcat := _named_catalogue(["dm_a", "m_z"])
	lcat.follow_content(index, PackedStringArray(["surf", "bhop"]))
	var lrot := DotMapRotation.of(lcat)
	var lf := _file([{"exempt": ["m_z", "utopia_bhop"]}])
	lf.apply(lrot)
	index.add_pack(_workshop_pack("alice/utopia", "1.0.0", DotContentIndex.SESSION_SOLO))
	_check(lcat.get_map(&"utopia_one").in_rotation and not lcat.get_map(&"utopia_bhop").in_rotation
		and lcat.get_map(&"dm_a").in_rotation and not lcat.get_map(&"m_z").in_rotation,
		"a pack mounted later joins the rotation except its exempt maps")
	# A pattern matching nothing warns (once), like an include list.
	f = _file([{"exempt": ["nothing_*"]}])
	f.resolve(cat)
	f.resolve(cat)
	_check(f.warnings.is_empty() and f._warned.size() == 1, "an exempt pattern that matches nothing warns once (%d)" % f._warned.size())
	# Everything exempt never empties the server.
	f = _file([{"exempt": ["*"]}])
	f.apply(rot)
	_check(f.fell_back() and _ids_in(cat).size() == 5, "exempting everything falls back to every map")
	_done()


func _ids_in_after(f: DotMapRotationFile, rot: DotMapRotation, cat: DotMapCatalogue) -> Array:
	f.apply(rot)
	return _ids_in(cat)


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


func _test_rotation_profile() -> void:
	_section("rotation entries carry a mode/cfg profile")
	var base := OS.get_temp_dir().path_join("dot_map_profile_%d" % Time.get_ticks_usec())
	var pdir := base.path_join("server/addon/dot_map/cfg")
	_put(pdir.path_join("ctf.yml"), "cvars:\n  timelimit: 20\n  nested:\n    a: 1\n")
	_put(pdir.path_join("koth.yaml"), "capture_time: 5\nmode: ignored_for_an_id\n")
	_put(pdir.path_join("night/fast.yml"), "mode: koth\ngravity: 600\n")
	_put(base.path_join("abs_prof.yml"), "mode: ffa\nfraglimit: 30\n")
	var cat := _named_catalogue(["p_a", "p_b", "g_one", "g_two", "p_plain", "p_path", "p_abs", "p_missing", "p_both"])
	var rot := DotMapRotation.of(cat)
	var tree: Variant = DotYaml.parse("""defaults:
  mode: tdm
  rotations:
    main:
      mode: cycle
      cfg: siege
      maps:
        - map: p_a
          mode: ctf
        - p_b:
            cfg: koth
        - g_*:
            mode: ffa
        - p_plain
        - map: p_path
          cfg: night/fast
        - map: p_abs
          cfg: %s
        - map: p_missing
          cfg: nope/missing.yml
        - map: p_both
          mode: ctf
          cfg: koth
    other:
      maps: [p_plain]
""" % base.path_join("abs_prof.yml")).value
	var f := _file([tree], "g")
	f.config_dir = base
	_check(f.warnings.is_empty(), "a game mode and cfg: in a rotation body are not read as the picking mode (%s)" % [f.warnings])
	f.apply(rot, "main")
	_check(rot.mode == DotMapRotation.Mode.SEQUENTIAL and rot.order.size() == 9, "mode: cycle still picks the order, and every entry plays")
	var a := cat.get_map(&"p_a").profile
	_check(a.get("mode") == "ctf" and a.get("values") == {"timelimit": 20} and str(a.get("cfg_path")).ends_with("cfg/ctf.yml"),
		"the map:/mode: entry form names a mode, and cfg/ctf.yml gives its cvars (nested values skipped) (%s)" % [a])
	var b := cat.get_map(&"p_b").profile
	_check(b.get("mode") == "koth" and b.get("values") == {"capture_time": 5}, "the single-key form with cfg:, and a .yaml file (%s)" % [b])
	_check(cat.get_map(&"g_one").profile.get("mode") == "ffa" and cat.get_map(&"g_two").profile.get("mode") == "ffa"
		and (cat.get_map(&"g_one").profile.get("values") as Dictionary).is_empty(), "a glob carries its profile to every match; a mode with no file has no cvars")
	_check(cat.get_map(&"p_plain").profile.get("mode") == "siege", "a plain entry takes the rotation's profile")
	var p := cat.get_map(&"p_path").profile
	_check(p.get("mode") == "koth" and p.get("values") == {"gravity": 600}, "a relative path reads cfg/<path>.yml, and its mode: (%s)" % [p])
	var ab := cat.get_map(&"p_abs").profile
	_check(ab.get("mode") == "ffa" and ab.get("values") == {"fraglimit": 30}, "an absolute path is read as is (%s)" % [ab])
	var miss := cat.get_map(&"p_missing").profile
	_check(miss.get("mode") == "" and (miss.get("values") as Dictionary).is_empty() and cat.get_map(&"p_missing").in_rotation,
		"a missing file leaves the map in rotation with the game's default")
	_check(f._warned.has("missing|nope/missing.yml"), "and warns")
	var warned := f._warned.size()
	f.apply(rot, "main")
	_check(f._warned.size() == warned, "once")
	_check(cat.get_map(&"p_both").profile.get("mode") == "ctf", "mode: wins over a different cfg:")
	_check(f.profile_for(cat, &"p_a", "main").get("mode") == "ctf" and f.profile_value(cat, &"p_b", "main") == "koth", "the getters answer per id")
	f.apply(rot, "other")
	_check(cat.get_map(&"p_plain").profile.get("mode") == "tdm", "a rotation without one takes the section's")
	_check(cat.get_map(&"p_a").profile.is_empty(), "a map out of rotation has no profile")
	var seen: Array = []
	f.profile_changed.connect(func(m: DotMapDef, prof: Dictionary) -> void: seen.append([m.id, prof.get("mode")]))
	f.note_changed(cat.get_map(&"p_plain"))
	_check(seen == [[&"p_plain", "tdm"]], "profile_changed reports the map's profile (%s)" % [seen])
	_check(DotMapRotationFile.is_mode_id("ctf") and not DotMapRotationFile.is_mode_id("ctf.yml")
		and not DotMapRotationFile.is_mode_id("a/b") and not DotMapRotationFile.is_mode_id("/x/y"), "what counts as a mode id")
	var plain := _file([{"defaults": {"maps": ["p_a"]}}])
	plain.apply(rot)
	_check(cat.get_map(&"p_a").profile.is_empty(), "no mode or cfg: no profile")
	var live := {"timelimit": 10, "gravity": 800}
	var mc := DotMapConfig.new()
	mc.allow("timelimit", {"type": "int"})
	mc.get_fn = func(k: String) -> Variant: return live.get(k)
	mc.set_fn = func(k: String, v: Variant) -> bool:
		live[k] = v
		return true
	var got := mc.apply_values("p_a", {"timelimit": 20, "gravity": 100})
	_check(got.ok and live["timelimit"] == 20 and live["gravity"] == 800, "apply_values sets a profile's allowed cvars only (%s)" % [live])
	mc.apply_values("p_plain", {})
	_check(live["timelimit"] == 10 and mc.applied().is_empty(), "and the next map puts them back")
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
	_check(not bad["settings"].has("arena_gravity"), "a value below the minimum is refused, not clamped (%s)" % [bad["settings"]])
	var gwhy := ""
	for r: Dictionary in bad["rejected"]:
		if r["key"] == "arena_gravity":
			gwhy = String(r["why"])
	_check(gwhy.contains("arena_gravity") and gwhy.contains("-5"), "the refusal names the key and the value (%s)" % [gwhy])
	_check(bad["rejected"].size() == 3 and not bad["settings"].has("arena_air") and not bad["settings"].has("rm"), "a non-number and an unlisted command key are both refused (%s)" % [bad["rejected"]])
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
	_check(not cfg2._check("arena_int", 1.0e30).ok, "an int too big to hold is refused, not clamped")
	var bare := DotMapConfig.new()
	_check(not bare.apply("x").ok, "apply without hooks fails")


func _test_model_texture_max() -> void:
	_section("model_texture_max: family default 2048, layered")
	var mesh := load("res://addons/dot_map/bsp/mesh_parts/mesh_props.gd") as GDScript
	var kept: Variant = mesh.get("model_texture_max")
	_check(kept == 2048, "the default is 2048 (%s)" % [kept])
	mesh.call("apply_config")
	_check(mesh.get("model_texture_max") == 2048, "no file, env or argv leaves the default")
	OS.set_environment("GS_MAP_MODEL_TEXTURE_MAX", "1024")
	mesh.call("apply_config")
	_check(mesh.get("model_texture_max") == 1024, "the environment overrides it")
	OS.set_environment("GS_MAP_MODEL_TEXTURE_MAX", "-1")
	mesh.call("apply_config")
	_check(mesh.get("model_texture_max") == -1, "-1 stays uncapped")
	OS.unset_environment("GS_MAP_MODEL_TEXTURE_MAX")
	mesh.set("model_texture_max", 512)
	mesh.call("apply_config")
	_check(mesh.get("model_texture_max") == 512, "a game's own assignment survives with nothing above it")
	mesh.set("model_texture_max", kept)
	_completed += 1


func _test_supports() -> void:
	_section("supports: a shot breaks a support and says what stood on it, and says what stood on it")
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
	var client := DotMapSupport.build_all(recs, 8, false)
	_check(not client[1].hurt(500.0) and not client[1].is_broken(), "a client's hurt does nothing")
	client[1].apply_broken()
	_check(client[1].is_broken(), "but the host's word breaks it there")
	for n in made + client:
		n.free()
	_done()
