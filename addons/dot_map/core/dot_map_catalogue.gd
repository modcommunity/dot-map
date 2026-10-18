@tool
class_name DotMapCatalogue
extends Resource

## Every map a server knows about, and the file an operator edits.
##
## [b]The catalogue is separate from the rotation on purpose.[/b] A server knows about
## two hundred maps and rotates through twelve of them; the other hundred and eighty
## still have leaderboards, are still nominatable, and still have to resolve when
## somebody links to one. Merging the two lists means removing a map from the rotation
## also removes it from the records — which is how a leaderboard nobody meant to
## delete disappears.
##
## Plain JSON, because on a community server the person who maintains this is a person
## with a text editor.

const CHANNEL := "map.catalogue"

const FORMAT_VERSION := 1

@export var maps: Array[DotMapDef] = []

## Free-form: who maintains it, where it came from.
@export var meta: Dictionary = {}

## Fast lookup by id. Rebuilt on every mutation rather than maintained.
var _by_id: Dictionary = {}

var _index: DotContentIndex = null
var _accepted_kinds: PackedStringArray = PackedStringArray()
var _followed: Array[StringName] = []


func add(map: DotMapDef) -> DotResult:
	if map == null:
		return DotResult.fail(DotError.CODE_INVALID, "No map to add.")

	var valid := map.validate()

	if not valid.ok:
		return valid

	if _by_id.is_empty() and not maps.is_empty():
		_reindex()

	if _by_id.has(map.id):
		# Replaced rather than refused: a catalogue reloaded after an edit should end
		# up with the edited entry, and a server operator adding a corrected line to
		# the bottom of the file means the corrected one.
		var existing: DotMapDef = _by_id[map.id]
		maps[maps.find(existing)] = map
		_by_id[map.id] = map
		return DotResult.success(map)

	maps.append(map)
	_by_id[map.id] = map

	return DotResult.success(map)


## Add a delivered map by its pack key (see [method DotMapDef.from_content_key]), with
## the scene inside the pack the game loads for it. The usual way to turn a game
## descriptor's `maps:` list into a catalogue:
##
## [codeblock]
## for key in server.games.current_maps():
##     catalogue.add_delivered(key, "map.tscn")
## [/codeblock]
func add_delivered(key: String, scene: String) -> DotResult:
	var map := DotMapDef.from_content_key(key, scene)

	if map == null:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"A delivered map is named <owner>/<map id>@<version>.",
			key
		)

	return add(map)


## Follow a [DotContentIndex]: every map entry of a mounted pack, in the index's current
## session, becomes a [DotMapDef] here, and the rows are rebuilt whenever a pack arrives or the
## session changes. This is how a Workshop subscription reaches the map menu without the menu
## naming a pack.
##
## [param accepted_kinds] is the game's [code]accepts.map_kinds[/code]. [b]Empty means none,
## not any[/b]: the Workshop is opt-in per game, so a game that states no kinds must not have a
## map pack it cannot load pushed into its menu. [code]"*"[/code] accepts every kind. An entry's
## [code]map_kind[/code] is an open set; one this game does not accept is left in the index and
## offered to nobody.
##
## A map the catalogue already holds under the same id (the game's own, an operator's) always
## wins: a pack cannot replace a map by claiming its id. Nothing is ever removed from the index,
## so a session change drops this catalogue's followed rows and re-adds the visible ones.
func follow_content(index: DotContentIndex, accepted_kinds: PackedStringArray = PackedStringArray()) -> void:
	unfollow_content()
	if index == null:
		return
	_index = index
	_accepted_kinds = accepted_kinds
	index.pack_added.connect(_on_index_pack_added)
	index.session_changed.connect(_on_index_session_changed)
	refresh_content()


## Stop following. The rows already added stay until the next refresh; call
## [method refresh_content] afterwards to drop them.
func unfollow_content() -> void:
	if _index != null:
		if _index.pack_added.is_connected(_on_index_pack_added):
			_index.pack_added.disconnect(_on_index_pack_added)
		if _index.session_changed.is_connected(_on_index_session_changed):
			_index.session_changed.disconnect(_on_index_session_changed)
	_index = null
	_drop_followed()


