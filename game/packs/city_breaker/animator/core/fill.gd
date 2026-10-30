class_name FSAFill
extends RefCounted
## Fill: the frames between two keys, made for you (FILL_PLAN.md). Two engines make the in-between poses:
##   shape    rules, per Euler channel (the same channels the game lerps): a Hermite curve whose end speeds come from the
##            timing and, with Flow, from the speed the motion really has coming into A and leaving B; Overlap makes each joint
##            trail its parent and catch up by B; Anticipate winds back first; Overshoot goes past B and settles onto it
##   library  the stretch of one of our clips (mirrored too) whose first pose is nearest A and last pose nearest B, played at the
##            span's length and bent onto A and B (motion warping: the offsets at the two ends fade across)
## then every joint inside its natural limits, planted feet held where they stand (hinge leg IK) or stepped on an arc, an
## optional jump arc for the hips. The result is plain keys tagged "breakdown" with "fill": id, so the game plays it as it is.
## No UI and no app state here: FSAApp.fill_* call it and keep the undo.

const ENGINES := ["shape", "library"]
const TIMINGS := ["smooth", "even", "strike", "settle"]
const TIMING_NAMES := {"smooth": "smooth (eases in and out)", "even": "even", "strike": "strike (slow start, hits B fast)",
	"settle": "settle (fast start, eases into B)"}
const DEFAULTS := {"engine": "shape", "timing": "smooth", "flow": 0.6, "overlap": 0.3, "anticipate": 0.0, "overshoot": 0.0,
	"feet": true, "air": 0.0, "step": 0, "pick": 0}
## the end speeds of each timing, in "the whole change over the span" (Hermite slopes; at most 3 keeps the curve from going back)
const SLOPES := {"smooth": [0.0, 0.0], "even": [1.0, 1.0], "strike": [0.0, 2.6], "settle": [2.6, 0.0]}
## how far down the chain from the hips a joint sits: Overlap delays it by that much (legs do not trail: the feet hold the floor)
const DEPTH := {"torso": 1, "chest": 2, "neck": 3, "head": 4, "armL": 3, "armR": 3, "elbowL": 4, "elbowR": 4, "handL": 5,
	"handR": 5, "tail": 1, "tail2": 2, "tail3": 3, "earL": 5, "earR": 5, "crest": 5, "crest2": 6}
const OVERLAP_PER_DEPTH := 0.15   # Overlap 1: a hand (depth 5) starts 0.75 of a "lag" behind (sin warp, at most ~24% of the span)
const ANTICIPATE_TIME := 0.25     # Anticipate 1: the main move starts a quarter of the span late, after a wind-up the other way
const ANTICIPATE_SIZE := 0.12     # ... the wind-up is 12% of the change
const OVERSHOOT_TIME := 0.2       # Overshoot 1: reaches B a fifth of the span early, goes past by 12% (more down the chain)
const OVERSHOOT_SIZE := 0.12
## the bones (and weights) two poses are compared on in the library search
const MATCH := {"hips": 2.0, "torso": 2.0, "chest": 1.5, "neck": 0.5, "head": 0.7, "armL": 1.2, "armR": 1.2, "elbowL": 0.8,
	"elbowR": 0.8, "handL": 0.3, "handR": 0.3, "legL": 1.5, "legR": 1.5, "kneeL": 1.0, "kneeR": 1.0, "footL": 0.4, "footR": 0.4}
const MATCH_DY := 3.0             # a metre of hips height counts as 3 radians
const MATCH_RATE := 30.0          # the library is sampled at 30 poses a second
const STRETCH_COST := 0.25        # cost of playing a stretch at another speed, per e-fold (0.5x or 2x costs ~0.17)
const FEET_SAME := 0.03           # a standing foot that moved less than this (metres) is held; more is a step
const STEP_LIFT := [0.03, 0.12]   # a step lifts a quarter of its length, inside these
const SPIN := 1.0                 # the hips turning more than this (radians, as keyed) from A to B: held feet pivot with the body


