extends SceneTree
## Checks for RMT Wrap (capsule math, the fit, the Body Solve) on real fighters and clips:
##   godot --headless --path . --script res://game/packs/city_breaker/tools/wrap_check.gd
## Exits non-zero on a failure.

var _n := 0
var _fails := 0


func ok(cond: bool, what: String) -> void:
	_n += 1
	if not cond:
		_fails += 1
		print("FAIL: ", what)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_math()
	_fit()
	await _solve()
	await _springs()
	await _world_and_others()
	await _shift_keeps_rotation()
	print("WRAP CHECK: %d passed, %d failed" % [_n - _fails, _fails])
	quit(1 if _fails > 0 else 0)


func _math() -> void:
	# crossing segments: closest points meet in the middle
	var c := RmtCapsule.seg_closest(Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(0, -1, 1), Vector3(0, 1, 1))
	ok((c[2] as Vector3).is_equal_approx(Vector3.ZERO) and (c[3] as Vector3).is_equal_approx(Vector3(0, 0, 1)), "crossing segments: closest points")
	# parallel capsules 0.3 apart with radii 0.2 + 0.2 overlap by 0.1, pushed apart along the gap
	var o := RmtCapsule.overlap(Vector3(0, 0, 0), Vector3(0, 1, 0), 0.2, Vector3(0.3, 0, 0), Vector3(0.3, 1, 0), 0.2)
	ok(absf(float(o["depth"]) - 0.1) < 1e-5 and (o["normal"] as Vector3).is_equal_approx(Vector3(-1, 0, 0)), "parallel capsules: depth and normal")
	ok(float(RmtCapsule.overlap(Vector3.ZERO, Vector3.UP, 0.1, Vector3(1, 0, 0), Vector3(1, 1, 0), 0.1)["depth"]) < 0.0, "apart capsules don't overlap")
	ok(absf(RmtCapsule.bottom(Vector3(0, 1, 0), Vector3(0, 0.5, 0), 0.2) - 0.3) < 1e-6, "capsule bottom")
	ok(RmtWrapFit.family("handL_2") == "hand" and RmtWrapFit.family("tail3") == "tail" and RmtWrapFit.family("earR2") == "ear", "piece families")
	ok(RmtWrapFit.owner_of("indexL2", {"merge": {"index": "hand"}}) == "handL" and RmtWrapFit.owner_of("head", {"merge": {"index": "hand"}}) == "head", "finger bones count for the hand")


func _fit() -> void:
	# a cylinder of points, radius 0.1, 1 m long along Y: one capsule on the axis, radius just inside 0.1
	var pts := PackedVector3Array()
	for i in 400:
		var a := float(i) * 0.37
		pts.append(Vector3(cos(a) * 0.1, float(i % 100) / 100.0, sin(a) * 0.1))
	var cap := RmtWrapFit.fit_capsule(pts, 0.8, 0.03)
	ok(absf(float(cap["r"]) - 0.1) < 0.005, "cylinder: radius %.4f" % float(cap["r"]))
	ok(absf(((cap["b"] as Vector3) - (cap["a"] as Vector3)).normalized().dot(Vector3.UP)) > 0.99, "cylinder: axis along it")
	# a flat sheet becomes a row of thin capsules
	var sheet := PackedVector3Array()
	for i in 30:
		for j in 30:
			sheet.append(Vector3(float(i) / 29.0 * 0.6, float(j) / 29.0, 0.02 * (1.0 if (i + j) % 2 == 0 else -1.0)))
	var row := RmtWrapFit.fit_cloud(sheet, 0.8, 0.03, 2.5)
	ok(row.size() >= 2 and float(row[0]["r"]) < 0.05, "flat sheet: %d thin capsules" % row.size())
	# every fighter has a wrap with a head, two hands and two feet
	for key in CBRoster.keys():
		var w := RmtWrapBody.load_wrap(CBWraps.WRAPS % key)
		var ids := {}
		for p in w.get("pieces", []):
			ids[RmtWrapFit.family(str(p["id"])) + ("L" if str(p["bone"]).ends_with("L") else "R" if str(p["bone"]).ends_with("R") else "")] = true
		ok(ids.has("head") and ids.has("handL") and ids.has("handR") and ids.has("footL") and ids.has("footR"), "%s wrap has head, hands, feet" % key)


func _rot(fp: CBWrapPose) -> Array:
	var out: Array = []
	for i in fp.skel.get_bone_count():
		out.append(fp.skel.get_bone_pose_rotation(i))
	return out


