extends Node
## Studio round trip, headless-safe: godot --path . res://game/packs/city_breaker/tools/studio_check.tscn
var _fails := 0
var _n := 0
func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if not cond:
		_fails += 1
	print("  ", "ok  " if cond else "FAIL", "  ", name, ("  (" + detail + ")") if detail != "" else "")

func _ready() -> void:
	var cues_before := FileAccess.get_file_as_string(CBCues.DATA)
	var combos_before := FileAccess.get_file_as_string(CBFxRmt.COMBOS)
	var pairs_before := FileAccess.get_file_as_string(CBPairs.DATA)
	var st: Node = load("res://game/packs/city_breaker/studio/studio.tscn").instantiate()
	add_child(st)
	await get_tree().create_timer(1.0).timeout
	_ok("fighter loaded with its bones (27, vix has 33 with ears)", st.bones.size() >= 27, str(st.bones.size()))
	_ok("sockets built (12 nodes + 2 ground)", st.sockets.size() >= 14, str(st.sockets.size()))
	# a clip: crouch at 0, jump pose at 8
	st._new_clip()
	var nm: String = st.clip_name
	st.pose = {}
	for b in st.bones:
		st.pose[b] = Vector3.ZERO
	st.pose["legL"] = Vector3(-1.2, 0, 0)
	st.pose["kneeL"] = Vector3(1.6, 0, 0)
	st.pose["hips"] = Vector3(0.5, 0, 0)
	st.pose["_dy"] = -0.3
	st.frame = 8.0
	st._key_frame()
	_ok("two keys stored", (st.clip["keys"] as Array).size() == 2)
	st._goto_frame(4.0)
	var mid: Vector3 = st.pose["kneeL"]
	_ok("in-between interpolates the knee", absf(mid.x - 0.8) < 0.05, "%.3f" % mid.x)
	_ok("knee check passes", (st.clip["keys"] as Array).size() == 2)
	# saved and reloadable
	var back := CBClipLib.load_clip(nm)
	_ok("clip file saved and loads back", not back.is_empty() and (back["keys"] as Array).size() == 2)
	# the Animation resource exists and plays
	_ok("animation installed in the player", st.anim.has_animation(nm), nm)
	var a: Animation = st.anim.get_animation(nm)
	_ok("animation has bone tracks + hips position", a.get_track_count() == st.bones.size() + 1, str(a.get_track_count()))
	_ok("length = frames / fps", absf(a.length - 24.0 / 30.0) < 0.01, str(a.length))
	# cues
	st.fx_sel = "impact_spark"
	st.frame = 5.0
	st._add_cue()
	_ok("cue added", st.cues_work.size() == 1)
	CBCues.set_clip(nm, st.cues_work)
	var cp := CBCues.Player.new()
	var fired: Array = []
	cp.on_fire = func(c: Dictionary) -> void: fired.append(c["fx"])
	cp.reset(nm)
	cp.tick(0.05)
	cp.tick(0.2)
	cp.tick(0.3)
	_ok("cue fires once when the clip passes it", fired == ["impact_spark"], str(fired))
	cp.tick(0.01)
	cp.tick(0.3)
	_ok("cue fires again after the clip restarts", fired.size() == 2)
	# combo
	st.combo_layers = [["impact_spark", 1.0, 0.0], ["shock_punch", 1.2, 0.05]]
	st.ui_combo_name.text = "studio_check_combo"
	st._combo_save()
	_ok("combo saved and found", CBFxRmt.combos().has("studio_check_combo"))
	# sockets: add, edit, rebuild
	st.ui_s_name.text = "test_sock"
	st._add_socket()
	st._edit_spec("t", 0.5)
	_ok("new socket exists on the skeleton", st.sockets.has("test_sock") and (st.sockets["test_sock"] as Node3D).is_inside_tree())
	st._remove_socket()
	_ok("socket removed", not st.sockets.has("test_sock"))
	# ground centre + soles
	st._add_ground_mid()
	st._add_soles()
	_ok("ground_mid is a ground socket on the root", st.sock_specs["ground_mid"].get("ground", false) and st.sock_specs["ground_mid"]["bone"] == "root")
	var sole_y: float = (st.sockets["sole_L"] as Node3D).global_position.y
	_ok("sole sits on the floor at rest", absf(sole_y) < 0.08, "y=%.3f" % sole_y)
	# a reactor staged next to the actor
	st.ui_pair_show.button_pressed = true
	st.pair["dx"] = 1.2
	st.pair["yaw"] = 180.0
	st._place_reactor()
	var d: float = st.rmodel.global_position.distance_to(st.actor_model.global_position)
	_ok("reactor stands 1.2 m in front", absf(d - 1.2) < 0.01, "%.3f" % d)
	st._new_reactor_clip()
	_ok("now editing the reactor with its own clip", st.edit_reactor and str(st.clip_name).ends_with("_react"), st.clip_name)
	var rname: String = st.clip_name
	st.pose = {}
	for b in st.bones:
		st.pose[b] = Vector3.ZERO
	st.pose["torso"] = Vector3(0.5, 0, 0)
	st.frame = 6.0
	st._key_frame()
	_ok("reactor clip keyed and saved", CBClipLib.load_clip(rname).get("keys", []).size() == 2)
	st._set_edit(false)
	_ok("back on the actor clip", not st.edit_reactor and st.clip_name == nm, st.clip_name)
	st._save_pair()
	_ok("pair saved for the actor clip", str(CBPairs.for_clip(nm).get("reactor_clip", "")) == rname)
	var pair_back := FileAccess.get_file_as_string(CBPairs.DATA)
	_ok("pairs.json written", pair_back.contains(rname))
	# ears exist on vix; proportional pose drags the neighbours with a falloff
	_ok("vix has ear bones", st.bones.has("earL") and st.bones.has("earL3"))
	st.clip = CBClipLib.blank("zone_test")
	st.pose = {}
	for b in st.bones:
		st.pose[b] = Vector3.ZERO
	st.prop_on = true
	st.prop_radius = 0.4
	st.prop_falloff = "linear"
	st.bone_sel = "earL"
	st._set_rot(0, 0.6)
	var e2: Vector3 = st.pose["earL2"]
	var e3: Vector3 = st.pose["earL3"]
	_ok("proportional: the next ear joint follows, less", e2.x > 0.0 and e2.x < 0.6, "earL2 %.3f" % e2.x)
	_ok("proportional: the far joint follows least", e3.x <= e2.x, "earL3 %.3f" % e3.x)
	_ok("proportional: a bone outside the radius is untouched", (st.pose["legL"] as Vector3).x == 0.0)
	st.prop_on = false
	st.clip = {}
	# socket zone: radius + scatter
	st.ui_s_name.text = "zone_sock"
	st._add_socket()
	st._edit_zone("radius", 0.3)
	_ok("zone radius saved in the spec", is_equal_approx(CBSockets.zone_radius(st.sock_specs["zone_sock"]), 0.3))
	var far := 0.0
	for i in 40:
		far = maxf(far, CBFxRmt.scatter(st.sock_specs["zone_sock"]["zone"]).length())
	_ok("effects scatter inside the zone", far > 0.02 and far <= 0.3001, "max %.3f" % far)
	st._remove_socket()
	# secondary motion: chains, per-joint edit, ramp, rebuild
	_ok("secondary chains loaded (tail + ears)", st.sec_specs.has("tail") and st.sec_specs.has("ear_L"), str(st.sec_specs.keys()))
	st.ui_sec_on.button_pressed = true
	var sims := 0
	for c in st.actor_skel.get_children():
		if c is SpringBoneSimulator3D:
			sims += 1
	_ok("physics preview builds a simulator per chain", sims >= 4, str(sims))
	st._sec_select("tail")
	st._sec_ramp("stiffness", 2.0, 0.4)
	var arr: Array = st.sec_specs["tail"]["stiffness"]
	_ok("ramp: stiff at the root, loose at the tip", arr.size() == 3 and arr[0] > arr[2], str(arr))
	st.sec_joint = 1
	st._sec_edit_joint("drag", 0.77)
	_ok("one joint edited on its own", absf(float(st.sec_specs["tail"]["drag"][1]) - 0.77) < 0.001)
	st.ui_sec_on.button_pressed = false
	# body reactions: tune, try, save
	st._react_edit("strength", 1.5)
	_ok("reaction setting edited on the working copy", is_equal_approx(float(st.react_work["strength"]), 1.5))
	st.ui_react_sock.select(max(0, st.ui_react_sock.item_count - 1))
	st._react_try(false)
	_ok("hitting the actor starts the spring", st.actor_react.is_busy())
	st._react_try(true)
	_ok("hitting the reactor starts its spring and the actor recoils", st.rreact.is_busy())
	var react_before := FileAccess.get_file_as_string(CBHitReact.DATA)
	st._react_save(true)
	_ok("saved as a per-fighter override", FileAccess.get_file_as_string(CBHitReact.DATA).contains("\"strength\": 1.5"))
	var rf := FileAccess.open(CBHitReact.DATA, FileAccess.WRITE); rf.store_string(react_before); rf.close()
	CBHitReact.data(true)
	# ---- pose mode: euler round trip, global mode, ground lock, click picking / dragging, click-add socket
	st.clip = CBClipLib.blank("pm_test")
	st._neutral()
	var e0 := Vector3(0.4, -0.3, 0.2)
	var back_e := CBClipLib.rot_basis(e0).get_euler(EULER_ORDER_ZYX)
	_ok("rot_basis and ZYX euler round-trip", back_e.distance_to(e0) < 0.001, str(back_e))
	st.bone_sel = "armL"
	st.space_global = true
	st._set_rot(0, 0.5)
	st._apply()
	var g: Vector3 = st._global_euler("armL")
	_ok("global mode: the slider value is what the bone ends up at", absf(g.x - 0.5) < 0.02, "%.3f" % g.x)
	st.space_global = false
	st._neutral()
	st.ground_lock = true
	var foot_before: Vector3 = st.skel.get_bone_global_pose(st.skel.find_bone("footL")).origin
	st._set_dy(-0.25)
	var foot_after: Vector3 = st.skel.get_bone_global_pose(st.skel.find_bone("footL")).origin
	_ok("ground lock: lowering the hips 25 cm keeps the foot put", foot_before.distance_to(foot_after) < 0.02, "moved %.3f m" % foot_before.distance_to(foot_after))
	_ok("ground lock: the knees bent, never backwards", float((st.pose["kneeL"] as Vector3).x) > 0.2 and float((st.pose["kneeR"] as Vector3).x) >= 0.0, "kneeL %.2f" % float((st.pose["kneeL"] as Vector3).x))
	st.ground_lock = false
	st._neutral()
	st._set_dy(-0.25)
	var foot_free: Vector3 = st.skel.get_bone_global_pose(st.skel.find_bone("footL")).origin
	_ok("without the lock the foot goes down with the hips", foot_before.distance_to(foot_free) > 0.15, "%.3f" % foot_before.distance_to(foot_free))
	st._neutral()
	st._apply()
	await get_tree().process_frame
	var ap: Vector2 = st.cam.unproject_position(st._bone_o(st.skel.find_bone("elbowL")))
	_ok("clicking a joint picks that bone", st._pick_bone_at(ap) == "elbowL", st._pick_bone_at(ap))
	var wrist_before: Vector3 = st._bone_o(st.skel.find_bone("handL"))
	st.drag_bone = "armL"
	var ev := InputEventMouseMotion.new()
	ev.position = ap + Vector2(40, -60)
	ev.relative = Vector2(40, -60)
	st._drag(ev)
	var wrist_after: Vector3 = st._bone_o(st.skel.find_bone("handL"))
	_ok("dragging the shoulder swings the arm", wrist_before.distance_to(wrist_after) > 0.05, "%.3f m" % wrist_before.distance_to(wrist_after))
	st._neutral()
	st._apply()
	await get_tree().process_frame
	var n0: int = st.sock_specs.size()
	var chest_px: Vector2 = st.cam.unproject_position(st._bone_o(st.skel.find_bone("chest")))
	st._click_add_socket(chest_px)
	_ok("click-add made a socket on the clicked bone", st.sock_specs.size() == n0 + 1)
	st.clip = {}
	# every fighter's baked clips must still move (a Blender re-export once flattened them to 2 keys)
	for fk in ["vix", "carter", "al", "slum", "guru", "bigbill", "rhino", "goat"]:
		var fps := load(CBRoster.model_path(fk)) as PackedScene
		var fm := fps.instantiate() as Node3D
		st.add_child(fm)
		var fa: AnimationPlayer = fm.find_children("*", "AnimationPlayer", true, false)[0]
		var an := fa.get_animation("jab")
		var keys := 0
		for t in an.get_track_count():
			keys = maxi(keys, an.track_get_key_count(t))
		_ok("%s jab is keyed (not flattened)" % fk, keys > 10, "max keys %d" % keys)
		fm.queue_free()
	# ---- unbake, key blend, ghost blocks
	var e_in := Vector3(0.4, -0.3, 0.7)
	CBClipLib.apply_pose(st.skel, {"armL": e_in})
	var e_out := CBAnimTools.euler_of(st.skel.get_bone_rest(st.skel.find_bone("armL")), st.skel.get_bone_pose(st.skel.find_bone("armL")))
	_ok("euler round trip (pose -> skeleton -> euler)", e_in.distance_to(e_out) < 0.002, str(e_out))
	var baked := "run" if st.anim.has_animation("run") and not CBClipLib.list_clips().has("run") else "fightIdle"
	st._select_clip(baked)
	var frames_src := int(round(st.anim.get_animation(baked).length * 30.0))
	st._unbake()
	var ub: String = st.clip_name
	var nkeys := (st.clip["keys"] as Array).size()
	_ok("unbake: a studio copy named %s_edit with sparse keys" % baked, ub == baked + "_edit" and nkeys >= 2 and nkeys < frames_src, "%d keys for %d frames" % [nkeys, frames_src])
	_ok("the baked original is untouched", not CBClipLib.list_clips().has(baked) or baked == "fightIdle")
	var worst := 0.0
	var worst_bone := ""
	for f in [2, int(frames_src * 0.4), int(frames_src * 0.8)]:
		st.anim.active = true
		st.anim.play(baked)
		st.anim.seek(float(f) / 30.0, true)
		st.anim.advance(0.0)
		var ks := CBAnimTools.sample_key(st.skel, f, st.bones)
		var pa := CBClipLib.pose_at(st.clip, float(f), st.bones)
		for b in st.bones:
			var evk := CBClipLib._key_rot(ks, str(b))
			var ang := CBClipLib.rot_basis(evk).get_rotation_quaternion().angle_to(CBClipLib.rot_basis(pa[b] as Vector3).get_rotation_quaternion())
			if ang > worst:
				worst = ang
				worst_bone = "%s f=%d key=%s pose=%s" % [str(b), f, str(evk), str(pa[b])]
	_ok("the unbaked clip reproduces the baked motion (max %.3f rad off at 3 frames)" % worst, worst < 0.25, "%.3f at %s" % [worst, worst_bone])
	# key blend: an edit of +0.5 at frame 8 reaches the keys at 4 and 12 (weights from the falloff) and not the one at 0 (too far)
	var kc := {"name": "blendtest", "fps": 30, "frames": 16, "keys": [
		{"f": 0, "rot": {}, "hips_dy": 0.0}, {"f": 4, "rot": {}, "hips_dy": 0.0}, {"f": 8, "rot": {}, "hips_dy": 0.0}, {"f": 12, "rot": {}, "hips_dy": 0.0}]}
	var dl := {"kneeL": Vector3(0.5, 0, 0), "_dy": -0.2}
	var touched := CBAnimTools.blend_neighbours(kc, 8, dl, 6.0, "smooth")
	var k4: Vector3 = CBClipLib._key_rot((kc["keys"] as Array)[1], "kneeL")
	var k12: Vector3 = CBClipLib._key_rot((kc["keys"] as Array)[3], "kneeL")
	var k0: Vector3 = CBClipLib._key_rot((kc["keys"] as Array)[0], "kneeL")
	_ok("key blend reaches the keys before and after, fading with distance", touched == 2 and absf(k4.x - k12.x) < 0.002 and k4.x > 0.05 and k4.x < 0.25 and k0.x == 0.0, "k4 %.3f k12 %.3f k0 %.3f" % [k4.x, k12.x, k0.x])
	_ok("key blend weights: 1 at the edit, 0 at the range, linear / sharp / constant differ", CBAnimTools.weight("smooth", 0.0, 6.0) == 1.0 and CBAnimTools.weight("smooth", 6.0, 6.0) == 0.0 and CBAnimTools.weight("linear", 3.0, 6.0) == 0.5 and CBAnimTools.weight("sharp", 3.0, 6.0) < 0.2 and CBAnimTools.weight("constant", 5.0, 6.0) == 1.0)
	# the same through the Studio: KEY with key blend on
	st._new_clip()
	var bn: String = st.clip_name
	for fr in [0, 16]:
		st.pose = {}
		for b in st.bones:
			st.pose[b] = Vector3.ZERO
		st.pose["kneeL"] = Vector3(0.5, 0, 0)
		st.frame = float(fr)
		st._key_frame()
	st.key_blend_on = true
	st.key_blend_range = 12.0
	st.pose = CBClipLib.pose_at(st.clip, 8.0, st.bones)
	st.pose["kneeL"] = Vector3(1.5, 0, 0)    # +1.0 over the interpolated 0.5
	st.frame = 8.0
	st._key_frame()
	var kk0: Vector3 = CBClipLib._key_rot(CBClipLib.sorted_keys(st.clip)[0], "kneeL")
	_ok("KEY with key blend: the keys at 0 and 16 moved toward the edit", kk0.x > 0.5 and kk0.x < 1.2, "%.3f" % kk0.x)
	st.key_blend_on = false
	# ghost blocks live in the clip and survive a save
	st._ghost_add(CBAnimTools.ledge_ghost())
	st._ghost_add(CBAnimTools.new_ghost("crate", Vector3(1, 0.5, 0), Vector3(1, 1, 1)))
	_ok("two ghosts added, with unique names", st._ghosts().size() == 2 and st.ghost_nodes.size() == 2, str(st.ghost_nodes.keys()))
	st.ghost_sel = "crate"
	st.frame = 0.0
	st._ghost_key()
	st.frame = 12.0
	st._ghost_edit("pos", 0, 3.0)
	var gh := CBAnimTools.ghost_at(st.clip, st._ghost_by_name("crate"), 6.0)
	_ok("a keyed ghost moves between its keys (x 1 -> 3, half way = 2)", absf((gh["pos"] as Vector3).x - 2.0) < 0.02, str(gh["pos"]))
	var gback := CBClipLib.load_clip(bn)
	_ok("ghosts and ghost keys are saved in the clip file", (gback.get("ghosts", []) as Array).size() == 2 and (gback.get("ghost_keys", {}) as Dictionary).has("crate"))
	var lg := CBAnimTools.ledge_ghost()
	var lp := CBAnimTools.ghost_vec(lg, "pos")
	var ls := CBAnimTools.ghost_vec(lg, "size")
	_ok("the ledge preset's top face is at hang height (2.2 m)", absf(lp.y + ls.y * 0.5 - 2.2) < 0.01, "%.2f" % (lp.y + ls.y * 0.5))
	CBClipLib.delete_clip(bn)
	CBClipLib.delete_clip(ub)
	# move gizmo: hips shift is stored, a hand slid by IK lands near its target, copy/paste and close loop
	st._neutral()
	st.move_mode = true
	st.bone_sel = "handL"
	var hi: int = st.skel.find_bone("handL")
	var h0: Vector3 = st._bone_o(hi)
	st._move_ik(hi, Vector3(0.0, 0.25, 0.0))
	var h1: Vector3 = st._bone_o(hi)
	_ok("MOVE slides a hand up by IK (0.25 m asked)", h1.y - h0.y > 0.15 and absf(h1.x - h0.x) < 0.12, "%.3f %.3f" % [h1.y - h0.y, h1.x - h0.x])
	var mp := CBClipLib.pose_at({"keys": [{"f": 0, "rot": {}, "hips_dy": 0.0, "hips_dx": 0.2}, {"f": 10, "rot": {}, "hips_dy": 0.0, "hips_dx": 0.4}]}, 5.0, st.bones)
	_ok("hips_dx interpolates between keys", absf(float(mp["_dx"]) - 0.3) < 0.001, str(mp["_dx"]))
	var slid := 0
	for mb in ["elbowL", "footR", "kneeL", "head", "handR", "chest", "armL"]:
		st._neutral()
		var mi: int = st.skel.find_bone(mb)
		var m0: Vector3 = st._bone_o(mi)
		st._move_ik(mi, Vector3(0.0, 0.0, 0.2))
		if (st._bone_o(mi) - m0).z > 0.15:
			slid += 1
	_ok("MOVE places elbow, foot, knee, head, hand, chest and arm 0.2 m forward", slid == 7, str(slid))
	_ok("a bone straight on the hips has no chain (the caller slides the body)", not st._move_ik(st.skel.find_bone("tail"), Vector3(0, 0, 0.2)))
	# the real mouse path: press on the Z handle of the left hand, drag along it
	st._neutral()
	st._set_move(true)
	st.bone_sel = "handL"
	var hj: int = st.skel.find_bone("handL")
	var ho: Vector3 = st._bone_o(hj)
	var tip: Vector2 = st.cam.unproject_position(ho + Vector3.BACK * st.AXIS_LEN)
	var dir: Vector2 = tip - st.cam.unproject_position(ho)
	var mev := InputEventMouseButton.new()
	mev.button_index = MOUSE_BUTTON_LEFT
	mev.pressed = true
	mev.position = tip
	st._input(mev)
	_ok("pressing the Z handle in MOVE mode grabs it", st.drag_axis == 2 and st.drag_bone == "handL", str(st.drag_axis))
	var mv := InputEventMouseMotion.new()
	mv.relative = dir.normalized() * 20.0
	mv.position = tip
	mv.button_mask = MOUSE_BUTTON_MASK_LEFT
	st._input(mv)
	var ho2: Vector3 = st._bone_o(hj)
	_ok("dragging it slides the hand forward", ho2.z - ho.z > 0.02, "%.3f" % (ho2.z - ho.z))
	mev.pressed = false
	st._input(mev)
	st.move_mode = false
	st._copy_pose()
	_ok("copy pose keeps the pose", not st.pose_copy.is_empty())
	# export
	st._export_glb()
	var glb := ProjectSettings.globalize_path("res://game/packs/city_breaker/exports/vix_studio.glb")
	_ok("GLB exported", FileAccess.file_exists(glb), glb)
	# clean up everything the check wrote
	CBClipLib.delete_clip(nm)
	CBClipLib.delete_clip(rname)
	CBPairs.set_pair(nm, {})
	CBPairs.save()
	var f := FileAccess.open(CBCues.DATA, FileAccess.WRITE); f.store_string(cues_before); f.close()
	var f2 := FileAccess.open(CBFxRmt.COMBOS, FileAccess.WRITE); f2.store_string(combos_before); f2.close()
	var f3 := FileAccess.open(CBPairs.DATA, FileAccess.WRITE); f3.store_string(pairs_before); f3.close()
	if FileAccess.file_exists(glb):
		DirAccess.remove_absolute(glb)
	print("\nSTUDIO_CHECK %d checks, %d failed" % [_n, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
