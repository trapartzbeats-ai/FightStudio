class_name CBHitReact
extends SkeletonModifier3D
## Procedural body reaction to a hit, like an IK pull: where an attack zone lands, that part of the VICTIM is pushed along the blow, the
## bones around it follow in proportion (a falloff by distance, plus a pull up the chain: a hit on the hand moves the arm, less the
## shoulder), then a damped spring brings everything back to the animation. The ATTACKER's striking limb recoils a little the same way.
## It runs after the animation (it is a SkeletonModifier3D), so it works on top of any clip and costs nothing when nothing was hit.
##
##   var react := CBHitReact.attach(skel, "vix")
##   react.impact(world_hit_point, world_push_direction, magnitude)      # the victim
##   react.recoil("handR", world_direction, magnitude)                   # the attacker's striking bone
##
## Settings: data/hit_react.json (shared + per fighter, Studio REACT tab): radius (m), strength, frequency (Hz) and damping of the
## spring, `up` / `down` = how much of the push travels to parent / child bones per step, `max_angle`, `recoil` (attacker share) and
## `bone_scale` (per bone: a heavy torso gives less than a head).

const DATA := "res://game/packs/city_breaker/data/hit_react.json"
static var _data: Dictionary = {}

var cfg: Dictionary = {}
var _rv: Dictionary = {}     # bone index -> rotation vector (skeleton space axis * angle)
var _rw: Dictionary = {}     # bone index -> angular velocity (same space)
var _active := false


