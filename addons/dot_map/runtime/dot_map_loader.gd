class_name DotMapLoader
extends RefCounted

## Turns a [DotMapDef] into a loaded scene, fetching its content first when it is not
## already here.
##
## [b]dot-cloud is not a dependency and is not named.[/b] The family rule — a script
## that mentions a [code]class_name[/code] the project does not have fails to parse
## and takes everything referencing it down too. So the cloud client is found in
## [DotRegistry] under [code]dot_cloud_client[/code] and its methods are called by
## name. A game that ships every map in its build never installs dot-cloud and this
## works unchanged; a game that delivers maps installs it and this starts fetching.
##
## [b]That indirection has bitten this family before[/b] and the lesson is in the
## registry lookup rather than in a comment: [code]DotCloudClient[/code] once failed
## to publish itself under that name, four call sites across two addons all found
## null, and every one of them treated an absent cloud as "this deployment ships its
## content in the build" — which is a legitimate configuration and therefore
## indistinguishable from the bug. So [member require_cloud] exists: a deployment that
## KNOWS its maps are delivered can say so, and get a loud failure instead of a
## mysterious one.
##
## [codeblock]
## var loaded := await loader.load_map(map_def)
## if loaded.ok:
##     var scene: PackedScene = loaded.value
## [/codeblock]

const CHANNEL := "map.loader"

## The registry name dot-cloud publishes its client under.
const CLOUD_SERVICE := &"dot_cloud_client"

## Fail rather than fall back to the disk when there is no cloud client.
##
## For a deployment whose maps are all delivered: without it, a missing cloud client
## looks exactly like a map that ships in the build, and the error surfaces as a scene
## that will not load rather than as a subsystem that is not installed.
var require_cloud: bool = false

## Seconds a content fetch may take before it is abandoned.
##
## Bounded because a server switching maps has players waiting on it: an unbounded
## fetch against a CDN having a bad day is a server that appears to have hung.
var fetch_timeout: float = 120.0

## Diagnostics.
var maps_loaded: int = 0
var packs_fetched: int = 0


## Whether a map's content is already available.
##
## For a client deciding whether to show a progress bar, and for a server deciding
## whether it can switch immediately.
func is_ready(map: DotMapDef) -> bool:
	if map == null:
		return false

	if map.is_local():
		return ResourceLoader.exists(map.scene_path)

	var cloud := _cloud()

	if cloud == null:
		return ResourceLoader.exists(map.scene_path)

	if not cloud.has_method("is_mounted"):
		return ResourceLoader.exists(map.scene_path)

	return bool(
		cloud.call("is_mounted", map.content_id, map.effective_content_version())
	)


## Fetches a map's content if needed and loads its scene.
##
## Returns the [PackedScene]. Instantiating it and putting it in the tree is the
## host's business — a loader that added it to a tree would have to know which one.
func load_map(map: DotMapDef) -> DotResult:
	if map == null:
		return DotResult.fail(DotError.CODE_INVALID, "No map to load.")

	var valid := map.validate()

	if not valid.ok:
		return valid

	if not map.is_local():
		var fetched := await ensure_content(map)

		if not fetched.ok:
			return fetched.wrap("Could not get %s's content." % String(map.id))

	if not ResourceLoader.exists(map.scene_path):
		return DotResult.fail(
			DotError.CODE_IO,
			"The map's scene is not there.",
			"%s: %s" % [String(map.id), map.scene_path]
		)

	var scene: Resource = load(map.scene_path)

	if not (scene is PackedScene):
		return DotResult.fail(
			DotError.CODE_INVALID,
			"A map's scene path must point at a PackedScene.",
			"%s: %s" % [String(map.id), map.scene_path]
		)

	maps_loaded += 1

	return DotResult.success(scene)


