# dot-map

Maps as content rather than as builds.

Read the family-wide conventions in [`../../CLAUDE.md`](../../CLAUDE.md) first. This
file is only what is specific to maps.

**Only dot-core is a dependency.** dot-cloud and dot-timer are both optional and
neither is named anywhere in the source — see "Reaching dot-cloud without naming it".

## The one idea, and the question it answers

**One game, many maps, switched under live players. A map is content, not a project.**

The question this exists to answer is "how do we ship a hundred surf maps", and the
answer a first look at Godot suggests — one project per map — is wrong in a way that
only becomes obvious at map forty:

| One project per map | One game, many maps |
| --- | --- |
| A hundred export pipelines | One |
| A hundred copies of every addon | One |
| A player downloads a whole game to try a map | They download a map |
| Records are per-project, so there is no leaderboard across maps | One records table |
| A "server" can only ever run one map | A server runs a rotation |
| A map fix is a release | A map fix is a version bump on one pack |

So a map is a `DotMapDef`: an id, a version, a scene path, and optionally a dot-cloud
content id the scene lives inside. It is how every game in this genre has worked for
twenty-five years, and it is the shape the rest of the family was already built for —
dot-cloud namespaces content by `id/version` *precisely because a mounted resource
pack can never be unmounted on any platform*, so a new version of a map is a new
mount rather than a replacement, and a server can hold both while players finish
their runs on the old one.

**A map id is never renamed.** Records name their map by it, so changing one orphans
every time ever set on it. `display_name` is the one to change.

## Layout

```
addons/dot_map/
  core/
    dot_map_def.gd        one map: id, version, scene, pack, tier, player range
    dot_map_catalogue.gd  every map a server knows about. The JSON an operator edits
  runtime/
    dot_map_loader.gd     def -> PackedScene, fetching content first if needed
    dot_map_rotation.gd   what plays next, and what may not play again yet
    dot_map_session.gd    which map is loaded, and the switch. The node a game adds
  net/
    dot_map_message.gd    the five messages a map change is made of
    dot_map_sync_host.gd  announces, waits for peers, then swaps. Read the class doc
    dot_map_sync_client.gd  fetches, reports ready, loads. Owns the trust rules
  vote/
    dot_map_vote.gd       nominations, a ballot, a winner
    dot_map_timelimit.gd  when the map ends, and rock the vote
  integrations/
    dot_map_commands.gd   `map`, `maps`, `mapinfo` on any host. Names no dot-server class
```

## The catalogue is not the rotation

A server knows about two hundred maps and rotates through twelve. The other hundred
and eighty still have leaderboards, are still nominatable, and still have to resolve
when somebody links to one. Merging the two lists means removing a map from the
rotation also removes it from the records — which is how a leaderboard nobody meant
to delete disappears.

**One bad entry does not condemn the file.** A server with a hundred and ninety-nine
good maps and one typo boots on the hundred and ninety-nine and says loudly which one
it dropped. Refusing to start with an error nobody can locate is the worse failure,
and on a community server the person maintaining this file is a person with a text
editor.

**An exact id match wins a search outright.** On a server with `surf_kitsune` and
`surf_kitsune2`, a substring search returns both, and whatever picks the first has
chosen for the player who typed the full name.

## Changing a map

`DotMapSession.change_to_map` is the most dangerous thing a server does — players are
in runs, entities are replicated, content may still be downloading, and the scene
about to be freed is the one everything holds a reference to. The order is:

1. **announce** (`changing`) before anything is torn down, so a timer can abandon its
   runs and a netcode can stop replicating entities that are about to vanish;
2. **fetch and load the new scene** before freeing the old one;
3. free the old world and add the new one **in the same call**;
4. **announce** (`changed`) so listeners can rebuild.

**Step 2 is the one people skip.** Freeing first is simpler, uses less memory, and
turns a CDN having a bad day into a server with no map and no way back.
`examples/map_selftest.gd::_test_change_survives_a_failure` is the test that guards
it: it points a map at a scene that does not exist, and requires that the session is
still on the map it was running, with that world still in the tree, and able to change
again afterwards.

Step 3 uses `free()` and not `queue_free()`, because the new world goes in during the
same call and a deferred free would leave both in the tree for a frame — two maps'
worth of collision geometry, and any group lookup finding the old one.

A second change while one is in progress is **refused, not queued**: two overlapping
changes free the same node twice, and the second one's `await` resumes into a tree the
first has already rebuilt.

