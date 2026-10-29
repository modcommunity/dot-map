class_name DotMapCommands
extends RefCounted

## `map`, `maps` and `mapinfo` on a dot-server in one call: [code]DotMapCommands.install(self, session[, sync_host])[/code].
## Duck-typed host (add_command or command) and context (reply, args), so no dot-server class is named. `map` changes the world, not the game;
## there is no `nextmap` or `timeleft` because dot-vote registers those over the same maps.

const CHANNEL := "map.commands"

## Default command names, by role. Override any of them through [member names].
const DEFAULTS := {
	"map": "map",
	"maps": "maps",
	"mapinfo": "mapinfo",
	"rotation": "sv_map_rotation",
	"rotations": "maps_rotations",
}

## Which of the above are marked typable in chat whatever the host server's default is. Both of the read-only
## ones.
const CHAT := ["maps", "mapinfo", "rotations"]

## The server's maps.yml, for `sv_map_rotation` and `maps_rotations`. Optional: without one
## those two say there is no rotation file and `maps` lists every map unmarked.
var rotation_file: DotMapRotationFile = null

## `() -> DotMapRotationFile`, for a game that re-reads maps.yml and so replaces the object.
## Takes precedence over [member rotation_file].
var rotation_file_fn: Callable = Callable()

## Where the catalogue, the current map and the clock are read from.
var session: DotMapSession = null

## What actually performs the change. A [DotMapSession], or a [DotMapSyncHost] in front of one when the
## change has to reach clients rather than only the server's own process. Duck-typed on `change_to`, because
## those two are the same three methods and dot-map must not care which is in front.
var changer: Object = null

## `(id: StringName) -> DotResult`, for a host whose change is its own method. Takes precedence over [member
## changer]. game-playground's `change_map` resets the props, the NPCs and the course before it touches the
## session, so handing the session straight to a command would change the world out from under all three.
var change_fn: Callable = Callable()

## Prepended to every command name. `"sv_"` gives `sv_map`.
var prefix: String = ""

## Per-role name overrides, e.g. `{"maps": "maplist"}`.
var names: Dictionary = {}

## Where an operator's `commands:` block comes from: `() -> Dictionary` with `prefix` and `names` (a name or
## a list of names per role; the rest are aliases). Read once by [method bind], so the file wins over the
## game's own settings. A game points it at its rotation file (`file.commands`) and names nothing itself.
var spec_fn: Callable = Callable()

## What a player types before a command in chat, for text shown to players.
var chat_prefix: String = "!"

## Names refused because something else had them.
var skipped: PackedStringArray = PackedStringArray()

## Permission `map` needs. Empty makes it console-only.
var admin_permission: String = "changemap"

## Whether `map` may be typed in chat at all. On. It is [member admin_permission] that decides whether a
## particular person may change the map, and a player without `changemap` is refused the same way in chat as
## anywhere else.
var allow_chat_change: bool = true

## How many players are present, for the availability filter. Optional.
var player_count_fn: Callable = Callable()

## Whether `map <id>` may be given an id the catalogue does not hold. Off, and it has to be, because the
## catalogue is what a map id MEANS on most servers.
var may_fetch_unknown: bool = false

## Names actually registered, for a module that has to remove them again.
var registered: PackedStringArray = PackedStringArray()


static func install(
	host: Object, p_session: DotMapSession, p_changer: Object = null
) -> DotMapCommands:
	var commands := DotMapCommands.new()
	commands.session = p_session
	commands.changer = p_changer if p_changer != null else p_session
	commands.bind(host)
	return commands


## The same, for a host whose map change is its own method rather than an object.
static func install_with(
	host: Object, p_session: DotMapSession, p_change_fn: Callable
) -> DotMapCommands:
	var commands := DotMapCommands.new()
	commands.session = p_session
	commands.changer = p_session
	commands.change_fn = p_change_fn
	commands.bind(host)
	return commands


## The name help and hints show for a role: the primary, prefix included.
func command_name(role: String) -> String:
	return DotCommandNames.all_of(prefix, names, DEFAULTS, role)[0]


## Every name a role answers to, the primary first.
func command_names(role: String) -> PackedStringArray:
	return DotCommandNames.all_of(prefix, names, DEFAULTS, role)


