class_name FSAMotionImport
extends RefCounted
## Outside motion onto our rig: a Mixamo animation (FBX, with or without skin) or a GLB / glTF with a Mixamo-style skeleton
## becomes a clip in the game's format (data/clips JSON), so it plays on every fighter and edits like any other clip.
##
## How a bone moves: each of our bones takes its source bone's turn away from the SOURCE's rest pose, in world space, then is
## made local to our parent. Mixamo rests in a T-pose and we rest in an A-pose, so first every bone is lined up: a fixed turn
## that points our rest bone along the source's rest bone (an arm hanging down is swung up level). The hips' move away from
## rest is scaled by the hips height of the two rigs. Fingers come along on the fighters that have those finger bones.
##
## Clean-up, all optional: "in place" takes out the straight-line travel (and keeps its speed in the clip), joints are kept
## inside the rig limits (knees never bend forward), keys that a straight line between their neighbours already gives are
## dropped, and the clip is marked loop / planted when it looks like one.
##
##   var r := FSAMotionImport.load_source("C:/Users/User/Downloads/Capoeira Spin Kick.fbx", holder)
##   var clip := FSAMotionImport.retarget(r, our_skeleton, {"name": "capoeira_kick", "in_place": true})

const SIDE := {"L": "Right", "R": "Left"}   ## our L is Mixamo's Right: both rigs face +Z (as bpy_rig_from_mixamo.py, film-strip checked)
const FPS_OUT := 60


## our bone -> the source bone (name without the "mixamorig" prefix) whose motion it takes
static func source_map() -> Dictionary:
	var m := {"hips": "Hips", "torso": "Spine", "chest": "Spine2", "neck": "Neck", "head": "Head"}
	for s in SIDE:
		var mx: String = SIDE[s]
		m["leg" + s] = mx + "UpLeg"
		m["knee" + s] = mx + "Leg"
		m["foot" + s] = mx + "Foot"
		m["arm" + s] = mx + "Arm"
		m["elbow" + s] = mx + "ForeArm"
		m["hand" + s] = mx + "Hand"
		m["fingers" + s] = mx + "HandMiddle1"
		m["tips" + s] = mx + "HandMiddle2"
		m["nail" + s] = mx + "HandMiddle3"
		m["thumb" + s] = mx + "HandThumb1"
		m["thumb" + s + "2"] = mx + "HandThumb2"
		for j in 3:
			var suf := "" if j == 0 else str(j + 1)
			m["index" + s + suf] = mx + "HandIndex" + str(j + 1)
			m["ring" + s + suf] = mx + "HandRing" + str(j + 1)
			m["pinky" + s + suf] = mx + "HandPinky" + str(j + 1)
	return m


## the next joint along a source bone (what its direction points at); empty = the bone keeps its parent's line-up
static func _src_next(name: String) -> String:
	for mx in ["Left", "Right"]:
		var t := {mx + "Arm": mx + "ForeArm", mx + "ForeArm": mx + "Hand", mx + "Hand": mx + "HandMiddle1",
			mx + "UpLeg": mx + "Leg", mx + "Leg": mx + "Foot"}
		if t.has(name):
			return t[name]
		for f in ["Thumb", "Index", "Middle", "Ring", "Pinky"]:
			for j in 3:
				if name == mx + "Hand" + f + str(j + 1):
					return mx + "Hand" + f + str(j + 2)
	return ""


## the next joint along one of our bones (rig v4); empty = it keeps its parent's line-up
static func _our_next(name: String) -> String:
	for s in ["L", "R"]:
		var t := {"arm" + s: "elbow" + s, "elbow" + s: "hand" + s, "hand" + s: "fingers" + s, "leg" + s: "knee" + s,
			"knee" + s: "foot" + s, "fingers" + s: "tips" + s, "tips" + s: "nail" + s, "thumb" + s: "thumb" + s + "2",
			"index" + s: "index" + s + "2", "index" + s + "2": "index" + s + "3", "ring" + s: "ring" + s + "2",
			"ring" + s + "2": "ring" + s + "3", "pinky" + s: "pinky" + s + "2", "pinky" + s + "2": "pinky" + s + "3"}
		if t.has(name):
			return t[name]
	return ""