# ================================================================ span + options

## the options with defaults filled in and kept in range
static func settings(opts: Dictionary) -> Dictionary:
	var s := DEFAULTS.duplicate()
	for k in opts:
		if s.has(k):
			s[k] = opts[k]
	s["engine"] = str(s["engine"]) if str(s["engine"]) in ENGINES else "shape"
	s["timing"] = str(s["timing"]) if str(s["timing"]) in TIMINGS else "smooth"
	for k in ["flow", "overlap", "anticipate", "overshoot"]:
		s[k] = clampf(float(s[k]), 0.0, 1.0)
	s["feet"] = bool(s["feet"])
	s["air"] = clampf(float(s["air"]), 0.0, 200.0)
	s["step"] = clampi(int(s["step"]), 0, 12)
	s["pick"] = maxi(0, int(s["pick"]))
	return s


## frames between keys: every 2 at 60 fps, every frame at 30
static func step_of(doc: FSADoc, s: Dictionary) -> int:
	return int(s["step"]) if int(s["step"]) > 0 else maxi(1, int(round(doc.fps / 30.0)))


## the span around frame f: inside a fill, that fill's span (its own breakdown keys do not split it); else the keys before and
## after f (a key on f counts as the start); [] when there is none
static func span_around(doc: FSADoc, f: float) -> Array:
	for fl in doc.fills:
		if f >= float(fl["a"]) - 0.001 and f < float(fl["b"]) - 0.001:
			return [int(fl["a"]), int(fl["b"])]
	var a := doc.prev_key(f + 0.001)
	var b := doc.next_key(f + 0.001)
	if a < 0 or b < 0:
		return []
	return [a, b]


static func fills(doc: FSADoc) -> Array:
	return doc.fills


static func find(doc: FSADoc, id: String) -> Dictionary:
	for fl in doc.fills:
		if str((fl as Dictionary).get("id", "")) == id:
			return fl
	return {}


## the fill whose span is exactly a..b
static func at_span(doc: FSADoc, a: int, b: int) -> Dictionary:
	for fl in doc.fills:
		if int((fl as Dictionary)["a"]) == a and int((fl as Dictionary)["b"]) == b:
			return fl
	return {}


# ================================================================ poses

## the pose at frame f from the base keys (wraps on a loop; held at the clip's ends)
static func _pose(doc: FSADoc, f: float, bones: Array) -> Dictionary:
	if doc.loop:
		f = fposmod(f, float(doc.frames))
	return doc.base_pose(clampf(f, 0.0, float(doc.frames)), bones)


## speed per frame coming into frame a (from a - 1) or going out of b (to b + 1); zero at a clip end that does not loop
static func _speed(doc: FSADoc, f: int, dir: int, bones: Array, pose: Dictionary) -> Dictionary:
	var g := f + dir
	if not doc.loop and (g < 0 or g > doc.frames):
		return {}
	var other := _pose(doc, float(g), bones)
	var out := {}
	for b in bones:
		out[b] = ((pose.get(b, Vector3.ZERO) as Vector3) - (other.get(b, Vector3.ZERO) as Vector3)) * float(-dir)
	for ax in ["_dx", "_dy", "_dz"]:
		out[ax] = (float(pose.get(ax, 0.0)) - float(other.get(ax, 0.0))) * float(-dir)
	return out


static func _hermite(p0: float, p1: float, m0: float, m1: float, t: float) -> float:
	var t2 := t * t
	var t3 := t2 * t
	return (2.0 * t3 - 3.0 * t2 + 1.0) * p0 + (t3 - 2.0 * t2 + t) * m0 + (-2.0 * t3 + 3.0 * t2) * p1 + (t3 - t2) * m1


