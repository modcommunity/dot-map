# Converter v2: one lossless store, one replacement layer, one entity runtime

Design for the next generation of `tools/bsp` (`dotbsp`). Status: design, 2026-10-23; nothing below is built unless it says so. Package 1 (the store, repeated keys, outputs of any name) is built: `dotbsp/store.py`, `bsp.py store`. The rule it serves: **when an imported map is wrong, fix the converter, the replacement tables or an addon class, then regenerate every map; never patch one map.**

## Why: what today's converter keeps and what it loses

Measured on 2026-10-23 with `bsp.py mesh --coverage` and a scan of every readable map under `~/mapsrc` (105 maps, 295 entity classes, 14,075 output links; 5 files unreadable, all cut-off downloads).

- **Geometry is not the problem.** Both wipeout pilots (`mg_office_coursee`, `mg_dans_course`) convert with drawn and solid coverage 1.0000 and full silhouettes; every class is decided (no `unknown`).
- **Meaning is.** The converter writes records (`movers`, `volumes`, `links`, `breakables`, `entities`) and stops. 99 of the 295 classes are `data`: kept, never run. Each game's adapter then re-decides what a record means, and drops what it has no piece for. Office: 171 links, 11 hurt volumes that start disabled and are switched by a trigger (the timed "lava" room: `OnTrigger` sets a brush red, enables the hurt and the steam, then undoes all three 3 s later and re-arms after 6 s), 33 breakables, 10 ladder volumes. The adapter (`mg-wipeout-maps/tools/import_world.py`) builds hurt volumes only when enabled and at 100+ damage, turns every ladder into a bounce pad, and lists the rest as "not built". The converter had the ladders; no climb was wired.
- **Glass**: surfaces carry a generic id (`glass`) but no surface properties (translucent, alpha-tested, breakable); breakable records have `glass: null`. Nothing tells a builder to draw it see-through or break it.
- **The raw store is lossy in two places**: `reader.parse_entities` keeps only the first value of a repeated non-output key, and `movers.outputs` reads only keys starting with `On`, so outputs named otherwise (`OutValue` on counters, `PressedAttack`, `XAxis`, `PlayerOn` on input-capture entities: 145 links in the scan) are lost. The original `.bsp` itself is not copied into the store, so the store cannot be rebuilt from itself.
- **The class table is built from what our maps happen to use**, so the first map with a new class fails, and nothing checks which keys and inputs of a known class we ignore.

## 1. The lossless store

One directory per source file, outside every repository, keyed by content: `$DOTBSP_STORE` (default `~/mapsrc/store`) `/<sha256>/`. A name index `~/mapsrc/store/index.json` maps `<game>/<map id>` to the hash; the existing `~/mapsrc/<game>/raw/<map>/` directories become links into it. Today's sources total 11.6 GB, most of it packed author art.

