extends SceneTree
## A picture of every fighter's Collision Wrap: front and side, the model with its capsules drawn over it (colour = rank:
## body warm, limbs green, hands / feet cyan, tails / ears purple). Needs a window (not --headless); it never takes focus.
##   godot --path . --script res://game/packs/city_breaker/tools/wrap_sheet.gd -- --out=C:/Dev/wrap_out/wrap_sheet.png [--who=vix]
##   [--pose=<clip>:<frame>]   pose every fighter on that clip frame instead of the rest pose
##   [--shots=<key>:<clip>[:<frame>],...]   instead: those clip frames posed as in a match (planted on the floor), the parts
##   that clash drawn red, the floor drawn when the clip is planted; no frame = the frame with the deepest clash
##   [--video=<key>:<clip>[:<loops>]]   before / after frames (the clip as keyed | with the Body Solve) into <out> as a folder of
##   PNGs (frame_0000.png ...), clashing parts red; make an mp4 with ffmpeg. With --springs: tails / ears / crests swing on
##   their springs, left free (as before), right with the wrap's colliders and the after-springs pass; red = a chain in the body

var CELL := Vector2i(360, 440)   # --cell=WxH
const WRAPS := "res://game/packs/city_breaker/data/wraps/%s.collide.json"
const RANK_COL := [Color(1.0, 0.45, 0.15), Color(1.0, 0.6, 0.2), Color(1.0, 0.8, 0.3), Color(0.35, 0.9, 0.4), Color(0.25, 0.8, 0.6),
	Color(0.3, 0.85, 1.0), Color(0.75, 0.45, 1.0)]

var out := "C:/Dev/wrap_out/wrap_sheet.png"
var who := ""
var pose_clip := ""
var pose_frame := 0.0
var shots: Array = []
var video: PackedStringArray = []
var springs := false   # --springs: the video compares spring chains free (left) and with the wrap (right), both solved
var _seen := {}        # CBWrapPose -> [red pieces, capsules, worst], measured inside its skeleton update (after the springs)


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cell="):
			var wh := a.substr(7).split("x")
			CELL = Vector2i(int(wh[0]), int(wh[1]))
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--who="):
			who = a.substr(6)
		elif a.begins_with("--pose="):
			var p := a.substr(7).split(":")
			pose_clip = p[0]
			pose_frame = float(p[1]) if p.size() > 1 else 0.0
		elif a == "--springs":
			springs = true
		elif a.begins_with("--video="):
			video = a.substr(8).split(":")
		elif a.begins_with("--shots="):
			for one in a.substr(8).split(","):
				shots.append(one.split(":"))
	root.size = CELL
	_run.call_deferred()


