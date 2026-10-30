class_name RmtBodySolve
extends RefCounted
## The Body Solve (RMT Wrap, Collision Wrap): after a clip has posed the skeleton, every part that went into the body (deeper
## than it does at rest, past its flesh allowance) or under the floor is pushed back out by bending that part's own joints:
## a fist in the face bends the wrist, elbow and shoulder until it sits in front of the face.
##
## - Ranks decide who gives way (the higher rank moves: a hand before the arm, the arm before the chest, a tail last); equal
##   ranks both move half. A part whose joints are all locked can't move, so the other one does.
## - Chains: a part may bend its own joint and a few above it (rules.chain); hips and root never bend. The joint furthest up
##   the chain moves first (the shoulder before the wrist: a person moves the whole arm away), and no joint turns more than its
##   max_turn away from the clip (a wrist never folds back).
## - Every joint stays inside its natural range (the rig limits: wrists, ankles, fingers, spine, neck, shoulders, hips; knees
##   never bend forward). Hinges (elbows, knees) only bend about their own X. A clip that already goes past a limit keeps its
##   own value: the solve never pushes a joint further out.
## - Planted feet stay put: the knee and thigh over a foot on the floor are locked (the ankle may still turn the toes up).
## - Nothing goes through the floor: if the body itself (hips to head) is under it, the whole model is lifted (`lift_node`).
## - Nothing goes into the world (`world`: walls, decks, props, through Godot physics) or into other bodies (`others`: their
##   capsules): limbs, head and tails bend out of them (a punch rests on the chest it hits, a hand on the deck stays on top).
## - A trunk or head can't bend out of the world (a head in the deck under a ledge): the whole model is shifted out instead,
##   at most `nudge_max`, at once, and eases back when it is free (`lift_node`, visual only). Never against another body.
## - No pops: a correction carries over to the next frame and fades when it's not needed, and it changes at most `max_step`
##   radians per frame.
## Deterministic: the same pose in gives the same pose out.

var body: RmtWrapBody
var skel: Skeleton3D
var lift_node: Node3D        # raised when the body is under the floor (the model root); null = never lift
var iterations := 2          # passes per frame (the correction carries over, so it settles over a few frames)
var max_step := 0.25         # radians a bone's correction may change per frame
var keep := 0.8              # share of last frame's correction carried into this frame
var margin := 0.003          # metres pushed out past touching
var tol := 0.0               # self clashes count past this (world metres)
var sole := 0.02             # a foot may sink this far into the floor (metres)
var limits := {}             # bone name -> {"x": [lo, hi], "y": [...], "z": [...]} in the clip's Euler (radians)
var movers := {}             # piece index -> true: only these may move (empty = every piece); the after-springs pass moves chains only
var world: PhysicsDirectSpaceState3D   # stay out of this world's colliders (walls, decks, props); null = no world
var world_mask := 1          # which collision layers count (City Breaker: 1 = solid decks, not the one-way platforms)
var world_exclude: Array[RID] = []    # this body's own colliders
var others: Array = []       # other bodies' capsules this frame, [[a, b, r], ...] in world space: they don't move, this body does
var avoid_from := 2          # pieces of this rank and up stay out of the world and the others (head, limbs, tails; not the trunk)
var nudge_max := 0.25        # metres the whole model may shift (visually) when its trunk or head is in the world (never for
                             # another body: the model would drift away from where its hits land)
var nudge_upto := 2          # pieces up to this rank shift the whole model (trunk, neck, head: they can't bend far enough)
var nudge_back := 0.12       # share of the shift given back per frame once it is no longer needed

var _chain: Array = []       # piece index -> [bone idx...], nearest joint first
var _hinge := {}             # bone idx -> true (bends about its own X only)
var _corr := {}              # bone idx -> Quaternion, local correction on top of the clip pose
var _locked := {}            # bone idx -> true this frame
var _bones: Array = []       # every bone that can bend
var _rest := {}              # bone idx -> rest Basis (orthonormal)
var _max_turn := {}          # bone idx -> radians
var _clip := {}              # bone idx -> the clip's own local rotation this frame
var _others_box := AABB()    # around `others` this frame
var _shape_box := {}         # Shape3D -> its local AABB (debug mesh), for the cheap test before a precise world query
var _cap_shape := {}         # piece index -> [CapsuleShape3D, PhysicsShapeQueryParameters3D]
var _nudge := Vector3.ZERO   # the whole-model shift carried from frame to frame (out at once, back slowly)


