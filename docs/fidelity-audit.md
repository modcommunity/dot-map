# Gameplay fidelity audit

Every BSP the converter can be asked for, read by `dot-map-convert/tools/fidelity_audit.py` (converter 3089e8a):
each entity class is classed implemented / approximated / ignored / unknown, and every way a map's gameplay
(teleports, triggers, doors, buttons, logic, filters, push, hurt, water, spawns, checkpoints, timers) can be lost
is a finding. Severity: **lost** (the converter drops it; a bug), **unsupported** (listed, fails loudly in the
report, needs a runtime component), **source** (the original map does the same nothing), **handled** (counted
so a regression shows).

Regenerate:

```
hv <dot-map-convert wt> local python3 -P tools/fidelity_audit.py OUT.json <dir> --jobs 3 --md OUT.md
```

Shipped maps carry the same findings as `lists.gameplay_lost` in their `*.coverage.json`, ratcheted by
`tools/coverage_gameplay.py --check` (a new loss fails CI). Playlot's converted worlds are also checked by
`playlot-maps/tools/check_worlds.py` in CI: every map has its world pack, a ground-supported spawn inside the
world bounds, and no more than 1% of its BSP hulls absent.

## mapsrc (1033 maps)

### Totals

1028 distinct maps audited, 5 could not be read.

| Finding | Severity | Maps | Items | Meaning |
| --- | --- | --- | --- | --- |
| `volume_unrecorded` | lost | 207 | 1027 | a trigger/volume brush entity with no volume record (nothing touches it) |
| `class_unsupported` | unsupported | 831 | 3572 | a gameplay class (wired by outputs, or a trigger/logic/filter/game class) with no runtime component |
| `input_unimplemented` | unsupported | 718 | 4152 | an input sent to an entity whose component does not implement it |
| `player_input` | unsupported | 356 | 810 | an input sent to the player (!activator/!player): the game's actor must implement it |
| `class_unknown` | unsupported | 249 | 1434 | a class nobody decided about (no classes.tsv row) |
| `filter_class_unsupported` | unsupported | 203 | 1955 | a filter class the runtime does not evaluate (admits everyone) |
| `volume_parented` | unsupported | 120 | 468 | a volume parented to something that moves without a mover record (a prop_dynamic, a physics object): the volume stays where it was compiled |
| `volume_key_unread` | unsupported | 37 | 205 | a gameplay key on a volume the runtime does not apply |
| `target_dangling` | source | 332 | 2979 | an output target no entity carries (the original does nothing there either) |
| `volume_follows` | handled | 277 | 1717 | a volume parented to a door, lift, train or spinner (through parents that do not move): DotMapVolumeNode carries it with the mover chain, SetParent included |
| `filter_dangling` | source | 184 | 1056 | a filtername no entity carries (the engine admits everyone) |
| `parent_dangling` | source | 54 | 238 | a parentname no entity carries |
| `teleport_dangling` | source | 21 | 40 | a trigger_teleport target no entity carries (the engine does nothing) |
| `teleport_target_dynamic` | handled | 14 | 76 | a trigger_teleport whose target logic changes at run time (AddOutput target / SetRemoteDestination); DotMapTeleport re-aims it as the engine does |

### Entity classes

| Status | Classes | Of which gameplay |
| --- | --- | --- |
| implemented | 244 | 80 |
| approximated | 88 | 29 |
| ignored | 90 | 20 |
| unknown | 118 | 12 |

Gameplay classes not implemented, by maps using them:

| Class | Status | Maps |
| --- | --- | --- |
| `path_track` | approximated | 389 |
| `point_viewcontrol` | ignored | 243 |
| `func_respawnroom` | unknown | 232 |
| `filter_activator_tfteam` | ignored | 229 |
| `func_respawnroomvisualizer` | unknown | 215 |
| `func_regenerate` | approximated | 207 |
| `trigger_capture_area` | approximated | 183 |
| `func_buyzone` | ignored | 177 |
| `env_laser` | approximated | 134 |
| `game_round_win` | unknown | 114 |
| `env_entity_maker` | approximated | 113 |
| `game_text` | approximated | 98 |
| `player_speedmod` | approximated | 83 |
| `player_weaponstrip` | approximated | 70 |
| `trigger_add_tf_player_condition` | approximated | 47 |
| `func_clip_vphysics` | ignored | 47 |
| `func_bomb_target` | approximated | 46 |
| `logic_script` | ignored | 39 |
| `game_forcerespawn` | unknown | 35 |
| `point_push` | approximated | 31 |
| `point_teleport` | approximated | 24 |
| `game_intro_viewpoint` | unknown | 23 |
| `point_hurt` | approximated | 21 |
| `env_firesource` | approximated | 21 |
| `trigger_stun` | approximated | 19 |
| `logic_waves` | approximated | 19 |
| `math_remap` | approximated | 18 |
| `trigger_catapult` | approximated | 18 |
| `game_end` | unknown | 17 |
| `path_corner` | unknown | 17 |
| `func_hostage_rescue` | ignored | 16 |
| `trigger_ignite_arrows` | ignored | 15 |
| `trigger_look` | approximated | 14 |
| `game_text_tf` | unknown | 12 |
| `func_nogrenades` | unknown | 12 |
| `trigger_ignite` | ignored | 11 |
| `trigger_vphysics_motion` | approximated | 10 |
| `logic_branch_listener` | approximated | 8 |
| `game_weapon_manager` | ignored | 8 |
| `trigger_apply_impulse` | approximated | 7 |
| `logic_gamerules` | ignored | 7 |
| `trigger_player_respawn_override` | ignored | 6 |
| `filter_tf_condition` | ignored | 6 |
| `filter_tf_damaged_by_weapon_in_slot` | ignored | 6 |
| `trigger_remove_tf_player_condition` | approximated | 5 |
| `trigger_add_or_remove_tf_player_attributes` | approximated | 4 |
| `filter_tf_class` | ignored | 4 |
| `trigger_autosave` | ignored | 4 |
| `trigger_waterydeath` | ignored | 4 |
| `trigger_proximity` | approximated | 4 |
| `trigger_remove` | ignored | 3 |
| `trigger_brush` | approximated | 3 |
| `game_ragdoll_manager` | unknown | 3 |
| `trigger_passtime_ball` | approximated | 3 |
| `func_tank` | unknown | 3 |
| `game_zone_player` | unknown | 3 |
| `trigger_rd_vault_trigger` | ignored | 2 |
| `filter_base` | ignored | 1 |
| `trigger_timer_door` | approximated | 1 |
| `filter_tf_bot_has_tag` | ignored | 1 |
| `trigger_teleport_relative` | approximated | 1 |

### Other mappable categories

| Category | Maps | Entities |
| --- | --- | --- |
| lights | 996 | 203002 |
| sound | 850 | 36427 |
| sprites_beams | 825 | 69996 |
| physics_props | 790 | 85992 |
| particles | 773 | 32121 |
| sky_fog_post | 749 | 3318 |
| water | 742 | 2089 |
| commands | 559 | 2943 |
| decals_overlays | 467 | 34001 |
| nav_ai | 458 | 105065 |

Maps carrying: 
Maps packing sounds: 0; packing sound scripts or soundscapes: 0

### Per map