func _cap_mesh(a: Vector3, b: Vector3, r: float, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = r
	cm.height = maxf(a.distance_to(b) + 2.0 * r, 2.0 * r + 0.0001)
	cm.radial_segments = 16
	cm.rings = 4
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	m.albedo_color = Color(col, 0.38)
	mi.material_override = m
	var y := (b - a).normalized() if a.distance_to(b) > 1e-5 else Vector3.UP
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	mi.transform = Transform3D(Basis(x, y, x.cross(y)), (a + b) * 0.5)
	return mi


func _shot() -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _run() -> void:
	if not video.is_empty():
		await _run_video()
		return
	if not shots.is_empty():
		await _run_shots()
		return
	var keys: Array = CBRoster.keys() if who == "" else [who]
	var sheet := Image.create(CELL.x * 2 * mini(keys.size(), 4), CELL.y * ceili(keys.size() / 4.0), false, Image.FORMAT_RGBA8)
	sheet.fill(Color("0d0b0f"))
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("1f1a24")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.75)
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	root.add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	root.add_child(cam)
	cam.current = true
	for n in keys.size():
		var key: String = keys[n]
		var model := (load(CBRoster.model_path(key)) as PackedScene).instantiate() as Node3D
		root.add_child(model)
		var skel := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		skel.reset_bone_poses()
		if pose_clip != "":
			var c := CBClipLib.load_clip(CBAnim.own(key, pose_clip))
			if not c.is_empty():
				var bones: Array = []
				for i in skel.get_bone_count():
					bones.append(skel.get_bone_name(i))
				CBClipLib.apply_pose(skel, CBClipLib.pose_at(c, pose_frame, bones))
		skel.force_update_all_bone_transforms()
		var body := RmtWrapBody.new(RmtWrapBody.load_wrap(WRAPS % key), skel)
		var caps := body.capsules()
		var holder := Node3D.new()
		root.add_child(holder)
		var lo := Vector3.INF
		var hi := -Vector3.INF
		for i in caps.size():
			var c: Array = caps[i]
			holder.add_child(_cap_mesh(c[0], c[1], c[2], RANK_COL[clampi(int(body.pieces[i]["rank"]), 0, RANK_COL.size() - 1)]))
			for p in [c[0], c[1]]:
				lo = lo.min((p as Vector3) - Vector3.ONE * float(c[2]))
				hi = hi.max((p as Vector3) + Vector3.ONE * float(c[2]))
		var mid := (lo + hi) * 0.5
		var h := maxf(hi.y - lo.y, maxf(hi.x - lo.x, hi.z - lo.z))
		cam.size = h * 1.12
		for v in 2:
			var dir := Vector3(0, 0, 1) if v == 0 else Vector3(1, 0, 0)
			cam.transform = Transform3D(Basis.looking_at(-dir, Vector3.UP), mid + dir * h * 3.0)
			var img: Image = await _shot()
			img.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(((n % 4) * 2 + v) * CELL.x, (n / 4) * CELL.y))
		print("%s: %d pieces" % [key, caps.size()])
		holder.queue_free()
		model.queue_free()
		await process_frame
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	sheet.save_png(out)
	print("saved ", out)
	quit()


func _stage() -> Camera3D:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("1f1a24")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.75)
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	root.add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	root.add_child(cam)
	cam.current = true
	return cam


## the frame of a clip with the deepest clash (self or floor)
func _worst_frame(fp: CBWrapPose, c: Dictionary) -> int:
	var best := 0
	var worst := -1.0
	for f in int(c.get("frames", 0)) + 1:
		var cl := fp.clashes(0.01, fp.pose(c, float(f)))
		for x in cl["self"] + cl["floor"]:
			if float(x["excess"]) > worst:
				worst = float(x["excess"])
				best = f
	return best


func _run_shots() -> void:
	var cam := _stage()
	var label := Label.new()
	label.position = Vector2(8, 6)
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color("f4efe6"))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	root.add_child(label)
	var per_row := 2
	var sheet := Image.create(CELL.x * 2 * mini(shots.size(), per_row), CELL.y * ceili(shots.size() / float(per_row)), false, Image.FORMAT_RGBA8)
	sheet.fill(Color("0d0b0f"))
	var floor_mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(4, 0.004, 4)
	floor_mesh.mesh = bm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(1.0, 0.48, 0.1, 0.35)
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	floor_mesh.material_override = fm
	root.add_child(floor_mesh)
	for n in shots.size():
		var sh: PackedStringArray = shots[n]
		var fp := CBWrapPose.new(sh[0], root)
		var c := CBClipLib.load_clip(sh[1])
		var f := int(sh[2]) if sh.size() > 2 else _worst_frame(fp, c)
		var planted := fp.pose(c, float(f))
		var cl := fp.clashes(0.01, planted)
		var caps: Array = cl["caps"]
		var red := {}
		var worst := 0.0
		var what := ""
		for x in cl["self"]:
			red[x["i"]] = true
			red[x["j"]] = true
			if float(x["excess"]) > worst:
				worst = float(x["excess"])
				what = "%s into %s" % [fp.body.pieces[x["i"]]["id"], fp.body.pieces[x["j"]]["id"]]
		for u in cl["floor"]:
			red[u["i"]] = true
			if float(u["excess"]) > worst:
				worst = float(u["excess"])
				what = "%s under the floor" % fp.body.pieces[u["i"]]["id"]
		var holder := Node3D.new()
		root.add_child(holder)
		var lo := Vector3.INF
		var hi := -Vector3.INF
		for i in caps.size():
			var cp: Array = caps[i]
			var mi := _cap_mesh(cp[0], cp[1], cp[2], Color(1, 0.1, 0.1) if red.has(i) else Color(0.6, 0.9, 1.0))
			(mi.material_override as StandardMaterial3D).albedo_color.a = 0.6 if red.has(i) else 0.12
			holder.add_child(mi)
			for p in [cp[0], cp[1]]:
				lo = lo.min((p as Vector3) - Vector3.ONE * float(cp[2]))
				hi = hi.max((p as Vector3) + Vector3.ONE * float(cp[2]))
		floor_mesh.visible = planted
		if planted:
			lo.y = minf(lo.y, -0.05)
		var mid := (lo + hi) * 0.5
		floor_mesh.position = Vector3(mid.x, 0, mid.z)
		var h := maxf(hi.y - lo.y, maxf(hi.x - lo.x, hi.z - lo.z))
		cam.size = h * 1.15
		label.text = "%s  %s  f%d
