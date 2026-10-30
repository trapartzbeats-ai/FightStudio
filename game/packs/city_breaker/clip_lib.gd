class_name CBClipLib
extends RefCounted
## Studio clips: poses keyed per frame in plain JSON (data/clips/<name>.json), turned into Godot Animation resources at runtime and
## added to a fighter's AnimationPlayer, so a clip made in the Studio plays at once, on all eight fighters (same rig), without baking.
##
##   {"version": 1, "name": "jump2", "fps": 30, "frames": 24, "loop": false, "override": false,
##    "keys": [{"f": 0, "rot": {"legL": [x, y, z], ...}, "hips_dy": 0.0}, ...]}
##
## rot = Euler radians per bone, applied as Rz * Ry * Rx on top of the bone's rest (rig v4: thigh X negative = forward, knee X
## POSITIVE = bends, arm X negative = raised forward, elbow X negative = flexed, armL Z negative / armR Z positive = out, spine X
## positive = lean forward). A hips key rotation is the whole-body spin (somersaults turn about the hips). hips_dy = hips height (hips_dx / hips_dz: the whole body shifts sideways / forward, metres)
## change in metres (rig units). A bone missing from a key is neutral at that key.

const DIR := "res://game/packs/city_breaker/data/clips/"
const FORMAT := 1


static func list_clips() -> Array:
	var out: Array = []
	if DirAccess.dir_exists_absolute(DIR):
		for f in DirAccess.get_files_at(DIR):
			if f.ends_with(".json"):
				out.append(f.get_basename())
	out.sort()
	return out


static func blank(name: String, frames: int = 24, fps: int = 30) -> Dictionary:
	return {"version": FORMAT, "name": name, "fps": fps, "frames": frames, "loop": false, "override": false,
		"keys": [{"f": 0, "rot": {}, "hips_dy": 0.0}]}


static func load_clip(name: String) -> Dictionary:
	var f := FileAccess.open(DIR + name + ".json", FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


static func save_clip(clip: Dictionary) -> int:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var f := FileAccess.open(DIR + str(clip["name"]) + ".json", FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(clip, "  "))
	f.close()
	return OK


static func delete_clip(name: String) -> void:
	var p := ProjectSettings.globalize_path(DIR + name + ".json")
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)


## rotation of a bone key: Rz * Ry * Rx (Blender's XYZ), the order every clip in this pack was authored in
static func rot_basis(e: Vector3) -> Basis:
	return Basis(Vector3.BACK, e.z) * Basis(Vector3.UP, e.y) * Basis(Vector3.RIGHT, e.x)


static func _key_rot(key: Dictionary, bone: String) -> Vector3:
	var r: Array = (key.get("rot", {}) as Dictionary).get(bone, [0.0, 0.0, 0.0])
	return Vector3(float(r[0]), float(r[1]), float(r[2]))


## the key list sorted by frame
static func sorted_keys(clip: Dictionary) -> Array:
	var keys: Array = (clip.get("keys", []) as Array).duplicate()
	keys.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["f"]) < int(b["f"]))
	return keys


