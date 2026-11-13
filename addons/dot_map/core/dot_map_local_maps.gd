class_name DotMapLocalMaps
extends RefCounted

## Converted maps dropped into a game by hand: a raw [code]dot-bsp-mesh[/code] folder ([code]<name>.json[/code], [code]<name>.bin[/code], [code]textures/[/code]) copied under a root, offered as "(local)" with no pack, zip or manifest written.
## Every entry is a plain dictionary ([method scan]); [method to_def] makes the catalogue row and [method spawns] the start points, generated from the hulls when the map names none.
## Internal only: a local map is never in a pack, so a server never names it and a client never fetches it.

const CHANNEL := "dot_map.local_maps"

## Appended to the map's own name for its id, so a local copy never replaces a shipped or delivered map of the same name.
const ID_SUFFIX := "_local"

## Appended to the title a menu prints.
const TAG := " (local)"

## The folder the converter writes inside a map's source folder; looked into when a whole map folder was copied.
const CONVERT_DIR := "convert"

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


## Every local map under [param from] (default [method roots]), sorted by id. Each is
## [code]{id, name, prefix, dir, root, title, kind}[/code]; nothing is parsed, so a broken copy is found here and fails in [method open].
static func scan(from: PackedStringArray = PackedStringArray()) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen := {}
	for root in (roots() if from.is_empty() else from):
		if not DirAccess.dir_exists_absolute(root):
			continue
		var names := DirAccess.get_directories_at(root)
		names.sort()
		for folder in names:
			var entry := entry_at(root.path_join(folder))
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
