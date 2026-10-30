class_name RmtWrapFit
extends RefCounted
## Fits a Collision Wrap to a skinned model: one capsule per bone, riding that bone, sized from the vertices the bone owns.
##
## Every vertex goes to the bone with the most weight on it (after `merge`, e.g. finger bones into the hand). Each bone's cloud,
## in the bone's own rest space, gets a capsule along its main axis (PCA): the ends trimmed a little so a stray vertex can't
## stretch it, the radius at a percentile of the distances to the axis so the capsule sits just inside the skin (a collision
## shape that sticks out of the skin would clash where nothing touches).
##
## Wrap file (data/wraps/<key>.collide.json), lengths in skeleton space (the model at scale 1):
##   {"version": 1, "kind": "collide", "pieces": [{"id", "bone", "a": [x,y,z], "b": [x,y,z], "r", "rank", "verts"}],
##    "pairs": [[id1, id2, allow]], "rules": {...}}
## `pairs` are the pieces checked against each other (not neighbours at a joint) as [id1, id2, allow, soft]: `allow` = how deep
## they already overlap in the rest pose (skeleton space; the model's own shape, never a clash), `soft` = how much more they may
## press like flesh (world metres, from rules.soft).


## bone-space vertex clouds: {owner bone name: PackedVector3Array}, positions in the owner bone's rest space
static func clouds(model: Node3D, skel: Skeleton3D, rules: Dictionary) -> Dictionary:
	var out := {}
	var to_owner := {}   # bind bone name -> [owner name, Transform3D bone rest space -> owner rest space]
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.skin == null or m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			if arr[Mesh.ARRAY_BONES] == null or arr[Mesh.ARRAY_WEIGHTS] == null:
				continue
			var bo: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var w: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			if bo.is_empty() or v.is_empty():
				continue
			var st := bo.size() / v.size()
			for i in v.size():
				var best := 0
				for j in st:
					if w[i * st + j] > w[i * st + best]:
						best = j
				var bind := bo[i * st + best]
				var bname := m.skin.get_bind_name(bind)
				if bname == "":
					bname = skel.get_bone_name(m.skin.get_bind_bone(bind))
				if not to_owner.has(bname):
					var owner := owner_of(bname, rules)
					var bi := skel.find_bone(bname)
					var oi := skel.find_bone(owner)
					if owner == "" or bi < 0 or oi < 0:
						to_owner[bname] = ["", Transform3D()]
					else:
						to_owner[bname] = [owner, skel.get_bone_global_rest(oi).affine_inverse() * skel.get_bone_global_rest(bi)]
				var o: Array = to_owner[bname]
				if str(o[0]) == "":
					continue
				var p: Vector3 = (o[1] as Transform3D) * (m.skin.get_bind_pose(bind) * v[i])
				if not out.has(o[0]):
					out[o[0]] = []   # a plain Array: a packed array inside a Dictionary is a copy, appends to it are lost
				(out[o[0]] as Array).append(p)
	for k in out:
		out[k] = PackedVector3Array(out[k])
	return out


## the bone a vertex of `bone` counts for: rules.merge maps a name prefix (with its L / R side and any number after it) to the
## owner prefix ("index" -> "hand": indexL2 -> handL); rules.skip lists bones that get no piece and no vertices ("root")
static func owner_of(bone: String, rules: Dictionary) -> String:
	if bone in (rules.get("skip", []) as Array):
		return ""
	var merge: Dictionary = rules.get("merge", {})
	for pre in merge:
		if bone.begins_with(str(pre)):
			var rest := bone.substr(str(pre).length())
			var side := rest.left(1) if rest.left(1) in ["L", "R"] else ""
			var tail := rest.substr(side.length())
			if tail == "" or tail.is_valid_int():
				return str(merge[pre]) + side
	return bone


## the covariance of a cloud around c: [xx, xy, xz, yy, yz, zz]
static func _cov(pts: PackedVector3Array, c: Vector3) -> Array:
	var m := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	for p in pts:
		var d := p - c
		m[0] += d.x * d.x
		m[1] += d.x * d.y
		m[2] += d.x * d.z
		m[3] += d.y * d.y
		m[4] += d.y * d.z
		m[5] += d.z * d.z
	return m


static func _mul(m: Array, v: Vector3) -> Vector3:
	return Vector3(m[0] * v.x + m[1] * v.y + m[2] * v.z, m[1] * v.x + m[3] * v.y + m[4] * v.z, m[2] * v.x + m[4] * v.y + m[5] * v.z)


## the strongest direction of a covariance (power iteration), optionally ignoring a direction already found
static func _power(m: Array, skip: Vector3 = Vector3.ZERO) -> Vector3:
	var v := Vector3(0.3, 1.0, 0.2).normalized()
	if skip != Vector3.ZERO:
		v = (v - skip * v.dot(skip)).normalized()
	for _i in 50:
		var nv := _mul(m, v)
		if skip != Vector3.ZERO:
			nv -= skip * nv.dot(skip)
		if nv.length_squared() < 1e-18:
			break
		v = nv.normalized()
	return v