## the pose at a (fractional) frame: {bone: Vector3 euler, "_dy": hips height change}, interpolated between the surrounding keys.
## Each key may carry "ease" for the stretch to the next key: "linear", "in" (slow start, whips into the next pose: strikes), "out"
## (fast start, settles), "inout" (smoothstep), "hold" (stays, then jumps), "spline" (Catmull-Rom through the neighbours: cycles).
## A clip may set "ease" for every key that has none; a clip without either is linear (older clips play as before).
static func pose_at(clip: Dictionary, frame: float, bones: Array) -> Dictionary:
	var keys := sorted_keys(clip)
	var out: Dictionary = {}
	if keys.is_empty():
		for b in bones:
			out[b] = Vector3.ZERO
		out["_dy"] = 0.0
		return out
	var ia := 0
	var ib := keys.size() - 1
	for i in keys.size():
		if float(keys[i]["f"]) <= frame:
			ia = i
		if float(keys[i]["f"]) >= frame:
			ib = i
			break
	var a: Dictionary = keys[ia]
	var b: Dictionary = keys[ib]
	var span := float(b["f"]) - float(a["f"])
	var t := 0.0 if span <= 0.0 else clampf((frame - float(a["f"])) / span, 0.0, 1.0)
	var ease := str(a.get("ease", clip.get("ease", "linear")))
	if ease == "spline" and ib != ia:
		var loop := bool(clip.get("loop", false))
		var n := keys.size()
		var p0: Dictionary = keys[ia - 1] if ia > 0 else (keys[n - 2] if loop and n > 2 else a)
		var p3: Dictionary = keys[ib + 1] if ib + 1 < n else (keys[1] if loop and n > 2 else b)
		for bone in bones:
			out[bone] = _catmull(_key_rot(p0, bone), _key_rot(a, bone), _key_rot(b, bone), _key_rot(p3, bone), t)
		for k in ["dy", "dx", "dz"]:
			var c := _catmull(Vector3(float(p0.get("hips_" + k, 0.0)), 0, 0), Vector3(float(a.get("hips_" + k, 0.0)), 0, 0),
				Vector3(float(b.get("hips_" + k, 0.0)), 0, 0), Vector3(float(p3.get("hips_" + k, 0.0)), 0, 0), t)
			out["_" + k] = c.x
		return out
	t = ease_t(ease, t)
	for bone in bones:
		out[bone] = _key_rot(a, bone).lerp(_key_rot(b, bone), t)
	out["_dy"] = lerpf(float(a.get("hips_dy", 0.0)), float(b.get("hips_dy", 0.0)), t)
	out["_dx"] = lerpf(float(a.get("hips_dx", 0.0)), float(b.get("hips_dx", 0.0)), t)
	out["_dz"] = lerpf(float(a.get("hips_dz", 0.0)), float(b.get("hips_dz", 0.0)), t)
	return out


static func ease_t(ease: String, t: float) -> float:
	match ease:
		"in":
			return t * t * t
		"out":
			return 1.0 - pow(1.0 - t, 3.0)
		"inout":
			return t * t * (3.0 - 2.0 * t)
		"hold":
			return 0.0 if t < 1.0 else 1.0
	return t


static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


## Fingered rigs (rig v4 + three fingers and a two-joint thumb, 2026-10-28): fingers / tips stay the middle finger, and each new bone
## follows the old key it replaces (times a share), plus any key of its own. So every clip keyed with fingers / tips / thumb closes the
## whole hand, and a clip can still pose one finger on its own.
const FOLLOW := {
	"indexL": ["fingersL", 1.0], "pinkyL": ["fingersL", 1.0], "indexL2": ["tipsL", 1.0], "pinkyL2": ["tipsL", 1.0],
	"nailL": ["tipsL", 0.7], "indexL3": ["tipsL", 0.7], "pinkyL3": ["tipsL", 0.7], "thumbL2": ["thumbL", 0.8],
	"indexR": ["fingersR", 1.0], "pinkyR": ["fingersR", 1.0], "indexR2": ["tipsR", 1.0], "pinkyR2": ["tipsR", 1.0],
	"nailR": ["tipsR", 0.7], "indexR3": ["tipsR", 0.7], "pinkyR3": ["tipsR", 0.7], "thumbR2": ["thumbR", 0.8],
	# four-fingered rigs (Slum) add a ring finger
	"ringL": ["fingersL", 1.0], "ringL2": ["tipsL", 1.0], "ringL3": ["tipsL", 0.7],
	"ringR": ["fingersR", 1.0], "ringR2": ["tipsR", 1.0], "ringR3": ["tipsR", 0.7],
}


## FINGER RETARGET (2026-10-30). Finger turns in clips are kept on ONE shared hand (data/finger_frames.json "shared_hands",
## the average of every fingered fighter's hand) and each fighter turns them onto its own hand when a pose goes on the
## skeleton: R_own = M * R * M^T, M = own hand frame * shared hand frame^T (one per hand: wrist -> knuckles, across the
## knuckles, the palm). The models' hands sit up to ~50 degrees apart, so the same numbers curled one hand and bent another
## sideways. Fighters without finger frames (plain rig v4 hands) play the numbers as they are.
const FINGER_FRAMES := "res://game/packs/city_breaker/data/finger_frames.json"
const FINGER_BONES := ["fingers", "tips", "nail", "thumb", "thumb%s2", "index", "index%s2", "index%s3", "ring", "ring%s2",
	"ring%s3", "pinky", "pinky%s2", "pinky%s3"]
