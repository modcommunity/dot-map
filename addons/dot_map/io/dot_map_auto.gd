class_name DotMapAuto
extends DotMapEntity

## logic_auto: fires its map-start outputs once, when the runtime starts.


func on_map_spawn(io: RefCounted) -> void:
	for o in ["OnMapSpawn", "OnNewGame", "OnMultiNewRound"]:
		fire(io, o, null)
