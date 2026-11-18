class_name DotMapDocDrop
extends RefCounted

## The acceptor for a game whose maps are DOCUMENTS (a JSON file of the game's own kind: spawns, nav, safe areas) rather than
## converted mesh folders. Hand [method accept] to [method DotMapDropIntake.add_acceptor]: it finds the documents in a dropped
## [code].json[/code], a folder (searched [param depth] folders down) or a [code].zip[/code] (read in place, nothing unpacked), and
## gives each to the game's [param take] callable, which checks it, stores it and joins the catalogue. The result is the
## [code]{added, errors}[/code] the intake wants, and [method lines] says it as "Added <title> (local)" / "Not a map: <reason>".
## The game keeps its own validation; nothing here knows a game's format beyond its [code]kind[/code] key.

const CHANNEL := "dot_map.doc_drop"

## The key a document names its kind by.
const KIND_KEY := "kind"

## Appended to a title a menu or a toast prints; the same tag as [constant DotMapLocalMaps.TAG].
const TAG := " (local)"

## A document in a zip larger than this many bytes is refused, not read; 0 is no limit.
static var max_doc_bytes := 16 * 1024 * 1024


## [code]{}[/code] when [param path] holds no document of [param kinds] and no refusal (the intake then refuses it as not this
## game's), else [code]{added: Array[Dictionary], errors: PackedStringArray}[/code]. [param take] is
## [code]func(doc: Dictionary, text: String, name: String, into: String) -> Dictionary[/code] and returns either
## [code]{added: <entry dictionary>}[/code] or [code]{error: "<why>"}[/code]. [param name] is the file's name (inside a zip too).
static func accept(path: String, into: String, kinds: PackedStringArray, depth: int, take: Callable) -> Dictionary:
	var found := documents_in(path, kinds, depth)
	var errors: PackedStringArray = found["errors"]
	var added: Array[Dictionary] = []
	var docs: Array = found["docs"]
	if docs.is_empty() and errors.is_empty():
		return {}
	for d: Dictionary in docs:
		var got: Dictionary = take.call(d["doc"], d["text"], d["name"], into)
		if str(got.get("error", "")) != "":
			errors.append("%s: %s" % [d["name"], got["error"]])
		elif got.get("added") is Dictionary:
			added.append(got["added"])
	return {"added": added, "errors": errors}


## Every document of [param kinds] in [param path]: [code]{docs: Array[{name, text, doc}], errors: PackedStringArray}[/code],
## sorted by name. [param path] is one document, a folder ([param depth] folders down, 0 is no limit) or a zip (every
## [code].json[/code] in it, at most [member max_doc_bytes] each; an unsafe name or a too-large one is an error line).
static func documents_in(path: String, kinds: PackedStringArray, depth: int) -> Dictionary:
	var docs: Array[Dictionary] = []
	var errors := PackedStringArray()
	var clean := path.rstrip("/")
	if FileAccess.file_exists(clean):
		if clean.get_extension().to_lower() == "zip":
			_from_zip(clean, kinds, docs, errors)
		elif clean.get_extension().to_lower() == "json":
			_add(docs, clean.get_file(), FileAccess.get_file_as_string(clean), kinds)
	elif DirAccess.dir_exists_absolute(clean):
		_collect(clean, depth if depth > 0 else -1, kinds, docs, errors)
	return {"docs": docs, "errors": errors}


## Writes [param text] to [code]<into>/<id>.json[/code] (the folder is made); the path, or empty after a warning.
static func write_doc(into: String, id: String, text: String) -> String:
	var made := DirAccess.make_dir_recursive_absolute(into)
	if made != OK:
		DotLog.warn(CHANNEL, "cannot make %s (%s)" % [into, error_string(made)])
		return ""
	var target := into.path_join(id + ".json")
	var out := FileAccess.open(target, FileAccess.WRITE)
	if out == null:
		DotLog.warn(CHANNEL, "cannot write %s (%s)" % [target, error_string(FileAccess.get_open_error())])
		return ""
	out.store_string(text)
	out.close()
	return target


## What to show for an intake result: "Added <title> (local). <hint>" for the maps added, then "Not a map: <reason>" for each
## refusal. An added entry's [code]title[/code] (else [code]name[/code], else [code]id[/code]) is printed.
static func lines(result: Dictionary, hint: String = "") -> PackedStringArray:
	var out := PackedStringArray()
	var titles := PackedStringArray()
	for entry: Variant in result.get("added", []):
		if entry is Dictionary:
			var e: Dictionary = entry
			var title := str(e.get("title", e.get("name", e.get("id", "?"))))
			titles.append(title if title.ends_with(TAG) else title + TAG)
	if not titles.is_empty():
		out.append(("Added %s. %s" % [", ".join(titles), hint]).strip_edges())
	for line: String in result.get("errors", PackedStringArray()):
		out.append("Not a map: %s" % line)
	return out


static func _add(docs: Array[Dictionary], name: String, text: String, kinds: PackedStringArray) -> bool:
	var json := JSON.new()
	if json.parse(text) != OK:
		return false
	var data: Variant = json.data
	if data is Dictionary and kinds.has(str((data as Dictionary).get(KIND_KEY, ""))):
		docs.append({"name": name, "text": text, "doc": data})
		return true
	return false


static func _collect(dir: String, left: int, kinds: PackedStringArray, docs: Array[Dictionary], errors: PackedStringArray) -> void:
	var files := DirAccess.get_files_at(dir)
	files.sort()
	for file in files:
		var ext := file.get_extension().to_lower()
		if ext == "json":
			_add(docs, file, FileAccess.get_file_as_string(dir.path_join(file)), kinds)
		elif ext == "zip":
			_from_zip(dir.path_join(file), kinds, docs, errors, true)
	if left == 0:
		return
	var subs := DirAccess.get_directories_at(dir)
	subs.sort()
	for sub in subs:
		if not sub.begins_with(".") and sub != "__MACOSX":
			_collect(dir.path_join(sub), left - 1 if left > 0 else -1, kinds, docs, errors)


## [param quiet]: a zip met while searching a folder that holds no document of the kind is not an error (it is not this game's).
static func _from_zip(zip_path: String, kinds: PackedStringArray, docs: Array[Dictionary], errors: PackedStringArray, quiet: bool = false) -> void:
	var shown := zip_path.get_file()
	var zip := ZIPReader.new()
	if zip.open(zip_path) != OK:
		if not quiet:
			errors.append("%s: %s" % [shown, DotMapLocalMaps.ZIP_UNREADABLE])
		return
	var names := zip.get_files()
	names.sort()
	var found := false
	for name in names:
		if name.get_extension().to_lower() != "json" or name.ends_with("/") or name.begins_with("__MACOSX/") or name.get_file().begins_with("._"):
			continue
		if name.begins_with("/") or name.contains("\\") or name.contains(":") or name.split("/").has(".."):
			errors.append("%s: unsafe path in the zip: %s" % [shown, name])
			continue
		var bytes := zip.read_file(name)
		if max_doc_bytes > 0 and bytes.size() > max_doc_bytes:
			errors.append("%s: %s is %d bytes, more than max_doc_bytes %d" % [shown, name, bytes.size(), max_doc_bytes])
			continue
		found = _add(docs, name.get_file(), bytes.get_string_from_utf8(), kinds) or found
	zip.close()
	if not found and not quiet and errors.is_empty():
		errors.append("%s: no map document in the zip" % shown)