## the main axis of a cloud (power iteration on its covariance)
static func main_axis(pts: PackedVector3Array, c: Vector3) -> Vector3:
	return _power(_cov(pts, c))


static func _pct(sorted: PackedFloat32Array, q: float) -> float:
	if sorted.is_empty():
		return 0.0
	return sorted[clampi(int(round(q * float(sorted.size() - 1))), 0, sorted.size() - 1)]


## a limb: the bone (joint at the origin to the child joint `e`, bone space) picks the vertices that belong to this stretch (none
## behind the joint: clothes over the joint above it, like shorts over the hip), then the capsule follows the flesh (main axis).
## The radius is capped at `max_frac` x the bone's length when the rules say so (a robe or train weighted to the legs).
static func fit_limb(pts: PackedVector3Array, e: Vector3, rpct: float, trim: float, max_frac: float) -> Dictionary:
	var L := e.length()
	var ax := e / L
	var keep := PackedVector3Array()
	for p in pts:
		var t := p.dot(ax)
		if t >= -0.05 * L and t <= 1.1 * L:
			keep.append(p)
	var cap: Dictionary = fit_cloud(keep if keep.size() >= 8 else pts, rpct, trim, 0.0)[0]
	if max_frac > 0.0 and float(cap["r"]) > max_frac * L:
		cap["r"] = max_frac * L
	return cap


## an end part or a hub (head, hand, foot, chest, hips): one capsule along the cloud's main axis, or, when the cloud is flat
## (its width more than `flat` x its thickness: the Bill Collector's paper body), a row of thin capsules side by side
static func fit_cloud(pts: PackedVector3Array, rpct: float, trim: float, flat: float) -> Array:
	var c := Vector3.ZERO
	for p in pts:
		c += p
	c /= float(pts.size())
	var m := _cov(pts, c)
	var a1 := _power(m)
	var a2 := _power(m, a1)
	var a3 := a1.cross(a2).normalized()
	var t1 := PackedFloat32Array()
	var t2 := PackedFloat32Array()
	var t3 := PackedFloat32Array()
	var ds := PackedFloat32Array()
	for p in pts:
		var d := p - c
		var u := d.dot(a1)
		t1.append(u)
		t2.append(d.dot(a2))
		t3.append(absf(d.dot(a3)))
		ds.append((d - a1 * u).length())
	t1.sort()
	t2.sort()
	t3.sort()
	ds.sort()
	var lo1 := _pct(t1, trim)
	var hi1 := _pct(t1, 1.0 - trim)
	var lo2 := _pct(t2, trim)
	var hi2 := _pct(t2, 1.0 - trim)
	var half3 := _pct(t3, rpct)
	if flat > 0.0 and half3 > 1e-5 and (hi2 - lo2) > flat * 2.0 * half3:
		var r := half3
		var k := clampi(roundi((hi2 - lo2) / (2.0 * r)), 2, 5)
		var out: Array = []
		for i in k:
			var o := lerpf(lo2 + r, hi2 - r, float(i) / float(k - 1))
			var a := c + a1 * (lo1 + r) + a2 * o
			var b := c + a1 * maxf(hi1 - r, lo1 + r) + a2 * o
			out.append({"a": a, "b": b, "r": r})
		return out
	var rr := _pct(ds, rpct)
	var lo := lo1 + rr
	var hi := hi1 - rr
	if lo > hi:
		lo = (lo + hi) * 0.5
		hi = lo
	return [{"a": c + a1 * lo, "b": c + a1 * hi, "r": rr}]


## a capsule {a, b, r} around a bone-space cloud (the main axis, no flat split)
static func fit_capsule(pts: PackedVector3Array, rpct: float, trim: float) -> Dictionary:
	return fit_cloud(pts, rpct, trim, 0.0)[0]


## the one child joint a limb runs to (bone space), or null when the bone ends a chain or branches (hands, feet, head, chest, hips)
static func only_child(skel: Skeleton3D, i: int, rules: Dictionary) -> Variant:
	var own: Array = []
	for c in skel.get_bone_children(i):
		var n := skel.get_bone_name(c)
		if owner_of(n, rules) == n:
			own.append(c)
	if own.size() != 1 or skel.get_bone_rest(own[0]).origin.length() < 1e-4:
		return null
	return skel.get_bone_rest(own[0]).origin


## the rank of a piece: lower ranks hold, higher ranks give way (rules.ranks maps a name prefix to a rank)
static func rank_of(bone: String, rules: Dictionary) -> int:
	return int(_by_prefix(bone, rules.get("ranks", {}), 9))


## a per-family value: the longest prefix of `bone` found in `table`
static func _by_prefix(bone: String, table: Dictionary, fallback: Variant) -> Variant:
	var best := ""
	for pre in table:
		if bone.begins_with(str(pre)) and str(pre).length() > best.length():
			best = str(pre)
	return table[best] if best != "" else fallback