func _worst(fp: CBWrapPose, planted: bool) -> float:
	var cl := fp.clashes(0.0, planted)
	var w := 0.0
	for x in cl["self"] + cl["floor"]:
		w = maxf(w, float(x["excess"]))
	return w


func _solve() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	# a fist in the face (Carter's air dodge, frame 57): the solve takes it out
	var fp := CBWrapPose.new("carter", holder)
	var c := CBClipLib.load_clip("a_carter_air_dodge_f")
	var before := _worst(fp, fp.pose(c, 57.0))
	fp.solver.reset()
	for f in range(40, 58):
		fp.pose(c, float(f), true)
	var after := _worst(fp, false)
	ok(before > 0.1 and after < before * 0.3, "fist in the face: %.1f cm -> %.1f cm" % [before * 100.0, after * 100.0])
	# the same frames again give the same pose (deterministic)
	var r1 := _rot(fp)
	fp.solver.reset()
	for f in range(40, 58):
		fp.pose(c, float(f), true)
	var r2 := _rot(fp)
	var same := true
	for i in r1.size():
		if not (r1[i] as Quaternion).is_equal_approx(r2[i]):
			same = false
	ok(same, "the solve is deterministic")
	# knees never bend forward, elbows stay in their range, wrists stay inside theirs (or where the clip already had them)
	var rig: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CBWraps.RIG))
	var lim: Dictionary = rig["limits"]
	var worst_out := 0.0
	var where := ""
	for clip_name in ["a_carter_air_dodge_f", "a_carter_dair", "a_wait", "a_carter_fsmash"]:
		var cc := CBClipLib.load_clip(clip_name)
		if cc.is_empty():
			continue
		fp.solver.reset()
		for f in int(cc.get("frames", 0)) + 1:
			# the pose right before the solve (the clip, plus the game's flat feet): the solve may never go further out
			fp.pose(cc, float(f))
			var pre := {}
			for b in ["kneeL", "kneeR", "elbowL", "elbowR", "handL", "handR", "footL", "footR"]:
				var bi0 := fp.skel.find_bone(b)
				pre[b] = (fp.skel.get_bone_rest(bi0).basis.orthonormalized().inverse() * Basis(fp.skel.get_bone_pose_rotation(bi0))).get_euler(EULER_ORDER_ZYX)
			fp.pose(cc, float(f), true)
			for b in ["kneeL", "kneeR", "elbowL", "elbowR", "handL", "handR", "footL", "footR"]:
				var bi := fp.skel.find_bone(b)
				var rest := fp.skel.get_bone_rest(bi).basis.orthonormalized()
				var e := (rest.inverse() * Basis(fp.skel.get_bone_pose_rotation(bi))).get_euler(EULER_ORDER_ZYX)
				var ce: Vector3 = pre[b]
				for ai in 3:
					var ax: String = ["x", "y", "z"][ai]
					if (lim[b] as Dictionary).has(ax):
						var r: Array = lim[b][ax]
						var lo := minf(float(r[0]), ce[ai])
						var hi := maxf(float(r[1]), ce[ai])
						var out := maxf(lo - e[ai], e[ai] - hi)
						if out > worst_out:
							worst_out = out
							where = "%s %s %s f%d" % [clip_name, b, ax, f]
	ok(worst_out < 0.02, "joints stay in their natural range (worst %.3f rad %s)" % [worst_out, where])
	# a planted foot stays where the clip put it
	var w := CBClipLib.load_clip("a_wait")
	fp.solver.reset()
	var planted := fp.pose(w, 20.0)
	var foot := fp.skel.find_bone("footL")
	var p0 := (fp.skel.global_transform * fp.skel.get_bone_global_pose(foot)).origin
	fp.pose(w, 20.0, true)
	var p1 := (fp.skel.global_transform * fp.skel.get_bone_global_pose(foot)).origin
	ok(planted and p0.distance_to(p1) < 0.002, "a planted foot stays put (moved %.1f mm)" % (p0.distance_to(p1) * 1000.0))
	fp.model.queue_free()
	await process_frame
	# Kat's back throw: her head never goes under the floor (the body is lifted)
	var kp := CBWrapPose.new("kat", holder)
	var kc := CBClipLib.load_clip("a_kat_bthrow")
	kp.solver.reset()
	var deepest := 0.0
	for f in int(kc.get("frames", 0)) + 1:
		kp.pose(kc, float(f), true)
		var caps := kp.body.capsules()
		for i in kp.body.pieces.size():
			if int(kp.body.pieces[i]["rank"]) <= 2:
				var cp: Array = caps[i]
				deepest = maxf(deepest, -RmtCapsule.bottom(cp[0], cp[1], cp[2]))
	ok(deepest < 0.01, "Kat's back throw: body above the floor (deepest %.1f cm)" % (deepest * 100.0))
	kp.model.queue_free()
	await process_frame


