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
## a server with [code]surf_kitsune[/code] and [code]surf_kitsune2[/code], a substring
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
