class_name DotMapLocalMaps
extends RefCounted

## Converted maps dropped into a game by hand: a raw [code]dot-bsp-mesh[/code] folder ([code]<name>.json[/code], [code]<name>.bin[/code], [code]textures/[/code]) copied under a root, offered as "(local)" with no pack or manifest written.
## A [code].zip[/code] of such a folder under a root is unpacked once into [member zip_cache] (keyed by its hash) and offered the same way;
## [method accept_dropped] copies a folder or zip dragged onto the window into [constant DROP_ROOT] ([method watch_drops] wires it).
## Every entry is a plain dictionary ([method scan]); [method to_def] makes the catalogue row and [method spawns] the start points, generated from the hulls when the map names none.
## Internal only: a local map is never in a pack, so a server never names it and a client never fetches it.

const CHANNEL := "dot_map.local_maps"

## Appended to the map's own name for its id, so a local copy never replaces a shipped or delivered map of the same name.
const ID_SUFFIX := "_local"

## The name suffix of an internal original pack ([code]<map>_orig[/code]), drawn with its own textures when loaded locally.
const ORIG_MARK := "_orig"

## Appended to the title a menu prints.
const TAG := " (local)"

## The folder the converter writes inside a map's source folder; looked into when a whole map folder was copied.
const CONVERT_DIR := "convert"

## A zip with more entries than this is refused, not unpacked.
const ZIP_MAX_FILES := 20000

## Where a dropped folder or zip is copied.
const DROP_ROOT := "user://maps"

## Where zips are unpacked, one folder per zip hash; a hidden folder, so [method scan] never lists it as a map.
static var zip_cache := "user://maps/.zip_cache"

## zip path -> [code][size, mtime, hash][/code], so a zip is hashed once per change, not once per scan.
static var _zip_hashes := {}

## The id prefixes that say what a map is for; anything else is an arena map.
const KIND_PREFIXES := {
	"surf_": DotMapDef.KIND_SURF,
	"bhop_": DotMapDef.KIND_BHOP,
	"kz_": DotMapDef.KIND_KZ,
	"kz-": DotMapDef.KIND_KZ,
	"bkz_": DotMapDef.KIND_KZ,
	"xc_": DotMapDef.KIND_KZ,
	"gm_": DotMapDef.KIND_SANDBOX,
}

## Metres above the generated floor point a start is placed, so a capsule is not born in the floor.
const SPAWN_LIFT := 0.1


## Where local maps are looked for, in order: beside the addons of a project run from source, then the user data folder (the
## one that also works in an exported build). The first root that has an id wins.
static func roots() -> PackedStringArray:
	return PackedStringArray(["res://addons/maps", "user://maps"])


## Every local map under [param from] (default [method roots]), sorted by id: each folder ([method entry_at]) and each
## [code].zip[/code] ([method entry_in_zip]); hidden names are skipped. Each is [code]{id, name, prefix, dir, root, title, kind}[/code]
## (plus [code]zip[/code]); the mesh is not parsed, so a broken copy is found here and fails in [method open].
static func scan(from: PackedStringArray = PackedStringArray()) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen := {}
	for root in (roots() if from.is_empty() else from):
		if not DirAccess.dir_exists_absolute(root):
			continue
		var names := DirAccess.get_directories_at(root)
		names.sort()
		var zips := PackedStringArray()
		for file in DirAccess.get_files_at(root):
			if file.get_extension().to_lower() == "zip":
				zips.append(file)
		zips.sort()
		for folder in names + zips:
			if folder.begins_with("."):
				continue
			var path := root.path_join(folder)
			var entry := entry_in_zip(path) if folder.get_extension().to_lower() == "zip" and FileAccess.file_exists(path) else entry_at(path)
			if entry.is_empty() or seen.has(entry["id"]):
				continue
			entry["root"] = root
			seen[entry["id"]] = true
			out.append(entry)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
	return out


