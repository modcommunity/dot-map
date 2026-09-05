@tool
class_name DotMapSyncClient
extends Node

## A peer's half of a map change: fetch what the host named, say so, then show it.
##
## The counterpart to [DotMapSyncHost]. Transport-agnostic for the same reason — set
## [member send_fn] to anything that can put a [Dictionary] in front of the host, and
## feed whatever arrives into [method handle].
##
## [codeblock]
## var sync := DotMapSyncClient.new()
## sync.session = map_session
## sync.send_fn = func(payload: Dictionary) -> void: link.send(payload)
## add_child(sync)
##
## link.message_received.connect(func(p): sync.handle(p))
## [/codeblock]
##
## [b]A host does not get to name a scene path.[/b] This is the same rule
## [code]DotClientLink._resolve_scene[/code] enforces and it is here for the same reason:
## a client that loads whatever absolute [code]res://[/code] path it is sent will load
## anything in its own build if a hostile server asks. So by default the map is taken
## from this client's [b]own catalogue[/b] by id, and the announced definition is used
## only for the fields that cannot be spoofed into something dangerous. See
## [member accept_unknown_maps], which is what a records server with two hundred maps and
## a client that ships none of them needs, and which is safe only because a map accepted
## that way must live inside dot-cloud's mount.

const CHANNEL := "map.sync.client"

## The mount prefix a delivered map's scene must be under to be accepted from a host.
##
## Duplicated from dot-cloud rather than read from it: this addon must compile in a
## project that does not have dot-cloud, and a constant that disagreed with dot-cloud
## would fail closed — a refused map, not a loaded wrong one.
const MOUNT_ROOT := "res://dot_cloud/"

## The registry name dot-cloud publishes its client under.
const CLOUD_SERVICE := &"dot_cloud_client"

## The host announced a map and the fetch has begun. For a progress screen.
signal fetching(map: DotMapDef)

## Fetch progress, 0..1.
signal fetch_progress(fraction: float)

## The content is here. The host has not said to show it yet.
signal content_ready(map: DotMapDef)

## The map is in the world.
signal changed(map: DotMapDef)

## Something went wrong on this end. The host will time this peer out.
signal fetch_failed(map: DotMapDef, error: DotError)

## The host abandoned the change.
signal change_aborted(map_id: StringName, reason: String)

@export_group("Wiring")

## The session this drives. Required.
@export var session_ref: DotNodeRef = null

@export_group("Trust")

## Accept a map definition the host sent that this client's catalogue does not have.
##
## [b]On, and the refusal below is what makes that safe.[/b] A records server carries
## two hundred maps and a client ships none of them, so a client that only knew its own
## catalogue could join such a server and never load a single map. What keeps it honest
## is [method _accept]: an unknown map must be [i]delivered[/i] — it must name a content
## id, and its scene must resolve inside [constant MOUNT_ROOT] — so the worst a hostile
## host can do is make this client download and mount its own content, which is what
## joining a server already means.
##
## Off is for a client that ships every map it will ever play and should refuse to be
## sent anywhere else.
@export var accept_unknown_maps: bool = true

## Add maps accepted from a host to this client's catalogue.
##
## So the second time round is a catalogue hit rather than a re-negotiation, and so a
## client can list where it has been.
@export var remember_accepted_maps: bool = true

## The session this drives, assigned directly when there is no [member session_ref].
var session: DotMapSession = null

## Sends one payload to the host. Set by the game.
var send_fn: Callable = Callable()

## The map this client was last told to get, whether or not it has it.
var announced: DotMapDef = null

## Whether the content for [member announced] is here.
var is_ready: bool = false

var _fetching: bool = false

## The cloud progress subscription, kept so it is only ever made once.
var _progress_handler: Callable = Callable()


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	if session == null and session_ref != null:
		var resolved := session_ref.resolve(self)
		if resolved.ok:
			session = resolved.value as DotMapSession


# --- Receiving -------------------------------------------------------------

