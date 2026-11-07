extends "tests_cloud.gd"

## The map data bundle and its stores: round trip, layering, stale fallback and hostile imports.


func _bundle(version: String = "1.0.0", sections: Dictionary = {"spawns": {"points": [{"id": "a", "pos": [1.0, 2.0, 3.0]}]}}) -> DotMapDataBundle:
	var b := DotMapDataBundle.new()
	b.game = "game-x"
	b.map_id = "surf_a"
	b.map_version = version
	b.digest = "abc"
	b.meta = {"author": "me"}
	b.sections = sections
	return b


func _json(patch: Dictionary) -> String:
	var d := _bundle().to_dict()
	d.merge(patch, true)
	return JSON.stringify(d)


func _test_data_round_trip() -> void:
	_section("map data round trip")
	var b := _bundle()
	var mem := DotMapDataMemory.new()
	_check((await mem.save(b, "t")).ok, "memory store saves")
	var got: DotResult = await mem.fetch("game-x", "surf_a", "1.0.0")
	_check(got.ok and got.value.sections == b.sections and got.value.meta == b.meta and got.value.digest == "abc" and not got.value.stale, "memory store gives it back equal")
	var dir := "user://map_data_test_%d" % Time.get_ticks_usec()
	var file := DotMapDataFile.new(dir)
	_check((await file.save(b, "t")).ok and FileAccess.file_exists(dir + "/game-x/surf_a/1.0.0.json"), "file store writes <game>/<map>/<version>.json")
	got = await file.fetch("game-x", "surf_a", "1.0.0")
	_check(got.ok and got.value.to_dict() == b.to_dict(), "file store reads it back equal")
	_check((await file.versions("game-x", "surf_a")).value == PackedStringArray(["1.0.0"]), "versions lists it")
	_check((await file.remove("game-x", "surf_a", "1.0.0")).ok and (await file.fetch("game-x", "surf_a", "1.0.0")).code() == DotMapDataStore.NOT_FOUND, "remove deletes it and a load is then not_found")
	_check((await file.fetch("game-x", "../x", "1.0.0")).code() == DotError.CODE_INVALID and (await mem.save(_bundle("1.0.0/../x"))).code() == DotError.CODE_INVALID, "an id with a separator is refused before any path is built")
	_check(DotMapDataBundle.from_json(b.to_json().value).value.to_dict() == b.to_dict(), "to_json then from_json is the identity")
	var big := _bundle("1.0.0", {"spawns": {"s": "x".repeat(2000)}})
	_check((await mem.save(big)).code() == DotError.CODE_INVALID, "export refuses what an import would")
	_done()


func _test_data_layering() -> void:
	_section("map data layering")
	var pack := DotMapDataMemory.new()
	var store := DotMapDataMemory.new()
	var _p := await pack.save(_bundle("1.0.0", {"spawns": {"v": "pack"}, "cull": {"v": "pack"}}))
	var _s := await store.save(_bundle("1.0.0", {"spawns": {"v": "store"}, "nav_links": {"v": "store"}}))
	var r: DotResult = await DotMapDataStore.read_layered(pack, store, "game-x", "surf_a", "1.0.0")
	var s: Dictionary = r.value.sections if r.ok else {}
	_check(r.ok and s.get("spawns", {}).get("v") == "store", "the store overrides the pack's section")
	_check(s.get("cull", {}).get("v") == "pack" and s.get("nav_links", {}).get("v") == "store", "sections only one side has are kept")
	_check((await DotMapDataStore.read_layered(pack, DotMapDataMemory.new(), "game-x", "surf_a", "1.0.0")).value.sections["spawns"]["v"] == "pack", "an empty store leaves the pack's data")
	_check((await DotMapDataStore.read_layered(null, null, "game-x", "surf_a", "1.0.0")).code() == DotMapDataStore.NOT_FOUND, "nothing anywhere is not_found")
	var ro := DotMapDataPack.new("user://nowhere")
	_check((await ro.save(_bundle())).code() == DotError.CODE_FORBIDDEN and (await ro.remove("game-x", "surf_a", "1.0.0")).code() == DotError.CODE_FORBIDDEN, "a pack store is read-only")
	_done()