## Changing the map for everybody, and how that differs from changing the game

`DotMapSession` changes the map **in this process**. That is all it ever did, and for a
long time it was all there was — so a dedicated server freed its world, loaded the next
one, and every connected client carried on playing the map that no longer existed. The
one game in the family that networked map changes at all broadcast a map id and hoped
every client already had the scene in its build, which works exactly until the first map
that is delivered rather than shipped.

`addons/dot_map/net/` is the protocol that was missing. Four messages:

```
announce  host -> peer   here is the map we are going to; go and get it
progress  peer -> host   I am n% of the way there
ready     peer -> host   I have it
load      host -> peer   everyone has it; put it on screen now
abort     host -> peer   the change was abandoned; stay where you are
```

**`announce` and `load` are separate on purpose.** The host does not swap until its peers
can, so there are necessarily two moments. Collapsing them is a bug this family already
has by another name: dot-server's `report_content_ready` used to send a client to load
the game the server had not swapped to yet.

### Changing a game and changing a map are different operations

Both are worth having, and confusing them is how you get a server that reconnects
everybody every four minutes:

| | Changing a **game** (dot-server) | Changing a **map** (here) |
| --- | --- | --- |
| What is replaced | The module, the netcode, the client's scene | The world, and nothing else |
| What happens to players | `SPAWNED -> DOWNLOADING -> LOADING -> SPAWNED` | They stay spawned |
| Who owns it | `DotGameManager` | `DotMapSyncHost` |
| How often | Rarely — an operator's decision | Every few minutes, by a vote or a timer |
| What a client is told | A game id, a content key and a scene | A map definition |
| Cost | A signon | A content fetch, and often not even that |

A rotation running through `DotGameManager.change_game` would put every player through
signon on every map. That is why this exists.

**And it is why `map` is a command here rather than there.** dot-server shipped a `map`
alias for `changelevel` for as long as it had no notion of a map at all — every other
server calls the thing that swaps what is running `map`, so operators typed both. Once
this addon existed, an operator typing `map de_dust2` on a server running one game and a
hundred maps meant the row on the right every time, and got a refusal naming games. The
plain name belongs to the plain thing; dot-server's game change is `changelevel`, `game`
and `gamechange` now.

`DotMapCommands.install(host, session)` registers `map`, `maps` and `mapinfo` on anything
with `add_command` (a `DotModule`) or `command` (a `DotConsole`), duck-typed, so this file
names no dot-server class and the addon stays installable without it. Pass a
`DotMapSyncHost` as the third argument when the change has to reach clients rather than
only the server's own process — it has the same three change methods, deliberately.

**`map` says nothing about chat and `nextmap` is not registered at all.** The first because `admin_permission` — `changemap` — is what decides who may change the map, and it decides it the same way wherever the line was typed; `map` is left at `ChatPolicy.DEFAULT` so a host server's `sv_chat_commands` has the last word, and `allow_chat_change = false` marks it `no_chat()` for a records server that wants a map change to cost a deliberate trip to the console. It was the other way round until `sv_chat_commands` landed, and what the old default produced was an operator holding the flag being told the command cannot be run from chat. The second because dot-vote already registers `nextmap` and `timeleft` over the same maps, and two commands of one name is the last one registered winning silently. `mapinfo` answers both questions without taking a name somebody else has.

### The host may say *which* map, never *what* the map is

`DotMapSyncClient` takes the map from **its own catalogue** when it has the id. The
announced definition is only used for a map it does not have — and then it must be
*delivered*: it has to name a `content_id`, and its scene and zone paths have to resolve
inside `res://dot_cloud/<id>/<version>/` after `simplify_path()`.

This is the same rule `DotClientLink._resolve_scene` enforces, for the same reason, and
the `simplify_path` is there because dot-cloud already learned that
`"res://a/b/../../evil"` does `begins_with("res://a/b/")`. Without the delivered
requirement a host could name any scene in the client's own build; with it, the worst it
can do is make the client download its content, which is what connecting to it already
meant. `accept_unknown_maps = false` is for a client that ships every map it will ever
play and should refuse to be sent anywhere else.

**A records server is why `accept_unknown_maps` defaults to on.** It carries two hundred
maps and its clients ship none of them, so a client that only knew its own catalogue
could join and never load a single map.

