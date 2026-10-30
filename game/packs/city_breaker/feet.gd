class_name CBFeet
extends RefCounted
## Feet on the floor. Each foot's sole is read once from the model's own mesh: the plane the bottom of the foot lies on, how high
## the ankle sits above it, and the sole's outline (toe, heel, sides). The models were not all built standing level: Carter, Al,
## Guru, Hype and Vic stand in a stance at rest with one foot turned out and lower than the other, so neither the ankle bone nor
## the rest pose says where the sole is. ground() then, on a pose the clip just put on the skeleton:
##   1. levels every foot near the floor on its own sole plane, keeping where the toes point; a foot whose ankle the clip keys
##      well onto the toes or the heel (a push-off, a heel strike) keeps that and pivots on the toe / heel. A foot only tipped
##      because the shin leans (bent knees, the ankle keyed straight) is levelled: that tip is not meant
##   2. keeps every ankle inside its natural turn, so a deep crouch lifts the heel instead of bending the ankle past what one does
##   3. (planted clips) lifts or lowers the body so the lower foot's sole, not its ankle, stands on the floor
##   4. brings each foot near the floor onto it with two-bone leg IK: the knee keeps the clip's own bend plane and is never
##      straighter than its rest bend (the rig's knee limit); when a leg cannot reach, the body comes down a little so it can. No foot, standing or not,
##      goes into the floor
## A foot well off the floor (a kick, a step) is left as the clip keys it, fading in between.
##   CBFeet.ground(skel, model, floor_y, planted)   after CBClipLib.apply_pose, with model.position.y reset by the caller

const CONTACT_FULL := 0.04     # a foot whose lowest point is up to 4 cm above the other one's is standing on the floor
const CONTACT_NONE := 0.12     # one 12 cm up is off it (in between it fades)
const PIVOT_FROM := 0.3        # radians the clip keys the ankle toward the toes / heel (from rest) where a pivot starts
const PIVOT_FULL := 0.6        # and from here the foot keeps the clip's tip fully
## natural ankle turns (rig v4: foot +X = toes down), the same as the rig's natural limits
const LIMITS := {
	"footL": {"x": [-0.7, 0.95], "y": [-0.5, 0.5], "z": [-0.45, 0.45]},
	"footR": {"x": [-0.7, 0.95], "y": [-0.5, 0.5], "z": [-0.45, 0.45]},
}
const SIDES := ["L", "R"]
## the soles of the roster's models, read ahead of time (tools/feet_bake.gd) so a model shows without the 50-330 ms read; an
## entry whose model changed (other bone or vertex count) is ignored and the sole is read off the mesh again
const BAKED := "res://game/packs/city_breaker/data/feet_soles.json"

static var _cache := {}
static var _baked = null


## {"footL": {"n": sole up in the foot's own axes, "h": ankle height above the sole plane, "pts": sole outline (foot axes),
##  "tilt0": how far the sole is off level at rest (degrees), "verts": how many vertices the foot carries}, "footR": ...}
static func sole_info(sk: Skeleton3D) -> Dictionary:
	var meshes := _meshes(sk)
	var key := "%d" % sk.get_bone_count()
	for mi in meshes:
		key += ":%d" % (mi as MeshInstance3D).mesh.get_instance_id()
	if meshes.is_empty():
		key = "bare:%d" % sk.get_instance_id()
	if _cache.has(key):
		return _cache[key]
	var out := _from_bake(sk, meshes)
	if out.is_empty():
		out = read_soles(sk, meshes)
	_cache[key] = out
	return out


## read the soles off the meshes now (no bake, no cache)
static func read_soles(sk: Skeleton3D, meshes: Array = []) -> Dictionary:
	if meshes.is_empty():
		meshes = _meshes(sk)
	var out := {}
	for s in SIDES:
		var fb := sk.find_bone("foot" + s)
		if fb >= 0:
			out["foot" + s] = _fit(sk, fb, meshes)
	return out


## a bake entry for this model: {"bones", "mesh_verts", "footL": {n, h, pts, tilt0, verts, size}, ...} (JSON-ready)
static func bake_entry(sk: Skeleton3D) -> Dictionary:
	var meshes := _meshes(sk)
	var e := {"bones": sk.get_bone_count(), "mesh_verts": _mesh_verts(meshes)}
	var soles := read_soles(sk, meshes)
	for b in soles:
		var fi: Dictionary = soles[b]
		var pts: Array = []
		for p in fi["pts"]:
			pts.append([snappedf(p.x, 0.00001), snappedf(p.y, 0.00001), snappedf(p.z, 0.00001)])
		var n: Vector3 = fi["n"]
		e[b] = {"n": [n.x, n.y, n.z], "h": fi["h"], "pts": pts, "tilt0": fi["tilt0"], "verts": fi["verts"], "size": fi["size"]}
	return e


