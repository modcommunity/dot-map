class_name DotMapConfig
extends RefCounted

## Per-map settings: the merged `{cvar: value}` a map asks for, resolved from `map/<name>.yml` files, whitelisted, applied on load and put back on the next map.
##
## Files are `map/<name>.yml` inside each [DotAddonConfig] tier of `dot-map` (`cfg/addons/dot_map/`, `cfg/game/<game>/dot_map/`, then the operator's `cfg/server/addons/dot_map/` and `cfg/server/game/<game>/dot_map/`), in every root. [code]<name>[/code] is the map id or a glob (`surf_*`, `?`/`*`, case-insensitive), the content a flat mapping of key to scalar.
##
## [b]Order, strongest first[/b]: command line `--dot-map.map.<key>=v` / environment `DOT_MAP_MAP_<KEY>` (a key some file or [member defaults] already holds, as [DotAddonConfig] does everywhere), then the operator's tiers (exact file over wildcards), then the shipped tiers (exact over wildcards), then [member defaults] (the converter's values). Among wildcards the more specific wins: most literal characters, then the longer pattern, then the later name alphabetically; at equal specificity the stronger tier (game over addon, per-game over shared) and the later root win. Nothing is executed: a value is only ever handed to [member set_fn] for a key in [member schema].
##
## [codeblock]
## var cfg := DotMapConfig.new()
## cfg.game = "game-arena"
## cfg.allow("arena_surf_airaccelerate", {"type": "float", "min": 0.0})
## cfg.get_fn = func(k: String) -> Variant: return console.get_cvar_string(k)
## cfg.set_fn = func(k: String, v: Variant) -> bool: return console.set_cvar(k, str(v)).ok
## cfg.apply(String(map.id))   # on every map load; restores the last map's keys first
## [/codeblock]

const CHANNEL := "map.config"
const ADDON := "dot-map"
const SUBDIR := "map"
const EXTENSIONS: PackedStringArray = ["yml", "yaml"]
const TIERS_SHIPPED: PackedStringArray = ["addons", "game"]
const TIERS_SERVER: PackedStringArray = ["server/addons", "server/game"]

## The game whose `cfg/game/<game>/` tiers are read; empty skips them.
var game: String = ""

## A `--config`-style root read last among the roots, as [method DotAddonConfig.file_layers] takes.
var config_dir: String = ""

## Allowed keys: key -> `{type: "float"|"int"|"bool"|"string"|"" (any scalar), min, max}`. Empty allows nothing.
var schema: Dictionary = {}

## The converter's values, the weakest layer: key -> value.
var defaults: Dictionary = {}

## `(key: String) -> Variant`: the key's current value, so [method restore] can put it back.
var get_fn: Callable = Callable()

## `(key: String, value: Variant) -> bool`: applies one value; false means the game refused it.
var set_fn: Callable = Callable()

## The map [method apply] last applied for.
var current_map: String = ""

## key -> `{before, set}` for what is applied now.
var _applied: Dictionary = {}
var _warned: Dictionary = {}
var _last: Dictionary = {}


## Whitelists [param key]; [param spec] may hold `type`, `min`, `max`. Chainable.
func allow(key: String, spec: Dictionary = {}) -> DotMapConfig:
	schema[key.strip_edges().to_lower()] = spec
	return self


## Whitelists every name in [param keys] with no constraint.
func allow_all(keys: PackedStringArray) -> DotMapConfig:
	for k in keys:
		allow(k)
	return self


## The merged settings for [param map_name]. Value: `{settings, sources (key -> where it came from), rejected ([{key, why, from}]), files (weakest first)}`. Unknown or badly typed keys are rejected and logged once, never applied.
func resolve(map_name: String) -> DotResult:
	var name := map_name.strip_edges().to_lower()
	if name == "":
		return DotResult.fail(DotError.CODE_INVALID, "A map name is needed to resolve its settings.")

	var merged := {}
	var sources := {}
	var files := PackedStringArray()
	var problems: Array = []
	for k: Variant in defaults:
		merged[_norm(k)] = defaults[k]
		sources[_norm(k)] = "converter default"

	for entry: Dictionary in _matching_files(name):
		var parsed := DotYaml.parse_file(entry["path"])
		if not parsed.ok or not (parsed.value is Dictionary or parsed.value == null):
			problems.append({"key": "", "why": "unreadable file", "from": entry["path"]})
			_warn_once("file:" + entry["path"], "a map settings file could not be read", {"file": entry["path"]})
			continue
		files.append(entry["path"])
		if parsed.value == null:
			continue
		for k: Variant in (parsed.value as Dictionary):
			merged[_norm(k)] = (parsed.value as Dictionary)[k]
			sources[_norm(k)] = entry["path"]

	for line in DotAddonConfig.apply_overrides("%s.%s" % [ADDON, SUBDIR], merged):
		sources[line.get_slice(" <- ", 0)] = line.get_slice(" <- ", 1)

	var settings := {}
	var rejected: Array = []
	for key: String in merged:
		var checked := _check(key, merged[key])
		if not checked.ok:
			rejected.append({"key": key, "why": checked.error.message, "from": sources[key]})
			_warn_once("%s:%s:%s" % [name, key, sources[key]], "a map setting was not applied", {
				"map": name, "key": key, "why": checked.error.message, "from": sources[key]})
		else:
			settings[key] = checked.value
	rejected.append_array(problems)

	var out := {"settings": settings, "sources": sources, "rejected": rejected, "files": files}
	_last[name] = out
	return DotResult.success(out)