## a hump 0 -> 1 -> 0 across [p, q], zero outside
static func _bump(u: float, p: float, q: float) -> float:
	if u <= p or u >= q or q <= p:
		return 0.0
	var s := sin(PI * (u - p) / (q - p))
	return s * s


static func _smooth(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


## a slope kept sane: the speed coming in may be big next to a small change; past 3x the change (or 20 degrees / 10 cm over
## the span) the curve loops back on itself
static func _cap(m: float, delta: float, floor_v: float) -> float:
	var lim := maxf(3.0 * absf(delta), floor_v)
	return clampf(m, -lim, lim)


# ================================================================ engine 1: shape

## poses for frames a < f < b (every `step`): {f: pose}
static func shape(doc: FSADoc, bones: Array, a: int, b: int, s: Dictionary, frames: Array) -> Dictionary:
	var pa := _pose(doc, float(a), bones)
	var pb := _pose(doc, float(b), bones)
	var span := float(b - a)
	var va := _speed(doc, a, -1, bones, pa) if float(s["flow"]) > 0.0 else {}
	var vb := _speed(doc, b, 1, bones, pb) if float(s["flow"]) > 0.0 else {}
	var sl: Array = SLOPES[str(s["timing"])]
	var flow := float(s["flow"])
	var ant := float(s["anticipate"])
	var ovs := float(s["overshoot"])
	var t0 := ANTICIPATE_TIME * ant
	var t1 := 1.0 - OVERSHOOT_TIME * ovs
	var out := {}
	for f in frames:
		var u := (float(f) - float(a)) / span
		var um := clampf((u - t0) / maxf(t1 - t0, 0.05), 0.0, 1.0)   # the main move, after the wind-up, before the settle
		var pose := {}
		for bn in bones:
			var ea: Vector3 = pa.get(bn, Vector3.ZERO)
			var eb: Vector3 = pb.get(bn, Vector3.ZERO)   # as keyed: the game lerps the raw values, so a turn keyed past 180 degrees (a spin) stays one
			var d := float(DEPTH.get(str(bn), 0)) if not FSARig.is_finger(str(bn)) else 6.0
			var lag := minf(0.9, float(s["overlap"]) * OVERLAP_PER_DEPTH * d)
			var ub := um - lag / PI * sin(PI * um)        # this joint's own progress: behind its parent, caught up by B
			var e := Vector3.ZERO
			for i in 3:
				var dl := eb[i] - ea[i]
				var m0 := lerpf(float(sl[0]) * dl, float((va.get(bn, Vector3.ZERO) as Vector3)[i]) * span, flow) if not va.is_empty() else float(sl[0]) * dl
				var m1 := lerpf(float(sl[1]) * dl, float((vb.get(bn, Vector3.ZERO) as Vector3)[i]) * span, flow) if not vb.is_empty() else float(sl[1]) * dl
				m0 = _cap(m0, dl, 0.35)
				m1 = _cap(m1, dl, 0.35)
				e[i] = _hermite(ea[i], eb[i], m0, m1, ub)
				e[i] += -ANTICIPATE_SIZE * ant * dl * _bump(u, 0.0, t0 + 0.2)
				e[i] += OVERSHOOT_SIZE * ovs * (1.0 + 0.15 * d) * dl * _bump(u, t1 - 0.15, 1.0)
			pose[bn] = e
		for ax in ["_dx", "_dy", "_dz"]:
			var xa := float(pa.get(ax, 0.0))
			var xb := float(pb.get(ax, 0.0))
			var dl := xb - xa
			var m0 := lerpf(float(sl[0]) * dl, float(va.get(ax, 0.0)) * span, flow) if not va.is_empty() else float(sl[0]) * dl
			var m1 := lerpf(float(sl[1]) * dl, float(vb.get(ax, 0.0)) * span, flow) if not vb.is_empty() else float(sl[1]) * dl
			pose[ax] = _hermite(xa, xb, _cap(m0, dl, 0.1), _cap(m1, dl, 0.1), um)
		out[f] = pose
	return out


# ================================================================ engine 2: library

static var _index: Array = []      # [{name, fps, frames, loop, n, q: PackedFloat32Array (n x bones x 4), dy: PackedFloat32Array}]
static var _index_sig := ""


static func _bone_names() -> Array:
	return MATCH.keys()


## every clip as poses 30 times a second (built once, again when a clip file changes)
static func library_index(force: bool = false) -> Array:
	var names := CBClipLib.list_clips()
	var sig_parts: PackedStringArray = []
	for n in names:
		sig_parts.append("%s:%d" % [n, FileAccess.get_modified_time(CBClipLib.DIR + str(n) + ".json")])
	var sig := str(",".join(sig_parts).hash())
	if not force and sig == _index_sig and not _index.is_empty():
		return _index
	_index = []
	var mb := _bone_names()
	for n in names:
		var c := CBClipLib.load_clip(str(n))
		if c.is_empty() or (c.get("keys", []) as Array).is_empty():
			continue
		var fps := maxf(1.0, float(c.get("fps", 30)))
		var frames := maxi(1, int(c.get("frames", 24)))
		var cnt := int(floor(float(frames) / fps * MATCH_RATE)) + 1
		var q := PackedFloat32Array()
		var dy := PackedFloat32Array()
		q.resize(cnt * mb.size() * 4)
		dy.resize(cnt)
		var src := {"keys": CBClipLib.sorted_keys(c), "loop": c.get("loop", false), "ease": c.get("ease", "linear")}
		for i in cnt:
			var p := CBClipLib.pose_at(src, minf(float(frames), float(i) / MATCH_RATE * fps), mb)
			_put(q, i * mb.size() * 4, p, mb)
			dy[i] = float(p.get("_dy", 0.0))
		_index.append({"name": str(n), "fps": fps, "frames": frames, "loop": bool(c.get("loop", false)), "n": cnt, "q": q, "dy": dy})
	_index_sig = sig
	return _index


static func _put(q: PackedFloat32Array, at: int, pose: Dictionary, mb: Array) -> void:
	for j in mb.size():
		var r := CBClipLib.rot_basis(pose.get(mb[j], Vector3.ZERO)).get_rotation_quaternion()
		q[at + j * 4] = r.x
		q[at + j * 4 + 1] = r.y
		q[at + j * 4 + 2] = r.z
		q[at + j * 4 + 3] = r.w


## a pose as the search compares it
static func _feature(pose: Dictionary) -> Dictionary:
	var mb := _bone_names()
	var q := PackedFloat32Array()
	q.resize(mb.size() * 4)
	_put(q, 0, pose, mb)
	return {"q": q, "dy": float(pose.get("_dy", 0.0))}


## weighted RMS of the turn between two poses (radians) + the hips height
static func _dist(fq: PackedFloat32Array, fdy: float, q: PackedFloat32Array, at: int, dy: float, w: PackedFloat32Array, wsum: float) -> float:
	var acc := 0.0
	for j in w.size():
		var k := at + j * 4
		var d := absf(fq[j * 4] * q[k] + fq[j * 4 + 1] * q[k + 1] + fq[j * 4 + 2] * q[k + 2] + fq[j * 4 + 3] * q[k + 3])
		var ang := 2.0 * acos(minf(1.0, d))
		acc += w[j] * ang * ang
	return sqrt(acc / wsum) + MATCH_DY * absf(fdy - dy)


static func mirror_pose(pose: Dictionary, bones: Array) -> Dictionary:
	var out := pose.duplicate()
	for b in bones:
		var e: Vector3 = pose.get(b, Vector3.ZERO)
		out[FSARig.mirror_name(str(b))] = FSARig.mirror_euler(e)
	out["_dx"] = -float(pose.get("_dx", 0.0))
	return out


## the library stretches that best join pose A to pose B in `frames_len` frames at `fps`: [{clip, from, to (clip frames),
## mirror, cost, score (0..100), frames (how long it took there, in this clip's frames)}], best first, one per clip and side
static func matches(doc: FSADoc, bones: Array, a: int, b: int, n: int = 5) -> Array:
	var pa := _pose(doc, float(a), bones)
	var pb := _pose(doc, float(b), bones)
	var secs := float(b - a) / float(doc.fps)
	var mb := _bone_names()
	var w := PackedFloat32Array()
	var wsum := 0.0
	for k in mb:
		w.append(float(MATCH[k]))
		wsum += float(MATCH[k])
	var lo := maxi(1, int(ceil(secs * 0.5 * MATCH_RATE)))
	var hi := maxi(lo, int(floor(secs * 2.0 * MATCH_RATE)))
	var found: Array = []
	for side in [false, true]:
		var fa := _feature(mirror_pose(pa, bones) if side else pa)
		var fb := _feature(mirror_pose(pb, bones) if side else pb)
		for e in library_index():
			var ed: Dictionary = e
			if str(ed["name"]) == doc.name:
				continue
			var cnt := int(ed["n"])
			var q: PackedFloat32Array = ed["q"]
			var dy: PackedFloat32Array = ed["dy"]
			var loop := bool(ed["loop"]) and cnt > 2
			var da := PackedFloat32Array()
			var db := PackedFloat32Array()
			da.resize(cnt)
			db.resize(cnt)
			var dbmin := INF
			for i in cnt:
				da[i] = _dist(fa["q"], float(fa["dy"]), q, i * mb.size() * 4, dy[i], w, wsum)
				db[i] = _dist(fb["q"], float(fb["dy"]), q, i * mb.size() * 4, dy[i], w, wsum)
				dbmin = minf(dbmin, db[i])
			var best := {"cost": INF}
			for i in cnt:
				if da[i] + dbmin >= float(best["cost"]):
					continue
				for len_i in range(lo, hi + 1):
					var j := i + len_i
					if j >= cnt:
						if not loop:
							break
						j = j % (cnt - 1)
						if len_i > cnt - 1:
							break
					var c := da[i] + db[j] + STRETCH_COST * absf(log(float(len_i) / (secs * MATCH_RATE)))
					if c < float(best["cost"]):
						best = {"cost": c, "i": i, "len": len_i}
			if best.has("i"):
				var fps := float(ed["fps"])
				var f0 := float(best["i"]) / MATCH_RATE * fps
				var f1 := f0 + float(best["len"]) / MATCH_RATE * fps
				found.append({"clip": str(ed["name"]), "from": snappedf(f0, 0.01), "to": snappedf(f1, 0.01), "mirror": side,
					"cost": snappedf(float(best["cost"]), 0.0001), "score": int(round(100.0 * exp(-2.5 * float(best["cost"])))),
					"frames": int(round(float(best["len"]) / MATCH_RATE * float(doc.fps)))})
	found.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["cost"]) < float(y["cost"]))
	return found.slice(0, n)