## Feeds one payload from the host in.
##
## Returns whether it was a map message, so a game sharing a channel can keep looking.
## [b]Not awaited by the caller[/b] — an announce starts a fetch that can take minutes,
## and a transport's receive path must not be suspended for it.
func handle(payload: Dictionary) -> bool:
	if not DotMapMessage.is_map_message(payload):
		return false

	match DotMapMessage.kind_of(payload):
		DotMapMessage.KIND_ANNOUNCE:
			var announcement: Variant = payload.get("map", {})
			if announcement is Dictionary:
				_on_announce(announcement as Dictionary)
			return true

		DotMapMessage.KIND_LOAD:
			_on_load(
				StringName(str(payload.get("map", ""))),
				str(payload.get("version", ""))
			)
			return true

		DotMapMessage.KIND_ABORT:
			var id := StringName(str(payload.get("map", "")))
			var reason := str(payload.get("reason", ""))
			DotLog.info(CHANNEL, "the host abandoned the map change", {
				"map": String(id), "why": reason
			})
			announced = null
			is_ready = false
			change_aborted.emit(id, reason)
			return true

	# A ready or a progress arriving here is the host talking like a peer, which is a
	# wiring mistake worth seeing rather than ignoring.
	DotLog.warn(CHANNEL, "the host sent a peer-only message", {
		"kind": String(DotMapMessage.kind_of(payload))
	})
	return true


func _on_announce(dict: Dictionary) -> void:
	var accepted := _accept(dict)

	if not accepted.ok:
		DotLog.warn(CHANNEL, "refusing the announced map", {
			"why": accepted.error.message, "detail": accepted.error.detail
		})
		# Deliberately silent to the host beyond not reporting ready: it will time
		# this peer out and do whatever it does about that. Reporting ready for a map
		# that was refused is the one answer that must never be given.
		fetch_failed.emit(null, accepted.error)
		return

	var map: DotMapDef = accepted.value

	announced = map
	is_ready = false

	_fetch(map)


## Fetches the announced map's content and reports readiness.
##
## Its own coroutine rather than an awaited call from [method handle], so a transport's
## receive path is never suspended for the length of a download.
func _fetch(map: DotMapDef) -> void:
	if _fetching:
		# A second announce while the first is in flight is a host that changed its
		# mind. The first fetch finishes and reports against the map it was for; the
		# host compares ids and versions, so a stale report cannot be mistaken for a
		# current one.
		DotLog.debug(CHANNEL, "already fetching; the newer announce will follow")

	if session == null or session.loader == null:
		fetch_failed.emit(map, DotError.make(
			DotError.CODE_STATE, "No map session to fetch through."
		))
		return

	if session.loader.is_ready(map):
		# Already here. Reported immediately rather than after a no-op fetch, which is
		# what makes changing back to a map everybody has instant.
		is_ready = true
		content_ready.emit(map)
		_send(DotMapMessage.ready(map.id, map.version))
		return

	_fetching = true
	_subscribe_to_progress()
	fetching.emit(map)
	_send(DotMapMessage.progress(map.id, 0.0))

	var fetched: DotResult = await session.loader.ensure_content(map)

	_fetching = false

	if not fetched.ok:
		DotLog.error(CHANNEL, "could not get the announced map", {
			"map": String(map.id), "why": fetched.error.message
		})
		fetch_failed.emit(map, fetched.error)
		return

	is_ready = true
	content_ready.emit(map)
	_send(DotMapMessage.ready(map.id, map.version))


func _on_load(id: StringName, version: String) -> void:
	if announced == null or announced.id != id:
		# A load for a map this peer was never announced. It can happen legitimately —
		# a peer that joined between the announce and the load — so the catalogue is
		# asked before giving up.
		var known: DotMapDef = (
			session.catalogue.get_map(id)
			if session != null and session.catalogue != null else null
		)

		if known == null:
			DotLog.warn(CHANNEL, "told to load a map we were never sent", {
				"map": String(id)
			})
			return

		announced = known

	if version != "" and announced.version != version:
		DotLog.warn(CHANNEL, "told to load a different version than announced", {
			"map": String(id), "announced": announced.version, "asked": version
		})
		return

	_load(announced)


func _load(map: DotMapDef) -> void:
	var changed_result: DotResult = await session.change_to_map(map)

	if not changed_result.ok:
		DotLog.error(CHANNEL, "the announced map would not load", {
			"map": String(map.id), "why": changed_result.error.message
		})
		fetch_failed.emit(map, changed_result.error)
		return

	changed.emit(map)


# --- Trust -----------------------------------------------------------------

## Turns an announced definition into a map this client is willing to load.
##
## The client's own catalogue wins outright when it has the id: a host may tell this
## client [i]which[/i] map, never [i]what[/i] the map is made of.
func _accept(dict: Dictionary) -> DotResult:
	var id := StringName(str(dict.get("id", "")))

	if id == &"":
		return DotResult.fail(DotError.CODE_INVALID, "The announced map has no id.")

	if session != null and session.catalogue != null:
		var known := session.catalogue.get_map(id)

		if known != null:
			# The version still has to agree. A host on a republished map is asking
			# for geometry this client does not have, and loading the old one puts a
			# player in a world that is subtly not everybody else's — which on a timer
			# server is a record set on a map that no longer exists.
			var wanted := str(dict.get("version", known.version))

			if wanted != known.version and known.is_local():
				return DotResult.fail(
					DotError.CODE_STATE,
					"This client has a different version of that map.",
					"%s: have %s, asked for %s" % [String(id), known.version, wanted]
				)

			if wanted != known.version:
				# Delivered, so the right version is fetchable. Taking the announced
				# definition here is safe by the same rule the unknown case uses.
				return _accept_delivered(dict, id)

			return DotResult.success(known)

	if not accept_unknown_maps:
		return DotResult.fail(
			DotError.CODE_FORBIDDEN,
			"This client does not have that map and will not take one from a host.",
			String(id)
		)

	return _accept_delivered(dict, id)


