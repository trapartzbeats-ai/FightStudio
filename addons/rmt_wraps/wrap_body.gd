class_name RmtWrapBody
extends RefCounted
## A Collision Wrap on a live skeleton: the wrap's capsules where the bones are right now, and which of them go into each other.
##   var body := RmtWrapBody.new(RmtWrapBody.load_wrap("res://.../vix.collide.json"), skel)
##   for c in body.clashes(0.01): ...      # pieces going into each other deeper than 1 cm (world metres)

var skel: Skeleton3D
var pieces: Array = []   # [{id, bone_idx, a, b, r, rank}] (a / b / r in skeleton space)
var pairs: Array = []    # [[i, j, allow, soft]] piece indices; allow in skeleton space, soft in world metres
var index := {}          # id -> piece index
var _pi := PackedInt32Array()     # pairs, flat: piece i, piece j
var _pa := PackedFloat32Array()   # pairs, flat: allow (skeleton space), soft (metres)


static func load_wrap(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	return RmtWrapFit.from_json(d) if d is Dictionary else {}


func _init(wrap: Dictionary, p_skel: Skeleton3D) -> void:
	skel = p_skel
	for p in wrap.get("pieces", []):
		var bi := skel.find_bone(str(p["bone"]))
		if bi < 0:
			continue
		index[str(p["id"])] = pieces.size()
		pieces.append({"id": str(p["id"]), "bone_idx": bi, "a": p["a"], "b": p["b"], "r": float(p["r"]), "rank": int(p.get("rank", 9))})
	for pr in wrap.get("pairs", []):
		if index.has(str(pr[0])) and index.has(str(pr[1])):
			pairs.append([index[str(pr[0])], index[str(pr[1])], float(pr[2]), float(pr[3]) if (pr as Array).size() > 3 else 0.0])
	for pr in pairs:
		_pi.append(pr[0])
		_pi.append(pr[1])
		_pa.append(pr[2])
		_pa.append(pr[3])


## world size of one skeleton-space metre (the model is scaled to its match height)
func world_scale() -> float:
	return skel.global_transform.basis.get_scale().x


## every piece where it is now, in world space: [[a, b, r], ...] (same order as `pieces`)
func capsules() -> Array:
	var out: Array = []
	var g := skel.global_transform
	var s := world_scale()
	for p in pieces:
		var t := g * skel.get_bone_global_pose(int(p["bone_idx"]))
		out.append([t * (p["a"] as Vector3), t * (p["b"] as Vector3), float(p["r"]) * s])
	return out


## pairs going into each other deeper than they do at rest plus `tol` (world metres):
## [{i, j, excess, depth, normal, pa, pb}], `normal` pushes piece i out of piece j
func clashes(tol: float, caps: Array = []) -> Array:
	if caps.is_empty():
		caps = capsules()
	var s := world_scale()
	var n := caps.size()
	# a bounding sphere per piece: most pairs are far apart and stop at one distance check
	var mid := PackedVector3Array()
	var rad := PackedFloat32Array()
	mid.resize(n)
	rad.resize(n)
	for k in n:
		var c: Array = caps[k]
		mid[k] = ((c[0] as Vector3) + (c[1] as Vector3)) * 0.5
		rad[k] = (c[0] as Vector3).distance_to(c[1]) * 0.5 + float(c[2])
	var out: Array = []
	for k in _pi.size() / 2:
		var i := _pi[k * 2]
		var j := _pi[k * 2 + 1]
		var reach := rad[i] + rad[j]
		if mid[i].distance_squared_to(mid[j]) > reach * reach:
			continue
		var a: Array = caps[i]
		var b: Array = caps[j]
		var o := RmtCapsule.overlap(a[0], a[1], a[2], b[0], b[1], b[2])
		var excess := float(o["depth"]) - _pa[k * 2] * s - _pa[k * 2 + 1]
		if excess > tol:
			out.append({"i": i, "j": j, "excess": excess, "depth": o["depth"], "normal": o["normal"], "pa": o["pa"], "pb": o["pb"]})
	return out


## pieces below a floor at height `floor_y` deeper than `tol`: [{i, excess}]; `skip` = piece ids left out (feet stand on it)
func under_floor(floor_y: float, tol: float, skip: Array = [], caps: Array = []) -> Array:
	if caps.is_empty():
		caps = capsules()
	var out: Array = []
	for i in pieces.size():
		if str(pieces[i]["id"]) in skip:
			continue
		var c: Array = caps[i]
		var ex := floor_y - RmtCapsule.bottom(c[0], c[1], c[2])
		if ex > tol:
			out.append({"i": i, "excess": ex})
	return out
