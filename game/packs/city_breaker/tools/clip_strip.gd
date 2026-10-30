extends Node3D
## Film strip of a clip on a fighter, side-on, 6 frames: godot --path . --resolution 1800x600 res://game/packs/city_breaker/tools/clip_strip.tscn -- --fighter=vix --clip=jump --out=D:/Cache/strip.png
var _key := "vix"
var _clip := "jump"
var _out := "D:/Cache/clip_strip.png"
func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)   # never takes the keyboard
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fighter="): _key = a.substr(10)
		elif a.begins_with("--clip="): _clip = a.substr(7)
		elif a.begins_with("--out="): _out = a.substr(6)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.17, 0.2)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.72, 0.8)
	var we := WorldEnvironment.new(); we.environment = env; add_child(we)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40, 30, 0); sun.light_energy = 1.6; add_child(sun)
	var cam := Camera3D.new(); cam.fov = 28.0; add_child(cam)
	cam.position = Vector3(0, 1.3, 9.0); cam.look_at(Vector3(0, 1.2, 0), Vector3.UP)
	var ps := load(CBRoster.model_path(_key)) as PackedScene
	var models: Array = []
	var anims: Array = []
	var N := 6
	for i in N:
		var m := ps.instantiate() as Node3D
		add_child(m)
		m.position = Vector3(-4.4 + i * 1.76, 0, 0)
		m.rotation.y = deg_to_rad(90)   # side on, facing screen-right
		models.append(m)
		anims.append(m.find_children("*", "AnimationPlayer", true, false)[0])
		CBClipLib.install(anims[i], m, m.find_children("*", "Skeleton3D", true, false)[0])
	var len_: float = (anims[0] as AnimationPlayer).get_animation(_clip).length
	for i in N:
		var ap: AnimationPlayer = anims[i]
		ap.play(_clip)
		ap.seek(len_ * float(i) / float(N - 1) * 0.98, true)
		ap.pause()
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out)
	print("STRIP ", _clip, " len ", len_)
	get_tree().quit()
