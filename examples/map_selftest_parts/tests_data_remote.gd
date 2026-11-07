extends "tests_data.gd"

## The sql and http map data stores against fakes: no database and no network are touched.


## A dot-sql driver held in memory: understands exactly the statements DotMapDataSqlSchema writes.
class FakeSql extends RefCounted:
	var rows: Array = []  # {game, map_id, map_version, section, data, updated_by}
	var opened := false
	var statements: Array = []
	var migrated: Array = []
	var fail_batch := false

	func open() -> DotResult:
		opened = true
		return DotResult.success(true)

	func close() -> void:
		opened = false

	func is_open() -> bool:
		return opened

	func migrate(component: String, steps: Array) -> DotResult:
		migrated.append([component, steps])
		return DotResult.success(true)

	func supports_transactions() -> bool:
		return true

	func query(sql: String, params: Array = []) -> DotResult:
		statements.append([sql, params])
		var out: Array = []
		if sql.begins_with("SELECT DISTINCT map_version"):
			var seen := {}
			for r in rows:
				if r["game"] == params[0] and r["map_id"] == params[1] and not seen.has(r["map_version"]):
					seen[r["map_version"]] = true
					out.append({"map_version": r["map_version"]})
		elif sql.begins_with("SELECT section, data"):
			for r in rows:
				if r["game"] == params[0] and r["map_id"] == params[1] and r["map_version"] == params[2]:
					out.append({"section": r["section"], "data": r["data"]})
			out = out.slice(0, int(params[3]))
		return DotResult.success(out)

	func execute(sql: String, params: Array = []) -> DotResult:
		statements.append([sql, params])
		if sql.begins_with("DELETE"):
			rows = rows.filter(func(r: Dictionary) -> bool: return not (r["game"] == params[0] and r["map_id"] == params[1] and r["map_version"] == params[2]))
		elif sql.begins_with("INSERT"):
			rows.append({"game": params[0], "map_id": params[1], "map_version": params[2], "section": params[3], "data": params[4], "updated_by": params[5]})
		return DotResult.success(1)

	func batch(list: Array) -> DotResult:
		if fail_batch:
			return DotResult.fail(DotError.CODE_IO, "disk full")
		for entry in list:
			var _r := execute(entry[0], entry[1])
		return DotResult.success(list.size())


## An HTTP client held in memory with the shape of DotHttp.request.
class FakeHttp extends RefCounted:
	var files: Dictionary = {}  # path -> text
	var calls: Array = []
	var down := false
	var versions_reply: Variant = null
	var oversize := false

	func request(method: int, path: String, body: PackedByteArray = PackedByteArray(), headers: Dictionary = {}) -> DotResult:
		calls.append({"method": method, "path": path, "headers": headers})
		if down:
			return DotResult.fail(DotError.CODE_NETWORK, "Could not connect.")
		var parts := path.split("/")
		var listing := parts.size() == 3
		match method:
			HTTPClient.METHOD_PUT:
				files[path] = body.get_string_from_utf8()
				return DotResult.success({"status": 200, "body_text": ""})
			HTTPClient.METHOD_DELETE:
				if not files.erase(path):
					return DotResult.failure(DotError.from_http(404))
				return DotResult.success({"status": 200, "body_text": ""})
		if listing:
			if versions_reply != null:
				return DotResult.success({"status": 200, "body_text": JSON.stringify(versions_reply)})
			var found: Array = []
			for p: String in files:
				if p.begins_with(path + "/"):
					found.append(p.get_file())
			if found.is_empty():
				return DotResult.failure(DotError.from_http(404))
			return DotResult.success({"status": 200, "body_text": JSON.stringify({"versions": found})})
		if oversize:
			return DotResult.success({"status": 200, "body_text": "x".repeat(DotMapDataBundle.MAX_BYTES + 1)})
		if not files.has(path):
			return DotResult.failure(DotError.from_http(404))
		return DotResult.success({"status": 200, "body_text": files[path]})


