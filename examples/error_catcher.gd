extends Logger
## Collects engine errors while added with OS.add_logger: an engine error does not fail a check by itself.

var errors: Array[String] = []


func _log_error(function: String, _file: String, _line: int, code: String,
		rationale: String, _editor_notify: bool, _error_type: int,
		_script_backtraces: Array) -> void:
	errors.append("%s %s %s" % [code, rationale, function])
