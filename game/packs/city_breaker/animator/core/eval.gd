class_name FSAEval
extends RefCounted
## Turns a document into poses.
##
##   pose = base keys (CBClipLib.pose_at, the game's own interpolation)
##        + layers, bottom to top: "add" (adds its rotations), "add_delta" (adds a clip's motion relative to its own first
##          frame), "override" (blends toward its pose); each with a weight, a frame range with fade in / out, a bone mask,
##          mute / solo; a layer's source is its own keys or another clip (offset, speed, cycle)
##   then constraints, in list order, on the skeleton: ik, pin (freeze a bone in the world), aim, limit, copy_rot, floor
##
## Positions in constraints are WORLD metres with the model standing at the origin, facing +Z (what you see in the Animator).
## Every skeleton the Animator poses stands at the origin, so world <-> skeleton space is the skeleton node's own transform.

static var _clips: Dictionary = {}


static func clip_src(n: String) -> Dictionary:
	if not _clips.has(n):
		_clips[n] = CBClipLib.load_clip(n)
	return _clips[n]


static func forget_clips() -> void:
	_clips.clear()


# ---------------------------------------------------------------- layers

static func _smooth01(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## a layer's weight at frame f: its weight, zero outside its range, faded in / out at the ends
static func layer_weight(l: Dictionary, f: float, frames: int) -> float:
	var w := float(l.get("weight", 1.0))
	var a := float(l.get("start", 0))
	var b := float(l.get("end", -1))
	if b < 0.0:
		b = float(frames)
	if f < a - 0.001 or f > b + 0.001:
		return 0.0
	var fi := float(l.get("fade_in", 0))
	var fo := float(l.get("fade_out", 0))
	if fi > 0.0 and f < a + fi:
		w *= _smooth01((f - a) / fi)
	if fo > 0.0 and f > b - fo:
		w *= _smooth01((b - f) / fo)
	return w


## the bones a layer drives
static func layer_bones(l: Dictionary, bones: Array) -> Array:
	var masked := FSARig.mask_bones(l.get("mask", []) as Array, bones)
	if str(l.get("source", "keys")) != "keys":
		return masked
	var used: Dictionary = {}
	for k in (l.get("keys", []) as Array):
		for b in ((k as Dictionary).get("rot", {}) as Dictionary):
			used[b] = true
		if absf(float((k as Dictionary).get("hips_dy", 0.0))) + absf(float((k as Dictionary).get("hips_dx", 0.0))) + absf(float((k as Dictionary).get("hips_dz", 0.0))) > 0.0:
			used["hips"] = true
	var out: Array = []
	for b in masked:
		if used.has(b):
			out.append(b)
	return out


## the layer's own pose at frame f
static func layer_value(l: Dictionary, f: float, bones: Array, doc_loop: bool) -> Dictionary:
	if str(l.get("source", "keys")) == "clip":
		var c := clip_src(str(l.get("clip", "")))
		if c.is_empty():
			return {}
		var n := float(c.get("frames", 24))
		var t := (f - float(l.get("offset", 0))) * float(l.get("speed", 1.0))
		t = fposmod(t, n) if bool(l.get("cycle", true)) else clampf(t, 0.0, n)
		var p := CBClipLib.pose_at(c, t, bones)
		if str(l.get("mode", "add")) == "add_delta":
			var ref := CBClipLib.pose_at(c, float(l.get("ref", 0)), bones)
			for b in bones:
				p[b] = (p[b] as Vector3) - (ref[b] as Vector3)
			for ax in ["_dy", "_dx", "_dz"]:
				p[ax] = float(p.get(ax, 0.0)) - float(ref.get(ax, 0.0))
		return p
	var ks: Array = l.get("keys", [])
	if ks.is_empty():
		return {}
	return CBClipLib.pose_at({"keys": ks, "loop": doc_loop, "ease": str(l.get("ease", "linear"))}, f, bones)


## base keys + layers (no skeleton needed). skip_id: leave one layer out (editing a layer measures what lies under it)
static func layer_pose(doc: FSADoc, f: float, bones: Array, skip_id: String = "") -> Dictionary:
	var pose := doc.base_pose(f, bones)
	var solo := false
	for l in doc.layers:
		if bool((l as Dictionary).get("solo", false)) and not bool((l as Dictionary).get("mute", false)):
			solo = true
	for l in doc.layers:
		var ld: Dictionary = l
		if bool(ld.get("mute", false)) or (solo and not bool(ld.get("solo", false))) or str(ld.get("id", "")) == skip_id:
			continue
		var w := layer_weight(ld, f, doc.frames)
		if w <= 0.0:
			continue
		var lp := layer_value(ld, f, bones, doc.loop)
		if lp.is_empty():
			continue
		var mode := str(ld.get("mode", "add"))
		var lb := layer_bones(ld, bones)
		var adj := bool(ld.get("adjust", false))
		for b in lb:
			var cur: Vector3 = pose.get(b, Vector3.ZERO)
			var v: Vector3 = lp.get(b, Vector3.ZERO)
			var nv: Vector3 = cur.lerp(v, w) if mode == "override" else cur + v * w
			if adj:
				nv = _within_limits(str(b), nv, cur)
			pose[b] = nv
		if "hips" in lb:
			for ax in ["_dy", "_dx", "_dz"]:
				var c0 := float(pose.get(ax, 0.0))
				var v0 := float(lp.get(ax, 0.0))
				pose[ax] = lerpf(c0, v0, w) if mode == "override" else c0 + v0 * w
	return pose


## an adjustment never turns a joint past its rig limits (knees never bend forward); where the clip itself is already past a
## limit, the clip's own value is the edge (an adjustment never makes it worse)
static func _within_limits(b: String, e: Vector3, before: Vector3) -> Vector3:
	var lim: Dictionary = FSARig.limits().get(b, {})
	if lim.is_empty():
		return e
	var out := e
	for i in 3:
		var ax: String = ["x", "y", "z"][i]
		if lim.has(ax):
			var r: Array = lim[ax]
			out[i] = clampf(e[i], minf(float(r[0]), before[i]), maxf(float(r[1]), before[i]))
	return out


# ---------------------------------------------------------------- constraints

static func has_live_constraints(doc: FSADoc) -> bool:
	for c in doc.constraints:
		if bool((c as Dictionary).get("enabled", true)) and float((c as Dictionary).get("influence", 1.0)) > 0.0:
			return true
	return false


## a constraint's strength at frame f (influence, its range, a soft edge of `blend` frames)
static func con_weight(c: Dictionary, f: float, frames: int) -> float:
	if not bool(c.get("enabled", true)):
		return 0.0
	var w := float(c.get("influence", 1.0))
	var a := float(c.get("start", 0))
	var b := float(c.get("end", -1))
	if b < 0.0:
		b = float(frames)
	if f < a - 0.001 or f > b + 0.001:
		return 0.0
	var bl := float(c.get("blend", 0))
	if bl > 0.0:
		var w_in := _smooth01((f - a) / bl) if a > 0.0 else 1.0
		var w_out := _smooth01((b - f) / bl) if b < float(frames) else 1.0
		w *= minf(w_in, w_out)
	return w


## the final pose at frame f: layers, then constraints solved on `skel` (left posed). ctx caches pin captures; clear it whenever
## the document changes.
static func final_pose(doc: FSADoc, f: float, skel: Skeleton3D, bones: Array, ctx: Dictionary) -> Dictionary:
	return solve_pose(doc, f, skel, bones, ctx, layer_pose(doc, f, bones))


## constraints on a given pose (the pose before constraints: keys + layers, or an edit not keyed yet)
static func solve_pose(doc: FSADoc, f: float, skel: Skeleton3D, bones: Array, ctx: Dictionary, pose: Dictionary) -> Dictionary:
	if skel == null or not has_live_constraints(doc):
		if skel != null:
			CBClipLib.apply_pose(skel, pose)
		return pose
	_capture_pins(doc, skel, bones, ctx)
	CBClipLib.apply_pose(skel, pose)
	skel.force_update_all_bone_transforms()
	var touched: Dictionary = {}
	for c in doc.constraints:
		var cd: Dictionary = c
		var w := con_weight(cd, f, doc.frames)
		if w <= 0.0:
			continue
		match str(cd.get("type", "")):
			"ik":
				_ik(cd, f, skel, w, touched, ctx)
			"pin":
				_pin(cd, skel, w, touched, ctx)
			"aim":
				_aim(cd, f, skel, w, touched)
			"limit":
				_limit(cd, skel, w, touched)
			"copy_rot":
				_copy_rot(cd, skel, w, touched)
			"floor":
				_floor(cd, skel, w, touched, ctx)
		skel.force_update_all_bone_transforms()
	return read_back(skel, pose, touched)


## pose dict from the skeleton for the bones constraints touched (the rest keep their exact values, so no Euler flips creep in)
static func read_back(skel: Skeleton3D, pose: Dictionary, touched: Dictionary) -> Dictionary:
	var out := pose.duplicate()
	var leaders_first: Array = []
	var followers: Array = []
	for i in touched:
		var bn := skel.get_bone_name(int(i))
		if CBClipLib.FOLLOW.has(bn):
			followers.append(int(i))
		else:
			leaders_first.append(int(i))
	for i in leaders_first + followers:
		var bn := skel.get_bone_name(i)
		var rest := skel.get_bone_rest(i)
		var local := skel.get_bone_pose(i)
		var e := (rest.basis.orthonormalized().inverse() * local.basis.orthonormalized()).get_euler(EULER_ORDER_ZYX)
		if CBClipLib.FOLLOW.has(bn):
			var fl: Array = CBClipLib.FOLLOW[bn]
			e -= (out.get(str(fl[0]), Vector3.ZERO) as Vector3) * float(fl[1])
		out[bn] = nearest_euler(e, pose.get(bn, Vector3.ZERO))
		if bn == "hips":
			var d := local.origin - rest.origin
			out["_dx"] = d.x
			out["_dy"] = d.y
			out["_dz"] = d.z
	return out


## the Euler triple for the same rotation that lies nearest `ref` (keeps interpolation from spinning the long way)
static func nearest_euler(e: Vector3, ref: Vector3) -> Vector3:
	var best := e
	var bd := INF
	for cand in [e, Vector3(e.x + PI, PI - e.y, e.z + PI)]:
		var c: Vector3 = cand
		for i in 3:
			c[i] = ref[i] + wrapf(c[i] - ref[i], -PI, PI)
		var d := c.distance_squared_to(ref)
		if d < bd:
			bd = d
			best = c
	return best


static func _w2s(skel: Skeleton3D, p: Vector3) -> Vector3:
	return skel.global_transform.affine_inverse() * p


static func s2w(skel: Skeleton3D, p: Vector3) -> Vector3:
	return skel.global_transform * p


static func _v3(a: Variant, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	if a is Vector3:
		return a
	if typeof(a) == TYPE_ARRAY and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return fallback


## a keyed / fixed world point: {"pos": [x,y,z]} or {"keys": [{f, pos}]} (linear between keys) or {"bone": name, "offset": [..]}
static func target_point(spec: Dictionary, f: float, skel: Skeleton3D) -> Vector3:
	if spec.has("bone") and str(spec["bone"]) != "":
		var bi := skel.find_bone(str(spec["bone"]))
		if bi >= 0:
			var g := skel.get_bone_global_pose(bi)
			return s2w(skel, g.origin + g.basis * _v3(spec.get("offset", [0, 0, 0])))
	var ks: Array = spec.get("keys", [])
	if not ks.is_empty():
		var a: Dictionary = ks[0]
		if f <= float(a["f"]):
			return _v3(a["pos"])
		for i in range(1, ks.size()):
			var b: Dictionary = ks[i]
			if f <= float(b["f"]):
				var span := float(b["f"]) - float(a["f"])
				var t := 0.0 if span <= 0.0 else (f - float(a["f"])) / span
				return _v3(a["pos"]).lerp(_v3(b["pos"]), t)
			a = b
		return _v3(a["pos"])
	return _v3(spec.get("pos", [0, 1, 0.3]))


## set a bone's rotation in skeleton space (blended by w with its current one)
static func _set_global_basis(skel: Skeleton3D, i: int, want: Basis, w: float) -> void:
	var p := skel.get_bone_parent(i)
	var pb := skel.get_bone_global_pose(p).basis.orthonormalized() if p >= 0 else Basis()
	var local := (pb.inverse() * want.orthonormalized()).get_rotation_quaternion()
	var cur := skel.get_bone_pose_rotation(i)
	skel.set_bone_pose_rotation(i, cur.slerp(local, clampf(w, 0.0, 1.0)))


static func _arc(u: Vector3, v: Vector3) -> Basis:
	var a := u.normalized()
	var b := v.normalized()
	var ax := a.cross(b)
	var d := clampf(a.dot(b), -1.0, 1.0)
	if ax.length() < 1e-7:
		if d > 0.0:
			return Basis()
		var perp := a.cross(Vector3.UP) if absf(a.dot(Vector3.UP)) < 0.9 else a.cross(Vector3.RIGHT)
		return Basis(perp.normalized(), PI)
	return Basis(ax.normalized(), acos(d))


## two-bone IK in skeleton space. pole = a point the knee / elbow points toward (Vector3.INF: none given; a hinge keeps the
## plane it already bends in, any other limb uses auto_pole). end_basis: hold the end bone's global orientation (feet stay
## flat, a pinned hand keeps its angle); null = the end bone turns with the lower bone.
static func solve_two_bone(skel: Skeleton3D, ia: int, ib: int, ic: int, target: Vector3, pole: Vector3, end_basis: Variant, w: float) -> void:
	if is_hinge(skel.get_bone_name(ib)):
		_solve_hinge(skel, ia, ib, ic, target, pole, end_basis, w)
		return
	if not pole.is_finite():
		pole = auto_pole(skel, skel.get_bone_name(ia), ia, ib, ic)
	var ga := skel.get_bone_global_pose(ia)
	var gb := skel.get_bone_global_pose(ib)
	var gc := skel.get_bone_global_pose(ic)
	var pa := ga.origin
	var pb := gb.origin
	var pc := gc.origin
	var l1 := pa.distance_to(pb)
	var l2 := pb.distance_to(pc)
	if l1 < 1e-5 or l2 < 1e-5:
		return
	var to := target - pa
	if to.length() < 1e-5:
		return
	var dir := to.normalized()
	var d := clampf(to.length(), absf(l1 - l2) + 1e-4, l1 + l2 - 1e-4)
	var pv := pole - pa
	var u := pv - dir * pv.dot(dir)
	if u.length() < 1e-6:
		u = (pb - pa) - dir * (pb - pa).dot(dir)
	if u.length() < 1e-6:
		u = dir.cross(Vector3.RIGHT)
	u = u.normalized()
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var pb2 := pa + dir * (cos_a * l1) + u * (sqrt(1.0 - cos_a * cos_a) * l1)
	var pc2 := pa + dir * d
	var od := (pb - pa).normalized()
	var on := (pb - pa).cross(pc - pb)
	if on.length() < 1e-7:
		on = (pb - pa).cross(pole - pa)
	if on.length() < 1e-7:
		on = od.cross(Vector3.RIGHT)
	on = on.normalized()
	var nd := (pb2 - pa).normalized()
	var nn := (pb2 - pa).cross(pc2 - pb2)
	if nn.length() < 1e-7:
		nn = on
	nn = nn.normalized()
	var f_old := Basis(od, on, od.cross(on))
	var f_new := Basis(nd, nn, nd.cross(nn))
	var r1 := f_new * f_old.transposed()
	var low_now := r1 * (pc - pb).normalized()
	var r2 := _arc(low_now, (pc2 - pb2).normalized())
	_set_global_basis(skel, ia, r1 * ga.basis.orthonormalized(), w)
	skel.force_update_all_bone_transforms()
	_set_global_basis(skel, ib, r2 * r1 * gb.basis.orthonormalized(), w)
	skel.force_update_all_bone_transforms()
	if end_basis is Basis:
		_set_global_basis(skel, ic, end_basis as Basis, w)


## joints that bend on one axis only (data/animator_rig.json "hinge"): knees and elbows
static func is_hinge(b: String) -> bool:
	return b in (FSARig.data().get("hinge", ["elbowL", "elbowR", "kneeL", "kneeR"]) as Array)


## two-bone IK for a hinge (knee, elbow): the middle joint only bends on its X, inside its limits (a knee never bends forward
## and never twists), the upper bone aims the limb at the target along the shortest arc (the bend keeps the plane the limb
## already bends in), then, when a pole is given, turns about that line so the joint points at it. The joint limits never
## fight the result: the free solve put twist into the thigh that the limits then clamped, and the foot missed.
static func _solve_hinge(skel: Skeleton3D, ia: int, ib: int, ic: int, target: Vector3, pole: Vector3, end_basis: Variant, w: float) -> void:
	var before := [skel.get_bone_pose_rotation(ia), skel.get_bone_pose_rotation(ib), skel.get_bone_pose_rotation(ic)]
	var ga := skel.get_bone_global_pose(ia)
	var pa := ga.origin
	var want := pa.distance_to(target)
	if want < 1e-5:
		return
	var bname := skel.get_bone_name(ib)
	var rest_b := skel.get_bone_rest(ib).basis.orthonormalized()
	var e := FSARig.clamp_limits(bname, (rest_b.inverse() * Basis(skel.get_bone_pose_rotation(ib))).get_euler(EULER_ORDER_ZYX))
	var lim: Dictionary = FSARig.limits().get(bname, {})
	var r: Array = lim.get("x", [-PI, PI])
	var lo := float(r[0])
	var hi := float(r[1])
	# where the end joint lands for a bend x (the upper bone as it is now): pb + Gb(x) * c's local offset
	var pb := pa + ga.basis * skel.get_bone_pose_position(ib)
	var sb := skel.get_bone_pose_scale(ib)
	var oc := skel.get_bone_pose_position(ic)
	var miss := func(x: float) -> float:
		var gb := ga.basis * (rest_b * Basis.from_euler(Vector3(x, e.y, e.z), EULER_ORDER_ZYX)).scaled(sb)
		return absf(pa.distance_to(pb + gb * oc) - want)
	var best := e.x
	var bm := INF
	var n := 48
	var step := (hi - lo) / float(n)
	for i in n + 1:
		var x := lo + step * i
		var m: float = miss.call(x)
		if m < bm:
			bm = m
			best = x
	var a := maxf(lo, best - step)
	var b := minf(hi, best + step)
	for it in 30:
		var m1 := a + (b - a) / 3.0
		var m2 := b - (b - a) / 3.0
		if float(miss.call(m1)) < float(miss.call(m2)):
			b = m2
		else:
			a = m1
	skel.set_bone_pose_rotation(ib, (rest_b * Basis.from_euler(Vector3((a + b) * 0.5, e.y, e.z), EULER_ORDER_ZYX)).get_rotation_quaternion())
	skel.force_update_all_bone_transforms()
	var pc := skel.get_bone_global_pose(ic).origin
	_set_global_basis(skel, ia, _arc(pc - pa, target - pa) * ga.basis.orthonormalized(), 1.0)
	skel.force_update_all_bone_transforms()
	if pole.is_finite():
		var axis := (target - pa).normalized()
		var k := skel.get_bone_global_pose(ib).origin - pa
		var pv := pole - pa
		k -= axis * k.dot(axis)
		pv -= axis * pv.dot(axis)
		if k.length() > 1e-5 and pv.length() > 1e-5:
			var ang := atan2(axis.dot(k.cross(pv)), k.dot(pv))
			_set_global_basis(skel, ia, Basis(axis, ang) * skel.get_bone_global_pose(ia).basis.orthonormalized(), 1.0)
			skel.force_update_all_bone_transforms()
	if end_basis is Basis:
		_set_global_basis(skel, ic, end_basis as Basis, 1.0)
	if w < 1.0:
		var ids := [ia, ib, ic]
		for i in 3:
			skel.set_bone_pose_rotation(ids[i], (before[i] as Quaternion).slerp(skel.get_bone_pose_rotation(ids[i]), clampf(w, 0.0, 1.0)))
	skel.force_update_all_bone_transforms()


## the pole for a limb: the current bend direction when the joint is bent, else forward for knees / back for elbows
static func auto_pole(skel: Skeleton3D, limb: String, ia: int, ib: int, ic: int) -> Vector3:
	var pa := skel.get_bone_global_pose(ia).origin
	var pb := skel.get_bone_global_pose(ib).origin
	var pc := skel.get_bone_global_pose(ic).origin
	var mid := (pa + pc) * 0.5
	var off := pb - mid
	var line := (pc - pa).normalized()
	off -= line * off.dot(line)
	var fwd := skel.global_transform.basis.inverse() * Vector3.BACK   # world +Z (the way the fighter faces) in skeleton space
	var want := fwd if limb.begins_with("leg") else -fwd
	if off.length() > 0.01 * pa.distance_to(pc):
		return pb + off.normalized() * 0.4
	return pb + want.normalized() * 0.4


static func _limb_ids(skel: Skeleton3D, limb: String) -> Array:
	if not FSARig.LIMBS.has(limb):
		return []
	var ids: Array = []
	for b in (FSARig.LIMBS[limb] as Array):
		var i := skel.find_bone(str(b))
		if i < 0:
			return []
		ids.append(i)
	return ids


static func _ik(c: Dictionary, f: float, skel: Skeleton3D, w: float, touched: Dictionary, ctx: Dictionary) -> void:
	var limb := str(c.get("limb", ""))
	var ids := _limb_ids(skel, limb)
	if ids.is_empty():
		return
	var t := _w2s(skel, target_point(c.get("target", {}) as Dictionary, f, skel))
	var pole := Vector3.INF   # none given: a hinge keeps its own bend plane
	if not (c.get("pole", {}) as Dictionary).is_empty():
		pole = _w2s(skel, target_point(c["pole"] as Dictionary, f, skel))
	var keep: Variant = null
	if bool(c.get("keep_end", true)):
		keep = skel.get_bone_global_pose(ids[2]).basis.orthonormalized()
	solve_two_bone(skel, ids[0], ids[1], ids[2], t, pole, keep, w)
	for i in ids:
		touched[i] = true


## pins capture the bone at pin_frame (layers, no constraints) once per document version
static func _capture_pins(doc: FSADoc, skel: Skeleton3D, bones: Array, ctx: Dictionary) -> void:
	for c in doc.constraints:
		var cd: Dictionary = c
		if str(cd.get("type", "")) != "pin" or not bool(cd.get("enabled", true)):
			continue
		var key := "pin:" + str(cd.get("id", ""))
		if ctx.has(key):
			continue
		var bi := skel.find_bone(str(cd.get("bone", "")))
		if bi < 0:
			continue
		CBClipLib.apply_pose(skel, layer_pose(doc, float(cd.get("pin_frame", cd.get("start", 0))), bones))
		skel.force_update_all_bone_transforms()
		ctx[key] = skel.get_bone_global_pose(bi)


static func _pin(c: Dictionary, skel: Skeleton3D, w: float, touched: Dictionary, ctx: Dictionary) -> void:
	var bone := str(c.get("bone", ""))
	var bi := skel.find_bone(bone)
	var cap: Variant = ctx.get("pin:" + str(c.get("id", "")))
	if bi < 0 or not (cap is Transform3D):
		return
	var g: Transform3D = cap
	var what := str(c.get("what", "both"))
	var limb := FSARig.limb_of_end(bone)
	if limb != "" and what != "rotation":
		var ids := _limb_ids(skel, limb)
		if ids.is_empty():
			return
		var keep: Variant = g.basis.orthonormalized() if what == "both" else skel.get_bone_global_pose(ids[2]).basis.orthonormalized()
		solve_two_bone(skel, ids[0], ids[1], ids[2], g.origin, Vector3.INF, keep, w)
		for i in ids:
			touched[i] = true
		return
	if what != "position":
		_set_global_basis(skel, bi, g.basis, w)
		touched[bi] = true
	if bone == "hips" and what != "rotation":
		var p := skel.get_bone_parent(bi)
		var pg := skel.get_bone_global_pose(p) if p >= 0 else Transform3D()
		var want := pg.affine_inverse() * g.origin
		var cur := skel.get_bone_pose_position(bi)
		skel.set_bone_pose_position(bi, cur.lerp(want, clampf(w, 0.0, 1.0)))
		touched[bi] = true


const AXES := {"+x": Vector3.RIGHT, "-x": Vector3.LEFT, "+y": Vector3.UP, "-y": Vector3.DOWN, "+z": Vector3.BACK, "-z": Vector3.FORWARD}


static func _aim(c: Dictionary, f: float, skel: Skeleton3D, w: float, touched: Dictionary) -> void:
	var bi := skel.find_bone(str(c.get("bone", "head")))
	if bi < 0:
		return
	var g := skel.get_bone_global_pose(bi)
	var t := _w2s(skel, target_point(c.get("target", {}) as Dictionary, f, skel))
	var axis: Vector3 = AXES.get(str(c.get("axis", "+z")), Vector3.BACK)
	var fwd := (g.basis.orthonormalized() * axis).normalized()
	var want := t - g.origin
	if want.length() < 1e-4:
		return
	_set_global_basis(skel, bi, _arc(fwd, want) * g.basis.orthonormalized(), w)
	touched[bi] = true


static func _limit(c: Dictionary, skel: Skeleton3D, w: float, touched: Dictionary) -> void:
	var bi := skel.find_bone(str(c.get("bone", "")))
	if bi < 0:
		return
	var rest := skel.get_bone_rest(bi)
	var e := (rest.basis.orthonormalized().inverse() * skel.get_bone_pose(bi).basis.orthonormalized()).get_euler(EULER_ORDER_ZYX)
	var lo := _v3(c.get("min", [-PI, -PI, -PI]))
	var hi := _v3(c.get("max", [PI, PI, PI]))
	var cl := Vector3(clampf(e.x, lo.x, hi.x), clampf(e.y, lo.y, hi.y), clampf(e.z, lo.z, hi.z))
	if cl.is_equal_approx(e):
		return
	var q := (rest.basis.orthonormalized() * CBClipLib.rot_basis(e.lerp(cl, clampf(w, 0.0, 1.0)))).get_rotation_quaternion()
	skel.set_bone_pose_rotation(bi, q)
	touched[bi] = true


static func _copy_rot(c: Dictionary, skel: Skeleton3D, w: float, touched: Dictionary) -> void:
	var bi := skel.find_bone(str(c.get("bone", "")))
	var si := skel.find_bone(str(c.get("source", "")))
	if bi < 0 or si < 0:
		return
	var srest := skel.get_bone_rest(si)
	var se := (srest.basis.orthonormalized().inverse() * skel.get_bone_pose(si).basis.orthonormalized()).get_euler(EULER_ORDER_ZYX)
	if bool(c.get("mirror", false)):
		se = FSARig.mirror_euler(se)
	se = se * float(c.get("mix", 1.0)) + _v3(c.get("offset", [0, 0, 0]))
	var rest := skel.get_bone_rest(bi)
	var cur := (rest.basis.orthonormalized().inverse() * skel.get_bone_pose(bi).basis.orthonormalized()).get_euler(EULER_ORDER_ZYX)
	var q := (rest.basis.orthonormalized() * CBClipLib.rot_basis(cur.lerp(se, clampf(w, 0.0, 1.0)))).get_rotation_quaternion()
	skel.set_bone_pose_rotation(bi, q)
	touched[bi] = true


## how high a bone sits above the floor when it touches it: a foot keeps its rest ankle height (the model stands on y = 0 at
## rest), anything else (a hand, a knee) its radius
static func rest_height(skel: Skeleton3D, bi: int, ctx: Dictionary, radius: float = 0.04) -> float:
	if not skel.get_bone_name(bi).begins_with("foot"):
		return radius
	var key := "rest_h:%d:%d" % [skel.get_instance_id(), bi]
	if not ctx.has(key):
		ctx[key] = maxf(0.0, s2w(skel, skel.get_bone_global_rest(bi).origin).y)
	return float(ctx[key])


## floor: no listed bone sinks under the floor (the whole body is lifted by the hips). plant: the lowest one stands on it.
static func _floor(c: Dictionary, skel: Skeleton3D, w: float, touched: Dictionary, ctx: Dictionary) -> void:
	var hi := skel.find_bone("hips")
	if hi < 0:
		return
	var floor_y := float(c.get("height", 0.0))
	var need := -INF
	var soles := CBFeet.sole_info(skel)
	for b in (c.get("bones", ["footL", "footR"]) as Array):
		var bi := skel.find_bone(str(b))
		if bi < 0:
			continue
		if soles.has(str(b)):   # a foot: its real sole (the mesh), not the ankle
			need = maxf(need, floor_y - CBFeet.lowest(skel, str(b), soles))
			continue
		var y := s2w(skel, skel.get_bone_global_pose(bi).origin).y
		need = maxf(need, floor_y + rest_height(skel, bi, ctx, float(c.get("radius", 0.04))) - y)
	if need == -INF:
		return
	if str(c.get("mode", "floor")) == "floor" and need <= 0.0:
		return
	var p := skel.get_bone_parent(hi)
	var pb := skel.get_bone_global_pose(p).basis if p >= 0 else Basis()
	var d_skel := skel.global_transform.basis.inverse() * Vector3(0, need * clampf(w, 0.0, 1.0), 0)
	skel.set_bone_pose_position(hi, skel.get_bone_pose_position(hi) + pb.inverse() * d_skel)
	touched[hi] = true


## CCD IK for any joint that is not a hand or a foot (drag the head and the spine bends, drag a tail tip and the tail
## follows): turn up to `chain` ancestors (never the root or the hips) so the joint reaches the target. Returns touched ids.
static func ccd(skel: Skeleton3D, bi: int, target: Vector3, chain: int = 3, iters: int = 12) -> Array:
	var ids: Array = []
	var p := skel.get_bone_parent(bi)
	while p >= 0 and ids.size() < chain:
		var pn := skel.get_bone_name(p)
		if pn == "root" or pn == "hips":
			break
		ids.append(p)
		p = skel.get_bone_parent(p)
	var t := _w2s(skel, target)
	for it in iters:
		for j in ids:
			skel.force_update_all_bone_transforms()
			var pj := skel.get_bone_global_pose(int(j)).origin
			var end := skel.get_bone_global_pose(bi).origin
			if end.distance_to(t) < 0.002:
				return ids
			var a := end - pj
			var b := t - pj
			if a.length() < 1e-4 or b.length() < 1e-4:
				continue
			var r := _arc(a, b)
			var ang := r.get_rotation_quaternion().get_angle()
			if ang > 0.35:
				r = Basis(r.get_rotation_quaternion().get_axis().normalized(), 0.35)
			var g := skel.get_bone_global_pose(int(j)).basis.orthonormalized()
			_set_global_basis(skel, int(j), r * g, 0.6)
	skel.force_update_all_bone_transforms()
	return ids


# ---------------------------------------------------------------- bake

## the clip as the game will play it: a key on every frame from the final pose (layers + constraints)
static func bake(doc: FSADoc, skel: Skeleton3D, bones: Array, ctx: Dictionary) -> Array:
	var out: Array = []
	for f in doc.frames + 1:
		var p := final_pose(doc, float(f), skel, bones, ctx)
		var k := {"f": f}
		FSADoc.fill_key(k, p, bones)
		out.append(k)
	return out