func _test_data_sql() -> void:
	_section("map data sql store")
	var drv := FakeSql.new()
	var store := DotMapDataSql.new(drv)
	_check((await store.fetch("game-x", "surf_a", "1.0.0")).code() == DotError.CODE_STATE, "a closed database is refused, not queried")
	_check((await store.open()).ok and drv.migrated.size() == 1 and drv.migrated[0][0] == "dot_map_data:dot_map_data", "open opens the driver and migrates the table")
	var spec: Dictionary = drv.migrated[0][1][0][0]
	_check(spec["primary_key"] == ["game", "map_id", "map_version", "section"] and spec["columns"].size() == 7, "the table is keyed by game, map, version and section")
	var b := _bundle("1.0.0", {"spawns": {"p": [1.0]}, "cull": {"c": 2.0}})
	_check((await store.save(b, "admin1")).ok, "save writes")
	_check(drv.rows.size() == 3 and drv.rows.all(func(r: Dictionary) -> bool: return r["updated_by"] == "admin1"), "one row per section plus the meta row, with the author")
	var got: DotResult = await store.fetch("game-x", "surf_a", "1.0.0")
	_check(got.ok and got.value.to_dict() == b.to_dict() and not got.value.stale, "fetch gives the bundle back equal, meta and digest included")
	var _s := await store.save(_bundle("1.0.0", {"spawns": {"p": [2.0]}}), "admin2")
	got = await store.fetch("game-x", "surf_a", "1.0.0")
	_check(got.ok and got.value.sections.keys() == ["spawns"] and got.value.sections["spawns"]["p"] == [2.0], "a second save replaces the version, dropping a removed section")
	var _t := await store.save(_bundle("1.2.0", {"spawns": {"p": [3.0]}}))
	_check((await store.versions("game-x", "surf_a")).value == PackedStringArray(["1.0.0", "1.2.0"]), "versions are in semver order")
	got = await store.fetch("game-x", "surf_a", "1.5.0")
	_check(got.ok and got.value.map_version == "1.2.0" and got.value.stale, "a newer map gets the newest older data, stale")
	_check((await store.fetch("game-x", "surf_a", "0.5.0")).code() == DotMapDataStore.NOT_FOUND and (await store.fetch("game-x", "other", "1.0.0")).code() == DotMapDataStore.NOT_FOUND, "nothing held is not_found")
	var layered: DotResult = await DotMapDataStore.read_layered(null, store, "game-x", "surf_a", "1.2.0")
	_check(layered.ok and layered.value.sections["spawns"]["p"] == [3.0], "it layers like any store")
	var before := drv.statements.size()
	var evil_id := "x'; DROP TABLE dot_map_data;--"
	_check((await store.fetch("game-x", evil_id, "1.0.0")).code() == DotError.CODE_INVALID and (await store.save(_bundle(evil_id))).code() == DotError.CODE_INVALID and (await store.remove("game-x", "../a", "1.0.0")).code() == DotError.CODE_INVALID, "an unsafe key is refused before any statement")
	_check(drv.statements.size() == before, "and no statement was sent")
	_check(drv.statements.all(func(s: Array) -> bool: return not str(s[0]).contains("surf_a") and not str(s[0]).contains("game-x")), "values are bound, never spliced into the SQL")
	_check((await store.remove("game-x", "surf_a", "1.2.0")).ok and (await store.remove("game-x", "surf_a", "1.2.0")).code() == DotMapDataStore.NOT_FOUND, "remove deletes, then it is not_found")
	drv.fail_batch = true
	var failed: DotResult = await store.save(_bundle("3.0.0"))
	_check(not failed.ok and failed.code() == DotError.CODE_IO, "a failed write is reported")
	_check((await store.save(_bundle("1.0.0", {"spawns": {"s": "x".repeat(2000)}}))).code() == DotError.CODE_INVALID, "export limits apply to a save")
	_done()