## poses for the frames from a library stretch, bent so it starts on A and ends on B
static func library(doc: FSADoc, bones: Array, a: int, b: int, m: Dictionary, frames: Array) -> Dictionary:
	var pa := _pose(doc, float(a), bones)
	var pb := _pose(doc, float(b), bones)
	var c := FSAEval.clip_src(str(m["clip"]))
	var src := {"keys": CBClipLib.sorted_keys(c), "loop": c.get("loop", false), "ease": c.get("ease", "linear")}
	var cf := float(c.get("frames", 24))
	var mir := bool(m.get("mirror", false))
	var at := func(u: float) -> Dictionary:
		var sf := lerpf(float(m["from"]), float(m["to"]), u)
		if bool(c.get("loop", false)):
			sf = fposmod(sf, cf)
		var p := CBClipLib.pose_at(src, clampf(sf, 0.0, cf), bones)
		return mirror_pose(p, bones) if mir else p
	# the stretch's Euler values carried along from A's (no flips mid-way), then its ends measured against A and B
	var m0: Dictionary = at.call(0.0)
	var m1: Dictionary = at.call(1.0)
	var cont := {}
	for bn in bones:
		cont[bn] = FSAEval.nearest_euler(m0.get(bn, Vector3.ZERO), pa.get(bn, Vector3.ZERO))
	var off_a := {}
	for bn in bones:
		off_a[bn] = (pa.get(bn, Vector3.ZERO) as Vector3) - (cont[bn] as Vector3)
	var us: Array = [1.0]
	for f in frames:
		us.append((float(f) - float(a)) / float(b - a))
	us.sort()
	var seq := {}
	var prev := cont.duplicate()
	for u in us:
		var p: Dictionary = at.call(float(u))
		var q := {}
		for bn in bones:
			q[bn] = FSAEval.nearest_euler(p.get(bn, Vector3.ZERO), prev[bn])
		for ax in ["_dx", "_dy", "_dz"]:
			q[ax] = float(p.get(ax, 0.0))
		seq[u] = q
		prev = q
	var end: Dictionary = seq[1.0]
	var out := {}
	for f in frames:
		var u := (float(f) - float(a)) / float(b - a)
		var p: Dictionary = seq[u]
		var w := _smooth(u)
		var pose := {}
		for bn in bones:
			var eb: Vector3 = pb.get(bn, Vector3.ZERO)   # as keyed (a spin the keys ask for is added across the span)
			pose[bn] = (p[bn] as Vector3) + (off_a[bn] as Vector3).lerp(eb - (end[bn] as Vector3), w)
		for ax in ["_dx", "_dy", "_dz"]:
			var oa := float(pa.get(ax, 0.0)) - float(m0.get(ax, 0.0))
			var ob := float(pb.get(ax, 0.0)) - float(end[ax])
			pose[ax] = float(p[ax]) + lerpf(oa, ob, w)
		out[f] = pose
	return out


