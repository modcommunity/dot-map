class_name DotMapDataStore
extends RefCounted

## Where a map's [DotMapDataBundle] lives. Every method returns a [DotResult] and a subclass may make it a
## coroutine, so callers [code]await[/code]. The base refuses everything; [DotMapDataMemory],
## [DotMapDataFile] and [DotMapDataPack] are the local stores.

const NOT_FOUND := "not_found"


## The bundle for this version, else the newest older one with [member DotMapDataBundle.stale] set.
func fetch(_game: String, _map_id: String, _map_version: String) -> DotResult:
	return DotResult.fail(DotError.CODE_UNSUPPORTED, "This store cannot load.")


## Writes the bundle under its own game, map id and version. [param by] is logged.
func save(_bundle: DotMapDataBundle, _by: String = "") -> DotResult:
	return DotResult.fail(DotError.CODE_UNSUPPORTED, "This store cannot save.")


## The versions held for a map, oldest first.
func versions(_game: String, _map_id: String) -> DotResult:
	return DotResult.fail(DotError.CODE_UNSUPPORTED, "This store cannot list.")


func remove(_game: String, _map_id: String, _map_version: String) -> DotResult:
	return DotResult.fail(DotError.CODE_UNSUPPORTED, "This store cannot remove.")


## The map's data as a game reads it: the pack's bundle is the default, the store's the override, section by
## section. Either may be null. Fails with [constant NOT_FOUND] when neither has anything.
static func read_layered(pack: DotMapDataStore, store: DotMapDataStore, game: String, map_id: String, map_version: String) -> DotResult:
	var base: DotMapDataBundle = null
	var over: DotMapDataBundle = null
	if pack != null:
		var r: DotResult = await pack.fetch(game, map_id, map_version)
		if r.ok:
			base = r.value
	if store != null:
		var r2: DotResult = await store.fetch(game, map_id, map_version)
		if r2.ok:
			over = r2.value
		elif r2.code() != NOT_FOUND:
			return r2
	var out := DotMapDataBundle.layered(base, over)
	if out == null:
		return DotResult.fail(NOT_FOUND, "No data for %s %s." % [map_id, map_version])
	return DotResult.success(out)


## The version to serve: exact, else the newest older. "" when none.
static func pick_version(held: PackedStringArray, wanted: String) -> String:
	if wanted in held:
		return wanted
	var want := DotSemVer.parse(wanted)
	var best := ""
	var best_v: DotSemVer = null
	for v in held:
		var sv := DotSemVer.parse(v)
		if not sv.valid or not want.valid or not sv.is_older_than(want):
			continue
		if best_v == null or sv.is_newer_than(best_v):
			best = v
			best_v = sv
	return best


## Oldest first by semver; text order for versions that are not semver.
static func sort_versions(found: Array) -> PackedStringArray:
	found.sort_custom(func(a: String, b: String) -> bool:
		var x := DotSemVer.parse(a)
		var y := DotSemVer.parse(b)
		return x.is_older_than(y) if x.valid and y.valid else a < b)
	return PackedStringArray(found)


## Null when the key is safe to use in a path, else the refusal.
static func check_key(game: String, map_id: String, map_version: String = "0") -> DotResult:
	for s in [game, map_id, map_version]:
		if not DotMapDataBundle.is_safe_id(s):
			return DotResult.fail(DotError.CODE_INVALID, "Unsafe game, map id or version.")
	return null