func _test_data_sql_hostile_rows() -> void:
	_section("map data sql hostile rows")
	var drv := FakeSql.new()
	var store := DotMapDataSql.new(drv)
	var _o := await store.open()
	var deep: Variant = "leaf"
	for i in 20:
		deep = {"d": deep}
	var cases := {
		"a resource path": {"x": "res://evil.gd"},
		"a script name": {"x": "evil.gd"},
		"a url": {"x": "https://evil.example/x"},
		"a long string": {"x": "y".repeat(2000)},
		"deep nesting": deep,
	}
	for what: String in cases:
		drv.rows = [{"game": "game-x", "map_id": "surf_a", "map_version": "1.0.0", "section": "spawns", "data": JSON.stringify(cases[what]), "updated_by": ""}]
		_check((await store.fetch("game-x", "surf_a", "1.0.0")).code() == DotError.CODE_INVALID, "%s in a row is refused" % what)
	drv.rows = [
		{"game": "game-x", "map_id": "surf_a", "map_version": "1.0.0", "section": "spawns", "data": "{\"a\": 1}", "updated_by": ""},
		{"game": "game-x", "map_id": "surf_a", "map_version": "1.0.0", "section": "evil", "data": "{\"a\": 1}", "updated_by": ""},
	]
	var got: DotResult = await store.fetch("game-x", "surf_a", "1.0.0")
	_check(got.ok and got.value.sections.keys() == ["spawns"], "an unknown section row is dropped")
	drv.rows = [{"game": "game-x", "map_id": "surf_a", "map_version": "1.0.0", "section": "spawns", "data": "[1]", "updated_by": ""}]
	_check((await store.fetch("game-x", "surf_a", "1.0.0")).code() == DotError.CODE_INVALID, "a row that is not an object is refused")
	drv.rows = [{"game": "game-x", "map_id": "surf_a", "map_version": "../x", "section": "spawns", "data": "{}", "updated_by": ""}]
	_check((await store.versions("game-x", "surf_a")).value.is_empty(), "a stored version that is not a safe id is not listed")
	drv.rows = [{"game": "game-x", "map_id": "surf_a", "map_version": "1.0.0", "section": "spawns", "data": "{}", "updated_by": ""}]
	var text := _json({"map": {"id": "surf_a", "version": "2.0.0", "digest": "abc"}})
	_check(DotMapDataBundle.import_json(text, "surf_a", "1.0.0", "abc").code() == DotError.CODE_CONFLICT and DotMapDataBundle.import_json(text, "surf_a", "1.0.0", "abc", true).ok, "a file for another version still needs force to import")
	_done()


func _test_data_http() -> void:
	_section("map data http store")
	var http := FakeHttp.new()
	var store := DotMapDataHttp.new(http, "s3cret")
	var b := _bundle("1.0.0", {"spawns": {"p": [1.0]}})
	_check((await store.save(b, "admin1")).ok and http.files.has("map-data/game-x/surf_a/1.0.0"), "save PUTs the bundle under game/map/version")
	var put: Dictionary = http.calls[0]
	_check(put["method"] == HTTPClient.METHOD_PUT and put["headers"]["Authorization"] == "Bearer s3cret" and put["headers"]["X-Updated-By"] == "admin1", "the token and author ride in headers")
	var got: DotResult = await store.fetch("game-x", "surf_a", "1.0.0")
	_check(got.ok and got.value.to_dict() == b.to_dict() and not got.value.stale, "fetch gives it back equal")
	var _t := await store.save(_bundle("1.2.0", {"spawns": {"p": [2.0]}}))
	_check((await store.versions("game-x", "surf_a")).value == PackedStringArray(["1.0.0", "1.2.0"]), "versions are in semver order")
	got = await store.fetch("game-x", "surf_a", "1.5.0")
	_check(got.ok and got.value.map_version == "1.2.0" and got.value.stale, "an older version is served stale")
	_check((await store.fetch("game-x", "nothing", "1.0.0")).code() == DotMapDataStore.NOT_FOUND and (await store.fetch("game-x", "surf_a", "0.1.0")).code() == DotMapDataStore.NOT_FOUND, "a 404 and a too-new request are not_found")
	_check((await store.remove("game-x", "surf_a", "1.2.0")).ok and (await store.remove("game-x", "surf_a", "1.2.0")).code() == DotMapDataStore.NOT_FOUND, "remove DELETEs, then not_found")
	var layered: DotResult = await DotMapDataStore.read_layered(null, store, "game-x", "surf_a", "1.0.0")
	_check(layered.ok and layered.value.sections["spawns"]["p"] == [1.0], "it layers like any store")
	var n := http.calls.size()
	_check((await store.fetch("game-x", "../up", "1.0.0")).code() == DotError.CODE_INVALID and (await store.remove("game-x", "a/b", "1.0.0")).code() == DotError.CODE_INVALID and http.calls.size() == n, "an unsafe key never reaches the network")
	http.down = true
	_check((await store.fetch("game-x", "surf_a", "1.0.0")).code() == DotError.CODE_NETWORK and (await store.save(b)).code() == DotError.CODE_NETWORK, "an unreachable server is a network error")
	http.down = false
	_check((await DotMapDataHttp.new(null).fetch("game-x", "surf_a", "1.0.0")).code() == DotError.CODE_STATE, "no client is a state error")
	_done()