## the model's scene file (the key in the bake), "" when the skeleton is not in a saved scene
static func model_key(sk: Skeleton3D) -> String:
	return sk.owner.scene_file_path if sk.owner != null else ""


static func _from_bake(sk: Skeleton3D, meshes: Array) -> Dictionary:
	if _baked == null:
		_baked = {}
		if FileAccess.file_exists(BAKED):
			var j = JSON.parse_string(FileAccess.get_file_as_string(BAKED))
			if j is Dictionary:
				_baked = j
	var e: Dictionary = (_baked as Dictionary).get(model_key(sk), {})
	if e.is_empty() or int(e.get("bones", -1)) != sk.get_bone_count() or int(e.get("mesh_verts", -1)) != _mesh_verts(meshes):
		return {}
	var out := {}
	for s in SIDES:
		var b: String = "foot" + s
		if not e.has(b):
			continue
		var fi: Dictionary = e[b]
		var pts: Array = []
		for p in fi["pts"]:
			pts.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
		var n: Array = fi["n"]
		out[b] = {"n": Vector3(float(n[0]), float(n[1]), float(n[2])), "h": float(fi["h"]), "pts": pts, "tilt0": float(fi["tilt0"]),
			"verts": int(fi["verts"]), "size": float(fi["size"])}
	return out


static func _mesh_verts(meshes: Array) -> int:
	var n := 0
	for mi in meshes:
		var m: Mesh = (mi as MeshInstance3D).mesh
		for si in m.get_surface_count():
			n += m.surface_get_array_len(si)
	return n


## the feet of a posed skeleton on a floor at height floor_y (see the top of this file); returns what it did:
## {"lift": body raised by (m), "drop": body lowered so a leg could reach (m), "footL": {"w", "tilt", "gap"}, ...}
static func ground(sk: Skeleton3D, model: Node3D, floor_y: float, planted: bool) -> Dictionary:
	var info := sole_info(sk)
	var done := {"lift": 0.0, "drop": 0.0}
	if info.is_empty():
		return done
	sk.force_update_all_bone_transforms()
	var up_s := (sk.global_transform.basis.inverse() * Vector3.UP).normalized()   # world up, in the skeleton's axes
	var scale := (sk.global_transform.basis * up_s).length()
	var st := standing(sk, info)
	var w := {}
	for b in info:
		w[b] = float(st[b]["w"])
		done[b] = (st[b] as Dictionary).duplicate()
		(done[b] as Dictionary)["gap"] = 0.0
	# 1 + 2: level the standing feet (their own sole plane), inside the ankle's natural turn
	var hold := {}
	for b in info:
		var bi := sk.find_bone(b)
		if float(w[b]) > 0.0:
			var g := sk.get_bone_global_pose(bi).basis.orthonormalized()
			_set_global(sk, bi, Basis(g.get_rotation_quaternion().slerp((st[b]["flat"] as Basis).get_rotation_quaternion(), float(w[b]))))
			(done[b] as Dictionary)["limit"] = _clamp(sk, bi, b)
			sk.force_update_all_bone_transforms()
		hold[b] = sk.get_bone_global_pose(bi).basis.orthonormalized()
	# 3: the body, so the lower sole stands on the floor
	if planted and model != null:
		var low := INF
		for b in info:
			low = minf(low, lowest(sk, b, info))
		if low != INF:
			model.position.y += floor_y - low
			done["lift"] = floor_y - low
			sk.force_update_all_bone_transforms()
	# 4: each standing foot onto the floor (legs), the body down a little when a leg cannot reach; again until it settles (the
	# ankle's limits can turn a foot a hair once the shin has moved)
	for pass_i in 4:
		var short := 0.0
		var moved := 0.0
		for b in info:
			var gap := lowest(sk, b, info) - floor_y
			(done[b] as Dictionary)["gap"] = gap
			var dy := -gap * float(w[b]) if gap > 0.0 else -gap   # a foot never goes into the floor, standing or not
			if absf(dy) < 5e-4:
				continue
			moved = maxf(moved, absf(dy))
			short = maxf(short, _reach(sk, b, sk.global_transform.basis.inverse() * Vector3(0, dy, 0), hold[b]) * scale)
		if short >= 0.002 and planted and model != null and float(done["drop"]) == 0.0:
			model.position.y -= short
			done["drop"] = short
			sk.force_update_all_bone_transforms()
			continue
		if moved < 5e-4:
			break
	return done


