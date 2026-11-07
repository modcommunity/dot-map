class_name DotMapDataSqlSchema
extends RefCounted

## The one table of [DotMapDataSql] as plain data for a dot-sql driver to render, so this names no dot-sql class.
## One row per section; the digest and meta of a bundle are one more row under [constant META_SECTION].

const DEFAULT_TABLE := "dot_map_data"
const MIGRATION_COMPONENT := "dot_map_data"
const META_SECTION := "_meta"
const COLUMNS := ["game", "map_id", "map_version", "section", "data", "updated_by", "updated_at"]


static func spec(table: String = DEFAULT_TABLE) -> Dictionary:
	return {
		"name": table,
		"columns": [
			{"name": "game", "type": "key", "null": false},
			{"name": "map_id", "type": "key", "null": false},
			{"name": "map_version", "type": "key", "null": false},
			{"name": "section", "type": "key", "null": false},
			{"name": "data", "type": "json", "null": false},
			{"name": "updated_by", "type": "text"},
			{"name": "updated_at", "type": "bigint", "null": false, "default": 0},
		],
		"primary_key": ["game", "map_id", "map_version", "section"],
	}


## Step N brings version N to N+1; add a step, never edit one.
static func migration_steps(table: String = DEFAULT_TABLE) -> Array:
	return [[spec(table)]]


static func select_versions(table: String) -> String:
	return "SELECT DISTINCT map_version FROM %s WHERE game = ? AND map_id = ? LIMIT ?" % table


static func select_rows(table: String) -> String:
	return "SELECT section, data FROM %s WHERE game = ? AND map_id = ? AND map_version = ? LIMIT ?" % table


static func delete_version(table: String) -> String:
	return "DELETE FROM %s WHERE game = ? AND map_id = ? AND map_version = ?" % table


static func insert_row(table: String) -> String:
	return "INSERT INTO %s (%s) VALUES (?, ?, ?, ?, ?, ?, ?)" % [table, ", ".join(COLUMNS)]
