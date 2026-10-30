class_name FSARig
extends RefCounted
## What the Animator knows about rig v4 (every City Breaker fighter and the open-world bodies share it): bone groups for the
## outliner and layer masks, left / right mirroring, what each axis does, joint limits (a knee never bends forward), the limbs
## the IK works on, and the rig controls (one slider that drives several bones: a fist, a spine curl, a crouch).
##
## data/animator_rig.json holds the controls and limits; it is written the first time with the defaults below, then it is yours.

const DATA := "res://game/packs/city_breaker/data/animator_rig.json"

const GROUPS := [
	["Body", ["root", "hips", "torso", "chest", "neck", "head"]],
	["Arm L", ["armL", "elbowL", "handL"]],
	["Arm R", ["armR", "elbowR", "handR"]],
	["Hand L", ["fingersL", "tipsL", "nailL", "thumbL", "thumbL2", "indexL", "indexL2", "indexL3", "ringL", "ringL2", "ringL3", "pinkyL", "pinkyL2", "pinkyL3"]],
	["Hand R", ["fingersR", "tipsR", "nailR", "thumbR", "thumbR2", "indexR", "indexR2", "indexR3", "ringR", "ringR2", "ringR3", "pinkyR", "pinkyR2", "pinkyR3"]],
	["Leg L", ["legL", "kneeL", "footL"]],
	["Leg R", ["legR", "kneeR", "footR"]],
]

## masks for layers and quick selection
const MASKS := {
	"Full body": [],
	"Upper body": ["torso", "chest", "neck", "head", "armL", "elbowL", "handL", "armR", "elbowR", "handR", "@Hand L", "@Hand R"],
	"Lower body": ["hips", "legL", "kneeL", "footL", "legR", "kneeR", "footR"],
	"Arms": ["armL", "elbowL", "handL", "armR", "elbowR", "handR", "@Hand L", "@Hand R"],
	"Arm L": ["armL", "elbowL", "handL", "@Hand L"],
	"Arm R": ["armR", "elbowR", "handR", "@Hand R"],
	"Legs": ["legL", "kneeL", "footL", "legR", "kneeR", "footR"],
	"Head": ["neck", "head", "@Ears"],
	"Spine": ["torso", "chest", "neck"],
	"Hands": ["@Hand L", "@Hand R"],
	"Tail": ["@Tail"],
}

## limbs the IK works on: upper, lower, end
const LIMBS := {
	"armL": ["armL", "elbowL", "handL"], "armR": ["armR", "elbowR", "handR"],
	"legL": ["legL", "kneeL", "footL"], "legR": ["legR", "kneeR", "footR"],
}

const HINTS := {
	"leg": "X - thigh forward, + back   Z leg out to the side   Y turn the leg",
	"knee": "X + bends the knee (never negative: a knee does not bend forward)",
	"foot": "X + points the toes down",
	"arm": "X - raises the arm forward, + swings it back   Z arm out to the side",
	"elbow": "X - bends the elbow",
	"hand": "X bends the wrist   Z tilts it",
	"torso": "X + leans forward   Y twist   Z side lean",
	"chest": "X + leans forward   Y twist   Z side lean",
	"neck": "X + nods forward   Y turn",
	"head": "X + nods forward   Y turns the head   Z tilts it",
	"hips": "whole body turns about the hips: X + forward somersault, Y spin, Z roll. Move = hips_dx / dy / dz",
	"root": "the feet point; clips leave it at rest",
	"tail": "X curls the tail up / down   Z swishes it side to side",
	"fingers": "X curls the fingers   Z spreads them",
	"tips": "X curls the last finger joint",
	"thumb": "X curls the thumb   Z swings it away from the hand",
	"ear": "X folds the ear forward / back   Z tilts it",
	"crest": "X bends the crest forward / back   Z tilts it",
	"pom": "X / Z tip the pompom",
	"fin": "X / Z tilt the fin",
}

## joint limits in radians {bone: {"x": [lo, hi], ...}}: the tools clamp to them when they write a pose
const DEFAULT_LIMITS := {
	"kneeL": {"x": [0.0, 2.7]}, "kneeR": {"x": [0.0, 2.7]},
	"elbowL": {"x": [-2.75, 0.08]}, "elbowR": {"x": [-2.75, 0.08]},
}