## The entry with [param id] (the [constant ID_SUFFIX] one [method scan] gives), or empty.
static func find(id: StringName, from: PackedStringArray = PackedStringArray()) -> Dictionary:
	for entry: Dictionary in scan(from):
		if str(entry["id"]) == String(id):
			return entry
	return {}


## The entry for one copied folder: the convert folder itself, or a map folder with [code]convert/[/code] inside. Empty when
## neither holds a [code]<name>.json[/code] beside its [code]<name>.bin[/code].
static func entry_at(folder: String) -> Dictionary:
	var dirs: Array[String] = [folder, folder.path_join(CONVERT_DIR)]
	for dir in dirs:
		var prefix := prefix_in(dir)
		if prefix.is_empty():
			continue
		var name := prefix.get_file()
		return {"id": name + ID_SUFFIX, "name": name, "prefix": prefix, "dir": dir,
				"title": _title(folder, dir, name) + TAG, "kind": kind_for(name)}
	return {}


## The entry for a [code].zip[/code] of a convert folder or a map folder (at its top or one folder down), unpacked into
## [member zip_cache] the first time this zip's bytes are seen; [code]zip[/code] holds the zip's path. Empty when it is no such zip.
static func entry_in_zip(zip_path: String) -> Dictionary:
	var dir := _unpacked(zip_path)
	if dir.is_empty():
		return {}
	var entry := _entry_under(dir)
	if not entry.is_empty():
		entry["zip"] = zip_path
	return entry


## Copies each dropped path into [param into]: a map folder, a convert folder, a [code].zip[/code] of either, or a
## [code].json[/code]/[code].bin[/code] (its folder is taken). A copy replaces an earlier one of the same name.
## Returns [code]{added: Array[Dictionary], errors: PackedStringArray}[/code]: the new entries, and one line per path that is
## not a map (nothing is copied for those). The game rescans its catalogue after.
static func accept_dropped(paths: PackedStringArray, into: String = DROP_ROOT) -> Dictionary:
	var added: Array[Dictionary] = []
	var errors := PackedStringArray()
	for raw in paths:
		var path := raw.simplify_path().rstrip("/")
		var ext := path.get_extension().to_lower()
		if FileAccess.file_exists(path) and (ext == "json" or ext == "bin"):
			path = path.get_base_dir()
			ext = ""
		var shown := path.get_file() if path.get_file() != "" else (raw if raw != "" else "(empty)")
		var entry := {}
		if path.is_empty():
			errors.append("%s: not a map folder or a .zip" % shown)
			continue
		if DirAccess.dir_exists_absolute(path):
			if _entry_under(path).is_empty():
				errors.append("%s: not a converted map (no <name>.json beside <name>.bin in it or in convert/)" % shown)
				continue
			var target := into.path_join(shown)
			var into_abs := ProjectSettings.globalize_path(into).simplify_path()
			var path_abs := ProjectSettings.globalize_path(path)
			if (into_abs + "/").begins_with(path_abs + "/"):
				errors.append("%s: holds the maps folder itself" % shown)
				continue
			if path_abs != ProjectSettings.globalize_path(target).simplify_path():
				_wipe(target)
				if _copy_tree(path, target) == 0:
					errors.append("%s: could not be copied into %s" % [shown, into])
					continue
			entry = _entry_under(target)
		elif FileAccess.file_exists(path) and ext == "zip":
			var why := _zip_problem(path)
			if not why.is_empty():
				errors.append("%s: %s" % [shown, why])
				continue
			var target := into.path_join(shown)
			DirAccess.make_dir_recursive_absolute(into)
			if ProjectSettings.globalize_path(path) != ProjectSettings.globalize_path(target).simplify_path() and DirAccess.copy_absolute(path, target) != OK:
				errors.append("%s: could not be copied into %s" % [shown, into])
				continue
			entry = entry_in_zip(target)
			if entry.is_empty():
				DirAccess.remove_absolute(target)
		else:
			errors.append("%s: not a map folder or a .zip" % shown)
			continue
		if entry.is_empty():
			errors.append("%s: the copy in %s is not a map" % [shown, into])
			continue
		entry["root"] = into
		added.append(entry)
	for line in errors:
		DotLog.warn(CHANNEL, "dropped %s" % line)
	for e in added:
		DotLog.info(CHANNEL, "dropped map added: %s" % str(e["id"]))
	return {"added": added, "errors": errors}