func _init(p_body: RmtWrapBody, chain_rules: Dictionary, p_limits: Dictionary, turn_rules: Dictionary = {}, hinges: Array = []) -> void:
	body = p_body
	skel = body.skel
	limits = p_limits
	var seen := {}
	for p in body.pieces:
		var n := int(_by_prefix(str(p["id"]), chain_rules, 1))
		var ch: Array = []
		var b := int(p["bone_idx"])
		for _k in n:
			if b < 0 or skel.get_bone_name(b) in ["hips", "root"]:
				break
			ch.append(b)
			if not seen.has(b):
				seen[b] = true
				_bones.append(b)
				_rest[b] = skel.get_bone_rest(b).basis.orthonormalized()
				_max_turn[b] = float(_by_prefix(skel.get_bone_name(b), turn_rules, 1.2))
			b = skel.get_bone_parent(b)
		ch.reverse()   # furthest joint first
		_chain.append(ch)
	for name in limits:
		var bi := skel.find_bone(str(name))
		if bi >= 0 and (str(name) in hinges or (hinges.is_empty() and (limits[name] as Dictionary).keys() == ["x"])):
			_hinge[bi] = true


## the rig's Euler convention (the clip format and the joint limits): Rz * Ry * Rx on top of the rest pose
static func euler_basis(e: Vector3) -> Basis:
	return Basis(Vector3.BACK, e.z) * Basis(Vector3.UP, e.y) * Basis(Vector3.RIGHT, e.x)


static func _by_prefix(id: String, table: Dictionary, fallback: Variant) -> Variant:
	var best := ""
	for pre in table:
		if id.begins_with(str(pre)) and str(pre).length() > best.length():
			best = str(pre)
	return table[best] if best != "" else fallback


## forget the carried corrections (a new fighter, a teleport)
func reset() -> void:
	_corr.clear()
	_nudge = Vector3.ZERO


## run right after the clip pose is on the skeleton; floor_y = NAN when no floor counts this frame (in the air)
func solve(floor_y: float = NAN) -> Dictionary:
	var clip := {}
	for b in _bones:
		clip[b] = skel.get_bone_pose_rotation(b)
	_clip = clip
	for b in _corr:
		skel.set_bone_pose_rotation(b, Quaternion.IDENTITY.slerp(_corr[b], keep) * clip[b])
		_clamp_limits(b)
		_cap_turn(b)
	skel.force_update_all_bone_transforms()
	var stats := {"contacts": 0, "lift": 0.0, "max_corr": 0.0, "max_corr_bone": ""}
	_locked.clear()
	_others_box = AABB()
	for k in others.size():
		var o: Array = others[k]
		var ob := AABB((o[0] as Vector3).min(o[1]), ((o[0] as Vector3) - (o[1] as Vector3)).abs()).grow(float(o[2]))
		_others_box = ob if k == 0 else _others_box.merge(ob)
	var caps: Array = []
	if lift_node != null and world != null:
		stats["nudge"] = _nudge_out()
	if not is_nan(floor_y):
		stats["lift"] = _lift(floor_y)
		caps = body.capsules()
		_lock_planted(floor_y, caps)
	for it in iterations:
		var contacts := _contacts(floor_y, caps)
		caps = []
		if it == 0:
			stats["contacts"] = contacts.size()
		if contacts.is_empty():
			break
		for c in contacts:
			_push(int(c[0]), c[1], c[2], float(c[3]))
	# keep what changed as this frame's correction, never more than max_step away from last frame's
	for b in _bones:
		var now := skel.get_bone_pose_rotation(b)
		var corr: Quaternion = now * (clip[b] as Quaternion).inverse()
		var prev: Quaternion = _corr.get(b, Quaternion.IDENTITY)
		var step := prev.angle_to(corr)
		if step > max_step:
			corr = prev.slerp(corr, max_step / step)
			skel.set_bone_pose_rotation(b, corr * clip[b])
		if corr.angle_to(Quaternion.IDENTITY) < 0.002:
			_corr.erase(b)
			skel.set_bone_pose_rotation(b, clip[b])
		else:
			_corr[b] = corr
			var ang := corr.angle_to(Quaternion.IDENTITY)
			if ang > float(stats["max_corr"]):
				stats["max_corr"] = ang
				stats["max_corr_bone"] = skel.get_bone_name(b)
	skel.force_update_all_bone_transforms()
	return stats


