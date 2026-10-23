class_name DotMapIO
extends RefCounted

## The runtime for a map's input/output logic: outputs fire inputs at other entities after a delay.
## It is deterministic: time is the game's tick (see [method advance]), never the wall clock, and
## nothing here knows a body, a mesh or a sound. Only the server runs it.
##
## A game plugs in with [method register_handler] (what its own classes do with an input),
## [method register_class] (a class with state of its own) and the callables [member damage_fn],
## [member move_fn], [member effect_fn], [member event_fn]. Commands a map issues (a server
## command entity) are recorded in [member commands] and never executed.

const CHANNEL := "map.io"
const CODE_SOURCE_FORMAT := "dot-bsp-source"

## An entity changed: [code]key[/code] is "enabled", "color" or a logic class's own value.
signal state_changed(entity: DotMapEntity, key: String, value: Variant, tick: int)

## Ticks of the authoritative simulation per second; a link's delay is rounded to whole ticks.
var rate := 60
## The tick now: [method advance] moves it.
var now := 0
## Seeds every random choice; the same seed and inputs give the same run on every machine.
var rng_seed := 0
## Zero-delay hops allowed in one causal chain before the event is dropped as a loop.
var max_chain := 64
## Events one tick may run before the rest are dropped as a runaway.
var max_events_per_tick := 8192
## Cvar names (or [code]prefix*[/code] patterns) a map command may set; the rest is denied.
var command_allow := PackedStringArray()
## Keep [member history] of every state change (tests and replays).
var record_history := false

## [code]damage(body, amount, kind, attacker)[/code].
var damage_fn := Callable()
## [code]move_body(body, velocity_or_transform)[/code].
var move_fn := Callable()
## [code]effect(kind, entity, on)[/code].
var effect_fn := Callable()
## [code]event(kind, data)[/code]: text, hint, score, equip, say, cvar.
var event_fn := Callable()
## [code]actor(body, input, param, caller)[/code] for inputs aimed at [code]!activator[/code]/[code]!player[/code].
var actor_fn := Callable()
## [code]player() -> Variant[/code] for [code]!player[/code]; the activator when unset.
var player_fn := Callable()

var entities: Array = []
var history: Array = []
## Every map command seen: [code]{tick, entity, kind, text, name, allowed}[/code].
var commands: Array = []
## "classname|input" to the times an input arrived that no class or handler implements.
var unhandled: Dictionary = {}
## A game callable that was missing when needed, with how often.
var missing_callables: Dictionary = {}
var delivered := 0
var loop_trips := 0
var unresolved: Dictionary = {}

var _queue: Array = []
var _seq := 0
var _running := false
var _by_name: Dictionary = {}
var _by_index: Dictionary = {}
var _classes: Dictionary = {}
var _handlers: Dictionary = {}
var _streams: Dictionary = {}
var _catalogue: Dictionary = {}
var _tick_events := 0
var _current_depth := 0


func _init() -> void:
	_classes = {
		"logic_relay": DotMapRelay, "logic_timer": DotMapTimer, "math_counter": DotMapCounter,
		"logic_case": DotMapCase, "logic_compare": DotMapCompare, "logic_branch": DotMapBranch,
		"logic_auto": DotMapAuto, "trigger_multiple": DotMapTrigger, "trigger_once": DotMapTrigger,
		"point_servercommand": DotMapServerCommand, "point_clientcommand": DotMapServerCommand,
	}


## Builds from a source document ([code]dot-bsp-source[/code], the lossless store's
## [code]doc.json[/code]); this is the one place that reads its shape.
func load_document(doc: Dictionary) -> DotResult:
	if str(doc.get("format", "")) != CODE_SOURCE_FORMAT:
		return DotResult.fail(DotError.CODE_PARSE, "not a dot-bsp-source document")
	if int(doc.get("version", 0)) > 1:
		return DotResult.fail(DotError.CODE_VERSION, "source document version %s is newer than this reader" % doc.get("version"))
	var recs: Variant = doc.get("entities")
	if not recs is Array:
		return DotResult.fail(DotError.CODE_PARSE, "source document has no entity list")
	return load_records(recs)