# ================================================================ after the engines

static func clamp_pose(pose: Dictionary, bones: Array) -> void:
	for bn in bones:
		pose[bn] = FSARig.clamp_limits(str(bn), pose.get(bn, Vector3.ZERO))


## planted feet: each foot standing at A and at B is held on the floor (the same spot: lerped across; moved more than
## FEET_SAME: a step that lifts on an arc). Works on the hidden probe skeleton. Returns {foot: "held" | "step" | "free"}
static func feet(doc: FSADoc, bones: Array, sk: Skeleton3D, a: int, b: int, poses: Dictionary) -> Dictionary:
	var info := CBFeet.sole_info(sk)
	var out := {"footL": "free", "footR": "free"}
	if info.is_empty() or sk == null:
		return out
	var ends := {}
	for ef in [a, b]:
		var p := _pose(doc, float(ef), bones)
		CBClipLib.apply_pose(sk, p)
		sk.force_update_all_bone_transforms()
		var st := CBFeet.standing(sk, info)
		var row := {}
		for ft in ["footL", "footR"]:
			var bi := sk.find_bone(ft)
			if bi < 0:
				continue
			var g := sk.get_bone_global_pose(bi)
			row[ft] = {"on": float((st.get(ft, {}) as Dictionary).get("w", 0.0)) >= 0.5, "pos": sk.global_transform * g.origin,
				"basis": g.basis.orthonormalized()}
		ends[ef] = row
	var plans := {}
	for ft in ["footL", "footR"]:
		var ra: Dictionary = (ends[a] as Dictionary).get(ft, {})
		var rb: Dictionary = (ends[b] as Dictionary).get(ft, {})
		if ra.is_empty() or rb.is_empty() or not bool(ra["on"]) or not bool(rb["on"]):
			continue
		var pa: Vector3 = ra["pos"]
		var pb: Vector3 = rb["pos"]
		var flat := Vector2(pb.x - pa.x, pb.z - pa.z).length()
		plans[ft] = {"pa": pa, "pb": pb, "ba": ra["basis"], "bb": rb["basis"], "step": flat >= FEET_SAME, "len": flat}
		out[ft] = "step" if flat >= FEET_SAME else "held"
	if plans.is_empty():
		return out
	# two steps: the longer one first, the other after it
	var steppers: Array = plans.keys().filter(func(k: String) -> bool: return bool(plans[k]["step"]))
	steppers.sort_custom(func(x: String, y: String) -> bool: return float(plans[x]["len"]) > float(plans[y]["len"]))
	for i in steppers.size():
		var win := [0.15, 0.85] if steppers.size() == 1 else ([0.05, 0.55] if i == 0 else [0.45, 0.95])
		plans[steppers[i]]["win"] = win
	# the body spins (the hips turn a lot from A to B, a full turn reads the same at both ends): a held foot stays on its spot
	# but pivots with the leg, it does not keep A's turn
	var spin := ((_pose(doc, float(b), bones).get("hips", Vector3.ZERO) as Vector3) - (_pose(doc, float(a), bones).get("hips", Vector3.ZERO) as Vector3)).length() > SPIN
	var inv := sk.global_transform.affine_inverse()
	for f in poses:
		var pose: Dictionary = poses[f]
		var u := (float(f) - float(a)) / float(b - a)
		CBClipLib.apply_pose(sk, pose)
		sk.force_update_all_bone_transforms()
		var touched := {}
		for ft in plans:
			var pl: Dictionary = plans[ft]
			var side := "L" if ft == "footL" else "R"
			var ids := [sk.find_bone("leg" + side), sk.find_bone("knee" + side), sk.find_bone(ft)]
			if ids.has(-1):
				continue
			var k := _smooth(u)
			var lift := 0.0
			if bool(pl["step"]):
				var win: Array = pl["win"]
				var wu := clampf((u - float(win[0])) / (float(win[1]) - float(win[0])), 0.0, 1.0)
				k = _smooth(wu)
				lift = clampf(0.25 * float(pl["len"]), STEP_LIFT[0], STEP_LIFT[1]) * sin(PI * wu)
			var target: Vector3 = (pl["pa"] as Vector3).lerp(pl["pb"], k) + Vector3(0, lift, 0)
			var hold := Basis((pl["ba"] as Basis).get_rotation_quaternion().slerp((pl["bb"] as Basis).get_rotation_quaternion(), k))
			if spin:
				hold = sk.get_bone_global_pose(ids[2]).basis.orthonormalized()
			FSAEval.solve_two_bone(sk, ids[0], ids[1], ids[2], inv * target, Vector3.INF, hold, 1.0)
			sk.force_update_all_bone_transforms()
			for i in ids:
				touched[i] = true
		if not touched.is_empty():
			poses[f] = FSAEval.read_back(sk, pose, touched)
	return out


