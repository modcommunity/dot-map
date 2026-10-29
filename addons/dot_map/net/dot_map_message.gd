class_name DotMapMessage
extends RefCounted

## The four messages a map change is made of, as plain [Dictionary]s because dot-map depends on nothing but dot-core and cannot know the game's transport.
## announce (host to peer: fetch this map), progress (peer to host), ready (peer to host: I have it), load (host to peer: everyone has it, show it).
## "load" is separate from "announce" because the host must not switch before its clients can; collapsing them is the map-change bug of a client sent to load a game the server had not swapped to.

## Host to peer: fetch this map's content.
const KIND_ANNOUNCE := &"map.announce"

## Peer to host: I am this far through fetching it.
const KIND_PROGRESS := &"map.progress"

## Peer to host: I have it, or I already had it.
const KIND_READY := &"map.ready"

## Host to peer: put it in the world now.
const KIND_LOAD := &"map.load"

## Host to peer: the change was abandoned; stay where you are.
const KIND_ABORT := &"map.abort"


static func announce(map: DotMapDef) -> Dictionary:
	return {
		"kind": String(KIND_ANNOUNCE),
		# The whole definition, not just the id. A client that does not have this map in its own catalogue — a map
		# added to a server since the client last updated, which on a records server is most of them — has no other
		# way to learn its content id and version.
		"map": map.to_dictionary(),
	}


static func progress(map_id: StringName, fraction: float) -> Dictionary:
	return {
		"kind": String(KIND_PROGRESS),
		"map": String(map_id),
		"fraction": clampf(fraction, 0.0, 1.0),
	}


static func ready(map_id: StringName, version: String) -> Dictionary:
	return {
		"kind": String(KIND_READY),
		"map": String(map_id),
		# The version, not only the id. A peer that has version 1.0.0 of a map the host has just republished as
		# 1.1.0 is not ready, and says so with the same message it would use if it were.
		"version": version,
	}


static func load_now(map_id: StringName, version: String) -> Dictionary:
	return {
		"kind": String(KIND_LOAD),
		"map": String(map_id),
		"version": version,
	}


static func abort(map_id: StringName, reason: String) -> Dictionary:
	return {
		"kind": String(KIND_ABORT),
		"map": String(map_id),
		"reason": reason,
	}


static func kind_of(payload: Dictionary) -> StringName:
	return StringName(str(payload.get("kind", "")))


## Whether a payload is one of ours at all. A host may well put these on the same channel as its own traffic,
## so both ends need a cheap way to say "not mine" rather than misreading somebody else's dictionary.
static func is_map_message(payload: Dictionary) -> bool:
	var kind := kind_of(payload)
	return kind == KIND_ANNOUNCE or kind == KIND_PROGRESS \
		or kind == KIND_READY or kind == KIND_LOAD or kind == KIND_ABORT
