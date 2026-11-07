class_name DotMapDataFile
extends DotMapDataStore

## `<root>/<game>/<map_id>/<version>.json`, one file per version. A write flushes the browser's filesystem.

var root := "user://map_data"


func _init(p_root: String = "user://map_data") -> void:
	root = p_root


func fetch(game: String, map_id: String, map_version: String) -> DotResult:
	var held := versions(game, map_id)
	if not held.ok:
		return held
	var v := pick_version(held.value, map_version)
	if v == "":
		return DotResult.fail(NOT_FOUND, "No data for %s %s." % [map_id, map_version])
	var f := FileAccess.open(_path(game, map_id, v), FileAccess.READ)
	if f == null:
		return DotResult.fail(DotError.CODE_IO, "Cannot read map data for %s %s." % [map_id, v])
	var res := DotMapDataBundle.from_json(f.get_as_text())
	if res.ok:
		var b: DotMapDataBundle = res.value
		if b.game != game or b.map_id != map_id or b.map_version != v:
			return DotResult.fail(DotError.CODE_INVALID, "File %s %s holds data for another map." % [map_id, v])
		b.stale = v != map_version
	return res


func save(bundle: DotMapDataBundle, by: String = "") -> DotResult:
	var text := bundle.to_json()
	if not text.ok:
		return text
	var dir := root.path_join(bundle.game).path_join(bundle.map_id)
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		return DotResult.fail(DotError.CODE_IO, "Cannot create %s." % dir)
	var f := FileAccess.open(_path(bundle.game, bundle.map_id, bundle.map_version), FileAccess.WRITE)
	if f == null:
		return DotResult.fail(DotError.CODE_IO, "Cannot write map data for %s %s." % [bundle.map_id, bundle.map_version])
	f.store_string(text.value)
	f.close()
	DotWeb.sync_filesystem()
	DotLog.info("map_data", "%s saved %s %s" % [by, bundle.map_id, bundle.map_version])
	return DotResult.success(bundle)


func versions(game: String, map_id: String) -> DotResult:
	var bad := check_key(game, map_id)
	if bad != null:
		return bad
	var found: Array = []
	for name in DirAccess.get_files_at(root.path_join(game).path_join(map_id)):
		if name.ends_with(".json"):
			found.append(name.trim_suffix(".json"))
	return DotResult.success(sort_versions(found))


func remove(game: String, map_id: String, map_version: String) -> DotResult:
	var bad := check_key(game, map_id, map_version)
	if bad != null:
		return bad
	var path := _path(game, map_id, map_version)
	if not FileAccess.file_exists(path):
		return DotResult.fail(NOT_FOUND, "No data for %s %s." % [map_id, map_version])
	if DirAccess.remove_absolute(path) != OK:
		return DotResult.fail(DotError.CODE_IO, "Cannot remove %s." % path)
	DotWeb.sync_filesystem()
	return DotResult.success()


func _path(game: String, map_id: String, version: String) -> String:
	return root.path_join(game).path_join(map_id).path_join(version + ".json")
