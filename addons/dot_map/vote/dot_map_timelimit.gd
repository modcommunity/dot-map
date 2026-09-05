class_name DotMapTimeLimit
extends RefCounted

## When the map should end, and how the players get a say before it does.
##
## [b]A server that never changes map is not a server.[/b] Somebody joins, plays the
## map they arrived on, and leaves — the rotation, the catalogue and the vote all
## exist and nothing ever reaches them. Every long-lived server in this genre has the
## same three mechanisms, and they are three because each covers a case the others do
## not:
##
## - a **time limit**, so a map ends even when nobody asks;
## - **rock the vote**, so a map that everybody hates ends early;
## - **extending**, so a map everybody is enjoying does not end on a timer.
##
## [b]Counted in simulated seconds, advanced by the host.[/b] Not a wall clock: a
## server that stalls for ten seconds should not lose ten seconds of its map, and a
## test must be able to run an hour of it in a millisecond. It is the same choice
## [DotPropSpawner] makes and for the same reasons.
##
## [codeblock]
## limit.start(1800.0)                 # a thirty-minute map
##
## # once per tick
## limit.advance(delta)
##
## # when somebody types !rtv
## limit.rock_the_vote(player_id, player_count)
## [/codeblock]

const CHANNEL := "map.timelimit"

## The map's time is up, or enough players asked for it to be.
##
## [param reason] is [constant REASON_TIME] or [constant REASON_RTV]. Emitted once
## per map; the host runs the vote and changes the map.
signal expired(reason: StringName)

## Somebody rocked the vote. [param needed] is how many more are wanted.
signal rocked(player_id: StringName, votes: int, needed: int)

## The map was extended. [param seconds] is by how much.
signal extended(seconds: float)

## Emitted once when the remaining time first drops below [member warn_at].
signal warning(seconds_left: float)

const REASON_TIME := &"time"
const REASON_RTV := &"rtv"

## Seconds the map runs for. 0 disables the time limit entirely.
##
## Zero is a real configuration — a server whose map only ever changes by vote — and
## is not the same as "a very long limit", because a limit that exists still fires
## eventually and surprises somebody at four in the morning.
var duration: float = 1800.0

## Seconds remaining, counted down by [method advance].
var remaining: float = 0.0

## Seconds left when [signal warning] fires. 0 disables it.
var warn_at: float = 120.0

## Seconds an extend adds.
var extend_seconds: float = 600.0

## How many times one map may be extended. 0 = unlimited.
##
## [b]Bounded, because "extend" wins by default.[/b] The people still on a map are
## the people who like it, so an unbounded extend means a popular map runs until
## everybody else has left — which is how a server ends up with one map.
var max_extends: int = 3

## Fraction of the players who must rock the vote for it to pass, 0..1.
##
## 0.6 rather than a majority: rocking the vote is a request to leave a map early,
## and a bare majority of a twelve-player server is seven people deciding for the
## other five on a map those five chose.
var rtv_fraction: float = 0.6

## Fewest players before rocking the vote does anything at all.
##
## On an empty or nearly-empty server one person is always a majority, so without
## this a single player changes the map at will — which is fine, and is what
## [member rtv_min_players] of 1 configures. The default of 2 makes it a vote.
var rtv_min_players: int = 2

## Whether the map is running at all.
var running: bool = false

## Extends used on this map.
var extends_used: int = 0

## Player ids who have rocked the vote.
var _rtv: Dictionary = {}

var _warned: bool = false
var _expired: bool = false


static func of(p_duration: float) -> DotMapTimeLimit:
	var limit := DotMapTimeLimit.new()
	limit.duration = p_duration
	return limit


## Starts the clock for a new map. Call on every map change.
##
## [param override] replaces [member duration] for this map only — a long map gets a
## longer limit, which is a property of the map rather than of the server.
func start(override: float = -1.0) -> void:
	duration = override if override >= 0.0 else duration
	remaining = duration
	running = duration > 0.0
	extends_used = 0
	_rtv.clear()
	_warned = false
	_expired = false


func stop() -> void:
	running = false


