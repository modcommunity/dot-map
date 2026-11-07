class_name DotMapDataBundle
extends RefCounted

## One map's tool data (spawns, nav settings, hand links, cull rules) as a JSON file keyed by game, map id
## and map version. Sections are opaque dictionaries owned by their producers; only the names are fixed.
## [method from_json] is the untrusted door: caps, known sections only, no loadable paths.

const FORMAT := "dot-map-data"
const SCHEMA := 1
const SECTIONS: Array[String] = ["spawns", "nav_settings", "nav_links", "nav_annotations", "cull"]

const MAX_BYTES := 4 * 1024 * 1024
const MAX_STRING := 1024
const MAX_NODES := 100000
const MAX_DEPTH := 12
const MAX_ID := 64

var game := ""
var map_id := ""
var map_version := ""
var digest := ""
var meta: Dictionary = {}
var sections: Dictionary = {}

## Set by a store's load: the bundle is for an older map version than the one asked for.
var stale := false


## A safe file and key name: no separators, no leading dot.
static func is_safe_id(s: String) -> bool:
	if s.is_empty() or s.length() > MAX_ID or s.begins_with("."):
		return false
	for i in s.length():
		var c := s.unicode_at(i)
		var ok := (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95 or c == 45 or c == 46
		if not ok:
			return false
	return true


func to_dict() -> Dictionary:
	return {
		"format": FORMAT, "schema": SCHEMA, "game": game,
		"map": {"id": map_id, "version": map_version, "digest": digest},
		"meta": meta, "sections": sections,
	}


## The file text. Checks the same caps an import does, so nothing is written that could not be read back.
func to_json() -> DotResult:
	var text := JSON.stringify(to_dict(), "\t")
	var res := from_json(text)
	return res if not res.ok else DotResult.success(text)


## Section by section: [param over] wins where it has the section, else [param base]. Either may be null.
static func layered(base: DotMapDataBundle, over: DotMapDataBundle) -> DotMapDataBundle:
	if base == null or over == null:
		return over if base == null else base
	var out := _copy(over)
	out.stale = over.stale or base.stale
	for key: String in base.sections:
		if not out.sections.has(key):
			out.sections[key] = base.sections[key].duplicate(true)
	return out


## Parses and validates. Failure codes: parse, version (newer schema), invalid (shape, caps, paths).
static func from_json(text: String) -> DotResult:
	if text.length() > MAX_BYTES:
		return DotResult.fail(DotError.CODE_INVALID, "Map data is larger than %d bytes." % MAX_BYTES)
	var json := JSON.new()
	var parsed: Variant = json.data if json.parse(text) == OK else null
	if not parsed is Dictionary:
		return DotResult.fail(DotError.CODE_PARSE, "Map data is not a JSON object.")
	var d: Dictionary = parsed
	if d.get("format") != FORMAT:
		return DotResult.fail(DotError.CODE_INVALID, "Not a %s file." % FORMAT)
	if not (d.get("schema") is float or d.get("schema") is int) or d["schema"] != floorf(d["schema"]):
		return DotResult.fail(DotError.CODE_INVALID, "Map data has no schema number.")
	if int(d["schema"]) > SCHEMA:
		return DotResult.fail(DotError.CODE_VERSION, "Map data schema %d is newer than %d." % [int(d["schema"]), SCHEMA])
	var map: Variant = d.get("map")
	if not map is Dictionary or not d.get("game") is String or not d.get("sections", {}) is Dictionary or not d.get("meta", {}) is Dictionary:
		return DotResult.fail(DotError.CODE_INVALID, "Map data has the wrong shape.")
	var b := DotMapDataBundle.new()
	b.game = d["game"]
	b.map_id = str(map.get("id", ""))
	b.map_version = str(map.get("version", ""))
	b.digest = str(map.get("digest", ""))
	if not is_safe_id(b.game) or not is_safe_id(b.map_id) or not is_safe_id(b.map_version):
		return DotResult.fail(DotError.CODE_INVALID, "Game, map id and version must be 1 to %d letters, digits, _ - ." % MAX_ID)
	if b.digest.length() > 128:
		return DotResult.fail(DotError.CODE_INVALID, "Digest is too long.")
	var budget := [MAX_NODES]
	for part: Variant in [d.get("meta", {}), d.get("sections", {})]:
		var bad := _scan(part, 0, budget)
		if bad != "":
			return DotResult.fail(DotError.CODE_INVALID, bad)
	b.meta = d.get("meta", {}).duplicate(true)
	var secs: Dictionary = d.get("sections", {})
	for key: String in secs:
		if not key in SECTIONS:
			continue
		if not secs[key] is Dictionary:
			return DotResult.fail(DotError.CODE_INVALID, "Section %s is not an object." % key)
		b.sections[key] = secs[key].duplicate(true)
	return DotResult.success(b)


## A file handed in by a person. It must be for this map (conflict otherwise). A different version or
## geometry digest is refused unless [param force]; [method import_warnings] says what differs.
static func import_json(text: String, map_id: String, map_version: String, digest: String = "", force: bool = false) -> DotResult:
	var res := from_json(text)
	if not res.ok:
		return res
	var b: DotMapDataBundle = res.value
	if b.map_id != map_id:
		return DotResult.fail(DotError.CODE_CONFLICT, "This data is for map %s, not %s." % [b.map_id, map_id])
	var warnings := import_warnings(b, map_version, digest)
	if not warnings.is_empty() and not force:
		return DotResult.fail(DotError.CODE_CONFLICT, "; ".join(warnings) + " (import again with force).")
	return DotResult.success(b)


## What differs between a bundle and the map it is imported onto.
static func import_warnings(b: DotMapDataBundle, map_version: String, digest: String = "") -> PackedStringArray:
	var out := PackedStringArray()
	if b.map_version != map_version:
		out.append("made for version %s, map is %s" % [b.map_version, map_version])
	if digest != "" and b.digest != "" and b.digest != digest:
		out.append("made for different geometry")
	return out


static func _copy(src: DotMapDataBundle) -> DotMapDataBundle:
	var b := DotMapDataBundle.new()
	b.game = src.game
	b.map_id = src.map_id
	b.map_version = src.map_version
	b.digest = src.digest
	b.meta = src.meta.duplicate(true)
	b.sections = src.sections.duplicate(true)
	return b


## Returns the first problem in a value tree, or "". Counts nodes against [param budget].
static func _scan(v: Variant, depth: int, budget: Array) -> String:
	budget[0] -= 1
	if budget[0] < 0:
		return "Map data has more than %d values." % MAX_NODES
	if depth > MAX_DEPTH:
		return "Map data is nested deeper than %d." % MAX_DEPTH
	if v is String:
		return _scan_string(v)
	if v is float and (is_nan(v) or is_inf(v)):
		return "Map data holds a number that is not finite."
	if v is Dictionary:
		for k: Variant in v:
			var bad := _scan_string(k) if k is String else "Map data has a key that is not text."
			if bad == "":
				bad = _scan(v[k], depth + 1, budget)
			if bad != "":
				return bad
	elif v is Array:
		for item: Variant in v:
			var bad := _scan(item, depth + 1, budget)
			if bad != "":
				return bad
	elif not (v == null or v is bool or v is int or v is float):
		return "Map data holds a value of a kind JSON does not have."
	return ""


static func _scan_string(s: String) -> String:
	if s.length() > MAX_STRING:
		return "Map data holds a string longer than %d." % MAX_STRING
	var low := s.to_lower()
	if low.contains("://") or low.begins_with("/") or low.contains("../") or low.contains("..\\"):
		return "Map data may not carry paths or URLs."
	for ext in [".gd", ".gdc", ".tscn", ".scn", ".tres", ".res", ".so", ".dll", ".pck"]:
		if low.ends_with(ext):
			return "Map data may not name a script or resource."
	return ""