## Builds from entity records ([code]index, classname, targetname, parentname, pairs, outputs[/code]);
## the interface any other source of a map's entities satisfies.
func load_records(records: Array) -> DotResult:
	entities = []
	_by_name = {}
	_by_index = {}
	_queue = []
	for r: Variant in records:
		if not r is Dictionary:
			return DotResult.fail(DotError.CODE_PARSE, "entity record is not a dictionary")
		var rec: Dictionary = r
		if not rec.has("classname"):
			return DotResult.fail(DotError.CODE_PARSE, "entity record without a classname")
		var cls := str(rec["classname"]).to_lower()
		var script: Variant = _classes.get(cls)
		var e: DotMapEntity = script.new() if script != null else DotMapEntity.new()
		e.load_record(rec)
		entities.append(e)
		_by_index[e.index] = e
		_index_name(e)
	DotLog.debug(CHANNEL, "loaded", {"entities": entities.size()})
	return DotResult.success(entities.size())


## Gives [param classname] an entity class of its own (a script extending [DotMapEntity]).
func register_class(classname: String, script: Script) -> DotResult:
	if classname.is_empty() or script == null:
		return DotResult.fail(DotError.CODE_INVALID, "register_class needs a class name and a script")
	_classes[classname.to_lower()] = script
	return DotResult.success()


## A game's meaning for inputs on [param classname]:
## [code]handler(entity, input, param, activator, caller) -> bool[/code], asked before the built-in
## inputs; true means handled.
func register_handler(classname: String, handler: Callable) -> DotResult:
	if classname.is_empty() or not handler.is_valid():
		return DotResult.fail(DotError.CODE_INVALID, "register_handler needs a class name and a valid callable")
	var key := classname.to_lower()
	if not _handlers.has(key):
		_handlers[key] = []
	(_handlers[key] as Array).append(handler)
	return DotResult.success()


## The class catalogue ([code]classes: {name: {inputs: {lower: name}}}[/code]) lets
## [method coverage] tell an input the engine has from a typo.
func set_catalogue(classes: Dictionary) -> void:
	_catalogue = classes


## Fires the map-start outputs (logic_auto, relay OnSpawn) and arms timers. Call once, at tick 0.
func start() -> void:
	for e: DotMapEntity in entities.duplicate():
		e.on_map_spawn(self)
	_flush()


## Moves time forward by [param ticks] and runs every event that falls due, in (tick, order).
func advance(ticks: int = 1) -> void:
	for i in ticks:
		now += 1
		_tick_events = 0
		_flush()


func seconds() -> float:
	return float(now) / float(rate)


func ticks_for(delay: float) -> int:
	return maxi(0, int(round(delay * rate)))


## Queues an input from outside (a button the game saw pressed, a trigger a body entered).
func send(target: String, input: String, param: String = "", delay: float = 0.0, activator: Variant = null) -> DotResult:
	if resolve(target, null, activator).is_empty() and not target.begins_with("!"):
		return DotResult.fail(DotError.CODE_INVALID, "no entity named %s" % target)
	_enqueue(target, input, param, now + ticks_for(delay), activator, null, null, 0)
	_flush()
	return DotResult.success()


## Fires [param output] on the entity with the map's [param index], as if it had raised it.
func raise(index: int, output: String, activator: Variant = null) -> DotResult:
	if not _by_index.has(index):
		return DotResult.fail(DotError.CODE_INVALID, "no entity %d" % index)
	(_by_index[index] as DotMapEntity).fire(self, output, activator)
	_flush()
	return DotResult.success()


## A body touched the trigger with the map's entity [param index]; the trigger class decides what that fires.
func touch(index: int, activator: Variant = null) -> DotResult:
	if not _by_index.get(index) is DotMapTrigger:
		return DotResult.fail(DotError.CODE_INVALID, "entity %d is not a trigger" % index)
	(_by_index[index] as DotMapTrigger).touch(self, activator)
	_flush()
	return DotResult.success()


## Entities that [param target] names: a targetname, a class name, or a [code]*[/code] pattern; the
## specials resolve against [param source] and [param activator].
func resolve(target: String, source: Variant, activator: Variant) -> Array:
	var out: Array = []
	var lo := target.to_lower()
	match lo:
		"!self", "!caller":
			if source is DotMapEntity:
				out.append(source)
			return out
		"!activator":
			if activator is DotMapEntity:
				out.append(activator)
			return out
		"!player":
			return out
	if lo.contains("*"):
		for e: DotMapEntity in entities:
			if e.alive and not e.targetname.is_empty() and e.targetname.matchn(target):
				out.append(e)
		return out
	for e: Variant in _by_name.get(lo, []):
		if (e as DotMapEntity).alive:
			out.append(e)
	if out.is_empty():
		for e: DotMapEntity in entities:
			if e.alive and e.classname.to_lower() == lo:
				out.append(e)
	return out


func find(targetname: String) -> Array:
	return resolve(targetname, null, null)