## Rebuild the followed rows from the index now. Needed after
## [method DotContentIndex.tag_pack], which adds a session to a pack without announcing it.
func refresh_content() -> void:
	_drop_followed()
	if _index == null:
		return
	for entry in _index.entries(&"map"):
		var map := _def_from_entry(entry)
		if map == null:
			continue
		if get_map(map.id) != null:
			DotLog.debug(CHANNEL, "a pack map lost its id to an existing map", {
				"id": String(map.id), "pack": entry.content_id
			})
			continue
		if add(map).ok:
			_followed.append(map.id)


func _drop_followed() -> void:
	for id in _followed:
		var held := get_map(id)
		# Only a row this follower made; an operator may have replaced the id since.
		if held != null and held.entry_key != "":
			remove(id)
	_followed.clear()


func _on_index_pack_added(_pack: Dictionary, _entries: Array[DotContentEntry]) -> void:
	refresh_content()


func _on_index_session_changed(_session: StringName) -> void:
	refresh_content()


func _def_from_entry(entry: DotContentEntry) -> DotMapDef:
	var raw_kind := str(entry.raw.get("map_kind", ""))
	if raw_kind == "" or not (_accepted_kinds.has("*") or _accepted_kinds.has(raw_kind)):
		return null

	var map := DotMapDef.new()
	map.id = StringName(entry.id)
	map.version = entry.version if DotSemVer.parse(entry.version).valid else "1.0.0"
	map.display_name = entry.name
	map.kind = StringName(raw_kind)
	map.scene_path = entry.path("scene")
	map.zones_path = entry.path("zones")
	map.content_id = StringName(entry.content_id)
	map.content_version = entry.version
	map.tier = clampi(int(entry.raw.get("tier", 1)), 1, 10)
	map.min_players = maxi(int(entry.raw.get("min_players", 0)), 0)
	map.max_players = maxi(int(entry.raw.get("max_players", 0)), 0)
	map.meta = entry.meta.duplicate(true)
	map.pack_title = entry.pack_title if entry.pack_title != "" else entry.content_id
	map.entry_key = entry.key

	var valid := map.validate()
	if not valid.ok:
		DotLog.debug(CHANNEL, "a pack map was refused", {
			"key": entry.key, "why": valid.error.message
		})
		return null
	return map


func remove(id: StringName) -> bool:
	_reindex()

	if not _by_id.has(id):
		return false

	maps.erase(_by_id[id])
	_by_id.erase(id)

	return true


func get_map(id: StringName) -> DotMapDef:
	if _by_id.size() != maps.size():
		_reindex()

	var found: Variant = _by_id.get(id)
	return found if found is DotMapDef else null


func has(id: StringName) -> bool:
	return get_map(id) != null


func size() -> int:
	return maps.size()


func _reindex() -> void:
	_by_id.clear()

	for map in maps:
		_by_id[map.id] = map


## Maps of one kind that may be offered at this player count.
##
## [param kind] of [code]&""[/code] means any.
func available(kind: StringName = &"", players: int = 0) -> Array[DotMapDef]:
	var out: Array[DotMapDef] = []

	for map in maps:
		if not map.available_for(players):
			continue
		if kind != &"" and map.kind != kind:
			continue
		out.append(map)

	return out


## Maps whose id or display name contains [param text], case-insensitively.
##
## An exact id match is returned alone and first. [b]Not merely an ordering
## nicety.[/b] A player typing the full name of a map they want must get that map: on
## a server with [code]surf_tidewater[/code] and [code]surf_tidewater2[/code], a substring
## search returns both and whatever picks the first has chosen for them.
func search(text: String, limit: int = 20) -> Array[DotMapDef]:
	var needle := text.strip_edges().to_lower()
	var out: Array[DotMapDef] = []

	if needle == "":
		return out

	var exact := get_map(StringName(needle))

	if exact != null:
		out.append(exact)
		return out

	for map in maps:
		if out.size() >= limit:
			break

		if (
			String(map.id).to_lower().contains(needle)
			or map.display_name.to_lower().contains(needle)
		):
			out.append(map)

	return out