## Puts the last map's keys back, then applies [param map_name]'s settings through [member set_fn]. Value: the keys applied. Fails (CODE_STATE) before changing anything when the hooks are not set.
func apply(map_name: String) -> DotResult:
	if not get_fn.is_valid() or not set_fn.is_valid():
		return DotResult.fail(DotError.CODE_STATE, "DotMapConfig needs get_fn and set_fn before apply().")
	var resolved := resolve(map_name)
	restore()
	current_map = map_name
	if not resolved.ok:
		return resolved
	var done := PackedStringArray()
	var settings: Dictionary = resolved.value["settings"]
	for key: String in settings:
		var before: Variant = get_fn.call(key)
		if set_fn.call(key, settings[key]) == false:
			DotLog.warn(CHANNEL, "the game refused a map setting", {"map": map_name, "key": key})
			continue
		_applied[key] = {"before": before, "set": settings[key]}
		done.append(key)
	DotLog.info(CHANNEL, "map settings applied", {"map": map_name, "keys": ", ".join(done)})
	return DotResult.success(done)


## Restores what [method apply] changed, except a key something else has changed since (an operator's later edit stays). Returns how many were put back.
func restore() -> int:
	var n := 0
	for key: String in _applied:
		var rec: Dictionary = _applied[key]
		if get_fn.is_valid() and str(get_fn.call(key)) != str(rec["set"]):
			continue
		if set_fn.is_valid() and set_fn.call(key, rec["before"]) != false:
			n += 1
	_applied.clear()
	current_map = ""
	return n


## What is applied now: key -> value.
func applied() -> Dictionary:
	var out := {}
	for key: String in _applied:
		out[key] = _applied[key]["set"]
	return out


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray(["DotMapConfig map=%s keys=%d allowed=%d" % [current_map, _applied.size(), schema.size()]])
	var last: Dictionary = _last.get(current_map.to_lower(), {})
	for key: String in _applied:
		out.append("  %s = %s  (%s)" % [key, _applied[key]["set"], (last.get("sources", {}) as Dictionary).get(key, "?")])
	for r: Dictionary in last.get("rejected", []):
		out.append("  rejected %s: %s (%s)" % [r["key"], r["why"], r["from"]])
	return out


func _norm(key: Variant) -> String:
	return String(key).strip_edges().to_lower()


func _warn_once(id: String, message: String, fields: Dictionary) -> void:
	if not _warned.has(id):
		_warned[id] = true
		DotLog.warn(CHANNEL, message, fields)


## The value coerced to its schema entry, or a failure naming why.
func _check(key: String, value: Variant) -> DotResult:
	if not schema.has(key):
		return DotResult.fail(DotError.CODE_INVALID, "not a setting this game accepts")
	if value is Dictionary or value is Array or value == null:
		return DotResult.fail(DotError.CODE_INVALID, "a setting is one scalar value")
	var spec: Dictionary = schema[key] if schema[key] is Dictionary else {}
	var type := String(spec.get("type", ""))
	var out: Variant = value
	match type:
		"float", "int":
			var text := str(value)
			if value is bool or not (value is int or value is float or text.is_valid_float()):
				return DotResult.fail(DotError.CODE_INVALID, "expected a number")
			out = float(value) if value is float or value is int else text.to_float()
			if spec.has("min"):
				out = maxf(float(out), float(spec["min"]))
			if spec.has("max"):
				out = minf(float(out), float(spec["max"]))
			if type == "int":
				out = int(out)
		"bool":
			var t := str(value).to_lower()
			if not ["true", "false", "1", "0"].has(t):
				return DotResult.fail(DotError.CODE_INVALID, "expected true or false")
			out = t == "true" or t == "1"
		"string":
			out = str(value)
	return DotResult.success(out)


## Files whose name matches, weakest first (the order they are merged in).
func _matching_files(name: String) -> Array:
	var found: Array = []
	for group in 2:
		var tiers: PackedStringArray = TIERS_SERVER if group == 1 else TIERS_SHIPPED
		for t in tiers.size():
			var dirs: PackedStringArray = DotAddonConfig.tier_dirs(ADDON, tiers[t], config_dir, game)
			for r in dirs.size():
				var dir := dirs[r].path_join(SUBDIR)
				if not DirAccess.dir_exists_absolute(dir):
					continue
				for f in DirAccess.get_files_at(dir):
					if not EXTENSIONS.has(f.get_extension().to_lower()):
						continue
					var pattern := f.get_basename().to_lower()
					var wild := pattern.contains("*") or pattern.contains("?")
					if (wild and name.matchn(pattern)) or (not wild and name == pattern):
						found.append({"path": dir.path_join(f), "pattern": pattern, "group": group,
							"exact": 0 if wild else 1, "literal": _literal(pattern), "tier": t, "root": r})
	found.sort_custom(_weaker)
	return found


static func _literal(pattern: String) -> int:
	return pattern.length() - pattern.count("*") - pattern.count("?")


static func _weaker(a: Dictionary, b: Dictionary) -> bool:
	for k in ["group", "exact", "literal"]:
		if a[k] != b[k]:
			return a[k] < b[k]
	if a["pattern"].length() != b["pattern"].length():
		return a["pattern"].length() < b["pattern"].length()
	if a["pattern"] != b["pattern"]:
		return a["pattern"] < b["pattern"]
	if a["tier"] != b["tier"]:
		return a["tier"] < b["tier"]
	return a["root"] < b["root"]
