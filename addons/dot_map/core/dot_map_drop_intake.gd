class_name DotMapDropIntake
extends Node

## Maps a person hands a game: dropped on the window, dropped on the executable (command-line paths, [method take_cmdline]),
## or named by [code]--map-path=<path>[/code]. Each path goes to the first acceptor that claims it; one nobody claims is
## refused LOUDLY with what the game takes. Add as a child; on the web a drop is copied before the callback returns.

const CHANNEL := "dot_map.drop"

## Godot's own options that take the next argument as their value, so that value is never read as a dropped path.
const ENGINE_VALUE_FLAGS := ["--path", "--main-pack", "--scene", "--script", "-s", "--log-file", "--render-thread",
		"--rendering-driver", "--rendering-method", "--display-driver", "--audio-driver", "--audio-output-latency",
		"--text-driver", "--tablet-driver", "--accessibility", "--accessibility-driver", "--language", "-l",
		"--resolution", "--position", "--screen", "--gpu-index", "--max-fps", "--fixed-fps", "--frame-delay",
		"--time-scale", "--delta-smoothing", "--quit-after", "--write-movie", "--xr-mode", "--remote-debug",
		"--remote-fs", "--remote-fs-password", "--debug-server", "--breakpoints", "-b", "--benchmark-file",
		"--patches", "--wid", "--export-release", "--export-debug", "--export-pack", "--export-patch",
		"--doctool", "--gdscript-docs", "--lsp-port", "--dap-port", "--editor-pid", "--validate-extension-api"]

## After every handled drop: [code]{source, paths, added, errors}[/code], the same dictionary [method handle] returns.
signal handled(result: Dictionary)

## Where acceptors copy what they take.
var into := DotMapLocalMaps.DROP_ROOT

## How many folders below a dropped folder a converted map is looked for; 0 is no limit.
var search_depth := 3

## Connect [signal Window.files_dropped] of this node's window in [method _ready].
var watch_window := true

## Options whose next argument is their value; a game adds its own (dot-core reads [code]--config <dir>[/code], say).
var value_flags := PackedStringArray(ENGINE_VALUE_FLAGS)

## The explicit option: [code]--map-path=<path>[/code] or [code]--map-path <path>[/code], a path that must exist.
var path_flag := "--map-path"

## The game's own config option prefixes (`--zz-`, say): such an option and its value are never read as a dropped path.
## `--<addon>.<key> <value>` is always skipped. See [method strip_config_args].
var config_prefixes := PackedStringArray()

## [code]func(prefix: String, stem: String) -> bool[/code]: whether the config option [code]<prefix><stem>[/code] takes the
## next argument as its value. Empty: it does when that argument is not an option. [method config_takes_value] answers it from a config.
var option_takes_value := Callable()

## The last [method handle] result, and running totals for [method describe_lines].
var last_result := {}
var drops := 0
var added_total := 0
var refused_total := 0

## [code][what, Callable][/code] pairs in the order they are tried.
var _acceptors: Array = []
var _window: Window = null


func _ready() -> void:
	if watch_window:
		watch(get_window())


func _exit_tree() -> void:
	unwatch()


## Listens to [param window]'s drops (one window at a time).
func watch(window: Window) -> void:
	unwatch()
	if window == null:
		return
	_window = window
	_window.files_dropped.connect(_on_files_dropped)


func unwatch() -> void:
	if _window != null and is_instance_valid(_window) and _window.files_dropped.is_connected(_on_files_dropped):
		_window.files_dropped.disconnect(_on_files_dropped)
	_window = null


## Adds an acceptor, tried after those already added. [param fn] is [code]func(path: String, into: String) -> Dictionary[/code]:
## empty when the path is not its kind, else [code]{added: Array[Dictionary], errors: PackedStringArray}[/code] (an entry
## should carry [code]id[/code] and [code]title[/code]). [param what] names the kind in the refusal ("a map .json").
func add_acceptor(what: String, fn: Callable) -> void:
	_acceptors.append([what, fn])


## Adds the converted-map acceptor: a map folder (searched [member search_depth] folders down), a convert folder, a zip of
## either, or a [code].json[/code]/[code].bin[/code] beside its pair, copied by [method DotMapLocalMaps.accept_dropped].
func add_converted_maps() -> void:
	add_acceptor("a converted map folder or its .zip", _accept_converted)


## What the acceptors take, for a game's own help text.
func accepted_kinds() -> PackedStringArray:
	var out := PackedStringArray()
	for pair: Array in _acceptors:
		out.append(str(pair[0]))
	return out


