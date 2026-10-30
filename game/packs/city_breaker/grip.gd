class_name CBGrip
extends RefCounted
## Held objects sit in the hand the same way in the game and in Fight Studio: a frame built from the hand's own bones every
## frame (never a bone-attachment offset, which differs per model and put Vix's spray can through his wrist). Three kinds:
##   cylinder - can, bottle, bat / sword handle: inside the finger curl, the axis (Y) along the knuckle line pinky -> index
##   sphere   - ball, bomb, orb: cupped in front of the palm
##   block    - box, phone, card: flat on the palm, its long side (Y) along the fingers
## size = the object's extents in metres (cylinder x = diameter, y = length; sphere x = diameter; block x, y, z). Frame axes:
## Y = the object's axis, Z = out of the palm. Pair each kind with its hand pose: data/poses/grip_<kind>_<side>.json.
## Works on 3-finger (Vix) and 4-finger rigs (rig v4 finger bones).

const KINDS := ["cylinder", "sphere", "block"]


static func _bone(skel: Skeleton3D, name: String) -> Vector3:
	var i := skel.find_bone(name)
	if i < 0:
		return Vector3.INF
	return skel.global_transform * skel.get_bone_global_pose(i).origin


## the hand's own frame: wrist -> knuckles (along), pinky -> index (across), and which way the palm faces (palm)
static func hand_axes(skel: Skeleton3D, side: String) -> Dictionary:
	var hand := _bone(skel, "hand" + side)
	var fing := _bone(skel, "fingers" + side)
	var tips := _bone(skel, "tips" + side)
	var idx := _bone(skel, "index" + side)
	var pin := _bone(skel, "pinky" + side)
	if hand == Vector3.INF or fing == Vector3.INF:
		return {}
	var along := (fing - hand)
	var reach := along.length()
	along = along.normalized()
	var across := (idx - pin) if idx != Vector3.INF and pin != Vector3.INF else Vector3.ZERO
	across = across - along * across.dot(along)
	if across.length() < 0.002:
		across = along.cross(Vector3.UP)
	across = across.normalized()
	# the palm, from the hand's handedness (checked on Vix and Carter joints, loop 1): fingers forward + thumb side up ->
	# a right palm faces the body's midline = along x across; a left palm the other way. The fingertip curl is not used:
	# half-open poses gave it the wrong sign (the ball sat on the back of Carter's hand).
	var palm := along.cross(across) * (1.0 if side == "R" else -1.0)
	return {"hand": hand, "fing": fing, "tips": tips if tips != Vector3.INF else fing + along * reach * 0.6,
		"along": along, "across": across, "palm": palm.normalized(), "reach": reach}


## where a held object sits (world transform) for the current pose
static func frame(skel: Skeleton3D, side: String, kind: String, size: Vector3) -> Transform3D:
	var a := hand_axes(skel, side)
	if a.is_empty():
		return Transform3D.IDENTITY
	var along: Vector3 = a["along"]
	var across: Vector3 = a["across"]
	var palm: Vector3 = a["palm"]
	var hand: Vector3 = a["hand"]
	var fing: Vector3 = a["fing"]
	var tips: Vector3 = a["tips"]
	var y := along
	var center := fing
	# the bones run through the middle of the hand: everything sits out past the palm skin (about a fifth of the
	# wrist -> knuckle length, 2.4-2.5 cm on Vix and Carter), or a block vanishes into the palm (review loop 2)
	var pd := (a["reach"] as float) * 0.2
	match kind:
		"cylinder":   # in the tunnel the curled fingers make, under the knuckles
			y = across
			center = fing + palm * (size.x * 0.5 + pd * 0.6) - along * (a["reach"] as float) * 0.12
		"sphere":     # cupped: in front of the palm, between the wrist and the knuckles
			center = hand.lerp(fing, 0.55) + palm * (size.x * 0.5 + pd * 0.5)
		_:            # flat on the palm, the long side along the fingers
			center = hand.lerp(fing, 0.55) + palm * (size.z * 0.5 + pd)
	var z := palm - y * palm.dot(y)
	if z.length() < 0.001:
		z = y.cross(Vector3.RIGHT)
	z = z.normalized()
	var x := y.cross(z).normalized()
	return Transform3D(Basis(x, y, z), center)


## a grey proxy of a kind and size (for placement work in Fight Studio and test scenes)
static func proxy_mesh(kind: String, size: Vector3) -> Mesh:
	match kind:
		"cylinder":
			var c := CylinderMesh.new()
			c.top_radius = size.x * 0.5
			c.bottom_radius = size.x * 0.5
			c.height = size.y
			c.radial_segments = 20
			return c
		"sphere":
			var s := SphereMesh.new()
			s.radius = size.x * 0.5
			s.height = size.x
			return s
	var b := BoxMesh.new()
	b.size = size
	return b


# ---------------------------------------------------------------- the hand wraps what it holds

## the finger chains, knuckle out (%s = side); a chain the rig lacks (no ring on three-finger hands) is skipped
const WRAP_CHAINS := [["index%s", "index%s2", "index%s3"], ["fingers%s", "tips%s", "nail%s"], ["ring%s", "ring%s2", "ring%s3"],
	["pinky%s", "pinky%s2", "pinky%s3"], ["thumb%s", "thumb%s2"]]
