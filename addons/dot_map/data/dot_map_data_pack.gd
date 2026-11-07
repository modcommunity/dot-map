class_name DotMapDataPack
extends DotMapDataFile

## The bundle shipped inside a map's pack: the layout of [DotMapDataFile] under the pack's mount, read-only.


func _init(p_root: String = "res://map_data") -> void:
	root = p_root


func save(_bundle: DotMapDataBundle, _by: String = "") -> DotResult:
	return DotResult.fail(DotError.CODE_FORBIDDEN, "A pack's map data is read-only.")


func remove(_game: String, _map_id: String, _map_version: String) -> DotResult:
	return DotResult.fail(DotError.CODE_FORBIDDEN, "A pack's map data is read-only.")
