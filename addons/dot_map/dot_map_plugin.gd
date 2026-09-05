@tool
extends EditorPlugin

## Editor entry point for dot-map. Registers inspector types only.
##
## No autoloads. A map session is the clearest case for it after the controller: a
## server switching maps and a replay viewer showing an old one are two sessions in
## one process, and a singleton makes the second impossible.

const _ICON := "res://addons/dot_map/icon_placeholder.svg"

const _TYPES := [
	[
		"DotMapSession",
		"Node",
		"res://addons/dot_map/runtime/dot_map_session.gd",
	],
	[
		"DotMapSyncHost",
		"Node",
		"res://addons/dot_map/net/dot_map_sync_host.gd",
	],
	[
		"DotMapSyncClient",
		"Node",
		"res://addons/dot_map/net/dot_map_sync_client.gd",
	],
]


func _enter_tree() -> void:
	var icon: Texture2D = null
	if ResourceLoader.exists(_ICON):
		icon = load(_ICON) as Texture2D

	for entry in _TYPES:
		add_custom_type(entry[0], entry[1], load(entry[2]), icon)


func _exit_tree() -> void:
	for i in range(_TYPES.size() - 1, -1, -1):
		remove_custom_type(_TYPES[i][0])