**One built-in scene reading a delivered document is the other shape, and `trusted_template_scenes` is for it.** The family's mount constraint says a pack's script cannot extend a class of the build it is mounted into, so a game whose maps are data — a manifest and a mesh, turned into a world by one scene the game ships — can never put that scene in the pack, and the rule above refused every map it had. game-g2gfast found it by being the first to try, and worked around it by fetching by its own convention before dot-map saw the announce. A client that lists a scene in `trusted_template_scenes` (empty by default, which is the strict rule unchanged) accepts an announce naming that exact scene, after `simplify_path`, if the map names a `content_id` and its data — `zones_path`, every key in `template_path_keys` (default `manifest`, at least one required), and every *path-shaped* string anywhere in `meta`, nested or not — resolves inside `res://dot_cloud/<content_id>/<version>/`. The sweep of the whole of `meta` is fail-closed on purpose: a template that one day reads a key nobody listed must not be the day a host can point it at `user://` or a file in the build. What a hostile host can still do is make the client fetch any content from the client's own origin (or from the announce's `manifest_url` — signed manifests are what stop that from mounting anything, exactly as for any delivered map) and instantiate a listed scene over it. So the template is the attack surface: it parses whatever the pack holds and must treat it as untrusted input, and it must take paths only from keys the check covers. The class doc on `trusted_template_scenes` says the same, where the next person to add a key will read it.

### What the first transport found

The protocol ran over a real network for the first time in game-g2gfast (dot-net, a server and a client) and five things in this addon were wrong. All five are fixed here, each with a check in `map_selftest` that was armed by putting the old line back:

- **A joiner was never told to load.** `join_payload()` is an announce, and `load` was only ever sent at the end of a change, so a peer that joined between changes fetched the map, said ready, and waited for ever. **The host now answers a `ready` for the map it is on, while no change is running, with a `load` — once per peer per map.** That was chosen over making `admit_peer` the only way in, because the `ready` is the one moment the host knows the peer has the content, the host is the one end that knows whether it already told that peer to load, and it covers every caller at once: `admit_peer` (new, the one-call join), a host that calls `add_peer` and sends `join_payload` itself, and a straggler whose download landed after the change went ahead without it. The "once" matters: without it the straggler, already sent the change's `load`, is sent a second one and rebuilds its world.
- **A peer admitted mid-change was waited on**, though `add_peer` said it was not: `_wait_for_peers` counted every entry of `peers` on every poll, so the change was held to its timeout and the joiner reported as a straggler for a map it had never been announced. The peers a change waits on, sends its `load` or `abort` to, and counts as ready are now the ones registered when it began (`_participants`); a peer added during it is announced whatever map the host settled on, finished or abandoned.
- **The delivered-map rule refused the template shape.** See above.
- **A refused `load` adopted the map it refused.** `_on_load` set `announced` from the catalogue before checking the version the host asked for.
- **Progress was unthrottled.** One message per dot-cloud progress signal, into a server that rate-limits a client and drops the excess without choosing, can cost the `ready` behind it. `progress_interval_sec` (0.25 s; 0 turns it off) throttles what is *sent*; the first report of a fetch, a report of 1.0 and every `ready` always go, and the local `fetch_progress` signal is never throttled.

And one found while writing the checks for those: **a `load` that overtook its own fetch was taken at once.** That is exactly the straggler `swap_without_stragglers` makes — the host gives up waiting, swaps, and sends `load` while the peer is still downloading — and taking it meant asking the content client for the same pack a second time mid-download. dot-cloud happens to join the running request, so it worked with dot-cloud and with nothing else. The client now holds such a `load` until its fetch lands (`_load_after_fetch`), and an `abort` drops it.

### It is transport-agnostic, and that is not laziness

This addon depends on nothing but dot-core, so it cannot know whether the game carrying
these messages uses dot-net's bit packer, Godot's RPCs, a WebSocket or a loopback.
`send_fn` takes a `Dictionary` and one peer id — never a broadcast address, because
`send(payload, 0)` is how this family last delivered a private per-player message to
every client at once. The loop over peers is in the open, in `_broadcast`.

## Reaching dot-cloud without naming it

`DotMapLoader` finds the cloud client in `DotRegistry` under `dot_cloud_client` and
calls its methods by name. The family rule — a script that *mentions* an absent
`class_name` fails to parse and takes everything referencing it down — but there is a
sharper reason here, and it is a bug this family has already had:

`DotCloudClient` once failed to publish itself under that name. Four call sites across
two addons all found null, and **every one of them treated an absent cloud as "this
deployment ships its content in the build"** — which is a legitimate configuration and
therefore indistinguishable from the bug. Nothing errored, for months.

