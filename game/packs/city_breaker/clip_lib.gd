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
## positive = lean forward). A hips key rotation is the whole-body spin (somersaults turn about the hips). hips_dy = hips height
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


## the pose at a (fractional) frame: {bone: Vector3 euler, "_dy": hips height change}, interpolated between the surrounding keys
static func pose_at(clip: Dictionary, frame: float, bones: Array) -> Dictionary:
	var keys := sorted_keys(clip)
	var out: Dictionary = {}
	if keys.is_empty():
		for b in bones:
			out[b] = Vector3.ZERO
		out["_dy"] = 0.0
		return out
	var a: Dictionary = keys[0]
	var b: Dictionary = keys[keys.size() - 1]
	for k in keys:
		if float(k["f"]) <= frame:
			a = k
		if float(k["f"]) >= frame:
			b = k
			break
	var span := float(b["f"]) - float(a["f"])
	var t := 0.0 if span <= 0.0 else clampf((frame - float(a["f"])) / span, 0.0, 1.0)
	for bone in bones:
		out[bone] = _key_rot(a, bone).lerp(_key_rot(b, bone), t)
	out["_dy"] = lerpf(float(a.get("hips_dy", 0.0)), float(b.get("hips_dy", 0.0)), t)
	return out


## put a pose straight on the skeleton (the Studio shows the frame you are on)
static func apply_pose(skel: Skeleton3D, pose: Dictionary) -> void:
	for i in skel.get_bone_count():
		var name := skel.get_bone_name(i)
		var rest := skel.get_bone_rest(i)
		var e: Vector3 = pose.get(name, Vector3.ZERO)
		var t := Transform3D(rest.basis * rot_basis(e), rest.origin)
		if name == "hips":
			t.origin += Vector3(0.0, float(pose.get("_dy", 0.0)), 0.0)
		skel.set_bone_pose(i, t)


## an Animation resource for a fighter skeleton; `root` is the model root the AnimationPlayer's root node points at
static func build_animation(clip: Dictionary, skel: Skeleton3D, root: Node3D) -> Animation:
	var anim := Animation.new()
	var fps := float(clip.get("fps", 30))
	anim.length = maxf(float(clip.get("frames", 24)) / fps, 0.05)
	anim.loop_mode = Animation.LOOP_LINEAR if bool(clip.get("loop", false)) else Animation.LOOP_NONE
	var base := str(root.get_path_to(skel))
	var keys := sorted_keys(clip)
	for i in skel.get_bone_count():
		var name := skel.get_bone_name(i)
		var rest := skel.get_bone_rest(i)
		var rt := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(rt, NodePath("%s:%s" % [base, name]))
		anim.track_set_interpolation_type(rt, Animation.INTERPOLATION_LINEAR)
		for k in keys:
			var q := (rest.basis * rot_basis(_key_rot(k, name))).get_rotation_quaternion()
			anim.rotation_track_insert_key(rt, float(k["f"]) / fps, q)
		if name == "hips":
			var pt := anim.add_track(Animation.TYPE_POSITION_3D)
			anim.track_set_path(pt, NodePath("%s:%s" % [base, name]))
			anim.track_set_interpolation_type(pt, Animation.INTERPOLATION_LINEAR)
			for k in keys:
				anim.position_track_insert_key(pt, float(k["f"]) / fps, rest.origin + Vector3(0.0, float(k.get("hips_dy", 0.0)), 0.0))
	return anim


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
