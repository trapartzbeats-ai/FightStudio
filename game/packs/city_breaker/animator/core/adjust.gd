class_name FSAAdjust
extends RefCounted
## Adjust: tilt a body part across the whole clip, a frame range, or around one frame, without touching its keys (the
## shoulders up a little on every frame of a walk, an arm straighter, the hands meeting for a clap).
##
## An adjustment is an "add" layer tagged "adjust": one constant turn for one bone over its range, fading in and out at the
## ends, so RESTORE just removes it and the keys never changed. Adjusting the same part with the same scope again replaces
## its turn (the value you set is the total). It never turns a joint past its rig limits, unless the clip itself already
## went past them there (FSAEval.layer_pose).
##   {"name": "Adjust armL", "mode": "add", "source": "keys", "adjust": true, "bone": "armL", "scope": "all"|"frame"|"range",
##    "keys": [{"f": 0, "rot": {"armL": [x, y, z]}}], "mask": ["armL"], "start", "end", "fade_in", "fade_out"}

const SCOPES := ["all", "frame", "range"]
const SCOPE_NAMES := {"all": "all frames", "frame": "around one frame", "range": "frame range"}


## [start, end, fade_in, fade_out] for a scope: "all" = the whole clip; "frame" = `at`, easing over `ease` frames each side
## (0 = that frame only); "range" = from..to, easing over `ease` frames inside each end
static func span(scope: String, at: int, from: int, to: int, ease: int) -> Array:
	match scope:
		"frame":
			return [maxi(0, at - ease), at + ease, ease, ease]
		"range":
			return [mini(from, to), maxi(from, to), ease, ease]
	return [0, -1, 0, 0]


static func adjust_layers(doc: FSADoc) -> Array:
	return doc.layers.filter(func(l: Dictionary) -> bool: return bool(l.get("adjust", false)))


## the adjustment of `bone` with exactly this span, or {}
static func find(doc: FSADoc, bone: String, scope: String, sp: Array) -> Dictionary:
	for l in adjust_layers(doc):
		if str(l.get("bone", "")) == bone and str(l.get("scope", "")) == scope and int(l.get("start", 0)) == int(sp[0]) and int(l.get("end", -1)) == int(sp[1]):
			return l
	return {}


## an adjustment's turn (radians)
static func value(l: Dictionary) -> Vector3:
	var ks: Array = l.get("keys", [])
	if ks.is_empty():
		return Vector3.ZERO
	var r: Array = ((ks[0] as Dictionary).get("rot", {}) as Dictionary).get(str(l.get("bone", "")), [0.0, 0.0, 0.0])
	return Vector3(float(r[0]), float(r[1]), float(r[2]))


static func layer_def(bone: String, scope: String, sp: Array, turn: Vector3) -> Dictionary:
	return {"name": "Adjust %s" % bone, "mode": "add", "source": "keys", "adjust": true, "bone": bone, "scope": scope, "mask": [bone],
		"keys": [{"f": 0, "rot": {bone: [snappedf(turn.x, 0.0001), snappedf(turn.y, 0.0001), snappedf(turn.z, 0.0001)]}}],
		"start": sp[0], "end": sp[1], "fade_in": sp[2], "fade_out": sp[3], "weight": 1.0}


## bone -> how many adjustments it has (the * marks)
static func adjusted_bones(doc: FSADoc) -> Dictionary:
	var out := {}
	for l in adjust_layers(doc):
		if not bool(l.get("mute", false)):
			var b := str(l.get("bone", ""))
			out[b] = int(out.get(b, 0)) + 1
	return out


## one line for the list: "armL  all frames  X +12  Z -5"
static func describe(l: Dictionary) -> String:
	var v := value(l)
	var parts: PackedStringArray = []
	for i in 3:
		if absf(v[i]) > 1e-4:
			parts.append("%s %+.0f" % [["X", "Y", "Z"][i], rad_to_deg(v[i])])
	var where := str(SCOPE_NAMES.get(str(l.get("scope", "all")), ""))
	if str(l.get("scope", "")) == "frame":
		where = "around f%d" % int(round((float(l.get("start", 0)) + float(l.get("end", 0))) * 0.5))
	elif str(l.get("scope", "")) == "range":
		where = "f%d-%d" % [int(l.get("start", 0)), int(l.get("end", 0))]
	return "%s  %s  %s%s" % [l.get("bone", ""), where, " ".join(parts), "  (muted)" if bool(l.get("mute", false)) else ""]
