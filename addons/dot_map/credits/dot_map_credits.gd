class_name DotMapCredits
extends RefCounted
## The credits of a loaded converted map, read from its manifest's licence block (the rows `bsp.py` writes to
## CREDITS.md and credits.json): the map's author, and every free texture, model and sound it shows.

const ATTRIBUTION := ["CC-BY-4.0"]


## One dict per distinct work: kind, name, author, licence, url, attribution (true when the licence requires naming
## the author) and uses. [param only_attribution] keeps just the works whose licence requires the credit.
static func works(manifest: Dictionary, only_attribution: bool = false) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen := {}
	var block: Dictionary = manifest.get("licence", {})
	for kind: String in ["texture", "model", "sound"]:
		var rows: Array = block.get("model_stand_ins" if kind == "model" else kind + "s", [])
		for row: Dictionary in rows:
			if kind == "texture" and str(row.get("kind", "")) == "generated":
				continue
			var name := str(row.get("generic", "")) if kind == "texture" else str(row.get("stand_in", ""))
			var key := "%s|%s" % [kind, str(row.get("url", "")) if row.get("url", "") != "" else name]
			if seen.has(key):
				out[seen[key]]["uses"] += int(row.get("count", row.get("surfaces", 1)))
				continue
			seen[key] = out.size()
			out.append({
				"kind": kind, "name": name, "author": str(row.get("author", "")), "licence": str(row.get("licence", "")),
				"url": str(row.get("url", "")), "attribution": ATTRIBUTION.has(str(row.get("licence", ""))),
				"uses": int(row.get("count", row.get("surfaces", 1))),
			})
	if only_attribution:
		return out.filter(func(w: Dictionary) -> bool: return w["attribution"])
	return out


## The one line a scoreboard or menu shows: the map's author and page, then the authors whose licence asks for a credit.
static func line(manifest: Dictionary) -> String:
	var parts := PackedStringArray()
	var credit: Dictionary = manifest.get("credit", {})
	if str(credit.get("author", "")) != "":
		parts.append("Map by %s" % credit["author"])
	var names := {}
	for w in works(manifest, true):
		if str(w["author"]) != "":
			names[w["author"]] = true
	if not names.is_empty():
		parts.append("Art: %s" % ", ".join(PackedStringArray(names.keys())))
	return " | ".join(parts)