## the in-between poses for a..b with these settings: {"poses": {f: pose}, "feet": {...}, "match": {} (library), "frames": [...]}
static func make(doc: FSADoc, bones: Array, sk: Skeleton3D, a: int, b: int, s: Dictionary) -> Dictionary:
	var st := step_of(doc, s)
	var frames: Array = []
	var f := a + st
	while f < b:
		frames.append(f)
		f += st
	var res := {"frames": frames, "match": {}, "feet": {}}
	if frames.is_empty():
		res["poses"] = {}
		return res
	var poses := {}
	if str(s["engine"]) == "library":
		var ms := matches(doc, bones, a, b, int(s["pick"]) + 1)
		if ms.is_empty():
			res["error"] = "no clip in the library joins these two poses"
			res["poses"] = {}
			return res
		var m: Dictionary = ms[mini(int(s["pick"]), ms.size() - 1)]
		res["match"] = m
		poses = library(doc, bones, a, b, m, frames)
	else:
		poses = shape(doc, bones, a, b, s, frames)
	if float(s["air"]) > 0.0:
		for fr in poses:
			var u := (float(fr) - float(a)) / float(b - a)
			(poses[fr] as Dictionary)["_dy"] = float((poses[fr] as Dictionary)["_dy"]) + float(s["air"]) / 100.0 * 4.0 * u * (1.0 - u)
	for fr in poses:
		clamp_pose(poses[fr], bones)
	if bool(s["feet"]) and doc.plant and float(s["air"]) <= 0.0 and sk != null:
		res["feet"] = feet(doc, bones, sk, a, b, poses)
		for fr in poses:
			clamp_pose(poses[fr], bones)
	res["poses"] = poses
	return res