## which feet of the pose stand on the floor (changes nothing): per foot {"w": 1 standing .. 0 off the floor, "pivot": how much
## the clip keys the ankle onto the toes / heel, "tilt": degrees the sole is off level as keyed, "flat": the turn it would stand
## with}. Judged on each foot as it would stand (levelled; a pivot keeps the clip's tip), because levelling a foot whose toes
## dig in lifts its lowest point a lot. A foot that cannot stand flat where the leg puts it (a back leg stretched out behind)
## is off the floor here: its toes may touch, its heel is up, as the clip has it.
static func standing(sk: Skeleton3D, info: Dictionary = {}) -> Dictionary:
	if info.is_empty():
		info = sole_info(sk)
	var up_s := (sk.global_transform.basis.inverse() * Vector3.UP).normalized()
	var out := {}
	var lo := INF
	for b in info:
		var bi := sk.find_bone(b)
		var g := sk.get_bone_global_pose(bi).basis.orthonormalized()
		var n := (g * (info[b]["n"] as Vector3)).normalized()
		var keyed := (sk.get_bone_rest(bi).basis.orthonormalized().inverse() * Basis(sk.get_bone_pose_rotation(bi))).get_euler(EULER_ORDER_ZYX).x
		var pivot := smoothstep(PIVOT_FROM, PIVOT_FULL, absf(keyed))
		var level := Basis(g.get_rotation_quaternion().slerp((_arc(n, up_s) * g).get_rotation_quaternion(), 1.0 - pivot))
		var est := _lowest_as(sk, bi, info[b], level)
		lo = minf(lo, est)
		out[b] = {"tilt": rad_to_deg(n.angle_to(up_s)), "pivot": pivot, "flat": level, "est": est}
	for b in out:
		out[b]["w"] = 1.0 - smoothstep(CONTACT_FULL, CONTACT_NONE, float(out[b]["est"]) - lo)
	return out


## the lowest point of a foot's sole outline, world height
static func lowest(sk: Skeleton3D, b: String, info: Dictionary = {}) -> float:
	if info.is_empty():
		info = sole_info(sk)
	if not info.has(b):
		return INF
	var gp := sk.get_bone_global_pose(sk.find_bone(b))
	var lo := INF
	for p in (info[b]["pts"] as Array):
		lo = minf(lo, (sk.global_transform * (gp * (p as Vector3))).y)
	return lo


## the lowest point of a foot's sole if it had global turn `g` (skeleton axes), world height
static func _lowest_as(sk: Skeleton3D, bi: int, fi: Dictionary, g: Basis) -> float:
	var t := Transform3D(g, sk.get_bone_global_pose(bi).origin)
	var lo := INF
	for p in (fi["pts"] as Array):
		lo = minf(lo, (sk.global_transform * (t * (p as Vector3))).y)
	return lo