const WRAP_STEP := 0.087       ## the search step (5 degrees), then halved down to about a third of a degree
const WRAP_GAP := 0.002        ## metres of air the solve leaves between skin and object
static var _flim: Dictionary = {}


## THE HAND WRAPS THE OBJECT (2026-10-30, the user: "put collision wrap on the prop objects so the hand wraps around
## naturally"). The held object is its collision shape (kind + size, the same as frame(): cylinder, sphere, block); each
## finger joint is a capsule as thick as the model's own finger skin (data/finger_frames.json "thickness"). Knuckle out, each
## joint turns about its curl axis (the shared hand turned onto this fighter's, as CBClipLib plays it) until the finger's
## skin meets the object: closing when it hangs off, opening when it sinks in, never past animator_rig.json finger_limits.
## It starts from the pose on the skeleton (the clip's hand), so a clip still says how the hand holds; the wrap makes it
## touch. prop = the object's world transform (Y = its axis, Z = out of the palm). Returns how many joints it turned.
static func wrap_hand(skel: Skeleton3D, side: String, kind: String, size: Vector3, prop: Transform3D) -> int:
	var fmap := CBClipLib.finger_map(skel)
	if fmap.is_empty():
		return 0
	var fd := CBClipLib.finger_data()
	var thick: Dictionary = (fd.get("thickness", {}) as Dictionary).get(CBClipLib.fighter_key(skel), {})
	var shared: Dictionary = fd.get("shared", {})
	var sg := skel.global_transform
	var sc := sg.basis.get_scale().x
	var inv := prop.affine_inverse()
	var turned := 0
	for ch: Array in WRAP_CHAINS:
		var names: Array = ch.map(func(x: String) -> String: return x % side)
		var ids: Array = names.map(func(n: String) -> int: return skel.find_bone(n))
		if ids.has(-1) or not shared.has(names[0]):
			continue
		var n := ids.size()
		var locals: Array = []
		var axes: Array = []
		var radii: Array = []
		for k in n:
			locals.append(skel.get_bone_pose(ids[k]))
			var m: Basis = fmap.get(names[k], Basis.IDENTITY)
			var c: Array = (shared[names[k]] as Dictionary)["c"]
			axes.append((m * Vector3(c[0], c[1], c[2])).normalized())
			radii.append(float((thick.get(names[k], {}) as Dictionary).get("r", 0.012)) * sc)
		# the fingertip past the last joint: along the last segment, as long as the skin reaches
		var last_rest := skel.get_bone_rest(ids[n - 1]).origin
		var tip_len := float((thick.get(names[n - 1], {}) as Dictionary).get("len", last_rest.length() * 0.8))
		var tip := last_rest.normalized() * tip_len
		var base := skel.get_bone_global_pose(skel.get_bone_parent(ids[0]))
		for k in n:
			var cur := _curl_of(skel, fmap, names[k], ids[k], locals[k], shared)
			var lim: Array = (_finger_limits().get(str((shared[names[k]] as Dictionary)["kind"]), {}) as Dictionary).get("curl", [-20, 100])
			var lo := deg_to_rad(float(lim[0])) - cur
			var hi := deg_to_rad(float(lim[1])) - cur
			if k == 0 and str(names[0]).begins_with("thumb"):
				# the thumb does not curl round an object, it swings over to meet it from the other side: turn it straight
				# toward the object's middle, as far as all three of its ranges allow
				var joint := (base * (locals[0] as Transform3D)).origin
				var g := base
				for j in n:
					g = g * (locals[j] as Transform3D)
				var reach := g * tip - joint
				var to := sg.affine_inverse() * prop.origin - joint
				var ax := reach.cross(to)
				if ax.length() > 1e-6:
					axes[0] = (base.basis.orthonormalized().inverse() * ax).normalized()
					lo = -0.35
					hi = 0.0
					while hi < 1.4 and _thumb_ok(skel, fmap, names[0], ids[0], locals[0], axes[0], hi + WRAP_STEP, shared):
						hi += WRAP_STEP
			var touch := func(ang: float) -> bool:
				return _chain_touches(skel, ids, locals, axes, radii, tip, base, k, ang, sg, inv, kind, size)
			var a := 0.0
			if touch.call(0.0):   # sunk in: open until clear
				var b := 0.0
				while b > lo and touch.call(b):
					b = maxf(b - WRAP_STEP, lo)
				a = _bisect(touch, b, minf(b + WRAP_STEP, 0.0)) if not touch.call(b) else b
			else:                 # hanging off: close until it touches
				var b := 0.0
				while b < hi and not touch.call(b):
					b = minf(b + WRAP_STEP, hi)
				a = _bisect(touch, maxf(b - WRAP_STEP, 0.0), b) if touch.call(b) else b
			if absf(a) > 0.001:
				var l0: Transform3D = locals[k]
				locals[k] = Transform3D(Basis(axes[k], a) * l0.basis, l0.origin)
				skel.set_bone_pose_rotation(ids[k], (locals[k] as Transform3D).basis.get_rotation_quaternion())
				turned += 1
			base = base * (locals[k] as Transform3D)
	if turned > 0:
		skel.force_update_all_bone_transforms()
	return turned


