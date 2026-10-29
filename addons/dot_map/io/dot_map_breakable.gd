class_name DotMapBreakable
extends DotMapEntity

## func_breakable, func_breakable_surf and a breakable prop_physics: health, damage from the game ([method
## DotMapIO.hurt]), and a break that fires OnBreak, hides the model and lets it go.

const MATERIALS: PackedStringArray = ["glass", "wood", "metal", "flesh", "concrete", "tile", "computer",
		"unbreakable_glass", "rock", "web"]

var health := 0.0
var max_health := 0.0
var broken := false
## Source's material number as a name; [code]unbreakable_glass[/code] takes no damage.
var material := "glass"
## Damage under this is ignored (minhealthdmg).
var min_damage := 0.0
## Set by the game when the break is its own to render ([code]effect(kind, entity, on)[/code] still fires).
var glass: DotMapGlass = null

var _damage_blocked := false


func _configure() -> void:
	var mi := int(key_float("material"))
	material = MATERIALS[mi] if mi >= 0 and mi < MATERIALS.size() else "glass"
	health = key_float("health")
	if classname.to_lower() == "func_breakable_surf" and health <= 0.0:
		health = 1.0
	max_health = health
	min_damage = key_float("minhealthdmg")
	_damage_blocked = has_spawnflag(1) or material == "unbreakable_glass"


## Takes a manifest [code]breakables[/code] record: its health (the map's, else 1) and material.
func set_record(rec: Dictionary) -> void:
	if key("health").is_empty() or key_float("health") <= 0.0:
		health = float(rec.get("health", health))
		max_health = health
	if rec.get("material") != null and key("material").is_empty():
		var mi := int(rec["material"])
		material = MATERIALS[mi] if mi >= 0 and mi < MATERIALS.size() else material
	_damage_blocked = has_spawnflag(1) or material == "unbreakable_glass"


## Reads health and material for a prop from the game's model table ([code]{health, material}[/code]).
func set_propdata(data: Dictionary) -> void:
	if key_float("health") <= 0.0 and float(data.get("health", 0.0)) > 0.0:
		health = float(data["health"])
		max_health = health
	if data.has("material"):
		material = str(data["material"])


func on_map_spawn(io: DotMapIO) -> void:
	if io.propdata_fn.is_valid() and classname.to_lower().begins_with("prop_physics") and not key("model").is_empty():
		var d: Variant = io.propdata_fn.call(key("model"))
		if d is Dictionary:
			set_propdata(d)


## Whether damage can break it at all.
func is_breakable() -> bool:
	return alive and not broken and health > 0.0 and not _damage_blocked


## Damage from the game; the authority only. Returns true when it broke.
func hurt(io: DotMapIO, amount: float, at: Vector3 = Vector3.ZERO, by: Variant = null) -> bool:
	if not io.authoritative or not is_breakable() or amount <= 0.0 or amount < min_damage:
		return false
	health -= amount
	fire(io, "OnTakeDamage", by)
	if health <= 0.0:
		health = 0.0
		_break(io, by, at)
		return true
	fire(io, "OnHealthChanged", by, str(health))
	io.report_state(self, "health", health)
	return false


func _input(io: DotMapIO, name: String, param: String, activator: Variant, _caller: Variant) -> bool:
	match name:
		"break", "shatter":
			_break(io, activator, Vector3.ZERO)
		"sethealth":
			health = maxf(param.to_float(), 0.0)
			max_health = maxf(max_health, health)
			fire(io, "OnHealthChanged", activator, str(health))
			io.report_state(self, "health", health)
			if health <= 0.0 and not broken:
				_break(io, activator, Vector3.ZERO)
		"addhealth":
			health += param.to_float()
			fire(io, "OnHealthChanged", activator, str(health))
			io.report_state(self, "health", health)
		"removehealth":
			hurt(io, param.to_float(), Vector3.ZERO, activator)
		"enable":
			_damage_blocked = false
			return true
		"disable":
			_damage_blocked = true
			return true
		_:
			return false
	return true


func _break(io: DotMapIO, by: Variant, at: Vector3) -> void:
	if broken:
		return
	broken = true
	health = 0.0
	fire(io, "OnBreak", by)
	var drop := int(key_float("spawnobject"))
	if drop > 0:
		io.event("spawn_object", {"entity": index, "name": targetname, "object": drop, "at": at})
	io.report_state(self, "broken", true)
	io.effect("break", self, true)
	io.kill(self)


func _apply(_io: DotMapIO, key_: String, value: Variant, _tick: int) -> bool:
	match key_:
		"health":
			health = float(value)
		"broken":
			broken = bool(value)
		_:
			return false
	return true


func _bound() -> void:
	if glass != null:
		glass.authoritative = false


func _view_changed(key_: String, value: Variant) -> void:
	if key_ == "broken" and bool(value):
		if glass != null:
			glass.apply_broken(node.global_position if node != null and node.is_inside_tree() else Vector3.ZERO)
		if node != null:
			set_active(node, false)
		return
	super._view_changed(key_, value)


func state() -> Dictionary:
	var s := super.state()
	s["health"] = health
	s["broken"] = broken
	return s
