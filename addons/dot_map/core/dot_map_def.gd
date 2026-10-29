@tool
class_name DotMapDef
extends Resource

## One map, as an entry in a catalogue rather than as a build: an id, a version, a scene path and, optionally, a dot-cloud pack the scene lives inside.
## One game with many maps as content, not one project per map: the server switches under live players and a client downloads the one it needs. dot-cloud namespaces content by [code]id/version[/code] because a mounted pack can never be unmounted.
## Fill [code]id[/code], [code]version[/code], [code]scene_path[/code], [code]zones_path[/code] and [code]tier[/code].

## What kind of map this is, so a rotation can be filtered. StringNames rather than an enum because a game
## invents its own: this family should not have an opinion about whether "climb" is a genre.
const KIND_SURF := &"surf"
const KIND_BHOP := &"bhop"
const KIND_KZ := &"kz"
const KIND_RACE := &"race"
const KIND_ARENA := &"arena"
const KIND_SANDBOX := &"sandbox"

@export_group("Identity")

## Stable id. Lower case, no spaces. This is what records are filed under. Never renamed. A record names its
## map by this, so changing it orphans every time ever set. Change [member display_name] instead, which
## nothing keys on.
@export var id: StringName = &""

## Semantic version of the map's content. Part of the content's address, not decoration. dot-cloud namespaces
## a pack by [code]id/version[/code] because a mounted resource pack can never be unmounted on any platform —
## so a new version of a map is a new mount rather than a replacement, and both can be present at once.
@export var version: String = "1.0.0"

@export var display_name: String = ""

@export var author: String = ""

@export_multiline var description: String = ""

## What kind of map. See [constant KIND_SURF] and friends.
@export var kind: StringName = &"surf"

@export_group("Difficulty")

## 1..10, feeding the ranking points. See [code]DotTimerStyle.points_for[/code]. Kept on the map rather than
## derived from times, because a new map has no times and the first player on it should still earn what it is
## worth. A game that wants to re-tier from measured completion rates overwrites this.
@export_range(1, 10, 1) var tier: int = 1

## Rough length in seconds, for a rotation that wants to avoid a run of long maps.
@export_range(0, 3600, 1) var expected_seconds: int = 0

@export_group("Content")

## Where the map's scene is, once its content is available. A path inside the pack, not a path on this
## machine. When the map ships in the build this is an ordinary [code]res://[/code] path; when it is
## delivered, it is the path the pack mounts at, which dot-cloud makes the same string on every machine.
@export var scene_path: String = ""

## The map's zone file, for a timed map. Empty when the map has no timer.
@export var zones_path: String = ""

## The dot-cloud content id this map lives in, or empty when it ships in the build. A separate field from
## [member id] because several maps can share one pack — a map pack is exactly that — and because a map that
## ships in the build has no pack at all.
@export var content_id: StringName = &""

## The pack version to mount. Defaults to [member version] when empty.
@export var content_version: String = ""

## Where this map's manifest is, when it is not where the cloud client would look. Normally empty, and that
## is the point.
@export var manifest_url: String = ""

## Optional content groups to fetch with the pack. Empty fetches only what is required. Matches
## [DotCloudFile.groups]: a map that ships high-resolution textures or a commentary track as an optional
## group names it here, and a client that does not want them fetches less.
@export var content_groups: PackedStringArray = PackedStringArray()

@export_group("Rotation")

## Whether this map may be chosen by a vote or a rotation. Off for a lobby, a test map, or one that is broken
## but whose records should stay readable. Deliberately separate from deleting the entry: removing a map from
## the catalogue also removes the leaderboard nobody asked to lose.
@export var enabled: bool = true

## Whether the server's ACTIVE rotation lists this map (maps.yml). Runtime state, never saved. Separate from
## [member enabled] on purpose: [member enabled] is the catalogue author's statement about the map, and a
## rotation file that flipped it would undo an operator's `"enabled": false` the moment the map was listed.
var in_rotation: bool = true

## The settings the active rotation's entry gives this map (`{waves: "easy", profile: "night"}`),
## opaque to dot-map. Runtime state set by [DotMapRotationFile.apply], never saved; empty for a bare entry.
var play: Dictionary = {}


## The values to try for [param key], best first: [param override] (a server command such as
## `sv_waves`), then the rotation entry's, then [param fallback] (the map document's, the game's
## default). Empty ones are skipped, so a game tries each and warns on a missing id instead of failing.
func play_candidates(key: String, override: Variant = "", fallback: Variant = "") -> Array:
	var out: Array = []
	for v: Variant in [override, play.get(key, ""), fallback]:
		if str(v) != "" and not out.has(v):
			out.append(v)
	return out

## Players below this many, and the map is not offered. A forty-slot arena map on a server with three people
## on it is an empty map, and the vote that chose it is the reason the three of them leave.
@export_range(0, 128, 1) var min_players: int = 0

## Players above this many, and the map is not offered.
@export_range(0, 128, 1) var max_players: int = 0

## A permission the player needs to nominate it, or empty for anybody.
@export var nominate_permission: String = ""

## Free-form, for whatever a game keeps about a map.
@export var meta: Dictionary = {}

## The title of the Workshop pack this map came from, or "" for a map the game or its server
## names. Runtime only (never written to a catalogue file): a menu marks a map with it so a
## player can tell their own subscription from the game's maps. [method label] is that mark.
var pack_title: String = ""

## The [DotContentEntry] key this map was built from, or "" for any other map. A catalogue
## that follows a content index uses it to tell its own rows from the operator's.
var entry_key: String = ""


## A map out of a delivered pack key, `<owner>/<map id>@<version>` -- what a game descriptor's `maps:` list
## holds once the server has installed the game (dot-server's DotGameDescriptor.maps,
## DotGameManager.current_maps). Null for a key that is not that.
static func from_content_key(key: String, scene: String = "") -> DotMapDef:
	var at := key.rfind("@")
	if at <= 0 or at == key.length() - 1:
		return null

	var content := key.substr(0, at).strip_edges()
	var content_version_part := key.substr(at + 1).strip_edges()
	var cut := content.rfind("/")

	if cut <= 0 or cut == content.length() - 1:
		return null

	var map := DotMapDef.new()
	map.id = StringName(content.substr(cut + 1))
	map.content_id = StringName(content)
	map.content_version = content_version_part
	map.scene_path = scene

	if scene != "" and not scene.contains("://"):
		map.scene_path = "res://dot_cloud/%s/%s/%s" % [content, content_version_part, scene.trim_prefix("/")]

	return map


func effective_content_version() -> String:
	return content_version if content_version != "" else version


func name_or_id() -> String:
	return display_name if display_name != "" else String(id)


## What a menu, ballot or list prints: the name, marked with the pack when a subscription
## provided it. A map the game names is printed bare.
func label() -> String:
	if pack_title == "":
		return name_or_id()
	return "%s [%s]" % [name_or_id(), pack_title]


## Whether the map ships inside the game's own build.
func is_local() -> bool:
	return content_id == &""


## Whether the map may be offered at this player count.
func available_for(players: int) -> bool:
	if not enabled or not in_rotation:
		return false

	return available_for_players(players)


## The player-count half of [method available_for], for a list that shows maps the
## rotation does not play.
func available_for_players(players: int) -> bool:
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
