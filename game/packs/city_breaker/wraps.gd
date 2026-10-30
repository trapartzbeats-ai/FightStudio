class_name CBWraps
extends RefCounted
## City Breaker's side of RMT Wrap (WRAPS_PLAN.md): each fighter's Collision Wrap (data/wraps/<key>.collide.json) and the Body
## Solve that keeps its body parts out of its own body and out of the floor (addons/rmt_wraps). Visual only: hits and hurt
## checks read the clip's own pose (CBAnim.hit_world), so the fight plays exactly as before.

const WRAPS := "res://game/packs/city_breaker/data/wraps/%s.collide.json"
const RULES := "res://game/packs/city_breaker/data/wraps/wrap_rules.json"
const RIG := "res://game/packs/city_breaker/data/animator_rig.json"

static var enabled := not ("--no-wraps" in OS.get_cmdline_user_args())   ## the Body Solve in matches (--no-wraps: clips as keyed)
static var world_on := not ("--no-wrap-world" in OS.get_cmdline_user_args())     ## limbs stay out of the stage's solid decks (C3)
static var others_on := not ("--no-wrap-others" in OS.get_cmdline_user_args())   ## limbs stay out of the other fighters' bodies (C3)
static var _json := {}


static func _load(path: String) -> Dictionary:
	if not _json.has(path):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		_json[path] = d if d is Dictionary else {}
	return _json[path]


## the Body Solve for a fighter on its skeleton, or null when it has no wrap; `lift` is raised when the body is under the floor
static func make_solver(skel: Skeleton3D, key: String, lift: Node3D) -> RmtBodySolve:
	var wrap := _load(WRAPS % key)
	if wrap.is_empty():
		return null
	var body := RmtWrapBody.new(RmtWrapFit.from_json(wrap), skel)
	var rules := _load(RULES)
	var over: Dictionary = (rules.get("fighters", {}) as Dictionary).get(key, {})
	var chain: Dictionary = (rules.get("chain", {}) as Dictionary).duplicate()
	chain.merge(over.get("chain", {}), true)
	var turn: Dictionary = (rules.get("max_turn", {}) as Dictionary).duplicate()
	turn.merge(over.get("max_turn", {}), true)
	var rig := _load(RIG)
	var s := RmtBodySolve.new(body, chain, rig.get("limits", {}), turn, rig.get("hinge", []))
	s.lift_node = lift
	return s


## the fighter key of a skeleton from its model file (assets/chars/<key>_fight.glb), "" when it is not a City Breaker fighter
static func key_of(skel: Skeleton3D) -> String:
	var n: Node = skel
	while n != null:
		var f := n.scene_file_path
		if f.ends_with("_fight.glb"):
			return f.get_file().trim_suffix("_fight.glb")
		n = n.get_parent()
	return ""