## a source bone's name without its rig prefix ("mixamorig:Hips", "mixamorig1_Hips" -> "Hips")
static func plain(bone: String) -> String:
	var re := RegEx.new()
	re.compile("^mixamorig\\d*[:_](.+)$")
	var m := re.search(bone)
	return m.get_string(1) if m != null else bone


## load an FBX / GLB / glTF under `parent` (it must be in the scene tree so its animation can play):
## {"scene", "skel", "player", "anims": [names with tracks], "error"}
static func load_source(path: String, parent: Node) -> Dictionary:
	var doc: GLTFDocument = FBXDocument.new() if path.get_extension().to_lower() == "fbx" else GLTFDocument.new()
	var state: GLTFState = FBXState.new() if doc is FBXDocument else GLTFState.new()
	var err := doc.append_from_file(path, state)
	if err != OK:
		return {"error": "could not read %s (error %d)" % [path.get_file(), err]}
	var scene := doc.generate_scene(state, 30.0)
	if scene == null:
		return {"error": "%s has no scene" % path.get_file()}
	parent.add_child(scene)
	var sks := scene.find_children("*", "Skeleton3D", true, false)
	var aps := scene.find_children("*", "AnimationPlayer", true, false)
	if sks.is_empty() or aps.is_empty():
		scene.queue_free()
		return {"error": "%s has no skeleton animation" % path.get_file()}
	var ap := aps[0] as AnimationPlayer
	var anims: Array = []
	for an in ap.get_animation_list():
		if ap.get_animation(an).get_track_count() > 0:
			anims.append(str(an))
	# the animation with the most tracks first (Mixamo files carry an empty "Take 001" next to "mixamo_com")
	anims.sort_custom(func(a: String, b: String) -> bool: return ap.get_animation(a).get_track_count() > ap.get_animation(b).get_track_count())
	if anims.is_empty():
		scene.queue_free()
		return {"error": "%s has no animation" % path.get_file()}
	return {"scene": scene, "skel": sks[0], "player": ap, "anims": anims, "path": path}


## our bone -> source bone index, for the bones both rigs have
static func _pairs(src: Skeleton3D, ours: Skeleton3D) -> Dictionary:
	var by_plain := {}
	for i in src.get_bone_count():
		by_plain[plain(src.get_bone_name(i))] = i
	var out := {}
	var m := source_map()
	for ob in m:
		var oi := ours.find_bone(str(ob))
		if oi >= 0 and by_plain.has(m[ob]):
			out[oi] = by_plain[m[ob]]
	return out


