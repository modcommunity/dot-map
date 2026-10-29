class_name DotMapRotationFile
extends RefCounted

## The maps a server PLAYS, read from `cfg/addons/dot_map/maps.yml` and its tiers; the catalogue is what is merely installed. A map not in the rotation stays loadable by `map <id>` but is left out of the pool, ballots and nominations ([member DotMapDef.in_rotation]).
## Keys: `defaults:` and `games: <game>:` with `rotation`, `mode` (random with `cooldown`, or cycle), `maps` (patterns), `rotations: {name: {maps}}`. No file means every installed map rotates, sorted by id; `merge: true` adds to the shipped file, `remove: [ids]` drops maps.
## Layers, weakest first: shipped file, server `defaults:`, server `games:`. Parsing and matching are dot-core's [DotRotationSpec]; patterns expand at [method apply], called on every map change and rescan.

const CHANNEL := "map.rotation_file"
const EXTENSIONS := ["yml", "yaml"]

## The game this server runs, as a section key matches it (`game-g2gfast`).
var game: String = ""

## The merged spec ([DotRotationSpec]).
var spec: Dictionary = {}

## The name `sv_map_rotation` last switched to; empty follows the file.
var requested: String = ""

## `owner/collection` to the `owner/map` refs it publishes, for `owner/collection/*`. Dot-map
## downloads nothing; the host that knows the collections (the server's content step) sets it.
var collections: Dictionary = {}

## Where the layers were read from, weakest first.
var sources: PackedStringArray = PackedStringArray()

## Map ids (or the last segment of a ref) taken out of every rotation, from a top-level `remove: [ids]` in any layer.
var removed: PackedStringArray = PackedStringArray()

var warnings: PackedStringArray = PackedStringArray()
var _warned: Dictionary = {}
var _last: PackedStringArray = PackedStringArray()
var _last_name: String = ""

## `(DotMapDef) -> bool`, asked per map when a rotation is empty and so nothing is listed. The default is
## every map; a game that keeps some out when there is no file gives the same rule here, so an empty rotation
## and an absent file mean the same thing.
var fallback_in: Callable = Callable()
var _fell_back: bool = false

## The rotation [method apply] last marked, held weakly: the catalogue's signal holds this file,
## and a strong reference back would be a cycle nothing frees.
var _bound: WeakRef = null
var _bound_catalogue: DotMapCatalogue = null


## The stem games pass for the default file; it resolves to `cfg/addons/dot_map/maps.yml`, with the old flat path read through [DotCfgLegacy].
const DEFAULT_STEM := "cfg/maps.yml"


## Where a path given as [param stem] (with or without extension) is: in [param config_dir] first when one is
## given (the directory the host was started with, a plain filesystem path), then beside the project, in
## `user://`, beside the executable. "" when there is none.
static func find(stem: String, config_dir: String = "") -> String:
	if stem.strip_edges().is_empty():
		return ""
	if stem.trim_suffix(".yml").trim_suffix(".yaml") == DEFAULT_STEM.trim_suffix(".yml"):
		return DotCfgLegacy.find(_find_flat(stem, config_dir), _strongest(DotAddonConfig.file_layers("dot-map", "maps.yml", config_dir)))
	return _find_flat(stem, config_dir)


## The `maps.yml` files that apply, weakest first: `cfg/addons/dot_map/`, the game's `cfg/game/<game>/dot_map/`, the operator's `cfg/server/addons/dot_map/` and `cfg/server/game/<game>/dot_map/`. An operator file replaces every weaker one unless it starts `merge: true` ([method DotAddonConfig.replace_aware_layers]). [param p_game] stands in for [member DotAddonConfig.game] when that is unset.
static func find_layers(config_dir: String = "", p_game: String = "") -> PackedStringArray:
	var had := DotAddonConfig.game
	if had == "" and p_game != "":
		DotAddonConfig.game = p_game
	var out := DotAddonConfig.replace_aware_layers("dot-map", "maps.yml", config_dir)
	DotAddonConfig.game = had
	return out


static func _strongest(paths: PackedStringArray) -> String:
	return "" if paths.is_empty() else paths[paths.size() - 1]


static func _find_flat(stem: String, config_dir: String) -> String:
	var names := PackedStringArray([stem]) if stem.get_extension() != "" \
		else PackedStringArray(EXTENSIONS.map(func(e: String) -> String: return "%s.%s" % [stem, e]))
	if config_dir != "":
		for n in names:
			var beside := config_dir.path_join(n.get_file())
			if FileAccess.file_exists(beside):
				return beside
	var bases := PackedStringArray([""])
	if stem.is_relative_path() and not stem.begins_with("res://") and not stem.begins_with("user://"):
		bases = PackedStringArray(["res://", "user://", OS.get_executable_path().get_base_dir() + "/"])
	for base in bases:
		for n in names:
			if FileAccess.file_exists(base + n):
				return base + n
	return ""