## the trunk and head (ranks up to nudge_upto) can't bend out of the world: shift the whole model out by the deepest contact,
## at once; give it back slowly when it's free. Not against other bodies: there the model would drift from where its hits land
## (a thrown item, a hit, all read the clip pose), so limbs bend and that's all
func _nudge_out() -> float:
	var caps := body.capsules()
	var want := Vector3.ZERO
	var near := _near_world(caps) if world != null else []
	for i in body.pieces.size():
		if int(body.pieces[i]["rank"]) > nudge_upto:
			continue
		var cp: Array = caps[i]
		var box := AABB((cp[0] as Vector3).min(cp[1]), ((cp[0] as Vector3) - (cp[1] as Vector3)).abs()).grow(float(cp[2]))
		for nb in near:
			if box.intersects(nb):
				for hit in _query_world(i, cp):
					var v: Vector3 = (hit[1] as Vector3) * (float(hit[2]) + margin)
					if v.length() > want.length():
						want = v
				break
	want = want.limit_length(nudge_max)
	# out at once (so nothing shows through), back slowly (so it never snaps)
	if want == Vector3.ZERO:
		_nudge *= 1.0 - nudge_back
	else:
		var d := want.normalized()
		var along := _nudge.dot(d)
		if along < want.length():
			_nudge += d * (want.length() - along)
		else:
			_nudge -= d * minf(along - want.length(), along * nudge_back)
	if _nudge.length() < 0.001:
		_nudge = Vector3.ZERO
		return 0.0
	_shift(_nudge)
	skel.force_update_all_bone_transforms()
	return _nudge.length()


## move the model by a world offset through its LOCAL position: setting global_position rebuilds the node's rotation from its
## basis, and on a model pitched past 90 degrees (a thrown fighter) that reads back as a flipped twin (y and z turned by PI) which
## the next frame's `rotation.x = ...` then keeps: the fighter stays upside down and its hurt checks with it
func _shift(world_delta: Vector3) -> void:
	var p := lift_node.get_parent() as Node3D
	lift_node.position += p.global_transform.basis.inverse() * world_delta if p != null else world_delta


## the body itself (hips to head) can't be under the floor: lift the whole model
func _lift(floor_y: float) -> float:
	if lift_node == null:
		return 0.0
	var caps := body.capsules()
	var deepest := 0.0
	for i in body.pieces.size():
		if int(body.pieces[i]["rank"]) <= 2:
			var c: Array = caps[i]
			deepest = maxf(deepest, floor_y - RmtCapsule.bottom(c[0], c[1], c[2]))
	if deepest > 0.0:
		_shift(Vector3(0.0, deepest, 0.0))
		skel.force_update_all_bone_transforms()
	return deepest


## a foot on the floor keeps its place: the knee and thigh above it may not bend
func _lock_planted(floor_y: float, caps: Array) -> void:
	for i in body.pieces.size():
		var id := str(body.pieces[i]["id"])
		if not id.begins_with("foot"):
			continue
		var c: Array = caps[i]
		if RmtCapsule.bottom(c[0], c[1], c[2]) - floor_y < 0.05:
			var b := skel.get_bone_parent(int(body.pieces[i]["bone_idx"]))
			while b >= 0 and not skel.get_bone_name(b) in ["hips", "root"]:
				_locked[b] = true
				b = skel.get_bone_parent(b)


func _movable(i: int) -> bool:
	if not movers.is_empty() and not movers.has(i):
		return false
	for b in _chain[i]:
		if not _locked.has(b):
			return true
	return false