## Accepts a map this client did not already know, if and only if it is delivered.
##
## [b]The refusal is the whole control.[/b] A definition from a host may name any scene
## path it likes, and a client that loaded one would load anything in its own build. A
## delivered map cannot: its scene lives inside dot-cloud's version-namespaced mount, so
## the worst a hostile host achieves is making this client download its content — which
## is what connecting to it already means.
func _accept_delivered(dict: Dictionary, id: StringName) -> DotResult:
	var map := DotMapDef.from_dictionary(dict)

	var valid := map.validate()

	if not valid.ok:
		return valid.wrap("The announced map is not usable.")

	if map.is_local():
		return DotResult.fail(
			DotError.CODE_FORBIDDEN,
			"A host may not send a map that is not delivered content.",
			"%s names no content_id, so its scene would be a path in this build"
				% String(id)
		)

	var prefix := "%s%s/%s/" % [
		MOUNT_ROOT, String(map.content_id), map.effective_content_version()
	]

	# simplify_path first, because "res://dot_cloud/a/1/../../../addons/x.tscn" does
	# begin with the prefix. dot-cloud learned this one the same way.
	if not map.scene_path.simplify_path().begins_with(prefix):
		return DotResult.fail(
			DotError.CODE_FORBIDDEN,
			"The announced map's scene is outside its own content.",
			"%s is not under %s" % [map.scene_path, prefix]
		)

	if map.zones_path != "" \
		and not map.zones_path.simplify_path().begins_with(prefix):
		return DotResult.fail(
			DotError.CODE_FORBIDDEN,
			"The announced map's zone file is outside its own content.",
			"%s is not under %s" % [map.zones_path, prefix]
		)

	if remember_accepted_maps and session != null and session.catalogue != null:
		# Replaces any older entry, because the version check above has already
		# decided this one is the version the host is on.
		session.catalogue.remove(map.id)
		session.catalogue.add(map)

	return DotResult.success(map)


func _send(payload: Dictionary) -> void:
	if not send_fn.is_valid():
		DotLog.warn(CHANNEL, "no send_fn; the host will never hear that we are ready")
		return
	send_fn.call(payload)


## Subscribes to dot-cloud's download progress, once.
##
## [b]Wired here rather than left to the game.[/b] `report_progress` was public and
## called by nobody, which is this family's most repeated bug — a value produced
## correctly and consumed by nothing looks exactly like a value produced wrongly, and the
## symptom is a progress bar that never moves on the one screen a player stares at.
##
## The [Callable] is a member and not a fresh lambda, because [method Object.is_connected]
## compares Callables and a lambda written at the call site is a new one every time — so
## the guard would never match its own handler and every map change would add another
## subscriber. dot-server's client link shipped exactly that bug.
##
## Duck-typed through [DotRegistry], because this addon must compile without dot-cloud.
func _subscribe_to_progress() -> void:
	var cloud := DotRegistry.get_service(CLOUD_SERVICE)

	if cloud == null or not cloud.has_signal("progress_changed"):
		return

	if _progress_handler.is_null():
		_progress_handler = _on_cloud_progress

	if not cloud.is_connected("progress_changed", _progress_handler):
		cloud.connect("progress_changed", _progress_handler)


func _on_cloud_progress(p: Dictionary) -> void:
	report_progress(float(p.get("fraction", 0.0)))


## Reports fetch progress to the host.
##
## Called automatically while a fetch is running; public so a game whose content does not
## come through dot-cloud can drive it itself.
func report_progress(fraction: float) -> void:
	if announced == null:
		return
	fetch_progress.emit(clampf(fraction, 0.0, 1.0))
	_send(DotMapMessage.progress(announced.id, fraction))


func describe() -> Dictionary:
	return {
		"announced": String(announced.id) if announced != null else "-",
		"ready": is_ready,
		"fetching": _fetching,
		"map": String(session.current.id) if session != null and session.current != null
			else "-",
	}
