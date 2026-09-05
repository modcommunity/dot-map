@tool
class_name DotMapDef
extends Resource

## One map, as an entry in a catalogue rather than as a build.
##
## [b]This class is the answer to "how do we ship a hundred surf maps".[/b] The
## obvious approach — one Godot project per map — is what a first look at the engine
## suggests and it is wrong in a way that only becomes obvious at map forty: a
## hundred projects is a hundred export pipelines, a hundred copies of every addon, a
## hundred version numbers, and a player who has to download a whole game to try a
## map. Worse, the records are then per-project, and a "server" is a thing that can
## only ever run one map.
##
## So: [b]one game, many maps, and a map is content.[/b] A map is an id, a version, a
## scene path and — optionally — a dot-cloud pack the scene lives inside. The server
## switches between them under live players; a client downloads the one it needs. It
## is how every game in this genre has worked for twenty-five years, and the shape the
## rest of the family was already built for: dot-cloud namespaces content by
## [code]id/version[/code] precisely because a mounted pack can never be unmounted, and
## dot-server already knows how to change what it is running.
##
## [codeblock]
## var map := DotMapDef.new()
## map.id = &"surf_beginner"
## map.version = "1.2.0"
## map.scene_path = "res://maps/surf_beginner/map.tscn"
## map.zones_path = "res://maps/surf_beginner/zones.json"
## map.tier = 2
## [/codeblock]

## What kind of map this is, so a rotation can be filtered.
##
## StringNames rather than an enum because a game invents its own: this family should
## not have an opinion about whether "climb" is a genre.
const KIND_SURF := &"surf"
const KIND_BHOP := &"bhop"
const KIND_KZ := &"kz"
const KIND_RACE := &"race"
const KIND_ARENA := &"arena"
const KIND_SANDBOX := &"sandbox"

@export_group("Identity")

## Stable id. Lower case, no spaces. This is what records are filed under.
##
## [b]Never renamed.[/b] A record names its map by this, so changing it orphans every
## time ever set. Change [member display_name] instead, which nothing keys on.
@export var id: StringName = &""

## Semantic version of the map's content.
##
## [b]Part of the content's address, not decoration.[/b] dot-cloud namespaces a pack
## by [code]id/version[/code] because a mounted resource pack can never be unmounted
## on any platform — so a new version of a map is a new mount rather than a
## replacement, and both can be present at once. It is also what tells a records table
## that the geometry changed.
@export var version: String = "1.0.0"

@export var display_name: String = ""

@export var author: String = ""

@export_multiline var description: String = ""

## What kind of map. See [constant KIND_SURF] and friends.
@export var kind: StringName = &"surf"

@export_group("Difficulty")

## 1..10, feeding the ranking points. See [code]DotTimerStyle.points_for[/code].
##
## Kept on the map rather than derived from times, because a new map has no times and
## the first player on it should still earn what it is worth. A game that wants to
## re-tier from measured completion rates overwrites this.
@export_range(1, 10, 1) var tier: int = 1

## Rough length in seconds, for a rotation that wants to avoid a run of long maps.
@export_range(0, 3600, 1) var expected_seconds: int = 0

@export_group("Content")

## Where the map's scene is, once its content is available.
##
## [b]A path inside the pack, not a path on this machine.[/b] When the map ships in
## the build this is an ordinary [code]res://[/code] path; when it is delivered, it is
## the path the pack mounts at, which dot-cloud makes the same string on every
## machine. That is the whole reason the loader goes through the cloud client rather
## than resolving a file itself.
@export var scene_path: String = ""

## The map's zone file, for a timed map. Empty when the map has no timer.
@export var zones_path: String = ""

## The dot-cloud content id this map lives in, or empty when it ships in the build.
##
## A separate field from [member id] because several maps can share one pack — a map
## pack is exactly that — and because a map that ships in the build has no pack at
## all.
@export var content_id: StringName = &""

## The pack version to mount. Defaults to [member version] when empty.
@export var content_version: String = ""

## Where this map's manifest is, when it is not where the cloud client would look.
##
## [b]Normally empty, and that is the point.[/b] A catalogue of a hundred maps should
## not repeat the same CDN hostname a hundred times, so the loader asks the cloud client
## for the content by [member content_id] and [member content_version] and the client
## builds the URL from its own configured bases. This is the escape hatch for the map
## that lives somewhere else — a community pack on a different host, a map served from
## the machine it was built on — and it takes precedence over anything derived.
@export var manifest_url: String = ""

## Optional content groups to fetch with the pack. Empty fetches only what is required.
##
## Matches [DotCloudFile.groups]: a map that ships high-resolution textures or a
## commentary track as an optional group names it here, and a client that does not want
## them fetches less.
@export var content_groups: PackedStringArray = PackedStringArray()

@export_group("Rotation")

## Whether this map may be chosen by a vote or a rotation.
##
## Off for a lobby, a test map, or one that is broken but whose records should stay
## readable. Deliberately separate from deleting the entry: removing a map from the
## catalogue also removes the leaderboard nobody asked to lose.
@export var enabled: bool = true

