# Changing a map, locally and for everybody

## The order of a change

`DotMapSession.change_to_map` is the most dangerous thing a server does: players are in runs, entities are replicated, content may still be downloading, and the scene about to be freed is the one everything holds a reference to. The order is:

1. **announce** (`changing`) before anything is torn down, so a timer can abandon its runs and a netcode can stop replicating entities that are about to vanish;
2. **fetch and load the new scene** before freeing the old one;
3. free the old world and add the new one **in the same call**;
4. **announce** (`changed`) so listeners can rebuild.

**Step 2 is the one people skip.** Freeing first is simpler, uses less memory, and turns a CDN having a bad day into a server with no map and no way back. `_test_change_survives_a_failure` in `examples/map_selftest.gd` guards it: it points a map at a scene that does not exist, and requires that the session is still on the map it was running, with that world still in the tree, and able to change again afterwards.

Step 3 uses `free()` and not `queue_free()`, because the new world goes in during the same call and a deferred free would leave both in the tree for a frame: two maps' worth of collision geometry, and any group lookup finding the old one.

A second change while one is in progress is **refused, not queued**: two overlapping changes free the same node twice, and the second one's `await` resumes into a tree the first has already rebuilt.

## Changing the map for everybody

`DotMapSession` changes the map **in this process** only. Without a protocol, a dedicated server freed its world, loaded the next one, and every connected client carried on playing the map that no longer existed; broadcasting a map id and hoping every client has the scene in its build works until the first map that is delivered rather than shipped.

`addons/dot_map/net/` is the protocol. Five messages:

```
announce  host -> peer   here is the map we are going to; go and get it
progress  peer -> host   I am n% of the way there
ready     peer -> host   I have it
load      host -> peer   everyone has it; put it on screen now
abort     host -> peer   the change was abandoned; stay where you are
```

**`announce` and `load` are separate on purpose.** The host does not swap until its peers can, so there are necessarily two moments. Collapsing them is a bug this family has had by another name: dot-server's `report_content_ready` once sent a client to load the game the server had not swapped to yet.