## Spring chains (CBSecondary: tails, ears, crests...) bounce off the body instead of swinging through it: the chain's joints
## get the radius of their own wrap pieces, and the simulator gets the fighter's other wrap capsules as colliders (not the
## neighbour at the chain's root joint), each shrunk by how far the chain already sits in it at rest. Returns how many colliders.
static func spring_colliders(sim: SpringBoneSimulator3D, skel: Skeleton3D, key: String, root: String, end: String) -> int:
	if key == "":
		key = key_of(skel)
	var wrap := _load(WRAPS % key)
	if wrap.is_empty():
		return 0
	var fams: Array = (_load(RULES).get("spring_collide", ["tail", "ear", "crest", "pom", "fin"]) as Array)
	if not RmtWrapFit.family(root) in fams:
		return 0
	# the chain's bones, root to end
	var chain := {}
	var b := skel.find_bone(end)
	var r := skel.find_bone(root)
	while b >= 0:
		chain[skel.get_bone_name(b)] = true
		if b == r:
			break
		b = skel.get_bone_parent(b)
	var pieces: Array = RmtWrapFit.from_json(wrap)["pieces"]
	var mine: Array = []
	for p in pieces:
		if chain.has(str(p["bone"])):
			mine.append(str(p["id"]))
	# which pieces the chain may hit (listed as a pair with any chain piece: not the neighbour of every piece; the head counts
	# for an ear even though it holds the ear's root), and how much
	# of each it already sits in at rest (the smallest overlap of any chain piece): that collider is shrunk by it, so the chain
	# just touches it at rest and a swing any deeper is pushed back out (a tail beside a thigh, an ear on the head)
	var hits := {}     # piece id -> [pairs with chain pieces, largest rest overlap]
	for pr in wrap.get("pairs", []):
		var a := str(pr[0])
		var c := str(pr[1])
		var other := ""
		if a in mine and not c in mine:
			other = c
		elif c in mine and not a in mine:
			other = a
		if other == "":
			continue
		var h: Array = hits.get(other, [0, 0.0])
		var al := float(pr[2])
		# the smallest resting overlap counts: every other chain joint is stopped from going deeper than it does now
		hits[other] = [int(h[0]) + 1, al if al > 0.0 and (float(h[1]) == 0.0 or al < float(h[1])) else float(h[1])]
	# joint radius = the chain's own thickness
	var radius := {}
	for p in pieces:
		if chain.has(str(p["bone"])):
			radius[str(p["bone"])] = maxf(float(radius.get(str(p["bone"]), 0.0)), float(p["r"]))
	var thin := 0.0
	for k in radius:
		thin = float(radius[k]) if thin == 0.0 else minf(thin, float(radius[k]))
	for j in sim.get_joint_count(0):
		var jb := sim.get_joint_bone_name(0, j)
		sim.set_joint_radius(0, j, float(radius.get(jb, thin)))
	var n := 0
	for p in pieces:
		var id := str(p["id"])
		if mine.is_empty() or not hits.has(id) or id in mine:
			continue
		var a3: Vector3 = p["a"]
		var b3: Vector3 = p["b"]
		var col := SpringBoneCollisionCapsule3D.new()
		col.name = "wrap_" + id
		col.bone_name = str(p["bone"])
		col.radius = maxf(float(p["r"]) - float(hits[id][1]), float(p["r"]) * 0.3)
		col.mid_height = a3.distance_to(b3)
		col.position_offset = (a3 + b3) * 0.5
		var axis := (b3 - a3).normalized() if a3.distance_to(b3) > 1e-5 else Vector3.UP
		col.rotation_offset = Quaternion(Vector3.UP, axis)
		sim.add_child(col)
		n += 1
	sim.set_enable_all_child_collisions(0, true)
	return n


## After the spring chains: a Body Solve that moves only the chains (tails, ears, crests...) and runs as the last skeleton
## modifier, so whatever the springs still swing into the body is pushed back out on the pose you see. Returns the modifier.
static func spring_guard(skel: Skeleton3D, key: String, sims: Dictionary) -> RmtWrapModifier:
	if key == "":
		key = key_of(skel)
	var s := make_solver(skel, key, null)
	if s == null:
		return null
	var fams: Array = (_load(RULES).get("spring_collide", ["tail", "ear", "crest", "pom", "fin"]) as Array)
	var chain_bones := {}
	for name in sims:
		var sim: SpringBoneSimulator3D = sims[name]
		if not RmtWrapFit.family(sim.get_root_bone_name(0)) in fams:
			continue
		for j in sim.get_joint_count(0):
			chain_bones[sim.get_joint_bone_name(0, j)] = true
	for i in s.body.pieces.size():
		if chain_bones.has(skel.get_bone_name(int(s.body.pieces[i]["bone_idx"]))):
			s.movers[i] = true
	if s.movers.is_empty():
		return null
	s.keep = 0.0          # the springs carry the motion from frame to frame; this only corrects what they produce
	s.max_step = PI
	var m := RmtWrapModifier.new()
	m.name = "wrap_guard"
	m.solver = s
	skel.add_child(m)    # after the spring simulators: modifiers run in child order
	return m


## the other fighters' bodies this fighter's limbs stay out of: their wraps where they ended up (a grab partner is left out:
## holding someone means touching them)
static func others_for(f: CBFighter) -> Array:
	var out: Array = []
	var m := f.match_ref
	if m == null or not ("fighters" in m):
		return out
	for o in m.fighters:
		var of := o as CBFighter
		if of == f or of == null or not of.alive or of.anim == null:
			continue
		if not of.is_visible_in_tree():   # hidden (an ultimate's cut keeps them parked off-camera): nothing to bump into
			continue
		if f.catch_target == of or of.catch_target == f:
			continue
		out.append_array(of.anim.wrap_caps)
	return out
