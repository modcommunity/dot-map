extends Node

## Counters, [code]_check[/code], [code]_section[/code] and the catalogue builders of the map self-test.

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()
var _entered := 0
var _completed := 0


func _check_near(
	value: float, expected: float, epsilon: float, what: String
) -> void:
	_check(
		absf(value - expected) <= epsilon, what,
		"%.4f vs %.4f" % [value, expected]
	)


func _section(title: String) -> void:
	_entered += 1
	print(title)


## A section reached its last line. See [constant SECTIONS].
func _done() -> void:
	_completed += 1


func _check(ok: bool, what: String, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    %s" % what)
	else:
		_failed += 1
		var line := what if detail == "" else "%s (%s)" % [what, detail]
		_failures.append(line)
		print("  FAIL  %s" % line)


## A map that points at a scene which really exists, so a load can be tried.
func _map(id: StringName, tier: int = 1) -> DotMapDef:
	var map := DotMapDef.new()
	map.id = id
	map.display_name = String(id).capitalize()
	map.scene_path = "res://fixtures/test_world.tscn"
	map.tier = tier
	map.kind = DotMapDef.KIND_SURF
	return map


func _catalogue(count: int) -> DotMapCatalogue:
	var catalogue := DotMapCatalogue.new()

	for i in range(count):
		catalogue.add(_map(StringName("surf_%d" % i), (i % 10) + 1))

	return catalogue