## move a foot's ankle by delta (skeleton axes) with the leg: thigh + shin turn in the knee's own bend plane; the foot keeps
## `hold` (its global turn). Returns how far short the leg fell (skeleton units), 0 when it reached.
static func _reach(sk: Skeleton3D, b: String, delta: Vector3, hold: Basis) -> float:
	var s := b.substr(4)
	var ia := sk.find_bone("leg" + s)
	var ib := sk.find_bone("knee" + s)
	var ic := sk.find_bone(b)
	if ia < 0 or ib < 0 or ic < 0:
		return 0.0
	var ga := sk.get_bone_global_pose(ia)
	var pa := ga.origin
	var pb := sk.get_bone_global_pose(ib).origin
	var pc := sk.get_bone_global_pose(ic).origin
	var l1 := pa.distance_to(pb)
	var l2 := pb.distance_to(pc)
	var to := pc + delta - pa
	if l1 < 1e-5 or l2 < 1e-5 or to.length() < 1e-5:
		return 0.0
	# the longest the leg gets: its knee at the rest bend (knee X 0, the rig's limit), which is a little bent on the models
	# built standing in a stance; never a straight-line l1 + l2 that would take the knee past it
	var reach := minf(l1 + l2, sk.get_bone_global_rest(ia).origin.distance_to(sk.get_bone_global_rest(ic).origin)) - 1e-4
	var short := maxf(0.0, to.length() - reach)
	var d := clampf(to.length(), absf(l1 - l2) + 1e-4, reach)
	var dir := to.normalized()
	# the bend: where the knee points now (off the hip-ankle line); a straight leg bends the knee toward the way the model
	# faces (the skeleton's own +Z; in a match the model is turned side on, so never the world's)
	var line := (pc - pa).normalized()
	var off := (pb - pa) - line * (pb - pa).dot(line)
	if off.length() < 0.01 * l1:
		off = Vector3.BACK
	var u := off - dir * off.dot(dir)
	if u.length() < 1e-6:
		return short
	u = u.normalized()
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var pb2 := pa + dir * (cos_a * l1) + u * (sqrt(1.0 - cos_a * cos_a) * l1)
	var pc2 := pa + dir * d
	_set_global(sk, ia, _arc(pb - pa, pb2 - pa) * ga.basis.orthonormalized())
	sk.force_update_all_bone_transforms()
	var gb1 := sk.get_bone_global_pose(ib)
	var shin := sk.get_bone_global_pose(ic).origin - gb1.origin
	_set_global(sk, ib, _arc(shin, pc2 - pb2) * gb1.basis.orthonormalized())
	sk.force_update_all_bone_transforms()
	_set_global(sk, ic, hold)
	_clamp(sk, ic, b)
	sk.force_update_all_bone_transforms()
	return short


## a bone's turn in skeleton axes, written as its local pose
static func _set_global(sk: Skeleton3D, i: int, want: Basis) -> void:
	var p := sk.get_bone_parent(i)
	var pb := sk.get_bone_global_pose(p).basis.orthonormalized() if p >= 0 else Basis()
	sk.set_bone_pose_rotation(i, (pb.inverse() * want.orthonormalized()).get_rotation_quaternion())


## keep a foot inside its natural turn; true when it had to stop there
static func _clamp(sk: Skeleton3D, i: int, b: String) -> bool:
	var lim: Dictionary = LIMITS.get(b, {})
	if lim.is_empty():
		return false
	var rest := sk.get_bone_rest(i).basis.orthonormalized()
	var e := (rest.inverse() * Basis(sk.get_bone_pose_rotation(i))).get_euler(EULER_ORDER_ZYX)
	var out := e
	for ax in 3:
		var r: Array = lim.get(["x", "y", "z"][ax], [])
		if not r.is_empty():
			out[ax] = clampf(e[ax], float(r[0]), float(r[1]))
	if out.is_equal_approx(e):
		return false
	sk.set_bone_pose_rotation(i, (rest * Basis.from_euler(out, EULER_ORDER_ZYX)).get_rotation_quaternion())
	return true


static func _arc(u: Vector3, v: Vector3) -> Basis:
	var a := u.normalized()
	var b := v.normalized()
	var ax := a.cross(b)
	var dd := clampf(a.dot(b), -1.0, 1.0)
	if ax.length() < 1e-7:
		return Basis() if dd > 0.0 else Basis((a.cross(Vector3.RIGHT) if absf(a.x) < 0.9 else a.cross(Vector3.UP)).normalized(), PI)
	return Basis(ax.normalized(), acos(dd))


## the skinned meshes this skeleton drives
static func _meshes(sk: Skeleton3D) -> Array:
	var root: Node = sk.owner if sk.owner != null else sk.get_parent()
	if root == null:
		root = sk
	var out: Array = []
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh != null and mi.skin != null and mi.get_node_or_null(mi.skeleton) == sk:
			out.append(mi)
	return out