## Queues every link of [param output] on [param source]. Returns how many were queued.
func fire(source: DotMapEntity, output: String, activator: Variant, param: String = "") -> int:
	var lo := output.to_lower()
	var count := 0
	var spent: Array = []
	for link: Dictionary in source.links:
		if link["output"] != lo:
			continue
		var times: int = link["times"]
		if times == 0:
			continue
		var depth := 0
		var due := now + ticks_for(link["delay"])
		if due == now and _running:
			depth = _current_depth + 1
		if depth > max_chain:
			loop_trips += 1
			DotLog.warn(CHANNEL, "output chain dropped as a loop", {
				"from": source.targetname, "output": output, "target": link["target"], "input": link["input"]})
			continue
		var p: String = link["param"] if not str(link["param"]).is_empty() else param
		_enqueue(link["target"], link["input"], p, due, activator, source, source, depth)
		count += 1
		if times > 0:
			link["times"] = times - 1
			if times - 1 == 0:
				spent.append(link)
	for link: Dictionary in spent:
		source.links.erase(link)
	return count


## Queues an input for an entity itself (a timer's next beat); never counted as unhandled.
func schedule_self(entity: DotMapEntity, input: String, param: String, delay: float) -> void:
	_enqueue("#%d" % entity.index, input, param, now + ticks_for(delay), null, entity, null, 0)


## Removes the pending events [param source] queued (a relay's CancelPending).
func cancel_pending(source: DotMapEntity) -> int:
	var kept: Array = []
	for ev: Dictionary in _queue:
		if ev["source"] != source or str(ev["input"]).begins_with("__"):
			kept.append(ev)
	var removed := _queue.size() - kept.size()
	_queue = kept
	return removed


func pending() -> int:
	return _queue.size()


func kill(e: DotMapEntity) -> void:
	if not e.alive:
		return
	e.alive = false
	report_state(e, "alive", false)


## Kills [param e] and the entities whose parent it is.
func kill_hierarchy(e: DotMapEntity) -> void:
	kill(e)
	if e.targetname.is_empty():
		return
	for c: DotMapEntity in entities:
		if c.alive and c.parentname.to_lower() == e.targetname.to_lower():
			kill_hierarchy(c)


func rename(e: DotMapEntity, new_name: String) -> void:
	var old := e.targetname.to_lower()
	if _by_name.has(old):
		(_by_name[old] as Array).erase(e)
	e.targetname = new_name
	_index_name(e)


## Records a state change for listeners (and [member history] when asked).
func report_state(e: DotMapEntity, key: String, value: Variant) -> void:
	state_changed.emit(e, key, value, now)
	if record_history:
		history.append({"tick": now, "entity": e.index, "name": e.targetname, "key": key, "value": value})


## A random stream private to [param e]: same seed, same entity, same draws.
func stream_for(e: DotMapEntity) -> DotRandomStream:
	if not _streams.has(e.index):
		_streams[e.index] = DotRandomStream.new(rng_seed).stream(StringName("io%d" % e.index))
	return _streams[e.index]


## Records one map command and sends allowed ones to the game; nothing is ever executed here.
func record_command(e: DotMapEntity, text: String) -> Dictionary:
	var clean := text.strip_edges()
	var parts := clean.split(" ", false, 1)
	var name := parts[0].to_lower() if parts.size() > 0 else ""
	var rec := {"tick": now, "entity": e.index, "text": clean, "name": name, "kind": "denied", "allowed": false}
	if name == "say" or name == "say_team":
		rec["kind"] = "say"
		rec["allowed"] = true
	elif not name.is_empty() and _cvar_allowed(name):
		rec["kind"] = "cvar"
		rec["allowed"] = true
	commands.append(rec)
	if rec["allowed"]:
		event(str(rec["kind"]), rec)
	else:
		DotLog.info(CHANNEL, "map command denied", {"command": clean})
	return rec


## The game's event callable, or a counted no-op.
func event(kind: String, data: Dictionary) -> void:
	if event_fn.is_valid():
		event_fn.call(kind, data)
	else:
		_missing("event." + kind)


func effect(kind: String, e: DotMapEntity, on: bool) -> void:
	if effect_fn.is_valid():
		effect_fn.call(kind, e, on)
	else:
		_missing("effect." + kind)


func damage(body: Variant, amount: float, kind: String, attacker: Variant) -> void:
	if damage_fn.is_valid():
		damage_fn.call(body, amount, kind, attacker)
	else:
		_missing("damage")


func move_body(body: Variant, motion: Variant) -> void:
	if move_fn.is_valid():
		move_fn.call(body, motion)
	else:
		_missing("move_body")


