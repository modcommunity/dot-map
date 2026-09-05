class_name DotMapVote
extends RefCounted

## A map vote: nominations, a ballot, and a winner.
##
## [b]One player, one vote, changeable until the ballot closes.[/b] Changeable because
## the alternative is a player who misclicks being stuck with it for the rest of the
## round, and because letting somebody change their mind is what makes a live tally
## worth showing.
##
## [b]The tie-break is deterministic and is not random.[/b] Two maps on four votes each
## resolved by a coin flip means a client's live tally and the server's result can
## disagree, and the players who watched it read that as the vote being rigged. Ties
## go to the map that was nominated first, which everybody watching can see coming.
##
## Nothing here draws a menu, sends a chat message or counts down. A vote is a tally
## and a rule; how it is presented is the game's.

const CHANNEL := "map.vote"

signal opened(options: Array)
signal voted(voter: StringName, choice: StringName)
signal closed(winner: DotMapDef, tally: Dictionary)

## The maps on the ballot, in order. Ties resolve toward the front.
var options: Array[DotMapDef] = []

## Voter id -> map id.
var ballots: Dictionary = {}

## Ids nominated, in nomination order, before the ballot opened.
var nominations: Array[StringName] = []

var open: bool = false

## Most options a ballot may carry.
##
## Bounded because a vote with thirty entries is one nobody reads: everybody picks
## from the first five they can see, which is a worse outcome than a smaller ballot
## chosen properly.
var max_options: int = 6

## How many of the ballot's places are reserved for nominations.
##
## The rest are filled from the rotation. Reserving some rather than all is what stops
## one organised group of three deciding every map on a twenty-player server.
var reserved_for_nominations: int = 4

## Whether "extend the current map" is on the ballot.
var allow_extend: bool = true

## The pseudo-id for the extend option.
const EXTEND := &"__extend__"


## Nominates a map. False if it is already nominated or the ballot is open.
func nominate(id: StringName) -> bool:
	if open or nominations.has(id):
		return false

	nominations.append(id)

	return true


func withdraw(id: StringName) -> bool:
	if open or not nominations.has(id):
		return false

	nominations.erase(id)

	return true


## Opens a ballot: nominations first, then the rotation fills the rest.
##
## [param extra] is where the non-nominated options come from — usually
## [method DotMapRotation.pool] minus what is on cooldown.
func begin(
	catalogue: DotMapCatalogue,
	extra: Array[DotMapDef],
	current: DotMapDef = null
) -> DotResult:
	if open:
		return DotResult.fail(DotError.CODE_STATE, "A vote is already open.")

	if catalogue == null:
		return DotResult.fail(DotError.CODE_INVALID, "A vote needs a catalogue.")

	options.clear()
	ballots.clear()

	var chosen := {}

	for id in nominations:
		if options.size() >= mini(reserved_for_nominations, max_options):
			break

		var map := catalogue.get_map(id)

		if map == null or chosen.has(id):
			continue

		options.append(map)
		chosen[id] = true

	for map in extra:
		if options.size() >= max_options:
			break

		# The current map is never an ordinary option: "play this again" is what the
		# extend option is for, and having both on the ballot splits the vote of the
		# people who want exactly the same thing.
		if chosen.has(map.id) or (current != null and map.id == current.id):
			continue

		options.append(map)
		chosen[map.id] = true

	if options.is_empty() and not allow_extend:
		return DotResult.fail(
			DotError.CODE_STATE, "There is nothing to vote on."
		)

	nominations.clear()
	open = true

	opened.emit(options)

	return DotResult.success(options)


## Casts or changes a vote. [param choice] may be [constant EXTEND].
func cast_vote(voter: StringName, choice: StringName) -> bool:
	if not open:
		return false

	if choice == EXTEND:
		if not allow_extend:
			return false
	else:
		var known := false

		for map in options:
			if map.id == choice:
				known = true
				break

		if not known:
			return false

	ballots[voter] = choice

	voted.emit(voter, choice)

	return true


## Votes per option id. Includes zero-vote options, so a tally renders in full.
func tally() -> Dictionary:
	var counts := {}

	for map in options:
		counts[map.id] = 0

	if allow_extend:
		counts[EXTEND] = 0

	for voter in ballots:
		var choice: StringName = ballots[voter]
		counts[choice] = int(counts.get(choice, 0)) + 1

	return counts


## Closes the ballot and returns the winner, or null for extend / nothing.
##
## Ties go to whichever option is earlier in [member options], which is nomination
## order. Deterministic on purpose — see the class documentation.
func finish() -> DotMapDef:
	if not open:
		return null

	open = false

	var counts := tally()
	var best := -1
	var winner: DotMapDef = null
	var extend_votes := int(counts.get(EXTEND, 0))

	for map in options:
		var votes := int(counts.get(map.id, 0))

		if votes > best:
			best = votes
			winner = map

	# Extend wins only outright. A tie between "extend" and a map goes to the map,
	# because the players who wanted something new are the ones who lose by staying,
	# and a server that ties toward the status quo never changes map.
	if allow_extend and extend_votes > best:
		winner = null

	closed.emit(winner, counts)

	return winner


func voter_count() -> int:
	return ballots.size()


func reset() -> void:
	open = false
	options.clear()
	ballots.clear()
	nominations.clear()


func describe() -> Dictionary:
	return {
		"open": open,
		"options": options.size(),
		"nominations": nominations.size(),
		"votes": ballots.size(),
		"tally": tally(),
	}