So `DotMapLoader.require_cloud` exists. A deployment that *knows* its maps are
delivered sets it and gets a loud `CODE_STATE` failure naming the registry key it
looked for, instead of a scene that mysteriously will not load.

**The interface it calls did not exist.** `DotMapLoader` has called
`ensure(content_id, version)` and `is_mounted(content_id, version)` since it was written.
`DotCloudClient` offered `acquire(manifest_url)` and `is_ready(content_key)` — different
names taking different things. So **every delivered map failed** with "the registered
cloud client does not speak the content interface", and nothing could see it: the only
loader test here ran with no cloud client at all, which is the branch that falls back to
the disk and passes. dot-cloud now provides `ensure` / `is_mounted`, and
`_test_sync_a_delivered_map` publishes a real signed pack and drives a peer through
fetching it, so the two ends meet in a test rather than in a deployment.

`DotMapDef.manifest_url` is the escape hatch and is normally empty: a catalogue of two
hundred maps should not repeat the same CDN hostname two hundred times, so the client
builds the URL from `content_id`, `content_version` and its own
`manifest_url_template`.

Zones come back from `load_zones` as **text**, not as a parsed `DotTimerZoneSet`.
dot-timer is optional; naming the class here would make every map load in a game
without a timer fail to parse. The host, which has dot-timer, calls
`DotTimerZoneSet.from_json`.

## Rotation and voting

**The cooldown is the whole design of a rotation.** Without one a server plays the
same three popular maps for ever, because a vote is a popularity contest and
popularity does not change between rounds.

The cooldown is **clamped to half the pool at choosing time**, not when it is set: a
cooldown of eight on a server with six maps in rotation excludes everything, and the
honest behaviour is to shorten the memory rather than to return nothing — which would
leave the server on its current map for ever with no error anywhere. A pool of one
repeats.

**The random mode is seeded and the seed advances deterministically**, so a client can
show the same "next map" the server will pick without asking. A time-based reseed
would make that prediction wrong.

**A vote's tie-break is deterministic and is not random.** Two maps on four votes each
resolved by a coin flip means a client's live tally and the server's result can
disagree, and the players who watched it read that as the vote being rigged. Ties go
to the option nominated first.

Three other rules in `DotMapVote`, each of which is a specific failure avoided:

- **Only some of the ballot is reserved for nominations.** All of it, and one
  organised group of three decides every map on a twenty-player server.
- **The current map is never an ordinary option.** "Play this again" is what the
  extend option is for, and having both splits the vote of the people who want the
  same thing.
- **A tie with extend goes to the new map.** The players who wanted something new are
  the ones who lose by staying, and a server that ties toward the status quo never
  changes map.

## The map has to end on its own

**A server that never changes map is not a server.** Somebody joins, plays the map
they arrived on, and leaves — and the rotation, the catalogue and the vote all exist
and are never reached. `DotMapTimeLimit` is the three mechanisms every long-lived
server in this genre has, and there are three because each covers a case the others do
not: a **time limit** so a map ends when nobody asks, **rock the vote** so one
everybody hates ends early, and **extending** so one everybody is enjoying does not end
on a timer.

**Counted in simulated seconds, advanced by the host**, never a wall clock — a server
that stalls for ten seconds should not lose ten seconds off its map, and a test must be
able to run an hour of it in a millisecond. Same choice `DotPropSpawner.advance` makes.

Five rules in it, each of which is a specific failure:

- **The expiry is latched.** The host's response is to run a vote and change the map,
  and both take time; without the latch a limit that reached zero would fire on every
  tick until the map actually changed — a vote opened a hundred and twenty times a
  second.
- **Extending is bounded.** The people still on a map are the people who like it, so
  an unbounded extend means a popular map runs until everybody else has left.
- **Extending clears the rock-the-vote tally.** The players who wanted it to end have
  just been outvoted; carrying their votes forward ends the map the moment one more
  person joins and agrees.
- **Rocking the vote is idempotent per player.** Typing it twice is what somebody does
  when nothing visible happened, and counting it twice would let two people end a map
  for six.
- **A player who leaves takes their vote with them** (`unrock`). Without it, a server
  whose players trickle away keeps their votes while the threshold falls with the
  player count — so a map ends on the votes of people who are not there.

`DotMapSession` emits `map_over` and **does not change the map itself**. What happens
when a map ends is a game's decision — run a vote, take the next in the rotation, end
the round first, show a scoreboard — and a session that decided would have to be fought
by every game that wanted any of those.

