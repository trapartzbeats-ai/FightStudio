extends SceneTree
## Headless checks for the Fight Studio Animator (no window needed):
##   godot --headless --path . --script res://game/packs/city_breaker/animator/tests/animator_check.gd
## Works on a scratch clip that is never saved over a real one (saves go to a temp name and are trashed after).

var app: FSAApp
var fails := 0
var passes := 0


func ok(cond: bool, what: String) -> void:
	if cond:
		passes += 1
	else:
		fails += 1
		print("FAIL ", what)


func near(a: float, b: float, tol: float = 1e-3) -> bool:
	return absf(a - b) <= tol


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var ps := load("res://game/packs/city_breaker/animator/animator.tscn") as PackedScene
	app = ps.instantiate() as FSAApp
	root.add_child(app)
	for i in 5:
		await process_frame
	ok(app.doc != null and app.doc.name == "w_walk", "opens w_walk at start")
	ok(not app.autokey, "auto key is off at start")
	ok(not app.history.dirty(), "nothing changed at start (got: %s)" % str(app.history.labels(5)))
	_euler()
	_doc_ops()
	_propagate()
	_layers()
	_constraints()
	_pose_tools()
	_save_roundtrip()
	_merge()
	_adjust()
	_feet()
	await _api()
	print("ANIMATOR CHECK: %d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)


func _euler() -> void:
	for e in [Vector3(0.3, -0.7, 1.1), Vector3(-1.2, 0.4, -0.2), Vector3(0.0, 1.3, 0.5)]:
		var b := CBClipLib.rot_basis(e)
		var back := b.get_euler(EULER_ORDER_ZYX)
		ok(back.distance_to(e) < 1e-4, "Euler round trip ZYX %s -> %s" % [e, back])
		ok(Basis.from_euler(e, EULER_ORDER_ZYX).is_equal_approx(b), "from_euler(ZYX) == rot_basis")
	var alt := Vector3(0.3 + PI, PI - 0.5, 0.2 + PI)
	ok(FSAEval.nearest_euler(alt, Vector3(0.3, 0.5, 0.2)).distance_to(Vector3(0.3, 0.5, 0.2)) < 1e-4, "nearest_euler picks the twin triple")
	ok(FSARig.mirror_name("indexL2") == "indexR2" and FSARig.mirror_name("armR") == "armL" and FSARig.mirror_name("head") == "head", "mirror names")
	ok(FSARig.clamp_limits("kneeL", Vector3(-0.4, 0, 0)).x == 0.0, "knee limit stops a forward bend")


func _doc_ops() -> void:
	app.new_clip("zz_animator_check", 30, 30, false, true)
	ok(app.doc.name == "zz_animator_check" and app.doc.keys.size() == 1, "new clip has one key")
	app.set_frame(10.0)
	app.set_bone_euler("armR", Vector3(-0.8, 0, 0.3))
	ok(not app.pending.is_empty(), "an edit is pending until keyed")
	app.key_now()
	ok(app.doc.has_key(10), "K keys frame 10")
	var k := app.doc.key_at(10)
	ok(near(float(k["rot"]["armR"][0]), -0.8), "the key holds the edit")
	app.set_frame(5.0)
	var p := app.editable_pose()
	var k0: Vector3 = FSADoc.pose_of_key(app.doc.key_at(0), app.bones)["armR"]
	ok((p["armR"] as Vector3).distance_to(k0.lerp(Vector3(-0.8, 0, 0.3), 0.5)) < 0.01, "in-between interpolates (got %s)" % p["armR"])
	app.undo()
	ok(not app.doc.has_key(10), "undo removes the key")
	app.redo()
	ok(app.doc.has_key(10), "redo brings it back")
	ok(app.move_keys([10], 4), "move key 10 -> 14")
	ok(app.doc.has_key(14) and not app.doc.has_key(10), "the key moved")
	app.insert_frames(2, 3)
	ok(app.doc.has_key(17) and app.doc.frames == 33, "insert 3 frames shifts later keys and lengthens the clip")
	app.delete_frames(2, 3)
	ok(app.doc.has_key(14) and app.doc.frames == 30, "delete frames undoes it")
	app.set_keys_field([14], "lock", true)
	app.set_frame(14.0)
	app.set_bone_euler("armR", Vector3(0.5, 0, 0))
	var r := app.key_now()
	ok(not bool(r.get("ok", true)), "a locked key refuses an update")
	app.set_keys_field([14], "lock", false)
	app.revert_pending()
	app.set_lock("legL", "x")
	app.set_frame(14.0)
	var leg0: Vector3 = app.editable_pose()["legL"]
	app.set_bone_euler("legL", Vector3(-0.9, 0.2, 0))
	ok(near((app.pending["legL"] as Vector3).x, leg0.x) and near((app.pending["legL"] as Vector3).y, 0.2), "a locked channel stays, the others move")
	app.revert_pending()
	app.set_lock("legL", "")
	app.set_bone_euler("kneeR", Vector3(-0.6, 0, 0))
	ok((app.pending["kneeR"] as Vector3).x >= 0.0, "the tools never bend a knee forward")
	app.revert_pending()


func _propagate() -> void:
	app.new_clip("zz_animator_check", 40, 30, true, true)
	ok(app.doc.has_key(0) and app.doc.has_key(40), "a loop clip starts with first = last key")
	ok(str(app.doc.key_at(0).get("link", "")) != "" and app.doc.key_at(0)["link"] == app.doc.key_at(40)["link"], "first and last keys are linked")
	app.set_frame(0.0)
	app.set_bone_euler("chest", Vector3(0.25, 0, 0))
	var r := app.key_now()
	ok(40 in (r.get("also_updated", []) as Array), "editing f0 updates the linked f40")
	ok(near(float(app.doc.key_at(40)["rot"]["chest"][0]), 0.25), "f40 got the same change")
	# same pose (not linked) follows in "pose" mode
	app.set_frame(20.0)
	app.key_now()
	app.unlink_keys([0, 40])
	app.propagate = "pose"
	app.set_frame(0.0)
	app.set_bone_euler("head", Vector3(0.1, 0.3, 0))
	r = app.key_now()
	ok(20 in (r.get("also_updated", []) as Array) and 40 in (r.get("also_updated", []) as Array), "same-pose keys follow the edit (got %s)" % str(r.get("also_updated", [])))
	app.propagate = "off"
	app.set_bone_euler("head", Vector3(0.0, 0.0, 0))
	r = app.key_now()
	ok((r.get("also_updated", []) as Array).is_empty(), "propagate off touches only that key")
	app.propagate = "pose"


func _layers() -> void:
	app.new_clip("zz_animator_check", 30, 30, false, true)
	var l := app.add_layer({"name": "wave", "mode": "add", "source": "keys", "mask": ["armR", "elbowR"]})
	app.set_active_layer(str(l["id"]))
	app.set_frame(10.0)
	var base := FSAEval.layer_pose(app.doc, 10.0, app.bones)
	app.set_bone_euler("armR", (base["armR"] as Vector3) + Vector3(-0.5, 0, 0))
	app.key_now()
	ok(app.doc.keys.size() == 1, "keying a layer leaves the base keys alone")
	var lp := FSAEval.layer_pose(app.doc, 10.0, app.bones)
	ok(near((lp["armR"] as Vector3).x - (base["armR"] as Vector3).x, -0.5, 0.01), "the layer adds the edit on top")
	app.set_layer(str(l["id"]), {"weight": 0.5})
	lp = FSAEval.layer_pose(app.doc, 10.0, app.bones)
	ok(near((lp["armR"] as Vector3).x - (base["armR"] as Vector3).x, -0.25, 0.01), "weight 0.5 halves it")
	app.set_layer(str(l["id"]), {"mute": true})
	ok(not app.doc.needs_bake(), "a muted layer needs no bake")
	app.set_active_layer("")
	var cl := app.add_layer({"name": "walk", "mode": "override", "source": "clip", "clip": "w_walk", "mask": FSARig.MASKS["Lower body"], "fade_in": 6, "start": 6})
	var a := FSAEval.layer_pose(app.doc, 3.0, app.bones)
	var b := FSAEval.layer_pose(app.doc, 20.0, app.bones)
	var walk := CBClipLib.pose_at(CBClipLib.load_clip("w_walk"), 20.0, app.bones)
	ok((a["legL"] as Vector3).distance_to(app.doc.base_pose(3.0, app.bones)["legL"]) < 1e-4, "a clip layer is silent before its range")
	ok((b["legL"] as Vector3).distance_to(walk["legL"]) < 1e-3, "an override clip layer takes over its bones")
	ok((b["armL"] as Vector3).distance_to(walk["armL"]) > 1e-3 or (walk["armL"] as Vector3).length() < 1e-3, "and leaves the bones outside its mask")
	app.remove_layer(str(cl["id"]))


func _constraints() -> void:
	app.new_clip("zz_animator_check", 30, 30, false, true)
	var sk := app.stage.probe_skel
	var shoulder := app.joint_world("armR")
	var tgt := shoulder + Vector3(0.15, -0.3, 0.35).normalized() * 0.5   # well inside the arm's reach
	var c := app.add_constraint({"type": "ik", "limb": "armR", "target": {"pos": [tgt.x, tgt.y, tgt.z]}})
	app.final_pose_on(sk, 0.0)
	var hi := sk.find_bone("handR")
	var got := sk.global_transform * sk.get_bone_global_pose(hi).origin
	ok(got.distance_to(tgt) < 0.01, "IK puts the hand on its target (miss %.4f m)" % got.distance_to(tgt))
	ok(app.doc.needs_bake(), "a live constraint means the save bakes")
	app.set_constraint(str(c["id"]), {"enabled": false})
	# pin (freeze) the left foot at f0 while the hips move down
	app.set_frame(0.0)
	var foot0 := app.joint_world("footL")
	app.set_frame(15.0)
	app.set_hips_shift("dy", -0.25)
	app.key_now()
	app.add_constraint({"type": "pin", "bone": "footL", "what": "both", "pin_frame": 0, "start": 0, "end": -1})
	app.final_pose_on(sk, 15.0)
	var foot15 := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("footL")).origin
	ok(foot15.distance_to(foot0) < 0.01, "a frozen foot stays put while the body drops (moved %.4f m)" % foot15.distance_to(foot0))
	var kx := (app.final_pose_on(sk, 15.0)["kneeL"] as Vector3).x
	ok(kx > 0.05, "the knee bends (backwards) to keep the foot planted (%.2f)" % kx)
	var baked := FSAEval.bake(app.doc, sk, app.bones, {})
	ok(baked.size() == 31, "bake writes a key per frame")
	app.bake_to_keys()
	ok(not app.doc.needs_bake() and app.doc.keys.size() == 31, "bake to keys switches constraints off")
	var lay := CBClipLib.pose_at(app.doc.source(), 15.0, app.bones)
	CBClipLib.apply_pose(sk, lay)
	sk.force_update_all_bone_transforms()
	var foot_b := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("footL")).origin
	ok(foot_b.distance_to(foot0) < 0.015, "the baked keys keep the foot where the pin held it (%.4f m)" % foot_b.distance_to(foot0))