## the family of a piece: its name without side, number and row index (handL -> hand, tail3 -> tail, head_2 -> head)
static func family(id: String) -> String:
	var s := id
	while s.length() > 0 and (s.right(1).is_valid_int() or s.right(1) in ["L", "R", "_"]):
		s = s.left(s.length() - 1)
	return s


## how deep two pieces may press like flesh before it counts (world metres): rules.soft["<family>|<family>"], names sorted
static func soft_of(a: String, b: String, rules: Dictionary) -> float:
	var fa := family(a)
	var fb := family(b)
	var k := "%s|%s" % [fa, fb] if fa <= fb else "%s|%s" % [fb, fa]
	return float((rules.get("soft", {}) as Dictionary).get(k, 0.0))


## the nearest ancestor bone that has a piece (pieces between two that have none count as one joint)
static func piece_parent(skel: Skeleton3D, bone: String, has_piece: Dictionary) -> String:
	var i := skel.get_bone_parent(skel.find_bone(bone))
	while i >= 0:
		var n := skel.get_bone_name(i)
		if has_piece.has(n):
			return n
		i = skel.get_bone_parent(i)
	return ""


## the whole wrap for a skinned model in its rest pose. rules.max_r caps a limb's radius at a share of its length (by name
## prefix); rules.flat = how many times wider than thick a cloud must be to become a row of capsules (0 = never)
static func fit(model: Node3D, skel: Skeleton3D, rules: Dictionary) -> Dictionary:
	var cl := clouds(model, skel, rules)
	var min_verts := int(rules.get("min_verts", 40))
	var rpct := float(rules.get("radius_pct", 0.8))
	var trim := float(rules.get("trim", 0.03))
	var pieces: Array = []
	var has_piece := {}
	for i in skel.get_bone_count():
		var n := skel.get_bone_name(i)
		if not cl.has(n) or (cl[n] as PackedVector3Array).size() < min_verts:
			continue
		var e: Variant = only_child(skel, i, rules)
		var caps: Array
		if e != null:
			caps = [fit_limb(cl[n], e, rpct, trim, float(_by_prefix(n, rules.get("max_r", {}), 0.0)))]
		else:
			caps = fit_cloud(cl[n], rpct, trim, float(rules.get("flat", 0.0)))
		for k in caps.size():
			pieces.append({"id": n if k == 0 else "%s_%d" % [n, k + 1], "bone": n, "a": caps[k]["a"], "b": caps[k]["b"],
				"r": caps[k]["r"], "rank": rank_of(n, rules), "verts": (cl[n] as PackedVector3Array).size()})
		has_piece[n] = true
	# neighbours at a joint never count (nor pieces of one bone); everything else is checked, minus what overlaps at rest
	var par := {}
	for p in pieces:
		par[p["id"]] = piece_parent(skel, str(p["bone"]), has_piece)
	var rest_world := {}
	for p in pieces:
		var g := skel.get_bone_global_rest(skel.find_bone(str(p["bone"])))
		rest_world[p["id"]] = [g * (p["a"] as Vector3), g * (p["b"] as Vector3)]
	var pairs: Array = []
	for i in pieces.size():
		for j in range(i + 1, pieces.size()):
			var a: Dictionary = pieces[i]
			var b: Dictionary = pieces[j]
			if a["bone"] == b["bone"] or par[a["id"]] == b["bone"] or par[b["id"]] == a["bone"]:
				continue
			var wa: Array = rest_world[a["id"]]
			var wb: Array = rest_world[b["id"]]
			var o := RmtCapsule.overlap(wa[0], wa[1], float(a["r"]), wb[0], wb[1], float(b["r"]))
			pairs.append([a["id"], b["id"], maxf(0.0, float(o["depth"])), soft_of(str(a["id"]), str(b["id"]), rules)])
	return {"version": 1, "kind": "collide", "pieces": pieces, "pairs": pairs, "rules": rules}


## JSON-ready copy (vectors as rounded arrays)
static func to_json(wrap: Dictionary) -> Dictionary:
	var out := wrap.duplicate(true)
	var ps: Array = []
	for p in wrap["pieces"]:
		var q: Dictionary = (p as Dictionary).duplicate()
		for k in ["a", "b"]:
			var v: Vector3 = p[k]
			q[k] = [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)]
		q["r"] = snappedf(float(p["r"]), 0.0001)
		ps.append(q)
	out["pieces"] = ps
	var prs: Array = []
	for pr in wrap["pairs"]:
		prs.append([pr[0], pr[1], snappedf(float(pr[2]), 0.0001), snappedf(float(pr[3]), 0.0001)])
	out["pairs"] = prs
	return out


## back from JSON (arrays -> vectors)
static func from_json(d: Dictionary) -> Dictionary:
	var out := d.duplicate(true)
	for p in out.get("pieces", []):
		for k in ["a", "b"]:
			var v: Array = p[k]
			p[k] = Vector3(float(v[0]), float(v[1]), float(v[2]))
	return out
