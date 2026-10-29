class_name DotMapStateTransport
extends RefCounted

## The reference [member DotMapStateSync.send_fn] for a game: queues each peer's state messages, sends them as few payloads as the game's channel allows ([member max_bytes]), and unpacks them on the client.
## Set [member raw_send], pass [code]t.send[/code] as the world's send_fn, call [code]t.flush_on(world.io)[/code] after the sync's own handler, and feed incoming payloads to [code]t.receive[/code] when [method is_state_payload].
## One message bigger than [member max_bytes] goes alone, so the channel must carry that size. Nothing here names a net addon.

const TYPE_BATCH := "io_batch"

## [code]raw_send(peer, payload: Dictionary)[/code]: the game's reliable channel.
var raw_send := Callable()
## A batch stops growing past this many bytes of JSON (a usual packet's payload).
var max_bytes := 1100
## Payloads sent, and messages inside them.
var payloads := 0
var messages := 0

var _queues: Dictionary = {}


## The [member DotMapStateSync.send_fn] shape: queues [param msg] for [param peer].
func send(peer: Variant, msg: Dictionary) -> void:
	if not _queues.has(peer):
		_queues[peer] = []
	(_queues[peer] as Array).append(msg)


## Sends every queue now.
func flush() -> void:
	if not raw_send.is_valid():
		_queues.clear()
		return
	for peer: Variant in _queues:
		var batch: Array = []
		var size := 0
		for m: Dictionary in _queues[peer]:
			var n := JSON.stringify(m).length()
			if not batch.is_empty() and size + n > max_bytes:
				_emit(peer, batch)
				batch = []
				size = 0
			batch.append(m)
			size += n
		if not batch.is_empty():
			_emit(peer, batch)
	_queues.clear()


## Flushes whenever [param io] settles a tick; connect after the [DotMapStateSync] so its message is queued first.
func flush_on(io: DotMapIO) -> void:
	io.settled.connect(func(_tick: int) -> void: flush())


func _emit(peer: Variant, batch: Array) -> void:
	payloads += 1
	messages += batch.size()
	raw_send.call(peer, batch[0] if batch.size() == 1 else {"type": TYPE_BATCH, "messages": batch})


## Whether [param payload] is for [method receive]: a batch, or one state message.
static func is_state_payload(payload: Dictionary) -> bool:
	var t := str(payload.get("type", ""))
	return t == TYPE_BATCH or t == DotMapStateSync.TYPE_STATE or t == DotMapStateSync.TYPE_SNAPSHOT


## Feeds a payload to [param sync] on a client; the result's value is the changes applied.
func receive(io: DotMapIO, sync: DotMapStateSync, payload: Dictionary) -> DotResult:
	if str(payload.get("type", "")) != TYPE_BATCH:
		return sync.apply(io, payload)
	var list: Variant = payload.get("messages")
	if not list is Array:
		return DotResult.fail(DotError.CODE_PARSE, "batch without messages")
	var n := 0
	for m: Variant in list:
		if not m is Dictionary:
			return DotResult.fail(DotError.CODE_PARSE, "batch holds a non-message")
		var r := sync.apply(io, m)
		if not r.ok:
			return r
		n += int(r.value)
	return DotResult.success(n)