## Hands each path to the first acceptor that claims it; anything unclaimed or missing is an error, logged as one.
## Flushes the web file system when something was copied. Emits [signal handled] and returns the result.
func handle(paths: PackedStringArray, source: String = "window") -> Dictionary:
	var added: Array[Dictionary] = []
	var errors := PackedStringArray()
	var seen := PackedStringArray()
	for raw in without_web_root(paths):
		var path := _local_path(raw)
		seen.append(path)
		var shown := path.rstrip("/").get_file() if path.rstrip("/").get_file() != "" else (path if path != "" else "(empty path)")
		if path.is_empty() or not (FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)):
			errors.append("%s: not found" % shown)
			continue
		if _acceptors.is_empty():
			errors.append("%s: this game loads no dropped maps" % shown)
			continue
		var claimed := false
		for pair: Array in _acceptors:
			var got: Variant = (pair[1] as Callable).call(path, into)
			if not (got is Dictionary) or (got as Dictionary).is_empty():
				continue
			claimed = true
			for e: Variant in (got as Dictionary).get("added", []):
				if e is Dictionary:
					added.append(e)
			var errs: Variant = (got as Dictionary).get("errors", PackedStringArray())
			if errs is PackedStringArray:
				errors.append_array(errs)
			elif errs is Array:
				for line: Variant in errs:
					errors.append(str(line))
			break
		if not claimed:
			errors.append("%s: not a map this game can load (it takes %s)" % [shown, " or ".join(accepted_kinds())])
	if not added.is_empty():
		DotWeb.sync_filesystem()
	for line in errors:
		DotLog.error(CHANNEL, "%s drop refused: %s" % [source, line])
	for e in added:
		DotLog.info(CHANNEL, "%s drop added: %s" % [source, str(e.get("id", "?"))])
	var result := {"source": source, "paths": seen, "added": added, "errors": errors}
	last_result = result
	drops += 1
	added_total += added.size()
	refused_total += errors.size()
	handled.emit(result)
	return result


## Handles the paths on the command line ([method paths_in_args] of [param args], by default the engine's and the user's
## arguments). Returns [code]{}[/code] and emits nothing when there are none, so a game can call it on every start.
func take_cmdline(args: PackedStringArray = PackedStringArray(), use_process_args: bool = true) -> Dictionary:
	var all := args.duplicate()
	if use_process_args and args.is_empty():
		all = OS.get_cmdline_args()
		all.append_array(OS.get_cmdline_user_args())
	var paths := paths_in(all)
	if paths.is_empty():
		return {}
	return handle(paths, "command line")


## The dropped paths in [param args] ([method paths_in_args] after [method strip_config_args] with [member config_prefixes]):
## every path that exists, every flag value, and every absolute path that does not exist (handled as not found).
func paths_in(args: PackedStringArray) -> PackedStringArray:
	var found := paths_in_args(strip_config_args(args, config_prefixes, option_takes_value), value_flags, path_flag)
	var paths: PackedStringArray = found["paths"]
	paths.append_array(found["missing"] as PackedStringArray)
	return paths


## [param args] without the game's config options and their values (`<prefix><key> <value>`, and `--<addon>.<key> <value>`): a value
## that happens to be a folder is not a dropped map. [param takes_value] is [member option_takes_value]; with none, an
## option without `=` takes the next argument unless that is an option itself.
static func strip_config_args(args: PackedStringArray, prefixes: PackedStringArray, takes_value: Callable = Callable()) -> PackedStringArray:
	var out := PackedStringArray()
	var i := 0
	while i < args.size():
		var a := args[i]
		i += 1
		var prefix := ""
		for p in prefixes:
			if a.begins_with(p):
				prefix = p
				break
		if prefix != "" or (a.begins_with("--") and a.get_slice("=", 0).contains(".")):
			var value := not a.contains("=") and i < args.size() and not args[i].begins_with("--")
			if value and prefix != "" and takes_value.is_valid():
				value = bool(takes_value.call(prefix, a.trim_prefix(prefix)))
			if value:
				i += 1
			continue
		out.append(a)
	return out


## Whether [param stem] names a non-boolean key of [param config] (a dot-core [code]DotConfig[/code]): a bare boolean option is a
## switch, so the argument after it is not its value, nor after an unknown key.
static func config_takes_value(config: Object, stem: String) -> bool:
	var key := str(config.call(&"_match_key", stem, config.call(&"config_keys")))
	return key != "" and typeof(config.get(key)) != TYPE_BOOL


## True for a connect address or URL handed to the process (`wss://host:6100/`, `https://...`, `host:6100`): never a dropped
## path. `file://` is a path and is not one.
static func is_url_arg(arg: String) -> bool:
	if arg.contains("://"):
		return not arg.to_lower().begins_with("file://")
	var colon := arg.rfind(":")
	if colon <= 0 or arg.contains("/") or arg.contains("\\"):
		return false
	var port := arg.substr(colon + 1)
	return port.is_valid_int() and not arg.substr(0, colon).contains(":")