## Connects [param window]'s [signal Window.files_dropped] to [method accept_dropped]; [param on_result] gets its dictionary.
static func watch_drops(window: Window, on_result: Callable) -> void:
	window.files_dropped.connect(func(files: PackedStringArray) -> void: on_result.call(accept_dropped(files)))


## The mesh prefix in [param dir] ([code]<dir>/<name>[/code] for the first [code]<name>.bin[/code], by name, with a
## [code]<name>.json[/code] beside it), or empty.
static func prefix_in(dir: String) -> String:
	if not DirAccess.dir_exists_absolute(dir):
		return ""
	var files := DirAccess.get_files_at(dir)
	files.sort()
	for file in files:
		if file.get_extension() == "bin" and files.has(file.get_basename() + ".json"):
			return dir.path_join(file.get_basename())
	return ""


## What a map is for, from its name ([constant KIND_PREFIXES]); a game that knows better sets [member DotMapDef.kind] itself.
static func kind_for(name: String) -> StringName:
	var lower := name.to_lower()
	for prefix: String in KIND_PREFIXES:
		if lower.begins_with(prefix):
			return KIND_PREFIXES[prefix]
	return DotMapDef.KIND_ARENA


## [code]0.0.0-<12 hex>[/code] of the manifest's bytes, so a re-converted copy is a new version and a record set on the old
## brushes is not filed against the new ones. Empty when the manifest is gone.
static func version_of(entry: Dictionary) -> String:
	var path := str(entry.get("prefix", "")) + ".json"
	if not FileAccess.file_exists(path):
		return ""
	return "0.0.0-%s" % FileAccess.get_md5(path).substr(0, 12)


## The catalogue row for [param entry]: [member DotMapDef.scene_path] is the mesh manifest (there is no scene), the
## content id empty (it ships with nobody), and [member DotMapDef.kind] from [method kind_for].
static func to_def(entry: Dictionary) -> DotMapDef:
	var def := DotMapDef.new()
	def.id = StringName(str(entry["id"]))
	def.display_name = str(entry["title"])
	def.kind = entry["kind"]
	def.scene_path = str(entry["prefix"]) + ".json"
	var version := version_of(entry)
	if not version.is_empty():
		def.version = version
	def.description = "A local map from %s" % str(entry["dir"])
	return def


## True for an internal original pack: a map named [code]<map>_orig[/code] (what [code]dot-map-convert regen --orig-textures[/code] writes).
## Only a local map can be one; a pack, a zip or a manifest never is, so original textures are never published.
static func is_original(entry: Dictionary) -> bool:
	return str(entry.get("name", "")).to_lower().ends_with(ORIG_MARK)


## The surfaces builder to draw [param entry] with: the map's own textures ([member DotMapSurfaces.use_original_textures]) for an
## [method is_original] pack, the free replacements for any other local map. Pass it to [method DotMapSurfaces.world_material_for].
static func surfaces_for(entry: Dictionary) -> DotMapSurfaces:
	var surfaces := DotMapSurfaces.new()
	surfaces.use_original_textures = is_original(entry)
	return surfaces


## The map's mesh ([method DotMapBspMesh.load_prefix]): the format, hash and size checks are that reader's.
static func open(entry: Dictionary) -> DotResult:
	var res := DotMapBspMesh.load_prefix(str(entry.get("prefix", "")))
	if not res.ok:
		DotLog.warn(CHANNEL, "local map %s does not load: %s" % [str(entry.get("id", "")), str(res)])
	return res


