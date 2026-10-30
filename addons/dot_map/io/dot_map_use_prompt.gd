class_name DotMapUsePrompt
extends Label

## The look-at prompt: "[E] Use" while the eye is on something pressable in reach, "Locked" when it is locked, hidden otherwise.

## Text for the use key; a game with a rebound key sets it.
var key_name := "E"


func _init() -> void:
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_theme_font_size_override("font_size", 22)
	add_theme_color_override("font_outline_color", Color.BLACK)
	add_theme_constant_override("outline_size", 6)
	visible = false


## Shows what [method DotMapUse.aim] returned (an empty dictionary hides it). With [param rules] the
## reach is the current [code]sv_use_reach[/code], the server's own test, not the one when [code]info[/code] was made.
func show_aim(info: Dictionary, rules: DotMapUse = null) -> void:
	var label := String(info.get("label", ""))
	var reachable: bool = rules.in_reach(info) if rules != null else bool(info.get("in_range", false))
	visible = not info.is_empty() and reachable and label != ""
	if not visible:
		return
	text = label if info.get("state") == &"locked" else "[%s] %s" % [key_name, label]
	modulate = Color(1, 0.6, 0.5) if info.get("state") == &"locked" else Color.WHITE