func _pose_tools() -> void:
	app.new_clip("zz_animator_check", 30, 30, false, true)
	app.set_frame(0.0)
	app.set_bone_euler("armL", Vector3(-0.6, 0.1, -0.4))
	app.pose_mirror("l2r")
	var p := app.editable_pose()
	ok((p["armR"] as Vector3).distance_to(Vector3(-0.6, -0.1, 0.4)) < 1e-4, "mirror L>R flips Y and Z")
	app.key_now()
	var ctl: Dictionary = FSARig.controls()[0]
	app.set_control(ctl, 0.8)
	ok(near(FSARig.control_value(ctl, app.editable_pose()), 0.8, 0.01), "a control reads back the value it set")
	app.revert_pending()
	app.set_frame(20.0)
	app.reset_bones(app.bones)
	app.key_now()
	app.set_frame(10.0)
	app.breakdown(0.5)
	var mid: Vector3 = app.editable_pose()["armR"]
	ok(mid.distance_to(Vector3(-0.3, -0.05, 0.2)) < 0.01, "a half-way breakdown sits halfway (%s)" % mid)
	app.revert_pending()
	# IK drag of a hand
	app.set_frame(0.0)
	var h := app.joint_world("handL")
	app.drag_begin("test")
	app.drag_ik("handL", h + Vector3(0, 0.2, 0.15))
	app.drag_end()
	app._apply_now()
	ok(app.joint_world("handL").distance_to(h + Vector3(0, 0.2, 0.15)) < 0.02, "dragging a hand with IK moves it there")
	app.revert_pending()


