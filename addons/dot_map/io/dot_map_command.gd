class_name DotMapCommand
extends RefCounted

## What a map may ask the server to do. A map's command entity never runs anything: its text is
## split into single commands and each is judged here, then recorded by [DotMapIO]. Allowed is a
## chat line or a cvar the operator listed, with a plain value; the names below are denied even
## when a pattern would match, so a careless allow-list cannot hand a map the server.

## A first word that is never allowed.
const NEVER := ["quit", "exit", "exec", "alias", "bind", "unbind", "connect", "disconnect", "map", "changelevel",
		"kick", "kickid", "ban", "banid", "addip", "rcon", "rcon_password", "sv_password", "script", "lua_run",
		"sm", "plugin_load", "writeid", "cfg", "echo", "wait", "toggle", "incrementvar", "cvarlist", "find",
		"changemap", "gamechange", "game", "sv_map", "restart", "shutdown", "sv_cheats", "writeconfig", "host_writeconfig",
		"load", "save", "sv_rcon", "setpause", "unpause", "_restart", "disconnect_all", "status", "mp_restartgame"]
const MAX_LENGTH := 256
const MAX_SAY := 200

static var _name_re: RegEx = null
static var _value_re: RegEx = null


## Splits [param text] on [code];[/code] into trimmed, non-empty commands.
static func split(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	for part in text.split(";", false):
		var c := part.strip_edges()
		if not c.is_empty():
			out.append(c)
	return out


## Judges one command against [param allow] (cvar names or [code]prefix*[/code] patterns):
## [code]{name, args, kind: say|cvar|denied, allowed, reason}[/code].
static func judge(command: String, allow: PackedStringArray) -> Dictionary:
	if _name_re == null:
		_name_re = RegEx.create_from_string("^[a-z0-9_.]+$")
		_value_re = RegEx.create_from_string("^[A-Za-z0-9_.,:+\\- ]*$")
	var clean := command.strip_edges()
	var parts := clean.split(" ", false, 1)
	var name := parts[0].to_lower() if parts.size() > 0 else ""
	var args := parts[1].strip_edges() if parts.size() > 1 else ""
	var rec := {"name": name, "args": args, "kind": "denied", "allowed": false, "reason": ""}
	if clean.length() > MAX_LENGTH:
		rec["reason"] = "too long"
	elif name.is_empty() or _name_re.search(name) == null:
		rec["reason"] = "not a plain command name"
	elif name == "say" or name == "say_team":
		if args.length() > MAX_SAY or args.contains("\n"):
			rec["reason"] = "chat line too long"
		elif args.begins_with("!") or args.begins_with("/") or args.begins_with("\"!") or args.begins_with("\"/"):
			rec["reason"] = "chat line would be read as a command"
		else:
			rec["kind"] = "say"
			rec["allowed"] = true
	elif NEVER.has(name) or name.begins_with("rcon") or name.begins_with("sv_rcon") or name.begins_with("ds_"):
		rec["reason"] = "never allowed"
	else:
		var listed := false
		for pat in allow:
			if name.matchn(pat):
				listed = true
				break
		if not listed:
			rec["reason"] = "not on the allow-list"
		elif _value_re.search(args) == null:
			rec["reason"] = "value has characters a setting never needs"
		else:
			rec["kind"] = "cvar"
			rec["allowed"] = true
	return rec