# ================================================================ writing it into the clip

## put a made fill into the doc: the keys between a and b go (unless locked: then nothing changes and false comes back), the
## made poses come in as "breakdown" keys of fill `id`, key A eases linear while the fill is on
static func write(doc: FSADoc, bones: Array, a: int, b: int, made: Dictionary, s: Dictionary, id: String) -> bool:
	for k in doc.keys:
		var kf := int((k as Dictionary)["f"])
		if kf > a and kf < b and bool((k as Dictionary).get("lock", false)):
			return false
	var old := at_span(doc, a, b)
	var a_ease := str(old.get("a_ease", (doc.key_at(a)).get("ease", "")))
	doc.keys = doc.keys.filter(func(k: Dictionary) -> bool: return int(k["f"]) <= a or int(k["f"]) >= b)
	doc.fills = doc.fills.filter(func(fl: Dictionary) -> bool: return not (int(fl["b"]) > a and int(fl["a"]) < b))
	var poses: Dictionary = made.get("poses", {})
	for f in poses:
		doc.write_key(int(f), poses[f], bones)
		var k := doc.key_at(int(f))
		k["tag"] = "breakdown"
		k["fill"] = id
	var ka := doc.key_at(a)
	if not ka.is_empty():
		ka["ease"] = "linear"
	var rec := {"id": id, "a": a, "b": b, "a_ease": a_ease, "settings": s.duplicate()}
	if not (made.get("match", {}) as Dictionary).is_empty():
		rec["match"] = (made["match"] as Dictionary).duplicate()
	doc.fills.append(rec)
	doc.fills.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x["a"]) < int(y["a"]))
	return true