func _save_roundtrip() -> void:
	app.new_clip("zz_animator_check", 24, 30, false, true)
	app.set_frame(12.0)
	app.set_bone_euler("torso", Vector3(0.3, 0.2, 0))
	app.key_now()
	app.add_constraint({"type": "floor", "bones": ["footL", "footR"], "mode": "plant"})
	var r := app.save()
	ok(bool(r.get("ok", false)) and bool(r.get("baked", false)), "save writes the clip and bakes the live constraint")
	var c := CBClipLib.load_clip("zz_animator_check")
	ok(str((c.get("studio", {}) as Dictionary).get("saved", "")).length() == 19, "every save stamps studio.saved (the generators skip the clip)")
	ok(FSADoc.from_clip(c).saved == str(c["studio"]["saved"]) and FSADoc.from_clip({"name": "x", "keys": []}).saved == "", "saved is read back; a generator clip has none")
	ok((c.get("keys", []) as Array).size() == 25, "the game keys are the bake (a key per frame)")
	ok((c.get("studio", {}) as Dictionary).has("base") and ((c["studio"] as Dictionary)["base"] as Array).size() == 2, "the editable keys ride along under studio.base")
	var d := FSADoc.from_clip(c)
	ok(not d.outside_edit and d.keys.size() == 2 and d.constraints.size() == 1, "re-opening gives back the base keys and the constraint")
	c["keys"] = (c["keys"] as Array).slice(0, 3)
	var d2 := FSADoc.from_clip(c)
	ok(d2.outside_edit and not d2.needs_bake(), "keys changed elsewhere are taken as the base, constraints switched off")
	app.trash_clip("zz_animator_check")
	ok(not FileAccess.file_exists(CBClipLib.DIR + "zz_animator_check.json"), "the scratch clip went to the trash")