static func data(force: bool = false) -> Dictionary:
	if _data.is_empty() or force:
		_data = {"settings": {}, "fighters": {}}
		var f := FileAccess.open(DATA, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if typeof(parsed) == TYPE_DICTIONARY:
				_data = parsed
	return _data


static func settings_for(key: String) -> Dictionary:
	var d := data()
	var out: Dictionary = (d.get("settings", {}) as Dictionary).duplicate(true)
	var over: Dictionary = (d.get("fighters", {}) as Dictionary).get(key, {})
	for k in over:
		if k == "bone_scale" and out.has("bone_scale"):
			(out["bone_scale"] as Dictionary).merge(over[k], true)
		else:
			out[k] = over[k]
	return out


static func save_data(d: Dictionary) -> int:
	var f := FileAccess.open(DATA, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(d, "  "))
	f.close()
	_data = d
	return OK


static func attach(skel: Skeleton3D, key: String) -> CBHitReact:
	var r := CBHitReact.new()
	r.name = "hit_react"
	r.cfg = settings_for(key)
	skel.add_child(r)
	return r


func _num(k: String, fallback: float) -> float:
	return float(cfg.get(k, fallback))


# ------------------------------------------------------------------ impulses

## the victim: push the body part at `world_pos` along `world_dir`; `mag` is the swing in radians at the contact point
func impact(world_pos: Vector3, world_dir: Vector3, mag: float) -> void:
	var skel := get_skeleton()
	if skel == null or not bool(cfg.get("enabled", true)):
		return
	var p := skel.global_transform.affine_inverse() * world_pos
	var d := (skel.global_transform.basis.inverse() * world_dir).normalized()
	var radius := maxf(_num("radius", 0.55), 0.05)
	var kind := str(cfg.get("falloff", "smooth"))
	var n := skel.get_bone_count()
	var dist: Array = []
	var best := 0
	var bd := 1e9
	for i in n:
		var di := _seg_dist(skel, i, p)
		dist.append(di)
		if di < bd:
			bd = di
			best = i
	var w: Array = []
	w.resize(n)
	w.fill(0.0)
	for i in n:
		w[i] = CBSockets.falloff(kind, float(dist[i]) / radius) if float(dist[i]) < radius else 0.0
	_spread(skel, best, w)
	for i in n:
		if float(w[i]) > 0.01:
			_kick(skel, i, d, mag * float(w[i]) * _num("strength", 1.0))


## the attacker's striking bone (and a little up its chain) kicks back against the blow
func recoil(bone_name: String, world_dir: Vector3, mag: float) -> void:
	var skel := get_skeleton()
	if skel == null or not bool(cfg.get("enabled", true)):
		return
	var i := skel.find_bone(bone_name)
	if i < 0:
		return
	var d := (skel.global_transform.basis.inverse() * world_dir).normalized()
	var w: Array = []
	w.resize(skel.get_bone_count())
	w.fill(0.0)
	w[i] = 1.0
	_spread(skel, i, w, true)
	for j in w.size():
		if float(w[j]) > 0.01:
			_kick(skel, j, d, mag * _num("recoil", 0.35) * float(w[j]) * _num("strength", 1.0))


## the pull along the chain from the bone that was hit: parents by `up` per step, children by `down` per step (never lowers a weight)
func _spread(skel: Skeleton3D, from: int, w: Array, up_only: bool = false) -> void:
	w[from] = maxf(float(w[from]), 1.0)
	var k := 1.0
	var i := from
	var guard := 0
	var steps := int(_num("up_steps", 3))   # the pull dies out a few joints up: a hit on the head does not swing the legs
	while skel.get_bone_parent(i) >= 0 and guard < steps:
		i = skel.get_bone_parent(i)
		k *= _num("up", 0.6)
		w[i] = maxf(float(w[i]), k)
		guard += 1
	if up_only:
		return
	_spread_down(skel, from, 1.0, w, 0)


func _spread_down(skel: Skeleton3D, i: int, k: float, w: Array, depth: int) -> void:
	if depth > 6:
		return
	for c in skel.get_bone_children(i):
		var kc := k * _num("down", 0.45)
		w[c] = maxf(float(w[c]), kc)
		_spread_down(skel, c, kc, w, depth + 1)


func _kick(skel: Skeleton3D, i: int, d: Vector3, mag: float) -> void:
	var scale_k := float((cfg.get("bone_scale", {}) as Dictionary).get(skel.get_bone_name(i), 1.0))
	var angle := mag * scale_k
	if absf(angle) < 0.002:
		return
	var origin := skel.get_bone_global_pose(i).origin
	var axis_v := _bone_dir(skel, i).cross(d)
	if axis_v.length() < 0.08:
		axis_v = d.cross(Vector3.UP)
		if axis_v.length() < 0.08:
			axis_v = Vector3.RIGHT
	axis_v = axis_v.normalized()
	var omega := TAU * _num("frequency", 8.0)
	_rw[i] = (_rw.get(i, Vector3.ZERO) as Vector3) + axis_v * angle * omega * 1.1
	_active = true


func _bone_dir(skel: Skeleton3D, i: int) -> Vector3:
	var kids := skel.get_bone_children(i)
	var o := skel.get_bone_global_pose(i).origin
	if not kids.is_empty():
		var v := skel.get_bone_global_pose(kids[0]).origin - o
		if v.length() > 0.001:
			return v.normalized()
	var par := skel.get_bone_parent(i)
	if par >= 0:
		var v2 := o - skel.get_bone_global_pose(par).origin
		if v2.length() > 0.001:
			return v2.normalized()
	return Vector3.DOWN


func _seg_dist(skel: Skeleton3D, i: int, p: Vector3) -> float:
	var a := skel.get_bone_global_pose(i).origin
	var kids := skel.get_bone_children(i)
	var b := a
	if not kids.is_empty():
		b = skel.get_bone_global_pose(kids[0]).origin
	var ab := b - a
	var l2 := ab.length_squared()
	var t := 0.0 if l2 < 1e-8 else clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


# ------------------------------------------------------------------ the spring, applied after the animation

func _process_modification_with_delta(delta: float) -> void:
	if not _active:
		return
	var skel := get_skeleton()
	if skel == null:
		return
	var dt := minf(delta, 1.0 / 20.0)
	var omega := TAU * _num("frequency", 8.0)
	var k := omega * omega
	var c := 2.0 * _num("damping", 0.45) * omega
	var max_a := _num("max_angle", 0.9)
	var alive := false
	var ids: Dictionary = {}
	for i in _rv:
		ids[i] = true
	for i in _rw:
		ids[i] = true
	for i in ids:
		var x: Vector3 = _rv.get(i, Vector3.ZERO)
		var v: Vector3 = _rw.get(i, Vector3.ZERO)
		v += (-k * x - c * v) * dt
		x += v * dt
		if x.length() > max_a:
			x = x.normalized() * max_a
		if x.length() < 0.0006 and v.length() < 0.004:
			_rv.erase(i)
			_rw.erase(i)
			continue
		_rv[i] = x
		_rw[i] = v
		alive = true
		var par := skel.get_bone_parent(i)
		var pb := skel.get_bone_global_pose(par).basis if par >= 0 else Basis.IDENTITY
		var local_axis := pb.inverse() * x
		var ang := local_axis.length()
		if ang > 0.0001:
			var q := Quaternion(local_axis / ang, ang)
			skel.set_bone_pose_rotation(i, q * skel.get_bone_pose_rotation(i))
	_active = alive


func is_busy() -> bool:
	return _active


func clear_state() -> void:
	_rv.clear()
	_rw.clear()
	_active = false