| Game | Map | Entities | Severe | Top findings |
| --- | --- | --- | --- | --- |
| Deathrun | DR_Ramesses_Revenge_v3 | 365 | 5 | class_unsupported 3, input_unimplemented 2 |
| Deathrun | Deathrun_Crash_Medievil | 699 | 28 | volume_parented 12, input_unimplemented 7, class_unsupported 6, player_input 2 |
| Deathrun | Deathrun_Eazy | 60 | 0 |  |
| Deathrun | Deathrun_Southpark_V3 | 491 | 6 | class_unsupported 5, input_unimplemented 1 |
| Deathrun | Deathrun_Spongebob_Finalfix2 | 911 | 13 | class_unsupported 6, input_unimplemented 5, volume_parented 2 |
| Deathrun | Deathrun_gyro_Final_v3 | 466 | 1 | class_unsupported 1 |
| Deathrun | deathrun_aztecan_finalb3 | 313 | 4 | class_unsupported 3, input_unimplemented 1 |
| Deathrun | deathrun_aztecan_finalb3 | 313 | 4 | class_unsupported 3, input_unimplemented 1 |
| Deathrun | deathrun_bathroom_b1 | 199 | 2 | class_unsupported 2 |
| Deathrun | deathrun_bathroom_b1 | 199 | 2 | class_unsupported 2 |
| Deathrun | deathrun_crash_medievil | 699 | 28 | volume_parented 12, input_unimplemented 7, class_unsupported 6, player_input 2 |
| Deathrun | deathrun_eazy | 60 | 0 |  |
| Deathrun | deathrun_family_guy_final2 | 550 | 28 | volume_parented 9, class_unsupported 7, input_unimplemented 6, player_input 5 |
| Deathrun | deathrun_family_guy_final2 | 550 | 28 | volume_parented 9, class_unsupported 7, input_unimplemented 6, player_input 5 |
| Deathrun | deathrun_gyro_final_v3 | 466 | 1 | class_unsupported 1 |
| Deathrun | deathrun_hadicap_v6 | 72 | 0 |  |
| Deathrun | deathrun_hadicap_v6 | 72 | 0 |  |
| Deathrun | deathrun_helix_b8-1 | 1076 | 29 | input_unimplemented 11, class_unsupported 11, player_input 5, volume_parented 2 |
| Deathrun | deathrun_helix_b8-1 | 1076 | 29 | input_unimplemented 11, class_unsupported 11, player_input 5, volume_parented 2 |
| Deathrun | deathrun_holyshit_v2 | 968 | 23 | class_unsupported 10, input_unimplemented 7, volume_parented 5, player_input 1 |
| Deathrun | deathrun_holyshit_v2 | 968 | 23 | class_unsupported 10, input_unimplemented 7, volume_parented 5, player_input 1 |
| Deathrun | deathrun_iceworld_v2fix | 1066 | 11 | input_unimplemented 5, class_unsupported 4, player_input 1, volume_parented 1 |
| Deathrun | deathrun_iceworld_v2fix | 1066 | 11 | input_unimplemented 5, class_unsupported 4, player_input 1, volume_parented 1 |
| Deathrun | deathrun_internet | 240 | 2 | input_unimplemented 1, class_unsupported 1 |
| Deathrun | deathrun_internet | 240 | 2 | input_unimplemented 1, class_unsupported 1 |
| Deathrun | deathrun_lego_world_finalfix3 | 452 | 9 | class_unsupported 5, input_unimplemented 3, volume_parented 1 |
| Deathrun | deathrun_lego_world_finalfix3 | 452 | 9 | class_unsupported 5, input_unimplemented 3, volume_parented 1 |
| Deathrun | deathrun_marioworld_finalob | 1449 | 17 | class_unsupported 12, input_unimplemented 5 |
| Deathrun | deathrun_marioworld_finalob | 1449 | 17 | class_unsupported 12, input_unimplemented 5 |
| Deathrun | deathrun_office | 249 | 17 | volume_parented 12, class_unsupported 3, input_unimplemented 2 |
| Deathrun | deathrun_office | 249 | 17 | volume_parented 12, class_unsupported 3, input_unimplemented 2 |
| Deathrun | deathrun_parking_garage | 494 | 11 | class_unsupported 6, input_unimplemented 5 |
| Deathrun | deathrun_parking_garage | 494 | 11 | class_unsupported 6, input_unimplemented 5 |
| Deathrun | deathrun_silenthill_v2 | 588 | 13 | input_unimplemented 7, class_unsupported 6 |
| Deathrun | deathrun_silenthill_v2 | 588 | 13 | input_unimplemented 7, class_unsupported 6 |
| Deathrun | deathrun_simpsons_final | 491 | 7 | class_unsupported 6, input_unimplemented 1 |
| Deathrun | deathrun_simpsons_final | 491 | 7 | class_unsupported 6, input_unimplemented 1 |
| Deathrun | deathrun_southpark_v3 | 491 | 6 | class_unsupported 5, input_unimplemented 1 |
| Deathrun | deathrun_spongebob_finalfix2 | 911 | 13 | class_unsupported 6, input_unimplemented 5, volume_parented 2 |
| Deathrun | deathrun_tp_percolate_oreo | 297 | 8 | input_unimplemented 4, class_unsupported 2, player_input 1, volume_parented 1 |
| Deathrun | deathrun_tp_percolate_oreo | 297 | 8 | input_unimplemented 4, class_unsupported 2, player_input 1, volume_parented 1 |
| Deathrun | deathrun_tribute_final | 1191 | 18 | class_unsupported 9, input_unimplemented 8, volume_parented 1 |
| Deathrun | deathrun_tribute_final | 1191 | 18 | class_unsupported 9, input_unimplemented 8, volume_parented 1 |
| Deathrun | deathrun_underconstruction_v5 | 264 | 5 | class_unsupported 3, input_unimplemented 2 |
| Deathrun | deathrun_underconstruction_v5 | 264 | 5 | class_unsupported 3, input_unimplemented 2 |
| Deathrun | dr_death_v1 | 130 | 6 | volume_key_unread 7, input_unimplemented 3 |
| Deathrun | dr_death_v1 | 130 | 6 | volume_key_unread 7, input_unimplemented 3 |
| Deathrun | dr_horrorhousecompleted | 1018 | 13 | input_unimplemented 6, class_unsupported 5, volume_parented 2 |
| Deathrun | dr_horrorhousecompleted | 1018 | 13 | input_unimplemented 6, class_unsupported 5, volume_parented 2 |
| Deathrun | dr_pirateships_b3 | 346 | 8 | input_unimplemented 3, volume_parented 2, class_unsupported 2, player_input 1 |
| Deathrun | dr_pirateships_b3 | 346 | 8 | input_unimplemented 3, volume_parented 2, class_unsupported 2, player_input 1 |
| Deathrun | dr_ramesses_revenge_v3 | 365 | 5 | class_unsupported 3, input_unimplemented 2 |
| FC | 2koth_abbey | 1371 | 23 | input_unimplemented 8, volume_unrecorded 6, filter_class_unsupported 6, class_unsupported 5 |
| FC | DR_Ramesses_Revenge_v3 | 365 | 5 | class_unsupported 3, input_unimplemented 2 |
| FC | Deathrun_Eazy | 60 | 0 |  |
| FC | Deathrun_Southpark_V3 | 491 | 6 | class_unsupported 5, input_unimplemented 1 |
| FC | Surf_Mesa | 228 | 3 | class_unsupported 3 |
| FC | ZM_Krusty_krab_a3 | 839 | 9 | class_unsupported 6, input_unimplemented 2, player_input 1 |
| FC | Zm_mansion_css_beta | 653 | 32 | class_unsupported 10, input_unimplemented 9, volume_parented 9, player_input 4 |
| FC | aim-forts | 56 | 1 | class_unsupported 1 |
| FC | arena_afterlife | 1010 | 6 | class_unsupported 4, class_unknown 2 |
| FC | arena_badlands | 256 | 9 | class_unsupported 4, class_unknown 3, input_unimplemented 2 |
| FC | arena_byre | 405 | 9 | class_unsupported 5, filter_class_unsupported 2, class_unknown 2, input_unimplemented 1 |
| FC | arena_granary | 203 | 9 | class_unsupported 4, class_unknown 3, input_unimplemented 2 |
| FC | arena_lumberyard | 206 | 10 | class_unsupported 4, class_unknown 4, input_unimplemented 2 |
| FC | arena_lumberyard_event | 707 | 21 | class_unknown 9, input_unimplemented 7, class_unsupported 4, player_input 1 |
| FC | arena_nucleus | 411 | 7 | class_unsupported 5, input_unimplemented 1, class_unknown 1 |
| FC | arena_offblast_final | 245 | 9 | class_unsupported 4, class_unknown 3, input_unimplemented 2 |
| FC | arena_perks | 1330 | 23 | class_unsupported 9, input_unimplemented 5, class_unknown 5, volume_unrecorded 4 |
| FC | arena_ravine | 266 | 10 | class_unsupported 4, class_unknown 4, input_unimplemented 2 |
| FC | arena_sawmill | 276 | 9 | class_unsupported 4, class_unknown 3, input_unimplemented 2 |
| FC | arena_watchtower | 148 | 8 | class_unknown 3, class_unsupported 3, input_unimplemented 2 |
| FC | arena_well | 442 | 12 | class_unsupported 6, class_unknown 4, input_unimplemented 2 |
| FC | background01 | 140 | 2 | class_unsupported 2 |
| FC | bhop_Evolve | 495 | 0 |  |
| FC | bhop_amor | 392 | 3 | player_input 1, input_unimplemented 1, class_unsupported 1 |
| FC | bhop_ananas | 858 | 5 | player_input 2, input_unimplemented 2, class_unsupported 1 |
| FC | bhop_angst | 1516 | 22 | player_input 9, input_unimplemented 7, class_unsupported 6 |
| FC | bhop_arcane_v2 | 1432 | 21 | volume_parented 8, input_unimplemented 5, player_input 4, class_unsupported 4 |
| FC | bhop_atmosphere | 458 | 3 | class_unsupported 2, player_input 1 |
| FC | bhop_aztec | 226 | 0 |  |
| FC | bhop_badges | 1224 | 6 | class_unsupported 4, player_input 2 |
| FC | bhop_badges2 | 1944 | 13 | class_unsupported 5, player_input 4, input_unimplemented 4 |
| FC | bhop_badges_mini | 1148 | 4 | player_input 2, class_unsupported 2 |
| FC | bhop_crash_egypt | 1284 | 14 | volume_key_unread 26, input_unimplemented 6, class_unsupported 5, player_input 2 |
| FC | bhop_depot | 1264 | 6 | input_unimplemented 3, player_input 2, class_unsupported 1 |
| FC | bhop_eazy | 323 | 0 |  |
| FC | bhop_eazy_v2 | 524 | 1 | class_unsupported 1 |
| FC | bhop_elate | 459 | 1 | volume_key_unread 30 |
| FC | bhop_epiphany | 1401 | 4 | player_input 3, class_unsupported 1 |
| FC | bhop_exanimo | 1301 | 2 | player_input 1, class_unsupported 1 |
| FC | bhop_exodus | 1191 | 14 | input_unimplemented 9, class_unsupported 3, player_input 2 |
| FC | bhop_forgotten | 1178 | 4 | player_input 3, class_unsupported 1 |
| FC | bhop_freakin | 1141 | 5 | player_input 2, input_unimplemented 2, class_unsupported 1 |
| FC | bhop_frotinity2 | 965 | 2 | player_input 2 |
| FC | bhop_fur | 423 | 0 |  |
| FC | bhop_fury | 1155 | 4 | player_input 2, input_unimplemented 1, class_unsupported 1 |
| FC | bhop_fury_2 | 1453 | 3 | player_input 2, class_unsupported 1 |
| FC | bhop_grove | 138 | 1 | player_input 1 |
| FC | bhop_hellish_dream_css | 523 | 4 | player_input 2, input_unimplemented 1, class_unsupported 1 |
| FC | bhop_interloper | 1144 | 5 | player_input 4, class_unsupported 1 |
| FC | bhop_japan | 540 | 8 | player_input 5, class_unsupported 2, input_unimplemented 1 |
| FC | bhop_lego2 | 1103 | 17 | class_unsupported 8, player_input 5, input_unimplemented 4 |
| FC | bhop_lego3 | 507 | 10 | player_input 5, class_unsupported 3, input_unimplemented 2 |
| FC | bhop_mario_fxd | 850 | 1 | player_input 1 |
| FC | bhop_monster_jam | 805 | 3 | class_unsupported 2, player_input 1 |
| FC | bhop_nature | 1101 | 7 | player_input 3, input_unimplemented 2, class_unsupported 2 |
| FC | bhop_null_fix | 1134 | 23 | player_input 9, input_unimplemented 7, class_unsupported 7 |
| FC | bhop_ocean | 199 | 2 | player_input 1, class_unsupported 1 |
| FC | bhop_overthinker | 794 | 5 | player_input 5 |
| FC | bhop_pandora2_fix | 1803 | 5 | player_input 4, class_unsupported 1 |
| FC | bhop_pharma | 1986 | 9 | player_input 3, input_unimplemented 3, class_unsupported 3 |
| FC | bhop_pit | 254 | 3 | player_input 2, input_unimplemented 1 |
| FC | bhop_sqee | 1322 | 2 | player_input 2 |
| FC | bhop_strength_v2 | 1574 | 8 | player_input 3, class_unsupported 3, input_unimplemented 2 |
| FC | bhop_supernova | 525 | 2 | player_input 2 |
| FC | bhop_tesquo_v2 | 909 | 7 | player_input 4, input_unimplemented 2, class_unsupported 1 |
| FC | bhop_toroux | 686 | 0 |  |
| FC | bhop_training_fun | 118 | 4 | class_unsupported 3, input_unimplemented 1 |
| FC | bhop_tranquility | 1421 | 2 | player_input 2 |
| FC | bhop_underground_crypt | 1851 | 5 | player_input 2, input_unimplemented 2, class_unsupported 1 |
| FC | blackhawkdown | 260 | 3 | class_unsupported 3 |
| FC | bunnyhop_pro | 22 | 1 | class_unsupported 1 |
| FC | buses_from_hell_fixed | 175 | 6 | input_unimplemented 3, volume_parented 2, class_unsupported 1 |
| FC | cp-orange-x3 | 197 | 8 | volume_unrecorded 4, class_unsupported 4 |
| FC | cp_5gorge | 859 | 17 | filter_class_unsupported 6, volume_unrecorded 5, class_unsupported 5, class_unknown 4 |
| FC | cp_altitude | 1027 | 34 | input_unimplemented 13, filter_class_unsupported 11, volume_unrecorded 9, class_unknown 6 |
| FC | cp_ambush_event | 1697 | 48 | filter_class_unsupported 30, volume_unrecorded 13, class_unknown 13, input_unimplemented 12 |
| FC | cp_badlands | 674 | 25 | input_unimplemented 8, filter_class_unsupported 8, class_unknown 7, class_unsupported 5 |
| FC | cp_brew | 1003 | 24 | input_unimplemented 9, filter_class_unsupported 9, class_unsupported 5, class_unknown 5 |
| FC | cp_burghausen | 903 | 28 | volume_unrecorded 10, input_unimplemented 7, class_unknown 6, class_unsupported 5 |
| FC | cp_canaveral_5cp | 747 | 32 | input_unimplemented 12, filter_class_unsupported 12, volume_unrecorded 7, class_unknown 6 |
| FC | cp_cargo | 518 | 24 | input_unimplemented 8, filter_class_unsupported 7, volume_unrecorded 5, class_unsupported 5 |
| FC | cp_carrier | 809 | 31 | input_unimplemented 12, class_unknown 7, class_unsupported 6, volume_unrecorded 5 |
| FC | cp_cloak | 64 | 5 | class_unsupported 2, class_unknown 2, input_unimplemented 1 |
| FC | cp_coldfront | 1277 | 23 | filter_class_unsupported 8, input_unimplemented 6, volume_unrecorded 6, class_unknown 6 |
| FC | cp_conifer | 675 | 24 | input_unimplemented 6, filter_class_unsupported 6, volume_unrecorded 5, class_unsupported 5 |
| FC | cp_cowerhouse | 2247 | 39 | input_unimplemented 20, class_unknown 10, class_unsupported 6, filter_class_unsupported 4 |
| FC | cp_darkmarsh | 2339 | 39 | input_unimplemented 13, volume_unrecorded 10, class_unknown 8, filter_class_unsupported 7 |
| FC | cp_degrootkeep | 211 | 19 | input_unimplemented 6, class_unsupported 6, class_unknown 5, volume_unrecorded 2 |
| FC | cp_degrootkeep_rats | 557 | 31 | filter_class_unsupported 12, class_unsupported 10, input_unimplemented 7, class_unknown 6 |
| FC | cp_dustbowl | 1070 | 24 | filter_class_unsupported 26, volume_unrecorded 7, class_unknown 6, input_unimplemented 5 |
| FC | cp_egypt_final | 1336 | 17 | volume_unrecorded 5, class_unknown 5, class_unsupported 4, input_unimplemented 3 |
| FC | cp_fastlane | 554 | 18 | filter_class_unsupported 8, class_unknown 5, input_unimplemented 4, volume_unrecorded 4 |
| FC | cp_fortezza | 768 | 23 | input_unimplemented 8, class_unknown 8, filter_class_unsupported 4, volume_unrecorded 3 |
| FC | cp_foundry | 1347 | 25 | input_unimplemented 9, filter_class_unsupported 8, class_unknown 6, class_unsupported 5 |
| FC | cp_freaky_fair | 757 | 25 | input_unimplemented 10, filter_class_unsupported 8, class_unknown 7, class_unsupported 5 |
| FC | cp_freight_final1 | 1145 | 22 | volume_unrecorded 8, filter_class_unsupported 8, class_unsupported 5, class_unknown 5 |
| FC | cp_frostwatch | 1320 | 29 | filter_class_unsupported 14, volume_unrecorded 11, input_unimplemented 6, class_unknown 6 |
| FC | cp_fulgur | 1228 | 31 | input_unimplemented 11, volume_unrecorded 8, filter_class_unsupported 7, class_unknown 6 |
| FC | cp_gorge | 534 | 18 | class_unsupported 6, class_unknown 5, input_unimplemented 3, volume_unrecorded 3 |
| FC | cp_gorge_event | 857 | 23 | class_unsupported 7, input_unimplemented 5, class_unknown 5, volume_unrecorded 3 |
| FC | cp_granary | 783 | 27 | input_unimplemented 8, filter_class_unsupported 8, class_unknown 8, class_unsupported 6 |
| FC | cp_gravelpit | 589 | 17 | class_unknown 6, input_unimplemented 4, class_unsupported 4, filter_class_unsupported 3 |
| FC | cp_gravelpit_snowy | 1577 | 26 | input_unimplemented 9, class_unknown 8, class_unsupported 6, filter_class_unsupported 3 |
| FC | cp_gullywash_final1 | 885 | 25 | input_unimplemented 8, filter_class_unsupported 8, class_unknown 7, class_unsupported 5 |
| FC | cp_hadal | 1188 | 25 | input_unimplemented 11, filter_class_unsupported 7, class_unsupported 6, class_unknown 5 |
| FC | cp_hardwood_final | 1084 | 30 | input_unimplemented 11, volume_unrecorded 6, filter_class_unsupported 6, class_unsupported 6 |
| FC | cp_holyhell | 6781 | 32 | filter_class_unsupported 12, input_unimplemented 9, volume_unrecorded 8, class_unknown 6 |
| FC | cp_junction_final | 899 | 14 | filter_class_unsupported 4, class_unknown 4, input_unimplemented 3, volume_unrecorded 3 |
| FC | cp_lavapit_final | 1115 | 29 | filter_class_unsupported 24, input_unimplemented 10, class_unsupported 8, class_unknown 7 |
| FC | cp_manor_event | 871 | 13 | class_unknown 4, volume_unrecorded 3, filter_class_unsupported 3, class_unsupported 3 |
| FC | cp_mercenarypark | 1191 | 46 | input_unimplemented 15, class_unknown 13, class_unsupported 11, filter_class_unsupported 9 |
| FC | cp_metalworks | 930 | 20 | filter_class_unsupported 8, input_unimplemented 7, class_unsupported 5, class_unknown 5 |
| FC | cp_mojave | 811 | 25 | input_unimplemented 12, class_unknown 6, volume_unrecorded 3, filter_class_unsupported 3 |
| FC | cp_mossrock | 718 | 23 | input_unimplemented 6, class_unsupported 6, volume_unrecorded 5, filter_class_unsupported 5 |
| FC | cp_mountainlab | 804 | 13 | class_unknown 4, volume_unrecorded 3, filter_class_unsupported 3, class_unsupported 3 |
| FC | cp_overgrown | 1155 | 29 | input_unimplemented 12, class_unsupported 6, volume_unrecorded 5, class_unknown 5 |
| FC | cp_powerhouse | 946 | 22 | class_unknown 8, input_unimplemented 6, class_unsupported 5, filter_class_unsupported 4 |
| FC | cp_premuda | 1511 | 38 | input_unimplemented 16, filter_class_unsupported 9, class_unsupported 8, class_unknown 7 |
| FC | cp_process_final | 998 | 22 | filter_class_unsupported 8, input_unimplemented 7, class_unsupported 5, class_unknown 5 |
| FC | cp_reckoner | 1010 | 19 | filter_class_unsupported 8, input_unimplemented 6, volume_unrecorded 4, class_unsupported 4 |
| FC | cp_snakewater_final1 | 986 | 27 | filter_class_unsupported 32, input_unimplemented 8, volume_unrecorded 7, class_unknown 6 |
| FC | cp_snowplow | 2106 | 48 | input_unimplemented 20, filter_class_unsupported 14, volume_unrecorded 10, class_unsupported 8 |
| FC | cp_spookeyridge | 1816 | 37 | filter_class_unsupported 36, input_unimplemented 12, class_unsupported 10, class_unknown 7 |
| FC | cp_standin_final | 779 | 20 | filter_class_unsupported 8, input_unimplemented 7, volume_unrecorded 4, class_unknown 4 |
| FC | cp_steel | 1208 | 33 | filter_class_unsupported 14, input_unimplemented 12, volume_unrecorded 8, class_unknown 6 |
| FC | cp_sulfur | 1180 | 34 | input_unimplemented 11, volume_unrecorded 9, filter_class_unsupported 9, class_unsupported 7 |
| FC | cp_sunshine | 988 | 23 | input_unimplemented 8, filter_class_unsupported 8, class_unsupported 5, class_unknown 5 |
| FC | cp_sunshine_event | 1121 | 19 | filter_class_unsupported 8, input_unimplemented 6, volume_unrecorded 4, class_unsupported 4 |
| FC | cp_vanguard | 1097 | 24 | filter_class_unsupported 10, input_unimplemented 7, class_unknown 6, class_unsupported 6 |
| FC | cp_well | 1431 | 23 | class_unknown 7, filter_class_unsupported 6, class_unsupported 6, input_unimplemented 4 |
| FC | cp_wildcat_event | 954 | 28 | input_unimplemented 8, class_unsupported 7, class_unknown 7, volume_unrecorded 5 |
| FC | cp_yukon_final | 674 | 19 | filter_class_unsupported 8, input_unimplemented 6, class_unknown 5, class_unsupported 5 |
| FC | cppl_gavle | 2197 | 49 | filter_class_unsupported 26, input_unimplemented 18, volume_unrecorded 10, class_unsupported 10 |
| FC | cs_assault | 891 | 5 | class_unsupported 4, input_unimplemented 1 |
| FC | cs_compound | 346 | 6 | class_unsupported 4, input_unimplemented 2 |
| FC | cs_crackhouse | 296 | 2 | class_unsupported 2 |
| FC | cs_havana | 754 | 3 | class_unsupported 2, input_unimplemented 1 |
| FC | cs_italy | 635 | 2 | class_unsupported 2 |
| FC | cs_militia | 599 | 3 | class_unsupported 3 |
| FC | cs_office | 821 | 6 | input_unimplemented 3, class_unsupported 3 |
| FC | ctf_2fort | 1097 | 15 | filter_class_unsupported 10, volume_unrecorded 8, class_unknown 3, class_unsupported 2 |
| FC | ctf_2fort_invasion | 1381 | 16 | filter_class_unsupported 10, volume_unrecorded 8, class_unknown 4, class_unsupported 2 |
| FC | ctf_applejack | 740 | 13 | filter_class_unsupported 6, input_unimplemented 4, class_unsupported 3, class_unknown 3 |
| FC | ctf_crasher | 2017 | 47 | input_unimplemented 19, class_unsupported 13, filter_class_unsupported 10, class_unknown 8 |
| FC | ctf_doublecross | 1003 | 15 | input_unimplemented 4, filter_class_unsupported 4, class_unsupported 4, class_unknown 4 |
| FC | ctf_doublecross_event | 1292 | 20 | class_unsupported 6, input_unimplemented 5, class_unknown 5, filter_class_unsupported 4 |
| FC | ctf_doublecross_snowy | 1171 | 9 | filter_class_unsupported 4, class_unsupported 3, volume_unrecorded 2, class_unknown 2 |
| FC | ctf_foundry | 1246 | 19 | filter_class_unsupported 8, class_unsupported 5, class_unknown 5, input_unimplemented 4 |
| FC | ctf_frosty | 1131 | 15 | filter_class_unsupported 6, volume_unrecorded 4, class_unknown 4, input_unimplemented 3 |
| FC | ctf_gorge | 617 | 17 | class_unsupported 5, class_unknown 5, input_unimplemented 4, filter_class_unsupported 4 |
| FC | ctf_haarp | 1336 | 43 | input_unimplemented 16, filter_class_unsupported 15, class_unknown 9, volume_unrecorded 8 |
| FC | ctf_hellfire | 789 | 18 | filter_class_unsupported 10, class_unsupported 6, class_unknown 5, input_unimplemented 4 |
| FC | ctf_helltrain_event | 2232 | 52 | input_unimplemented 16, class_unsupported 15, player_input 8, class_unknown 8 |
| FC | ctf_landfall | 662 | 13 | volume_unrecorded 4, filter_class_unsupported 4, input_unimplemented 3, class_unknown 3 |
| FC | ctf_medi_evil | 649 | 23 | input_unimplemented 11, class_unsupported 5, class_unknown 5, volume_unrecorded 2 |
| FC | ctf_pelican_peak | 987 | 22 | input_unimplemented 7, class_unsupported 5, volume_unrecorded 4, filter_class_unsupported 4 |
| FC | ctf_penguin_peak | 1029 | 24 | input_unimplemented 7, class_unsupported 6, volume_unrecorded 4, filter_class_unsupported 4 |
| FC | ctf_pressure | 932 | 27 | filter_class_unsupported 9, class_unsupported 8, input_unimplemented 6, volume_unrecorded 6 |
| FC | ctf_sawmill | 416 | 9 | class_unknown 4, volume_unrecorded 2, class_unsupported 2, input_unimplemented 1 |
| FC | ctf_sidewinder | 1138 | 20 | input_unimplemented 5, class_unsupported 5, volume_unrecorded 4, filter_class_unsupported 4 |
| FC | ctf_snowfall_final | 1209 | 9 | volume_unrecorded 4, filter_class_unsupported 4, class_unsupported 2, class_unknown 2 |
| FC | ctf_thundermountain | 722 | 18 | filter_class_unsupported 6, class_unsupported 6, class_unknown 5, input_unimplemented 4 |
| FC | ctf_turbine | 494 | 15 | volume_unrecorded 4, filter_class_unsupported 4, class_unknown 4, input_unimplemented 3 |
| FC | ctf_turbine_winter | 1471 | 20 | filter_class_unsupported 6, class_unsupported 5, volume_unrecorded 4, input_unimplemented 3 |
| FC | ctf_well | 1031 | 12 | volume_unrecorded 4, filter_class_unsupported 4, class_unsupported 3, class_unknown 3 |
| FC | de_aztec | 234 | 3 | class_unsupported 3 |
| FC | de_cbble | 388 | 3 | class_unsupported 3 |
| FC | de_chateau | 517 | 4 | class_unsupported 4 |
| FC | de_dust | 552 | 4 | class_unsupported 4 |
| FC | de_dust2 | 393 | 4 | class_unsupported 4 |
| FC | de_inferno | 680 | 5 | class_unsupported 4, input_unimplemented 1 |
| FC | de_nuke | 898 | 4 | class_unsupported 4 |
| FC | de_piranesi | 437 | 2 | class_unsupported 2 |
| FC | de_port | 537 | 2 | class_unsupported 2 |
| FC | de_prodigy | 849 | 4 | class_unsupported 4 |
| FC | de_tides | 421 | 4 | class_unsupported 4 |
| FC | de_train | 800 | 6 | class_unsupported 5, input_unimplemented 1 |
| FC | deathrun_aztecan_finalb3 | 313 | 4 | class_unsupported 3, input_unimplemented 1 |
| FC | deathrun_family_guy_final2 | 550 | 28 | volume_parented 9, class_unsupported 7, input_unimplemented 6, player_input 5 |
| FC | deathrun_hadicap_v6 | 72 | 0 |  |
| FC | deathrun_helix_b8-1 | 1076 | 29 | input_unimplemented 11, class_unsupported 11, player_input 5, volume_parented 2 |
| FC | deathrun_iceworld_v2fix | 1066 | 11 | input_unimplemented 5, class_unsupported 4, player_input 1, volume_parented 1 |
| FC | deathrun_internet | 240 | 2 | input_unimplemented 1, class_unsupported 1 |
| FC | deathrun_parking_garage | 494 | 11 | class_unsupported 6, input_unimplemented 5 |
| FC | deathrun_tp_percolate_oreo | 297 | 8 | input_unimplemented 4, class_unsupported 2, player_input 1, volume_parented 1 |
| FC | dm-hot-cn-v1 | 707 | 0 |  |
| FC | dm-industrial-gamma | 716 | 2 | class_unsupported 2 |
| FC | dm-morpheus | 369 | 0 |  |
| FC | dm-overwatch | 331 | 2 | class_unsupported 2 |
| FC | dm-scarletdevilmansion | 990 | 9 | volume_parented 6, class_unsupported 3 |
| FC | dm_lockdown | 648 | 8 | class_unsupported 5, class_unknown 2, input_unimplemented 1 |
| FC | dm_overwatch | 364 | 3 | class_unsupported 2, input_unimplemented 1 |
| FC | dm_powerhouse | 1400 | 3 | class_unknown 2, input_unimplemented 1 |
| FC | dm_resistance | 630 | 1 | input_unimplemented 1 |
| FC | dm_runoff | 608 | 4 | input_unimplemented 2, class_unsupported 2 |
| FC | dm_steamlab | 1090 | 4 | input_unimplemented 2, class_unsupported 2 |
| FC | dm_underpass | 878 | 2 | input_unimplemented 1, class_unsupported 1 |
| FC | dod_anzio | 834 | 1 | class_unsupported 1 |
| FC | dod_argentan | 599 | 2 | class_unsupported 2 |
| FC | dod_avalanche | 592 | 2 | input_unimplemented 1, class_unsupported 1 |
| FC | dod_colmar | 777 | 9 | input_unimplemented 5, class_unknown 2, class_unsupported 2 |
| FC | dod_donner | 653 | 1 | class_unsupported 1 |
| FC | dod_flash | 566 | 2 | input_unimplemented 1, class_unsupported 1 |
| FC | dod_jagd | 613 | 9 | input_unimplemented 5, class_unknown 3, class_unsupported 1 |
| FC | dod_kalt | 917 | 4 | input_unimplemented 2, class_unsupported 2 |
| FC | dod_palermo | 739 | 2 | class_unsupported 2 |
| FC | dr_death_v1 | 130 | 6 | volume_key_unread 7, input_unimplemented 3 |
| FC | dr_horrorhousecompleted | 1018 | 13 | input_unimplemented 6, class_unsupported 5, volume_parented 2 |
| FC | gg-canyon | 110 | 1 | class_unsupported 1 |
| FC | gg-fy-snow | 55 | 0 |  |
| FC | gg-garage | 349 | 0 |  |
| FC | gg-krusty-krab | 113 | 1 | class_unsupported 1 |
| FC | gg-lego-arena | 36 | 1 | class_unsupported 1 |
| FC | gg-punishment | 244 | 2 | class_unsupported 2 |
| FC | gg-simpsons-x | 170 | 1 | class_unsupported 1 |
| FC | gg-woods | 95 | 3 | class_unsupported 3 |
| FC | gm_apresort | 1027 | 5 | class_unsupported 3, input_unimplemented 2 |
| FC | gm_ashpit | 1512 | 18 | input_unimplemented 7, class_unsupported 6, player_input 4, class_unknown 1 |
| FC | gm_ashpit | 1512 | 18 | input_unimplemented 7, class_unsupported 6, player_input 4, class_unknown 1 |
| FC | gm_balkans | 2707 | 26 | class_unsupported 15, input_unimplemented 10, player_input 1 |
| FC | gm_balkans | 2707 | 26 | class_unsupported 15, input_unimplemented 10, player_input 1 |
| FC | gm_bigisland | 160 | 0 |  |
| FC | gm_bigisland | 160 | 0 |  |
| FC | gm_blackbrook_asylum | 932 | 2 | class_unsupported 2 |
| FC | gm_blackbrook_asylum | 932 | 2 | class_unsupported 2 |
| FC | gm_boreas | 8479 | 16 | input_unimplemented 9, class_unsupported 6, player_input 1 |
| FC | gm_boreas | 8479 | 16 | input_unimplemented 9, class_unsupported 6, player_input 1 |
| FC | gm_boreas | 8479 | 16 | input_unimplemented 9, class_unsupported 6, player_input 1 |
| FC | gm_construct | 1227 | 5 | input_unimplemented 2, player_input 1, class_unknown 1, class_unsupported 1 |
| FC | gm_deco_mansion | 2878 | 2 | input_unimplemented 1, class_unsupported 1 |
| FC | gm_flatgrass | 217 | 1 | input_unimplemented 1 |
| FC | gm_forgotten_asylum | 1217 | 11 | input_unimplemented 7, class_unsupported 4 |
| FC | gm_forgotten_asylum | 1217 | 11 | input_unimplemented 7, class_unsupported 4 |
| FC | gm_fork | 731 | 2 | input_unimplemented 1, class_unsupported 1 |
| FC | gm_fork | 731 | 2 | input_unimplemented 1, class_unsupported 1 |
| FC | gm_funkis_night | 1224 | 7 | input_unimplemented 6, class_unsupported 1 |
| FC | gm_mallparking | 1780 | 1 | class_unsupported 1 |
| FC | gm_mallparking | 1780 | 1 | class_unsupported 1 |
| FC | gm_mountainresort | 1212 | 12 | input_unimplemented 7, volume_key_unread 5, class_unsupported 1 |
| FC | gm_scarface | 2172 | 6 | class_unsupported 3, input_unimplemented 2, player_input 1 |
| FC | gm_shambles | 2677 | 1 | volume_key_unread 3 |
| FC | gm_shambles | 2677 | 1 | volume_key_unread 3 |
| FC | gm_valley | 2372 | 0 |  |
| FC | gm_valley | 2372 | 0 |  |
| FC | gm_villa | 2172 | 6 | class_unsupported 3, input_unimplemented 2, player_input 1 |
| FC | gm_vyten | 3266 | 3 | input_unimplemented 2, player_input 1 |
| FC | gm_vyten | 3266 | 3 | input_unimplemented 2, player_input 1 |
| FC | gm_york | 743 | 0 |  |
| FC | gm_york_remaster | 3361 | 1 | input_unimplemented 1 |
| FC | halls3 | 337 | 2 | input_unimplemented 1, class_unsupported 1 |
| FC | htf_marshlands | 836 | 27 | input_unimplemented 11, class_unknown 7, filter_class_unsupported 6, volume_unrecorded 4 |
| FC | itemtest | 98 | 6 | class_unsupported 3, volume_unrecorded 2, class_unknown 1 |
| FC | koth_badlands | 309 | 15 | input_unimplemented 5, filter_class_unsupported 4, class_unknown 4, class_unsupported 3 |
| FC | koth_bagel_event | 1437 | 31 | input_unimplemented 14, filter_class_unsupported 8, class_unsupported 8, class_unknown 5 |
| FC | koth_blowout | 529 | 21 | input_unimplemented 6, volume_unrecorded 6, filter_class_unsupported 6, class_unsupported 5 |
| FC | koth_boardwalk | 1297 | 19 | input_unimplemented 7, filter_class_unsupported 6, class_unsupported 5, class_unknown 3 |
| FC | koth_brazil | 729 | 17 | input_unimplemented 6, filter_class_unsupported 6, volume_unrecorded 4, class_unsupported 3 |
| FC | koth_cachoeira | 895 | 17 | input_unimplemented 6, volume_unrecorded 4, filter_class_unsupported 4, class_unknown 3 |
| FC | koth_camp_saxton | 823 | 19 | input_unimplemented 7, volume_unrecorded 4, filter_class_unsupported 4, class_unsupported 4 |
| FC | koth_cascade | 1178 | 18 | input_unimplemented 7, volume_unrecorded 4, filter_class_unsupported 4, class_unknown 3 |
| FC | koth_demolition | 1235 | 20 | filter_class_unsupported 12, input_unimplemented 9, class_unsupported 5, class_unknown 3 |
| FC | koth_dryfield | 776 | 15 | input_unimplemented 6, filter_class_unsupported 6, class_unsupported 3, class_unknown 3 |
| FC | koth_dusker | 937 | 23 | input_unimplemented 10, filter_class_unsupported 6, volume_unrecorded 4, class_unsupported 4 |
| FC | koth_harvest_event | 784 | 17 | input_unimplemented 6, class_unsupported 5, filter_class_unsupported 4, class_unknown 3 |
| FC | koth_harvest_final | 417 | 15 | input_unimplemented 6, filter_class_unsupported 4, class_unsupported 3, class_unknown 3 |
| FC | koth_highpass | 623 | 15 | input_unimplemented 6, filter_class_unsupported 4, class_unknown 3, class_unsupported 3 |
| FC | koth_king | 1169 | 15 | input_unimplemented 6, filter_class_unsupported 6, class_unknown 3, class_unsupported 3 |
| FC | koth_krampus | 971 | 21 | filter_class_unsupported 8, input_unimplemented 6, class_unsupported 6, volume_unrecorded 4 |
| FC | koth_lakeside_event | 964 | 27 | input_unimplemented 7, class_unsupported 7, filter_class_unsupported 6, player_input 4 |
| FC | koth_lakeside_final | 454 | 17 | input_unimplemented 8, class_unknown 4, class_unsupported 3, volume_unrecorded 2 |
| FC | koth_lazarus | 1537 | 20 | input_unimplemented 7, class_unsupported 5, volume_unrecorded 4, filter_class_unsupported 4 |
| FC | koth_los_muertos | 2344 | 33 | filter_class_unsupported 12, input_unimplemented 9, class_unsupported 7, volume_unrecorded 6 |
| FC | koth_mannhole | 1388 | 19 | input_unimplemented 6, class_unsupported 5, volume_unrecorded 4, filter_class_unsupported 4 |
| FC | koth_maple_ridge_event | 682 | 17 | input_unimplemented 6, volume_unrecorded 4, filter_class_unsupported 4, class_unknown 3 |
| FC | koth_megalo | 998 | 21 | class_unsupported 7, input_unimplemented 6, volume_unrecorded 4, filter_class_unsupported 4 |
| FC | koth_megaton | 789 | 29 | input_unimplemented 11, class_unsupported 9, filter_class_unsupported 6, volume_unrecorded 4 |
| FC | koth_moonshine_event | 1004 | 25 | filter_class_unsupported 12, input_unimplemented 9, class_unsupported 8, class_unknown 5 |
| FC | koth_nucleus | 584 | 17 | input_unimplemented 6, filter_class_unsupported 6, class_unsupported 5, class_unknown 3 |
| FC | koth_overcast_final | 1358 | 19 | input_unimplemented 9, filter_class_unsupported 4, class_unsupported 4, class_unknown 3 |
| FC | koth_probed | 1261 | 29 | filter_class_unsupported 47, input_unimplemented 11, class_unsupported 8, volume_unrecorded 5 |
| FC | koth_rotunda | 968 | 18 | input_unimplemented 6, filter_class_unsupported 4, class_unsupported 4, class_unknown 3 |
| FC | koth_sawmill | 323 | 10 | class_unsupported 4, class_unknown 3, volume_unrecorded 2, input_unimplemented 1 |
| FC | koth_sawmill_event | 1258 | 22 | class_unsupported 8, input_unimplemented 5, class_unknown 5, filter_class_unsupported 4 |
| FC | koth_sharkbay | 639 | 18 | input_unimplemented 7, filter_class_unsupported 6, class_unsupported 4, class_unknown 4 |
| FC | koth_shorelight | 691 | 19 | input_unimplemented 7, filter_class_unsupported 6, volume_unrecorded 4, class_unsupported 4 |
| FC | koth_slasher | 1814 | 34 | input_unimplemented 10, class_unsupported 8, class_unknown 7, filter_class_unsupported 6 |
| FC | koth_slaughter_event | 1945 | 21 | filter_class_unsupported 12, class_unsupported 7, input_unimplemented 6, class_unknown 4 |
| FC | koth_slime | 1553 | 24 | filter_class_unsupported 12, input_unimplemented 8, class_unknown 6, class_unsupported 5 |
| FC | koth_snowtower | 768 | 17 | filter_class_unsupported 8, input_unimplemented 6, volume_unrecorded 4, class_unknown 3 |
| FC | koth_suijin | 472 | 20 | input_unimplemented 6, filter_class_unsupported 6, volume_unrecorded 4, class_unsupported 4 |
| FC | koth_synthetic_event | 1364 | 32 | input_unimplemented 12, filter_class_unsupported 8, class_unsupported 6, class_unknown 6 |
| FC | koth_toxic | 2627 | 25 | filter_class_unsupported 14, input_unimplemented 10, class_unsupported 5, player_input 4 |
| FC | koth_trainsawlaser | 1440 | 33 | input_unimplemented 12, class_unsupported 8, player_input 4, volume_unrecorded 4 |
| FC | koth_undergrove_event | 1632 | 33 | filter_class_unsupported 12, input_unimplemented 10, class_unsupported 7, player_input 6 |
| FC | koth_viaduct | 341 | 19 | input_unimplemented 8, filter_class_unsupported 4, class_unsupported 4, class_unknown 4 |
| FC | koth_viaduct_event | 901 | 22 | filter_class_unsupported 8, input_unimplemented 6, class_unsupported 6, player_input 4 |
| FC | koth_winter_ridge | 546 | 18 | input_unimplemented 6, filter_class_unsupported 6, volume_unrecorded 4, class_unsupported 3 |
| FC | kz_bhop_badg3s | 2142 | 6 | player_input 3, class_unsupported 2, input_unimplemented 1 |
| FC | kz_bhop_lucid | 1318 | 4 | player_input 2, input_unimplemented 1, class_unsupported 1 |
| FC | kz_bhop_yonkoma | 1517 | 28 | class_unsupported 13, input_unimplemented 9, player_input 5, volume_parented 1 |
| FC | mg_LEGO_course | 246 | 3 | class_unsupported 2, input_unimplemented 1 |
| FC | mg_dans_course | 349 | 3 | class_unsupported 3 |
| FC | mg_dc_course_fixed | 705 | 6 | class_unsupported 3, input_unimplemented 2, player_input 1 |
| FC | mg_labo_course_fix | 477 | 4 | player_input 1, input_unimplemented 1, volume_parented 1, class_unsupported 1 |
| FC | mg_oaks_course | 561 | 16 | volume_parented 12, input_unimplemented 2, class_unsupported 2 |
| FC | mg_office_coursee | 766 | 16 | class_unsupported 7, input_unimplemented 6, player_input 3 |
| FC | mg_pauls_minecraft_course_v2 | 553 | 8 | player_input 3, input_unimplemented 3, class_unsupported 2 |
| FC | mg_scary_course_v2 | 952 | 6 | input_unimplemented 4, class_unsupported 2 |
| FC | mg_sweet_course_rework | 509 | 9 | class_unsupported 6, input_unimplemented 3 |
| FC | mg_waytobar_course_2012 | 630 | 2 | class_unsupported 2 |
| FC | mu_factory_winter | 2027 | 7 | input_unimplemented 4, class_unsupported 3 |
| FC | mu_greenwood | 188 | 0 |  |
| FC | mu_hotel | 376 | 0 |  |
| FC | mu_office | 244 | 0 |  |
| FC | mu_silence | 614 | 0 |  |
| FC | mvm_bigrock | 571 | 21 | class_unknown 10, class_unsupported 5, input_unimplemented 3, player_input 2 |
| FC | mvm_coaltown | 463 | 16 | class_unknown 9, filter_class_unsupported 4, class_unsupported 3, input_unimplemented 2 |
| FC | mvm_decoy | 376 | 16 | class_unknown 9, filter_class_unsupported 5, class_unsupported 3, input_unimplemented 2 |
| FC | mvm_ghost_town | 572 | 17 | class_unknown 9, filter_class_unsupported 4, class_unsupported 4, input_unimplemented 2 |
| FC | mvm_mannhattan | 704 | 38 | filter_class_unsupported 17, input_unimplemented 12, class_unknown 12, class_unsupported 10 |
| FC | mvm_mannworks | 498 | 17 | class_unknown 7, class_unsupported 4, input_unimplemented 3, player_input 2 |
| FC | mvm_rottenburg | 648 | 24 | class_unknown 14, input_unimplemented 4, class_unsupported 4, player_input 2 |
| FC | pass_brickyard | 1220 | 37 | input_unimplemented 11, class_unsupported 10, volume_unrecorded 8, class_unknown 8 |
| FC | pass_district | 1935 | 32 | volume_unrecorded 10, class_unsupported 8, input_unimplemented 7, class_unknown 7 |
| FC | pass_timbertown | 1056 | 31 | volume_unrecorded 10, class_unsupported 8, class_unknown 7, input_unimplemented 6 |
| FC | pd_atom_smash | 1682 | 33 | input_unimplemented 15, filter_class_unsupported 8, class_unknown 7, volume_unrecorded 6 |
| FC | pd_circus | 1773 | 50 | filter_class_unsupported 16, input_unimplemented 13, class_unsupported 12, volume_unrecorded 10 |
| FC | pd_cursed_cove_event | 1573 | 28 | input_unimplemented 13, filter_class_unsupported 10, class_unknown 7, class_unsupported 5 |
| FC | pd_farmageddon | 1189 | 44 | input_unimplemented 19, filter_class_unsupported 14, class_unknown 9, class_unsupported 7 |
| FC | pd_galleria | 1090 | 31 | input_unimplemented 16, filter_class_unsupported 6, class_unknown 6, volume_unrecorded 4 |
| FC | pd_mannsylvania | 1932 | 37 | filter_class_unsupported 36, input_unimplemented 16, class_unknown 9, class_unsupported 5 |
| FC | pd_monster_bash | 1648 | 43 | input_unimplemented 16, filter_class_unsupported 10, class_unknown 8, volume_unrecorded 6 |
| FC | pd_nutcracker | 937 | 24 | input_unimplemented 10, class_unknown 7, filter_class_unsupported 4, class_unsupported 4 |
| FC | pd_pit_of_death_event | 1075 | 37 | input_unimplemented 12, filter_class_unsupported 11, class_unknown 8, class_unsupported 7 |
| FC | pd_selbyen | 740 | 26 | input_unimplemented 10, class_unknown 7, filter_class_unsupported 6, volume_unrecorded 4 |
| FC | pd_snowville_event | 783 | 17 | input_unimplemented 7, class_unknown 5, class_unsupported 3, volume_unrecorded 2 |
| FC | pd_watergate | 959 | 48 | input_unimplemented 20, filter_class_unsupported 10, class_unknown 9, class_unsupported 8 |
| FC | ph_WolfsManor | 346 | 0 |  |
| FC | ph_abandoned_church | 279 | 0 |  |
| FC | ph_abandoned_hotel | 787 | 0 |  |
| FC | ph_apartment | 304 | 0 |  |
| FC | ph_autumngetaway | 932 | 0 |  |
| FC | ph_bank | 840 | 0 |  |
| FC | ph_bikinibottom | 555 | 1 | input_unimplemented 1 |
| FC | ph_cyber_dinner | 1987 | 2 | input_unimplemented 1, class_unsupported 1 |
| FC | ph_elementary_school | 853 | 7 | input_unimplemented 4, class_unsupported 3 |
| FC | ph_frontyard | 375 | 0 |  |
| FC | ph_gas_station | 1079 | 0 |  |
| FC | ph_hotel | 611 | 5 | input_unimplemented 4, class_unsupported 1 |
| FC | ph_islandhouse_2014 | 524 | 0 |  |
| FC | ph_library_final | 593 | 0 |  |
| FC | ph_midwestapartment | 474 | 0 |  |
| FC | ph_oceanwaves | 461 | 1 | class_unsupported 1 |
| FC | ph_office221 | 359 | 1 | input_unimplemented 1 |
| FC | ph_restaurant_os | 1432 | 13 | input_unimplemented 8, class_unsupported 4, player_input 1 |
| FC | ph_swimmingpool | 1676 | 11 | input_unimplemented 6, class_unsupported 4, player_input 1 |
| FC | ph_volcano_v1 | 1111 | 0 |  |
| FC | ph_warehouse_v2 | 783 | 2 | class_unsupported 2 |
| FC | ph_warehouse_v2 | 783 | 2 | class_unsupported 2 |
| FC | ph_westerncity | 1070 | 1 | input_unimplemented 1 |
| FC | pl_aquarius | 1543 | 69 | input_unimplemented 34, class_unsupported 12, class_unknown 11, filter_class_unsupported 8 |
| FC | pl_aridpass_event | 1468 | 40 | input_unimplemented 15, class_unsupported 10, volume_unrecorded 7, class_unknown 6 |
| FC | pl_badwater | 999 | 46 | input_unimplemented 22, class_unsupported 10, class_unknown 8, filter_class_unsupported 5 |
| FC | pl_barnblitz | 1352 | 45 | input_unimplemented 21, filter_class_unsupported 16, class_unknown 8, class_unsupported 8 |
| FC | pl_bloodwater | 2220 | 58 | input_unimplemented 22, filter_class_unsupported 14, class_unsupported 13, class_unknown 11 |
| FC | pl_borneo | 1201 | 34 | input_unimplemented 13, class_unsupported 8, class_unknown 6, volume_unrecorded 5 |
| FC | pl_breadspace | 1644 | 51 | input_unimplemented 22, class_unknown 13, volume_unrecorded 7, filter_class_unsupported 7 |
| FC | pl_cactuscanyon | 929 | 48 | input_unimplemented 25, class_unknown 9, filter_class_unsupported 8, class_unsupported 8 |
| FC | pl_camber | 1041 | 33 | input_unimplemented 15, filter_class_unsupported 11, class_unsupported 8, class_unknown 5 |
| FC | pl_cashworks | 1524 | 45 | input_unimplemented 22, filter_class_unsupported 11, class_unsupported 9, volume_unrecorded 6 |
| FC | pl_chilly | 1244 | 50 | input_unimplemented 21, filter_class_unsupported 13, volume_unrecorded 10, class_unsupported 10 |
| FC | pl_citadel | 1597 | 62 | input_unimplemented 28, filter_class_unsupported 12, class_unsupported 12, class_unknown 10 |
| FC | pl_coal_event | 1386 | 49 | input_unimplemented 20, class_unsupported 11, volume_unrecorded 9, filter_class_unsupported 9 |
| FC | pl_corruption | 2219 | 57 | filter_class_unsupported 40, input_unimplemented 21, class_unsupported 15, volume_unrecorded 9 |
| FC | pl_embargo | 2036 | 78 | input_unimplemented 32, class_unsupported 16, class_unknown 10, filter_class_unsupported 8 |
| FC | pl_emerge | 1068 | 35 | input_unimplemented 13, class_unsupported 9, volume_unrecorded 7, filter_class_unsupported 7 |
| FC | pl_enclosure_final | 1713 | 54 | input_unimplemented 18, volume_unrecorded 17, class_unsupported 10, filter_class_unsupported 9 |
| FC | pl_fifthcurve_event | 1600 | 65 | filter_class_unsupported 28, input_unimplemented 24, class_unknown 15, volume_unrecorded 10 |
| FC | pl_frontier_final | 1117 | 50 | input_unimplemented 20, class_unsupported 9, filter_class_unsupported 8, class_unknown 7 |
| FC | pl_frostcliff | 1549 | 49 | input_unimplemented 18, volume_unrecorded 12, filter_class_unsupported 10, class_unsupported 10 |
| FC | pl_goldrush | 1416 | 49 | filter_class_unsupported 35, input_unimplemented 24, class_unsupported 10, class_unknown 7 |
| FC | pl_hasslecastle | 1564 | 48 | input_unimplemented 22, class_unsupported 9, class_unknown 9, filter_class_unsupported 7 |
| FC | pl_hoodoo_final | 1456 | 45 | input_unimplemented 22, filter_class_unsupported 14, class_unknown 8, volume_unrecorded 7 |
| FC | pl_millstone_event | 1374 | 57 | input_unimplemented 20, filter_class_unsupported 17, class_unknown 13, class_unsupported 11 |
| FC | pl_odyssey | 1408 | 49 | input_unimplemented 19, filter_class_unsupported 15, volume_unrecorded 11, class_unsupported 11 |
| FC | pl_patagonia | 2644 | 92 | input_unimplemented 35, volume_unrecorded 21, filter_class_unsupported 21, class_unsupported 18 |
| FC | pl_phoenix | 1563 | 51 | input_unimplemented 23, class_unsupported 10, filter_class_unsupported 9, volume_unrecorded 8 |
| FC | pl_pier | 1681 | 50 | filter_class_unsupported 23, input_unimplemented 22, class_unknown 11, class_unsupported 10 |
| FC | pl_precipice_event_final | 1963 | 54 | input_unimplemented 21, class_unsupported 13, class_unknown 11, filter_class_unsupported 10 |
| FC | pl_redwood | 1431 | 44 | input_unimplemented 15, filter_class_unsupported 11, class_unsupported 11, volume_unrecorded 8 |
| FC | pl_rumble_event | 1620 | 72 | input_unimplemented 32, filter_class_unsupported 19, class_unknown 16, class_unsupported 12 |
| FC | pl_rumford_event | 1884 | 42 | input_unimplemented 16, class_unsupported 9, class_unknown 9, filter_class_unsupported 8 |
| FC | pl_sludgepit_event | 1699 | 46 | input_unimplemented 16, volume_unrecorded 10, class_unsupported 10, filter_class_unsupported 9 |
| FC | pl_snowycoast | 1489 | 40 | input_unimplemented 17, filter_class_unsupported 12, class_unsupported 8, volume_unrecorded 7 |
| FC | pl_spineyard | 2858 | 48 | filter_class_unsupported 17, input_unimplemented 16, class_unsupported 11, volume_unrecorded 10 |
| FC | pl_swiftwater_final1 | 1288 | 35 | input_unimplemented 16, filter_class_unsupported 10, class_unsupported 8, class_unknown 6 |
| FC | pl_terror_event | 1614 | 69 | filter_class_unsupported 33, input_unimplemented 32, class_unknown 14, volume_unrecorded 10 |
| FC | pl_thundermountain | 1909 | 65 | input_unimplemented 28, class_unsupported 17, filter_class_unsupported 13, class_unknown 11 |
| FC | pl_upward | 1004 | 44 | input_unimplemented 21, class_unsupported 8, filter_class_unsupported 7, class_unknown 7 |
| FC | pl_venice | 1445 | 44 | input_unimplemented 18, filter_class_unsupported 14, class_unsupported 9, volume_unrecorded 8 |
| FC | pl_wutville_event | 897 | 45 | input_unimplemented 17, filter_class_unsupported 8, class_unsupported 7, class_unknown 7 |
| FC | plr_bananabay | 880 | 27 | input_unimplemented 10, filter_class_unsupported 8, class_unsupported 6, class_unknown 6 |
| FC | plr_cutter | 1333 | 23 | filter_class_unsupported 8, input_unimplemented 7, class_unsupported 7, volume_unrecorded 4 |
| FC | plr_hacksaw | 1388 | 28 | input_unimplemented 10, filter_class_unsupported 10, class_unsupported 6, class_unknown 6 |
| FC | plr_hacksaw_event | 2054 | 50 | input_unimplemented 19, filter_class_unsupported 14, class_unsupported 12, class_unknown 9 |
| FC | plr_hightower | 1000 | 29 | input_unimplemented 11, filter_class_unsupported 8, class_unsupported 6, class_unknown 6 |
| FC | plr_hightower_event | 1651 | 45 | input_unimplemented 14, filter_class_unsupported 14, class_unknown 13, class_unsupported 9 |
| FC | plr_matterhorn | 1320 | 39 | input_unimplemented 15, class_unsupported 10, filter_class_unsupported 8, class_unknown 7 |
| FC | plr_nightfall_final | 1683 | 37 | class_unsupported 12, input_unimplemented 11, filter_class_unsupported 10, volume_unrecorded 6 |
| FC | plr_pipeline | 1572 | 45 | filter_class_unsupported 20, input_unimplemented 15, class_unsupported 11, class_unknown 9 |
| FC | rd_asteroid | 964 | 22 | class_unsupported 7, class_unknown 5, input_unimplemented 4, volume_unrecorded 4 |
| FC | rp_asheville | 7205 | 6 | class_unsupported 4, input_unimplemented 2 |
| FC | rp_asheville | 7205 | 6 | class_unsupported 4, input_unimplemented 2 |
| FC | rp_deadcity | 1351 | 2 | class_unsupported 2 |
| FC | rp_deadcity | 1351 | 2 | class_unsupported 2 |
| FC | rp_southside | 5122 | 19 | input_unimplemented 14, class_unsupported 4, player_input 1 |
| FC | rp_southside | 5122 | 19 | input_unimplemented 14, class_unsupported 4, player_input 1 |
| FC | rp_southside | 5122 | 19 | input_unimplemented 14, class_unsupported 4, player_input 1 |
| FC | sd_doomsday | 716 | 37 | input_unimplemented 18, filter_class_unsupported 10, class_unknown 9, class_unsupported 5 |
| FC | sd_doomsday_event | 1822 | 70 | input_unimplemented 36, class_unknown 17, class_unsupported 11, filter_class_unsupported 10 |
| FC | surf_10x_final | 238 | 1 | class_unsupported 1 |
| FC | surf_10x_reloaded_fixed | 324 | 1 | class_unsupported 1 |
| FC | surf_110b_austinpowers | 677 | 13 | volume_parented 9, input_unimplemented 2, class_unsupported 2 |
| FC | surf_29_12_06 | 203 | 2 | input_unimplemented 1, class_unsupported 1 |
| FC | surf_I_Hate_Campers | 243 | 4 | class_unsupported 4 |
| FC | surf_XIV_v2a | 1161 | 15 | class_unsupported 10, input_unimplemented 4, player_input 1 |
| FC | surf_adverse | 523 | 7 | class_unsupported 4, input_unimplemented 2, player_input 1 |
| FC | surf_aim_akcolt | 154 | 1 | input_unimplemented 1 |
| FC | surf_akai_final | 425 | 4 | input_unimplemented 2, class_unsupported 2 |
| FC | surf_animals | 1119 | 16 | input_unimplemented 9, class_unsupported 4, player_input 2, volume_parented 1 |
| FC | surf_aquaflow | 422 | 2 | player_input 1, input_unimplemented 1 |
| FC | surf_arcade | 1155 | 5 | player_input 2, class_unsupported 2, input_unimplemented 1 |
| FC | surf_bathroom_final | 434 | 9 | input_unimplemented 5, volume_key_unread 3, class_unsupported 1 |
| FC | surf_beginner | 173 | 2 | player_input 1, input_unimplemented 1 |
| FC | surf_beginner2 | 670 | 4 | player_input 3, class_unsupported 1 |
| FC | surf_buck_wild | 666 | 5 | class_unsupported 4, input_unimplemented 1 |
| FC | surf_dust2_2008_final | 167 | 7 | class_unsupported 4, input_unimplemented 3 |
| FC | surf_eclipse | 293 | 12 | input_unimplemented 6, class_unsupported 5, player_input 1 |
| FC | surf_ember | 567 | 2 | player_input 1, input_unimplemented 1 |
| FC | surf_fastspiral_retro | 182 | 2 | class_unsupported 2 |
| FC | surf_forbidden_ways_2nd | 350 | 5 | class_unsupported 4, input_unimplemented 1 |
| FC | surf_forbidden_ways_reloaded | 1221 | 3 | class_unsupported 3 |
| FC | surf_fruits | 1026 | 6 | class_unsupported 3, input_unimplemented 2, player_input 1 |
| FC | surf_grave_reloaded | 396 | 1 | class_unsupported 1 |
| FC | surf_greatriver | 217 | 0 |  |
| FC | surf_greatriver_v4 | 468 | 6 | class_unsupported 5, input_unimplemented 1 |
| FC | surf_greatriver_xdre4m | 452 | 13 | class_unsupported 9, input_unimplemented 4 |
| FC | surf_greensway | 197 | 1 | input_unimplemented 1 |
| FC | surf_interference | 732 | 2 | player_input 2 |
| FC | surf_japan_ptad | 531 | 11 | class_unsupported 7, input_unimplemented 3, player_input 1 |
| FC | surf_kitsune | 265 | 2 | player_input 2 |
| FC | surf_legends | 372 | 6 | input_unimplemented 3, class_unsupported 2, volume_key_unread 1 |
| FC | surf_life_of_duck | 153 | 1 | player_input 1 |
| FC | surf_lithium2 | 682 | 14 | input_unimplemented 5, class_unsupported 5, player_input 4 |
| FC | surf_lore | 691 | 12 | class_unsupported 7, input_unimplemented 4, player_input 1 |
| FC | surf_lt_omnific | 4949 | 24 | input_unimplemented 12, player_input 7, class_unsupported 5 |
| FC | surf_lt_unicorn | 1353 | 25 | input_unimplemented 12, class_unsupported 7, player_input 6 |
| FC | surf_machine2 | 331 | 4 | input_unimplemented 2, class_unsupported 2 |
| FC | surf_machine_remix_final | 475 | 4 | class_unsupported 3, input_unimplemented 1 |
| FC | surf_mai_redone_final2 | 655 | 13 | class_unsupported 8, input_unimplemented 3, player_input 1, volume_parented 1 |
| FC | surf_mai_remix | 258 | 3 | class_unsupported 2, input_unimplemented 1 |
| FC | surf_matrix_v8 | 936 | 4 | input_unimplemented 2, class_unsupported 2 |
| FC | surf_ny_advance | 665 | 8 | input_unimplemented 4, volume_parented 2, player_input 1, class_unsupported 1 |
| FC | surf_ny_bigloop_2008a | 228 | 0 |  |
| FC | surf_ny_exploder_prime | 280 | 1 | class_unsupported 1 |
| FC | surf_omnibus | 703 | 9 | input_unimplemented 4, class_unsupported 3, player_input 2 |
| FC | surf_parrot_selector | 640 | 15 | class_unsupported 9, input_unimplemented 4, player_input 2 |
| FC | surf_pavilion | 1679 | 12 | class_unsupported 6, input_unimplemented 4, volume_parented 2 |
| FC | surf_poolday | 225 | 2 | class_unsupported 2 |
| FC | surf_pox | 255 | 12 | class_unsupported 8, input_unimplemented 4 |
| FC | surf_quilavar | 415 | 2 | player_input 1, input_unimplemented 1 |
| FC | surf_rebel_resistance_final3 | 1475 | 8 | class_unsupported 5, input_unimplemented 3 |
| FC | surf_rookie | 451 | 2 | player_input 1, class_unsupported 1 |
| FC | surf_ski_2 | 197 | 3 | class_unsupported 2, input_unimplemented 1 |
| FC | surf_ski_2_source | 299 | 3 | player_input 1, input_unimplemented 1, class_unsupported 1 |
| FC | surf_skyworld | 100 | 0 |  |
| FC | surf_snipers_island | 131 | 1 | class_unsupported 1 |
| FC | surf_stonework3 | 1348 | 2 | player_input 1, input_unimplemented 1 |
| FC | surf_stonework4 | 1529 | 3 | player_input 1, input_unimplemented 1, class_unsupported 1 |
| FC | surf_summit | 843 | 4 | player_input 3, input_unimplemented 1 |
| FC | surf_the_flow | 82 | 1 | class_unsupported 1 |
| FC | surf_the_gloaming | 416 | 21 | class_unsupported 11, input_unimplemented 8, player_input 1, volume_parented 1 |
| FC | surf_thriller | 247 | 5 | input_unimplemented 4, class_unsupported 1 |
| FC | surf_torque2 | 1391 | 17 | class_unsupported 8, input_unimplemented 4, player_input 3, volume_parented 2 |
| FC | surf_vegetables | 1420 | 10 | input_unimplemented 4, class_unsupported 4, player_input 2 |
| FC | surf_velocity | 1209 | 18 | input_unimplemented 6, class_unsupported 6, player_input 5, volume_parented 1 |
| FC | surf_year3000 | 495 | 9 | input_unimplemented 6, volume_key_unread 2, class_unsupported 2 |
| FC | tc_hydro | 1530 | 33 | filter_class_unsupported 21, volume_unrecorded 11, input_unimplemented 10, class_unsupported 6 |
| FC | test_hardware | 191 | 4 | class_unsupported 3, input_unimplemented 1 |
| FC | test_map2 | 249 | 0 |  |
| FC | test_speakers | 86 | 5 | input_unimplemented 2, class_unsupported 2, class_unknown 1 |
| FC | tow_dynamite | 1481 | 42 | input_unimplemented 15, class_unsupported 12, filter_class_unsupported 8, class_unknown 7 |
| FC | tr_dustbowl | 1164 | 65 | input_unimplemented 36, filter_class_unsupported 35, class_unknown 16, volume_unrecorded 7 |
| FC | tr_target | 433 | 42 | input_unimplemented 23, class_unknown 10, filter_class_unsupported 9, class_unsupported 8 |
| FC | ttt_airbus_b3 | 1714 | 22 | class_unsupported 12, input_unimplemented 9, player_input 1 |
| FC | ttt_airbus_b3 | 1714 | 22 | class_unsupported 12, input_unimplemented 9, player_input 1 |
| FC | ttt_rooftops_2016_v1 | 3260 | 69 | input_unimplemented 30, class_unsupported 19, player_input 8, volume_parented 8 |
| FC | ttt_rooftops_2016_v1 | 3260 | 69 | input_unimplemented 30, class_unsupported 19, player_input 8, volume_parented 8 |
| FC | vsh_distillery | 412 | 7 | class_unsupported 3, input_unimplemented 2, player_input 1, class_unknown 1 |
| FC | vsh_maul | 844 | 6 | class_unsupported 4, input_unimplemented 1, class_unknown 1 |
| FC | vsh_nucleus | 614 | 12 | class_unsupported 5, class_unknown 4, input_unimplemented 2, filter_class_unsupported 2 |
| FC | vsh_outburst | 551 | 5 | class_unsupported 3, input_unimplemented 1, class_unknown 1 |
| FC | vsh_skirmish | 716 | 11 | class_unsupported 6, input_unimplemented 2, filter_class_unsupported 2, class_unknown 2 |
| FC | vsh_tinyrock | 408 | 7 | class_unsupported 4, input_unimplemented 2, class_unknown 1 |
| FC | welcometomexicov6 | 1012 | 5 | class_unsupported 4, input_unimplemented 1 |
| FC | ze_PotC_v3_4fix | 667 | 10 | class_unsupported 5, input_unimplemented 4, volume_parented 1 |
| FC | ze_biohazard_manor_v4a_004 | 1416 | 11 | input_unimplemented 4, class_unsupported 3, volume_parented 2, player_input 1 |
| FC | ze_blackmesa_escape_final | 386 | 3 | class_unsupported 2, input_unimplemented 1 |
| FC | ze_boat_escape_7_b1 | 577 | 10 | input_unimplemented 6, class_unsupported 3, volume_parented 1 |
| FC | ze_chaos_city_b1 | 231 | 3 | class_unsupported 2, input_unimplemented 1 |
| FC | ze_death_star_escape_v4_3 | 1272 | 9 | volume_parented 4, class_unsupported 4, input_unimplemented 1 |
| FC | ze_jurassicpark_v2 | 393 | 6 | class_unsupported 4, input_unimplemented 2 |
| FC | ze_nuke_beta | 404 | 1 | class_unsupported 1 |
| FC | ze_runforyourlife_1_v4 | 273 | 4 | class_unsupported 2, input_unimplemented 1, volume_parented 1 |
| FC | zi_atoll | 498 | 11 | filter_class_unsupported 27, class_unknown 5, class_unsupported 3, input_unimplemented 2 |
| FC | zi_blazehattan | 570 | 13 | class_unknown 5, input_unimplemented 3, class_unsupported 3, player_input 2 |
| FC | zi_devastation_final1 | 455 | 14 | class_unsupported 5, class_unknown 5, input_unimplemented 3, filter_class_unsupported 2 |
| FC | zi_murky | 679 | 12 | class_unknown 5, input_unimplemented 4, class_unsupported 3 |
| FC | zi_sanitarium | 1514 | 15 | class_unsupported 6, class_unknown 5, input_unimplemented 3, filter_class_unsupported 2 |
| FC | zi_woods | 457 | 13 | class_unsupported 5, class_unknown 5, input_unimplemented 3 |
| FC | zm_16chambres | 730 | 1 | class_unsupported 1 |
| FC | zm_4way_tunnel_v2 | 392 | 6 | class_unsupported 3, volume_parented 2, input_unimplemented 1 |
| FC | zm_ATIX_helicopter | 584 | 6 | input_unimplemented 3, class_unsupported 3 |
| FC | zm_blockfort_v5_b2 | 649 | 12 | class_unsupported 6, input_unimplemented 5, player_input 1 |
| FC | zm_day_lego_v2_fix | 712 | 5 | class_unsupported 3, input_unimplemented 2 |
| FC | zm_hellarch | 229 | 1 | class_unsupported 1 |
| FC | zm_house_outbreak4 | 426 | 2 | class_unsupported 2 |
| FC | zm_lila_panic | 131 | 2 | class_unsupported 2 |
| FC | zm_officeattack_b5a | 421 | 4 | class_unsupported 4 |
| FC | zm_roy_highway | 983 | 4 | input_unimplemented 2, class_unsupported 2 |
| FC | zm_roy_the_ship | 427 | 5 | class_unsupported 3, input_unimplemented 2 |
| FC | zs_abandoned_mall_v6b | 1866 | 0 |  |
| FC | zs_antarctic_hospital | 658 | 8 | input_unimplemented 5, class_unsupported 3 |
| FC | zs_erosion_b1 | 581 | 3 | input_unimplemented 2, class_unsupported 1 |
| FC | zs_goth_house | 260 | 0 |  |
| FC | zs_krusty_krab_large_v5 | 620 | 2 | player_input 1, class_unsupported 1 |
| FC | zs_lens | 527 | 3 | class_unsupported 2, input_unimplemented 1 |
| FC | zs_pathogen | 1053 | 10 | input_unimplemented 5, class_unsupported 5 |
| FC | zs_ravenstreet_v1 | 452 | 0 |  |
| FC | zs_slugde | 717 | 6 | input_unimplemented 3, class_unsupported 3 |
| FC | zs_verystill_v1a | 2178 | 5 | class_unsupported 4, input_unimplemented 1 |
| HnS | ph_hotel | 611 | 5 | input_unimplemented 4, class_unsupported 1 |
| HnS | ph_hotel | 611 | 5 | input_unimplemented 4, class_unsupported 1 |
| HnS | ph_hotel~720da13f | 611 | 5 | input_unimplemented 4, class_unsupported 1 |
| MM | mu_factory_winter | 2027 | 7 | input_unimplemented 4, class_unsupported 3 |
| MM | mu_factory_winter | 2027 | 7 | input_unimplemented 4, class_unsupported 3 |
| MM | mu_greenwood | 188 | 0 |  |
| MM | mu_greenwood | 188 | 0 |  |
| MM | mu_hotel | 376 | 0 |  |
| MM | mu_hotel | 376 | 0 |  |
| MM | mu_office | 244 | 0 |  |
| MM | mu_office | 244 | 0 |  |
| MM | mu_silence | 614 | 0 |  |
| MM | mu_silence | 614 | 0 |  |
| MM | test_map2 | 249 | 0 |  |
| MM | test_map2 | 249 | 0 |  |
| MM | ttt_silence_v3 | 649 | 7 | class_unsupported 4, input_unimplemented 2, volume_parented 1 |
| MM | ttt_silence_v3 | 649 | 7 | class_unsupported 4, input_unimplemented 2, volume_parented 1 |
| PH | gm_apresort | 1027 | 5 | class_unsupported 3, input_unimplemented 2 |
| PH | gm_villa | 2172 | 6 | class_unsupported 3, input_unimplemented 2, player_input 1 |
| PH | ph_WolfsManor | 346 | 0 |  |
| PH | ph_abandoned_church | 279 | 0 |  |
| PH | ph_abandoned_church | 279 | 0 |  |
| PH | ph_abandoned_hotel | 787 | 0 |  |
| PH | ph_abandoned_hotel | 787 | 0 |  |
| PH | ph_autumngetaway | 932 | 0 |  |
| PH | ph_autumngetaway | 932 | 0 |  |
| PH | ph_bank | 840 | 0 |  |
| PH | ph_bank | 840 | 0 |  |
| PH | ph_bikinibottom | 555 | 1 | input_unimplemented 1 |
| PH | ph_bikinibottom | 555 | 1 | input_unimplemented 1 |
| PH | ph_cyber_dinner | 1987 | 2 | input_unimplemented 1, class_unsupported 1 |
| PH | ph_cyber_dinner | 1987 | 2 | input_unimplemented 1, class_unsupported 1 |
| PH | ph_elementary_school | 853 | 7 | input_unimplemented 4, class_unsupported 3 |
| PH | ph_elementary_school | 853 | 7 | input_unimplemented 4, class_unsupported 3 |
| PH | ph_frontyard | 375 | 0 |  |
| PH | ph_frontyard | 375 | 0 |  |
| PH | ph_gas_station | 1079 | 0 |  |
| PH | ph_gas_station | 1079 | 0 |  |
| PH | ph_islandhouse_2014 | 524 | 0 |  |
| PH | ph_islandhouse_2014 | 524 | 0 |  |
| PH | ph_library_final | 593 | 0 |  |
| PH | ph_midwestapartment | 474 | 0 |  |
| PH | ph_midwestapartment | 474 | 0 |  |
| PH | ph_oceanwaves | 461 | 1 | class_unsupported 1 |
| PH | ph_oceanwaves | 461 | 1 | class_unsupported 1 |
| PH | ph_restaurant_os | 1432 | 13 | input_unimplemented 8, class_unsupported 4, player_input 1 |
| PH | ph_restaurant_os | 1432 | 13 | input_unimplemented 8, class_unsupported 4, player_input 1 |
| PH | ph_swimmingpool | 1676 | 11 | input_unimplemented 6, class_unsupported 4, player_input 1 |
| PH | ph_swimmingpool | 1676 | 11 | input_unimplemented 6, class_unsupported 4, player_input 1 |
| PH | ph_volcano_v1 | 1111 | 0 |  |
| PH | ph_volcano_v1 | 1111 | 0 |  |
| PH | ph_westerncity | 1070 | 1 | input_unimplemented 1 |
| PH | ph_westerncity | 1070 | 1 | input_unimplemented 1 |
| PH | ph_wolfsmanor | 346 | 0 |  |
| Playlot | gm_bigbridge | 25 | 0 |  |
| Playlot | gm_bigbridge | 25 | 0 |  |
| Playlot | gm_construct_d14_cse_lakeside | 591 | 2 | input_unimplemented 1, class_unsupported 1 |
| Playlot | gm_construct_d14_cse_lakeside | 591 | 2 | input_unimplemented 1, class_unsupported 1 |
| Playlot | gm_construct_dark | 621 | 30 | volume_parented 14, input_unimplemented 10, class_unsupported 6 |
| Playlot | gm_construct_dark | 621 | 30 | volume_parented 14, input_unimplemented 10, class_unsupported 6 |
| Playlot | gm_construct_extended_bunker | 872 | 2 | input_unimplemented 1, class_unsupported 1 |
| Playlot | gm_construct_extended_bunker | 872 | 2 | input_unimplemented 1, class_unsupported 1 |
| Playlot | gm_construct_flatgrass_v6 | 2964 | 1 | input_unimplemented 1 |
| Playlot | gm_construct_flatgrass_v6 | 2964 | 1 | input_unimplemented 1 |
| Playlot | gm_flatgrass_conspiracy | 299 | 5 | input_unimplemented 5 |
| Playlot | gm_flatgrass_conspiracy | 299 | 5 | input_unimplemented 5 |
| Playlot | gm_smallbase | 26 | 0 |  |
| Playlot | gm_smallbase | 26 | 0 |  |
| Playlot | mountain_b6 | 488 | 0 |  |
| Playlot | mountain_b6 | 488 | 0 |  |
| Wipeout | mg_LEGO_course | 246 | 3 | class_unsupported 2, input_unimplemented 1 |
| Wipeout | mg_dans_course | 349 | 3 | class_unsupported 3 |
| Wipeout | mg_dans_course | 349 | 3 | class_unsupported 3 |
| Wipeout | mg_dc_course_fixed | 705 | 6 | class_unsupported 3, input_unimplemented 2, player_input 1 |
| Wipeout | mg_dc_course_fixed | 705 | 6 | class_unsupported 3, input_unimplemented 2, player_input 1 |
| Wipeout | mg_labo_course_fix | 477 | 4 | player_input 1, input_unimplemented 1, volume_parented 1, class_unsupported 1 |
| Wipeout | mg_labo_course_fix | 477 | 4 | player_input 1, input_unimplemented 1, volume_parented 1, class_unsupported 1 |
| Wipeout | mg_lego_course | 246 | 3 | class_unsupported 2, input_unimplemented 1 |
| Wipeout | mg_oaks_course | 561 | 16 | volume_parented 12, input_unimplemented 2, class_unsupported 2 |
| Wipeout | mg_oaks_course | 561 | 16 | volume_parented 12, input_unimplemented 2, class_unsupported 2 |
| Wipeout | mg_office_coursee | 766 | 16 | class_unsupported 7, input_unimplemented 6, player_input 3 |
| Wipeout | mg_office_coursee | 766 | 16 | class_unsupported 7, input_unimplemented 6, player_input 3 |
| Wipeout | mg_pauls_minecraft_course_v2 | 553 | 8 | player_input 3, input_unimplemented 3, class_unsupported 2 |
| Wipeout | mg_pauls_minecraft_course_v2 | 553 | 8 | player_input 3, input_unimplemented 3, class_unsupported 2 |
| Wipeout | mg_scary_course_v2 | 952 | 6 | input_unimplemented 4, class_unsupported 2 |
| Wipeout | mg_scary_course_v2 | 952 | 6 | input_unimplemented 4, class_unsupported 2 |
| Wipeout | mg_sweet_course_rework | 509 | 9 | class_unsupported 6, input_unimplemented 3 |
| Wipeout | mg_sweet_course_rework | 509 | 9 | class_unsupported 6, input_unimplemented 3 |
| Wipeout | mg_waytobar_course_2012 | 630 | 2 | class_unsupported 2 |
| Wipeout | mg_waytobar_course_2012 | 630 | 2 | class_unsupported 2 |
| ZZ | ZM_Krusty_krab_a3 | 839 | 9 | class_unsupported 6, input_unimplemented 2, player_input 1 |
| ZZ | Zm_mansion_css_beta | 653 | 32 | class_unsupported 10, input_unimplemented 9, volume_parented 9, player_input 4 |
| ZZ | Zm_mansion_css_beta-1 | 653 | 32 | class_unsupported 10, input_unimplemented 9, volume_parented 9, player_input 4 |
| ZZ | ze_PotC_v3_4fix | 667 | 10 | class_unsupported 5, input_unimplemented 4, volume_parented 1 |
| ZZ | ze_biohazard_manor_v4a_004 | 1416 | 11 | input_unimplemented 4, class_unsupported 3, volume_parented 2, player_input 1 |
| ZZ | ze_biohazard_manor_v4a_004 | 1416 | 11 | input_unimplemented 4, class_unsupported 3, volume_parented 2, player_input 1 |
| ZZ | ze_blackmesa_escape_final | 386 | 3 | class_unsupported 2, input_unimplemented 1 |
| ZZ | ze_blackmesa_escape_final | 386 | 3 | class_unsupported 2, input_unimplemented 1 |
| ZZ | ze_boat_escape_7_b1 | 577 | 10 | input_unimplemented 6, class_unsupported 3, volume_parented 1 |
| ZZ | ze_boat_escape_7_b1 | 577 | 10 | input_unimplemented 6, class_unsupported 3, volume_parented 1 |
| ZZ | ze_chaos_city_b1 | 231 | 3 | class_unsupported 2, input_unimplemented 1 |
| ZZ | ze_chaos_city_b1 | 231 | 3 | class_unsupported 2, input_unimplemented 1 |
| ZZ | ze_death_star_escape_v4_3 | 1272 | 9 | volume_parented 4, class_unsupported 4, input_unimplemented 1 |
| ZZ | ze_death_star_escape_v4_3 | 1272 | 9 | volume_parented 4, class_unsupported 4, input_unimplemented 1 |
| ZZ | ze_jurassicpark_v2 | 393 | 6 | class_unsupported 4, input_unimplemented 2 |
| ZZ | ze_jurassicpark_v2 | 393 | 6 | class_unsupported 4, input_unimplemented 2 |
| ZZ | ze_potc_v3_4fix | 667 | 10 | class_unsupported 5, input_unimplemented 4, volume_parented 1 |
| ZZ | ze_voodoo_islands_v8_5 | 324 | 3 | class_unsupported 2, input_unimplemented 1 |
| ZZ | ze_voodoo_islands_v8_5 | 324 | 3 | class_unsupported 2, input_unimplemented 1 |
| ZZ | zm_16chambres | 730 | 1 | class_unsupported 1 |
| ZZ | zm_16chambres | 730 | 1 | class_unsupported 1 |
| ZZ | zm_4way_tunnel_v2 | 392 | 6 | class_unsupported 3, volume_parented 2, input_unimplemented 1 |
| ZZ | zm_4way_tunnel_v2 | 392 | 6 | class_unsupported 3, volume_parented 2, input_unimplemented 1 |
| ZZ | zm_ATIX_helicopter | 584 | 6 | input_unimplemented 3, class_unsupported 3 |
| ZZ | zm_atix_helicopter | 584 | 6 | input_unimplemented 3, class_unsupported 3 |
| ZZ | zm_blockfort_v5_b2 | 649 | 12 | class_unsupported 6, input_unimplemented 5, player_input 1 |
| ZZ | zm_blockfort_v5_b2 | 649 | 12 | class_unsupported 6, input_unimplemented 5, player_input 1 |
| ZZ | zm_clouds_v2_1 | 306 | 11 | player_input 5, class_unsupported 4, input_unimplemented 1, volume_parented 1 |
| ZZ | zm_clouds_v2_1 | 306 | 11 | player_input 5, class_unsupported 4, input_unimplemented 1, volume_parented 1 |
| ZZ | zm_day_lego_v2_fix | 712 | 5 | class_unsupported 3, input_unimplemented 2 |
| ZZ | zm_day_lego_v2_fix | 712 | 5 | class_unsupported 3, input_unimplemented 2 |
| ZZ | zm_hellarch | 229 | 1 | class_unsupported 1 |
| ZZ | zm_hellarch | 229 | 1 | class_unsupported 1 |
| ZZ | zm_house_outbreak4 | 426 | 2 | class_unsupported 2 |
| ZZ | zm_house_outbreak4 | 426 | 2 | class_unsupported 2 |
| ZZ | zm_krusty_krab_a3 | 839 | 9 | class_unsupported 6, input_unimplemented 2, player_input 1 |
| ZZ | zm_lila_panic | 131 | 2 | class_unsupported 2 |
| ZZ | zm_lila_panic | 131 | 2 | class_unsupported 2 |
| ZZ | zm_mansion_css_beta | 653 | 32 | class_unsupported 10, input_unimplemented 9, volume_parented 9, player_input 4 |
| ZZ | zm_mars_horror_b4 | 710 | 9 | class_unsupported 5, input_unimplemented 4 |
| ZZ | zm_mars_horror_b4 | 710 | 9 | class_unsupported 5, input_unimplemented 4 |
| ZZ | zm_officeattack_b5a | 421 | 4 | class_unsupported 4 |
| ZZ | zm_officeattack_b5a | 421 | 4 | class_unsupported 4 |
| ZZ | zm_roy_highway | 983 | 4 | input_unimplemented 2, class_unsupported 2 |
| ZZ | zm_roy_highway | 983 | 4 | input_unimplemented 2, class_unsupported 2 |
| ZZ | zm_roy_the_ship | 427 | 5 | class_unsupported 3, input_unimplemented 2 |
| ZZ | zm_roy_the_ship | 427 | 5 | class_unsupported 3, input_unimplemented 2 |
| ZZ | zm_roy_the_ship-1 | 427 | 5 | class_unsupported 3, input_unimplemented 2 |
| ZZ | zs_abandoned_mall_v6b | 1866 | 0 |  |
| ZZ | zs_abandoned_mall_v6b | 1866 | 0 |  |
| ZZ | zs_adrift_v4 | 1465 | 5 | class_unsupported 4, input_unimplemented 1 |
| ZZ | zs_adrift_v4 | 1465 | 5 | class_unsupported 4, input_unimplemented 1 |
| ZZ | zs_antarctic_hospital | 658 | 8 | input_unimplemented 5, class_unsupported 3 |
| ZZ | zs_antarctic_hospital | 658 | 8 | input_unimplemented 5, class_unsupported 3 |
| ZZ | zs_erosion_b1 | 581 | 3 | input_unimplemented 2, class_unsupported 1 |
| ZZ | zs_erosion_b1 | 581 | 3 | input_unimplemented 2, class_unsupported 1 |
| ZZ | zs_goth_house | 260 | 0 |  |
| ZZ | zs_goth_house | 260 | 0 |  |
| ZZ | zs_krusty_krab_large_v5 | 620 | 2 | player_input 1, class_unsupported 1 |
| ZZ | zs_krusty_krab_large_v5 | 620 | 2 | player_input 1, class_unsupported 1 |
| ZZ | zs_lens | 527 | 3 | class_unsupported 2, input_unimplemented 1 |
| ZZ | zs_lens | 527 | 3 | class_unsupported 2, input_unimplemented 1 |
| ZZ | zs_pathogen | 1053 | 10 | input_unimplemented 5, class_unsupported 5 |
| ZZ | zs_pathogen | 1053 | 10 | input_unimplemented 5, class_unsupported 5 |
| ZZ | zs_slugde | 717 | 6 | input_unimplemented 3, class_unsupported 3 |
| ZZ | zs_slugde | 717 | 6 | input_unimplemented 3, class_unsupported 3 |
| ZZ | zs_verystill_v1a | 2178 | 5 | class_unsupported 4, input_unimplemented 1 |
| ZZ | zs_verystill_v1a | 2178 | 5 | class_unsupported 4, input_unimplemented 1 |
| other | blank | 3 | 0 |  |
| other | cp_orange_x3 | 197 | 8 | volume_unrecorded 4, class_unsupported 4 |
| other | source | 1420 | 10 | input_unimplemented 4, class_unsupported 4, player_input 2 |
| other | source | 593 | 0 |  |
| other | source | 1421 | 2 | player_input 2 |
| other | source | 1517 | 28 | class_unsupported 13, input_unimplemented 9, player_input 5, volume_parented 1 |
| other | source | 459 | 1 | volume_key_unread 30 |
| other | source | 304 | 0 |  |
| other | source | 422 | 2 | player_input 1, input_unimplemented 1 |
| other | source | 1318 | 4 | player_input 2, input_unimplemented 1, class_unsupported 1 |
| other | source | 1155 | 5 | player_input 2, class_unsupported 2, input_unimplemented 1 |
| other | source | 858 | 5 | player_input 2, input_unimplemented 2, class_unsupported 1 |
| other | source | 1178 | 4 | player_input 3, class_unsupported 1 |
| other | source | 525 | 2 | player_input 2 |
| other | source | 2142 | 6 | player_input 3, class_unsupported 2, input_unimplemented 1 |
| other | source | 1119 | 16 | input_unimplemented 9, class_unsupported 4, player_input 2, volume_parented 1 |
| other | source | 1264 | 6 | input_unimplemented 3, player_input 2, class_unsupported 1 |
| other | source | 1516 | 22 | player_input 9, input_unimplemented 7, class_unsupported 6 |
| other | source | 732 | 2 | player_input 2 |
| other | source | 458 | 3 | class_unsupported 2, player_input 1 |
| other | source | 1103 | 17 | class_unsupported 8, player_input 5, input_unimplemented 4 |
| other | source | 965 | 2 | player_input 2 |
| other | source | 423 | 0 |  |
| other | source | 1134 | 23 | player_input 9, input_unimplemented 7, class_unsupported 7 |
| other | source | 1944 | 13 | class_unsupported 5, player_input 4, input_unimplemented 4 |
| other | source | 153 | 1 | player_input 1 |
| other | source | 199 | 2 | player_input 1, class_unsupported 1 |
| other | source | 1224 | 6 | class_unsupported 4, player_input 2 |
| other | source | 254 | 3 | player_input 2, input_unimplemented 1 |
| other | source | 4949 | 24 | input_unimplemented 12, player_input 7, class_unsupported 5 |
| other | source | 1224 | 7 | input_unimplemented 6, class_unsupported 1 |
| other | source | 1986 | 9 | player_input 3, input_unimplemented 3, class_unsupported 3 |
| other | source | 1101 | 7 | player_input 3, input_unimplemented 2, class_unsupported 2 |
| other | source | 228 | 3 | class_unsupported 3 |
| other | source | 794 | 5 | player_input 5 |
| other | source | 1191 | 14 | input_unimplemented 9, class_unsupported 3, player_input 2 |
| other | source | 495 | 0 |  |
| other | source | 1148 | 4 | player_input 2, class_unsupported 2 |
| other | source | 843 | 4 | player_input 3, input_unimplemented 1 |
| other | source | 415 | 2 | player_input 1, input_unimplemented 1 |
| other | source | 850 | 1 | player_input 1 |
| other | source | 2878 | 2 | input_unimplemented 1, class_unsupported 1 |
| other | source | 1803 | 5 | player_input 4, class_unsupported 1 |
| other | source | 1144 | 5 | player_input 4, class_unsupported 1 |
| other | source | 1155 | 4 | player_input 2, input_unimplemented 1, class_unsupported 1 |
| other | source | 1401 | 4 | player_input 3, class_unsupported 1 |
| other | source | 2172 | 6 | class_unsupported 3, input_unimplemented 2, player_input 1 |
| other | source | 670 | 4 | player_input 3, class_unsupported 1 |
| other | source | 703 | 9 | input_unimplemented 4, class_unsupported 3, player_input 2 |
| other | source | 523 | 4 | player_input 2, input_unimplemented 1, class_unsupported 1 |
| other | source | 1453 | 3 | player_input 2, class_unsupported 1 |
| other | source | 1301 | 2 | player_input 1, class_unsupported 1 |
| other | source | 507 | 10 | player_input 5, class_unsupported 3, input_unimplemented 2 |
| other | source | 1284 | 14 | volume_key_unread 26, input_unimplemented 6, class_unsupported 5, player_input 2 |
| other | source | 567 | 2 | player_input 1, input_unimplemented 1 |
| other | source | 1322 | 2 | player_input 2 |
| other | source | 1432 | 21 | volume_parented 8, input_unimplemented 5, player_input 4, class_unsupported 4 |
| other | source | 1851 | 5 | player_input 2, input_unimplemented 2, class_unsupported 1 |
| other | source | 359 | 1 | input_unimplemented 1 |
| other | source | 805 | 3 | class_unsupported 2, player_input 1 |
| other | source | 1353 | 25 | input_unimplemented 12, class_unsupported 7, player_input 6 |
| other | source | 682 | 14 | input_unimplemented 5, class_unsupported 5, player_input 4 |
| other | source | 540 | 8 | player_input 5, class_unsupported 2, input_unimplemented 1 |
| other | source | 451 | 2 | player_input 1, class_unsupported 1 |
| other | source | 1212 | 12 | input_unimplemented 7, volume_key_unread 5, class_unsupported 1 |
| other | source | 1348 | 2 | player_input 1, input_unimplemented 1 |
| other | source | 686 | 0 |  |
| other | source | 175 | 6 | input_unimplemented 3, volume_parented 2, class_unsupported 1 |
| other | source | 691 | 12 | class_unsupported 7, input_unimplemented 4, player_input 1 |
| other | source | 1141 | 5 | player_input 2, input_unimplemented 2, class_unsupported 1 |
| other | source | 1529 | 3 | player_input 1, input_unimplemented 1, class_unsupported 1 |
| other | source | 1574 | 8 | player_input 3, class_unsupported 3, input_unimplemented 2 |
| other | source | 909 | 7 | player_input 4, input_unimplemented 2, class_unsupported 1 |
| other | source | 524 | 1 | class_unsupported 1 |
| other | source | 1714 | 22 | class_unsupported 12, input_unimplemented 9, player_input 1 |
| other | source | 491 | 6 | class_unsupported 5, input_unimplemented 1 |
| other | source | 226 | 0 |  |
| other | source | 495 | 9 | input_unimplemented 6, volume_key_unread 2, class_unsupported 2 |
| other | source | 160 | 0 |  |
| other | source | 8479 | 16 | input_unimplemented 9, class_unsupported 6, player_input 1 |
| other | source | 293 | 12 | input_unimplemented 6, class_unsupported 5, player_input 1 |
| other | source | 2677 | 1 | volume_key_unread 3 |
| other | source | 297 | 8 | input_unimplemented 4, class_unsupported 2, player_input 1, volume_parented 1 |
| other | source | 56 | 1 | class_unsupported 1 |
| other | source | 392 | 6 | class_unsupported 3, volume_parented 2, input_unimplemented 1 |
| other | source | 658 | 8 | input_unimplemented 5, class_unsupported 3 |
| other | source | 630 | 2 | class_unsupported 2 |
| other | source | 584 | 6 | input_unimplemented 3, class_unsupported 3 |
| other | source | 243 | 4 | class_unsupported 4 |
| other | source | 249 | 0 |  |
| other | source | 82 | 1 | class_unsupported 1 |
| other | source | 2707 | 26 | class_unsupported 15, input_unimplemented 10, player_input 1 |
| other | source | 621 | 30 | volume_parented 14, input_unimplemented 10, class_unsupported 6 |
| other | source | 240 | 2 | input_unimplemented 1, class_unsupported 1 |
| other | source | 255 | 12 | class_unsupported 8, input_unimplemented 4 |
| other | source | 710 | 9 | class_unsupported 5, input_unimplemented 4 |
| other | source | 452 | 9 | class_unsupported 5, input_unimplemented 3, volume_parented 1 |
| other | source | 666 | 5 | class_unsupported 4, input_unimplemented 1 |
| other | source | 477 | 4 | player_input 1, input_unimplemented 1, volume_parented 1, class_unsupported 1 |
| other | source | 265 | 2 | player_input 2 |
| other | source | 717 | 6 | input_unimplemented 3, class_unsupported 3 |
| other | source | 130 | 6 | volume_key_unread 7, input_unimplemented 3 |
| other | source | 60 | 0 |  |
| other | source | 655 | 13 | class_unsupported 8, input_unimplemented 3, player_input 1, volume_parented 1 |
| other | source | 611 | 5 | input_unimplemented 4, class_unsupported 1 |
| other | source | 22 | 1 | class_unsupported 1 |
| other | source | 426 | 2 | class_unsupported 2 |
| other | source | 990 | 9 | volume_parented 6, class_unsupported 3 |
| other | source | 839 | 9 | class_unsupported 6, input_unimplemented 2, player_input 1 |
| other | source | 677 | 13 | volume_parented 9, input_unimplemented 2, class_unsupported 2 |
| other | source | 3260 | 69 | input_unimplemented 30, class_unsupported 19, player_input 8, volume_parented 8 |
| other | source | 466 | 1 | class_unsupported 1 |
| other | source | 591 | 2 | input_unimplemented 1, class_unsupported 1 |
| other | source | 110 | 1 | class_unsupported 1 |
| other | source | 531 | 11 | class_unsupported 7, input_unimplemented 3, player_input 1 |
| other | source | 55 | 0 |  |
| other | source | 1449 | 17 | class_unsupported 12, input_unimplemented 5 |
| other | source | 1070 | 1 | input_unimplemented 1 |
| other | source | 369 | 0 |  |
| other | source | 118 | 4 | class_unsupported 3, input_unimplemented 1 |
| other | source | 1012 | 5 | class_unsupported 4, input_unimplemented 1 |
| other | source | 392 | 3 | player_input 1, input_unimplemented 1, class_unsupported 1 |
| other | source | 452 | 13 | class_unsupported 9, input_unimplemented 4 |
| other | source | 494 | 11 | class_unsupported 6, input_unimplemented 5 |
| other | source | 853 | 7 | input_unimplemented 4, class_unsupported 3 |
| other | source | 524 | 0 |  |
| other | source | 707 | 0 |  |
| other | source | 273 | 4 | class_unsupported 2, input_unimplemented 1, volume_parented 1 |
| other | source | 416 | 21 | class_unsupported 11, input_unimplemented 8, player_input 1, volume_parented 1 |
| other | source | 555 | 1 | input_unimplemented 1 |
| other | source | 527 | 3 | class_unsupported 2, input_unimplemented 1 |
| other | source | 561 | 16 | volume_parented 12, input_unimplemented 2, class_unsupported 2 |
| other | source | 199 | 2 | class_unsupported 2 |
| other | source | 1191 | 18 | class_unsupported 9, input_unimplemented 8, volume_parented 1 |
| other | source | 372 | 6 | input_unimplemented 3, class_unsupported 2, volume_key_unread 1 |
| other | source | 649 | 7 | class_unsupported 4, input_unimplemented 2, volume_parented 1 |
| other | source | 1416 | 11 | input_unimplemented 4, class_unsupported 3, volume_parented 2, player_input 1 |
| other | source | 783 | 2 | class_unsupported 2 |
| other | source | 260 | 3 | class_unsupported 3 |
| other | source | 1512 | 18 | input_unimplemented 7, class_unsupported 6, player_input 4, class_unknown 1 |
| other | source | 1079 | 0 |  |
| other | source | 588 | 13 | input_unimplemented 7, class_unsupported 6 |
| other | source | 649 | 12 | class_unsupported 6, input_unimplemented 5, player_input 1 |
| other | source | 2178 | 5 | class_unsupported 4, input_unimplemented 1 |
| other | source | 705 | 6 | class_unsupported 3, input_unimplemented 2, player_input 1 |
| other | source | 620 | 2 | player_input 1, class_unsupported 1 |
| other | source | 589 | 10 | class_unsupported 4, input_unimplemented 3, volume_parented 2, player_input 1 |
| other | source | 716 | 2 | class_unsupported 2 |
| other | source | 95 | 3 | class_unsupported 3 |
| other | source | 280 | 1 | class_unsupported 1 |
| other | source | 474 | 0 |  |
| other | source | 323 | 0 |  |
| other | source | 279 | 0 |  |
| other | source | 541 | 9 | input_unimplemented 4, class_unsupported 3, player_input 2 |
| other | source | 461 | 1 | class_unsupported 1 |
| other | source | 667 | 10 | class_unsupported 5, input_unimplemented 4, volume_parented 1 |
| other | source | 1351 | 2 | class_unsupported 2 |
| other | source | 1026 | 6 | class_unsupported 3, input_unimplemented 2, player_input 1 |
| other | source | 3361 | 1 | input_unimplemented 1 |
| other | source | 1272 | 9 | volume_parented 4, class_unsupported 4, input_unimplemented 1 |
| other | source | 932 | 0 |  |
| other | source | 1221 | 3 | class_unsupported 3 |
| other | source | 952 | 6 | input_unimplemented 4, class_unsupported 2 |
| other | source | 1679 | 12 | class_unsupported 6, input_unimplemented 4, volume_parented 2 |
| other | source | 653 | 32 | class_unsupported 10, input_unimplemented 9, volume_parented 9, player_input 4 |
| other | source | 1676 | 11 | input_unimplemented 6, class_unsupported 4, player_input 1 |
| other | source | 488 | 0 |  |
| other | source | 376 | 0 |  |
| other | source | 1987 | 2 | input_unimplemented 1, class_unsupported 1 |
| other | source | 197 | 1 | input_unimplemented 1 |
| other | source | 299 | 5 | input_unimplemented 5 |
| other | source | 911 | 13 | class_unsupported 6, input_unimplemented 5, volume_parented 2 |
| other | source | 26 | 0 |  |
| other | source | 313 | 4 | class_unsupported 3, input_unimplemented 1 |
| other | source | 365 | 5 | class_unsupported 3, input_unimplemented 2 |
| other | source | 581 | 3 | input_unimplemented 2, class_unsupported 1 |
| other | source | 350 | 5 | class_unsupported 4, input_unimplemented 1 |
| other | source | 611 | 5 | input_unimplemented 4, class_unsupported 1 |
| other | source | 872 | 2 | input_unimplemented 1, class_unsupported 1 |
| other | source | 1465 | 5 | class_unsupported 4, input_unimplemented 1 |
| other | source | 396 | 1 | class_unsupported 1 |
| other | source | 100 | 0 |  |
| other | source | 452 | 0 |  |
| other | source | 1161 | 15 | class_unsupported 10, input_unimplemented 4, player_input 1 |
| other | source | 1209 | 18 | input_unimplemented 6, class_unsupported 6, player_input 5, volume_parented 1 |
| other | source | 264 | 5 | class_unsupported 3, input_unimplemented 2 |
| other | source | 7205 | 6 | class_unsupported 4, input_unimplemented 2 |
| other | source | 167 | 7 | class_unsupported 4, input_unimplemented 3 |
| other | source | 983 | 4 | input_unimplemented 2, class_unsupported 2 |
| other | source | 154 | 1 | input_unimplemented 1 |
| other | source | 509 | 9 | class_unsupported 6, input_unimplemented 3 |
| other | source | 36 | 1 | class_unsupported 1 |
| other | source | 3 | 0 |  |
| other | source | 1076 | 29 | input_unimplemented 11, class_unsupported 11, player_input 5, volume_parented 2 |
| other | source | 238 | 1 | class_unsupported 1 |
| other | source | 3266 | 3 | input_unimplemented 2, player_input 1 |
| other | source | 614 | 0 |  |
| other | source | 5122 | 19 | input_unimplemented 14, class_unsupported 4, player_input 1 |
| other | source | 249 | 17 | volume_parented 12, class_unsupported 3, input_unimplemented 2 |
| other | source | 244 | 2 | class_unsupported 2 |
| other | source | 404 | 1 | class_unsupported 1 |
| other | source | 427 | 5 | class_unsupported 3, input_unimplemented 2 |
| other | source | 131 | 2 | class_unsupported 2 |
| other | source | 246 | 3 | class_unsupported 2, input_unimplemented 1 |
| other | source | 138 | 1 | player_input 1 |
| other | source | 131 | 1 | class_unsupported 1 |
| other | source | 197 | 3 | class_unsupported 2, input_unimplemented 1 |
| other | source | 324 | 1 | class_unsupported 1 |
| other | source | 349 | 3 | class_unsupported 3 |
| other | source | 421 | 4 | class_unsupported 4 |
| other | source | 731 | 2 | input_unimplemented 1, class_unsupported 1 |
| other | source | 2372 | 0 |  |
| other | source | 170 | 1 | class_unsupported 1 |
| other | source | 968 | 23 | class_unsupported 10, input_unimplemented 7, volume_parented 5, player_input 1 |
| other | source | 1018 | 13 | input_unimplemented 6, class_unsupported 5, volume_parented 2 |
| other | source | 475 | 4 | class_unsupported 3, input_unimplemented 1 |
| other | source | 296 | 2 | class_unsupported 2 |
| other | source | 349 | 0 |  |
| other | source | 766 | 16 | class_unsupported 7, input_unimplemented 6, player_input 3 |
| other | source | 2027 | 7 | input_unimplemented 4, class_unsupported 3 |
| other | source | 188 | 0 |  |
| other | source | 1217 | 11 | input_unimplemented 7, class_unsupported 4 |
| other | source | 425 | 4 | input_unimplemented 2, class_unsupported 2 |
| other | source | 1111 | 0 |  |
| other | source | 393 | 6 | class_unsupported 4, input_unimplemented 2 |
| other | source | 113 | 1 | class_unsupported 1 |
| other | source | 550 | 28 | volume_parented 9, class_unsupported 7, input_unimplemented 6, player_input 5 |
| other | source | 712 | 5 | class_unsupported 3, input_unimplemented 2 |
| other | source | 787 | 0 |  |
| other | source | 553 | 8 | player_input 3, input_unimplemented 3, class_unsupported 2 |
| other | source | 260 | 0 |  |
| other | source | 231 | 3 | class_unsupported 2, input_unimplemented 1 |
| other | source | 577 | 10 | input_unimplemented 6, class_unsupported 3, volume_parented 1 |
| other | source | 173 | 2 | player_input 1, input_unimplemented 1 |
| other | source | 229 | 1 | class_unsupported 1 |
| other | source | 386 | 3 | class_unsupported 2, input_unimplemented 1 |
| other | source | 247 | 5 | input_unimplemented 4, class_unsupported 1 |
| other | source | 197 | 8 | volume_unrecorded 4, class_unsupported 4 |
| other | source | 1066 | 11 | input_unimplemented 5, class_unsupported 4, player_input 1, volume_parented 1 |
| other | source | 203 | 2 | input_unimplemented 1, class_unsupported 1 |
| other | source | 182 | 2 | class_unsupported 2 |
| other | source | 640 | 15 | class_unsupported 9, input_unimplemented 4, player_input 2 |
| other | source | 468 | 6 | class_unsupported 5, input_unimplemented 1 |
| other | source | 665 | 8 | input_unimplemented 4, volume_parented 2, player_input 1, class_unsupported 1 |
| other | source | 743 | 0 |  |
| other | source | 2964 | 1 | input_unimplemented 1 |
| other | source | 346 | 0 |  |
| other | source | 936 | 4 | input_unimplemented 2, class_unsupported 2 |
| other | source | 932 | 2 | class_unsupported 2 |
| other | source | 306 | 11 | player_input 5, class_unsupported 4, input_unimplemented 1, volume_parented 1 |
| other | source | 1866 | 0 |  |
| other | source | 331 | 2 | class_unsupported 2 |
| other | source | 1212 | 12 | input_unimplemented 7, volume_key_unread 5, class_unsupported 1 |
| other | source | 346 | 8 | input_unimplemented 3, volume_parented 2, class_unsupported 2, player_input 1 |
| other | source | 25 | 0 |  |
| other | source | 1780 | 1 | class_unsupported 1 |
| other | source | 299 | 3 | player_input 1, input_unimplemented 1, class_unsupported 1 |
| other | source | 1475 | 8 | class_unsupported 5, input_unimplemented 3 |
| other | source | 730 | 1 | class_unsupported 1 |
| other | source | 1053 | 10 | input_unimplemented 5, class_unsupported 5 |
| other | source | 217 | 0 |  |
| other | source | 434 | 9 | input_unimplemented 5, volume_key_unread 3, class_unsupported 1 |
| other | source | 324 | 3 | class_unsupported 2, input_unimplemented 1 |
| other | source | 331 | 4 | input_unimplemented 2, class_unsupported 2 |
| other | source | 523 | 7 | class_unsupported 4, input_unimplemented 2, player_input 1 |
| other | source | 225 | 2 | class_unsupported 2 |
| other | source | 375 | 0 |  |
| other | source | 699 | 28 | volume_parented 12, input_unimplemented 7, class_unsupported 6, player_input 2 |
| other | source | 1391 | 17 | class_unsupported 8, input_unimplemented 4, player_input 3, volume_parented 2 |
| other | source | 244 | 0 |  |
| other | source | 258 | 3 | class_unsupported 2, input_unimplemented 1 |
| other | source | 72 | 0 |  |
| other | source | 1432 | 13 | input_unimplemented 8, class_unsupported 4, player_input 1 |
| other | source | 228 | 0 |  |
| other | source | 1027 | 5 | class_unsupported 3, input_unimplemented 2 |
| other | source | 491 | 7 | class_unsupported 6, input_unimplemented 1 |
| other | source | 840 | 0 |  |