## read one foot's sole from the vertices it carries (weight >= 0.5), at rest, in the foot bone's own axes
static func _fit(sk: Skeleton3D, fb: int, meshes: Array) -> Dictionary:
	var rest_g := sk.get_bone_global_rest(fb)
	var inv := rest_g.affine_inverse()
	var dn := (rest_g.basis.orthonormalized().inverse() * Vector3.DOWN).normalized()   # the floor's down, in the foot's axes
	var pts := PackedVector3Array()
	var tris: Array = []   # foot-local triangles whose 3 corners the foot carries
	for mi0 in meshes:
		var mi := mi0 as MeshInstance3D
		var bone_of := {}
		for i in mi.skin.get_bind_count():
			var bi := mi.skin.get_bind_bone(i)
			bone_of[i] = bi if bi >= 0 else sk.find_bone(mi.skin.get_bind_name(i))
		for si in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			if arr[Mesh.ARRAY_BONES] == null or vs.is_empty():
				continue
			var bs: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var ws: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			var per := bs.size() / vs.size()
			var local := {}   # vertex index -> foot-local rest position
			for v in vs.size():
				var on := 0.0
				for j in per:
					if int(bone_of.get(bs[v * per + j], -1)) == fb:
						on += ws[v * per + j]
				if on < 0.5:
					continue
				var acc := Vector3.ZERO
				var tw := 0.0
				for j in per:
					var wj := ws[v * per + j]
					var bj := int(bone_of.get(bs[v * per + j], -1))
					if wj <= 0.0 or bj < 0:
						continue
					acc += (sk.get_bone_global_rest(bj) * mi.skin.get_bind_pose(bs[v * per + j]) * vs[v]) * wj
					tw += wj
				var p := inv * (acc / maxf(tw, 1e-6))
				local[v] = p
				pts.append(p)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			for t in range(0, idx.size() - 2, 3):
				if local.has(idx[t]) and local.has(idx[t + 1]) and local.has(idx[t + 2]):
					tris.append([local[idx[t]], local[idx[t + 1]], local[idx[t + 2]]])
	if pts.size() < 8:
		var h0 := maxf(0.0, rest_g.origin.y)
		return {"n": -dn, "h": h0, "pts": [dn * h0], "tilt0": 0.0, "verts": pts.size(), "size": 0.0}
	var ext := AABB(pts[0], Vector3.ZERO)
	for p in pts:
		ext = ext.expand(p)
	var size := ext.get_longest_axis_size()
	# the sole plane: the area-weighted normal of the faces that look down at the bottom of the foot (3 rounds, each on the
	# faces near the plane the round before found)
	var d := dn
	for round_i in 3:
		var s0 := _support(pts, d)
		var acc := Vector3.ZERO
		for t in tris:
			var a: Vector3 = t[0]
			var nb: Vector3 = ((t[1] as Vector3) - a).cross((t[2] as Vector3) - a)   # length = 2 x area
			if nb.length() < 1e-12:
				continue
			if ((a + (t[1] as Vector3) + (t[2] as Vector3)) / 3.0).dot(d) < s0 - 0.12 * size:
				continue
			var nn := nb if nb.dot(d) > 0.0 else -nb   # either winding: the side that faces down
			if nn.normalized().dot(d) < cos(deg_to_rad(50.0)):
				continue
			acc += nn
		if acc.length() < 1e-9:
			break
		d = acc.normalized()
	var s := _support(pts, d)
	# the contact points: whichever vertex is lowest when the foot tips any way up to 80 degrees off level (flat: the sole; on
	# its toes: the toe cap; back on the heel: the heel), so lowest() is right at every tilt. Only the lower half of the foot
	# can be lowest there.
	var fw := rest_g.basis.orthonormalized().inverse() * Vector3.BACK   # the fighter's facing (+Z) in the foot's axes
	fw = (fw - d * fw.dot(d)).normalized()
	var sd := d.cross(fw).normalized()
	var low_half := PackedVector3Array()
	for p in pts:
		if p.dot(d) >= s * 0.5:
			low_half.append(p)
	var outline: Array = []
	for ring in 9:
		var polar := deg_to_rad(10.0 * ring)
		var count := 1 if ring == 0 else maxi(6, int(round(18.0 * sin(polar))))
		for i in count:
			var az := TAU * i / count
			var dv := d * cos(polar) + (fw * cos(az) + sd * sin(az)) * sin(polar)
			var best := low_half[0]
			var bd := -INF
			for p in low_half:
				var v := p.dot(dv)
				if v > bd:
					bd = v
					best = p
			if not outline.has(best):
				outline.append(best)
	var tilt0 := rad_to_deg((rest_g.basis.orthonormalized() * -d).angle_to(Vector3.UP))
	return {"n": -d, "h": s, "pts": outline, "tilt0": tilt0, "verts": pts.size(), "size": size}


static func _support(pts: PackedVector3Array, d: Vector3) -> float:
	var s := -INF
	for p in pts:
		s = maxf(s, p.dot(d))
	return s