## Validating

```bash
godot --headless --path . --import
find . -name '*.gd' -not -path './.godot/*' | while read f; do
    godot --headless --path . --check-only --script "res://${f#./}"
done
godot --headless --path . res://examples/map_selftest.tscn   # 223 checks, 27 sections
```

**Run the check-only pass first.** This project hit the documented hazard while being
written: a missing `await` on a coroutine is a *parse* error, the scene then fails to
load, and the process **hangs** rather than exiting — nothing reaches
`get_tree().quit()`. It looks like an infinite loop in the test and it is a typo.

The other bug the suite found: `DotSemVer.parse` always returns an object and reports
the outcome on `.valid`, so a `== null` check passes for every string ever written and
`"banana"` was a valid map version.

## Where a game plugs in

| To change | Where |
| --- | --- |
| Where the loaded map is put in the tree | `DotMapSession.world_ref` |
| How the next map is chosen | `DotMapRotation.mode`, or `set_next` from a vote |
| How long a map stays off the menu | `DotMapRotation.cooldown` |
| How long a map runs | `DotMapSession.map_seconds`, or `DotMapTimeLimit.duration` |
| How many players must rock the vote | `DotMapTimeLimit.rtv_fraction` / `rtv_min_players` |
| How often a map may be extended | `DotMapTimeLimit.max_extends` |
| What happens when a map ends | The `map_over` signal. The session never decides |
| Whether the clock waits while the server sleeps | `DotMapSession.follow_hibernation(server)` (duck-typed on `hibernation_changed(bool)`) or `set_hibernating`; `restart_on_wake` (default on) starts the map's own limit again on waking |
| What is on a ballot | `DotMapVote.max_options` / `reserved_for_nominations` |
| Whether a map is offered at all | `DotMapDef.enabled`, `min_players`, `max_players` |
| What a map is worth | `DotMapDef.tier`, read by `DotTimerStyle.points_for` |
| Where content comes from | A `DotCloudSource` subclass, in dot-cloud |
| Where a map's manifest is | `DotMapDef.manifest_url`, or the client's template |
| How map changes reach clients | `DotMapSyncHost.send_fn` / `DotMapSyncClient.send_fn` |
| What a client will accept from a host | `DotMapSyncClient.accept_unknown_maps` |
| A built-in scene a host may name for delivered data | `DotMapSyncClient.trusted_template_scenes` / `template_path_keys` |
| How often a peer reports download progress | `DotMapSyncClient.progress_interval_sec` |
| Letting a peer in between changes | `DotMapSyncHost.admit_peer` (or `add_peer` + `join_payload`; the host sends the `load`) |
| Whether one slow peer holds the server | `DotMapSyncHost.swap_without_stragglers` |
| Anything else about a map | `DotMapDef.meta` |

## Things deliberately not here

- **A map downloader UI.** `fetching` says a fetch has started; dot-cloud reports
  progress; drawing a bar is the game's.
- **A transport.** `DotMapSyncHost.send_fn` and `DotMapSyncClient.send_fn` take a
  `Dictionary`; putting it on a wire is the game's. dot-map cannot name dot-net.
- **Kicking a peer that cannot get the map.** `peer_timed_out` and `on_timeout_fn` say
  who; this addon has no session list and no socket, so it cannot drop anybody.
- **A map vote menu or a chat command.** A vote is a tally and a rule. `rtv`, `nominate`
  and the countdown belong to dot-server's console and the game's chat — game-playground
  has them as `pg_rtv`, `pg_nextmap` and `pg_extend`.
- **Map metadata scraped from the scene.** A tier, an author and a description are
  editorial, they change without the geometry changing, and reading them out of the
  scene would mean loading every map to list them.
- **Per-map addon configuration.** A map that needed different movement would be a
  different game mode, and that is `DotFpsTunables` plus dot-server's module system.
- **Anything about what is *in* a map.** Spawns, zones, props and lights are the
  scene's and the timer's. This addon knows a map's name, version and where its scene
  is.

**A delivered map is compared by its pack, too (2026-10-04).** `DotMapSyncClient._accept` matched a remembered map on `version` alone; a republished delivered map keeps `version` and changes `content_version`, so a client that had the old pack loaded the old geometry. It now takes the announced definition when a delivered map's `content_version` differs from `effective_content_version()`. `map_selftest`: "a remembered delivered map announced at another pack version is taken as announced" (armed).