### Not audited

- deathrun_helix_b8: ValueError: /home/gamedev/projects/mapsrc/deathrun/126992/x/deathrun_helix_b8.bsp is cut off: lumps [0, 2, 6, 7, 8, 9, 11, 12] run past the end of its 4225536 b
- mu_hotel: ValueError: /home/gamedev/projects/mapsrc/murder/1830568620/x/mu_hotel.bsp is too short to be a BSP file
- mu_hotel: ValueError: /home/gamedev/projects/mapsrc/murder/1830568620/y/mu_hotel.bsp is too short to be a BSP file
- Zm_mansion_css_beta: ValueError: /home/gamedev/projects/mapsrc/zz/r131181/Zm_mansion_css_beta.bsp is cut off: lumps [0, 8, 9, 12, 13, 14, 15, 16] run past the end of its 1392640 byt
- zm_roy_the_ship: ValueError: /home/gamedev/projects/mapsrc/zz/r132707/zm_roy_the_ship.bsp is cut off: lumps [0, 4, 8, 9, 12, 13, 14, 15] run past the end of its 935168 bytes (an

## Inspirations (216 maps)

### Totals

216 distinct maps audited, 0 could not be read.

| Finding | Severity | Maps | Items | Meaning |
| --- | --- | --- | --- | --- |
| `class_unsupported` | unsupported | 162 | 519 | a gameplay class (wired by outputs, or a trigger/logic/filter/game class) with no runtime component |
| `player_input` | unsupported | 153 | 401 | an input sent to the player (!activator/!player): the game's actor must implement it |
| `input_unimplemented` | unsupported | 135 | 437 | an input sent to an entity whose component does not implement it |
| `volume_parented` | unsupported | 19 | 40 | a volume parented to something that moves without a mover record (a prop_dynamic, a physics object): the volume stays where it was compiled |
| `volume_key_unread` | unsupported | 6 | 63 | a gameplay key on a volume the runtime does not apply |
| `filter_dangling` | source | 104 | 946 | a filtername no entity carries (the engine admits everyone) |
| `target_dangling` | source | 48 | 185 | an output target no entity carries (the original does nothing there either) |
| `volume_follows` | handled | 28 | 337 | a volume parented to a door, lift, train or spinner (through parents that do not move): DotMapVolumeNode carries it with the mover chain, SetParent included |
| `teleport_dangling` | source | 17 | 209 | a trigger_teleport target no entity carries (the engine does nothing) |
| `parent_dangling` | source | 8 | 42 | a parentname no entity carries |
| `teleport_target_dynamic` | handled | 2 | 22 | a trigger_teleport whose target logic changes at run time (AddOutput target / SetRemoteDestination); DotMapTeleport re-aims it as the engine does |

### Entity classes

| Status | Classes | Of which gameplay |
| --- | --- | --- |
| implemented | 135 | 59 |
| approximated | 29 | 9 |
| ignored | 33 | 9 |
| unknown | 0 | 0 |

Gameplay classes not implemented, by maps using them:

| Class | Status | Maps |
| --- | --- | --- |
| `point_viewcontrol` | ignored | 105 |
| `path_track` | ignored | 51 |
| `env_entity_maker` | approximated | 46 |
| `player_weaponstrip` | approximated | 43 |
| `func_buyzone` | ignored | 29 |
| `player_speedmod` | approximated | 21 |
| `env_laser` | approximated | 19 |
| `game_text` | approximated | 18 |
| `func_bomb_target` | ignored | 18 |
| `game_weapon_manager` | ignored | 9 |
| `point_hurt` | approximated | 6 |
| `point_teleport` | approximated | 4 |
| `func_clip_vphysics` | ignored | 3 |
| `trigger_look` | approximated | 3 |
| `trigger_vphysics_motion` | ignored | 2 |
| `trigger_brush` | approximated | 2 |
| `env_firesource` | ignored | 2 |
| `trigger_remove` | ignored | 1 |

### Other mappable categories

| Category | Maps | Entities |
| --- | --- | --- |
| lights | 207 | 52807 |
| water | 166 | 594 |
| particles | 159 | 7494 |
| sprites_beams | 154 | 12697 |
| commands | 153 | 817 |
| sound | 152 | 3778 |
| sky_fog_post | 119 | 316 |
| physics_props | 89 | 1725 |
| decals_overlays | 77 | 5768 |
| nav_ai | 51 | 2486 |

Maps carrying: 
Maps packing sounds: 0; packing sound scripts or soundscapes: 0

### Per map

| Game | Map | Entities | Severe | Top findings |
| --- | --- | --- | --- | --- |
| Airdrift | Surf_Mesa | 228 | 3 | class_unsupported 3 |
| Airdrift | bhop_Evolve | 495 | 0 |  |
| Airdrift | bhop_FreAkin | 1141 | 5 | player_input 2, input_unimplemented 2, class_unsupported 1 |
| Airdrift | bhop_alvo2 | 562 | 6 | player_input 4, input_unimplemented 1, class_unsupported 1 |
| Airdrift | bhop_alvo2 | 562 | 6 | player_input 4, input_unimplemented 1, class_unsupported 1 |
| Airdrift | bhop_amor | 392 | 3 | player_input 1, input_unimplemented 1, class_unsupported 1 |
| Airdrift | bhop_amor | 392 | 3 | player_input 1, input_unimplemented 1, class_unsupported 1 |
| Airdrift | bhop_ananas | 858 | 5 | player_input 2, input_unimplemented 2, class_unsupported 1 |
| Airdrift | bhop_angst | 1516 | 22 | player_input 9, input_unimplemented 7, class_unsupported 6 |
| Airdrift | bhop_angst | 1516 | 22 | player_input 9, input_unimplemented 7, class_unsupported 6 |
| Airdrift | bhop_arcane_v2 | 1432 | 21 | volume_parented 8, input_unimplemented 5, player_input 4, class_unsupported 4 |
| Airdrift | bhop_atmosphere | 458 | 3 | class_unsupported 2, player_input 1 |
| Airdrift | bhop_atmosphere | 458 | 3 | class_unsupported 2, player_input 1 |
| Airdrift | bhop_aztec | 226 | 0 |  |
| Airdrift | bhop_badges | 1224 | 6 | class_unsupported 4, player_input 2 |
| Airdrift | bhop_badges2 | 1944 | 13 | class_unsupported 5, player_input 4, input_unimplemented 4 |
| Airdrift | bhop_badges_mini | 1148 | 4 | player_input 2, class_unsupported 2 |
| Airdrift | bhop_brodderlands | 778 | 4 | player_input 2, input_unimplemented 1, class_unsupported 1 |
| Airdrift | bhop_brodderlands | 778 | 4 | player_input 2, input_unimplemented 1, class_unsupported 1 |
| Airdrift | bhop_communityjump | 1754 | 5 | player_input 3, class_unsupported 2 |
| Airdrift | bhop_communityjump | 1754 | 5 | player_input 3, class_unsupported 2 |
| Airdrift | bhop_crash_egypt | 1284 | 14 | volume_key_unread 26, input_unimplemented 6, class_unsupported 5, player_input 2 |
| Airdrift | bhop_cw_journey | 2112 | 3 | player_input 2, class_unsupported 1 |
| Airdrift | bhop_cw_journey | 2112 | 3 | player_input 2, class_unsupported 1 |
| Airdrift | bhop_decay | 1451 | 6 | player_input 4, input_unimplemented 2 |
| Airdrift | bhop_decay | 1451 | 6 | player_input 4, input_unimplemented 2 |
| Airdrift | bhop_depot | 1264 | 6 | input_unimplemented 3, player_input 2, class_unsupported 1 |
| Airdrift | bhop_depot | 1264 | 6 | input_unimplemented 3, player_input 2, class_unsupported 1 |
| Airdrift | bhop_dunes | 430 | 5 | player_input 4, class_unsupported 1 |
| Airdrift | bhop_eazy | 323 | 0 |  |
| Airdrift | bhop_eazy_v2 | 524 | 1 | class_unsupported 1 |
| Airdrift | bhop_elate | 459 | 1 | volume_key_unread 30 |
| Airdrift | bhop_epiphany | 1401 | 4 | player_input 3, class_unsupported 1 |
| Airdrift | bhop_exanimo | 1301 | 2 | player_input 1, class_unsupported 1 |
| Airdrift | bhop_exanimo | 1301 | 2 | player_input 1, class_unsupported 1 |
| Airdrift | bhop_exodus | 1191 | 14 | input_unimplemented 9, class_unsupported 3, player_input 2 |
| Airdrift | bhop_forgotten | 1178 | 4 | player_input 3, class_unsupported 1 |
| Airdrift | bhop_forgotten | 1178 | 4 | player_input 3, class_unsupported 1 |
| Airdrift | bhop_freakin | 1141 | 5 | player_input 2, input_unimplemented 2, class_unsupported 1 |
| Airdrift | bhop_frotinity2 | 965 | 2 | player_input 2 |
| Airdrift | bhop_fur | 423 | 0 |  |
| Airdrift | bhop_fury | 1155 | 4 | player_input 2, input_unimplemented 1, class_unsupported 1 |
| Airdrift | bhop_fury | 1155 | 4 | player_input 2, input_unimplemented 1, class_unsupported 1 |
| Airdrift | bhop_fury_2 | 1453 | 3 | player_input 2, class_unsupported 1 |
| Airdrift | bhop_grove | 138 | 1 | player_input 1 |
| Airdrift | bhop_hellish_dream_css | 523 | 4 | player_input 2, input_unimplemented 1, class_unsupported 1 |
| Airdrift | bhop_hellish_dream_css | 523 | 4 | player_input 2, input_unimplemented 1, class_unsupported 1 |
| Airdrift | bhop_hive | 1147 | 7 | input_unimplemented 3, player_input 2, class_unsupported 2 |
| Airdrift | bhop_hive | 1147 | 7 | input_unimplemented 3, player_input 2, class_unsupported 2 |
| Airdrift | bhop_interloper | 1144 | 5 | player_input 4, class_unsupported 1 |
| Airdrift | bhop_japan | 540 | 8 | player_input 5, class_unsupported 2, input_unimplemented 1 |
| Airdrift | bhop_jouluuu | 584 | 2 | player_input 2 |
| Airdrift | bhop_jouluuu | 584 | 2 | player_input 2 |
| Airdrift | bhop_lego | 1093 | 19 | input_unimplemented 8, class_unsupported 7, player_input 4 |
| Airdrift | bhop_lego | 1093 | 19 | input_unimplemented 8, class_unsupported 7, player_input 4 |
| Airdrift | bhop_lego2 | 1103 | 17 | class_unsupported 8, player_input 5, input_unimplemented 4 |
| Airdrift | bhop_lego3 | 507 | 10 | player_input 5, class_unsupported 3, input_unimplemented 2 |
| Airdrift | bhop_lost_world_v2 | 2190 | 18 | class_unsupported 8, input_unimplemented 7, player_input 2, volume_parented 1 |
| Airdrift | bhop_mario_fxd | 850 | 1 | player_input 1 |
| Airdrift | bhop_miku_v2 | 468 | 6 | player_input 2, input_unimplemented 2, class_unsupported 2 |
| Airdrift | bhop_miku_v2 | 468 | 6 | player_input 2, input_unimplemented 2, class_unsupported 2 |
| Airdrift | bhop_monotonous | 244 | 0 |  |
| Airdrift | bhop_monotonous | 244 | 0 |  |
| Airdrift | bhop_monster_jam | 805 | 3 | class_unsupported 2, player_input 1 |
| Airdrift | bhop_nature | 1101 | 7 | player_input 3, input_unimplemented 2, class_unsupported 2 |
| Airdrift | bhop_null_fix | 1134 | 23 | player_input 9, input_unimplemented 7, class_unsupported 7 |
| Airdrift | bhop_null_fix | 1134 | 23 | player_input 9, input_unimplemented 7, class_unsupported 7 |
| Airdrift | bhop_ocean | 199 | 2 | player_input 1, class_unsupported 1 |
| Airdrift | bhop_overthinker | 794 | 5 | player_input 5 |
| Airdrift | bhop_pandora2_fix | 1803 | 5 | player_input 4, class_unsupported 1 |
| Airdrift | bhop_pharma | 1986 | 9 | player_input 3, input_unimplemented 3, class_unsupported 3 |
| Airdrift | bhop_pharma | 1986 | 9 | player_input 3, input_unimplemented 3, class_unsupported 3 |
| Airdrift | bhop_pharos_fix | 962 | 13 | player_input 8, input_unimplemented 3, class_unsupported 2 |
| Airdrift | bhop_pharos_fix | 962 | 13 | player_input 8, input_unimplemented 3, class_unsupported 2 |
| Airdrift | bhop_pit | 254 | 3 | player_input 2, input_unimplemented 1 |
| Airdrift | bhop_polyworld | 602 | 1 | player_input 1 |
| Airdrift | bhop_polyworld | 602 | 1 | player_input 1 |
| Airdrift | bhop_psykeeysss | 298 | 0 |  |
| Airdrift | bhop_psykeeysss | 298 | 0 |  |
| Airdrift | bhop_pym | 247 | 4 | player_input 3, input_unimplemented 1 |
| Airdrift | bhop_pym | 247 | 4 | player_input 3, input_unimplemented 1 |
| Airdrift | bhop_relinquished_fixx | 1184 | 2 | player_input 2 |
| Airdrift | bhop_relinquished_fixx | 1184 | 2 | player_input 2 |
| Airdrift | bhop_serenity | 282 | 2 | player_input 1, class_unsupported 1 |
| Airdrift | bhop_serenity | 282 | 2 | player_input 1, class_unsupported 1 |
| Airdrift | bhop_shutdown2 | 1232 | 6 | player_input 4, input_unimplemented 1, class_unsupported 1 |
| Airdrift | bhop_space | 638 | 9 | player_input 5, input_unimplemented 2, class_unsupported 2 |
| Airdrift | bhop_space | 638 | 9 | player_input 5, input_unimplemented 2, class_unsupported 2 |
| Airdrift | bhop_sqee | 1322 | 2 | player_input 2 |
| Airdrift | bhop_strength_v2 | 1574 | 8 | player_input 3, class_unsupported 3, input_unimplemented 2 |
| Airdrift | bhop_strength_v2 | 1574 | 8 | player_input 3, class_unsupported 3, input_unimplemented 2 |
| Airdrift | bhop_supernova | 525 | 2 | player_input 2 |
| Airdrift | bhop_tesquo_v2 | 909 | 7 | player_input 4, input_unimplemented 2, class_unsupported 1 |
| Airdrift | bhop_toroux | 686 | 0 |  |
| Airdrift | bhop_toroux | 686 | 0 |  |
| Airdrift | bhop_training_fun | 118 | 4 | class_unsupported 3, input_unimplemented 1 |
| Airdrift | bhop_training_fun | 118 | 4 | class_unsupported 3, input_unimplemented 1 |
| Airdrift | bhop_tranquility | 1421 | 2 | player_input 2 |
| Airdrift | bhop_tranquility | 1421 | 2 | player_input 2 |
| Airdrift | bhop_tron_evolution | 2194 | 2 | player_input 1, class_unsupported 1 |
| Airdrift | bhop_tron_evolution | 2194 | 2 | player_input 1, class_unsupported 1 |
| Airdrift | bhop_umbra | 1236 | 6 | player_input 4, input_unimplemented 1, class_unsupported 1 |
| Airdrift | bhop_underground_crypt | 1851 | 5 | player_input 2, input_unimplemented 2, class_unsupported 1 |
| Airdrift | bhop_unreality | 126 | 2 | player_input 2 |
| Airdrift | bhop_unreality | 126 | 2 | player_input 2 |
| Airdrift | bhop_woodenspace | 196 | 1 | player_input 1 |
| Airdrift | bunnyhop_pro | 22 | 1 | class_unsupported 1 |
| Airdrift | buses_from_hell_fixed | 175 | 6 | input_unimplemented 3, volume_parented 2, class_unsupported 1 |
| Airdrift | kz_bhop_badg3s | 2142 | 6 | player_input 3, class_unsupported 2, input_unimplemented 1 |
| Airdrift | kz_bhop_deserted | 198 | 3 | player_input 3 |
| Airdrift | kz_bhop_deserted | 198 | 3 | player_input 3 |
| Airdrift | kz_bhop_indiana | 1505 | 12 | input_unimplemented 5, class_unsupported 4, player_input 2, volume_parented 1 |
| Airdrift | kz_bhop_indiana | 1505 | 12 | input_unimplemented 5, class_unsupported 4, player_input 2, volume_parented 1 |
| Airdrift | kz_bhop_lucid | 1318 | 4 | player_input 2, input_unimplemented 1, class_unsupported 1 |
| Airdrift | kz_bhop_skodna | 1070 | 4 | player_input 4 |
| Airdrift | kz_bhop_skodna | 1070 | 4 | player_input 4 |
| Airdrift | kz_bhop_yonkoma | 1517 | 28 | class_unsupported 13, input_unimplemented 9, player_input 5, volume_parented 1 |
| Airdrift | surf_10x_final | 238 | 1 | class_unsupported 1 |
| Airdrift | surf_10x_reloaded_fixed | 324 | 1 | class_unsupported 1 |
| Airdrift | surf_110b_austinpowers | 677 | 13 | volume_parented 9, input_unimplemented 2, class_unsupported 2 |
| Airdrift | surf_29_12_06 | 203 | 2 | input_unimplemented 1, class_unsupported 1 |
| Airdrift | surf_I_Hate_Campers | 243 | 4 | class_unsupported 4 |
| Airdrift | surf_XIV_v2a | 1161 | 15 | class_unsupported 10, input_unimplemented 4, player_input 1 |
| Airdrift | surf_adverse | 523 | 7 | class_unsupported 4, input_unimplemented 2, player_input 1 |
| Airdrift | surf_aim_akcolt | 154 | 1 | input_unimplemented 1 |
| Airdrift | surf_aim_akcolt | 154 | 1 | input_unimplemented 1 |
| Airdrift | surf_akai_final | 425 | 4 | input_unimplemented 2, class_unsupported 2 |
| Airdrift | surf_amplitude_apex | 608 | 11 | input_unimplemented 6, class_unsupported 4, player_input 1 |
| Airdrift | surf_amplitude_apex | 608 | 11 | input_unimplemented 6, class_unsupported 4, player_input 1 |
| Airdrift | surf_amplitude_light | 760 | 8 | input_unimplemented 5, class_unsupported 3 |
| Airdrift | surf_animals | 1119 | 16 | input_unimplemented 9, class_unsupported 4, player_input 2, volume_parented 1 |
| Airdrift | surf_aquaflow | 422 | 2 | player_input 1, input_unimplemented 1 |
| Airdrift | surf_arcade | 1155 | 5 | player_input 2, class_unsupported 2, input_unimplemented 1 |
| Airdrift | surf_bathroom_final | 434 | 9 | input_unimplemented 5, volume_key_unread 3, class_unsupported 1 |
| Airdrift | surf_beginner | 173 | 2 | player_input 1, input_unimplemented 1 |
| Airdrift | surf_beginner2 | 670 | 4 | player_input 3, class_unsupported 1 |
| Airdrift | surf_buck_wild | 666 | 5 | class_unsupported 4, input_unimplemented 1 |
| Airdrift | surf_catalyst | 511 | 22 | input_unimplemented 9, class_unsupported 9, player_input 4 |
| Airdrift | surf_construction | 509 | 12 | input_unimplemented 6, class_unsupported 5, player_input 1 |
| Airdrift | surf_construction | 509 | 12 | input_unimplemented 6, class_unsupported 5, player_input 1 |
| Airdrift | surf_dust2_2008_final | 167 | 7 | class_unsupported 4, input_unimplemented 3 |
| Airdrift | surf_eclipse | 293 | 12 | input_unimplemented 6, class_unsupported 5, player_input 1 |
| Airdrift | surf_ember | 567 | 2 | player_input 1, input_unimplemented 1 |
| Airdrift | surf_ember | 567 | 2 | player_input 1, input_unimplemented 1 |
| Airdrift | surf_exile | 568 | 5 | player_input 2, input_unimplemented 2, class_unsupported 1 |
| Airdrift | surf_exile | 568 | 5 | player_input 2, input_unimplemented 2, class_unsupported 1 |
| Airdrift | surf_fastspiral_retro | 182 | 2 | class_unsupported 2 |
| Airdrift | surf_fastspiral_retro | 182 | 2 | class_unsupported 2 |
| Airdrift | surf_flowing | 244 | 12 | class_unsupported 12 |
| Airdrift | surf_forbidden_ways_2nd | 350 | 5 | class_unsupported 4, input_unimplemented 1 |
| Airdrift | surf_forbidden_ways_reloaded | 1221 | 3 | class_unsupported 3 |
| Airdrift | surf_fruits | 1026 | 6 | class_unsupported 3, input_unimplemented 2, player_input 1 |
| Airdrift | surf_godlike | 173 | 5 | class_unsupported 3, input_unimplemented 2 |
| Airdrift | surf_grave_reloaded | 396 | 1 | class_unsupported 1 |
| Airdrift | surf_greatriver | 217 | 0 |  |
| Airdrift | surf_greatriver_awesome | 218 | 0 |  |
| Airdrift | surf_greatriver_v4 | 468 | 6 | class_unsupported 5, input_unimplemented 1 |
| Airdrift | surf_greatriver_xdre4m | 452 | 13 | class_unsupported 9, input_unimplemented 4 |
| Airdrift | surf_greensway | 197 | 1 | input_unimplemented 1 |
| Airdrift | surf_gurus | 1129 | 8 | input_unimplemented 3, class_unsupported 3, player_input 2 |
| Airdrift | surf_gurus | 1129 | 8 | input_unimplemented 3, class_unsupported 3, player_input 2 |
| Airdrift | surf_interference | 732 | 2 | player_input 2 |
| Airdrift | surf_japan_ptad | 531 | 11 | class_unsupported 7, input_unimplemented 3, player_input 1 |
| Airdrift | surf_japan_reloaded | 496 | 9 | class_unsupported 5, input_unimplemented 4 |
| Airdrift | surf_japan_reloaded | 496 | 9 | class_unsupported 5, input_unimplemented 4 |
| Airdrift | surf_kitsune | 265 | 2 | player_input 2 |
| Airdrift | surf_legends | 372 | 6 | input_unimplemented 3, class_unsupported 2, volume_key_unread 1 |
| Airdrift | surf_life_of_duck | 153 | 1 | player_input 1 |
| Airdrift | surf_lithium | 541 | 9 | input_unimplemented 4, class_unsupported 3, player_input 2 |
| Airdrift | surf_lithium | 541 | 9 | input_unimplemented 4, class_unsupported 3, player_input 2 |
| Airdrift | surf_lithium2 | 682 | 14 | input_unimplemented 5, class_unsupported 5, player_input 4 |
| Airdrift | surf_lithium2 | 682 | 14 | input_unimplemented 5, class_unsupported 5, player_input 4 |
| Airdrift | surf_lore | 691 | 12 | class_unsupported 7, input_unimplemented 4, player_input 1 |
| Airdrift | surf_lt_omnific | 4949 | 24 | input_unimplemented 12, player_input 7, class_unsupported 5 |
| Airdrift | surf_lt_unicorn | 1353 | 25 | input_unimplemented 12, class_unsupported 7, player_input 6 |
| Airdrift | surf_machine2 | 331 | 4 | input_unimplemented 2, class_unsupported 2 |
| Airdrift | surf_machine_remix_final | 475 | 4 | class_unsupported 3, input_unimplemented 1 |
| Airdrift | surf_mai_redone_final2 | 655 | 13 | class_unsupported 8, input_unimplemented 3, player_input 1, volume_parented 1 |
| Airdrift | surf_mai_redone_final2 | 655 | 13 | class_unsupported 8, input_unimplemented 3, player_input 1, volume_parented 1 |
| Airdrift | surf_mai_remix | 258 | 3 | class_unsupported 2, input_unimplemented 1 |
| Airdrift | surf_matrix_v8 | 936 | 4 | input_unimplemented 2, class_unsupported 2 |
| Airdrift | surf_milkyway | 2508 | 4 | player_input 2, input_unimplemented 1, class_unsupported 1 |
| Airdrift | surf_milkyway | 2508 | 4 | player_input 2, input_unimplemented 1, class_unsupported 1 |
| Airdrift | surf_ny_advance | 665 | 8 | input_unimplemented 4, volume_parented 2, player_input 1, class_unsupported 1 |
| Airdrift | surf_ny_bigloop_2008a | 228 | 0 |  |
| Airdrift | surf_ny_exploder_prime | 280 | 1 | class_unsupported 1 |
| Airdrift | surf_ny_exploder_prime | 280 | 1 | class_unsupported 1 |
| Airdrift | surf_omnibus | 703 | 9 | input_unimplemented 4, class_unsupported 3, player_input 2 |
| Airdrift | surf_parrot_selector | 640 | 15 | class_unsupported 9, input_unimplemented 4, player_input 2 |
| Airdrift | surf_pavilion | 1679 | 12 | class_unsupported 6, input_unimplemented 4, volume_parented 2 |
| Airdrift | surf_poolday | 225 | 2 | class_unsupported 2 |
| Airdrift | surf_poolday | 225 | 2 | class_unsupported 2 |
| Airdrift | surf_pox | 255 | 12 | class_unsupported 8, input_unimplemented 4 |
| Airdrift | surf_quilavar | 415 | 2 | player_input 1, input_unimplemented 1 |
| Airdrift | surf_rebel_resistance_final3 | 1475 | 8 | class_unsupported 5, input_unimplemented 3 |
| Airdrift | surf_rocketman_v2 | 461 | 9 | class_unsupported 5, input_unimplemented 3, volume_key_unread 1 |
| Airdrift | surf_rookie | 451 | 2 | player_input 1, class_unsupported 1 |
| Airdrift | surf_ski_2 | 197 | 3 | class_unsupported 2, input_unimplemented 1 |
| Airdrift | surf_ski_2_source | 299 | 3 | player_input 1, input_unimplemented 1, class_unsupported 1 |
| Airdrift | surf_skyworld | 100 | 0 |  |
| Airdrift | surf_snipers_island | 131 | 1 | class_unsupported 1 |
| Airdrift | surf_spectrum | 2528 | 28 | class_unsupported 12, input_unimplemented 8, player_input 7, volume_parented 1 |
| Airdrift | surf_spectrum | 2528 | 28 | class_unsupported 12, input_unimplemented 8, player_input 7, volume_parented 1 |
| Airdrift | surf_stonework3 | 1348 | 2 | player_input 1, input_unimplemented 1 |
| Airdrift | surf_stonework4 | 1529 | 3 | player_input 1, input_unimplemented 1, class_unsupported 1 |
| Airdrift | surf_stonework4 | 1529 | 3 | player_input 1, input_unimplemented 1, class_unsupported 1 |
| Airdrift | surf_summit | 843 | 4 | player_input 3, input_unimplemented 1 |
| Airdrift | surf_the_flow | 82 | 1 | class_unsupported 1 |
| Airdrift | surf_the_gloaming | 416 | 21 | class_unsupported 11, input_unimplemented 8, player_input 1, volume_parented 1 |
| Airdrift | surf_thriller | 247 | 5 | input_unimplemented 4, class_unsupported 1 |
| Airdrift | surf_torque2 | 1391 | 17 | class_unsupported 8, input_unimplemented 4, player_input 3, volume_parented 2 |
| Airdrift | surf_vegetables | 1420 | 10 | input_unimplemented 4, class_unsupported 4, player_input 2 |
| Airdrift | surf_velocity | 1209 | 18 | input_unimplemented 6, class_unsupported 6, player_input 5, volume_parented 1 |
| Airdrift | surf_wazor | 589 | 10 | class_unsupported 4, input_unimplemented 3, volume_parented 2, player_input 1 |
| Airdrift | surf_wazor | 589 | 10 | class_unsupported 4, input_unimplemented 3, volume_parented 2, player_input 1 |
| Airdrift | surf_year3000 | 495 | 9 | input_unimplemented 6, volume_key_unread 2, class_unsupported 2 |
