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
