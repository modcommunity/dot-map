# Rotation, voting and the time limit

## Rotation

**The cooldown is the whole design of a rotation.** Without one a server plays the same three popular maps for ever, because a vote is a popularity contest and popularity does not change between rounds.

The cooldown is **clamped to half the pool at choosing time**, not when it is set: a cooldown of eight on a server with six maps in rotation excludes everything, and the honest behaviour is to shorten the memory rather than to return nothing, which would leave the server on its current map for ever with no error anywhere. A pool of one repeats.

**The random mode is seeded and the seed advances deterministically**, so a client can show the same "next map" the server will pick without asking. A time-based reseed would make that prediction wrong.

## `DotMapVote`

**A vote's tie-break is deterministic and is not random.** Two maps on four votes each resolved by a coin flip means a client's live tally and the server's result can disagree, and the players who watched it read that as the vote being rigged. Ties go to the option nominated first.

- **Only some of the ballot is reserved for nominations.** All of it, and one organised group of three decides every map on a twenty-player server.
- **The current map is never an ordinary option.** "Play this again" is what the extend option is for, and having both splits the vote of the people who want the same thing.
- **A tie with extend goes to the new map.** The players who wanted something new are the ones who lose by staying, and a server that ties toward the status quo never changes map.

The commands (`rtv`, `nominate`, `nextmap`, `timeleft`) and the ballot on screen are dot-vote's and dot-ui's; this is the tally and the rule.

## The map has to end on its own

**A server that never changes map is not a server.** Somebody joins, plays the map they arrived on, and leaves, and the rotation, the catalogue and the vote all exist and are never reached. `DotMapTimeLimit` is the three mechanisms every long-lived server in this genre has, and each covers a case the others do not: a **time limit** so a map ends when nobody asks, **rock the vote** so one everybody hates ends early, and **extending** so one everybody is enjoying does not end on a timer.

**Counted in simulated seconds, advanced by the host**, never a wall clock: a server that stalls for ten seconds should not lose ten seconds off its map, and a test must be able to run an hour of it in a millisecond. Same choice `DotPropSpawner.advance` makes.

- **The expiry is latched.** The host's response is to run a vote and change the map, and both take time; without the latch a limit that reached zero would fire on every tick until the map changed: a vote opened at the tick rate.
- **Extending is bounded.** The people still on a map are the people who like it, so an unbounded extend means a popular map runs until everybody else has left.
- **Extending clears the rock-the-vote tally.** The players who wanted it to end have just been outvoted; carrying their votes forward ends the map the moment one more person joins and agrees.
- **Rocking the vote is idempotent per player.** Typing it twice is what somebody does when nothing visible happened, and counting it twice would let two people end a map for six.
- **A player who leaves takes their vote with them** (`unrock`). Otherwise a server whose players trickle away keeps their votes while the threshold falls, and a map ends on the votes of people who are not there.

`DotMapSession` emits `map_over` and **does not change the map itself**. What happens when a map ends is a game's decision (run a vote, take the next in the rotation, end the round first, show a scoreboard), and a session that decided would have to be fought by every game that wanted any of those.

The clock can wait while the server hibernates: `DotMapSession.follow_hibernation(server)` (duck-typed on `hibernation_changed(bool)`) or `set_hibernating`; `restart_on_wake` (default on) starts the map's own limit again on waking.
