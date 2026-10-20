# Maps as content: the definition, the catalogue, and loading

## One game, many maps

The question this addon answers is "how do we ship a hundred surf maps", and the answer a first look at Godot suggests (one project per map) is wrong in a way that only becomes obvious at map forty:

| One project per map | One game, many maps |
| --- | --- |
| A hundred export pipelines | One |
| A hundred copies of every addon | One |
| A player downloads a whole game to try a map | They download a map |
| Records are per-project, so there is no leaderboard across maps | One records table |
| A "server" can only ever run one map | A server runs a rotation |
| A map fix is a release | A map fix is a version bump on one pack |

So a map is a `DotMapDef`: an id, a version, a scene path, and optionally a dot-cloud content id the scene lives inside. It is how every game in this genre has worked for decades, and it is the shape the rest of the family was built for: dot-cloud namespaces content by `id/version` *because a mounted resource pack can never be unmounted on any platform*, so a new version of a map is a new mount rather than a replacement, and a server can hold both while players finish their runs on the old one.

**A map id is never renamed.** Records name their map by it, so changing one orphans every time ever set on it. `display_name` is the one to change.

## The catalogue is not the rotation

A server knows about two hundred maps and rotates through twelve. The other hundred and eighty still have leaderboards, are still nominatable, and still have to resolve when somebody links to one. Merging the two lists means removing a map from the rotation also removes it from the records, which is how a leaderboard nobody meant to delete disappears.

**One bad entry does not condemn the file.** A server with a hundred and ninety-nine good maps and one typo boots on the hundred and ninety-nine and says loudly which one it dropped. Refusing to start with an error nobody can locate is the worse failure, and on a community server the person maintaining this file is a person with a text editor.

**An exact id match wins a search outright.** On a server with `surf_a` and `surf_a2`, a substring search returns both, and whatever picks the first has chosen for the player who typed the full name.

**A version is checked with `.valid`.** `DotSemVer.parse` always returns an object and reports the outcome on `.valid`; a `== null` check passes for every string, and `"banana"` was once a valid map version.

## Reaching dot-cloud without naming it

`DotMapLoader` finds the cloud client in `DotRegistry` under `dot_cloud_client` and calls `ensure(content_id, version, groups, manifest_url)` and `is_mounted(content_id, version)` by name. The family rule is reason enough (a script that *mentions* an absent `class_name` fails to parse), but there is a sharper one:

`DotCloudClient` once failed to publish itself under that name. Four call sites across two addons found null, and **every one treated an absent cloud as "this deployment ships its content in the build"**, which is a legitimate configuration and therefore indistinguishable from the bug. Nothing errored, for months.

So `DotMapLoader.require_cloud` exists. A deployment that *knows* its maps are delivered sets it and gets a loud `CODE_STATE` failure naming the registry key it looked for, instead of a scene that mysteriously will not load.

**A call by name is an interface nobody checks.** `DotMapLoader` called `ensure` / `is_mounted` for a long time while `DotCloudClient` offered different names taking different things, so every delivered map failed and the only loader test ran with no cloud client at all (the disk fallback, which passes). `_test_sync_a_delivered_map` now publishes a real signed pack and drives a peer through fetching it, so the two ends meet in a test rather than in a deployment. Keep it that way when either side changes.

`DotMapDef.manifest_url` is the escape hatch and is normally empty: a catalogue of two hundred maps should not repeat the same CDN hostname two hundred times, so the cloud client builds the URL from `content_id`, `content_version` and its own `manifest_url_template`.

**Zones come back from `load_zones` as text**, not as a parsed `DotTimerZoneSet`. dot-timer is optional; naming the class here would make every map load in a game without a timer fail to parse. The host, which has dot-timer, calls `DotTimerZoneSet.from_json`.

## Workshop maps: following the content index

`DotMapCatalogue.follow_content(index, accepted_kinds)` adds the `map` entries of mounted packs (dot-core's `DotContentIndex`, filled by dot-cloud on mount) as delivered `DotMapDef`s, and rebuilds them whenever a pack arrives or the index changes session, so a subscription appears in solo and an online session never sees it. `accepted_kinds` is the game's `accepts.map_kinds`; empty means none, because the Workshop is opt-in per game, and `"*"` means every kind. A map the catalogue already holds under an id always wins over a pack's. `tag_pack` is silent, so call `refresh_content()` after it. A refresh emits `content_refreshed` (API level 6), which the `DotMapRotationFile` last applied to that catalogue listens to, so the fresh defs get the rotation's `in_rotation` marks (and `fallback_in`) again instead of defaulting to in. A pack map carries `pack_title`; `DotMapDef.label()`, `DotMapVote.option_labels()` and the `maps` command print it as `Name [Pack]`. The menu that draws the list belongs to the game or dot-menu and should print `label()`.

## Deliberately not here

- **A map downloader UI.** `fetching` says a fetch has started; dot-cloud reports progress; drawing a bar is the game's.
- **Map metadata scraped from the scene.** A tier, an author and a description are editorial, they change without the geometry changing, and reading them out of the scene would mean loading every map to list them.
- **Per-map addon configuration.** A map that needed different movement would be a different game mode, and that is `DotFpsTunables` plus dot-server's module system.
- **Anything about what is *in* a map.** Spawns, zones, props and lights are the scene's and the timer's. This addon knows a map's name, version and where its scene is.