%s  %.1f cm" % [sh[0], sh[1], f, what if what != "" else "clean", worst * 100.0]
		for v in 2:
			var dir := Vector3(0, 0, 1) if v == 0 else Vector3(1, 0, 0)
			cam.transform = Transform3D(Basis.looking_at(-dir, Vector3.UP), mid + dir * h * 3.0)
			var img: Image = await _shot()
			img.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(((n % per_row) * 2 + v) * CELL.x, (n / per_row) * CELL.y))
		print("%s %s f%d: %s %.1f cm" % [sh[0], sh[1], f, what, worst * 100.0])
		holder.queue_free()
		fp.model.queue_free()
		await process_frame
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	sheet.save_png(out)
	print("saved ", out)
	quit()


func _caps_red(holder: Node3D, fp: CBWrapPose, planted: bool) -> float:
	for ch in holder.get_children():
		ch.queue_free()
	var cl := fp.clashes(0.01, planted)
	var caps: Array = cl["caps"]
	var red := {}
	var worst := 0.0
	for x in cl["self"]:
		red[x["i"]] = true
		red[x["j"]] = true
		worst = maxf(worst, float(x["excess"]))
	for u in cl["floor"]:
		red[u["i"]] = true
		worst = maxf(worst, float(u["excess"]))
	for i in red:
		var cp: Array = caps[i]
		var mi := _cap_mesh(cp[0], cp[1], cp[2], Color(1, 0.12, 0.1))
		(mi.material_override as StandardMaterial3D).albedo_color.a = 0.55
		holder.add_child(mi)
	return worst


## pieces of the spring chains that collide (tails, ears, crests, poms, fins)
func _chain_pieces(fp: CBWrapPose, sims: Dictionary) -> Dictionary:
	var fams: Array = ["tail", "ear", "crest", "pom", "fin"]
	var bones := {}
	for name in sims:
		var sim: SpringBoneSimulator3D = sims[name]
		if RmtWrapFit.family(sim.get_root_bone_name(0)) in fams:
			for j in sim.get_joint_count(0):
				bones[sim.get_joint_bone_name(0, j)] = true
	var out := {}
	for i in fp.body.pieces.size():
		if bones.has(fp.skel.get_bone_name(int(fp.body.pieces[i]["bone_idx"]))):
			out[i] = true
	return out