## The paths in [param args]: every [param flag] value, and every argument that is not an option, not an option's value
## ([param value_flags_in], the engine's when empty), not a [code]res://[/code]/[code]user://[/code] path, and names an existing file or folder.
## [code]{paths, missing}[/code]: missing is a flag value or an absolute path that does not exist (an error, not ignored).
static func paths_in_args(args: PackedStringArray, value_flags_in: PackedStringArray = PackedStringArray(),
		flag: String = "--map-path") -> Dictionary:
	var flags := value_flags_in if not value_flags_in.is_empty() else PackedStringArray(ENGINE_VALUE_FLAGS)
	var paths := PackedStringArray()
	var missing := PackedStringArray()
	var i := 0
	while i < args.size():
		var arg := args[i]
		i += 1
		var named := ""
		if flag != "" and arg.begins_with(flag + "="):
			named = arg.trim_prefix(flag + "=")
		elif flag != "" and arg == flag:
			named = args[i] if i < args.size() else ""
			i += 1
		elif arg.begins_with("-"):
			if not arg.contains("=") and flags.has(arg):
				i += 1
			continue
		elif arg.begins_with("res://") or arg.begins_with("user://") or arg == "--" or arg == "++" or is_url_arg(arg):
			continue
		else:
			var local := _local_path(arg)
			if FileAccess.file_exists(local) or DirAccess.dir_exists_absolute(local):
				paths.append(local)
			elif local.is_absolute_path():
				missing.append(local)
			continue
		var local_named := _local_path(named)
		if local_named != "" and (FileAccess.file_exists(local_named) or DirAccess.dir_exists_absolute(local_named)):
			paths.append(local_named)
		else:
			missing.append(local_named if local_named != "" else "%s with no path" % flag)
	return {"paths": paths, "missing": missing}


## [param paths] without the web drop's own folder: the browser hands [code][/tmp/drop-n, /tmp/drop-n/a, ...][/code], the
## first being the parent of every other. A list where that is not so is returned unchanged.
static func without_web_root(paths: PackedStringArray) -> PackedStringArray:
	if paths.size() < 2:
		return paths
	var root := paths[0].rstrip("/")
	if root.is_empty() or not DirAccess.dir_exists_absolute(root):
		return paths
	for k in range(1, paths.size()):
		if paths[k].rstrip("/").get_base_dir() != root:
			return paths
	return paths.slice(1)


## One line per added map and per refusal, for a toast or the console.
static func lines_for(result: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for e: Variant in result.get("added", []):
		if e is Dictionary:
			out.append("Added map: %s" % str((e as Dictionary).get("title", (e as Dictionary).get("id", "?"))))
	for line: Variant in result.get("errors", PackedStringArray()):
		out.append("Cannot load %s" % str(line))
	return out


func describe_lines() -> PackedStringArray:
	return PackedStringArray([
		"drop intake: into %s, search_depth %d%s, window %s" % [into, search_depth, " (no limit)" if search_depth == 0 else "",
				"watched" if _window != null else "not watched"],
		"  takes: %s" % (" | ".join(accepted_kinds()) if not _acceptors.is_empty() else "nothing (every drop is refused)"),
		"  drops %d, maps added %d, refused %d" % [drops, added_total, refused_total],
	])


func _on_files_dropped(files: PackedStringArray) -> void:
	handle(files, "window")


func _accept_converted(path: String, to: String) -> Dictionary:
	var take := ""
	var ext := path.get_extension().to_lower()
	if DirAccess.dir_exists_absolute(path):
		var entry := DotMapLocalMaps.entry_within(path.rstrip("/"), search_depth)
		if entry.is_empty():
			return {}
		take = str(entry["folder"])
	elif ext == "zip":
		var why := DotMapLocalMaps.zip_problem(path)
		if why == DotMapLocalMaps.ZIP_NO_MAP or why == DotMapLocalMaps.ZIP_UNREADABLE:
			return {}
		take = path
	elif ext == "json" or ext == "bin":
		if DotMapLocalMaps.prefix_in(path.get_base_dir()).is_empty() or not FileAccess.file_exists(path.get_basename() + ".bin"):
			return {}
		take = path
	else:
		return {}
	return DotMapLocalMaps.accept_dropped(PackedStringArray([take]), to)


## [param raw] as a path this process can open: Windows separators made forward when the raw path does not exist as given.
static func _local_path(raw: String) -> String:
	if raw.is_empty():
		return ""
	if raw.contains("\\") and not (FileAccess.file_exists(raw) or DirAccess.dir_exists_absolute(raw)):
		return raw.replace("\\", "/").simplify_path()
	return raw.simplify_path()