## take a fill out: its keys go, key A gets its ease back. Returns how many keys went
static func remove(doc: FSADoc, id: String) -> int:
	var fl := find(doc, id)
	if fl.is_empty():
		return 0
	var n := doc.keys.size()
	doc.keys = doc.keys.filter(func(k: Dictionary) -> bool: return str(k.get("fill", "")) != id)
	var ka := doc.key_at(int(fl["a"]))
	if not ka.is_empty():
		if str(fl.get("a_ease", "")) == "":
			ka.erase("ease")
		else:
			ka["ease"] = str(fl["a_ease"])
	doc.fills = doc.fills.filter(func(x: Dictionary) -> bool: return str(x["id"]) != id)
	return n - doc.keys.size()


static func describe(fl: Dictionary) -> String:
	var s: Dictionary = fl.get("settings", {})
	var t := "f%d-f%d  %s" % [int(fl["a"]), int(fl["b"]), str(s.get("engine", "shape"))]
	if str(s.get("engine", "")) == "library" and fl.has("match"):
		var m: Dictionary = fl["match"]
		t += ": %s%s %d%%" % [str(m["clip"]), " (mirrored)" if bool(m.get("mirror", false)) else "", int(m.get("score", 0))]
	else:
		t += ": %s, flow %d%%" % [str(s.get("timing", "smooth")), int(round(float(s.get("flow", 0.0)) * 100.0))]
	return t
