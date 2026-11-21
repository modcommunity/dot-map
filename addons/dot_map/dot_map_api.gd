extends RefCounted

## GameSpice Map's API level. The rule for bumping it is on [DotAddonApi]. LEVEL rises by one for anything a game
## could call that did not exist before. OLDEST is raised to LEVEL when something a game could have called is
## removed or changes meaning, because every pack built before that no longer compiles against this addon.

# 1: everything before this file existed (absent means 1). 2: DotMapDef.from_content_key and DotMapCatalogue.add_delivered. 3: a relative scene given to either is resolved onto the pack's mount. 4: DotMapSurfaces, the surface-kind material library (and its textures in surfaces/).

# 22: DotMapDef.profile, DotMapRotationFile.profile_changed, DotMapConfig.apply_values (per-map mode/cfg profiles). 23: DotMapLocalMaps (raw convert folders under res://addons/maps and user://maps, offered as "(local)").
# 24: DotMapLocalMaps zips (entry_in_zip, zip_cache) and drag-and-drop (accept_dropped, watch_drops, DROP_ROOT); DotMapDrawnWorld option original_textures.
# 25: DotMapSurfaces.shrink_textures_headless (default on): headless, a kind's textures load as 4x4 downsamples.
# 26: DotMapDropIntake (window, exe and --map-path drops, game acceptors, loud refusal); DotMapLocalMaps.zip_max_files, entry_within, zip_problem.
# 27: decal surface records ("decal": kind) drawn alpha-blended and depth-biased: DotMapBspMesh.DECAL_LOOKS, decal_material, decal_texture, is_decal_material, decal_depth_bias.
# 28: DotMapVpk (VPK v1/v2 directory-tree reader, CRC-checked), DotMapVtf (VTF to Image, VMT keys, material names) and DotMapVpkWriter (test fixtures) in source/: a player's own Source install read locally, never shipped.
# 29: DotMapDocDrop (the document-pack drop acceptor for games whose maps are JSON documents: a file, folder or zip; write_doc, lines).
# 30: DotMapDropIntake.config_prefixes, option_takes_value, paths_in, strip_config_args, config_takes_value (a game's own config options are never dropped paths).
# 31: DotMapBoxBatch (opaque static boxes of one material per cell drawn as one ArrayMesh; skip callable; skipped headless).
const LEVEL := 31
const OLDEST := 1