static var _finger_data: Dictionary = {}
static var _finger_maps: Dictionary = {}    ## fighter key -> {bone: Basis}


## data/finger_frames.json (loaded once): shared / shared_hands / hands / thickness / fighters
static func finger_data() -> Dictionary:
	if _finger_data.is_empty():
		var p: Variant = JSON.parse_string(FileAccess.get_file_as_string(FINGER_FRAMES)) if FileAccess.file_exists(FINGER_FRAMES) else null
		_finger_data = p if p is Dictionary else {"none": true}
	return _finger_data


## the fighter a skeleton belongs to (from its model's scene file <key>_fight.glb; kept on the skeleton), "" for others
static func fighter_key(skel: Skeleton3D) -> String:
	if skel.has_meta("cb_key"):
		return str(skel.get_meta("cb_key"))
	var key := ""
	var n: Node = skel
	while n != null and key == "":
		if n.scene_file_path.ends_with("_fight.glb"):
			key = n.scene_file_path.get_file().trim_suffix("_fight.glb")
		n = n.get_parent()
	skel.set_meta("cb_key", key)
	return key


## a fighter's finger retarget: bone -> M (empty when the fighter has no finger frames)
static func finger_map_of(key: String) -> Dictionary:
	if _finger_maps.has(key):
		return _finger_maps[key]
	finger_data()
	var out := {}
	var own: Dictionary = (_finger_data.get("hands", {}) as Dictionary).get(key, {})
	var sh: Dictionary = _finger_data.get("shared_hands", {})
	for side: String in ["L", "R"]:
		if not own.has(side) or not sh.has(side):
			continue
		var m := (_hand_basis(own[side]) * _hand_basis(sh[side]).transposed()).orthonormalized()
		for b: String in FINGER_BONES:
			out[(b % side) if "%s" in b else b + side] = m
	_finger_maps[key] = out
	return out


## the finger retarget of the fighter this skeleton belongs to (found from the model's scene file, then kept on it)
static func finger_map(skel: Skeleton3D) -> Dictionary:
	if skel.has_meta("cb_finger_map"):
		return skel.get_meta("cb_finger_map")
	var key := fighter_key(skel)
	var m := finger_map_of(key) if key != "" else {}
	skel.set_meta("cb_finger_map", m)
	return m


## a bone's local turn on the skeleton from its clip euler (finger joints turned onto this fighter's hand)
static func local_basis(fmap: Dictionary, name: String, e: Vector3) -> Basis:
	var b := rot_basis(e)
	if fmap.has(name):
		var m: Basis = fmap[name]
		return m * b * m.transposed()
	return b


## the other way: a bone's local turn read off the skeleton back to the clip's frame (Fight Studio's tools)
static func clip_basis(fmap: Dictionary, name: String, local: Basis) -> Basis:
	if fmap.has(name):
		var m: Basis = fmap[name]
		return m.transposed() * local * m
	return local


static func _hand_basis(h: Dictionary) -> Basis:
	var a: Array = h["along"]
	var c: Array = h["across"]
	var p: Array = h["palm"]
	return Basis(Vector3(a[0], a[1], a[2]), Vector3(c[0], c[1], c[2]), Vector3(p[0], p[1], p[2]))


## a bone's rotation in a pose, with the finger follow added
static func bone_rot(pose: Dictionary, name: String) -> Vector3:
	var e: Vector3 = pose.get(name, Vector3.ZERO)
	if FOLLOW.has(name):
		var f: Array = FOLLOW[name]
		e += (pose.get(str(f[0]), Vector3.ZERO) as Vector3) * float(f[1])
	return e


