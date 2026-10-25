class_name DotMapStore
extends RefCounted
## Finds the shared PBR and model stores of a converted map, shipped as a dot-cloud slice (`licence.store_pack`) plus the shared slices it names.

const CHANNEL := "dot_map.store"


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


## Downloads and mounts the slice when it is not, once per client (dot-cloud skips what it holds; an empty [param manifest_url] lets it resolve one). Ok with "" when
## the map ships none. A pack acquired with `--depends` has it already, so this is for a map loaded from a folder.
static func ensure(licence: Dictionary, cloud: Object, manifest_url: String = "") -> DotResult:
	var p := pack_of(licence)
	if p.is_empty() or cloud == null:
		return DotResult.success("")
	var dir := mount_dir(licence, cloud)
	if not dir.is_empty():
		return DotResult.success(dir)
	var res: DotResult = await cloud.call("ensure", StringName(str(p["id"])), str(p["version"]), PackedStringArray(), manifest_url)
	if not res.ok:
		return res.wrap("store slice %s@%s" % [p["id"], p["version"]])
	return DotResult.success(mount_dir(licence, cloud))


## Points [param surfaces] (DotMapSurfaces) and [param world] (DotMapBspMesh) at a mounted slice. Returns whether it was.
static func apply(licence: Dictionary, cloud: Object, surfaces: Object, world: Object) -> bool:
	var dirs := mount_dirs(licence, cloud)
	if dirs.is_empty():
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
