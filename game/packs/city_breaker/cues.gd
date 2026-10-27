class_name CBCues
extends RefCounted
## Effect cues on clips (data/clip_fx.json): "at 0.35 s of clip jab, play impact_spark on socket fist_R". The Studio edits them,
## fighters play them (fighter.gd) and the Studio plays them with the same scheduler, so what you see is what ships.
##
##   {"cues": {"jab": [{"t": 0.35, "fx": "impact_spark", "socket": "fist_R", "scale": 1.0, "mode": "burst", "dur": 0.4}]}}
##
## fx = an RMT effect id or a combo from data/fx_combos.json; mode "burst" = one-shot at the socket's position, "follow" = the
## effect rides the socket for `dur` seconds. t is seconds into the clip at normal speed.

const DATA := "res://game/packs/city_breaker/data/clip_fx.json"
static var _data: Dictionary = {}


static func load_data(force: bool = false) -> Dictionary:
	if _data.is_empty() or force:
		_data = {"cues": {}}
		var f := FileAccess.open(DATA, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if typeof(parsed) == TYPE_DICTIONARY and (parsed as Dictionary).has("cues"):
				_data = parsed
	return _data


static func for_clip(clip: String) -> Array:
	return (load_data().get("cues", {}) as Dictionary).get(clip, [])


static func set_clip(clip: String, cues: Array) -> void:
	var d := load_data()
	if cues.is_empty():
		(d["cues"] as Dictionary).erase(clip)
	else:
		(d["cues"] as Dictionary)[clip] = cues


static func save() -> int:
	var f := FileAccess.open(DATA, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(load_data(), "  "))
	f.close()
	return OK


## Fires a clip's cues as its playback position passes them. Feed it the clip name and the playback position every tick.
class Player:
	extends RefCounted
	var clip := ""
	var cues: Array = []
	var fired: Array = []
	var last_pos := 0.0
	var on_fire: Callable   ## func(cue: Dictionary)

	func reset(new_clip: String) -> void:
		clip = new_clip
		cues = CBCues.for_clip(new_clip)
		fired = []
		fired.resize(cues.size())
		fired.fill(false)
		last_pos = -1.0

	func tick(pos: float) -> void:
		if cues.is_empty():
			last_pos = pos
			return
		if pos < last_pos - 0.001:   # the clip restarted or looped
			fired.fill(false)
		for i in cues.size():
			if not bool(fired[i]) and pos >= float((cues[i] as Dictionary).get("t", 0.0)):
				fired[i] = true
				if on_fire.is_valid():
					on_fire.call(cues[i])
		last_pos = pos