| File | Holds |
| --- | --- |
| `source.bsp` | the original file, byte for byte (or the archive member it came from); everything else can be rebuilt from it |
| `credit.json` | author(s), page URL, licence text as published, the date and wording of the no-share check, the download URL and archive member, removal-on-request contact, which games ship it, the first import date. Required: `regen` refuses a map without author and page |
| `doc.json` | the **source document**: the decompiled map with nothing replaced (below) |
| `mesh.json`, `mesh.bin` | the drawn faces and hulls with source texture names (today's `mesh`), derived from `doc.json` and `source.bsp` |
| `census.json`, `pak.txt`, `pak/` | texture and model counts, the packed file list, the packed text files (materials, sound scripts) |

The source document (`dot-bsp-source`, version 1) is the editor-level map, as far as a compiled file can give it back:

- **entities** in file order, each an ordered list of `[key, value]` pairs exactly as written (repeats kept), plus parsed `outputs` for every key whose value has the five-field output shape, whatever the key is called; `targetname`, `parentname` and `classname` lifted out for indexing.
- **brushes** with every side (plane, texture name, texture axes and scale, contents, surface flags), the owning model, and the brush entity they belong to; **displacements** with power, vertices, alphas and flags; **static props** with every field of the record (model, origin, angles, skin, solidity, fade, lighting origin, scale where the version has it); **overlays** and decals with their material and projection; **cubemap probes**, **world lights** as compiled, **visibility clusters** only as a count.
- **texture references**: every material name, its packed `.vmt` text when the map packs one, otherwise the base game's material record (section 2).
- **models and sounds**: every path the map names, with where it is named.
- **navigation and spawns**: spawn entities, ladders, info nodes and hints, kept as entities; nothing is inferred here.

Nothing in the store is replaced, filtered or rounded beyond the file's own precision. `bsp.py store <file|dir>` writes it; `bsp.py store --check` rebuilds `doc.json` from `source.bsp` and compares. A store entry never enters a repository or a pack; it is the author's work, kept only so a map can be regenerated.

## 2. The replacement layer

Every shipped map is `regen(store entry, rules) -> manifest + coverage`. Rules are tables, read in three tiers with the family's layering: dot-map's defaults (`tools/bsp/rules/`), the game's (`<maps repo>/tools/convert/`), and the map's (`<maps repo>/tools/convert/maps/<id>.json`, for the rare map-specific fact such as which trigger is a finish line). A later tier overrides a row by key; nothing else is per map.

| Table | Key | Gives | Default for an unmapped key |
| --- | --- | --- | --- |
| `textures.tsv` (today's `source_textures.tsv` + `free_textures.tsv`) | texture name glob | generic id, tint, free replacement | `nearest.py`: by name, then by average colour, then a flat image in the original's colour |
| `materials.tsv` (new) | texture name glob or generic id | **surface properties**: `opaque`, `alpha_test`, `translucent` (with alpha), `additive`, `two_sided`, `emissive`, `water`, `sky`, `nodraw`, `glass` (see-through, breakable when its entity is), footstep and impact surface (dot-physics `DotPhysicsSurface` name), friction | derived from the material record: `$translucent`, `$alphatest`, `$additive`, `$nocull`, `$selfillum`, `%compilewater`, `$surfaceprop`; with no record, from the generic id (`glass` is translucent) |
| `models.tsv` (today's `free_models.tsv` + a game's `PropTable`) | model path glob | stand-in glb, scale, collision (`hull`, `box`, `none`), physics (`static`, `rigid`, mass), breakable (health, gib set) | a box the size of the model's recorded bounds, solid as the source said, coloured from the census |
| `sounds.tsv` (today's `free_sounds.tsv`) | sound path or sound-script name | stand-in id, volume, radius | a short neutral stand-in of the same kind (loop or one-shot), never silence unless the row says so; music and voice stay silent by rule |
| `classes.tsv` (today's `classes.py` rows) | entity class | treatment, the runtime component (section 3), which keys it consumes, which inputs it implements | `DotMapEntity`: kept, placed, every input recorded and reported as unimplemented, every output still fired when its generic triggers happen |
| `roles.tsv` (new, game tier) | class plus key match | what the game calls it: spawn of a team, start or finish zone, checkpoint, prop spawner, weapon pickup | none: unclaimed spawns stay generic spawns |

**The coverage report** (`<prefix>.coverage.json`, beside the manifest, and printed) lists per map: textures, models and sounds that fell to a default; classes with no component; for each class the keys present in the map that its component does not consume; inputs targeted at an entity whose component does not implement them; outputs whose trigger the component never raises; unresolved link targets; and counts of each. It is committed with the map. `regen --ratchet` fails when any count rises against the committed report, so a rule change can only shrink what is missing. Fallbacks make sure nothing is silently dropped: every entity in the source either has a component or is a `DotMapEntity` in the report.

**The class catalogue is generated, not surveyed.** The source engine's entity definitions exist in two forms: the editor's entity-definition files (`.fgd`: class, base classes, keys with type, default and choices, inputs, outputs) and a running server's datamap dump (every class the server can create, each field flagged key, input or output). `tools/bsp/defs/build.py` reads both from outside the repository (`$DOTBSP_DEFS`, default `~/mapsrc/defs`) and writes `tools/bsp/rules/entity_defs.json`: class names, key names with type and default, input and output names, nothing else. Coverage is measured against that full list, so a class no map has used yet still has its keys, inputs and defaults known; `classes.tsv` only says which component implements it. The definition files fetched for this (a community-maintained unified set) carry no licence, which is why only the derived names, types and defaults are committed.

## 3. The entity-class library

Ranked by the number of maps (of 105) that use each class; entity counts after the slash. Components live where the family already owns the subject; dot-map keeps everything that needs only dot-core, and reaches bodies, damage and effects through callables a game assigns (section 4), never by naming another addon.

| Class (maps/entities) | Component | Owner | Exists? |
| --- | --- | --- | --- |
| `worldspawn` 105, `func_detail`, `func_wall`, `func_lod`, `func_monitor` | `DotMapBspMesh` world surfaces and hulls | dot-map | yes |
| `light` 96/7552, `light_spot` 56, `light_environment` 84, `env_sun`, `shadow_control`, `light_dynamic` | `DotMapBspMesh.build_lights` from `lights.py` records; `light_dynamic` and named lights get `DotMapLight` (TurnOn/TurnOff/Toggle) | dot-map | records yes, inputs no |
| `func_breakable` 84/2705, `func_breakable_surf` 13/112, `func_physbox` 50, `func_physbox_multiplayer` | `DotMapBreakable`: health, material (glass, wood, metal...), Break/SetHealth/AddHealth, OnBreak/OnHealthChanged, glass shatter to free gibs, damage arrives through the game's damage callable | dot-map (gibs: dot-props `DotPropPieces`) | no |
| `ambient_generic` 82/1138, `env_soundscape*` 29 | `DotMapSound`: PlaySound/StopSound/ToggleSound/Volume/Pitch on `build_sounds`' stand-in | dot-map (playback through dot-audio by callable) | records yes, inputs no |
| `func_button` 79/1161, `func_rot_button`, `momentary_rot_button` | `DotMapMoverNode` (button kinds): use and touch press, Lock/Unlock/Press, OnPressed/OnUseLocked/OnIn/OnOut | dot-map | record `DotMapMover` yes, node no |
| `func_door` 67/1041, `func_door_rotating` 53, `prop_door_rotating` 34, `func_movelinear` 25, `func_plat` | `DotMapMoverNode`: Open/Close/Toggle/Lock/Unlock/SetSpeed/SetPosition, OnOpen/OnClose/OnFullyOpen/OnFullyClosed, blocked damage | dot-map | record yes |
| `func_rotating` 57/386 | `DotMapMoverNode` (spin): Start/Stop/Toggle/SetSpeed/Reverse | dot-map | record yes |
| `func_tracktrain` 38, `func_train`, `func_tanktrain`, `path_track` 42/711 | `DotMapMoverNode` (path): StartForward/StartBackward/Stop/SetSpeed/TeleportToPathTrack, path_track OnPass | dot-map | record yes |
| `water_lod_control` 74, `env_fog_controller` 36, `env_tonemap_controller`, `color_correction`, `sky_camera` 43 | `DotMapBspMesh.build_environment` | dot-map | yes |
| spawns: `info_player_*` (team, start, deathmatch, game-specific) 68+65+50 | `roles.tsv` to dot-spawn points | dot-spawn (game role) | spawns yes, roles no |
| `prop_dynamic` 66/1757, `prop_dynamic_override` 35 | `DotMapProp` (dynamic): stand-in, Enable/Disable/SetAnimation (no animation: logged)/Skin/Color/Kill | dot-map | placement yes |
| `prop_physics` 64/7903, `_multiplayer` 42/3958, `_override` 49/2528, `prop_ragdoll` 12 | `DotMapProp` (physics): a dot-props `DotPropInstance` when the game links dot-props, else static; breakable from `models.tsv` | dot-props (via a game callable) | partly (dot-props) |
| `infodecal` 65/4072, overlays | decals with replaced materials | dot-map | data only |
| `trigger_hurt` 63/1409 | `DotMapVolumeNode` (hurt): Enable/Disable/Toggle/SetDamage, damage per second through the damage callable, OnHurt | dot-map | record `DotMapVolume` yes, node no |
| `trigger_teleport` 58/667, `info_teleport_destination` 48, `info_target` 48 | `DotMapVolumeNode` (teleport), landmark, Enable/Disable | dot-map | record yes |
| `trigger_multiple` 53/414, `trigger_once` 47/430 | `DotMapVolumeNode` (touch): OnStartTouch/OnEndTouch/OnTrigger/OnStartTouchAll/OnEndTouchAll, `wait`, filters, Enable/Disable/Toggle | dot-map | record yes |
| `trigger_push` 51/349 | `DotMapVolumeNode` (push) via the body callable | dot-map | `push_velocity()` yes |
| `func_illusionary` 53/829 | drawn surfaces, never solid | dot-map | yes |
| `logic_auto` 52/84 | `DotMapIO` map-start outputs (OnMapSpawn, OnNewGame, OnMultiNewRound) | dot-map | no |
| `env_sprite` 46, `env_spritetrail` 29, `env_lightglow`, `point_spotlight` 41, `env_laser` 27, `env_beam`, `env_spark` 34, `env_steam` 28, `env_fire` 29, `env_smokestack` 17, `env_explosion` 35, `env_shake` 20, `env_fade` 14, `info_particle_system` 7 | `DotMapEffect`: one node per record, its inputs (ShowSprite/HideSprite, TurnOn/TurnOff, StartFire/Extinguish, Explode, StartShake, Fade, SparkOnce), drawn by a game-assigned effect callable; explosions and fire also hurt through the damage callable | dot-map (look: dot-fx `DotFxCatalogue`) | no |
| `func_brush` 45/846, `func_wall_toggle` 15/238 | `DotMapToggleBrush`: Enable/Disable/Toggle (drawn and solid), Color, Alpha, SetSolid | dot-map | no |
| `info_ladder` 45/283, `func_ladder`, `func_useableladder` 4 | ladder volumes handed to dot-player-controller's `DotFpsLadderMode.volumes` | dot-player-controller | climb yes, wiring no |
| `logic_timer` 44/139, `logic_relay` 29/143, `logic_case` 26/121, `math_counter` 23/99, `logic_compare` 15, `logic_branch` 8, `math_colorblend`, `logic_measure_movement` 2, `env_global` | `DotMapLogic` classes on `DotMapIO` (section 4) | dot-map | no |
| `point_template` 37/402, `env_entity_maker` 12 | `DotMapTemplate`: ForceSpawn re-creates its templated entities (fresh names per spawn when the template says so) | dot-map | no |
| `move_rope` 36, `keyframe_rope` 22 | `DotMapRope`: a drawn sagging line between its points | dot-map | no |
| `filter_activator_name` 16, `filter_activator_team` 24, `filter_damage_type` 8, other `filter_*` | `DotMapFilter`, asked by volumes and breakables; team through the game's team callable (dot-team) | dot-map | no |
| `func_water_analog` 16, `func_water` | `water` volumes to `DotFpsSwimMode` | dot-player-controller | swim yes, wiring no |
| `trigger_gravity` 5, `player_speedmod` 19 | body modifiers through the body callable (dot-player-controller `DotFpsModifier`) | dot-player-controller | modifier yes, wiring no |
| `point_viewcontrol` 26, `point_camera` 10, `func_monitor` | `DotMapCamera` through dot-core's `DotCameraProbe`; Enable/Disable hands the view over | dot-map | no |
| `game_text` 10, `env_hudhint` 8, `game_score` 12, `game_player_equip` 29, `player_weaponstrip` 7 | game-facing events through the game's event callable (text, hint, score, equip, strip) | dot-map (meaning: the game) | no |
| `point_servercommand` 31/42, `point_clientcommand` 2 | `DotMapCommand`: `say` becomes a chat or HUD line; `sv_*`/`mp_*` commands go through an allow-list of cvars the game has adopted; anything else is reported, never executed | dot-map | no (dropped today) |
| `game_ui` 10, `prop_vehicle_*` | input capture (its non-`On` outputs) through the body callable; vehicles stay props | dot-map | no |
| `phys_thruster` 14, `phys_hinge` 10, `phys_ballsocket`, other `phys_*` constraints | constraints on dot-props bodies | dot-props | no; reported |
| `func_reflective_glass` 10 | glass with the reflective flag from `materials.tsv` | dot-map | no |
| `env_cubemap`, `env_projectedtexture`, `env_wind`, `func_precipitation` 7 | environment probes, a spot light, weather through dot-fx `DotFxWeather` | dot-map, dot-fx | partly |
| `info_node*`, `info_hint`, `info_node_link` 17 | navigation hints for dot-npc's `DotNpcNavBuilder` | dot-npc | no; kept as data |
| `weapon_*`, `item_*` (60+ classes, long tail) | `roles.tsv` to the game's pickups (dot-loadout / dot-inventory); unknown ones become a generic pickup marker | the game, via dot-loadout | no |
| `npc_*`, `*_maker`, `scripted_*`, `ai_*` | dot-npc spawners when a game links dot-npc; otherwise reported | dot-npc | no |
| `func_areaportal*`, `func_occluder`, `func_dustmotes`, `func_smokevolume`, `env_embers`, `env_bubbles`, `func_buyzone`, `func_bomb_target`, `hostage_*`, `trigger_autosave` | dropped with the reason in the row (visibility hints, a mode's own objectives); still listed in coverage | none | dropped |
| `lua_run` 4/71 (inputs `RunCode` 79) | not run: a script host is not a converter; reported per map with its code, for a person to port to a class | none | reported |

The long tail (88 classes appear in one map only) is covered by prefix rows (`weapon_`, `item_`, `npc_`, `info_player_`) and by the `DotMapEntity` fallback; each still shows in the coverage report until a row claims it. `bsp.py classes --markdown` keeps writing the full ranked table to `tools/bsp/docs/entity-classes.md`, with a component column added.

## 4. The I/O runtime

`addons/dot_map/io/`, dot-core only, server-authoritative and deterministic.

- **`DotMapIO`** owns one queue of pending input events `(due_tick, sequence, target, input, param, activator, caller)`, advanced from the game's authoritative tick (`advance(ticks)`), never from wall time or `Timer` nodes, so a replay or a server at another tick rate gives the same order. Ties go by insertion order. A link's `delay` becomes `due_tick = now + round(delay * rate)`; `times` counts down per link and the link is removed at zero.
- **`DotMapEntity`** is every runtime entity's base: `targetname`, `keys`, its links, `fire(output, activator, param)`, and `accept(input, param, activator, caller)` with the inputs every class has: `Kill`, `KillHierarchy`, `AddOutput` (both the key form and the output form), `FireUser1..4` to `OnUser1..4`, `Enable`/`Disable` where the class has a state, `SetParent`/`ClearParent` (moves with a mover). Names resolve case-insensitively, `*` wildcards included; `!activator`, `!caller`, `!self`, `!player` resolve at fire time. An input a class does not implement is counted in the runtime coverage (`DotMapIO.unhandled()`), never an error.
- **Logic classes**: `logic_relay` (Trigger, Enable/Disable, Toggle, CancelPending, OnTrigger, fire-once flag), `logic_timer` (RefireTime, random interval, Enable/Disable/Toggle, FireTimer, ResetTimer, OnTimer/OnTimerHigh/OnTimerLow), `math_counter` (Add/Subtract/SetValue/SetValueNoFire/GetValue, OnHitMin/OnHitMax/OutValue/OnGetValue), `logic_case` (InValue, PickRandom, PickRandomShuffle, OnCase01..16, OnDefault), `logic_compare`, `logic_branch`, `logic_auto`. `CancelPending` removes the queued events a relay produced, which a timed sequence needs.
- **State changes are replicated, logic is not**: the authority runs the queue; what clients need (a brush shown or hidden or recoloured, a mover's target fraction and start tick, a breakable broken, an effect on or off, a sound started) goes out as small state records through the same kind of `send_fn` `DotMapSyncHost` uses, with a full snapshot for a joiner. Clients run no logic.
- **The game's side is four callables**, assigned, never subclassed: `damage(body, amount, kind, attacker)`, `move_body(body, velocity | transform)` (push, teleport, speed and gravity scales), `effect(kind, record, on)` and `event(kind, data)` (text, hint, score, equip, chat, command). A game without one gets a logged no-op and a coverage line.

The Office lava room is then data and nothing else: the trigger's eight timed links run on the queue, the hurt volume is enabled from 3 s to 6 s after entry, the brush turns red and back, the steam effect toggles, and the trigger re-arms. Doors (button `OnPressed` to `Open`, `wait`, `OnFullyOpen` to a relay), breakables (`Break` from a counter's `OnHitMax`), spawn-camping guards (`logic_auto` enabling a hurt after 20 s) and random routes (`logic_case PickRandom` enabling one of three paths) are the same mechanism.

## 5. Migration plan

One builder, one repository per package, in order. Each "done when" includes the regenerated maps and their committed coverage reports; a package that changes shipped output re-renders one map (`tools/screenshot.sh`) and looks at it.

| # | Repo | Scope | Done when |
| --- | --- | --- | --- |
| 1 | dot-map | Lossless store (section 1): `source.bsp` copy, `credit.json`, `doc.json` with ordered key pairs and outputs of any key name; `bsp.py store` and `store --check`; `raw/` becomes links; fix the two parser losses | every readable map under `~/mapsrc` stored; `store --check` clean on all; a test that the scan's 145 non-`On` links and repeated keys survive; `test_licence.py`, `test_mesh.py` pass |
| 2 | dot-map | Definition catalogue: `tools/bsp/defs/build.py` from the definition files and the datamap dump outside the repo, committed `rules/entity_defs.json`; `classes.tsv` with a component column; `bsp.py classes` reports keys and inputs per class against it | every class in the 105 maps found in the catalogue or listed; regenerated `entity-classes.md` |
| 3 | dot-map | Replacement layer: the rule tiers, `regen <store hash or game> --out`, `materials.tsv` and `roles.tsv` empty but read, the coverage report and `--ratchet` | zombie-zone-maps' 35 maps regenerate identical to today's `ship()` output apart from the new coverage files |
| 4 | dot-map | Surface properties: material records from packed `.vmt` and the base material index, `materials.tsv` defaults, `DotMapBspMesh` building translucent, alpha-tested, additive and two-sided materials; glass flags on breakables | Office's and Dan's glass renders see-through in a screenshot; coverage lists no glass surface as opaque |
| 5 | dot-map | `DotMapIO`, `DotMapEntity`, the logic classes, `CancelPending`, the four callables; a headless suite on Office's real links | the suite asserts the lava room's timeline tick by tick, a counter-to-break chain and a random route pick; check-only pass clean |
| 6 | dot-map | `DotMapToggleBrush`, `DotMapBreakable` (glass shatter, free gibs), `DotMapMoverNode` driving the existing `DotMapMover` records from inputs, and state replication to clients | a two-peer suite: a client sees the door open, the brush turn red and the glass break at the authority's tick |
| 7 | dot-map | `DotMapVolumeNode` (touch, hurt, push, teleport, gravity, water, ladder) with filters; `ladder_boxes()` and `water_boxes()` for dot-player-controller's modes; `DotMapEffect`, `DotMapSound` inputs, `DotMapCommand` allow-list, `DotMapTemplate` | suites on Dan's ladders (a body climbs the volume) and Office's hurt and teleport volumes |
| 8 | dot-map | `DotMapWorld`: one call builds mesh, environment, sounds, props, entities and the I/O runtime from a manifest with the game's callables; `examples/bsp_world_shot.tscn` uses it | the world shot of Office shows glass, lights and props; the runtime suite runs Office for 60 simulated seconds with no unhandled input it has a row for |
| 9 | mg-wipeout | Build courses from `DotMapWorld`: the four callables, ladders through `DotFpsLadderMode`, start and finish zones from `roles.tsv` matches instead of hand coordinates | Office and Dan's play through `./game.sh --no-parse test`, a bot trace finishes both, the lava room hurts only during its window |
| 10 | mg-wipeout-maps | Replace `tools/import_world.py`'s piece mapping with `regen`; the game tier of rules (roles, finish triggers); regenerate Office and Dan's | both regenerate with no hand edits and committed coverage; then the seven other community courses with a source under `~/mapsrc/wipeout` go to the conversion fleet, one builder each, replacing their `tools/build.py` stand-ins |
| 11 | zombie-zone-maps (then game-zombie-zone) | Adapter on `regen`; barricades read `DotMapBreakable`; 35 maps regenerated | the game's `headless_maps` passes on all; coverage committed |
| 12 | murder-mystery-maps | Same | regenerated maps pass the game's suites |
| 13 | mg-prop-hunt-maps | Same; deletes its `bsp_read.py` and local tables | as above |
| 14 | hide-n-seek-maps | Same | as above |
| 15 | mg-deathrun-maps | Traps from buttons, relays and movers run by `DotMapIO` instead of `bsp_to_course.py`'s own logic; hull scale kept | every course regenerated; a trap fires in the game's suite |
| 16 | game-playground-maps | Same | as above |
| 17 | game-g2gfast | Last: its own mesh and lightmap importer moves onto the store and `regen`, keeping baked light | the shipped maps import byte-identical in geometry, `headless_imported` passes |

Packages 1 to 8 are sequential in dot-map; 9 and 10 need 8; 11 to 17 need 8 and can run two at a time.

## Data still wanted from a running server

Dumped from a test server of each source game by a server plugin, stored under `~/mapsrc/defs/` (internal, never committed):

- the material and surface tables: the surface-properties scripts (every surface name with friction, elasticity, density, and impact and step sounds) and the prop data script (breakable model classes: health, gib counts, explosive damage);
- the text of every base-game material (`.vmt`) the scanned maps reference, or a dump of each one's `$basetexture`, `$translucent`, `$alphatest`, `$additive`, `$nocull`, `$surfaceprop`, and the average colour of its base texture;
- for every model path the maps name: bounds, collision hull size, `$surfaceprop`, the model's prop-data keys (health, gibs, physics mass), skins and body groups;
- the sound scripts (script name to files, volume, pitch, attenuation) and the soundscape scripts;
- a golden trace: every I/O event fired, with tick, caller, target, input and parameter, during 60 s on Office and on one deathrun map with a player walking the course, to check `DotMapIO` against.
