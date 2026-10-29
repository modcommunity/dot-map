extends Node

## The counters, check and finish every self-checking suite here repeats.

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()
var _entered := 0
var _completed := 0


func _section(title: String) -> void:
	_entered += 1
	print("  " + title)


func _done() -> void:
	_completed += 1


func _check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		_failures.append(what)


func _rec(index: int, cls: String, tname: String, pairs: Array = [], outs: Array = []) -> Dictionary:
	var outputs: Array = []
	for o: Array in outs:
		outputs.append({"output": o[0], "target": o[1], "input": o[2], "param": o[3] if o.size() > 3 else "",
				"delay": o[4] if o.size() > 4 else 0.0, "times": o[5] if o.size() > 5 else -1})
	return {"index": index, "classname": cls, "targetname": tname, "parentname": "", "pairs": pairs, "outputs": outputs}


## Prints the totals and quits non-zero when a check failed, a section aborted or the counts differ from the declared ones.
func _finish(checks: int, sections: int) -> void:
	print("")
	print("%d passed, %d failed" % [_passed, _failed])
	for line in _failures:
		print("  FAIL  %s" % line)
	print("%d of %d sections ran to their last line" % [_completed, _entered])
	if _entered != sections or _completed != _entered:
		print("ERROR: %d sections entered and %d completed, %d expected." % [_entered, _completed, sections])
		get_tree().quit(1)
		return
	if _passed + _failed != checks:
		print("ERROR: %d checks ran, %d expected. A section aborted part-way." % [_passed + _failed, checks])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)
