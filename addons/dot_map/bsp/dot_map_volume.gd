class_name DotMapVolume
extends RefCounted

## A trigger, push, hurt, teleport, water or ladder brush from a converted map, with exact
## containment, so a game needs no collision shape to ask "is this body inside".

var record: Dictionary = {}
var entity: int = -1
var model: int = -1
## One of multiple, once, teleport, push, hurt, gravity, water, ladder.
var kind: String = ""
var classname: String = ""
var targetname: String = ""
var disabled: bool = false
## Seconds before a [code]multiple[/code] fires again; -1 fires once.
var wait: float = 0.0
## Teleport destination name, or the trigger's filter name.
var target: String = ""
var filter: String = ""
var outputs: Array = []

var _brushes: Array = []


## Builds from a record of the manifest's [code]volumes[/code].
static func from_record(rec: Dictionary) -> DotMapVolume:
	var v := DotMapVolume.new()
	v.record = rec
	v.entity = int(rec["entity"]) if rec.get("entity") != null else -1
	v.model = int(rec.get("model", 0))
	v.kind = str(rec.get("kind", ""))
	v.classname = str(rec.get("classname", ""))
	v.targetname = str(rec.get("targetname", ""))
	v.disabled = bool(rec.get("disabled", false))
	v.wait = float(rec.get("wait", 0.0))
	v.target = str(rec.get("target", ""))
	v.filter = str(rec.get("filter", ""))
	v.outputs = rec.get("outputs", [])
	for planes: Array in rec.get("brushes", []):
		var set: Array[Plane] = []
		for p: Array in planes:
			set.append(Plane(Vector3(p[0], p[1], p[2]), float(p[3])))
		v._brushes.append(set)
	return v


## Whether [param point] (world metres) is inside any of the volume's brushes.
func contains(point: Vector3) -> bool:
	for planes: Array in _brushes:
		var inside := true
		for p: Plane in planes:
			if p.normal.dot(point) > p.d + 0.0001:
				inside = false
				break
		if inside:
			return true
	return false


## The box around every brush (corners found from plane triples).
func bounds() -> AABB:
	var box := AABB()
	var first := true
	for planes: Array in _brushes:
		for i in planes.size():
			for j in range(i + 1, planes.size()):
				for k in range(j + 1, planes.size()):
					var hit: Variant = (planes[i] as Plane).intersect_3(planes[j], planes[k])
					if hit == null or not _inside(planes, hit):
						continue
					box = AABB(hit, Vector3.ZERO) if first else box.expand(hit)
					first = false
	return box


func _inside(planes: Array, point: Vector3) -> bool:
	for p: Plane in planes:
		if p.normal.dot(point) > p.d + 0.001:
			return false
	return true


func brush_count() -> int:
	return _brushes.size()


func describe() -> Dictionary:
	return {"entity": entity, "kind": kind, "name": targetname, "brushes": _brushes.size(), "disabled": disabled}