## controls: one slider drives several bone channels. drives = [[bone, axis 0/1/2 or "dx"/"dy"/"dz", amount at value 1]]
const DEFAULT_CONTROLS := [
	{"name": "Fist L", "min": 0.0, "max": 1.0, "drives": [["fingersL", 0, -1.45], ["tipsL", 0, -1.25], ["thumbL", 0, -0.7], ["thumbL2", 0, -0.5]]},
	{"name": "Fist R", "min": 0.0, "max": 1.0, "drives": [["fingersR", 0, -1.45], ["tipsR", 0, -1.25], ["thumbR", 0, -0.7], ["thumbR2", 0, -0.5]]},
	{"name": "Spine bend", "min": -1.0, "max": 1.0, "drives": [["torso", 0, 0.35], ["chest", 0, 0.35], ["neck", 0, 0.15], ["head", 0, 0.15]]},
	{"name": "Spine twist", "min": -1.0, "max": 1.0, "drives": [["torso", 1, 0.3], ["chest", 1, 0.3], ["neck", 1, 0.2], ["head", 1, 0.2]]},
	{"name": "Spine side", "min": -1.0, "max": 1.0, "drives": [["torso", 2, 0.25], ["chest", 2, 0.25], ["neck", 2, 0.1]]},
	{"name": "Head look", "min": -1.0, "max": 1.0, "drives": [["neck", 1, 0.45], ["head", 1, 0.75]]},
	{"name": "Head nod", "min": -1.0, "max": 1.0, "drives": [["neck", 0, 0.3], ["head", 0, 0.45]]},
	{"name": "Crouch", "min": 0.0, "max": 1.0, "drives": [["legL", 0, -0.95], ["legR", 0, -0.95], ["kneeL", 0, 1.7], ["kneeR", 0, 1.7], ["footL", 0, -0.7], ["footR", 0, -0.7], ["torso", 0, 0.25], ["hips", "dy", -0.32]]},
	{"name": "Guard up", "min": 0.0, "max": 1.0, "drives": [["armL", 0, -0.9], ["armR", 0, -0.9], ["elbowL", 0, -2.0], ["elbowR", 0, -2.0], ["armL", 2, -0.25], ["armR", 2, 0.25]]},
	{"name": "Tail curl", "min": -1.0, "max": 1.0, "drives": [["tail", 0, 0.35], ["tail2", 0, 0.45], ["tail3", 0, 0.55]]},
	{"name": "Tail sway", "min": -1.0, "max": 1.0, "drives": [["tail", 2, 0.3], ["tail2", 2, 0.4], ["tail3", 2, 0.5]]},
	{"name": "Ears back", "min": -1.0, "max": 1.0, "drives": [["earL", 0, 0.6], ["earR", 0, 0.6], ["earL2", 0, 0.3], ["earR2", 0, 0.3]]},
]

static var _data: Dictionary = {}
static var _mirror_re: RegEx


static func data(force: bool = false) -> Dictionary:
	if not _data.is_empty() and not force:
		return _data
	var f := FileAccess.open(DATA, FileAccess.READ)
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if typeof(parsed) == TYPE_DICTIONARY:
			_data = parsed
	if _data.is_empty():
		_data = {"version": 1, "controls": DEFAULT_CONTROLS.duplicate(true), "limits": DEFAULT_LIMITS.duplicate(true)}
		save_data()
	return _data


static func save_data() -> int:
	var f := FileAccess.open(DATA, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(_data, "  "))
	f.close()
	return OK


static func controls() -> Array:
	return data().get("controls", []) as Array


static func limits() -> Dictionary:
	return data().get("limits", {}) as Dictionary


## the group a bone belongs to (tails, ears, crests... by prefix)
static func group_of(b: String) -> String:
	for g in GROUPS:
		if b in (g[1] as Array):
			return str(g[0])
	if b.begins_with("tail"):
		return "Tail"
	if b.begins_with("ear"):
		return "Ears"
	return "Extras"


## the bones of the skeleton sorted into groups, in GROUPS order then Tail / Ears / Extras: [[group, [bones]]]
static func grouped(bones: Array) -> Array:
	var order: Array = []
	for g in GROUPS:
		order.append(str(g[0]))
	order.append_array(["Tail", "Ears", "Extras"])
	var by: Dictionary = {}
	for b in bones:
		var g := group_of(str(b))
		if not by.has(g):
			by[g] = []
		(by[g] as Array).append(str(b))
	var out: Array = []
	for g in order:
		if by.has(g):
			out.append([g, by[g]])
	return out