## The start points: [code]{origin, yaw, team, classname, generated}[/code] in metres, from the manifest's
## [code]spawns[/code]; when it names none, one on top of the widest solid hull of the world, marked [code]generated[/code].
static func spawns(mesh: DotMapBspMesh) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s: Variant in mesh.manifest.get("spawns", []):
		if not s is Dictionary or not (s as Dictionary).get("at") is Array or ((s as Dictionary)["at"] as Array).size() < 3:
			continue
		var d: Dictionary = s
		var at: Array = d["at"]
		out.append({"origin": Vector3(float(at[0]), float(at[1]), float(at[2])), "yaw": float(d.get("yaw", 0.0)),
				"team": str(d.get("team", "any")), "classname": str(d.get("classname", "")), "generated": false})
	if out.is_empty():
		var floor_point: Variant = _widest_floor(mesh)
		if floor_point is Vector3:
			out.append({"origin": floor_point, "yaw": 0.0, "team": "any", "classname": "", "generated": true})
			DotLog.info(CHANNEL, "no spawns in %s, one generated at %s" % [mesh.source_path, str(floor_point)])
	return out


## Summary lines for a menu or a log.
static func describe_lines(entries: Array[Dictionary]) -> PackedStringArray:
	var out := PackedStringArray()
	for entry in entries:
		out.append("%s  %s  [%s]  %s" % [entry["id"], entry["title"], entry["kind"], entry["prefix"]])
	return out


## [method entry_at] for [param dir], or for the first map folder one level below (a zip of a folder, a dropped parent of one).
static func _entry_under(dir: String) -> Dictionary:
	var entry := entry_at(dir)
	if not entry.is_empty():
		return entry
	var subs := DirAccess.get_directories_at(dir)
	subs.sort()
	for sub in subs:
		if sub.begins_with(".") or sub == "__MACOSX":
			continue
		entry = entry_at(dir.path_join(sub))
		if not entry.is_empty():
			return entry
	return {}


## The zip's folder in [member zip_cache] (unpacked now if new), or empty for a zip that cannot be read or is unsafe.
static func _unpacked(zip_path: String) -> String:
	var key := _zip_hash(zip_path)
	if key.is_empty():
		return ""
	var dir := zip_cache.path_join(key)
	if FileAccess.file_exists(dir.path_join(".unpacked")):
		return dir
	var why := _zip_problem(zip_path)
	if not why.is_empty():
		DotLog.warn(CHANNEL, "%s: %s" % [zip_path, why])
		return ""
	var part := dir + ".part"
	_wipe(part)
	_wipe(dir)
	var zip := ZIPReader.new()
	if zip.open(zip_path) != OK:
		return ""
	for name in zip.get_files():
		if name.ends_with("/") or _skipped_in_zip(name):
			continue
		var out := part.path_join(name)
		DirAccess.make_dir_recursive_absolute(out.get_base_dir())
		var f := FileAccess.open(out, FileAccess.WRITE)
		if f == null:
			zip.close()
			_wipe(part)
			DotLog.warn(CHANNEL, "%s: cannot write %s" % [zip_path, out])
			return ""
		f.store_buffer(zip.read_file(name))
		f.close()
	zip.close()
	var marker := FileAccess.open(part.path_join(".unpacked"), FileAccess.WRITE)
	if marker == null:
		_wipe(part)
		return ""
	marker.store_string(zip_path)
	marker.close()
	if DirAccess.rename_absolute(part, dir) != OK:
		_wipe(part)
		return ""
	DotLog.info(CHANNEL, "unpacked %s into %s" % [zip_path, dir])
	return dir