func _test_data_http_hostile_reply() -> void:
	_section("map data http hostile reply")
	var http := FakeHttp.new()
	var store := DotMapDataHttp.new(http)
	var path := "map-data/game-x/surf_a/1.0.0"
	var cases := {
		"a resource path": _json({"sections": {"spawns": {"s": "res://evil.gd"}}}),
		"a script name": _json({"sections": {"spawns": {"s": "evil.gd"}}}),
		"a url": _json({"sections": {"spawns": {"s": "http://evil.example"}}}),
		"a long string": _json({"sections": {"spawns": {"s": "x".repeat(2000)}}}),
		"another map's data": _json({"map": {"id": "surf_b", "version": "1.0.0"}}),
		"another version's data": _json({"map": {"id": "surf_a", "version": "9.9.9"}}),
		"another game's data": _json({"game": "game-y"}),
		"a newer schema": _json({"schema": 2}),
		"garbage": "<html>502</html>",
	}
	for what: String in cases:
		http.files[path] = cases[what]
		var r: DotResult = await store.fetch("game-x", "surf_a", "1.0.0")
		_check(not r.ok and r.code() in [DotError.CODE_INVALID, DotError.CODE_VERSION, DotError.CODE_PARSE], "%s is refused" % what, r.code())
	http.files[path] = _json({"sections": {"spawns": {}, "evil": {"x": 1}}})
	var dropped: DotResult = await store.fetch("game-x", "surf_a", "1.0.0")
	_check(dropped.ok and dropped.value.sections.keys() == ["spawns"], "unknown sections are dropped")
	http.oversize = true
	_check((await store.fetch("game-x", "surf_a", "1.0.0")).code() == DotError.CODE_INVALID, "a reply over the size cap is refused")
	http.oversize = false
	http.versions_reply = {"versions": ["1.0.0", "../../etc/passwd", "a/b", 5, null, "evil.gd"]}
	_check((await store.versions("game-x", "surf_a")).value == PackedStringArray(["1.0.0", "evil.gd"]), "version names that are not safe ids are dropped")
	http.versions_reply = {"versions": "1.0.0"}
	_check((await store.versions("game-x", "surf_a")).code() == DotError.CODE_INVALID, "a version list that is not a list is refused")
	var many: Array = []
	for i in DotMapDataHttp.MAX_VERSIONS + 50:
		many.append("1.0.%d" % i)
	http.versions_reply = {"versions": many}
	_check((await store.versions("game-x", "surf_a")).value.size() == DotMapDataHttp.MAX_VERSIONS, "the version list is capped")
	_done()


func _test_data_config() -> void:
	_section("map data config")
	var cfg := DotMapDataConfig.new()
	_check(cfg.validate().ok and cfg.make_store().value is DotMapDataFile, "the default is the file store")
	cfg.apply_dictionary({"map_data_store": "sql", "map_data_table": "maps_x"}, "file")
	var made := cfg.make_store(FakeSql.new())
	_check(made.ok and made.value is DotMapDataSql and made.value.table == "maps_x", "sql builds from the driver and table")
	_check(cfg.make_store().code() == DotError.CODE_STATE, "sql without a driver fails")
	cfg.apply_dictionary({"map_data_table": "x; DROP"}, "file")
	_check(cfg.validate().code() == DotError.CODE_INVALID, "a table name that is not an identifier is refused")
	var h := DotMapDataConfig.new()
	h.apply_dictionary({"map_data_store": "http", "map_data_url": "https://tmc.example/api", "map_data_token": "tok"}, "file")
	var hm := h.make_store(null, FakeHttp.new())
	_check(hm.ok and hm.value is DotMapDataHttp and hm.value.token == "tok", "http builds from the url and token", str(hm.error) if not hm.ok else "")
	h.apply_dictionary({"map_data_token": "leaked"}, "env", false)
	_check(h.map_data_token == "tok", "the token is refused from the environment and argv")
	h.map_data_url = "http://evil.example/api"
	_check(h.validate().code() == DotError.CODE_INVALID, "plain http to a remote host is refused")
	h.map_data_url = "http://127.0.0.1:3000/api"
	_check(h.validate().ok, "plain http to localhost is allowed")
	h.apply_dictionary({"map_data_store": "bogus"}, "file")
	_check(h.validate().code() == DotError.CODE_INVALID, "an unknown store is refused")
	_done()