func _test_data_stale() -> void:
	_section("map data stale fallback")
	var mem := DotMapDataMemory.new()
	for v in ["1.0.0", "1.2.0", "2.0.0"]:
		var _r := await mem.save(_bundle(v, {"spawns": {"v": v}}))
	var r: DotResult = await mem.fetch("game-x", "surf_a", "1.5.0")
	_check(r.ok and r.value.map_version == "1.2.0" and r.value.stale, "an edited map gets the newest older data, marked stale", str(r.value.map_version if r.ok else r.error))
	_check((await mem.fetch("game-x", "surf_a", "0.9.0")).code() == DotMapDataStore.NOT_FOUND, "data only for newer versions is not used")
	_check(not (await mem.fetch("game-x", "surf_a", "2.0.0")).value.stale, "an exact match is not stale")
	_check((await mem.versions("game-x", "surf_a")).value == PackedStringArray(["1.0.0", "1.2.0", "2.0.0"]), "versions are in semver order")
	var layered: DotResult = await DotMapDataStore.read_layered(null, mem, "game-x", "surf_a", "1.5.0")
	_check(layered.ok and layered.value.stale, "stale survives layering")
	_done()


func _test_data_hostile_import() -> void:
	_section("map data hostile import")
	var ok := DotMapDataBundle.import_json(_json({}), "surf_a", "1.0.0", "abc")
	_check(ok.ok, "a matching file imports")
	_check(DotMapDataBundle.import_json(_json({}), "surf_b", "1.0.0", "abc", true).code() == DotError.CODE_CONFLICT, "a different map id is refused even with force")
	_check(DotMapDataBundle.import_json(_json({}), "surf_a", "2.0.0", "abc").code() == DotError.CODE_CONFLICT, "a different version needs force")
	_check(DotMapDataBundle.import_json(_json({}), "surf_a", "2.0.0", "abc", true).ok, "and force takes it")
	_check(DotMapDataBundle.import_json(_json({}), "surf_a", "1.0.0", "zzz").code() == DotError.CODE_CONFLICT, "a different geometry digest needs force")
	_check(DotMapDataBundle.from_json("not json").code() == DotError.CODE_PARSE and DotMapDataBundle.from_json(_json({"format": "other"})).code() == DotError.CODE_INVALID, "garbage and the wrong format are refused")
	_check(DotMapDataBundle.from_json(_json({"schema": 2})).code() == DotError.CODE_VERSION, "a newer schema is refused")
	var unknown := DotMapDataBundle.from_json(_json({"sections": {"spawns": {}, "evil": {"x": 1}}}))
	_check(unknown.ok and unknown.value.sections.keys() == ["spawns"], "unknown sections are dropped")
	_check(DotMapDataBundle.from_json(_json({"sections": {"spawns": {"script": "res://evil.gd"}}})).code() == DotError.CODE_INVALID, "a resource path is refused")
	_check(DotMapDataBundle.from_json(_json({"sections": {"spawns": {"s": "evil.gd"}}})).code() == DotError.CODE_INVALID, "a script name is refused")
	_check(DotMapDataBundle.from_json(_json({"sections": {"spawns": {"s": "x".repeat(2000)}}})).code() == DotError.CODE_INVALID, "a long string is refused")
	var deep: Variant = "leaf"
	for i in 20:
		deep = {"d": deep}
	_check(DotMapDataBundle.from_json(_json({"sections": {"spawns": deep}})).code() == DotError.CODE_INVALID, "deep nesting is refused")
	var wide: Array = []
	wide.resize(DotMapDataBundle.MAX_NODES + 1)
	wide.fill(1)
	_check(DotMapDataBundle.from_json(_json({"sections": {"spawns": {"p": wide}}})).code() == DotError.CODE_INVALID, "too many values are refused")
	_check(DotMapDataBundle.from_json(_json({"game": "../up"})).code() == DotError.CODE_INVALID, "an id that would climb out of the directory is refused")
	_check(DotMapDataBundle.from_json(_json({"sections": {"spawns": [1]}})).code() == DotError.CODE_INVALID, "a section that is not an object is refused")
	_done()