## Makes sure a delivered map's content is mounted.
##
## [b]A mounted pack can never be unmounted, on any platform.[/b] That is the
## constraint dot-cloud is built around and it decides the shape of this: content is
## namespaced by id and version, so a new version of a map is a new mount rather than
## a replacement, and a server can hold two versions at once while players finish
## their runs on the old one.
func ensure_content(map: DotMapDef) -> DotResult:
	var cloud := _cloud()

	if cloud == null:
		if require_cloud:
			return DotResult.fail(
				DotError.CODE_STATE,
				"This deployment delivers its maps and dot-cloud is not installed.",
				"looked for %s in DotRegistry" % String(CLOUD_SERVICE)
			)

		# The ambiguous case, said out loud. An absent cloud is a legitimate
		# configuration — the maps ship in the build — and is also exactly what a
		# cloud client that failed to register looks like.
		DotLog.debug(CHANNEL, "no cloud client; assuming the map is in the build", {
			"map": String(map.id), "content": String(map.content_id)
		})

		return DotResult.success(false)

	if not cloud.has_method("ensure"):
		return DotResult.fail(
			DotError.CODE_UNSUPPORTED,
			"The registered cloud client does not speak the content interface.",
			"no ensure() on %s" % cloud.get_class()
		)

	var version := map.effective_content_version()

	DotLog.info(CHANNEL, "fetching map content", {
		"map": String(map.id),
		"content": String(map.content_id),
		"version": version,
		"url": map.manifest_url if map.manifest_url != "" else "(derived)",
	})

	# [b]The contract, spelled out, because both ends of it are duck-typed:[/b]
	# [code]ensure(content_id, version, groups, manifest_url) -> DotResult[/code], with
	# the last two optional. It is what [code]DotCloudClient[/code] provides — and for
	# a long time it was not: this addon has called `ensure` and `is_mounted` since it
	# was written and dot-cloud offered `acquire` and `is_ready`, which take a URL and
	# an [code]id@version[/code] key. The two ends had never met, so every delivered
	# map failed with the refusal above, and no suite could see it because the only
	# loader test here runs with no cloud client at all — the branch that falls back to
	# the disk and passes.
	var result: Variant = await cloud.call(
		"ensure", map.content_id, version, map.content_groups, map.manifest_url
	)

	if result is DotResult:
		var typed: DotResult = result

		if typed.ok:
			packs_fetched += 1

		return typed

	# A cloud client that returned something else is a configuration error rather
	# than a fetch failure, and saying which is what makes it findable.
	return DotResult.fail(
		DotError.CODE_INTERNAL,
		"The cloud client returned something that is not a DotResult.",
		str(result)
	)


## The map's zone set, if it has one.
##
## Loaded through the same path as the scene and after the same content fetch, so a
## delivered map's zones come out of its pack rather than off the server's disk.
## Returns a success carrying null when the map has no zone file, because a map
## without a timer is normal and not an error.
func load_zones(map: DotMapDef) -> DotResult:
	if map == null or map.zones_path == "":
		return DotResult.success(null)

	if not FileAccess.file_exists(map.zones_path):
		return DotResult.fail(
			DotError.CODE_IO,
			"The map's zone file is not there.",
			"%s: %s" % [String(map.id), map.zones_path]
		)

	var file := FileAccess.open(map.zones_path, FileAccess.READ)

	if file == null:
		return DotResult.failure(
			DotError.from_engine(FileAccess.get_open_error(), map.zones_path)
		)

	var text := file.get_as_text()
	file.close()

	# Returned as text rather than parsed. dot-timer is optional — this addon must
	# compile without it — so the host, which does have it, calls
	# DotTimerZoneSet.from_json. Naming the class here would make every map load in a
	# game without a timer fail to parse.
	return DotResult.success(text)


func _cloud() -> Object:
	return DotRegistry.get_service(CLOUD_SERVICE)


func describe() -> Dictionary:
	return {
		"cloud": _cloud() != null,
		"require_cloud": require_cloud,
		"maps_loaded": maps_loaded,
		"packs_fetched": packs_fetched,
	}
