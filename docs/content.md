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

## Shared stores as dot-cloud slices

A converted map draws library textures and models that live in shared stores (`pbr-library`, `model-library`), not in its pack. `bsp.py storepack` publishes what each manifest draws as dot-cloud content, imported with VRAM compression, and writes `licence.store_pack = {id, version, shared}` into the manifest. A PBR set or model is cut by the group of maps that draw it; a group that is among the `--shared N` (default 8) biggest of any of its maps becomes its own slice, `<owner>/store-shared-<hash of the maps>@h<hash>`, and everything else stays in the map's own slice `<owner>/store-<map>@h<hash>` (the root, which also holds `credits.json`). The root declares its shared slices as manifest `dependencies`; dot-cloud takes eight per manifest and a chain four deep, so a root with more goes through empty group nodes (`store-<map>-g<level>-<n>`, a `group.json` and their own dependencies). A client that has downloaded map A fetches only the shared slices of map B that it lacks. `--shared 0` is one self-contained slice per map. The map's pack is published with `--depends id@version` (dot-cloud API 15), or `DotMapStore.ensure` fetches the root: either way the dependencies come first, once per client, because a pack mounts at `res://dot_cloud/<id>/<version>/` and never unmounts. `DotMapStore.apply(licence, cloud, surfaces, world)` sets `pbr_libraries` and `model_libraries` to the mounted root and its shared slices (the singular `pbr_library` and `model_library` to the root); `DotMapSurfaces` and `DotMapBspMesh` look a set or model up in each in order, `load()` the imported texture or model there and fall back to reading the webp or glb from a folder when no slice is mounted.

## Without the slices

A world whose slices are not mounted (a standalone `./game.sh play` has no dot-cloud client at all; a client whose server does not publish them gets a failed fetch) is still drawn, never white. `DotMapStore.ensure` records the missing ids and puts "Low-detail art: N art slices not installed" on the open `DotLoadGate` and into `DotMapCredits.line`; `DotMapStore.apply` logs one WARN per map naming the slice ids and how to get them, unless the raw stores are found beside the pack. `DotMapSurfaces.world_material_for` then draws each missing PBR set with, in order: the pack's own small albedo (`fallback_file`, `textures/fb_<set>.webp`, 64 px, about 30 KB a map, written by `bsp.py smallalbedo` or at the end of the licence pass), the addon's CC0 photo of the kind its name says (`stand_in_kind`: brick, grass, rock, ground, sand and the rest, tinted to the face's recorded colour), or the face's own flat colour; on a lightmapped map all three keep the author's baked light. Library models are left out.

Three ways to the full art:

- **Players**: publish the slices (`bsp.py storepack --dist`, then the team's publish step) and the map pack with `--depends`; the shell's dot-cloud client fetches them through `DotMapStore.ensure`. This is the only way a player gets them, and it is the operator's decision, because some sources' licences do not allow redistribution.
- **Publishing the slices to the team's origin**: sign with the key the shipped client trusts (`dot-server-deploy/keys/content.key`, whose public half is `client/content.json`'s `trusted_keys`; `storepack --dist <dir> --key <it>`, or re-sign each manifest's decoded payload with RS256; the client tries every trusted key, so `key_id` is only a label, and the team's packs use `tmc`). Read `GAMES_S3_ACCESS_KEY`, `GAMES_S3_ACCESS_SECRET`, `GAMES_S3_BUCKET` and `GAMES_S3_REGION` from the developer box's `.env` beside the repositories, the same file `deploy-web-shell.sh` uses, never from a commit. Check that each `<id>/<version>/` prefix is empty first, because a published id@version is never overwritten. For each `<owner>_<name>/<version>/` in the dist, `aws s3 sync` its `objects/` and `bundles/` to `s3://$GAMES_S3_BUCKET/game/content/<owner>/<name>/<version>/` with `--cache-control "public, max-age=31536000, immutable"`, then `aws s3 cp` its `manifest.json` last with `--content-type application/json --cache-control "public, max-age=300"`. Last, check that `<origin>/content/<id>/<version>/manifest.json` answers 200 and that its signature verifies against `client/content.json`.
- **A developer from a fresh bootstrap**: `tools/stage_stores.sh <maps repo> --from <src> --game <game>` copies the raw `pbr-library/` and `model-library/` (about 2 GB, never the slice build project) into `<maps repo>/.stores` and links `<game>/.stores` to it, kept out of git through the game's `.git/info/exclude`. A world's `licence.pbr_store` (`../../.stores/pbr-library`) resolves to `res://.stores` inside the game, so the standalone game then reads every set and model from files. `<src>` is an rsync source (`dev02:godot/zombie-zone-maps/.stores` for the team), a folder, or an http URL of a tar, and `$DOT_STORES_FROM` sets it once.
- **Nothing staged**: the small albedos above, which ship inside the pack.

Credits: `DotMapCredits.works(manifest, true)` lists the works whose licence requires naming the author; `DotMapCredits.line(manifest)` is the one line for a scoreboard or menu.

Compression measured on ze_death_star_escape (274 textures in 1k and 2k, 29 models): the source WebP and JPG store is 90 MB, the VRAM-compressed slice is 244 MiB of S3TC for a desktop or web client and 244 MiB of ETC2 for a phone or web client (the publisher tags `.s3tc`/`.bptc` and `.etc2`/`.astc` files by platform, API 15; a client downloads one set), about 2.7 times the WebP download. What it buys: 60 albedo maps (63 Mpx) took 864 ms to decode, mip and upload from WebP and 24 ms to `load()` as imported textures (CPU side, same box), and the GPU holds about a quarter to an eighth of the RGBA8 size. `storepack --lossless` imports without VRAM compression for a game that prefers the smaller download.