## [piece, point on its axis, push direction, how far]
func _contacts(floor_y: float, caps: Array = []) -> Array:
	if caps.is_empty():
		caps = body.capsules()
	var out: Array = []
	for c in body.clashes(tol, caps):
		var i := int(c["i"])
		var j := int(c["j"])
		var ex := float(c["excess"]) + margin
		var n: Vector3 = c["normal"]
		var ri := int(body.pieces[i]["rank"])
		var rj := int(body.pieces[j]["rank"])
		var mi := _movable(i)
		var mj := _movable(j)
		if ri == rj and mi and mj:
			out.append([i, c["pa"], n, ex * 0.5])
			out.append([j, c["pb"], -n, ex * 0.5])
		elif mi and (ri > rj or not mj):
			out.append([i, c["pa"], n, ex])
		elif mj:
			out.append([j, c["pb"], -n, ex])
	if not is_nan(floor_y):
		for i in body.pieces.size():
			var cp: Array = caps[i]
			var low: Vector3 = cp[0] if (cp[0] as Vector3).y < (cp[1] as Vector3).y else cp[1]
			var allow := sole if str(body.pieces[i]["id"]).begins_with("foot") else 0.0
			var ex := floor_y - (low.y - float(cp[2])) - allow
			if ex > 0.0 and _movable(i):
				out.append([i, low, Vector3.UP, ex + margin])
	if others.is_empty() and world == null:
		return out
	var near := _near_world(caps) if world != null else []
	for i in body.pieces.size():
		if int(body.pieces[i]["rank"]) < avoid_from or not _movable(i):
			continue
		var cp: Array = caps[i]
		var box := AABB((cp[0] as Vector3).min(cp[1]), ((cp[0] as Vector3) - (cp[1] as Vector3)).abs()).grow(float(cp[2]))
		# other bodies: their capsules don't move, this piece bends out of them
		if not others.is_empty() and box.intersects(_others_box):
			for o in others:
				var ov := RmtCapsule.overlap(cp[0], cp[1], cp[2], o[0], o[1], o[2])
				if float(ov["depth"]) > tol:
					out.append([i, ov["pa"], ov["normal"], float(ov["depth"]) + margin])
		# the world: a precise query only when the piece is near one of the colliders around the body
		for nb in near:
			if box.intersects(nb):
				var allow := sole if str(body.pieces[i]["id"]).begins_with("foot") else 0.0
				for hit in _query_world(i, cp):
					var ex := float(hit[2]) - allow
					if ex > 0.0:
						out.append([i, hit[0], hit[1], ex + margin])
				break
	return out


## the world colliders around the whole body this frame, as world AABBs (one broad query)
func _near_world(caps: Array) -> Array:
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for c in caps:
		var r := Vector3.ONE * float(c[2])
		lo = lo.min((c[0] as Vector3).min(c[1]) - r)
		hi = hi.max((c[0] as Vector3).max(c[1]) + r)
	var shape := BoxShape3D.new()
	shape.size = (hi - lo).max(Vector3.ONE * 0.01)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), (lo + hi) * 0.5)
	q.collision_mask = world_mask
	q.exclude = world_exclude
	var out: Array = []
	for r in world.intersect_shape(q, 16):
		var co: Object = r["collider"]
		if not co is CollisionObject3D:
			continue
		var obj := co as CollisionObject3D
		var owner_id := obj.shape_find_owner(int(r["shape"]))
		var node := obj.shape_owner_get_owner(owner_id) as Node3D
		var sh := obj.shape_owner_get_shape(owner_id, 0) if obj.shape_owner_get_shape_count(owner_id) > 0 else null
		if node == null or sh == null:
			continue
		if not _shape_box.has(sh):
			var m := sh.get_debug_mesh()
			_shape_box[sh] = m.get_aabb() if m != null else AABB(-Vector3.ONE, Vector3.ONE * 2.0)
		out.append(node.global_transform * (_shape_box[sh] as AABB))
	return out


## [[point on the piece, push direction, depth], ...] where piece i is inside the world
func _query_world(i: int, cp: Array) -> Array:
	if not _cap_shape.has(i):
		var cs := CapsuleShape3D.new()
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = cs
		_cap_shape[i] = [cs, q]
	var a: Vector3 = cp[0]
	var b: Vector3 = cp[1]
	var r := float(cp[2])
	var cs: CapsuleShape3D = _cap_shape[i][0]
	var q: PhysicsShapeQueryParameters3D = _cap_shape[i][1]
	cs.radius = r
	cs.height = a.distance_to(b) + 2.0 * r
	var y := (b - a).normalized() if a.distance_to(b) > 1e-5 else Vector3.UP
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	q.transform = Transform3D(Basis(x, y, x.cross(y)), (a + b) * 0.5)
	q.collision_mask = world_mask
	q.exclude = world_exclude
	var res := world.collide_shape(q, 4)
	var out: Array = []
	for k in res.size() / 2:
		var ps: Vector3 = res[k * 2]
		var d: Vector3 = (res[k * 2 + 1] as Vector3) - ps   # the other point minus ours = the way out (checked on Jolt)
		var depth := d.length()
		if depth > 1e-5:
			out.append([ps, d / depth, depth])
	return out


