class_name DotMapColorBlend
extends DotMapEntity

## math_colorblend: InValue between inmin and inmax mixes colormin to colormax and fires OutColor.

var out_color := Color.BLACK


func _input(io: DotMapIO, name: String, param: String, activator: Variant, _caller: Variant) -> bool:
	if name != "invalue":
		return false
	if not enabled:
		return true
	var lo := key_float("inmin", 0.0)
	var hi := key_float("inmax", 1.0)
	var t := 0.0 if is_equal_approx(lo, hi) else clampf((param.to_float() - lo) / (hi - lo), 0.0, 1.0)
	var a := _rgb(key("colormin", "0 0 0"))
	var b := _rgb(key("colormax", "255 255 255"))
	out_color = a.lerp(b, t)
	var text := "%d %d %d" % [roundi(out_color.r * 255.0), roundi(out_color.g * 255.0), roundi(out_color.b * 255.0)]
	io.report_state(self, "out_color", text)
	fire(io, "OutColor", activator, text)
	return true


func _rgb(text: String) -> Color:
	var p := text.split_floats(" ", false)
	if p.size() < 3:
		return Color.BLACK
	return Color(p[0] / 255.0, p[1] / 255.0, p[2] / 255.0)