## What a player types in chat for a role.
func typed(role: String) -> String:
	return DotCommandNames.typed(chat_prefix, command_name(role))


## Registers everything on [param host].
func bind(host: Object) -> DotResult:
	if host == null or session == null:
		return DotResult.fail(
			DotError.CODE_INVALID, "A host and a map session are both needed."
		)
	if changer == null:
		changer = session

	if spec_fn.is_valid():
		var from_file: Variant = spec_fn.call()
		if from_file is Dictionary:
			DotCommandNames.apply(self, from_file)

	var adder := ""
	if host.has_method("add_command"):
		adder = "add_command"
	elif host.has_method("command"):
		adder = "command"
	else:
		return DotResult.fail(
			DotError.CODE_UNSUPPORTED,
			"That host has no way to register a command.",
			"expected a DotModule (add_command) or a DotConsole (command)"
		)

	var table := {
		"map": [_cmd_map, "Change the map, or list what there is", admin_permission],
		"maps": [_cmd_maps, "List the maps this server can load", ""],
		"mapinfo": [_cmd_mapinfo, "What is running, what is next, and how long is left", ""],
		"rotations": [_cmd_rotations, "List the map rotations in maps.yml", ""],
		"rotation": [_cmd_rotation, "Show or switch the active map rotation", admin_permission],
	}

	for role: Variant in table:
		var entry: Array = table[role]

		for full in command_names(str(role)):
			if not DotCommandNames.available(host, full, registered, str(role), "map"):
				skipped.append(full)
				continue

			var registered_command: Variant = host.call(adder, full, entry[0], entry[1], entry[2])

			if registered_command is Object:
				_decorate(registered_command as Object, str(role))

			registered.append(full)

	DotLog.info(CHANNEL, "commands registered", {"count": registered.size()})
	return DotResult.success(registered)


## Applies the usage, chat and completion hints a registered command supports; each is duck-typed.
func _decorate(cmd: Object, role: String) -> void:
	if role == "rotation" and cmd.has_method("with_usage"):
		cmd.call("with_usage", "[rotation]")
	if CHAT.has(role):
		if cmd.has_method("with_chat"):
			cmd.call("with_chat")
	elif role == "map" and not allow_chat_change:
		# Duck-typed, like everything else here: `no_chat()` is dot-server's, and a
		# host console that predates it simply keeps the host's own default rather
		# than failing to register the command.
		if cmd.has_method("no_chat"):
			cmd.call("no_chat")
		elif cmd.has_method("with_chat"):
			cmd.call("with_chat", false)
	if role == "map":
		if cmd.has_method("with_usage"):
			cmd.call("with_usage", "[map_id]")
		# A completer, because a map id is the one argument nobody remembers. The lambda reads the catalogue at
		# completion time rather than closing over a list: a catalogue that gains a map after boot is the normal
		# case on a server that mounts delivered content.
		if cmd.has_method("with_completer"):
			cmd.call("with_completer", func(_p: String, _i: int) -> PackedStringArray:
				return map_ids()
			)


## Every map id this server could load, sorted. Sorted as Strings and never as StringNames: `Array.sort()` on
## a `StringName` compares interned pointers, which is how two peers in this family once assigned two
## different wire ids to one message type.
func map_ids() -> PackedStringArray:
	var out := PackedStringArray()
	if session == null or session.catalogue == null:
		return out
	# Every ENABLED map, in rotation or not: `map <id>` loads either, and the completer and
	# the list must say so. What the rotation plays is DotMapRotation.pool().
	for m in session.catalogue.maps:
		if m.enabled and m.available_for_players(_players()):
			out.append(String(m.id))
	out.sort()
	return out


func _players() -> int:
	return int(player_count_fn.call()) if player_count_fn.is_valid() else 0


func _args(ctx: Object) -> PackedStringArray:
	var args: Variant = ctx.get("args")
	return args as PackedStringArray if args is PackedStringArray else PackedStringArray()


func _reply(ctx: Object, text: String) -> void:
	ctx.call("reply", text)


func _reply_lines(ctx: Object, lines: PackedStringArray) -> void:
	if ctx.has_method("reply_lines"):
		ctx.call("reply_lines", lines)
		return
	for l in lines:
		_reply(ctx, l)