## Problems that make the catalogue unusable. Empty means it is fine.
func problems() -> PackedStringArray:
	var out := PackedStringArray()
	var seen := {}

	for map in maps:
		var valid := map.validate()

		if not valid.ok:
			out.append("%s: %s" % [String(map.id), valid.error.message])

		if seen.has(map.id):
			out.append("%s appears twice" % String(map.id))

		seen[map.id] = true

	return out


# --- Serialisation ---------------------------------------------------------

func to_dictionary() -> Dictionary:
	var list: Array = []

	for map in maps:
		list.append(map.to_dictionary())

	return {"format": FORMAT_VERSION, "meta": meta, "maps": list}


func to_json(pretty: bool = true) -> String:
	return JSON.stringify(to_dictionary(), "  " if pretty else "")


static func from_dictionary(data: Dictionary) -> DotResult:
	var format := int(data.get("format", 0))

	if format > FORMAT_VERSION:
		return DotResult.fail(
			DotError.CODE_VERSION,
			"That catalogue was written by a newer version of dot-map.",
			"format %d, this build reads %d" % [format, FORMAT_VERSION]
		)

	var catalogue := DotMapCatalogue.new()

	var meta_value: Variant = data.get("meta", {})
	catalogue.meta = meta_value if meta_value is Dictionary else {}

	var list_value: Variant = data.get("maps", [])

	if not (list_value is Array):
		return DotResult.fail(DotError.CODE_PARSE, "The maps key is not a list.")

	var refused := PackedStringArray()

	for entry in (list_value as Array):
		if not (entry is Dictionary):
			continue

		var map := DotMapDef.from_dictionary(entry)
		var added := catalogue.add(map)

		if not added.ok:
			# One bad entry does not condemn the file. A server with a hundred and
			# ninety-nine good maps and one typo should boot on the hundred and
			# ninety-nine — and say which one it dropped, loudly, rather than
			# refusing to start with an error nobody can locate.
			refused.append("%s: %s" % [String(map.id), added.error.message])

	if not refused.is_empty():
		DotLog.warn(CHANNEL, "some catalogue entries were dropped", {
			"count": refused.size(), "entries": ", ".join(refused)
		})

	return DotResult.success(catalogue)


static func from_json(text: String) -> DotResult:
	var parsed: Variant = JSON.parse_string(text)

	if not (parsed is Dictionary):
		return DotResult.fail(
			DotError.CODE_PARSE, "A map catalogue must be a JSON object."
		)

	return from_dictionary(parsed)


static func load_json(path: String) -> DotResult:
	if not FileAccess.file_exists(path):
		return DotResult.fail(DotError.CODE_IO, "No catalogue there.", path)

	var file := FileAccess.open(path, FileAccess.READ)

	if file == null:
		return DotResult.failure(
			DotError.from_engine(FileAccess.get_open_error(), path)
		)

	var text := file.get_as_text()
	file.close()

	return from_json(text).wrap("Could not read %s." % path)


func save_json(path: String) -> DotResult:
	var directory := path.get_base_dir()

	if directory != "" and not DirAccess.dir_exists_absolute(directory):
		var made := DirAccess.make_dir_recursive_absolute(directory)
		if made != OK:
			return DotResult.failure(DotError.from_engine(made, directory))

	var file := FileAccess.open(path, FileAccess.WRITE)

	if file == null:
		return DotResult.failure(
			DotError.from_engine(FileAccess.get_open_error(), path)
		)

	file.store_string(to_json())
	file.close()

	DotWeb.sync_filesystem()

	return DotResult.success(null)


func describe() -> Dictionary:
	var kinds := {}
	var local := 0

	for map in maps:
		kinds[String(map.kind)] = int(kinds.get(String(map.kind), 0)) + 1
		if map.is_local():
			local += 1

	return {
		"maps": maps.size(),
		"kinds": kinds,
		"in_build": local,
		"delivered": maps.size() - local,
	}


func _to_string() -> String:
	return "DotMapCatalogue(%d maps)" % maps.size()
