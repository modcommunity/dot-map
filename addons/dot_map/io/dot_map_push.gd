class_name DotMapPush
extends DotMapEntity

## trigger_push: the volume's direction and speed, which SetPushSpeed and SetPushDirection change.
## [DotMapVolumes] hands the push to [member DotMapIO.move_fn] as a [Vector3] (m/s) each step a
## body is inside.

## Unit direction, Godot axes.
var direction := Vector3.ZERO
## Metres a second.
var speed := 0.0


func velocity() -> Vector3:
	return direction * speed


func _input(io: DotMapIO, name: String, param: String, _activator: Variant, _caller: Variant) -> bool:
	match name:
		"setpushspeed":
			speed = param.to_float() * io.unit_scale
			return true
		"setpushdirection":
			var a := param.split_floats(" ", false)
			if a.size() >= 2:
				var p := deg_to_rad(a[0])
				var y := deg_to_rad(a[1])
				direction = to_godot_dir(Vector3(cos(p) * cos(y), cos(p) * sin(y), -sin(p)))
			return true
	return false
