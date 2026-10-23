class_name DotMapStateSync
extends RefCounted

## Carries a map's changing state from the server's [DotMapIO] to its clients, which run no logic.
##
## The host batches every [signal DotMapIO.state_changed] of a call into one message and sends it
## per peer through [member send_fn]; a peer added mid-game first gets a full snapshot, so a joiner
## sees the door where it is, the brush hidden and the glass broken. A client feeds each message to
## [method apply]. Messages are plain dictionaries of numbers, strings, bools and arrays, so any
## transport carries them. Motion needs no stream: a mover's message holds where it started and
## when, and each end works out the pose for its own tick.

const TYPE_STATE := "io_state"
const TYPE_SNAPSHOT := "io_snapshot"

## [code]send(peer, message: Dictionary)[/code], called once per peer, never with a broadcast id.
var send_fn := Callable()
var peers: Array = []
## Keys not sent (a logic value only the server reads).
var skip_keys: PackedStringArray = ["triggered"]
## Changes applied, and ones refused (unknown entity or key, bad shape), on a client.
var applied := 0
var refused := 0
## Keys a class does not carry to clients (a counter's value, say).
var ignored := 0

var _io: DotMapIO = null
var _pending: Array = []


## Starts listening to [param io] as the authority.
func attach_host(io: DotMapIO, send: Callable) -> void:
	_io = io
	send_fn = send
	io.state_changed.connect(_on_state)
	io.settled.connect(_on_settled)


## Lets [param peer] in: it is sent the whole state now and every change after.
func add_peer(peer: Variant) -> void:
	if peers.has(peer):
		return
	peers.append(peer)
	if _io != null and send_fn.is_valid():
		send_fn.call(peer, snapshot_message())


func remove_peer(peer: Variant) -> void:
	peers.erase(peer)


func snapshot_message() -> Dictionary:
	var snap := _io.snapshot()
	return {"type": TYPE_SNAPSHOT, "tick": snap["tick"], "entities": snap["entities"]}


func _on_state(e: DotMapEntity, key: String, value: Variant, _tick: int) -> void:
	if key in skip_keys or not _io.authoritative:
		return
	_pending.append([e.index, key, value])


func _on_settled(tick: int) -> void:
	if _pending.is_empty():
		return
	var msg := {"type": TYPE_STATE, "tick": tick, "changes": _pending}
	_pending = []
	if send_fn.is_valid():
		for p: Variant in peers:
			send_fn.call(p, msg)


## A client takes one message from the host into [param io] (built with [member DotMapIO.authoritative]
## false from the same records). Returns how many changes it applied.
func apply(io: DotMapIO, msg: Dictionary) -> DotResult:
	var kind := str(msg.get("type", ""))
	if kind != TYPE_STATE and kind != TYPE_SNAPSHOT:
		return DotResult.fail(DotError.CODE_PARSE, "not a map state message")
	if not msg.get("tick") is int and not msg.get("tick") is float:
		return DotResult.fail(DotError.CODE_PARSE, "state message without a tick")
	var tick := int(msg["tick"])
	io.now = maxi(io.now, tick) if kind == TYPE_STATE else tick
	var n := 0
	if kind == TYPE_SNAPSHOT:
		var ents: Variant = msg.get("entities")
		if not ents is Dictionary:
			return DotResult.fail(DotError.CODE_PARSE, "snapshot without entities")
		for k: Variant in ents:
			var st: Variant = ents[k]
			if st is Dictionary:
				for key: Variant in st:
					n += _apply_one(io, int(k), str(key), st[key], tick)
	else:
		var changes: Variant = msg.get("changes")
		if not changes is Array:
			return DotResult.fail(DotError.CODE_PARSE, "state message without changes")
		for c: Variant in changes:
			if c is Array and (c as Array).size() == 3:
				n += _apply_one(io, int(c[0]), str(c[1]), c[2], tick)
			else:
				refused += 1
	return DotResult.success(n)


func _apply_one(io: DotMapIO, index: int, key: String, value: Variant, tick: int) -> int:
	var e := io.entity_of(index)
	if e == null:
		refused += 1
		return 0
	if not e.apply_state(io, key, value, tick):
		ignored += 1
		return 0
	applied += 1
	return 1