## put a pose straight on the skeleton (the Studio shows the frame you are on)
static func apply_pose(skel: Skeleton3D, pose: Dictionary) -> void:
	var fmap := finger_map(skel)
	for i in skel.get_bone_count():
		var name := skel.get_bone_name(i)
		var rest := skel.get_bone_rest(i)
		var e: Vector3 = bone_rot(pose, name)
		var t := Transform3D(rest.basis * local_basis(fmap, name, e), rest.origin)
		if name == "hips":
			t.origin += Vector3(float(pose.get("_dx", 0.0)), float(pose.get("_dy", 0.0)), float(pose.get("_dz", 0.0)))
		skel.set_bone_pose(i, t)


## an Animation resource for a fighter skeleton; `root` is the model root the AnimationPlayer's root node points at
static func build_animation(clip: Dictionary, skel: Skeleton3D, root: Node3D) -> Animation:
	var anim := Animation.new()
	var fps := float(clip.get("fps", 30))
	anim.length = maxf(float(clip.get("frames", 24)) / fps, 0.05)
	anim.loop_mode = Animation.LOOP_LINEAR if bool(clip.get("loop", false)) else Animation.LOOP_NONE
	var base := str(root.get_path_to(skel))
	var fmap := finger_map(skel)
	var keys := sorted_keys(clip)
	if _eased(clip):
		# eased / spline clips: bake a key on every clip frame from pose_at, so the Studio's player matches the game exactly
		var bones: Array = []
		for bi in skel.get_bone_count():
			bones.append(skel.get_bone_name(bi))
		var baked: Array = []
		for f in int(float(clip.get("frames", 24))) + 1:
			var pz := pose_at(clip, float(f), bones)
			var rot: Dictionary = {}
			for bn in bones:
				var e: Vector3 = pz[bn]
				rot[bn] = [e.x, e.y, e.z]
			baked.append({"f": f, "rot": rot, "hips_dy": pz.get("_dy", 0.0), "hips_dx": pz.get("_dx", 0.0), "hips_dz": pz.get("_dz", 0.0)})
		keys = baked
	for i in skel.get_bone_count():
		var name := skel.get_bone_name(i)
		var rest := skel.get_bone_rest(i)
		var rt := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(rt, NodePath("%s:%s" % [base, name]))
		anim.track_set_interpolation_type(rt, Animation.INTERPOLATION_LINEAR)
		for k in keys:
			var e := _key_rot(k, name)
			if FOLLOW.has(name):
				e += _key_rot(k, str(FOLLOW[name][0])) * float(FOLLOW[name][1])
			var q := (rest.basis * local_basis(fmap, name, e)).get_rotation_quaternion()
			anim.rotation_track_insert_key(rt, float(k["f"]) / fps, q)
		if name == "hips":
			var pt := anim.add_track(Animation.TYPE_POSITION_3D)
			anim.track_set_path(pt, NodePath("%s:%s" % [base, name]))
			anim.track_set_interpolation_type(pt, Animation.INTERPOLATION_LINEAR)
			for k in keys:
				anim.position_track_insert_key(pt, float(k["f"]) / fps, rest.origin + Vector3(float(k.get("hips_dx", 0.0)), float(k.get("hips_dy", 0.0)), float(k.get("hips_dz", 0.0))))
	return anim


static func _eased(clip: Dictionary) -> bool:
	if str(clip.get("ease", "linear")) != "linear":
		return true
	for k in (clip.get("keys", []) as Array):
		if str((k as Dictionary).get("ease", "linear")) != "linear":
			return true
	return false


## add every studio clip to a model's AnimationPlayer (a clip never replaces a baked one unless it says "override"); returns the names added
static func install(ap: AnimationPlayer, root: Node3D, skel: Skeleton3D) -> Array:
	var added: Array = []
	if ap == null or skel == null:
		return added
	var lib: AnimationLibrary = ap.get_animation_library("")
	if lib == null:
		return added
	for name in list_clips():
		var clip := load_clip(str(name))
		if clip.is_empty():
			continue
		var has := lib.has_animation(str(name))
		if has and not bool(clip.get("override", false)):
			continue
		var a := build_animation(clip, skel, root)
		if has:
			lib.remove_animation(str(name))
		lib.add_animation(str(name), a)
		added.append(str(name))
	return added