func _api() -> void:
	var api := FSAApi.new()
	api.app = app
	var r: Dictionary = await api.call_method("ping", {})
	ok(r.get("result", "") == "pong", "api ping")
	r = await api.call_method("new_clip", {"name": "zz_animator_api", "frames": 20, "discard": true})
	ok(bool(r.get("ok", false)), "api new_clip %s" % str(r))
	r = await api.call_method("set_pose", {"frame": 10, "bones": {"armR": [-60, 0, 20], "kneeL": [-30, 0, 0]}})
	ok(bool(r.get("ok", false)) and "kneeL" in ((r["result"] as Dictionary).get("clamped_by_limits_or_locks", [])), "api set_pose keys and reports the clamped knee")
	r = await api.call_method("get_pose", {"frame": 10, "bones": ["armR"]})
	var arm: Array = ((r["result"] as Dictionary)["bones"] as Dictionary)["armR"]
	ok(near(float(arm[0]), -60.0, 0.05) and near(float(arm[2]), 20.0, 0.05), "api get_pose reads degrees back")
	r = await api.call_method("rig", {})
	ok(((r["result"] as Dictionary)["bones"] as Array).size() == app.bones.size(), "api rig lists every bone")
	r = await api.call_method("ik_pose", {"frame": 5, "bone": "footR", "target": [-0.12, 0.25, 0.3]})
	ok(bool(r.get("ok", false)) and float((r["result"] as Dictionary)["miss_m"]) < 0.03, "api ik_pose reaches (%s)" % str(r))
	# a foot pulled forward and up, and a hand out front: the joint limits never make the IK miss (knees / elbows bend on
	# their hinge only, so no twist piles up in the thigh / upper arm for the limits to clamp)
	var sh := app.joint_world("armR")
	var reach := sh.distance_to(app.joint_world("elbowR")) + app.joint_world("elbowR").distance_to(app.joint_world("handR"))
	var hand := sh + Vector3(0.1, -0.35, 0.85).normalized() * reach * 0.75   # in front of the shoulder, inside the arm's reach
	for t in [["footR", [0.12, 0.25, 0.3], "kneeR"], ["footL", [-0.2, 0.45, 0.35], "kneeL"], ["handR", [hand.x, hand.y, hand.z], "elbowR"]]:
		r = await api.call_method("ik_pose", {"frame": 5, "bone": t[0], "target": t[1]})
		var hinge: Vector3 = app.editable_pose().get(str(t[2]), Vector3.ZERO)
		ok(bool(r.get("ok", false)) and float((r["result"] as Dictionary)["miss_m"]) < 0.01 and absf(hinge.y) < 1e-3 and absf(hinge.z) < 1e-3,
			"ik reaches %s %s on the %s hinge (%s, %s deg)" % [t[0], str(t[1]), t[2], str(r.get("result", r)), str(hinge * 57.2958)])
	r = await api.call_method("checks", {})
	ok(bool(r.get("ok", false)), "api checks")
	r = await api.call_method("nope", {})
	ok(not bool(r.get("ok", true)), "unknown methods fail cleanly")
	r = await api.call_method("open_clip", {"name": "w_walk"})
	ok(not bool(r.get("ok", true)), "open_clip refuses to drop unsaved work without discard")
	app.history.mark_saved()


