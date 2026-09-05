class_name DotMapRotation
extends RefCounted

## What plays next, and what may not play again yet.
##
## [b]The cooldown is the whole design.[/b] A rotation without one plays the same
## three popular maps for ever, because a vote is a popularity contest and popularity
## does not change between rounds. Every server in this genre ends up with a
## "recently played" exclusion, and the number that matters is how many maps back it
## remembers — too few and the map you just played is on the menu again, too many and
## a small server has nothing to offer.
##
## Deterministic given the same history and the same seed, so a client can show the
## same "next map" the server will pick without asking.

const CHANNEL := "map.rotation"

## How a rotation chooses.
enum Mode {
	## Straight through the list, wrapping. Predictable, and what a small server wants.
	SEQUENTIAL,
	## Randomly, respecting the cooldown.
	RANDOM,
	## Nothing automatic: the next map is whatever [method set_next] was told.
	MANUAL,
}

var catalogue: DotMapCatalogue = null

## Ids in rotation order. Empty means "every enabled map in the catalogue".
##
## Separate from the catalogue for the reason in [DotMapCatalogue]: a server knows
## about two hundred maps and rotates twelve.
var order: Array[StringName] = []

var mode: Mode = Mode.RANDOM

## How many recently played maps are excluded from a choice.
##
## [b]Clamped against the pool size at choosing time, not here.[/b] A cooldown of
## eight on a server with six maps in rotation excludes everything, and the honest
## behaviour is to shorten the memory rather than to return nothing — which would
## leave the server on its current map for ever with no error anywhere.
var cooldown: int = 5

## Most recently played first.
var history: Array[StringName] = []

## Longest history kept. Bounds the memory on a server that has been up for months.
var history_limit: int = 64

## Seed for [constant Mode.RANDOM].
##
## Explicit so a client and a server pick the same next map, and so a test is
## reproducible. Advanced on every choice.
var seed_value: int = 0

## What [method choose] will return, when something has set it.
var _forced: StringName = &""

## Index for [constant Mode.SEQUENTIAL].
var _cursor: int = 0


static func of(p_catalogue: DotMapCatalogue) -> DotMapRotation:
	var rotation := DotMapRotation.new()
	rotation.catalogue = p_catalogue
	return rotation


## The maps eligible right now, in rotation order.
func pool(players: int = 0) -> Array[DotMapDef]:
	if catalogue == null:
		return []

	var out: Array[DotMapDef] = []

	if order.is_empty():
		for map in catalogue.maps:
			if map.available_for(players):
				out.append(map)
		return out

	for id in order:
		var map := catalogue.get_map(id)
		if map != null and map.available_for(players):
			out.append(map)

	return out


## Whether a map is still on cooldown.
func on_cooldown(id: StringName, pool_size: int = 0) -> bool:
	# Never exclude more than half the pool. Otherwise a long cooldown on a short
	# rotation excludes everything and the server never moves — which reads as the
	# rotation being broken rather than as a number being too big.
	var depth := cooldown

	if pool_size > 0:
		depth = mini(depth, maxi(pool_size / 2, 0))

	for i in range(mini(depth, history.size())):
		if history[i] == id:
			return true

	return false


## The next map, or null when the rotation cannot offer one.
##
## Does not record it as played — [method note_played] does that, when the map has
## actually been loaded. Two calls in a row give the same answer, which is what lets a
## HUD show "next map" without changing it.
func choose(players: int = 0) -> DotMapDef:
	if _forced != &"" and catalogue != null:
		var forced := catalogue.get_map(_forced)
		if forced != null:
			return forced

	var candidates := pool(players)

	if candidates.is_empty():
		DotLog.warn(CHANNEL, "the rotation has nothing to offer", {
			"players": players, "catalogue": catalogue.size() if catalogue else 0
		})
		return null

	var eligible: Array[DotMapDef] = []

	for map in candidates:
		if not on_cooldown(map.id, candidates.size()):
			eligible.append(map)

	# Everything on cooldown despite the halving — a pool of one, say. Playing the
	# same map again is a much better answer than stopping.
	if eligible.is_empty():
		eligible = candidates

	match mode:
		Mode.SEQUENTIAL:
			return eligible[_cursor % eligible.size()]
		Mode.MANUAL:
			return null
		_:
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_value
			return eligible[rng.randi_range(0, eligible.size() - 1)]


## Records a map as played, putting it on cooldown.
func note_played(id: StringName) -> void:
	history.push_front(id)

	while history.size() > history_limit:
		history.pop_back()

	_cursor += 1
	_forced = &""

	# Advanced so the next random choice differs, and advanced DETERMINISTICALLY so a
	# client following the same history reaches the same seed. A time-based reseed
	# here would make the client's prediction of the next map wrong.
	seed_value = int(hash(String(id)) ^ (seed_value * 1103515245 + 12345)) & 0x7FFFFFFF


## Forces the next map, overriding the mode. What a vote's result does.
func set_next(id: StringName) -> bool:
	if catalogue == null or not catalogue.has(id):
		return false

	_forced = id

	return true


func clear_next() -> void:
	_forced = &""


func forced_next() -> StringName:
	return _forced


func describe() -> Dictionary:
	var next := choose()

	return {
		"mode": Mode.keys()[mode],
		"pool": pool().size(),
		"cooldown": cooldown,
		"history": history.size(),
		"forced": String(_forced) if _forced != &"" else "-",
		"next": String(next.id) if next != null else "-",
	}
