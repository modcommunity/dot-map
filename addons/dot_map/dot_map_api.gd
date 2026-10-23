extends RefCounted

## dot-map's API level. The rule for bumping it is on [DotAddonApi].
##
## LEVEL rises by one for anything a game could call that did not exist before. OLDEST is
## raised to LEVEL when something a game could have called is removed or changes meaning,
## because every pack built before that no longer compiles against this addon.

# 1: everything before this file existed (absent means 1).
# 2: DotMapDef.from_content_key and DotMapCatalogue.add_delivered.
# 3: a relative scene given to either is resolved onto the pack's mount.
# 4: DotMapSurfaces, the surface-kind material library (and its textures in surfaces/).
# 5: DotMapRotationFile (cfg/maps.yml: rotations, wildcards, `commands:`), DotMapDef.in_rotation,
#    DotMapRotation.reset_cursor, DotMapCommands.spec_fn / chat_prefix / skipped / typed (names
#    that take aliases). Needs dot-core API level 12 (DotYaml, DotRotationSpec, DotCommandNames).
# 6: DotMapCatalogue.content_refreshed; DotMapRotationFile re-applies its marks on it, so a
#    content refresh no longer puts unlisted pack maps back in rotation.
# 7: DotMapRotationFile.find_layers; find("cfg/maps.yml") reads cfg/addons/dot_map/maps.yml (and
#    the operator's cfg/server/dot_map/), the flat cfg/maps.yml through DotCfgLegacy until
#    2026-12-31. Needs dot-core API level 15.
# 8: find_layers(config_dir, game) reads the game tier and the mirrored cfg/server/addons and cfg/server/game
#    tiers; an operator maps.yml replaces the shipped one unless it starts `merge: true`; `remove: [ids]`;
#    DotMapRotation.sort_unordered (no file: installed maps sorted by id). Needs dot-core API level 17.
# 9: DotMapDef.play and play_candidates, DotMapRotationFile.settings_for: a rotation entry may carry
#    settings ({pattern: {waves: easy}}, dot-core 9fc12e1). Needs that dot-core.
# 10: DotMapConfig (map/<name>.yml per-map settings with wildcards, a key whitelist, apply and restore on map change).
# 11: DotMapIO, the input/output runtime (io/: DotMapEntity and the logic classes, register_handler / register_class,
#     the damage/move/effect/event/actor callables, load_catalogue, spawn_record, globals).
# 12: world entities on the I/O runtime: DotMapToggleBrush, DotMapBreakable, DotMapMoverNode, DotMapStateSync (io_state/io_snapshot), bind_world.
# 13: volumes on the I/O runtime: DotMapVolumes (trigger_hurt, push, teleport, gravity, trigger, ladder_boxes, water_boxes),
#     DotMapHurt, DotMapPush, DotMapEffect, DotMapSound, DotMapCommand, DotMapIO.settle / destinations / area_damage.
# 14: DotMapWorld (one call builds a converted map's world), filter_multi, prop_door_rotating and func_physbox classes.
const LEVEL := 14
const OLDEST := 1
