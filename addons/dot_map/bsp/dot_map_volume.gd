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
## A [code]push[/code] volume's unit direction (Godot axes) and speed in metres a second.
var direction: Vector3 = Vector3.ZERO
var speed: float = 0.0
## Raw source flags; for a push volume bit 1 is "players" (the others are physics objects and NPCs).
var spawnflags: int = 0

## How far under the feet a column reaches, so a body resting on a floor is on a slab laid in it.
const COLUMN_SLACK := 0.03

## A thin trigger brush is thickened to this many metres (0 turns it off), so a runner covering more
## than a sheet's width between two ticks cannot step over it. Hurt, water and ladder are never grown:
## a kill sheet under a floor would reach a body standing on it.
static var min_thickness: float = 0.25
const THICKEN_KINDS := ["multiple", "once", "teleport", "push", "gravity"]

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
	v.spawnflags = int(rec.get("spawnflags", 0))
	var dir: Array = rec.get("direction", [])
	if dir.size() == 3:
		v.direction = Vector3(dir[0], dir[1], dir[2])
	v.speed = float(rec.get("speed", 0.0))
	for planes: Array in rec.get("brushes", []):
		var set: Array[Plane] = []
		for p: Array in planes:
			set.append(Plane(Vector3(p[0], p[1], p[2]), float(p[3])))
		v._brushes.append(set)
	if min_thickness > 0.0 and THICKEN_KINDS.has(v.kind):
		v._thicken(min_thickness)
	return v


## Thickens every brush thinner than [param thickness] along its own thinnest plane normal (not the world axes,
## so an angled sheet is thickened too, and nothing grows along the sheet's edges): the two planes facing
## opposite ways on that normal move out by half the shortfall each.
func _thicken(thickness: float) -> void:
	for planes: Array in _brushes:
		var verts: Array[Vector3] = []
		for i in planes.size():
			for j in range(i + 1, planes.size()):
				for k in range(j + 1, planes.size()):
					var hit: Variant = (planes[i] as Plane).intersect_3(planes[j], planes[k])
					if hit != null and _inside(planes, hit):
						verts.append(hit)
		if verts.is_empty():
			continue
		var thin := INF
		var axis := Vector3.ZERO
		for p: Plane in planes:
			var lo := INF
			var hi := -INF
			for v in verts:
				var t := p.normal.dot(v)
				lo = minf(lo, t)
				hi = maxf(hi, t)
			if hi - lo < thin:
				thin = hi - lo
				axis = p.normal
		if thin >= thickness:
			continue
		var pad := (thickness - thin) * 0.5
		for i in planes.size():
			var p: Plane = planes[i]
			if absf(p.normal.dot(axis)) > 0.999:
				planes[i] = Plane(p.normal, p.d + pad)


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


## Whether the vertical column from [param feet] up [param height] metres touches the volume: the exact
## test of a segment against each convex brush, so a slab thinner than the points [method contains]
## samples (a belt laid flat on a floor) still catches a body standing on it.
func touches_column(feet: Vector3, height: float) -> bool:
	var from := feet - Vector3(0.0, COLUMN_SLACK, 0.0)
	var span := Vector3(0.0, height + COLUMN_SLACK, 0.0)
	for planes: Array in _brushes:
		var t0 := 0.0
		var t1 := 1.0
		for p: Plane in planes:
			var start := p.normal.dot(from) - p.d - 0.0001
			var rate := p.normal.dot(span)
			if absf(rate) < 0.000001:
				if start > 0.0:
					t1 = -1.0
					break
			elif rate > 0.0:
				t1 = minf(t1, -start / rate)
			else:
				t0 = maxf(t0, -start / rate)
		if t0 <= t1:
			return true
	return false


## The velocity a push volume applies to a body inside (m/s, Godot axes); zero for other kinds.
func push_velocity() -> Vector3:
	return direction * speed if kind == "push" else Vector3.ZERO


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


## One box per brush (a ladder or a water brush is one convex box; a union would span the gaps).
func brush_boxes() -> Array[AABB]:
	var out: Array[AABB] = []
	for planes: Array in _brushes:
		var box := AABB()
		var first := true
		for i in planes.size():
			for j in range(i + 1, planes.size()):
				for k in range(j + 1, planes.size()):
					var hit: Variant = (planes[i] as Plane).intersect_3(planes[j], planes[k])
					if hit == null or not _inside(planes, hit):
						continue
					box = AABB(hit, Vector3.ZERO) if first else box.expand(hit)
					first = false
		if not first:
			out.append(box)
	return out


func _inside(planes: Array, point: Vector3) -> bool:
	for p: Plane in planes:
		if p.normal.dot(point) > p.d + 0.001:
			return false
	return true


func brush_count() -> int:
	return _brushes.size()


func describe() -> Dictionary:
	return {"entity": entity, "kind": kind, "name": targetname, "brushes": _brushes.size(), "disabled": disabled}