## Merge: the walk keeps the legs, the taunt gives the arms from f10, the walk repeats under the longer taunt
func _merge() -> void:
	var was := app.doc.name
	ok(app.open_clip("a_walk", true), "merge: open the walk as the base")
	var walk := CBClipLib.load_clip("a_walk")
	var taunt := CBClipLib.load_clip("a_taunt")
	var l := app.merge_add("a_taunt", ["Arm L", "Arm R", "Hands"], 10, 0, 0)
	ok(not l.is_empty() and bool(l.get("merge", false)) and int(l["offset"]) == 10 and int(l["end"]) == 70, "merge: the taunt lands at f10 and ends at f70")
	var p := FSAEval.layer_pose(app.doc, 40.0, app.bones)
	var pw := CBClipLib.pose_at(walk, 40.0, app.bones)
	var pt := CBClipLib.pose_at(taunt, 30.0, app.bones)
	ok((p["armR"] as Vector3).distance_to(pt["armR"]) < 1e-4 and (p["elbowL"] as Vector3).distance_to(pt["elbowL"]) < 1e-4, "merge: the arms come from the taunt")
	ok((p["legL"] as Vector3).distance_to(pw["legL"]) < 1e-4 and (p["chest"] as Vector3).distance_to(pw["chest"]) < 1e-4, "merge: legs and spine stay the walk's")
	ok(FSAMerge.length(app.doc) == 70, "merge: the merged clip runs to the end of the taunt (70)")
	app.merge_set(str(l["id"]), {"blend_in": 8})
	var mid := FSAEval.layer_pose(app.doc, 14.0, app.bones)
	var w14 := CBClipLib.pose_at(walk, 14.0, app.bones)
	var t4 := CBClipLib.pose_at(taunt, 4.0, app.bones)
	var arm: Vector3 = mid["armR"]
	ok(arm.distance_to(w14["armR"]) > 1e-3 and arm.distance_to(t4["armR"]) > 1e-3, "merge: blending in, the arm is between the walk and the taunt")
	app.merge_set(str(l["id"]), {"start": 12})
	var l2 := app.doc.layer_by_id(str(l["id"]))
	ok(int(l2["offset"]) == 12 and int(l2["end"]) == 72, "merge: moving the start moves the clip and its end")
	app.merge_set(str(l["id"]), {"parts": ["Arm R"]})
	ok((app.doc.layer_by_id(str(l["id"]))["mask"] as Array) == ["armR", "elbowR", "handR"], "merge: lighting parts sets the bones")
	app.merge_set(str(l["id"]), {"parts": ["Arm L", "Arm R", "Hands"], "start": 10, "blend_in": 0})
	var before := FileAccess.get_file_as_string(CBClipLib.DIR + "a_walk.json")
	var r := app.merge_bake("zz_merge_check")
	ok(app.doc.name == "zz_merge_check" and app.is_new and app.doc.frames == 70, "merge: bake opens one new clip of 70 frames")
	ok(app.doc.keys.size() < 71 and app.doc.keys.size() > 2, "merge: the baked keys are thinned (%d keys for 71 frames)" % app.doc.keys.size())
	var b60 := app.doc.base_pose(60.0, app.bones)
	ok((b60["legL"] as Vector3).distance_to(CBClipLib.pose_at(walk, 12.0, app.bones)["legL"]) < 0.03, "merge: the walk repeats under the long taunt (f60 = walk f12)")
	ok((b60["armR"] as Vector3).distance_to(CBClipLib.pose_at(taunt, 50.0, app.bones)["armR"]) < 0.03, "merge: and the arms are the taunt's (f60 = taunt f50)")
	ok(FileAccess.get_file_as_string(CBClipLib.DIR + "a_walk.json") == before, "merge: the base clip on disk is untouched")
	ok(str((app.doc.extra.get("merge", {}) as Dictionary).get("base", "")) == "a_walk", "merge: the recipe rides along in the new clip")
	ok(app.merge_rebuild() and app.doc.name == "a_walk" and FSAMerge.merge_layers(app.doc).size() == 1, "merge: rebuild opens the base with the clip on top again")
	ok(not r.has("error"), "merge: bake report")
	app.open_clip(was, true)


