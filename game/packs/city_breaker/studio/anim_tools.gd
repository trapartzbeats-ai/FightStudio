class_name CBAnimTools
extends RefCounted
## Studio animation tools that need no UI, so they can be tested headless:
##   * unbake: sample a BAKED animation (the dense per-frame tracks baked into a character GLB) into sparse, editable Studio keys
##   * key blend: an edit at one frame moves the keys before and after it by the same turn, fading with distance
##   * ghost blocks: translucent props kept in the clip (an edge to hang on, a crate to push) with their own keys

const FALLOFFS := ["smooth", "linear", "sharp", "constant"]


# ---------------------------------------------------------------- unbake

## the Studio euler (Rz * Ry * Rx on top of the rest) of a bone's current pose
static func euler_of(rest: Transform3D, pose: Transform3D) -> Vector3:
	return (rest.basis.inverse() * pose.basis).get_euler(EULER_ORDER_ZYX)


## sample the current skeleton pose as a Studio key at frame f
static func sample_key(skel: Skeleton3D, f: int, bones: Array) -> Dictionary:
	var rot: Dictionary = {}
	for b in bones:
		var i := skel.find_bone(str(b))
		if i < 0:
			continue
		var e := euler_of(skel.get_bone_rest(i), skel.get_bone_pose(i))
		if e.length() > 0.0005:
			rot[str(b)] = [snappedf(e.x, 0.001), snappedf(e.y, 0.001), snappedf(e.z, 0.001)]
	var dy := 0.0
	var hi := skel.find_bone("hips")
	if hi >= 0:
		dy = skel.get_bone_pose(hi).origin.y - skel.get_bone_rest(hi).origin.y
	return {"f": f, "rot": rot, "hips_dy": snappedf(dy, 0.001)}


## an editable copy of a baked animation: a key every `step` frames (30 fps), then redundant keys are dropped (tolerance in radians).
## The skeleton must be on that animation's player; the player is left paused on the last frame.
static func unbake(player: AnimationPlayer, skel: Skeleton3D, anim_name: String, bones: Array, step: int = 2, tol: float = 0.03) -> Dictionary:
	var src := player.get_animation(anim_name)
	var frames := maxi(1, int(round(src.length * 30.0)))
	player.active = true
	player.play(anim_name)
	var keys: Array = []
	var f := 0
	while f <= frames:
		player.seek(float(f) / 30.0, true)
		player.advance(0.0)
		keys.append(sample_key(skel, f, bones))
		f += maxi(1, step)
	if int((keys[keys.size() - 1] as Dictionary)["f"]) != frames:
		player.seek(float(frames) / 30.0, true)
		player.advance(0.0)
		keys.append(sample_key(skel, frames, bones))
	player.pause()
	var clip := {"version": CBClipLib.FORMAT, "name": anim_name + "_edit", "fps": 30, "frames": frames,
		"loop": src.loop_mode != Animation.LOOP_NONE, "override": false, "keys": keys, "unbaked_from": anim_name}
	reduce_keys(clip, bones, tol)
	return clip


## drop keys whose removal changes no bone by more than `tol` radians (or hips height by tol / 3 metres)
static func reduce_keys(clip: Dictionary, bones: Array, tol: float) -> int:
	var keys: Array = CBClipLib.sorted_keys(clip)
	var removed := 0
	var i := 1
	while i < keys.size() - 1:
		var a: Dictionary = keys[i - 1]
		var k: Dictionary = keys[i]
		var b: Dictionary = keys[i + 1]
		var t := float(int(k["f"]) - int(a["f"])) / float(int(b["f"]) - int(a["f"]))
		var worst := 0.0
		for bone in bones:
			var ea := CBClipLib._key_rot(a, str(bone))
			var eb := CBClipLib._key_rot(b, str(bone))
			var ek := CBClipLib._key_rot(k, str(bone))
			var d := ek - ea.lerp(eb, t)
			worst = maxf(worst, maxf(absf(d.x), maxf(absf(d.y), absf(d.z))))
		var dy := absf(float(k.get("hips_dy", 0.0)) - lerpf(float(a.get("hips_dy", 0.0)), float(b.get("hips_dy", 0.0)), t)) * 3.0
		if maxf(worst, dy) <= tol:
			keys.remove_at(i)
			removed += 1
		else:
			i += 1
	clip["keys"] = keys
	return removed


# ---------------------------------------------------------------- key blend

static func weight(kind: String, d: float, range_frames: float) -> float:
	if range_frames <= 0.0 or d >= range_frames:
		return 0.0
	var x := clampf(d / range_frames, 0.0, 1.0)
	match kind:
		"linear":
			return 1.0 - x
		"sharp":
			return pow(1.0 - x, 3.0)
		"constant":
			return 1.0
		_:
			return 1.0 - x * x * (3.0 - 2.0 * x)   # smoothstep


