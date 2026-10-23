# Per-map settings

A map can ask for settings (the commands its entities send, such as `sv_airaccelerate`, or anything an author wants per map) without ever running a command. `DotMapConfig` reads them from files, checks every key against a whitelist the game declares, applies them when the map loads and puts the previous values back on the next map.

## Where the files are

A file is `map/<name>.yml` inside each `dot-map` tier of dot-core's `DotAddonConfig`: `cfg/addons/dot_map/`, `cfg/game/<game>/dot_map/`, then the operator's `cfg/server/addons/dot_map/` and `cfg/server/game/<game>/dot_map/`, in every root. `<name>` is a map id or a glob (`surf_%.yml` covers every surf map: `%` is any run of characters, `@` is exactly one, case does not matter; the literal `*` and `?` still work but cannot be in a file name on Windows or in a published pack, so spell them `%` and `@`; map ids never contain either) and the content is a flat mapping of key to one scalar. Nothing is nested and no value is ever a command line.

## Which value wins

Strongest first: the command line (`--dot-map.map.<key>=v`) and environment (`DOT_MAP_MAP_<KEY>`), for a key a file or default already holds, as every `DotAddonConfig` override works; then the operator's tiers, an exact file over a wildcard; then the shipped tiers, an exact file over a wildcard; then the converter's default. Among wildcards the more specific wins: the most literal characters, then the longer pattern, then the later name alphabetically (so `surf_@` beats `surf_%`). At equal specificity the stronger tier (game over addon, per-game over shared) and the later root win. Keys merge one by one, so a stronger file only replaces the keys it names.

## The whitelist

The game declares what a map may set with `allow(key, {type, min, max})`, the names of cvars it registers; an empty schema allows nothing. A key outside it, a non-scalar, or a value of the wrong type is rejected, logged once as a warning and listed in `rejected` in the result of `resolve()`; it is never applied. A number outside `min`/`max` is clamped.

## Applying and restoring

The game gives `get_fn(key)` and `set_fn(key, value) -> bool` and calls `apply(map_id)` on every map load. `apply` first puts back what the last map changed (to the value before the first change), then applies the new map's settings. A key someone changed after it was applied (an operator typing the cvar mid-map) is left alone on restore. `restore()` is also what a module calls when it unloads.

## The converter's starter file

Every map gets one without being asked. `bsp.py store` writes `mapcfg.yml` into the map's store entry, and `bsp.py regen` writes `<outdir>/dot_map/map/<map_name>.yml` beside the regenerated map (copy that folder to `cfg/game/<game>/dot_map/map/` in the game's maps repo). Both come from the `Command` inputs aimed at `point_servercommand` entities; a map that sends none gets no file. Every value is commented out, commands that are not `name value` settings are listed as skipped, and an existing file is never overwritten. The same commands are also written into the converted manifest as `settings` (typed), which `DotMapWorld` uses as the weakest layer, so a map's own cvars apply once the game whitelists them. Nothing from the yml is applied until someone uncomments a line and the game whitelists the key. `python3 -m dotbsp.mapcfg OUT_DIR map.bsp ...` (from `tools/bsp`) does the same for loose files.

## Wiring a game

A game does not call `DotMapConfig` itself: dot-game's `DotGameMapConfig` is the one wiring (`DotGameModule._map_config_keys()` on the server, `DotGameClient.map_changed` on the client). See dot-game's docs/map-config.md.

## Export

`.yml` is dropped from an export unless the preset's filter includes `cfg/*`.
