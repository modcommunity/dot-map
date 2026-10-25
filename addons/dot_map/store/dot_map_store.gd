class_name DotMapStore
extends RefCounted
## Finds the shared PBR and model stores of a converted map, shipped as a dot-cloud slice (`licence.store_pack`) plus the shared slices it names.

const CHANNEL := "dot_map.store"
## What the one warning tells a developer to do; the steps are in docs/content.md#without-the-slices.
const HOW_TO_GET := "run the maps repository's tools/stage_stores.sh, or point the game's dot-cloud at a server that publishes them (dot-map docs/content.md#without-the-slices)"

## Root slice id to `{ids, why}` for every map whose slices could not be had, so [method notice] can say so.
static var _unfetched: Dictionary = {}
## Root slice ids already warned about: one WARN per map per process.
static var _warned: Dictionary = {}


## The `{id, version}` slice a map manifest's licence block names, or {} when it ships none.
static func pack_of(licence: Dictionary) -> Dictionary:
	var p: Variant = licence.get("store_pack", {})
	if p is Dictionary and str(p.get("id", "")) != "" and str(p.get("version", "")) != "":
		return p
	return {}


## Where the slice is mounted on [param cloud] (a DotCloudClient), or "" when it is not mounted or the map names none.
static func mount_dir(licence: Dictionary, cloud: Object) -> String:
	var p := pack_of(licence)
	if p.is_empty() or cloud == null:
		return ""
	var prefix: String = cloud.call("dependency_prefix", StringName(str(p["id"])), str(p["version"]))
	return prefix.trim_suffix("/")


## Every folder a map's art is mounted at: its own slice first, then each shared slice it names (`store_pack.shared`) that is mounted.
static func mount_dirs(licence: Dictionary, cloud: Object) -> PackedStringArray:
	var out := PackedStringArray()
	var own := mount_dir(licence, cloud)
	if own.is_empty():
		return out
	out.append(own)
	for s: Variant in pack_of(licence).get("shared", []):
		if s is Dictionary:
			var prefix: String = cloud.call("dependency_prefix", StringName(str(s.get("id", ""))), str(s.get("version", "")))
			if not prefix.is_empty():
				out.append(prefix.trim_suffix("/"))
	return out


## Every slice a map names as `id@version`, its own first; empty when it names none.
static func slice_ids(licence: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var p := pack_of(licence)
	if p.is_empty():
		return out
	out.append("%s@%s" % [p["id"], p["version"]])
	for s: Variant in p.get("shared", []):
		if s is Dictionary:
			out.append("%s@%s" % [s.get("id", ""), s.get("version", "")])
	return out


## The slices of [param licence] that are not mounted on [param cloud] (all of them without a cloud).
static func missing(licence: Dictionary, cloud: Object) -> PackedStringArray:
	var out := PackedStringArray()
	var ids := slice_ids(licence)
	if ids.is_empty() or cloud == null or mount_dir(licence, cloud).is_empty():
		return ids
	for id in ids.slice(1):
		if str(cloud.call("dependency_prefix", StringName(id.get_slice("@", 0)), id.get_slice("@", 1))).is_empty():
			out.append(id)
	return out


## A short line for a load screen or credits when the map's art slices could not be had, else "".
static func notice(licence: Dictionary) -> String:
	var p := pack_of(licence)
	if p.is_empty() or not _unfetched.has(str(p["id"])):
		return ""
	return "Low-detail art: %d art slices not installed" % (_unfetched[str(p["id"])]["ids"] as PackedStringArray).size()


## Forgets what [method ensure] recorded (a test, or slices staged since).
static func reset() -> void:
	_unfetched.clear()
	_warned.clear()


## Downloads and mounts the slice when it is not, once per client (dot-cloud skips what it holds; an empty [param manifest_url] lets it resolve one). Ok with "" when
## the map ships none. A pack acquired with `--depends` has it already, so this is for a map loaded from a folder.
static func ensure(licence: Dictionary, cloud: Object, manifest_url: String = "") -> DotResult:
	var p := pack_of(licence)
	if p.is_empty():
		return DotResult.success("")
	if cloud == null:
		_unfetched[str(p["id"])] = {"ids": slice_ids(licence), "why": "no dot-cloud client"}
		_show(licence)
		return DotResult.success("")
	var dir := mount_dir(licence, cloud)
	if not dir.is_empty():
		_unfetched.erase(str(p["id"]))
		return DotResult.success(dir)
	var res: DotResult = await cloud.call("ensure", StringName(str(p["id"])), str(p["version"]), PackedStringArray(), manifest_url)
	if not res.ok:
		_unfetched[str(p["id"])] = {"ids": missing(licence, cloud), "why": res.error.message}
		_show(licence)
		return res.wrap("store slice %s@%s" % [p["id"], p["version"]])
	_unfetched.erase(str(p["id"]))
	return DotResult.success(mount_dir(licence, cloud))


## Puts [method notice] on the load screen of the game in progress, if it has a [DotLoadGate].
static func _show(licence: Dictionary) -> void:
	var gate := DotRegistry.get_service(DotLoadGate.SERVICE) as DotLoadGate
	if gate != null and not gate.is_open():
		gate.set_progress(gate.progress(), notice(licence))


## Points [param surfaces] (DotMapSurfaces) and [param world] (DotMapBspMesh) at a mounted slice. Returns whether it was.
static func apply(licence: Dictionary, cloud: Object, surfaces: Object, world: Object) -> bool:
	var dirs := mount_dirs(licence, cloud) if cloud != null else PackedStringArray()
	if dirs.is_empty():
		_report(licence, world)
		return false
	var pbr := PackedStringArray()
	var models := PackedStringArray()
	for d in dirs:
		pbr.append(d.path_join("pbr"))
		models.append(d.path_join("models"))
	if surfaces != null:
		surfaces.set("pbr_library", pbr[0])
		surfaces.set("pbr_libraries", pbr)
	if world != null:
		world.set("model_library", models[0])
		world.set("model_libraries", models)
	return true


## The one WARN for a map drawn without its slices, unless its folder holds the art (`licence.pbr_store` beside the pack, a converter's own tree).
static func _report(licence: Dictionary, world: Object) -> void:
	var p := pack_of(licence)
	if p.is_empty() or _warned.has(str(p["id"])):
		return
	if world != null and _folder_has_art(licence, str(world.get("source_path")).get_base_dir()):
		_unfetched.erase(str(p["id"]))
		return
	_warned[str(p["id"])] = true
	var got: Dictionary = _unfetched.get(str(p["id"]), {"ids": slice_ids(licence), "why": "never fetched"})
	_unfetched[str(p["id"])] = got
	DotLog.warn(CHANNEL, "a map's art slices are not installed; it is drawn with low-detail stand-ins (each face's own colour) and without library models. To get them: %s" % HOW_TO_GET,
			{"slices": ", ".join(got["ids"]), "why": got["why"]})


static func _folder_has_art(licence: Dictionary, dir: String) -> bool:
	var store := str(licence.get("pbr_store", ""))
	if store.is_empty() or dir.is_empty():
		return false
	for t: Variant in licence.get("textures", []):
		if t is Dictionary and str(t.get("kind", "")) == "pbr":
			var set_dir := dir.path_join(store).simplify_path().path_join(str(t.get("file", "")).get_file()).path_join(str(t.get("tier", "1k")))
			return DirAccess.dir_exists_absolute(set_dir)
	return false
