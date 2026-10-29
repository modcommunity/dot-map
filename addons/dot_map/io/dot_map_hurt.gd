class_name DotMapHurt
extends DotMapEntity

## trigger_hurt: while a body is inside an enabled volume, every [code]hurtrate[/code] seconds (0.5) it takes
## [code]damage[/code] a second times that, through [member DotMapIO.damage_fn]. The first hit lands on
## entry.

## Damage type bit (source engine values) to the kind passed to the game.
const KINDS := {1: "crush", 2: "bullet", 4: "slash", 8: "burn", 16: "vehicle", 32: "fall", 64: "blast",
		128: "club", 256: "shock", 512: "sonic", 1024: "energybeam", 16384: "drown", 32768: "paralyze",
		65536: "nervegas", 131072: "poison", 262144: "radiation", 1048576: "acid", 2097152: "slowburn"}

## A spawnflag bit that means "hurt once"; stays 0: no stored map has such a bit (docs/io.md), and
## bit 8 is the base trigger's "physics objects". [code]damageonce[/code] 1 is what turns it on.
static var once_flag := 0

## Damage per second.
var damage := 10.0
var period := 0.5
var cap := 20.0
var model := 0
var kind := "generic"
var once := false
## Push of each hit in metres a second (Godot axes); zero for none.
var force := Vector3.ZERO

var _touching: Dictionary = {}
var _hits: Dictionary = {}
var _gen := 0
var _thinking := false


func _configure() -> void:
	damage = key_float("damage", 10.0)
	period = maxf(key_float("hurtrate", 0.5), 0.05)
	cap = key_float("damagecap", 20.0)
	model = int(key_float("damagemodel", 0.0))
	once = key_float("damageonce") != 0.0 or (once_flag != 0 and has_spawnflag(once_flag))
	force = Vector3.ZERO
	var f := key("damageforce").split_floats(" ", false)
	if f.size() >= 3 and not flag("nodmgforce"):
		force = to_godot_dir(Vector3(f[0], f[1], f[2])) * 0.0254
	var bits := int(key_float("damagetype", 0.0))
	kind = "generic"
	for bit: int in KINDS:
		if bits & bit:
			kind = KINDS[bit]
			break


func body_enter(io: DotMapIO, info: Dictionary) -> void:
	if not enabled:
		return
	_touching[info["id"]] = info
	fire(io, "OnStartTouch", info.get("body"))
	if not _thinking:
		_thinking = true
		_gen += 1
		io.schedule_self(self, "__think", str(_gen), 0.0)


func body_leave(io: DotMapIO, info: Dictionary) -> void:
	_touching.erase(info["id"])
	_hits.erase(info["id"])
	if enabled:
		fire(io, "OnEndTouch", info.get("body"))


func _enabled_changed(_io: DotMapIO, _on: bool) -> void:
	_touching.clear()
	_hits.clear()
	_thinking = false
	_gen += 1


func _input(io: DotMapIO, name: String, param: String, _activator: Variant, _caller: Variant) -> bool:
	match name:
		"__think":
			if _thinking and param == str(_gen):
				_think(io)
			return true
		"setdamage":
			damage = param.to_float()
			return true
	return false


func _think(io: DotMapIO) -> void:
	if _touching.is_empty():
		_thinking = false
		return
	for id: Variant in _touching.keys():
		var info: Dictionary = _touching[id]
		var n: int = _hits.get(id, 0)
		if once and n > 0:
			continue
		var amount := damage * period
		if model == 1:
			amount = amount * pow(2.0, n)
			if cap > 0.0:
				amount = minf(amount, cap)
		_hits[id] = n + 1
		io.damage(info.get("body"), amount, kind, self)
		if force != Vector3.ZERO:
			io.event("damage_force", {"body": info.get("body"), "force": force, "source": self})
		fire(io, "OnHurt", info.get("body"))
		if str(info.get("kind", "player")) == "player":
			fire(io, "OnHurtPlayer", info.get("body"))
	if _thinking:
		io.schedule_self(self, "__think", str(_gen), period)
