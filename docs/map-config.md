# Per-map settings

A map can ask for settings (the commands its entities send, such as `sv_airaccelerate`, or anything an author wants per map) without ever running a command. `DotMapConfig` reads them from files, checks every key against a whitelist the game declares, applies them when the map loads and puts the previous values back on the next map.

## Where the files are

A file is `map/<name>.yml` inside each `dot-map` tier of dot-core's `DotAddonConfig`: `cfg/addons/dot_map/`, `cfg/game/<game>/dot_map/`, then the operator's `cfg/server/addons/dot_map/` and `cfg/server/game/<game>/dot_map/`, in every root. `<name>` is a map id or a glob (`surf_*.yml` covers every surf map, `?` is one character, case does not matter) and the content is a flat mapping of key to one scalar. Nothing is nested and no value is ever a command line.

## Which value wins

Strongest first: the command line (`--dot-map.map.<key>=v`) and environment (`DOT_MAP_MAP_<KEY>`), for a key a file or default already holds, as every `DotAddonConfig` override works; then the operator's tiers, an exact file over a wildcard; then the shipped tiers, an exact file over a wildcard; then the converter's default. Among wildcards the more specific wins: the most literal characters, then the longer pattern, then the later name alphabetically (so `surf_?` beats `surf_*`). At equal specificity the stronger tier (game over addon, per-game over shared) and the later root win. Keys merge one by one, so a stronger file only replaces the keys it names.

## The whitelist

The game declares what a map may set with `allow(key, {type, min, max})`, the names of cvars it registers; an empty schema allows nothing. A key outside it, a non-scalar, or a value of the wrong type is rejected, logged once as a warning and listed in `rejected` in the result of `resolve()`; it is never applied. A number outside `min`/`max` is clamped.

## Applying and restoring

The game gives `get_fn(key)` and `set_fn(key, value) -> bool` and calls `apply(map_id)` on every map load. `apply` first puts back what the last map changed (to the value before the first change), then applies the new map's settings. A key someone changed after it was applied (an operator typing the cvar mid-map) is left alone on restore. `restore()` is also what a module calls when it unloads.

## The converter's starter file

`python3 -m dotbsp.mapcfg OUT_DIR map.bsp ...` (from `tools/bsp`) writes `<map_name>.yml` from the `Command` inputs aimed at `point_servercommand` entities. Every value is commented out, commands that are not `name value` settings are listed as skipped, and an existing file is never overwritten. Nothing is applied until someone uncomments a line and the game whitelists the key.

## Export

`.yml` is dropped from an export unless the preset's filter includes `cfg/*`.