## The `--config DIR` (or `--config=DIR`) the process was started with, or "". A game cannot
## ask the host for it, and the flag is the one thing the host and the game both see.
static func config_dir_arg() -> String:
	var args := OS.get_cmdline_user_args() + OS.get_cmdline_args()
	for i in args.size():
		if args[i] == "--config" and i + 1 < args.size():
			return args[i + 1]
		if args[i].begins_with("--config="):
			return args[i].substr(9)
	return ""


## Layers parsed trees, weakest first (the game's shipped file, then the server's).
static func from_trees(trees: Array, p_game: String = "", p_sources: PackedStringArray = PackedStringArray()) -> DotResult:
	var file := DotMapRotationFile.new()
	file.game = p_game
	file.sources = p_sources
	var layers: Array = []
	for t: Variant in trees:
		var tree := t as Dictionary
		if tree.get("remove") is Array:
			for r: Variant in (tree["remove"] as Array):
				file.removed.append(str(r))
		var where := "maps.yml"
		if tree.get("defaults") is Dictionary:
			layers.append(DotRotationSpec.normalize(tree["defaults"], "maps", file.warnings, where + " defaults"))
		if tree.get("games") is Dictionary:
			for key: Variant in (tree["games"] as Dictionary):
				if DotRotationSpec.key_matches(str(key), p_game) and (tree["games"] as Dictionary)[key] is Dictionary:
					layers.append(DotRotationSpec.normalize((tree["games"] as Dictionary)[key], "maps", file.warnings, "%s games.%s" % [where, key]))
	file.spec = DotRotationSpec.layer(layers)
	for w in file.warnings:
		DotLog.warn(CHANNEL, w)
	return DotResult.success(file)


## Reads the given files (a missing one is skipped, an unreadable one fails), weakest first.
static func load_files(paths: PackedStringArray, p_game: String = "") -> DotResult:
	var trees: Array = []
	var used := PackedStringArray()
	for path in paths:
		if path == "" or not FileAccess.file_exists(path):
			continue
		var parsed := DotYaml.parse_file(path)
		if not parsed.ok:
			return parsed.wrap("reading %s" % path)
		trees.append(parsed.value)
		used.append(path)
	return from_trees(trees, p_game, used)


## The merged `commands:` block (`prefix`, `names`): what the vote commands are called. See
## [DotRotationSpec]; the commands classes take it through their `spec_fn`.
func commands() -> Dictionary:
	return spec.get("commands", {"names": {}})


func has_rotations() -> bool:
	return not (spec.get("rotations", {}) as Dictionary).is_empty()


func rotation_names() -> PackedStringArray:
	var out := PackedStringArray()
	for n: Variant in (spec.get("rotations", {}) as Dictionary):
		out.append(str(n))
	return out


## The name in force: a live switch, else the file's `rotation:`, else `main`.
func active_name() -> String:
	return DotRotationSpec.active_name(spec, requested)


## The ids the rotation named [param name] (default: the active one) plays, in order, against
## [param catalogue]. Empty means "no file or nothing matched": the caller then plays everything.
func resolve(catalogue: DotMapCatalogue, name: String = "") -> PackedStringArray:
	var use := name if name != "" else active_name()
	var rots: Dictionary = spec.get("rotations", {})
	if use == "" or not rots.has(use) or catalogue == null:
		return PackedStringArray()
	var candidates := _candidates(catalogue)
	var unmatched := PackedStringArray()
	var ids := DotRotationSpec.expand((rots[use] as Dictionary)["entries"], candidates, collections, unmatched)
	if not removed.is_empty():
		var kept := PackedStringArray()
		for id in ids:
			if not removed.has(id):
				kept.append(id)
		ids = kept
	for entry in unmatched:
		var key := "%s|%s" % [use, entry]
		if not _warned.has(key):
			_warned[key] = true
			DotLog.warn(CHANNEL, "a map rotation entry matches no installed map", {"rotation": use, "entry": entry})
	return ids


func _candidates(catalogue: DotMapCatalogue) -> Array:
	var candidates: Array = []
	for m in catalogue.maps:
		var content := String(m.content_id)
		candidates.append({"id": String(m.id), "ref": content if content.count("/") == 1 else ""})
	return candidates


## The per-map settings the rotation [param name] (default: the active one) gives [param id]
## (`{waves: easy}` from a mapping entry), empty for a bare entry or no match.
func settings_for(catalogue: DotMapCatalogue, id: StringName, name: String = "") -> Dictionary:
	var use := name if name != "" else active_name()
	if use == "" or catalogue == null or not (spec.get("rotations", {}) as Dictionary).has(use):
		return {}
	return DotRotationSpec.settings_for(spec, use, String(id), _candidates(catalogue), collections)