## is the thumb's knuckle, turned by a about axis, still inside all three thumb ranges (curl, spread, twist)?
static func _thumb_ok(skel: Skeleton3D, fmap: Dictionary, name: String, id: int, local: Transform3D, axis: Vector3, a: float,
		shared: Dictionary) -> bool:
	var l := Basis(axis, a) * local.basis
	var r := CBClipLib.clip_basis(fmap, name, skel.get_bone_rest(id).basis.orthonormalized().inverse() * l.orthonormalized())
	var q := r.get_rotation_quaternion()
	if q.w < 0.0:
		q = -q
	var ang := q.get_angle()
	var rv := q.get_axis() * ang if ang > 1e-6 else Vector3.ZERO
	var fr: Dictionary = shared[name]
	var lim: Dictionary = _finger_limits().get(str(fr["kind"]), {})
	var i := 0
	for ax: String in ["c", "s", "t"]:
		var v: Array = fr[ax]
		var rng: Array = lim.get(["curl", "spread", "twist"][i], [-180, 180])
		var deg := rad_to_deg(rv.dot(Vector3(v[0], v[1], v[2])))
		if deg < float(rng[0]) or deg > float(rng[1]):
			return false
		i += 1
	return true


## the last clear angle between a clear one and a touching one
static func _bisect(touch: Callable, clear: float, hit: float) -> float:
	for i in 4:
		var mid := (clear + hit) * 0.5
		if touch.call(mid):
			hit = mid
		else:
			clear = mid
	return clear


## does the finger from joint k out touch the object with joint k turned by a (the joints before k as they are)?
static func _chain_touches(skel: Skeleton3D, ids: Array, locals: Array, axes: Array, radii: Array, tip: Vector3,
		base: Transform3D, k: int, a: float, sg: Transform3D, inv: Transform3D, kind: String, size: Vector3) -> bool:
	var g := base
	for j in range(k, ids.size()):
		var l: Transform3D = locals[j]
		if j == k:
			l = Transform3D(Basis(axes[j], a) * l.basis, l.origin)
		g = g * l
		var end: Vector3 = g * (skel.get_bone_rest(ids[j + 1]).origin if j + 1 < ids.size() else tip)
		var r: float = radii[j]
		var ts: Array = [0.34, 0.67, 1.0] if j == k else [0.0, 0.34, 0.67, 1.0]   # the pivot itself never moves
		for t: float in ts:
			var p := inv * (sg * g.origin.lerp(end, t))
			if _sdf(kind, size, p) < r + WRAP_GAP:
				return true
	return false


## how far a finger joint curls now (radians, + into the palm), from the skeleton's pose back on the shared hand
static func _curl_of(skel: Skeleton3D, fmap: Dictionary, name: String, id: int, local: Transform3D, shared: Dictionary) -> float:
	var r := CBClipLib.clip_basis(fmap, name, skel.get_bone_rest(id).basis.orthonormalized().inverse() * local.basis.orthonormalized())
	var q := r.get_rotation_quaternion()
	if q.w < 0.0:
		q = -q
	var ang := q.get_angle()
	if ang < 1e-6:
		return 0.0
	var c: Array = (shared[name] as Dictionary)["c"]
	return (q.get_axis() * ang).dot(Vector3(c[0], c[1], c[2]))


## signed distance from a point (in the object's frame) to the object's surface
static func _sdf(kind: String, size: Vector3, p: Vector3) -> float:
	match kind:
		"cylinder":
			var d := Vector2(Vector2(p.x, p.z).length() - size.x * 0.5, absf(p.y) - size.y * 0.5)
			return minf(maxf(d.x, d.y), 0.0) + Vector2(maxf(d.x, 0.0), maxf(d.y, 0.0)).length()
		"sphere":
			return p.length() - size.x * 0.5
	var q := p.abs() - size * 0.5
	return Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0)).length() + minf(maxf(q.x, maxf(q.y, q.z)), 0.0)


static func _finger_limits() -> Dictionary:
	if _flim.is_empty():
		var p: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://game/packs/city_breaker/data/animator_rig.json"))
		_flim = (p as Dictionary).get("finger_limits", {"none": {}}) if p is Dictionary else {"none": {}}
	return _flim


## something in a fighter's hand ({side, kind, size, node?}: the fighter's "held" meta): to its grip frame, fingers wrapped
static func hold(skel: Skeleton3D, held: Dictionary) -> Transform3D:
	var side := str(held.get("side", "R"))
	var kind := str(held.get("kind", "cylinder"))
	var size: Vector3 = held.get("size", Vector3(0.1, 0.2, 0.1))
	var t := frame(skel, side, kind, size)
	var nd: Variant = held.get("node")
	if nd is Node3D and is_instance_valid(nd):
		(nd as Node3D).global_transform = t
	wrap_hand(skel, side, kind, size, t)
	return t
