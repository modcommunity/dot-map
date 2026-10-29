class_name DotMapEntities
extends RefCounted

## Everything a converted map says about its brush entities and logic, read from a manifest: movers, volumes, the link graph and the entities kept as plain data.
## Start from [code]DotMapEntities.from_manifest(world.manifest)[/code], then [method mover_named], [member links].
## A class the converter does not know arrives in [member generic] with every key it had, so a game can read its own entities.

var movers: Array[DotMapMover] = []
var volumes: Array[DotMapVolume] = []
var links: DotMapLinks = null
## Entities kept as data: [code][{entity, classname, targetname, target, origin, treatment, keys}][/code].
var generic: Array = []

var _by_entity: Dictionary = {}
var _by_model: Dictionary = {}


## Reads the [code]movers[/code], [code]volumes[/code], [code]links[/code] and [code]entities[/code] sections.
static func from_manifest(doc: Dictionary) -> DotMapEntities:
	var e := DotMapEntities.new()
	var names := {}
	for rec: Dictionary in doc.get("movers", []):
		var m := DotMapMover.from_record(rec)
		e.movers.append(m)
		e._by_entity[m.entity] = m
		if m.model >= 0:
			e._by_model[m.model] = m
		names[m.entity] = m.targetname
	for rec: Dictionary in doc.get("volumes", []):
		var v := DotMapVolume.from_record(rec)
		e.volumes.append(v)
		if v.entity >= 0:
			names[v.entity] = v.targetname
	e.generic = doc.get("entities", [])
	for rec: Dictionary in e.generic:
		names[int(rec["entity"])] = str(rec.get("targetname", ""))
	e.links = DotMapLinks.from_records(doc.get("links", []), names)
	return e


## The mover of an entity index, or null.
func mover_of(entity: int) -> DotMapMover:
	return _by_entity.get(entity)


## The mover that owns brush model [param model], or null.
func mover_for_model(model: int) -> DotMapMover:
	return _by_model.get(model)


## The first mover with this targetname (case-insensitive), or null.
func mover_named(name: String) -> DotMapMover:
	for m in movers:
		if m.targetname.to_lower() == name.to_lower():
			return m
	return null


## Volumes of one kind ("hurt", "multiple", ...).
func volumes_of(kind: String) -> Array[DotMapVolume]:
	var out: Array[DotMapVolume] = []
	for v in volumes:
		if v.kind == kind:
			out.append(v)
	return out


## Generic entities of a class.
func generic_of(classname: String) -> Array:
	return generic.filter(func(r: Dictionary) -> bool: return str(r["classname"]) == classname)


## Classes the converter had no row for, so a game or a maintainer knows what went unconverted.
func unknown_classes() -> PackedStringArray:
	var seen := {}
	for rec: Dictionary in generic:
		if str(rec.get("treatment", "")) == "unknown":
			seen[str(rec["classname"])] = true
	return PackedStringArray(seen.keys())


func describe() -> Dictionary:
	return {"movers": movers.size(), "volumes": volumes.size(), "generic": generic.size(),
			"links": links.size(), "unresolved": links.unresolved().size()}
