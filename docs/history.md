# History

Bugs worth recognising if they come back. The rule each left is in [content.md](content.md), [changing.md](changing.md) or [rotation.md](rotation.md).

## What the first transport found

The sync protocol first ran over a real network in game-g2gfast (dot-net, a server and a client), and five things in this addon were wrong. Each is fixed with a check in `map_selftest` that was armed by putting the old line back.

- **A joiner was never told to load.** `join_payload()` is an announce, and `load` was only sent at the end of a change, so a peer that joined between changes fetched the map, said ready, and waited for ever.
- **A peer admitted mid-change was waited on**, though `add_peer` said it was not: `_wait_for_peers` counted every peer on every poll, so the change was held to its timeout and the joiner reported as a straggler for a map it had never been announced.
- **The delivered-map rule refused the template shape**, so a game whose maps are data read by one built-in scene could not receive any map. game-g2gfast worked around it by fetching by its own convention before dot-map saw the announce.
- **A refused `load` adopted the map it refused**: `_on_load` set `announced` from the catalogue before checking the version.
- **Progress was unthrottled**: one message per dot-cloud progress signal, into a server that drops a client's excess without choosing, could cost the `ready` behind it.
- And, while writing those checks: **a `load` that overtook its own fetch was taken at once**, asking for the same pack twice; it worked only because dot-cloud joins a running request.

## Others

- **Every delivered map failed** with "the registered cloud client does not speak the content interface": dot-map called `ensure` / `is_mounted` and dot-cloud offered `acquire(manifest_url)` / `is_ready(content_key)`. The only loader test ran without a cloud client. Before that, **`DotCloudClient` did not register itself at all** and every caller read null as "content is in the build".
- **A republished delivered map loaded the old geometry**: `_accept` matched a remembered map on `version` alone.
- **`"banana"` was a valid map version**: `DotSemVer.parse` never returns null.
- **A missing `await` on a coroutine is a parse error, and the scene then hangs** rather than exiting. It looks like an infinite loop in the test and it is a typo; run the check-only pass first.
- **`map` was refused for operators with the right flag** when typed in chat, because the old default marked it console-only; `sv_chat_commands` now decides.
- **`map` meant `changelevel` in dot-server** before this addon existed, so an operator typing `map <name>` on a one-game, many-map server got a refusal naming games.