## Advances the clock by one tick of simulated time.
func advance(delta: float) -> void:
	if not running or _expired:
		return

	remaining = maxf(remaining - delta, 0.0)

	if warn_at > 0.0 and not _warned and remaining <= warn_at:
		_warned = true
		warning.emit(remaining)

	if remaining <= 0.0:
		_fire(REASON_TIME)


func _fire(reason: StringName) -> void:
	# Latched, because the host's response to `expired` is to run a vote and change
	# the map, and both take time. Without the latch a limit that reached zero would
	# fire again on every tick until the map actually changed, which is a vote opened
	# a hundred and twenty times a second.
	if _expired:
		return

	_expired = true
	running = false

	DotLog.info(CHANNEL, "the map is over", {"reason": String(reason)})

	expired.emit(reason)


func is_expired() -> bool:
	return _expired


## Extends the map. False when it has been extended as often as it may be.
func extend(seconds: float = -1.0) -> bool:
	if max_extends > 0 and extends_used >= max_extends:
		return false

	var by := seconds if seconds > 0.0 else extend_seconds

	extends_used += 1
	remaining += by
	running = true

	# The warning and the latch both reset: an extended map has a fresh ending, and
	# a player who saw "two minutes left" ten minutes ago should see it again.
	_warned = false
	_expired = false

	# The rock-the-vote tally goes too. The players who wanted the map to end have
	# just been outvoted, and carrying their votes into the extension means the map
	# ends again the moment one more person joins and agrees.
	_rtv.clear()

	DotLog.info(CHANNEL, "the map was extended", {
		"by": by, "used": extends_used, "remaining": remaining
	})

	extended.emit(by)

	return true


func can_extend() -> bool:
	return max_extends <= 0 or extends_used < max_extends


# --- Rock the vote ---------------------------------------------------------

## How many players have to rock the vote right now.
func rtv_needed(player_count: int) -> int:
	if player_count < rtv_min_players:
		return 0

	return maxi(int(ceil(float(player_count) * rtv_fraction)), 1)


## Registers a player's rock-the-vote. Returns whether it passed.
##
## [b]Idempotent per player.[/b] Typing it twice is what a player does when nothing
## visible happened, and counting it twice would let two people end a map on a
## six-player server.
func rock_the_vote(player_id: StringName, player_count: int) -> bool:
	if _expired:
		return false

	if player_count < rtv_min_players:
		DotLog.debug(CHANNEL, "rtv ignored; too few players", {
			"players": player_count, "minimum": rtv_min_players
		})
		return false

	_rtv[player_id] = true

	var needed := rtv_needed(player_count)
	var votes := _rtv.size()

	rocked.emit(player_id, votes, maxi(needed - votes, 0))

	if votes >= needed:
		_fire(REASON_RTV)
		return true

	return false


## Withdraws a player's vote. For a player who leaves, or changes their mind.
##
## [b]Called when somebody disconnects, and that matters.[/b] Without it, a server
## whose players trickle away keeps their votes and the threshold falls with the
## player count — so a map ends on the votes of people who are no longer there.
func unrock(player_id: StringName) -> void:
	_rtv.erase(player_id)


func rtv_votes() -> int:
	return _rtv.size()


func has_rocked(player_id: StringName) -> bool:
	return _rtv.has(player_id)


## Time remaining, as [code]m:ss[/code].
##
## Minutes and seconds, not the timer's thousandths: this is a map clock somebody
## glances at, and three decimal places on it is noise.
func formatted_remaining() -> String:
	var total := maxf(remaining, 0.0)
	return "%d:%02d" % [int(total / 60.0), int(fmod(total, 60.0))]


func describe() -> Dictionary:
	return {
		"running": running,
		"remaining": formatted_remaining(),
		"extends": "%d of %s" % [
			extends_used, "unlimited" if max_extends <= 0 else str(max_extends)
		],
		"rtv": _rtv.size(),
		"expired": _expired,
	}


func _to_string() -> String:
	return "DotMapTimeLimit(%s left)" % formatted_remaining()