## Adjust: a part tilted across all frames / a range / one frame, on top of the keys; limits kept; restore; one undo step a drag
func _feet() -> void:
	var was := app.doc.name
	var was_f := app.fighter
	ok(app.dock.panels.has("Feet"), "feet: the Feet panel is in the dock")
	app.set_fighter("carter")
	app.open_clip("a_wait", true)
	ok(app.doc.plant, "feet: Carter's wait is planted")
	var r := app.feet_report(1)
	ok((r["frames"] as Array).size() == app.doc.frames + 1, "feet: a row per frame")
	ok(float(r["soles"]["footL"]["tilt0"]) > 8.0, "feet: Carter's own left sole is off level at rest (%.1f deg), so the rest pose is no guide" % float(r["soles"]["footL"]["tilt0"]))
	var bad := ""
	for row in r["frames"]:
		var lo := "footL" if float(row["footL"]["low_cm"]) <= float(row["footR"]["low_cm"]) else "footR"
		if str(row[lo]["state"]) != "flat" or absf(float(row[lo]["low_cm"])) > 1.0:
			bad = "f%d %s %s %.1f cm" % [int(row["f"]), lo, row[lo]["state"], float(row[lo]["low_cm"])]
		for b in ["footL", "footR"]:
			if str(row[b]["state"]) == "sink":
				bad = "f%d %s sinks" % [int(row["f"]), b]
	ok(bad == "", "feet: in Carter's wait the lower foot stands flat on the floor and no foot sinks %s" % bad)
	ok(app.stage.probe.position == Vector3.ZERO, "feet: the report leaves the probe model where it was")
	app.set_clip_prop("plant", false)
	var r2 := app.feet_report(1)
	ok(int((r2["counts"] as Dictionary).get("sink", 0)) > 0, "feet: unplanted, the same clip has feet in the floor (%d)" % int((r2["counts"] as Dictionary).get("sink", 0)))
	app.undo()
	ok(app.doc.plant, "feet: planted again after undo")
	app.set_fighter(was_f)
	app.open_clip(was, true)


