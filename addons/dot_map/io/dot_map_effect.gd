class_name DotMapEffect
extends DotMapEntity

## The env_* effects (sprite, trail, glow, spotlight, laser, beam, spark, steam, fire, smoke stack,
## explosion, shake, fade, particle system).

const ONE_SHOT := ["env_explosion", "env_shake", "env_fade", "env_spark", "env_screenoverlay"]

var effect_kind := ""


func _configure() -> void:
	effect_kind = classname.to_lower().trim_prefix("env_")
	if effect_kind == "info_particle_system":
		effect_kind = "particles"


func on_map_spawn(io: DotMapIO) -> void:
	if not ONE_SHOT.has(classname.to_lower()):
		io.effect(effect_kind, self, enabled)


func _enabled_changed(io: DotMapIO, on: bool) -> void:
	io.effect(effect_kind, self, on)


func _input(io: DotMapIO, name: String, _param: String, activator: Variant, _caller: Variant) -> bool:
	match name:
		"showsprite", "start", "startfire", "startspark", "turnon", "enable", "startsteam", "startbeam":
			if not ONE_SHOT.has(classname.to_lower()):
				set_enabled(io, true)
				return true
			return false
		"hidesprite", "stop", "extinguish", "stopspark", "turnoff", "disable", "stopsteam", "stopbeam":
			if not ONE_SHOT.has(classname.to_lower()):
				set_enabled(io, false)
				return true
			return false
		"togglesprite", "togglespark":
			set_enabled(io, not enabled)
			return true
		"explode":
			_explode(io, activator)
			return true
		"startshake", "fade", "sparkonce", "startoverlays":
			io.event(effect_kind if name != "startshake" else "shake", _data(io))
			return true
		"stopshake":
			io.event("shake_stop", _data(io))
			return true
	return false


func _data(io: DotMapIO) -> Dictionary:
	return {"entity": index, "name": targetname, "origin": origin(io), "keys": keys}


func _explode(io: DotMapIO, activator: Variant) -> void:
	var magnitude := key_float("imagnitude", 100.0)
	var data := _data(io)
	data["magnitude"] = magnitude
	io.event("explosion", data)
	io.effect("explosion", self, true)
	if has_spawnflag(1) or magnitude <= 0.0:
		return
	var radius_units := key_float("iradiusoverride", 0.0)
	if radius_units <= 0.0:
		radius_units = magnitude * 2.5
	io.area_damage.append({"origin": origin(io), "radius": radius_units * io.unit_scale, "amount": magnitude,
			"kind": "blast", "source": self, "activator": activator})