## Players below this many, and the map is not offered.
##
## A forty-slot arena map on a server with three people on it is an empty map, and
## the vote that chose it is the reason the three of them leave.
@export_range(0, 128, 1) var min_players: int = 0

## Players above this many, and the map is not offered.
@export_range(0, 128, 1) var max_players: int = 0

## A permission the player needs to nominate it, or empty for anybody.
@export var nominate_permission: String = ""

## Free-form, for whatever a game keeps about a map.
@export var meta: Dictionary = {}


func effective_content_version() -> String:
	return content_version if content_version != "" else version


func name_or_id() -> String:
	return display_name if display_name != "" else String(id)


## Whether the map ships inside the game's own build.
func is_local() -> bool:
	return content_id == &""


## Whether the map may be offered at this player count.
func available_for(players: int) -> bool:
	if not enabled:
		return false

	if min_players > 0 and players < min_players:
		return false

	if max_players > 0 and players > max_players:
		return false

	return true


func validate() -> DotResult:
	if id == &"":
		return DotResult.fail(DotError.CODE_INVALID, "A map needs an id.")

	if String(id).strip_edges() != String(id) or String(id).contains(" "):
		return DotResult.fail(
			DotError.CODE_INVALID,
			"A map id may not contain spaces or leading whitespace.",
			String(id)
		)

	if scene_path == "":
		return DotResult.fail(
			DotError.CODE_INVALID, "A map needs a scene path.", String(id)
		)

	# `parse` always returns an object and reports the outcome on `valid`, so
	# checking for null here passes for every string ever written.
	if not DotSemVer.parse(version).valid:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"A map's version must be semantic.",
			"%s: %s" % [String(id), version]
		)

	if min_players > 0 and max_players > 0 and min_players > max_players:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"min_players is above max_players, so the map can never be offered.",
			String(id)
		)

	return DotResult.success(null)


func to_dictionary() -> Dictionary:
	var out := {
		"id": String(id),
		"version": version,
		"scene": scene_path,
		"kind": String(kind),
		"tier": tier,
	}

	# Sparse, so a catalogue of two hundred maps stays readable by whoever maintains
	# it — which on a community server is a person with a text editor.
	if display_name != "":
		out["name"] = display_name
	if author != "":
		out["author"] = author
	if description != "":
		out["description"] = description
	if zones_path != "":
		out["zones"] = zones_path
	if content_id != &"":
		out["content"] = String(content_id)
	if content_version != "":
		out["content_version"] = content_version
	if manifest_url != "":
		out["manifest_url"] = manifest_url
	if not content_groups.is_empty():
		out["content_groups"] = Array(content_groups)
	if expected_seconds > 0:
		out["seconds"] = expected_seconds
	if not enabled:
		out["enabled"] = false
	if min_players > 0:
		out["min_players"] = min_players
	if max_players > 0:
		out["max_players"] = max_players
	if nominate_permission != "":
		out["nominate_permission"] = nominate_permission
	if not meta.is_empty():
		# Duplicated, not handed out: a Dictionary is a reference in GDScript, so
		# returning this one lets whoever serialises a map edit the map.
		out["meta"] = meta.duplicate(true)

	return out


static func from_dictionary(data: Dictionary) -> DotMapDef:
	var map := DotMapDef.new()

	map.id = StringName(str(data.get("id", "")))
	map.version = str(data.get("version", "1.0.0"))
	map.scene_path = str(data.get("scene", ""))
	map.zones_path = str(data.get("zones", ""))
	map.kind = StringName(str(data.get("kind", "surf")))
	map.tier = clampi(int(data.get("tier", 1)), 1, 10)
	map.display_name = str(data.get("name", ""))
	map.author = str(data.get("author", ""))
	map.description = str(data.get("description", ""))
	map.content_id = StringName(str(data.get("content", "")))
	map.content_version = str(data.get("content_version", ""))
	map.manifest_url = str(data.get("manifest_url", ""))

	var groups_value: Variant = data.get("content_groups", [])
	if groups_value is Array:
		for group in (groups_value as Array):
			map.content_groups.append(str(group))
	map.expected_seconds = int(data.get("seconds", 0))
	map.enabled = bool(data.get("enabled", true))
	map.min_players = int(data.get("min_players", 0))
	map.max_players = int(data.get("max_players", 0))
	map.nominate_permission = str(data.get("nominate_permission", ""))

	var meta_value: Variant = data.get("meta", {})
	map.meta = (
		(meta_value as Dictionary).duplicate(true) if meta_value is Dictionary else {}
	)

	return map


func describe() -> Dictionary:
	return {
		"id": String(id),
		"version": version,
		"kind": String(kind),
		"tier": tier,
		"local": is_local(),
		"scene": scene_path,
	}


func _to_string() -> String:
	return "DotMapDef(%s %s)" % [String(id), version]