func _watch(fp: CBWrapPose, chain: Dictionary) -> void:
	fp.skel.skeleton_updated.connect(func() -> void:
		var caps := fp.body.capsules()
		var red := {}
		var worst := 0.0
		for x in fp.body.clashes(0.01, caps):
			if chain.has(x["i"]) != chain.has(x["j"]):
				red[x["i"]] = true
				red[x["j"]] = true
				worst = maxf(worst, float(x["excess"]))
		_seen[fp] = [red, caps, worst])


func _draw_seen(holder: Node3D, fp: CBWrapPose) -> float:
	for ch in holder.get_children():
		ch.queue_free()
	var s: Array = _seen.get(fp, [{}, [], 0.0])
	for i in s[0]:
		var cp: Array = s[1][i]
		var mi := _cap_mesh(cp[0], cp[1], cp[2], Color(1, 0.12, 0.1))
		(mi.material_override as StandardMaterial3D).albedo_color.a = 0.55
		holder.add_child(mi)
	return float(s[2])


func _run_video() -> void:
	var cam := _stage()
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = 32.0
	var label := Label.new()
	label.position = Vector2(10, 8)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color("f4efe6"))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	root.add_child(label)
	var key := video[0]
	var clip_name := video[1]
	var loops := int(video[2]) if video.size() > 2 else 1
	var c := CBClipLib.load_clip(clip_name)
	var a := CBWrapPose.new(key, root)
	var b := CBWrapPose.new(key, root)
	var ha := Node3D.new()
	var hb := Node3D.new()
	root.add_child(ha)
	root.add_child(hb)
	var floor_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6, 6)
	floor_mesh.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("3a2c46")
	floor_mesh.material_override = fm
	root.add_child(floor_mesh)
	var moves: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CBWrapPose.MOVES % key))
	var h := float(moves.get("height_m", 2.0))
	var look := Vector3(0, h * 0.5, 0)
	cam.transform = Transform3D(Basis.looking_at(Vector3(-0.55, -0.12, -1).normalized(), Vector3.UP), look + Vector3(0.55, 0.12, 1).normalized() * h * 3.4)
	DirAccess.make_dir_recursive_absolute(out)
	var n := int(c.get("frames", 0))
	if springs:
		var sa := CBSecondary.build_specs(a.skel, CBSecondary.all_specs(key), key, false)
		var sb := CBSecondary.build_specs(b.skel, CBSecondary.all_specs(key), key, true)
		_watch(a, _chain_pieces(a, sa))
		_watch(b, _chain_pieces(b, sb))
		a.solver.reset()
	b.solver.reset()
	for _w in 8:
		b.pose(c, 0.0, true)
	var k := 0
	for loop in loops:
		for f in n + 1:
			var pa := a.pose(c, float(f), springs)
			b.pose(c, float(f), true)
			if springs:
				for fp in [a, b]:
					(fp as CBWrapPose).skel.set_bone_pose_rotation(0, (fp as CBWrapPose).skel.get_bone_pose_rotation(0))
				await process_frame
			var frame := Image.create(CELL.x * 2, CELL.y, false, Image.FORMAT_RGBA8)
			for side in 2:
				var me: CBWrapPose = a if side == 0 else b
				var other: CBWrapPose = b if side == 0 else a
				me.model.visible = true
				other.model.visible = false
				(ha if side == 0 else hb).visible = true
				(hb if side == 0 else ha).visible = false
				var worst := _draw_seen(ha if side == 0 else hb, me) if springs else _caps_red(ha if side == 0 else hb, me, pa)
				label.text = "%s  %s  f%d
%s%s" % [key, clip_name, f, ("SPRINGS FREE" if springs else "AS KEYED") if side == 0 else ("SPRINGS + WRAP" if springs else "BODY SOLVE"),
					"   %.0f cm through" % (worst * 100.0) if worst > 0.0 else "   clean"]
				var img: Image = await _shot()
				img.convert(Image.FORMAT_RGBA8)
				frame.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(side * CELL.x, 0))
			frame.save_png("%s/frame_%04d.png" % [out, k])
			k += 1
	print("saved %d frames to %s" % [k, out])
	quit()