## What the map asked for that nothing implemented: for the converter's coverage report.
func coverage() -> Dictionary:
	var unknown := {}
	for k: String in unhandled:
		var cls := k.get_slice("|", 0)
		var inp := k.get_slice("|", 1)
		var def: Dictionary = (_catalogue.get(cls, {}) as Dictionary).get("inputs", {})
		if not _catalogue.is_empty():
			unknown[k] = "known" if def.has(inp) else "not in the catalogue"
	return {"unhandled": unhandled.duplicate(), "catalogue": unknown, "missing_callables": missing_callables.duplicate(),
			"unresolved": unresolved.duplicate(), "loop_trips": loop_trips, "commands_denied": _denied()}


## A snapshot of every entity's state, for a joining client.
func snapshot() -> Dictionary:
	var out := {}
	for e: DotMapEntity in entities:
		out[e.index] = e.state()
	return {"tick": now, "entities": out}


func describe() -> Dictionary:
	return {"tick": now, "seconds": seconds(), "entities": entities.size(), "pending": _queue.size(),
			"delivered": delivered, "unhandled": unhandled.size(), "loop_trips": loop_trips,
			"commands": commands.size(), "denied": _denied(),
			"callables": {"damage": damage_fn.is_valid(), "move": move_fn.is_valid(),
				"effect": effect_fn.is_valid(), "event": event_fn.is_valid()}}


func _denied() -> int:
	var n := 0
	for c: Dictionary in commands:
		if not c["allowed"]:
			n += 1
	return n


func _cvar_allowed(name: String) -> bool:
	for pat in command_allow:
		if name.matchn(pat):
			return true
	return false


func _missing(what: String) -> void:
	missing_callables[what] = int(missing_callables.get(what, 0)) + 1


func _index_name(e: DotMapEntity) -> void:
	if e.targetname.is_empty():
		return
	var k := e.targetname.to_lower()
	if not _by_name.has(k):
		_by_name[k] = []
	(_by_name[k] as Array).append(e)


func _enqueue(target: String, input: String, param: String, due: int, activator: Variant, source: Variant, caller: Variant, depth: int) -> void:
	var ev := {"due": due, "seq": _seq, "target": target, "input": input, "param": param,
			"activator": activator, "source": source, "caller": caller, "depth": depth}
	_seq += 1
	var i := _queue.size()
	while i > 0 and int((_queue[i - 1] as Dictionary)["due"]) > due:
		i -= 1
	_queue.insert(i, ev)


func _flush() -> void:
	if _running:
		return
	_running = true
	while not _queue.is_empty() and int((_queue[0] as Dictionary)["due"]) <= now:
		if _tick_events >= max_events_per_tick:
			loop_trips += 1
			DotLog.error(CHANNEL, "too many events in one tick; dropping the rest", {"tick": now, "dropped": _queue.size()})
			var kept: Array = []
			for q: Dictionary in _queue:
				if int(q["due"]) > now:
					kept.append(q)
			_queue = kept
			break
		_tick_events += 1
		var ev: Dictionary = _queue.pop_front()
		_current_depth = ev["depth"]
		_deliver(ev)
	_running = false


func _deliver(ev: Dictionary) -> void:
	var target: String = ev["target"]
	var input: String = ev["input"]
	var source: Variant = ev["caller"]
	var activator: Variant = ev["activator"]
	var param: String = ev["param"]
	if target.begins_with("#"):
		var idx := int(target.substr(1))
		if _by_index.has(idx):
			(_by_index[idx] as DotMapEntity).accept(self, input, param, activator, null)
		return
	delivered += 1
	var lo := target.to_lower()
	if lo == "!activator" or lo == "!player":
		var actor: Variant = activator
		if lo == "!player" and player_fn.is_valid():
			actor = player_fn.call()
		if actor is DotMapEntity:
			_to_entity(actor, input, param, activator, source)
		elif actor_fn.is_valid():
			actor_fn.call(actor, input, param, source)
		else:
			_missing("actor." + input.to_lower())
		return
	var targets := resolve(target, source, activator)
	if targets.is_empty():
		unresolved[target] = int(unresolved.get(target, 0)) + 1
		return
	for e: DotMapEntity in targets:
		_to_entity(e, input, param, activator, source)


func _to_entity(e: DotMapEntity, input: String, param: String, activator: Variant, caller: Variant) -> void:
	for h: Callable in _handlers.get(e.classname.to_lower(), []):
		if h.is_valid() and h.call(e, input, param, activator, caller):
			return
	if not e.accept(self, input, param, activator, caller):
		var k := "%s|%s" % [e.classname.to_lower(), input.to_lower()]
		unhandled[k] = int(unhandled.get(k, 0)) + 1
