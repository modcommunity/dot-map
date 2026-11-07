class_name DotMapDataSql
extends DotMapDataStore

## Map data in a table, through a dot-sql driver held untyped (query, execute, batch, migrate, open) so dot-map
## still parses without dot-sql. Every row read goes through [method DotMapDataBundle.from_json], so a
## hand-edited row meets the same limits as an imported file.

const CHANNEL := "map_data"
const MAX_VERSIONS := 1000

var driver = null
var table := DotMapDataSqlSchema.DEFAULT_TABLE
## Create or migrate the table on [method open]. Off when the schema is managed elsewhere.
var create_schema := true


func _init(p_driver = null, p_table: String = DotMapDataSqlSchema.DEFAULT_TABLE) -> void:
	driver = p_driver
	table = p_table


func open() -> DotResult:
	if driver == null:
		return DotResult.fail(DotError.CODE_STATE, "No SQL driver.")
	var opened: DotResult = await driver.open()
	if not opened.ok:
		return opened
	if not create_schema:
		return DotResult.success(true)
	var migrated: DotResult = await driver.migrate("%s:%s" % [DotMapDataSqlSchema.MIGRATION_COMPONENT, table], DotMapDataSqlSchema.migration_steps(table))
	return migrated.wrap("Could not prepare the map data table.") if not migrated.ok else DotResult.success(true)


func close() -> void:
	if driver != null:
		driver.close()


func fetch(game: String, map_id: String, map_version: String) -> DotResult:
	var bad := _guard(game, map_id, map_version)
	if bad != null:
		return bad
	var held := await versions(game, map_id)
	if not held.ok:
		return held
	var v := pick_version(held.value, map_version)
	if v == "":
		return DotResult.fail(NOT_FOUND, "No data for %s %s." % [map_id, map_version])
	var got: DotResult = await driver.query(DotMapDataSqlSchema.select_rows(table), [game, map_id, v, DotMapDataBundle.SECTIONS.size() + 1])
	if not got.ok:
		return got.wrap("Could not read map data.")
	var doc := {"format": DotMapDataBundle.FORMAT, "schema": DotMapDataBundle.SCHEMA, "game": game, "map": {"id": map_id, "version": v}, "sections": {}}
	for row: Variant in got.value:
		if not row is Dictionary:
			continue
		var parsed: Variant = _row_data(row.get("data"))
		if parsed == null:
			return DotResult.fail(DotError.CODE_INVALID, "A map data row is not a JSON object.")
		var section := str(row.get("section", ""))
		if section == DotMapDataSqlSchema.META_SECTION:
			doc["map"]["digest"] = str(parsed.get("digest", ""))
			doc["meta"] = parsed.get("meta", {})
		elif section in DotMapDataBundle.SECTIONS:
			doc["sections"][section] = parsed
	var res := DotMapDataBundle.from_json(JSON.stringify(doc))
	if res.ok:
		res.value.stale = v != map_version
	return res


func save(bundle: DotMapDataBundle, by: String = "") -> DotResult:
	var text := bundle.to_json()
	if not text.ok:
		return text
	var bad := _guard(bundle.game, bundle.map_id, bundle.map_version)
	if bad != null:
		return bad
	var now := int(Time.get_unix_time_from_system())
	var key := [bundle.game, bundle.map_id, bundle.map_version]
	var insert := DotMapDataSqlSchema.insert_row(table)
	var statements: Array = [[DotMapDataSqlSchema.delete_version(table), key]]
	var meta := {"digest": bundle.digest, "meta": bundle.meta}
	statements.append([insert, key + [DotMapDataSqlSchema.META_SECTION, JSON.stringify(meta), by, now]])
	for section: String in bundle.sections:
		statements.append([insert, key + [section, JSON.stringify(bundle.sections[section]), by, now]])
	var wrote: DotResult = await driver.batch(statements)
	if not wrote.ok:
		return wrote.wrap("Could not write map data.")
	DotLog.info(CHANNEL, "%s saved %s %s" % [by, bundle.map_id, bundle.map_version])
	return DotResult.success(bundle)


func versions(game: String, map_id: String) -> DotResult:
	var bad := _guard(game, map_id)
	if bad != null:
		return bad
	var got: DotResult = await driver.query(DotMapDataSqlSchema.select_versions(table), [game, map_id, MAX_VERSIONS])
	if not got.ok:
		return got.wrap("Could not list map data.")
	var found: Array = []
	for row: Variant in got.value:
		var v := str(row.get("map_version", "")) if row is Dictionary else ""
		if DotMapDataBundle.is_safe_id(v):
			found.append(v)
	return DotResult.success(sort_versions(found))


func remove(game: String, map_id: String, map_version: String) -> DotResult:
	var bad := _guard(game, map_id, map_version)
	if bad != null:
		return bad
	var held := await versions(game, map_id)
	if not held.ok:
		return held
	if not map_version in (held.value as PackedStringArray):
		return DotResult.fail(NOT_FOUND, "No data for %s %s." % [map_id, map_version])
	var gone: DotResult = await driver.execute(DotMapDataSqlSchema.delete_version(table), [game, map_id, map_version])
	return gone.wrap("Could not remove map data.") if not gone.ok else DotResult.success()


func _guard(game: String, map_id: String, map_version: String = "0") -> DotResult:
	if driver == null or not driver.is_open():
		return DotResult.fail(DotError.CODE_STATE, "The database is not open.")
	return check_key(game, map_id, map_version)


## The row's JSON as a Dictionary (a driver may hand back text or a parsed value), else null.
static func _row_data(raw: Variant) -> Variant:
	if raw is Dictionary:
		return raw
	if raw is String and (raw as String).length() <= DotMapDataBundle.MAX_BYTES:
		var v: Variant = JSON.parse_string(raw)
		return v if v is Dictionary else null
	return null