## Marks every catalogue map in or out of rotation and sets the rotation's order, mode and
## cooldown. No file, an unknown rotation or an empty result leaves every map in (the whole
## catalogue): a rotation that empties the server must never leave it stuck.
func apply(rotation: DotMapRotation, name: String = "") -> DotResult:
	if rotation == null or rotation.catalogue == null:
		return DotResult.fail(DotError.CODE_INVALID, "A rotation with a catalogue is needed.")
	var use := name if name != "" else active_name()
	var ids := resolve(rotation.catalogue, use)
	_fell_back = false
	if has_rotations() and ids.is_empty():
		_fell_back = true
		var key := "empty|%s" % use
		if not _warned.has(key):
			_warned[key] = true
			DotLog.warn(CHANNEL, "the map rotation is empty; every installed map plays", {"rotation": use})
	_bind(rotation)
	var order: Array[StringName] = []
	for id in ids:
		order.append(StringName(id))
	for m in rotation.catalogue.maps:
		if ids.is_empty():
			m.in_rotation = bool(fallback_in.call(m)) if fallback_in.is_valid() else true
		else:
			m.in_rotation = ids.has(String(m.id))
		m.play = settings_for(rotation.catalogue, m.id, use) if m.in_rotation and not ids.is_empty() else {}
	rotation.order = order
	if has_rotations() and use != "" and (spec["rotations"] as Dictionary).has(use):
		rotation.mode = DotMapRotation.Mode.SEQUENTIAL if DotRotationSpec.mode_of(spec, use) == "cycle" \
			else DotMapRotation.Mode.RANDOM
		rotation.cooldown = DotRotationSpec.cooldown_of(spec, use, rotation.cooldown)
	if use != _last_name:
		rotation.reset_cursor()
	_last = ids
	_last_name = use
	return DotResult.success(ids)


## Follows the catalogue of the rotation last applied, so a content refresh (a pack installed,
## a session turned) re-applies the marks to the fresh defs it just made. Applying to another
## rotation moves the connection; the old catalogue is no longer followed.
func _bind(rotation: DotMapRotation) -> void:
	_bound = weakref(rotation)
	var catalogue := rotation.catalogue
	if catalogue == _bound_catalogue:
		return
	if _bound_catalogue != null and _bound_catalogue.content_refreshed.is_connected(_on_content_refreshed):
		_bound_catalogue.content_refreshed.disconnect(_on_content_refreshed)
	_bound_catalogue = catalogue
	catalogue.content_refreshed.connect(_on_content_refreshed)


func _on_content_refreshed() -> void:
	var rotation := _bound.get_ref() as DotMapRotation if _bound != null else null
	if rotation == null or rotation.catalogue != _bound_catalogue:
		return
	# The name last applied, so a game that applied a named rotation keeps it; a live switch
	# has already moved it through [member requested].
	apply(rotation, _last_name)


## Whether the last [method apply] found its rotation empty and so left every map in.
## A game that keeps some maps out by default (a kind that is another mode's) puts its own
## rule back when this is true.
func fell_back() -> bool:
	return _fell_back


## Switches the live rotation (`sv_map_rotation <name>`). An unknown name changes nothing.
func switch(rotation: DotMapRotation, name: String) -> DotResult:
	var rots: Dictionary = spec.get("rotations", {})
	if not rots.has(name):
		return DotResult.fail(DotError.CODE_INVALID, "No rotation called '%s'." % name,
			"rotations: %s" % ", ".join(rotation_names()))
	requested = name
	return apply(rotation)


## Re-applies after every map change, so a map installed meanwhile that matches joins.
func attach(session: DotMapSession) -> void:
	session.changed.connect(func(_map: DotMapDef, _world: Node) -> void:
		if session.rotation != null:
			apply(session.rotation))


func describe() -> Dictionary:
	return {
		"game": game, "sources": ", ".join(sources), "rotations": ", ".join(rotation_names()),
		"active": active_name(), "plays": _last.size(), "fell_back": _fell_back,
	}


func describe_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	for n in rotation_names():
		var mark := "*" if n == (_last_name if _last_name != "" else active_name()) else " "
		var entries: PackedStringArray = (spec["rotations"] as Dictionary)[n]["entries"]
		lines.append("%s %s (%s, cooldown %d): %s" % [mark, n, DotRotationSpec.mode_of(spec, n),
			DotRotationSpec.cooldown_of(spec, n, 0), ", ".join(entries)])
	return lines
