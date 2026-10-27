class_name CBPairs
extends RefCounted
## Two-body scenes (grabs, throws, combo finishers) staged in the Studio: when a move that plays `clip` connects, the VICTIM is placed
## relative to the attacker and plays a reaction clip made for it, so both bodies are animated by hand and fit each other.
##
##   {"pairs": {"grab": {"reactor_clip": "grabbed", "dx": 0.9, "dy": 0.0, "dz": 0.0, "yaw": 180.0, "delay": 0}}}
##
## dx = metres in front of the attacker, dy = up, dz = to the attacker's right, yaw = degrees the victim is turned (180 = facing the
## attacker), delay = frames the reaction starts after the attacker's clip. Studio: PAIR tab.

const DATA := "res://game/packs/city_breaker/data/pairs.json"
static var _data: Dictionary = {}


static func load_data(force: bool = false) -> Dictionary:
	if _data.is_empty() or force:
		_data = {"pairs": {}}
		var f := FileAccess.open(DATA, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if typeof(parsed) == TYPE_DICTIONARY and (parsed as Dictionary).has("pairs"):
				_data = parsed
	return _data


static func for_clip(clip: String) -> Dictionary:
	return (load_data().get("pairs", {}) as Dictionary).get(clip, {})


static func set_pair(clip: String, pair: Dictionary) -> void:
	var pairs: Dictionary = load_data()["pairs"]
	if pair.is_empty():
		pairs.erase(clip)
	else:
		pairs[clip] = pair


static func save() -> int:
	var f := FileAccess.open(DATA, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(load_data(), "  "))
	f.close()
	return OK
