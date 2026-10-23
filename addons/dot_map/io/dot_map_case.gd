class_name DotMapCase
extends DotMapEntity

## logic_case: InValue matches its text against Case01..16 and fires OnCaseNN or OnDefault;
## PickRandom picks a filled case at random; PickRandomShuffle goes through each once per round.

var _bag: Array = []


func _input(io: DotMapIO, name: String, param: String, activator: Variant, _caller: Variant) -> bool:
	match name:
		"invalue":
			var hit := false
			for n in range(1, 17):
				if _case(n) != "" and _case(n).to_lower() == param.strip_edges().to_lower():
					fire(io, "OnCase%02d" % n, activator, param)
					hit = true
			if not hit:
				fire(io, "OnDefault", activator, param)
		"pickrandom":
			var filled := _filled()
			if filled.is_empty():
				fire(io, "OnDefault", activator)
			else:
				_fire_case(io, filled[io.stream_for(self).next_range_i(0, filled.size() - 1)], activator)
		"pickrandomshuffle":
			if _bag.is_empty():
				_bag = _filled()
				var s := io.stream_for(self)
				for i in range(_bag.size() - 1, 0, -1):
					var j := s.next_range_i(0, i)
					var t: Variant = _bag[i]
					_bag[i] = _bag[j]
					_bag[j] = t
			if _bag.is_empty():
				fire(io, "OnDefault", activator)
			else:
				_fire_case(io, _bag.pop_back(), activator)
		_:
			return false
	return true


func _case(n: int) -> String:
	return key("case%02d" % n)


func _filled() -> Array:
	var out: Array = []
	for n in range(1, 17):
		if _case(n) != "":
			out.append(n)
	return out


func _fire_case(io: DotMapIO, n: int, activator: Variant) -> void:
	fire(io, "OnCase%02d" % n, activator, _case(n))
