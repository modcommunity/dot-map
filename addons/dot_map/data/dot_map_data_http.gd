class_name DotMapDataHttp
extends DotMapDataStore

## Map data on the backbone: `GET <prefix>/<game>/<map>` lists versions, `GET|PUT|DELETE <prefix>/<game>/<map>/<version>`
## carry one bundle as JSON text. [member client] is duck-typed (dot-core's DotHttp, or a fake): it needs
## `request(method, path, body: PackedByteArray, headers) -> DotResult` whose value has `status` and `body_text`.
## The reply is untrusted: it is size-capped, validated by [method DotMapDataBundle.from_json] and must be
## the map that was asked for.

const CHANNEL := "map_data"
const MAX_VERSIONS := 1000

var client: Object = null
var path_prefix := "map-data"
## Sent as a bearer token. Never logged, and refused from the environment and argv by [DotMapDataConfig].
var token := ""


func _init(p_client: Object = null, p_token: String = "") -> void:
	client = p_client
	token = p_token


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
	var got := await _send(HTTPClient.METHOD_GET, _path(game, map_id, v))
	if not got.ok:
		return got
	var res := DotMapDataBundle.from_json(got.value)
	if not res.ok:
		return res.wrap("The server sent bad map data.")
	var b: DotMapDataBundle = res.value
	if b.game != game or b.map_id != map_id or b.map_version != v:
		return DotResult.fail(DotError.CODE_INVALID, "The server sent data for another map.")
	b.stale = v != map_version
	return res


func save(bundle: DotMapDataBundle, by: String = "") -> DotResult:
	var text := bundle.to_json()
	if not text.ok:
		return text
	var bad := _guard(bundle.game, bundle.map_id, bundle.map_version)
	if bad != null:
		return bad
	var put := await _send(HTTPClient.METHOD_PUT, _path(bundle.game, bundle.map_id, bundle.map_version), (text.value as String).to_utf8_buffer(), by)
	if not put.ok:
		return put
	DotLog.info(CHANNEL, "%s saved %s %s" % [by, bundle.map_id, bundle.map_version])
	return DotResult.success(bundle)


func versions(game: String, map_id: String) -> DotResult:
	var bad := _guard(game, map_id)
	if bad != null:
		return bad
	var got := await _send(HTTPClient.METHOD_GET, _path(game, map_id))
	if got.code() == NOT_FOUND:
		return DotResult.success(PackedStringArray())
	if not got.ok:
		return got
	var parsed: Variant = JSON.parse_string(got.value)
	var list: Variant = parsed.get("versions") if parsed is Dictionary else null
	if not list is Array:
		return DotResult.fail(DotError.CODE_INVALID, "The server sent no version list.")
	var found: Array = []
	for v: Variant in (list as Array).slice(0, MAX_VERSIONS):
		if v is String and DotMapDataBundle.is_safe_id(v):
			found.append(v)
	return DotResult.success(sort_versions(found))


func remove(game: String, map_id: String, map_version: String) -> DotResult:
	var bad := _guard(game, map_id, map_version)
	if bad != null:
		return bad
	var gone := await _send(HTTPClient.METHOD_DELETE, _path(game, map_id, map_version))
	return DotResult.success() if gone.ok else gone


func _guard(game: String, map_id: String, map_version: String = "0") -> DotResult:
	if client == null or not client.has_method("request"):
		return DotResult.fail(DotError.CODE_STATE, "No HTTP client.")
	return check_key(game, map_id, map_version)


func _path(game: String, map_id: String, map_version: String = "") -> String:
	var p := "%s/%s/%s" % [path_prefix.trim_suffix("/"), game, map_id]
	return p if map_version == "" else p + "/" + map_version


## The body text of a 2xx reply, else the failure; a 404 is [constant NOT_FOUND].
func _send(method: int, path: String, body: PackedByteArray = PackedByteArray(), by: String = "") -> DotResult:
	var headers := {"Accept": "application/json"}
	if token != "":
		headers["Authorization"] = "Bearer " + token
	if by != "":
		headers["X-Updated-By"] = by.substr(0, DotMapDataBundle.MAX_ID).uri_encode()
	if not body.is_empty():
		headers["Content-Type"] = "application/json"
	var res: DotResult = await client.call("request", method, path, body, headers)
	if not res.ok:
		if res.error != null and res.error.http_status == 404:
			return DotResult.fail(NOT_FOUND, "The server has no such map data.")
		return res
	var reply: Variant = res.value
	var text: String = str(reply.get("body_text", "")) if reply is Dictionary else ""
	if text.length() > DotMapDataBundle.MAX_BYTES:
		return DotResult.fail(DotError.CODE_INVALID, "The server's reply is larger than %d bytes." % DotMapDataBundle.MAX_BYTES)
	return DotResult.success(text)
