extends Node
## Proves DotMapCredits and DotMapStore on a hand-written manifest and a stand-in cloud client.
## godot --headless --path . res://examples/store_demo.tscn

const CHECKS := 15
const SECTIONS := 3

var _passed := 0
var _failed := 0
var _entered := 0
var _completed := 0

const MANIFEST := {
	"credit": {"author": "Mapper"},
	"licence": {
		"textures": [
			{"kind": "pbr", "generic": "Bricks", "author": "ambientCG", "licence": "CC0-1.0", "url": "u/b", "surfaces": 4},
			{"kind": "pbr", "generic": "Moss", "author": "Jane", "licence": "CC-BY-4.0", "url": "u/m", "surfaces": 2},
			{"kind": "generated", "generic": "flat", "key": "k"},
		],
		"model_stand_ins": [
			{"stand_in": "lib/chair", "author": "Poly", "licence": "CC-BY-4.0", "url": "u/c", "count": 3},
			{"stand_in": "lib/chair2", "author": "Poly", "licence": "CC-BY-4.0", "url": "u/c", "count": 2},
		],
		"sounds": [{"stand_in": "wind", "author": "K", "licence": "CC0-1.0", "url": "u/w", "count": 1}],
		"store_pack": {"id": "gamemann/store-x", "version": "h1234abcd"},
	},
}


class FakeCloud:
	extends RefCounted
	var mounted := {}
	var ensured := 0

	func dependency_prefix(id: StringName, version: String) -> String:
		return mounted.get("%s@%s" % [id, version], "")

	func ensure(id: StringName, version: String, _groups: PackedStringArray, _url: String) -> DotResult:
		ensured += 1
		mounted["%s@%s" % [id, version]] = "res://dot_cloud/%s/%s/" % [id, version]
		return DotResult.success(null)


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL ", label)


func _run() -> void:
	_credits()
	await _store()
	_surfaces()
	print("%d checks, %d failed, %d/%d sections" % [_passed + _failed, _failed, _completed, SECTIONS])
	var bad := _failed > 0 or _passed + _failed != CHECKS or _completed != SECTIONS or _entered != SECTIONS
	get_tree().quit(1 if bad else 0)


func _credits() -> void:
	_entered += 1
	var all := DotMapCredits.works(MANIFEST)
	_check("generated textures are skipped, same url merges", all.size() == 4)
	var chair := all.filter(func(w: Dictionary) -> bool: return w["url"] == "u/c")
	_check("merged uses add up", chair.size() == 1 and chair[0]["uses"] == 5)
	var need := DotMapCredits.works(MANIFEST, true)
	_check("attribution filter keeps CC-BY only", need.size() == 2)
	_check("CC0 never needs a credit", not need.any(func(w: Dictionary) -> bool: return w["licence"] == "CC0-1.0"))
	var line := DotMapCredits.line(MANIFEST)
	_check("line names the map author", line.begins_with("Map by Mapper"))
	_check("line names the art authors", line.contains("Jane") and line.contains("Poly") and not line.contains("ambientCG"))
	_check("empty manifest gives an empty line", DotMapCredits.line({}) == "")
	_completed += 1


func _store() -> void:
	_entered += 1
	var lic: Dictionary = MANIFEST["licence"]
	var cloud := FakeCloud.new()
	_check("pack_of reads the slice", DotMapStore.pack_of(lic)["version"] == "h1234abcd")
	_check("no slice, no pack", DotMapStore.pack_of({}).is_empty())
	_check("not mounted gives no dir", DotMapStore.mount_dir(lic, cloud) == "")
	var res: DotResult = await DotMapStore.ensure(lic, cloud, "")
	_check("ensure without a manifest url fails", not res.ok)
	res = await DotMapStore.ensure(lic, cloud, "https://x/manifest.json")
	_check("ensure mounts it", res.ok and cloud.ensured == 1 and str(res.value).begins_with("res://dot_cloud/gamemann/store-x"))
	await DotMapStore.ensure(lic, cloud, "https://x/manifest.json")
	_check("a second ensure downloads nothing", cloud.ensured == 1)
	_completed += 1


func _surfaces() -> void:
	_entered += 1
	var cloud := FakeCloud.new()
	cloud.mounted["gamemann/store-x@h1234abcd"] = "res://dot_cloud/gamemann/store-x/h1234abcd/"
	var s := DotMapSurfaces.new()
	var w := DotMapBspMesh.new()
	_check("apply points both at the slice", DotMapStore.apply(MANIFEST["licence"], cloud, s, w)
			and s.pbr_library.ends_with("h1234abcd/pbr") and w.model_library.ends_with("h1234abcd/models"))
	_check("apply is false when unmounted", not DotMapStore.apply(MANIFEST["licence"], FakeCloud.new(), s, w))
	_completed += 1
