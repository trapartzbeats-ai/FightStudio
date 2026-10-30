extends SceneTree
## Which way does each axis bend a joint? Renders one fighter with a joint turned +/- on X, Y and Z (the clip's Euler), close
## up, so joint limits are set from what the rig really does (knees never bend forward; probe, never guess).
##   godot --path . --script res://game/packs/city_breaker/tools/axis_probe.gd -- --who=vix --bones=handR,footR --amount=1.0 --out=C:/Dev/wrap_out/axes.png

const CELL := Vector2i(300, 300)

var who := "vix"
var bones: Array = ["handR", "footR"]
var amount := 1.0
var out := "C:/Dev/wrap_out/axes.png"


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	root.size = CELL
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--who="):
			who = a.substr(6)
		elif a.begins_with("--bones="):
			bones = Array(a.substr(8).split(","))
		elif a.begins_with("--amount="):
			amount = float(a.substr(9))
		elif a.begins_with("--out="):
			out = a.substr(6)
	_run.call_deferred()


func _run() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("1f1a24")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.8)
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	root.add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	root.add_child(cam)
	cam.current = true
	var label := Label.new()
	label.position = Vector2(6, 4)
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color("ffc93c"))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	root.add_child(label)
	var fp := CBWrapPose.new(who, root)
	var skel := fp.skel
	# rows: bone x view (front, side); columns: rest, +x, -x, +y, -y, +z, -z
	var cols := [Vector3.ZERO, Vector3(amount, 0, 0), Vector3(-amount, 0, 0), Vector3(0, amount, 0), Vector3(0, -amount, 0),
		Vector3(0, 0, amount), Vector3(0, 0, -amount)]
	var names := ["rest", "+x", "-x", "+y", "-y", "+z", "-z"]
	var sheet := Image.create(CELL.x * cols.size(), CELL.y * bones.size() * 2, false, Image.FORMAT_RGBA8)
	for r in bones.size():
		var b: String = bones[r]
		for v in 2:
			for c in cols.size():
				var pose := {b: cols[c]}
				CBClipLib.apply_pose(skel, pose)
				skel.force_update_all_bone_transforms()
				var bi := skel.find_bone(b)
				var at := (skel.global_transform * skel.get_bone_global_pose(bi)).origin
				var par := skel.get_bone_parent(bi)
				var pa := (skel.global_transform * skel.get_bone_global_pose(par)).origin if par >= 0 else at
				var size := maxf(at.distance_to(pa) * 3.2, 0.35)
				cam.size = size
				var dir := Vector3(0, 0, 1) if v == 0 else Vector3(1, 0, 0)
				cam.transform = Transform3D(Basis.looking_at(-dir, Vector3.UP), at + dir * 6.0)
				label.text = "%s %s %s" % [b, names[c], "front" if v == 0 else "side"]
				await process_frame
				await process_frame
				await RenderingServer.frame_post_draw
				var img := root.get_texture().get_image()
				img.convert(Image.FORMAT_RGBA8)
				sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(c * CELL.x, (r * 2 + v) * CELL.y))
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	sheet.save_png(out)
	print("saved ", out)
	quit()