func _adjust() -> void:
	var was := app.doc.name
	app.open_clip("a_walk", true)
	var walk := CBClipLib.load_clip("a_walk")
	var keys_before := JSON.stringify(app.doc.keys)
	var t := Vector3(deg_to_rad(10.0), 0, 0)
	app.adjust_part("armL", t, "all")
	for f in [0, 13, 30]:
		var p := FSAEval.layer_pose(app.doc, float(f), app.bones)
		var b := CBClipLib.pose_at(walk, float(f), app.bones)
		ok(((p["armL"] as Vector3) - (b["armL"] as Vector3)).distance_to(t) < 1e-4 and (p["armR"] as Vector3).distance_to(b["armR"]) < 1e-4,
			"adjust: armL +10 X on f%d, armR untouched" % f)
	ok(JSON.stringify(app.doc.keys) == keys_before, "adjust: the keys never change")
	ok(FSAAdjust.adjusted_bones(app.doc).has("armL"), "adjust: armL is marked")
	app.adjust_part("armL", Vector3(deg_to_rad(20.0), 0, 0), "all")
	ok(FSAAdjust.adjust_layers(app.doc).size() == 1 and absf(app.adjust_value("armL").x - deg_to_rad(20.0)) < 1e-4, "adjust: setting it again replaces the turn")
	app.adjust_part("elbowL", Vector3(0.1, 0.2, 0.3), "all", -1, 0, -1, 6, true)
	ok(app.adjust_value("elbowR").distance_to(FSARig.mirror_euler(Vector3(0.1, 0.2, 0.3))) < 1e-4, "adjust: both sides gets the mirrored turn")
	app.adjust_part("head", Vector3(0.4, 0, 0), "range", -1, 10, 30, 5)
	var hb := func(f: float) -> float: return (CBClipLib.pose_at(walk, f, app.bones)["head"] as Vector3).x
	var ha := func(f: float) -> float: return (FSAEval.layer_pose(app.doc, f, app.bones)["head"] as Vector3).x
	ok(absf(float(ha.call(5.0)) - float(hb.call(5.0))) < 1e-4, "adjust range: before it, untouched")
	ok(absf(float(ha.call(20.0)) - float(hb.call(20.0)) - 0.4) < 1e-4, "adjust range: in the middle, the full turn")
	var d12 := float(ha.call(12.0)) - float(hb.call(12.0))
	ok(d12 > 0.01 and d12 < 0.39, "adjust range: easing in at its start (%.3f)" % d12)
	app.adjust_part("neck", Vector3(0.2, 0, 0), "frame", 24, 0, -1, 0)
	var n24 := (FSAEval.layer_pose(app.doc, 24.0, app.bones)["neck"] as Vector3).x - (CBClipLib.pose_at(walk, 24.0, app.bones)["neck"] as Vector3).x
	var n25 := (FSAEval.layer_pose(app.doc, 25.0, app.bones)["neck"] as Vector3).distance_to(CBClipLib.pose_at(walk, 25.0, app.bones)["neck"])
	ok(absf(n24 - 0.2) < 1e-4 and n25 < 1e-4, "adjust frame: that frame only (ease 0)")
	app.adjust_part("kneeL", Vector3(deg_to_rad(-90.0), 0, 0), "all")
	var worst := INF
	for f in app.doc.frames + 1:
		var kb := (CBClipLib.pose_at(walk, float(f), app.bones)["kneeL"] as Vector3).x
		var ka := (FSAEval.layer_pose(app.doc, float(f), app.bones)["kneeL"] as Vector3).x
		worst = minf(worst, ka - minf(0.0, kb))
	ok(worst >= -1e-4, "adjust: a knee adjustment never bends it forward")
	ok(app.adjust_restore("", "kneeL") == 1 and not FSAAdjust.adjusted_bones(app.doc).has("kneeL"), "adjust: restore one part")
	app.adjust_restore()
	var a13 := (FSAEval.layer_pose(app.doc, 13.0, app.bones)["armL"] as Vector3).distance_to(CBClipLib.pose_at(walk, 13.0, app.bones)["armL"])
	ok(FSAAdjust.adjust_layers(app.doc).is_empty() and a13 < 1e-4, "adjust: restore all, the clip is as it was")
	var n0: int = app.history.undo_stack.size()
	for i in 10:
		app.adjust_part("handR", Vector3(0, 0, deg_to_rad(float(i + 1))), "all")
	ok(app.history.undo_stack.size() == n0 + 1, "adjust: a drag (many small turns) is one undo step")
	app.open_clip(was, true)