func _reply_result(ctx: Object, result: DotResult, ok_text: String) -> void:
	if result.ok:
		_reply(ctx, ok_text)
		return
	# The detail is included deliberately. "You cannot load that" is an argument with the
	# server; "not in the catalogue; did you mean surf_mesa" is an answer.
	var detail := result.error.detail if result.error != null else ""
	_reply(ctx, "%s%s" % [
		result.error.message if result.error != null else "Refused.",
		" (%s)" % detail if detail != "" else "",
	])


func _cmd_map(ctx: Object) -> void:
	var args := _args(ctx)
	if args.is_empty():
		# With no argument this lists rather than refusing. An operator who types `map` to
		# remind themselves what there is should not have to be told the usage first.
		_cmd_maps(ctx)
		return

	var id := StringName(args[0])
	var known := session.catalogue == null or session.catalogue.has(id)

	if not known and not may_fetch_unknown:
		_reply(ctx, _refuse_unknown(args[0]))
		return

	_reply(ctx, "Changing to %s…" % args[0])

	# AWAITED, and this is the line that would otherwise be wrong in the way this family has a name for:
	# `DotMapSession.change_to` and `DotMapSyncHost.change_to` are both coroutines, so calling one without
	# awaiting returns a `GDScriptFunctionState` at its first `await` -- which is not a `DotResult`, so the...
	var res: Variant = (
		await change_fn.call(id) if change_fn.is_valid()
		else await changer.call("change_to", id)
	)
	if res is DotResult:
		var done := res as DotResult
		# The hint moves here rather than being dropped. An id that was not in the catalogue and could not be
		# fetched either is the typo case after all, and the suggestion is worth exactly as much now as it was
		# worth before the attempt -- it is only the REFUSAL that had to wait for the changer to have its say.
		if not done.ok and not known:
			_reply(ctx, _refuse_unknown(args[0]))
		else:
			_reply_result(ctx, done, "Now on %s." % args[0])
	else:
		# A changer that answered with something else is a wiring mistake, not a refusal,
		# and saying nothing at all is how it survives.
		_reply(ctx, "The map change did not report a result.")


## "No map called X", with the near matches the catalogue can offer.
func _refuse_unknown(typed: String) -> String:
	var hint := PackedStringArray()
	if session != null and session.catalogue != null:
		for m in session.catalogue.search(typed, 5):
			hint.append(String(m.id))
	return "No map called '%s'.%s" % [
		typed,
		" Did you mean: %s" % ", ".join(hint) if not hint.is_empty() else "",
	]


func _cmd_maps(ctx: Object) -> void:
	if session.catalogue == null:
		_reply(ctx, "This server has no map catalogue.")
		return
	var ids := map_ids()
	if ids.is_empty():
		_reply(ctx, "No maps are available right now.")
		return
	# A subscription's maps carry their pack, so a player sees which are theirs.
	var shown := PackedStringArray()
	for id in ids:
		var def := session.catalogue.get_map(StringName(id))
		var label := id if def == null or def.pack_title == "" else "%s [%s]" % [id, def.pack_title]
		# Installed and loadable, just not played: said, not hidden.
		if def != null and not def.in_rotation:
			label += " (not in rotation)"
		shown.append(label)
	_reply(ctx, "%d maps: %s" % [ids.size(), ", ".join(shown)])


func _cmd_mapinfo(ctx: Object) -> void:
	_reply_lines(ctx, session.describe_lines())


func _file() -> DotMapRotationFile:
	if rotation_file_fn.is_valid():
		return rotation_file_fn.call() as DotMapRotationFile
	return rotation_file


func _cmd_rotations(ctx: Object) -> void:
	var rotation_file := _file()
	if rotation_file == null or not rotation_file.has_rotations():
		_reply(ctx, "No map rotation file; every map plays.")
		return
	_reply_lines(ctx, rotation_file.describe_lines())


func _cmd_rotation(ctx: Object) -> void:
	var rotation_file := _file()
	if rotation_file == null or not rotation_file.has_rotations():
		_reply(ctx, "No map rotation file; every map plays.")
		return
	var args := _args(ctx)
	if args.is_empty():
		_reply(ctx, "Rotation %s (of: %s)." % [rotation_file.active_name(), ", ".join(rotation_file.rotation_names())])
		return
	_reply_result(ctx, rotation_file.switch(session.rotation, args[0]), "Now playing rotation %s." % args[0])