## the clip: options {"name", "anim", "in_place" (true), "limits" (true), "fingers" (true), "tolerance" (0.015), "plant" ("auto"
## / true / false), "loop" ("auto" / true / false)}. Returns {"clip", "report"} or {"error"}.
static func retarget(source: Dictionary, ours: Skeleton3D, opts: Dictionary = {}) -> Dictionary:
	if source.has("error"):
		return source
	var src: Skeleton3D = source["skel"]
	var ap: AnimationPlayer = source["player"]
	var anim_name: String = str(opts.get("anim", source["anims"][0]))
	var anim := ap.get_animation(anim_name)
	var pairs := _pairs(src, ours)
	if not pairs.has(ours.find_bone("hips")) or pairs.size() < 10:
		return {"error": "not a humanoid we know (matched %d bones); Mixamo skeletons work" % pairs.size()}
	var fingers := bool(opts.get("fingers", true))
	if not fingers:
		for oi in pairs.keys():
			var n := ours.get_bone_name(oi)
			if n.begins_with("fingers") or n.begins_with("tips") or n.begins_with("nail") or n.begins_with("thumb") \
					or n.begins_with("index") or n.begins_with("ring") or n.begins_with("pinky"):
				pairs.erase(oi)
	# rests: rotations (skeleton space) and joint positions
	var src_by_plain := {}
	for i in src.get_bone_count():
		src_by_plain[plain(src.get_bone_name(i))] = i
	var src_rest := {}
	for i in src.get_bone_count():
		src_rest[i] = src.get_bone_global_rest(i)
	var our_rest := {}
	for i in ours.get_bone_count():
		our_rest[i] = ours.get_bone_global_rest(i)
	# the line-up: for each paired bone, the turn that points our rest bone along the source's rest bone (world space)
	var align := {}
	for i in ours.get_bone_count():
		var c := Quaternion.IDENTITY
		var par := ours.get_bone_parent(i)
		if par >= 0 and align.has(par):
			c = align[par]
		if pairs.has(i):
			var sn := plain(src.get_bone_name(pairs[i]))
			var nxt_s := _src_next(sn)
			var nxt_o := _our_next(ours.get_bone_name(i))
			var oj := ours.find_bone(nxt_o) if nxt_o != "" else -1
			if nxt_s != "" and src_by_plain.has(nxt_s) and oj >= 0:
				var ds: Vector3 = (src_rest[src_by_plain[nxt_s]] as Transform3D).origin - (src_rest[pairs[i]] as Transform3D).origin
				var do_: Vector3 = (our_rest[oj] as Transform3D).origin - (our_rest[i] as Transform3D).origin
				if ds.length() > 1e-5 and do_.length() > 1e-5:
					c = Quaternion(do_.normalized(), ds.normalized())
		align[i] = c
	# hips: how far the source moved from its rest, in our size
	var src_hips := int(src_by_plain["Hips"])
	var our_hips := ours.find_bone("hips")
	var scale := (our_rest[our_hips] as Transform3D).origin.y / maxf((src_rest[src_hips] as Transform3D).origin.y, 1e-4)
	# sample every source frame (30 fps) onto our 60 fps clip frames
	var frames30 := maxi(1, int(round(anim.length * 30.0)))
	ap.active = true
	ap.play(anim_name)
	var keys: Array = []
	var prev := {}
	var hips_moves: Array = []
	var bones: Array = []
	for i in ours.get_bone_count():
		bones.append(ours.get_bone_name(i))
	for f30 in frames30 + 1:
		ap.seek(float(f30) / 30.0, true)
		ap.advance(0.0)
		src.force_update_all_bone_transforms()
		var g := {}      # our bone -> global pose rotation (skeleton space)
		var rot := {}
		for i in ours.get_bone_count():
			var par := ours.get_bone_parent(i)
			var gp: Quaternion = g[par] if par >= 0 else Quaternion.IDENTITY
			var rest_local := ours.get_bone_rest(i).basis.orthonormalized().get_rotation_quaternion()
			if not pairs.has(i):
				g[i] = gp * rest_local
				continue
			var si: int = pairs[i]
			var delta := src.get_bone_global_pose(si).basis.orthonormalized().get_rotation_quaternion() \
				* (src_rest[si] as Transform3D).basis.orthonormalized().get_rotation_quaternion().inverse()
			var gq: Quaternion = delta * (align[i] as Quaternion) * (our_rest[i] as Transform3D).basis.orthonormalized().get_rotation_quaternion()
			g[i] = gq
			var local := gp.inverse() * gq
			var e := Basis(rest_local.inverse() * local).get_euler(EULER_ORDER_ZYX)
			var bn := ours.get_bone_name(i)
			if prev.has(bn):
				e = FSAEval.nearest_euler(e, prev[bn])
			prev[bn] = e
			if e.length() > 1e-4:
				rot[bn] = [snappedf(e.x, 0.0001), snappedf(e.y, 0.0001), snappedf(e.z, 0.0001)]
		var hp := src.get_bone_global_pose(src_hips).origin - (src_rest[src_hips] as Transform3D).origin
		hips_moves.append(hp * scale)
		keys.append({"f": int(round(float(f30) * FPS_OUT / 30.0)), "rot": rot})
	ap.pause()
	ap.active = false
	# in place: take the straight-line travel out of the hips (keep the sway), remember the speed
	var travel := Vector3.ZERO
	var n := hips_moves.size()
	if bool(opts.get("in_place", true)) and n > 1:
		var dur := float(n - 1) / 30.0
		travel = ((hips_moves[n - 1] as Vector3) - (hips_moves[0] as Vector3)) / dur
		travel.y = 0.0
	for k in n:
		var t := float(k) / 30.0
		var h: Vector3 = (hips_moves[k] as Vector3) - travel * t
		keys[k]["hips_dx"] = snappedf(h.x, 0.0001)
		keys[k]["hips_dy"] = snappedf(h.y, 0.0001)
		keys[k]["hips_dz"] = snappedf(h.z, 0.0001)
	# natural ranges (the rig limits: knees never bend forward)
	var clamped := 0
	if bool(opts.get("limits", true)):
		for k in keys:
			var r: Dictionary = k["rot"]
			for bn in r:
				var e := Vector3(r[bn][0], r[bn][1], r[bn][2])
				var cl := FSARig.clamp_limits(str(bn), e)
				if not cl.is_equal_approx(e):
					if cl.distance_to(e) > 0.01:
						clamped += 1   # the report counts the ones you could see; even a hair is clamped (knees NEVER bend forward)
					r[bn] = [snappedf(cl.x, 0.0001), snappedf(cl.y, 0.0001), snappedf(cl.z, 0.0001)]
	var name := str(opts.get("name", ""))
	if name == "":
		name = suggest_name(str(source.get("path", anim_name)))
	var clip := {"version": CBClipLib.FORMAT, "name": name, "fps": FPS_OUT, "frames": int(keys[keys.size() - 1]["f"]), "loop": false,
		"override": true, "plant": false, "keys": keys,
		"note": "imported from %s (%s) by Fight Studio" % [str(source.get("path", "")).get_file(), anim_name],
		"import": {"source": str(source.get("path", "")), "anim": anim_name, "in_place": bool(opts.get("in_place", true)),
			"travel": [snappedf(travel.x, 0.001), snappedf(travel.z, 0.001)], "scale": snappedf(scale, 0.0001)}}
	# loop: first and last pose (nearly) the same
	var loop_opt: Variant = opts.get("loop", "auto")
	var loops := _same_pose(keys[0], keys[keys.size() - 1], bones, 0.12)
	clip["loop"] = loops if str(loop_opt) == "auto" else bool(loop_opt)
	# planted: never leaves the ground (the hips never rise much above their rest height)
	var plant_opt: Variant = opts.get("plant", "auto")
	var rise := 0.0
	for k in keys:
		rise = maxf(rise, float(k["hips_dy"]))
	var rest_h := (our_rest[our_hips] as Transform3D).origin.y
	clip["plant"] = rise < rest_h * 0.12 if str(plant_opt) == "auto" else bool(plant_opt)
	var before := keys.size()
	CBAnimTools.reduce_keys(clip, bones, float(opts.get("tolerance", 0.015)))
	var report := {"name": name, "anim": anim_name, "bones": pairs.size(), "frames": clip["frames"], "keys": (clip["keys"] as Array).size(),
		"sampled": before, "clamped": clamped, "loop": clip["loop"], "plant": clip["plant"], "travel_per_s": [travel.x, travel.z]}
	return {"clip": clip, "report": report}


static func _same_pose(a: Dictionary, b: Dictionary, bones: Array, tol: float) -> bool:
	for bn in bones:
		var ea := CBClipLib._key_rot(a, str(bn))
		var eb := CBClipLib._key_rot(b, str(bn))
		var d := ea - eb
		if maxf(absf(d.x), maxf(absf(d.y), absf(d.z))) > tol:
			return false
	return absf(float(a.get("hips_dy", 0.0)) - float(b.get("hips_dy", 0.0))) < 0.05


## a clip name from a file name: "Capoeira Spin Kick.fbx" -> "mx_capoeira_spin_kick"
static func suggest_name(path: String) -> String:
	var base := path.get_file().get_basename().to_lower()
	var out := ""
	for ch in base:
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	return "mx_" + out.strip_edges().trim_prefix("_").trim_suffix("_")