The rules each of which was a real failure once ([history](history.md#what-the-first-transport-found)):

- **A joiner is told to load.** The host answers a `ready` for the map it is on, while no change is running, with a `load`, **once per peer per map**. That covers `admit_peer` (the one-call join), a host that calls `add_peer` and sends `join_payload` itself, and a straggler whose download landed after the change went ahead. The "once" matters: a straggler already sent the change's `load` must not be sent a second and rebuild its world.
- **A change waits only on the peers registered when it began** (`_participants`): those are the ones it sends `load` or `abort` to and counts as ready. A peer added during it is announced whatever map the host settled on.
- **A refused `load` adopts nothing**: the requested version is checked before `announced` is set.
- **Progress is throttled** by `progress_interval_sec` (0.25 s; 0 turns it off), because a server that rate-limits a client drops the excess without choosing, and that can be the `ready`. The first report of a fetch, a report of 1.0 and every `ready` always go; the local `fetch_progress` signal is never throttled.
- **A `load` that overtakes its own fetch is held** until the fetch lands (`_load_after_fetch`), and an `abort` drops it. That is exactly the straggler `swap_without_stragglers` makes; taking the `load` at once asked the content client for the same pack twice mid-download, which only worked because dot-cloud happens to join a running request.
- **A delivered map is compared by its pack too.** A republished delivered map keeps `version` and changes `content_version`; `_accept` takes the announced definition when its `content_version` differs from `effective_content_version()`, or a client with the old pack loads the old geometry.

### Changing a game and changing a map are different operations

Confusing them is how you get a server that reconnects everybody every four minutes:

| | Changing a **game** (dot-server) | Changing a **map** (here) |
| --- | --- | --- |
| What is replaced | The module, the netcode, the client's scene | The world, and nothing else |
| What happens to players | `SPAWNED -> DOWNLOADING -> LOADING -> SPAWNED` | They stay spawned |
| Who owns it | `DotGameManager` | `DotMapSyncHost` |
| How often | Rarely: an operator's decision | Every few minutes, by a vote or a timer |
| What a client is told | A game id, a content key and a scene | A map definition |
| Cost | A signon | A content fetch, and often not even that |

A rotation running through `DotGameManager.change_game` would put every player through signon on every map.

## The commands

**`map` is a command here, not in dot-server.** Every server operator types `map` for the thing that swaps the level, and on a server running one game and a hundred maps that means the right-hand column of the table above. dot-server's game change is `changelevel`, `game` and `gamechange`.

`DotMapCommands.install(host, session)` registers `map`, `maps` and `mapinfo` on anything with `add_command` (a `DotModule`) or `command` (a `DotConsole`), duck-typed, so this file names no dot-server class. Pass a `DotMapSyncHost` as the third argument when the change has to reach clients; it has the same three change methods, deliberately.

- **`map` says nothing about chat.** `admin_permission` (`changemap`) decides who may change the map, the same way wherever the line was typed; `map` is left at `ChatPolicy.DEFAULT` so the host's `sv_chat_commands` has the last word, and `allow_chat_change = false` marks it `no_chat()` for a records server that wants a map change to cost a trip to the console.
- **`nextmap` is not registered here.** dot-vote registers `nextmap` and `timeleft` over the same maps, and two commands of one name is the last one registered winning silently. `mapinfo` answers both questions without taking a name somebody else has.

## The host may say *which* map, never *what* the map is

`DotMapSyncClient` takes the map from **its own catalogue** when it has the id. The announced definition is only used for a map it does not have, and then it must be *delivered*: it has to name a `content_id`, and its scene and zone paths have to resolve inside `res://dot_cloud/<id>/<version>/` after `simplify_path()`.

This is the rule `DotClientLink._resolve_scene` enforces, for the same reason, and the `simplify_path` is there because `"res://a/b/../../evil"` does `begins_with("res://a/b/")`. Without the delivered requirement a host could name any scene in the client's own build; with it, the worst it can do is make the client download its content, which is what connecting to it already meant. `accept_unknown_maps = false` is for a client that ships every map it will ever play.

**`accept_unknown_maps` defaults to on because of records servers**: one carries two hundred maps and its clients ship none of them.

### Template scenes

A game whose maps are data (a manifest and a mesh, turned into a world by one scene the game ships) can never put that scene in the pack, because a pack's script cannot extend a class of the build it is mounted into; the strict rule refused every such map. `trusted_template_scenes` (empty by default, which is the strict rule unchanged) lets a client accept an announce naming that exact scene, after `simplify_path`, if the map names a `content_id` and its data resolves inside `res://dot_cloud/<content_id>/<version>/`: `zones_path`, every key in `template_path_keys` (default `manifest`, at least one required), and every *path-shaped* string anywhere in `meta`, nested or not.

The sweep of the whole of `meta` is fail-closed on purpose: a template that one day reads a key nobody listed must not be the day a host can point it at `user://` or a file in the build. What a hostile host can still do is make the client fetch any content from the client's own origin (or from the announce's `manifest_url`; signed manifests stop that from mounting anything) and instantiate a listed scene over it. **So the template is the attack surface**: it must treat what the pack holds as untrusted input and take paths only from keys the check covers. The class doc on `trusted_template_scenes` says the same, where the next person to add a key will read it.

## It is transport-agnostic, and that is not laziness

This addon depends on nothing but dot-core, so it cannot know whether the game carrying these messages uses dot-net's bit packer, Godot's RPCs, a WebSocket or a loopback. `send_fn` takes a `Dictionary` and one peer id, **never a broadcast address**, because `send(payload, 0)` is how this family once delivered a private per-player message to every client at once. The loop over peers is in the open, in `_broadcast`.

## Deliberately not here

- **A transport.** `send_fn` takes a `Dictionary`; putting it on a wire is the game's. dot-map cannot name dot-net.
- **Kicking a peer that cannot get the map.** `peer_timed_out` and `on_timeout_fn` say who; this addon has no session list and no socket, so it cannot drop anybody.