## the bones a mask names ("@Group" expands to the group); an empty mask is the whole body
static func mask_bones(mask: Array, bones: Array) -> Array:
	if mask.is_empty():
		return bones.duplicate()
	var out: Array = []
	for m in mask:
		var s := str(m)
		if s.begins_with("@"):
			for b in bones:
				if group_of(str(b)) == s.substr(1) and not (b in out):
					out.append(b)
		elif s in bones and not (s in out):
			out.append(s)
	return out


## armL <-> armR, indexL2 <-> indexR2, earL3 <-> earR3; centre bones map to themselves
static func mirror_name(b: String) -> String:
	if _mirror_re == null:
		_mirror_re = RegEx.new()
		_mirror_re.compile("^(.*?)([LR])(\\d*)$")
	var m := _mirror_re.search(b)
	if m == null:
		return b
	return m.get_string(1) + ("R" if m.get_string(2) == "L" else "L") + m.get_string(3)


## "L", "R" or "" (a centre bone)
static func side_of(b: String) -> String:
	if mirror_name(b) == b:
		return ""
	return _mirror_re.search(b).get_string(2)


static func is_side(b: String) -> bool:
	return mirror_name(b) != b


## mirror a bone rotation across the body (the character's left / right): twist and side swing flip
static func mirror_euler(e: Vector3) -> Vector3:
	return Vector3(e.x, -e.y, -e.z)


static func hint(b: String) -> String:
	var keys := HINTS.keys()
	keys.sort_custom(func(a: String, c: String) -> bool: return a.length() > c.length())
	for k in keys:
		if b.begins_with(str(k)):
			return str(HINTS[k])
	return "X / Y / Z turn the bone about its own axes"


## clamp a bone rotation to the rig limits
static func clamp_limits(b: String, e: Vector3) -> Vector3:
	var lim: Dictionary = limits().get(b, {})
	if lim.is_empty():
		return e
	var out := e
	for i in 3:
		var ax: String = ["x", "y", "z"][i]
		if lim.has(ax):
			var r: Array = lim[ax]
			out[i] = clampf(out[i], float(r[0]), float(r[1]))
	return out


## does a rotation break the rig limits (by more than a hair)?
static func breaks_limits(b: String, e: Vector3) -> bool:
	return clamp_limits(b, e).distance_to(e) > 0.01


## the limb whose end bone this is (handL -> armL), or "" when the bone is not a limb end
static func limb_of_end(b: String) -> String:
	for k in LIMBS:
		if (LIMBS[k] as Array)[2] == b:
			return str(k)
	return ""


static func limb_of(b: String) -> String:
	for k in LIMBS:
		if b in (LIMBS[k] as Array):
			return str(k)
	return ""


# ---------------------------------------------------------------- controls

## the value a control reads from a pose: the least-squares fit of value * amount to the channels it drives
static func control_value(ctl: Dictionary, pose: Dictionary) -> float:
	var num := 0.0
	var den := 0.0
	for d in (ctl.get("drives", []) as Array):
		var amt := float(d[2])
		num += amt * _chan(pose, str(d[0]), d[1])
		den += amt * amt
	if den <= 0.0:
		return 0.0
	return num / den


## set a control: each driven channel keeps whatever the control does not explain, plus value * amount
static func set_control(ctl: Dictionary, pose: Dictionary, value: float) -> Dictionary:
	var out := pose.duplicate()
	var cur := control_value(ctl, pose)
	for d in (ctl.get("drives", []) as Array):
		var amt := float(d[2])
		var bone := str(d[0])
		_set_chan(out, bone, d[1], _chan(out, bone, d[1]) + (value - cur) * amt)
	return out


static func _chan(pose: Dictionary, bone: String, ax: Variant) -> float:
	if typeof(ax) == TYPE_STRING:
		return float(pose.get("_" + str(ax), 0.0))   # "dy" -> the hips shift "_dy"
	var e: Vector3 = pose.get(bone, Vector3.ZERO)
	return e[int(ax)]


static func _set_chan(pose: Dictionary, bone: String, ax: Variant, v: float) -> void:
	if typeof(ax) == TYPE_STRING:
		pose["_" + str(ax)] = v
		return
	var e: Vector3 = pose.get(bone, Vector3.ZERO)
	e[int(ax)] = v
	pose[bone] = e