## Why [param zip_path] is refused (it does not open, holds too many files, a name climbs out of its folder, or no mesh
## pair), or empty when it is fine to unpack.
static func _zip_problem(zip_path: String) -> String:
	var zip := ZIPReader.new()
	if zip.open(zip_path) != OK:
		return "not a readable zip"
	var names := zip.get_files()
	zip.close()
	if names.size() > ZIP_MAX_FILES:
		return "%d files, more than %d" % [names.size(), ZIP_MAX_FILES]
	var has := {}
	for name in names:
		if name.begins_with("/") or name.contains("\\") or name.contains(":") or name.split("/").has(".."):
			return "unsafe path in the zip: %s" % name
		if not _skipped_in_zip(name):
			has[name] = true
	for name: String in has:
		if name.get_extension().to_lower() == "bin" and has.has(name.get_basename() + ".json"):
			return ""
	return "no <name>.json beside <name>.bin in the zip"


static func _skipped_in_zip(name: String) -> bool:
	return name.begins_with("__MACOSX/") or name.get_file().begins_with("._")


## The first 16 hex of the zip's md5, remembered per path until its size or time changes; empty when it cannot be read.
static func _zip_hash(zip_path: String) -> String:
	var f := FileAccess.open(zip_path, FileAccess.READ)
	if f == null:
		return ""
	var size := f.get_length()
	f.close()
	var mtime := FileAccess.get_modified_time(zip_path)
	var known: Array = _zip_hashes.get(zip_path, [])
	if known.size() == 3 and int(known[0]) == size and int(known[1]) == mtime:
		return str(known[2])
	var md5 := FileAccess.get_md5(zip_path)
	if md5.is_empty():
		return ""
	_zip_hashes[zip_path] = [size, mtime, md5.substr(0, 16)]
	return md5.substr(0, 16)


static func _copy_tree(from_dir: String, to_dir: String) -> int:
	if DirAccess.make_dir_recursive_absolute(to_dir) != OK:
		return 0
	var count := 0
	for n in DirAccess.get_files_at(from_dir):
		if DirAccess.copy_absolute(from_dir.path_join(n), to_dir.path_join(n)) == OK:
			count += 1
	for d in DirAccess.get_directories_at(from_dir):
		count += _copy_tree(from_dir.path_join(d), to_dir.path_join(d))
	return count


## Removes [param dir] with everything in it, hidden names included (the [code].unpacked[/code] marker).
static func _wipe(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.include_hidden = true
	for sub in d.get_directories():
		_wipe(dir.path_join(sub))
	for n in d.get_files():
		DirAccess.remove_absolute(dir.path_join(n))
	DirAccess.remove_absolute(dir)


static func _title(folder: String, dir: String, name: String) -> String:
	var paths: Array[String] = [dir.path_join("addon.json"), folder.path_join("addon.json"), dir.get_base_dir().path_join("addon.json")]
	for path in paths:
		if not FileAccess.file_exists(path):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary and str((parsed as Dictionary).get("title", "")).strip_edges() != "":
			return str((parsed as Dictionary)["title"]).strip_edges()
	return name


## The top centre of the world's solid hull with the largest footprint, lifted by [constant SPAWN_LIFT]; null without one.
static func _widest_floor(mesh: DotMapBspMesh) -> Variant:
	var best: Variant = null
	var best_area := -1.0
	for hull: Dictionary in mesh.hull_shapes(DotMapBspMesh.WORLD, PackedStringArray(["solid"])):
		var points := (hull["shape"] as ConvexPolygonShape3D).points
		if points.is_empty():
			continue
		var box := AABB(points[0], Vector3.ZERO)
		for p in points:
			box = box.expand(p)
		var area := box.size.x * box.size.z
		if area > best_area:
			best_area = area
			best = Vector3(box.get_center().x, box.end.y + SPAWN_LIFT, box.get_center().z)
	if best is Vector3:
		return (best as Vector3) + mesh.model_origin(DotMapBspMesh.WORLD)
	return null
