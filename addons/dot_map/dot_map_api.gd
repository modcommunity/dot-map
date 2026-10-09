extends RefCounted

## dot-map's API level. The rule for bumping it is on [DotAddonApi].
##
## LEVEL rises by one for anything a game could call that did not exist before. OLDEST is
## raised to LEVEL when something a game could have called is removed or changes meaning,
## because every pack built before that no longer compiles against this addon.

# 1: everything before this file existed (absent means 1).
# 2: DotMapDef.from_content_key and DotMapCatalogue.add_delivered.
# 3: a relative scene given to either is resolved onto the pack's mount.
const LEVEL := 3
const OLDEST := 1