## move point `p` of piece `i` by `amount` along `dir`, bending the piece's chain (nearest joint first)
func _push(i: int, p: Vector3, dir: Vector3, amount: float) -> void:
	var target := p + dir * amount
	var cur := p
	var g := skel.global_transform
	var srot := g.basis.orthonormalized()
	for b in _chain[i]:
		if _locked.has(b):
			continue
		var pose := skel.get_bone_global_pose(b)
		var j := g * pose.origin
		var u := cur - j
		var v := target - j
		if u.length() < 1e-4 or v.length() < 1e-4:
			continue
		if _hinge.has(b):
			var ax := (srot * pose.basis.orthonormalized()).x.normalized()
			var up := u - ax * u.dot(ax)
			var vp := v - ax * v.dot(ax)
			if up.length() < 1e-4 or vp.length() < 1e-4:
				continue
			var ang := clampf(atan2(ax.dot(up.cross(vp)), up.dot(vp)), -0.5, 0.5)
			var e := (_rest[b] as Basis).inverse() * Basis(skel.get_bone_pose_rotation(b))
			var eu := e.get_euler(EULER_ORDER_ZYX)
			var want := eu.x + ang
			var lim: Array = (limits[skel.get_bone_name(b)] as Dictionary)["x"]
			var cx := ((_rest[b] as Basis).inverse() * Basis(_clip.get(b, skel.get_bone_pose_rotation(b)))).get_euler(EULER_ORDER_ZYX).x
			want = clampf(want, minf(float(lim[0]), cx), maxf(float(lim[1]), cx))
			var turn := want - eu.x
			if absf(turn) < 1e-5:
				continue
			eu.x = want
			skel.set_bone_pose_rotation(b, ((_rest[b] as Basis) * euler_basis(eu)).get_rotation_quaternion())
			cur = j + Quaternion(ax, turn) * (cur - j)
		else:
			var q := Quaternion(u.normalized(), v.normalized())
			var a := q.get_angle()
			if a < 1e-5:
				continue
			if a > 0.5:
				q = Quaternion.IDENTITY.slerp(q, 0.5 / a)
			# the world turn, seen from the bone's parent
			var qs := srot.get_rotation_quaternion().inverse() * q * srot.get_rotation_quaternion()
			var par := skel.get_bone_parent(b)
			var qp := skel.get_bone_global_pose(par).basis.get_rotation_quaternion() if par >= 0 else Quaternion.IDENTITY
			skel.set_bone_pose_rotation(b, (qp.inverse() * qs * qp) * skel.get_bone_pose_rotation(b))
			cur = j + q * (cur - j)
		_clamp_limits(b)
		_cap_turn(b)
		skel.force_update_bone_child_transform(b)
		if cur.distance_to(target) < 0.002:
			break


## keep a joint inside its natural range (the rig limits on the clip's Euler); where the clip itself already goes past a limit,
## the clip's own value is the edge (the solve never makes it worse)
func _clamp_limits(b: int) -> void:
	var lim: Dictionary = limits.get(skel.get_bone_name(b), {})
	if lim.is_empty():
		return
	var rest: Basis = _rest[b]
	var e := (rest.inverse() * Basis(skel.get_bone_pose_rotation(b))).get_euler(EULER_ORDER_ZYX)
	var c := (rest.inverse() * Basis(_clip.get(b, skel.get_bone_pose_rotation(b)))).get_euler(EULER_ORDER_ZYX)
	var out := e
	for i in 3:
		var ax: String = ["x", "y", "z"][i]
		if lim.has(ax):
			var r: Array = lim[ax]
			out[i] = clampf(e[i], minf(float(r[0]), c[i]), maxf(float(r[1]), c[i]))
	if out.is_equal_approx(e):
		return
	var q := (rest * euler_basis(out)).get_rotation_quaternion()
	# near gimbal lock the Euler reading can flip to a mirror twin far from the real turn: never clamp across that
	if q.angle_to(skel.get_bone_pose_rotation(b)) < 0.6:
		skel.set_bone_pose_rotation(b, q)


## keep a joint within max_turn of the clip's own rotation
func _cap_turn(b: int) -> void:
	var c: Quaternion = _clip.get(b, skel.get_bone_pose_rotation(b))
	var corr := skel.get_bone_pose_rotation(b) * c.inverse()
	var a := corr.angle_to(Quaternion.IDENTITY)
	var m := float(_max_turn.get(b, 1.2))
	if a > m:
		skel.set_bone_pose_rotation(b, Quaternion.IDENTITY.slerp(corr, m / a) * c)