var _spring_worst := 0.0
var _spring_fp: CBWrapPose
var _spring_chain := {}


func _springs() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	# Al's tail: the spring chain gets the body's capsules (the legs among them) and the after-springs pass runs last
	var fp := CBWrapPose.new("al", holder)
	var sims := CBSecondary.build_specs(fp.skel, CBSecondary.all_specs("al"), "al", true)
	var tail: SpringBoneSimulator3D = sims.get("tail")
	var names: Array = []
	if tail != null:
		for c in tail.get_children():
			names.append(str(c.name))
	ok("wrap_legR" in names and "wrap_kneeL" in names, "Al's tail collides with the legs (%d colliders)" % names.size())
	var last: Node = fp.skel.get_child(fp.skel.get_child_count() - 1)
	ok(last is RmtWrapModifier, "the after-springs pass is the last skeleton modifier")
	ok(tail != null and absf(tail.get_joint_radius(0, 2) - 0.175) < 0.01, "tail joints are as thick as the tail")
	# Carter's ears: the head counts (it holds the ear's root, but the rest of the ear may hit it)
	var cp := CBWrapPose.new("carter", holder)
	var cs := CBSecondary.build_specs(cp.skel, CBSecondary.all_specs("carter"), "carter", true)
	var ear: SpringBoneSimulator3D = cs.get("ear_L")
	ok(ear != null and ear.has_node("wrap_head"), "Carter's ears collide with his head")
	cp.model.queue_free()
	# Al rolls: with the springs swinging, no chain piece goes 2 cm into the body (it went 24.6 cm with free springs)
	_spring_fp = fp
	for i in fp.body.pieces.size():
		if str(fp.body.pieces[i]["id"]).begins_with("tail"):
			_spring_chain[i] = true
	fp.skel.skeleton_updated.connect(_spring_measure)
	var c := CBAnim.clip(CBAnim.own("al", "a_escape_f"))
	CBSecondary.reset(fp.skel)
	for f in int(c.get("frames", 0)) + 1:
		fp.pose(c, float(f), true)
		fp.skel.set_bone_pose_rotation(0, fp.skel.get_bone_pose_rotation(0))
		await process_frame
	ok(_spring_worst < 0.02, "Al's roll with springs: tail stays out of the body (worst %.1f cm)" % (_spring_worst * 100.0))
	fp.model.queue_free()
	await process_frame


func _spring_measure() -> void:
	for x in _spring_fp.body.clashes(0.0):
		if _spring_chain.has(x["i"]) != _spring_chain.has(x["j"]):
			_spring_worst = maxf(_spring_worst, float(x["excess"]))