## an edit of `delta` ({bone: Vector3, "_dy": float}) made at `frame`: every OTHER key within `range_frames` takes a share of it,
## fading with the distance in frames (before and after alike). The key at `frame` itself is not touched here.
static func blend_neighbours(clip: Dictionary, frame: int, delta: Dictionary, range_frames: float, kind: String) -> int:
	var touched := 0
	for k in (clip["keys"] as Array):
		var kd: Dictionary = k
		var df := absf(float(int(kd["f"]) - frame))
		if df == 0.0:
			continue
		var w := weight(kind, df, range_frames)
		if w <= 0.0:
			continue
		var rot: Dictionary = kd["rot"]
		for b in delta:
			if b == "_dy":
				continue
			var d: Vector3 = delta[b]
			if d.length() < 0.0005:
				continue
			var cur := CBClipLib._key_rot(kd, str(b)) + d * w
			if (b == "kneeL" or b == "kneeR") and cur.x < 0.0:
				cur.x = 0.0   # a knee never bends forward
			rot[b] = [snappedf(cur.x, 0.001), snappedf(cur.y, 0.001), snappedf(cur.z, 0.001)]
		kd["hips_dy"] = snappedf(float(kd.get("hips_dy", 0.0)) + float(delta.get("_dy", 0.0)) * w, 0.001)
		touched += 1
	return touched


## the difference between two poses (bone -> Vector3, "_dy" -> float)
static func pose_delta(after: Dictionary, before: Dictionary, bones: Array) -> Dictionary:
	var out: Dictionary = {}
	for b in bones:
		var d: Vector3 = after.get(b, Vector3.ZERO) - before.get(b, Vector3.ZERO)
		if d.length() > 0.0005:
			out[b] = d
	out["_dy"] = float(after.get("_dy", 0.0)) - float(before.get("_dy", 0.0))
	return out


# ---------------------------------------------------------------- ghost blocks
## clip["ghosts"] = [{"name", "pos": [x, y, z], "size": [w, h, d], "yaw": degrees, "color": "#rrggbb"}]
## clip["ghost_keys"] = {name: [{"f", "pos", "yaw"}]}  (optional: the block moves while the clip plays)

static func new_ghost(name: String, pos: Vector3, size: Vector3) -> Dictionary:
	return {"name": name, "pos": [pos.x, pos.y, pos.z], "size": [size.x, size.y, size.z], "yaw": 0.0, "color": "#6fb7ff"}


## the preset every ledge animation wants: the top front edge of a deck, where a fighter's palms rest when hanging (the origin is the
## feet; the fighter faces +Z). Hang height matches CBFighter.HANG_DROP, the edge sits 0.26 m in front of the body.
static func ledge_ghost() -> Dictionary:
	var drop := 2.2
	return new_ghost("ledge", Vector3(0.0, drop - 0.7, 0.26 + 0.75), Vector3(1.6, 1.4, 1.5))


static func ghost_vec(g: Dictionary, k: String) -> Vector3:
	var a: Array = g.get(k, [0, 0, 0])
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## the block's transform data at a frame: {"pos": Vector3, "yaw": float, "size": Vector3}
static func ghost_at(clip: Dictionary, g: Dictionary, frame: float) -> Dictionary:
	var out := {"pos": ghost_vec(g, "pos"), "yaw": float(g.get("yaw", 0.0)), "size": ghost_vec(g, "size")}
	var keys: Array = (clip.get("ghost_keys", {}) as Dictionary).get(str(g["name"]), [])
	if keys.is_empty():
		return out
	keys = keys.duplicate()
	keys.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["f"]) < int(b["f"]))
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
	out["pos"] = ghost_vec(a, "pos").lerp(ghost_vec(b, "pos"), t)
	out["yaw"] = lerpf(float(a.get("yaw", 0.0)), float(b.get("yaw", 0.0)), t)
	return out


static func set_ghost_key(clip: Dictionary, name: String, f: int, pos: Vector3, yaw: float) -> void:
	var gk: Dictionary = clip.get("ghost_keys", {})
	var keys: Array = gk.get(name, [])
	for i in keys.size():
		if int((keys[i] as Dictionary)["f"]) == f:
			keys.remove_at(i)
			break
	keys.append({"f": f, "pos": [snappedf(pos.x, 0.001), snappedf(pos.y, 0.001), snappedf(pos.z, 0.001)], "yaw": snappedf(yaw, 0.1)})
	gk[name] = keys
	clip["ghost_keys"] = gk