func _box_at(parent: Node, at: Vector3, size: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	b.add_child(cs)
	parent.add_child(b)
	b.global_position = at
	return b


func _in_box(fp: CBWrapPose, id: String) -> float:
	var i: int = fp.body.index[id]
	var cp: Array = fp.body.capsules()[i]
	var cs := CapsuleShape3D.new()
	cs.radius = float(cp[2])
	cs.height = (cp[0] as Vector3).distance_to(cp[1]) + 2.0 * float(cp[2])
	var y := ((cp[1] as Vector3) - (cp[0] as Vector3)).normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cs
	q.transform = Transform3D(Basis(x, y, x.cross(y)), ((cp[0] as Vector3) + (cp[1] as Vector3)) * 0.5)
	q.collision_mask = 1
	var res := root.get_world_3d().direct_space_state.collide_shape(q, 4)
	var d := 0.0
	for k in res.size() / 2:
		d = maxf(d, ((res[k * 2 + 1] as Vector3) - (res[k * 2] as Vector3)).length())
	return d


func _world_and_others() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var fp := CBWrapPose.new("carter", holder)
	var rest := CBClipLib.load_clip("a_wait")
	# a box where the right fist is: the solve bends the arm out of it
	fp.pose(rest, 0.0)
	var hand := fp.body.capsules()[fp.body.index["handR"]] as Array
	var box := _box_at(holder, ((hand[0] as Vector3) + (hand[1] as Vector3)) * 0.5 + Vector3(0.12, 0, 0), Vector3(0.2, 0.6, 0.6))
	await physics_frame
	await physics_frame
	var before := _in_box(fp, "handR")
	fp.solver.reset()
	fp.solver.world = root.get_world_3d().direct_space_state
	for _k in 6:
		fp.pose(rest, 0.0, true)
	var after := _in_box(fp, "handR")
	ok(before > 0.05 and after < 0.02, "a fist in a wall comes out of it: %.1f cm -> %.1f cm" % [before * 100.0, after * 100.0])
	box.queue_free()
	await physics_frame
	await physics_frame
	# a head in a box: the head can't bend that far, the whole model shifts out, and back once the box is gone
	fp.pose(rest, 0.0)
	var head := fp.body.capsules()[fp.body.index["head"]] as Array
	var hb := _box_at(holder, ((head[0] as Vector3) + (head[1] as Vector3)) * 0.5 + Vector3(0.0, 0.0, 0.25), Vector3(1.0, 1.0, 0.3))
	await physics_frame
	await physics_frame
	fp.solver.reset()
	var hbefore := 0.0
	fp.pose(rest, 0.0)
	hbefore = _in_box(fp, "head")
	for _k in 4:
		fp.pose(rest, 0.0, true)
	var hafter := _in_box(fp, "head")
	var shifted := fp.solver._nudge.length()
	ok(hbefore > 0.05 and hafter < 0.02 and shifted > 0.03, "a head in a wall: the model shifts out (%.1f cm -> %.1f cm, moved %.0f cm)" % [hbefore * 100.0, hafter * 100.0, shifted * 100.0])
	hb.queue_free()
	await physics_frame
	await physics_frame
	for _k in 40:
		fp.pose(rest, 0.0, true)
	ok(fp.solver._nudge.length() < 0.005, "and it eases back when the wall is gone (%.1f cm left)" % (fp.solver._nudge.length() * 100.0))
	fp.solver.world = null
	# another fighter's chest where the fist is: the fist stops at its surface
	var other := CBWrapPose.new("bigbill", holder)
	other.pose(rest, 0.0)
	fp.pose(rest, 0.0)
	var fist := fp.body.capsules()[fp.body.index["handR"]] as Array
	var chest_i: int = other.body.index["chest"]
	var oc := other.body.capsules()[chest_i] as Array
	other.model.global_position += ((fist[0] as Vector3) + (fist[1] as Vector3)) * 0.5 - ((oc[0] as Vector3) + (oc[1] as Vector3)) * 0.5
	other.skel.force_update_all_bone_transforms()
	var others := other.body.capsules()
	var depth := func() -> float:
		var cp: Array = fp.body.capsules()[fp.body.index["handR"]]
		var w := 0.0
		for o in others:
			w = maxf(w, float(RmtCapsule.overlap(cp[0], cp[1], cp[2], o[0], o[1], o[2])["depth"]))
		return w
	var obefore: float = depth.call()
	fp.solver.reset()
	fp.solver.others = others
	for _k in 8:
		fp.pose(rest, 0.0, true)
	var oafter: float = depth.call()
	ok(obefore > 0.05 and oafter < 0.03, "a fist in another fighter stops at the body: %.1f cm -> %.1f cm" % [obefore * 100.0, oafter * 100.0])
	holder.queue_free()
	await process_frame


## the solver moves the model through its local position: on a model pitched past 90 degrees (a thrown fighter) setting
## global_position re-read its rotation as a flipped twin, which then stuck and turned the fighter (and its hurt checks) upside
## down; the rotation must come through a shift exactly as it was
func _shift_keeps_rotation() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var fp := CBWrapPose.new("vix", holder)
	fp.model.rotation = Vector3(2.5, 1.26, 0.0)
	fp.solver._shift(Vector3(0.0, -0.2, 0.1))
	fp.model.rotation.x = 2.6   # what CBAnim does the next frame
	ok(absf(fp.model.rotation.z) < 0.001 and absf(fp.model.rotation.y - 1.26) < 0.001 and absf(fp.model.position.y + 0.2) < 0.001,
		"shifting a pitched model keeps its rotation (rot %s)" % str(fp.model.rotation))
	holder.queue_free()
	await process_frame
