extends Node3D
## FIGHT STUDIO: make effects, place sockets, pose and key animation on any City Breaker fighter, then save or export.
##   godot --path . res://game/packs/city_breaker/studio/studio.tscn
##
## Left   fighter, clip list (baked clips + your studio clips *), transport, frame slider
## Right  POSE (bone sliders, key frames, mirror) | SOCKETS (bone, along-bone point, offset; add/remove) | EFFECTS (RMT effects,
##        combos, cues on the clip's timeline)
## Save   clips -> data/clips/<name>.json (every fighter plays them), sockets -> data/sockets.json, cues -> data/clip_fx.json,
##        combos -> data/fx_combos.json, Export GLB -> fighter + all clips, Bake (Animato) -> into the fighter GLBs through Blender.
## Mouse  right-drag orbit, middle-drag pan, wheel zoom, left-click a socket dot to pick it. Space plays / pauses.

const Library := preload("res://addons/rmt_effects/core/library.gd")
const FIGHTERS := ["vix", "carter", "al", "slum", "guru", "bigbill", "rhino", "goat"]
const HINTS := {
	"leg": "X: - thigh forward, + back   Z: leg out to the side   Y: turn the leg",
	"knee": "X: + bends the knee (never negative: a knee does not bend forward)",
	"foot": "X: + points the toes down",
	"arm": "X: - raises the arm forward, + swings it back   Z: arm out to the side",
	"elbow": "X: - bends the elbow",
	"torso": "X: + leans forward   Y: twist   Z: side lean",
	"chest": "X: + leans forward   Y: twist   Z: side lean",
	"neck": "X: + nods forward   Y: turn",
	"head": "X: + nods forward   Y: turn the head   Z: tilt",
	"hips": "whole-body rotation about the hips: X + = forward somersault, Y = spin, Z = roll",
	"tail": "tail joint: X curls the tail up / down, Z swishes it side to side (the SECONDARY tab can make it move by itself)",
	"finger": "fingers: X curls them (use Fist / Open hand), Z spreads them",
	"tips": "fingertips: X curls the last joint",
	"thumb": "thumb: X curls it, Z swings it away from the hand",
	"crest": "crest / feather chain: X bends it forward and back, Z tilts it (SECONDARY can make it sway)",
	"pom": "pompom chain: X / Z tip it (SECONDARY can make it bounce)",
	"fin": "fin chain: X / Z tilt it",
	"ear": "ear: X folds it forward / back, Z tilts it sideways (SECONDARY can make it flop)",
}

var key := "vix"
var model: Node3D
var skel: Skeleton3D
var anim: AnimationPlayer
var cam := Camera3D.new()
var cam_target := Vector3(0, 1.0, 0)
var cam_dist := 4.6
var cam_yaw := 0.55
var cam_pitch := 0.12
var bones: Array = []
var sockets: Dictionary = {}
var sock_specs: Dictionary = {}          # working copy of this fighter's socket specs
var sock_sel := ""
var clip: Dictionary = {}                # the studio clip being edited ({} = a baked clip is selected)
var clip_name := ""
var frame := 0.0
var playing := false
var bone_sel := "hips"
var pose: Dictionary = {}
var fx_sel := ""
var cue_player := CBCues.Player.new()
var cues_work: Array = []
var combos_work: Dictionary = {}
var combo_layers: Array = []
var _loading := false
# the second body (victim / reactor) and which body the POSE tab edits
var actor_model: Node3D
var actor_skel: Skeleton3D
var rkey := "carter"
var rmodel: Node3D
var _other: Dictionary = {}              # the body that is NOT being edited: model, skel, anim, bones, clip, clip_name, pose
var show_reactor := false
var edit_reactor := false
var pair := {"reactor_clip": "", "dx": 1.0, "dy": 0.0, "dz": 0.0, "yaw": 180.0, "delay": 0}
var ui_pair_show: CheckBox
var ui_pair_fighter: OptionButton
var ui_pair_clips: ItemList
var ui_pair_edit: Label
var ui_pair_sl: Dictionary = {}
var sec_specs: Dictionary = {}           # working copy of this fighter's secondary-motion chains
var sec_sel := ""
var sec_joint := 0
var sec_on := false
var ui_sec_list: ItemList
var ui_sec_on: CheckBox
var ui_sec_enabled: CheckBox
var ui_sec_strength: HSlider
var ui_sec_extend: HSlider
var ui_sec_joint: OptionButton
var ui_sec_j: Dictionary = {}
var ui_sec_root: OptionButton
var ui_sec_end: OptionButton
var ui_sec_name: LineEdit
var ui_sec_ramp: Dictionary = {}
var react_work: Dictionary = {}         # hit-reaction settings being tuned (this fighter)
var actor_react: CBHitReact
var rreact: CBHitReact
var ui_react: Dictionary = {}
var ui_react_sock: OptionButton
var ui_react_dir: OptionButton
var ui_react_mag: HSlider
var ui_react_bone: OptionButton
var ui_react_scale: HSlider
const REACT_DIRS := [["from the front (pushed back)", Vector3(0, 0, -1)], ["from behind", Vector3(0, 0, 1)], ["from the left", Vector3(1, 0, 0)],
	["from the right", Vector3(-1, 0, 0)], ["from above (pushed down)", Vector3(0, -1, 0)], ["from below (lifted)", Vector3(0, 1, 0)]]
var prop_on := false
var prop_radius := 0.3
var prop_falloff := "smooth"
var prop_sub_only := true
var prop_from_socket := false
var ui_zone_r: HSlider
var ui_zone_f: OptionButton
var _zone_gizmo: MeshInstance3D
const FALLOFFS := ["smooth", "linear", "sharp", "constant"]
const SUB_PREFIX := ["tail", "ear", "finger", "tips", "thumb", "crest", "pom", "fin"]

# ui
var ui_fighter: OptionButton
var ui_clips: ItemList
var ui_play: Button
var ui_loop: CheckBox
var ui_speed: HSlider
var ui_frame: HSlider
var ui_frame_lbl: Label
var ui_status: Label
var ui_bone: OptionButton
var ui_rot: Array = []
var ui_hint: Label
var ui_dy: HSlider
var ui_keys: ItemList
var ui_len: SpinBox
var ui_s_list: ItemList
var ui_s_bone: OptionButton
var ui_s_to: OptionButton
var ui_s_t: HSlider
var ui_s_ex: Array = []
var ui_s_ground: CheckBox
var ui_s_name: LineEdit
var ui_fx_search: LineEdit
var ui_fx_list: ItemList
var ui_fx_scale: HSlider
var ui_fx_sock: OptionButton
var ui_fx_mode: OptionButton
var ui_fx_dur: HSlider
var ui_cues: ItemList
var ui_combo_name: LineEdit
var ui_combo_list: ItemList
var ui_combo_delay: HSlider
var ui_tabs: TabContainer


func _ready() -> void:
	ForgeCar.load_kit()
	RenderingServer.global_shader_parameter_add("car_inv", RenderingServer.GLOBAL_VAR_TYPE_TRANSFORM, Transform3D.IDENTITY)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fighter="):
			key = a.substr(10)
	_world()
	_build_ui()
	combos_work = CBFxRmt.combos().duplicate(true)
	_refresh_fx_list()
	_load_fighter(key)
	cue_player.on_fire = func(c: Dictionary) -> void: CBFxRmt.cue(self, self, c)
	if "--shot" in OS.get_cmdline_user_args():
		_demo_shot()


# ------------------------------------------------------------------ the 3D side

func _world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.14, 0.17)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.64, 0.72)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 35, 0)
	sun.light_energy = 1.5
	add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(14, 14)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.2, 0.21, 0.25)
	floor_mi.material_override = fm
	add_child(floor_mi)
	var grid := MeshInstance3D.new()
	var gm := ImmediateMesh.new()
	grid.mesh = gm
	gm.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(-7, 8):
		gm.surface_add_vertex(Vector3(i, 0.01, -7))
		gm.surface_add_vertex(Vector3(i, 0.01, 7))
		gm.surface_add_vertex(Vector3(-7, 0.01, i))
		gm.surface_add_vertex(Vector3(7, 0.01, i))
	gm.surface_end()
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.albedo_color = Color(0.3, 0.32, 0.38)
	grid.material_override = lm
	add_child(grid)
	cam.fov = 38.0
	add_child(cam)
	cam.current = true
	_cam()


func _cam() -> void:
	var dir := Vector3(sin(cam_yaw) * cos(cam_pitch), sin(cam_pitch), cos(cam_yaw) * cos(cam_pitch))
	cam.position = cam_target + dir * cam_dist
	cam.look_at(cam_target, Vector3.UP)


func _load_fighter(k: String) -> void:
	key = k
	if model != null:
		model.queue_free()
	var ps := load(CBRoster.model_path(k)) as PackedScene
	model = ps.instantiate() as Node3D
	add_child(model)
	skel = model.find_children("*", "Skeleton3D", true, false)[0]
	anim = model.find_children("*", "AnimationPlayer", true, false)[0]
	bones = []
	for i in skel.get_bone_count():
		bones.append(skel.get_bone_name(i))
	CBClipLib.install(anim, model, skel)
	actor_model = model
	actor_skel = skel
	edit_reactor = false
	react_work = CBHitReact.settings_for(k)
	actor_react = CBHitReact.attach(actor_skel, k)
	actor_react.cfg = react_work
	_load_reactor(rkey)
	_react_refresh_ui()
	var aabb := AABB()
	var first := true
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var b := (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		aabb = b if first else aabb.merge(b)
		first = false
	cam_target = Vector3(0, aabb.size.y * 0.5, 0)
	_load_socket_specs()
	_rebuild_sockets()
	sec_specs = CBSecondary.all_specs(k)
	sec_sel = ""
	_sec_rebuild()
	_refresh_clip_list()
	_fill_bone_options()
	_select_clip("fightIdle")
	_cam()


## the reactor body: a second fighter, placed relative to the actor by the pair settings
func _load_reactor(k: String) -> void:
	rkey = k
	if rmodel != null:
		rmodel.queue_free()
	var ps := load(CBRoster.model_path(k)) as PackedScene
	rmodel = ps.instantiate() as Node3D
	add_child(rmodel)
	var rs: Skeleton3D = rmodel.find_children("*", "Skeleton3D", true, false)[0]
	var ra: AnimationPlayer = rmodel.find_children("*", "AnimationPlayer", true, false)[0]
	var rb: Array = []
	for i in rs.get_bone_count():
		rb.append(rs.get_bone_name(i))
	CBClipLib.install(ra, rmodel, rs)
	rreact = CBHitReact.attach(rs, k)
	rreact.cfg = react_work
	_other = {"model": rmodel, "skel": rs, "anim": ra, "bones": rb, "clip": {}, "clip_name": "fightIdle", "pose": {}}
	rmodel.visible = show_reactor
	_place_reactor()
	_show_other()


## the reactor stands dx in front of the actor, dz to its right, dy up, turned yaw degrees (180 = facing the actor)
func _place_reactor() -> void:
	if rmodel == null or actor_model == null:
		return
	var b := actor_model.global_transform.basis
	var fwd := b.z
	var right := -b.x
	rmodel.global_position = actor_model.global_position + fwd * float(pair["dx"]) + right * float(pair["dz"]) + Vector3.UP * float(pair["dy"])
	rmodel.rotation = Vector3(0.0, actor_model.rotation.y + deg_to_rad(float(pair["yaw"])), 0.0)


## put the body that is not being edited on the frame the timeline is at (its own clip, `delay` frames later)
func _show_other() -> void:
	if not show_reactor or _other.is_empty():
		return
	var oa: AnimationPlayer = _other["anim"]
	var nm := str(_other["clip_name"])
	if oa == null or not oa.has_animation(nm):
		return
	var f := maxf(frame - float(pair["delay"]), 0.0)
	oa.active = true
	oa.play(nm)
	oa.seek(f / _other_fps(), true)
	oa.pause()


func _other_fps() -> float:
	return float((_other.get("clip", {}) as Dictionary).get("fps", 30)) if not (_other.get("clip", {}) as Dictionary).is_empty() else 30.0


## swap which body the POSE / clip controls edit
func _set_edit(reactor: bool) -> void:
	if reactor == edit_reactor or _other.is_empty():
		return
	_stop()
	var cur := {"model": model, "skel": skel, "anim": anim, "bones": bones, "clip": clip, "clip_name": clip_name, "pose": pose}
	model = _other["model"]
	skel = _other["skel"]
	anim = _other["anim"]
	bones = _other["bones"]
	clip = _other["clip"]
	clip_name = str(_other["clip_name"])
	pose = _other["pose"]
	_other = cur
	edit_reactor = reactor
	if ui_pair_edit != null:
		ui_pair_edit.text = "Editing: REACTOR (%s)" % rkey if reactor else "Editing: ACTOR (%s)" % key
	_refresh_clip_list()
	_fill_bone_options()
	_select_clip(clip_name)
	_say(("Now editing the REACTOR %s: its own clip, pose and keys (the actor plays alongside)." % rkey) if reactor else "Back to the actor.")


func _load_socket_specs() -> void:
	sock_specs = {}
	for name in (CBSockets.data().get("sockets", {}) as Dictionary):
		sock_specs[name] = CBSockets.spec(key, str(name))


func _rebuild_sockets() -> void:
	CBSockets.clear(actor_skel)
	sockets = CBSockets.build_specs(actor_skel, sock_specs, true)
	_mark_sock()
	_update_gizmo()
	if ui_s_list != null:
		_fill_socket_list()


func _mark_sock() -> void:
	for n in sockets:
		var node: Variant = sockets[n]
		if node is Node3D:
			var mi := (node as Node3D).get_node_or_null("marker") as MeshInstance3D
			if mi != null:
				var sel: bool = str(n) == sock_sel
				mi.scale = Vector3.ONE * (2.2 if sel else 1.0)
				(mi.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.9, 0.1) if sel else Color(1.0, 0.2, 0.9)


func _input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.pressed and _over_ui(mb.position):
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			cam_dist = maxf(1.2, cam_dist * 0.9)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			cam_dist = minf(14.0, cam_dist * 1.1)
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_pick_socket(mb.position)
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		if _over_ui(mm.position):
			return
		if mm.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			cam_yaw -= mm.relative.x * 0.008
			cam_pitch = clampf(cam_pitch + mm.relative.y * 0.006, -1.2, 1.4)
		elif mm.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			var right := cam.global_transform.basis.x
			cam_target += (-right * mm.relative.x + Vector3.UP * mm.relative.y) * 0.004 * cam_dist
	elif ev is InputEventKey and (ev as InputEventKey).pressed and not (ev as InputEventKey).echo:
		if (ev as InputEventKey).keycode == KEY_SPACE and not (get_viewport().gui_get_focus_owner() is LineEdit):
			_toggle_play()
			get_viewport().set_input_as_handled()


func _over_ui(p: Vector2) -> bool:
	var vp := get_viewport().get_visible_rect().size
	return p.x < 340.0 or p.x > vp.x - 420.0 or p.y > vp.y - 40.0


func _pick_socket(p: Vector2) -> void:
	var best := ""
	var bd := 22.0
	for n in sockets:
		var node: Variant = sockets[n]
		if node is Node3D:
			var sp := cam.unproject_position((node as Node3D).global_position)
			var d := sp.distance_to(p)
			if d < bd:
				bd = d
				best = str(n)
	if best != "":
		_select_socket(best)
		ui_tabs.current_tab = 1


func _process(delta: float) -> void:
	_cam()
	if playing and anim != null:
		var pos := anim.current_animation_position
		cue_player.tick(pos)
		var fps := _fps()
		frame = pos * fps
		_loading = true
		ui_frame.value = frame
		_loading = false
		ui_frame_lbl.text = _frame_text()
		_show_other()
		if not anim.is_playing():
			playing = false
			ui_play.text = "Play"


func _fps() -> float:
	return float(clip.get("fps", 30)) if not clip.is_empty() else 30.0


func _clip_len_frames() -> int:
	if not clip.is_empty():
		return int(clip.get("frames", 24))
	if anim != null and anim.has_animation(clip_name):
		return maxi(1, int(round(anim.get_animation(clip_name).length * 30.0)))
	return 30


func _frame_text() -> String:
	return "frame %d / %d   (%.2f s)" % [int(round(frame)), _clip_len_frames(), frame / _fps()]


# ------------------------------------------------------------------ UI building

func _label(parent: Node, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	parent.add_child(l)
	return l


func _button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _slider(parent: Node, text: String, lo: float, hi: float, step: float, val: float, cb: Callable) -> HSlider:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(86, 0)
	l.add_theme_font_size_override("font_size", 12)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = val
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(150, 18)
	row.add_child(s)
	var v := Label.new()
	v.custom_minimum_size = Vector2(46, 0)
	v.add_theme_font_size_override("font_size", 12)
	v.text = "%.3f" % val
	row.add_child(v)
	s.value_changed.connect(func(x: float) -> void:
		v.text = "%.3f" % x
		if not _loading:
			cb.call(x))
	return s


func _panel(anchor_right: bool) -> VBoxContainer:
	var layer := CanvasLayer.new()
	add_child(layer)
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.1, 0.13, 0.94)
	sb.set_content_margin_all(8)
	pc.add_theme_stylebox_override("panel", sb)
	layer.add_child(pc)
	if anchor_right:
		pc.anchor_left = 1.0
		pc.anchor_right = 1.0
		pc.anchor_bottom = 1.0
		pc.offset_left = -420
		pc.offset_bottom = -40
	else:
		pc.anchor_bottom = 1.0
		pc.offset_right = 340
		pc.offset_bottom = -40
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	pc.add_child(v)
	return v


func _build_ui() -> void:
	var left := _panel(false)
	_label(left, "FIGHT STUDIO").add_theme_font_size_override("font_size", 20)
	var row := HBoxContainer.new()
	left.add_child(row)
	_label(row, "Fighter ")
	ui_fighter = OptionButton.new()
	for f in FIGHTERS:
		ui_fighter.add_item(f)
	ui_fighter.item_selected.connect(func(i: int) -> void: _load_fighter(FIGHTERS[i]))
	row.add_child(ui_fighter)
	_label(left, "Clips   (* = studio clip)")
	ui_clips = ItemList.new()
	ui_clips.custom_minimum_size = Vector2(0, 250)
	ui_clips.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ui_clips.item_selected.connect(func(i: int) -> void: _select_clip(ui_clips.get_item_metadata(i)))
	left.add_child(ui_clips)
	var r2 := HBoxContainer.new()
	left.add_child(r2)
	_button(r2, "New clip", _new_clip)
	_button(r2, "Duplicate", _dup_clip)
	_button(r2, "Delete", _del_clip)
	var r3 := HBoxContainer.new()
	left.add_child(r3)
	ui_play = _button(r3, "Play", _toggle_play)
	_button(r3, "|<", func() -> void: _goto_frame(0))
	_button(r3, "<", func() -> void: _goto_frame(frame - 1))
	_button(r3, ">", func() -> void: _goto_frame(frame + 1))
	ui_loop = CheckBox.new()
	ui_loop.text = "loop"
	ui_loop.toggled.connect(func(on: bool) -> void:
		if not clip.is_empty() and not _loading:
			clip["loop"] = on
			_reinstall())
	r3.add_child(ui_loop)
	ui_speed = _slider(left, "speed", 0.1, 2.0, 0.05, 1.0, func(x: float) -> void: anim.speed_scale = x)
	ui_frame = _slider(left, "frame", 0.0, 60.0, 1.0, 0.0, func(x: float) -> void: _goto_frame(x))
	ui_frame_lbl = _label(left, "")
	var r4 := HBoxContainer.new()
	left.add_child(r4)
	_label(r4, "length (frames) ")
	ui_len = SpinBox.new()
	ui_len.min_value = 4
	ui_len.max_value = 240
	ui_len.value = 24
	ui_len.value_changed.connect(func(x: float) -> void:
		if not clip.is_empty() and not _loading:
			clip["frames"] = int(x)
			ui_frame.max_value = x
			_reinstall())
	r4.add_child(ui_len)
	_label(left, "Save / export")
	var r5 := HBoxContainer.new()
	left.add_child(r5)
	_button(r5, "Save all", _save_all)
	_button(r5, "Export GLB", _export_glb)
	_button(r5, "Bake (Animato)", _bake_animato)
	_button(r5, "Open folder", func() -> void: OS.shell_show_in_file_manager(ProjectSettings.globalize_path(CBClipLib.DIR)))

	var right := _panel(true)
	ui_tabs = TabContainer.new()
	ui_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(ui_tabs)
	_build_pose_tab()
	_build_socket_tab()
	_build_fx_tab()
	_build_pair_tab()
	_build_secondary_tab()
	_build_react_tab()

	var layer := CanvasLayer.new()
	add_child(layer)
	ui_status = Label.new()
	ui_status.anchor_top = 1.0
	ui_status.anchor_bottom = 1.0
	ui_status.anchor_right = 1.0
	ui_status.offset_top = -32
	ui_status.offset_left = 350
	ui_status.add_theme_font_size_override("font_size", 14)
	layer.add_child(ui_status)
	_say("Pick a clip, scrub the frame slider, switch to a studio clip (New clip) to pose and key it.")


func _say(t: String) -> void:
	if ui_status != null:
		ui_status.text = t


func _build_pose_tab() -> void:
	var v := VBoxContainer.new()
	v.name = "POSE"
	ui_tabs.add_child(v)
	_label(v, "Bone")
	ui_bone = OptionButton.new()
	ui_bone.item_selected.connect(func(i: int) -> void:
		bone_sel = ui_bone.get_item_text(i)
		_pose_to_sliders())
	v.add_child(ui_bone)
	ui_hint = _label(v, "")
	ui_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	ui_hint.custom_minimum_size = Vector2(380, 38)
	for ax in 3:
		var a := ax
		ui_rot.append(_slider(v, ["X rot", "Y rot", "Z rot"][ax], -3.4, 3.4, 0.01, 0.0, func(x: float) -> void: _set_rot(a, x)))
	ui_dy = _slider(v, "hips height", -0.9, 0.4, 0.005, 0.0, func(x: float) -> void:
		pose["_dy"] = x
		_apply())
	var r := HBoxContainer.new()
	v.add_child(r)
	_button(r, "KEY this frame", _key_frame)
	_button(r, "Delete key", _del_key)
	_button(r, "Neutral", _neutral)
	var r2 := HBoxContainer.new()
	v.add_child(r2)
	_button(r2, "Mirror L -> R", func() -> void: _mirror(true))
	_button(r2, "Mirror R -> L", func() -> void: _mirror(false))
	_button(r2, "Knees OK?", _knee_check)
	var rpp := HBoxContainer.new()
	v.add_child(rpp)
	var cb := CheckBox.new()
	cb.text = "proportional"
	cb.toggled.connect(func(on: bool) -> void: prop_on = on)
	rpp.add_child(cb)
	var cb2 := CheckBox.new()
	cb2.text = "sub-bones only"
	cb2.button_pressed = true
	cb2.toggled.connect(func(on: bool) -> void: prop_sub_only = on)
	rpp.add_child(cb2)
	var cb3 := CheckBox.new()
	cb3.text = "from socket zone"
	cb3.toggled.connect(func(on: bool) -> void: prop_from_socket = on)
	rpp.add_child(cb3)
	var rpf := HBoxContainer.new()
	v.add_child(rpf)
	_slider(rpf, "radius (m)", 0.02, 1.2, 0.01, prop_radius, func(x: float) -> void: prop_radius = x)
	var of := OptionButton.new()
	for f in FALLOFFS:
		of.add_item(f)
	of.item_selected.connect(func(i: int) -> void: prop_falloff = FALLOFFS[i])
	rpf.add_child(of)
	var rp := HBoxContainer.new()
	v.add_child(rp)
	_label(rp, "Parts: ")
	_button(rp, "Tail", func() -> void: _pick_bone("tail"))
	_button(rp, "Fingers L", func() -> void: _pick_bone("fingersL"))
	_button(rp, "Fingers R", func() -> void: _pick_bone("fingersR"))
	_button(rp, "Head", func() -> void: _pick_bone("head"))
	_button(rp, "Ear L", func() -> void: _pick_bone("earL"))
	_button(rp, "Ear R", func() -> void: _pick_bone("earR"))
	var rf := HBoxContainer.new()
	v.add_child(rf)
	_button(rf, "Fist L", func() -> void: _hand(true, 1.0))
	_button(rf, "Fist R", func() -> void: _hand(false, 1.0))
	_button(rf, "Open L", func() -> void: _hand(true, 0.0))
	_button(rf, "Open R", func() -> void: _hand(false, 0.0))
	_button(rf, "Tail curl", func() -> void: _tail_curl())
	_label(v, "Keys (click to jump)")
	ui_keys = ItemList.new()
	ui_keys.custom_minimum_size = Vector2(0, 120)
	ui_keys.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ui_keys.item_selected.connect(func(i: int) -> void: _goto_frame(float(ui_keys.get_item_metadata(i))))
	v.add_child(ui_keys)
	_label(v, "Pose with the sliders at a frame, press KEY. The in-betweens are interpolated. Spin = hips rotation.").autowrap_mode = TextServer.AUTOWRAP_WORD


func _build_socket_tab() -> void:
	var v := VBoxContainer.new()
	v.name = "SOCKETS"
	ui_tabs.add_child(v)
	_label(v, "Sockets (click a dot in the view too)")
	ui_s_list = ItemList.new()
	ui_s_list.custom_minimum_size = Vector2(0, 130)
	ui_s_list.item_selected.connect(func(i: int) -> void: _select_socket(str(ui_s_list.get_item_metadata(i))))
	v.add_child(ui_s_list)
	var r := HBoxContainer.new()
	v.add_child(r)
	ui_s_name = LineEdit.new()
	ui_s_name.placeholder_text = "new socket name"
	ui_s_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(ui_s_name)
	_button(r, "Add", _add_socket)
	_button(r, "Remove", _remove_socket)
	var rq := HBoxContainer.new()
	v.add_child(rq)
	_button(rq, "+ Ground centre", _add_ground_mid)
	_button(rq, "+ Both soles", _add_soles)
	_label(v, "Bone")
	ui_s_bone = OptionButton.new()
	ui_s_bone.item_selected.connect(func(i: int) -> void: _edit_spec("bone", ui_s_bone.get_item_text(i)))
	v.add_child(ui_s_bone)
	_label(v, "Toward bone (the point slides along bone -> this)")
	ui_s_to = OptionButton.new()
	ui_s_to.item_selected.connect(func(i: int) -> void: _edit_spec("to", ui_s_to.get_item_text(i) if i > 0 else ""))
	v.add_child(ui_s_to)
	ui_s_t = _slider(v, "along (t)", 0.0, 1.0, 0.01, 0.0, func(x: float) -> void: _edit_spec("t", x))
	for ax in 3:
		var a := ax
		ui_s_ex.append(_slider(v, ["offset X", "offset Y", "offset Z"][ax], -0.5, 0.5, 0.005, 0.0, func(_x: float) -> void: _edit_extra()))
	ui_zone_r = _slider(v, "zone radius", 0.0, 1.0, 0.01, 0.0, func(x: float) -> void: _edit_zone("radius", x))
	var rz := HBoxContainer.new()
	v.add_child(rz)
	_label(rz, "zone falloff ")
	ui_zone_f = OptionButton.new()
	for f in FALLOFFS:
		ui_zone_f.add_item(f)
	ui_zone_f.item_selected.connect(func(i: int) -> void: _edit_zone("falloff", FALLOFFS[i]))
	rz.add_child(ui_zone_f)
	ui_s_ground = CheckBox.new()
	ui_s_ground.text = "ground socket (the foot's x/z on the floor)"
	ui_s_ground.toggled.connect(func(on: bool) -> void: _edit_spec("ground", on))
	v.add_child(ui_s_ground)
	var r2 := HBoxContainer.new()
	v.add_child(r2)
	_button(r2, "Save for ALL fighters", func() -> void: _save_sockets(false))
	_button(r2, "Save for this fighter", func() -> void: _save_sockets(true))
	_button(r2, "Reset", func() -> void:
		_load_socket_specs()
		_rebuild_sockets()
		_say("Sockets reset to the saved ones."))
	_label(v, "Offsets are metres in the bone's own axes. 'for this fighter' stores only what differs.").autowrap_mode = TextServer.AUTOWRAP_WORD


func _build_secondary_tab() -> void:
	var v := VBoxContainer.new()
	v.name = "SECONDARY"
	ui_tabs.add_child(v)
	_label(v, "Secondary motion: tails, ears, fingers swing by themselves from how the character moves (no animation needed).").autowrap_mode = TextServer.AUTOWRAP_WORD
	ui_sec_on = CheckBox.new()
	ui_sec_on.text = "physics preview ON (turn off while posing)"
	ui_sec_on.toggled.connect(func(on: bool) -> void:
		sec_on = on
		_sec_rebuild())
	v.add_child(ui_sec_on)
	ui_sec_list = ItemList.new()
	ui_sec_list.custom_minimum_size = Vector2(0, 84)
	ui_sec_list.item_selected.connect(func(i: int) -> void: _sec_select(str(ui_sec_list.get_item_metadata(i))))
	v.add_child(ui_sec_list)
	ui_sec_enabled = CheckBox.new()
	ui_sec_enabled.text = "this chain is on"
	ui_sec_enabled.toggled.connect(func(on: bool) -> void: _sec_edit("enabled", on))
	v.add_child(ui_sec_enabled)
	ui_sec_strength = _slider(v, "strength", 0.0, 1.0, 0.01, 1.0, func(x: float) -> void: _sec_edit("strength", x))
	ui_sec_extend = _slider(v, "tip length (m)", 0.0, 0.8, 0.01, 0.0, func(x: float) -> void: _sec_edit("extend", x))
	var rj := HBoxContainer.new()
	v.add_child(rj)
	_label(rj, "joint ")
	ui_sec_joint = OptionButton.new()
	ui_sec_joint.item_selected.connect(func(i: int) -> void:
		sec_joint = i
		_sec_to_sliders())
	rj.add_child(ui_sec_joint)
	for spec in [["stiffness", "stiffness", 0.0, 5.0, 0.01], ["drag", "drag (damping)", 0.0, 1.0, 0.01], ["gravity", "gravity", 0.0, 2.0, 0.01]]:
		var k: String = spec[0]
		ui_sec_j[k] = _slider(v, spec[1], spec[2], spec[3], spec[4], 0.0, func(x: float) -> void: _sec_edit_joint(k, x))
	_label(v, "Ramp the whole chain (root -> tip):")
	for spec in [["stiffness", 0.0, 5.0], ["drag", 0.0, 1.0], ["gravity", 0.0, 2.0]]:
		var k2: String = spec[0]
		var row := HBoxContainer.new()
		v.add_child(row)
		_label(row, k2 + " ")
		var a := SpinBox.new()
		a.min_value = spec[1]
		a.max_value = spec[2]
		a.step = 0.05
		a.value = 1.0
		a.custom_minimum_size = Vector2(80, 0)
		row.add_child(a)
		_label(row, "->")
		var b := SpinBox.new()
		b.min_value = spec[1]
		b.max_value = spec[2]
		b.step = 0.05
		b.value = 0.5
		b.custom_minimum_size = Vector2(80, 0)
		row.add_child(b)
		_button(row, "Apply", func() -> void: _sec_ramp(k2, a.value, b.value))
		ui_sec_ramp[k2] = [a, b]
	var r2 := HBoxContainer.new()
	v.add_child(r2)
	_button(r2, "Shake test", _sec_shake)
	_button(r2, "Reset", func() -> void:
		CBSecondary.reset(actor_skel))
	_button(r2, "Save ALL fighters", func() -> void: _sec_save(false))
	_button(r2, "Save this fighter", func() -> void: _sec_save(true))
	var r3 := HBoxContainer.new()
	v.add_child(r3)
	ui_sec_name = LineEdit.new()
	ui_sec_name.placeholder_text = "new chain name"
	ui_sec_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r3.add_child(ui_sec_name)
	ui_sec_root = OptionButton.new()
	r3.add_child(ui_sec_root)
	ui_sec_end = OptionButton.new()
	r3.add_child(ui_sec_end)
	var r4 := HBoxContainer.new()
	v.add_child(r4)
	_button(r4, "Add chain (root -> end bone)", _sec_add)
	_button(r4, "Remove chain", _sec_remove)


## the joints of a chain, root to end
func _sec_joints(sp: Dictionary) -> Array:
	var out: Array = []
	var i := actor_skel.find_bone(str(sp.get("end", "")))
	var r := actor_skel.find_bone(str(sp.get("root", "")))
	var guard := 0
	while i >= 0 and guard < 40:
		out.push_front(actor_skel.get_bone_name(i))
		if i == r:
			break
		i = actor_skel.get_bone_parent(i)
		guard += 1
	return out


func _sec_refresh_list() -> void:
	if ui_sec_list == null:
		return
	ui_sec_list.clear()
	for n in sec_specs:
		var i := ui_sec_list.add_item("%s%s   %s -> %s" % ["" if bool(sec_specs[n].get("enabled", true)) else "(off) ", n, sec_specs[n].get("root", "?"), sec_specs[n].get("end", "?")])
		ui_sec_list.set_item_metadata(i, str(n))
		if str(n) == sec_sel:
			ui_sec_list.select(i)
	if ui_sec_root != null and ui_sec_root.item_count == 0:
		for b in bones:
			ui_sec_root.add_item(b)
			ui_sec_end.add_item(b)


## rebuild the simulators under the actor skeleton (preview ON) or take them away (OFF)
func _sec_rebuild() -> void:
	if actor_skel == null:
		return
	CBSecondary.clear(actor_skel)
	if sec_on:
		CBSecondary.build_specs(actor_skel, sec_specs)
	_sec_refresh_list()


func _sec_select(n: String) -> void:
	sec_sel = n
	sec_joint = 0
	var sp: Dictionary = sec_specs.get(n, {})
	_loading = true
	ui_sec_enabled.button_pressed = bool(sp.get("enabled", true))
	ui_sec_strength.value = float(sp.get("strength", 1.0))
	ui_sec_extend.value = float(sp.get("extend", 0.0))
	ui_sec_joint.clear()
	for j in _sec_joints(sp):
		ui_sec_joint.add_item(j)
	ui_sec_joint.select(0)
	_loading = false
	_sec_to_sliders()
	_say("Chain %s: set stiffness / drag / gravity per joint (root to tip), then Shake test with the preview on." % n)


func _sec_to_sliders() -> void:
	if sec_sel == "":
		return
	var sp: Dictionary = sec_specs[sec_sel]
	_loading = true
	for k in ui_sec_j:
		var val := CBSecondary.at(sp.get(k), sec_joint, 0.0)
		(ui_sec_j[k] as HSlider).value = val
		((ui_sec_j[k] as HSlider).get_parent().get_child(2) as Label).text = "%.3f" % val
	_loading = false


func _sec_edit(k: String, v: Variant) -> void:
	if sec_sel == "" or _loading:
		return
	sec_specs[sec_sel][k] = v
	_sec_rebuild()


func _sec_edit_joint(k: String, x: float) -> void:
	if sec_sel == "" or _loading:
		return
	var sp: Dictionary = sec_specs[sec_sel]
	var n := _sec_joints(sp).size()
	var arr: Array = []
	for j in n:
		arr.append(CBSecondary.at(sp.get(k), j, 0.0))
	arr[sec_joint] = snappedf(x, 0.001)
	sp[k] = arr
	_sec_rebuild()


func _sec_ramp(k: String, a: float, b: float) -> void:
	if sec_sel == "":
		return
	var sp: Dictionary = sec_specs[sec_sel]
	var n := _sec_joints(sp).size()
	var arr: Array = []
	for j in n:
		arr.append(snappedf(lerpf(a, b, float(j) / float(maxi(n - 1, 1))), 0.001))
	sp[k] = arr
	_sec_to_sliders()
	_sec_rebuild()
	_say("%s ramped %.2f -> %.2f along %s." % [k, a, b, sec_sel])


## move the whole character back and forth so the chains have something to react to
func _sec_shake() -> void:
	if not sec_on:
		ui_sec_on.button_pressed = true
	var tw := create_tween()
	var x0 := actor_model.position.x
	for i in 4:
		tw.tween_property(actor_model, "position:x", x0 + (1.4 if i % 2 == 0 else -1.4), 0.28)
	tw.tween_property(actor_model, "position:x", x0, 0.3)
	_say("Shaking the character: watch the chains swing and settle. Adjust and shake again.")


func _sec_add() -> void:
	var n := ui_sec_name.text.strip_edges().replace(" ", "_")
	if n == "" or sec_specs.has(n):
		_say("Give the new chain a unique name.")
		return
	sec_specs[n] = {"enabled": true, "root": ui_sec_root.get_item_text(maxi(ui_sec_root.selected, 0)), "end": ui_sec_end.get_item_text(maxi(ui_sec_end.selected, 0)),
		"extend": 0.1, "strength": 1.0, "stiffness": 1.0, "drag": 0.25, "gravity": 0.4}
	ui_sec_name.text = ""
	_sec_rebuild()
	_sec_select(n)


func _sec_remove() -> void:
	if sec_sel == "":
		return
	sec_specs.erase(sec_sel)
	sec_sel = ""
	_sec_rebuild()


func _sec_save(this_fighter_only: bool) -> void:
	var d: Dictionary = CBSecondary.data().duplicate(true)
	if this_fighter_only:
		var fighters: Dictionary = d.get("fighters", {})
		var over: Dictionary = {}
		for n in sec_specs:
			if sec_specs[n] != (d["chains"] as Dictionary).get(n, {}):
				over[n] = sec_specs[n]
		if over.is_empty():
			fighters.erase(key)
		else:
			fighters[key] = over
		d["fighters"] = fighters
	else:
		d["chains"] = sec_specs.duplicate(true)
	_say(("Secondary motion saved (%s)." % ("only " + key if this_fighter_only else "all fighters")) if CBSecondary.save_data(d) == OK else "Could not save secondary.json")


func _build_react_tab() -> void:
	var v := VBoxContainer.new()
	v.name = "REACT"
	ui_tabs.add_child(v)
	_label(v, "Body reactions: where an attack zone lands, that part of the victim moves with the blow, the bones around it follow in proportion, a spring settles them; the attacker's striking limb recoils.").autowrap_mode = TextServer.AUTOWRAP_WORD
	for spec in [["strength", "strength", 0.0, 3.0, 0.01], ["radius", "radius (m)", 0.05, 1.2, 0.01], ["frequency", "spring Hz", 2.0, 20.0, 0.1],
			["damping", "damping", 0.1, 1.5, 0.01], ["up", "pull up chain", 0.0, 1.0, 0.01], ["up_steps", "joints up", 0.0, 6.0, 1.0],
			["down", "pull down chain", 0.0, 1.0, 0.01], ["recoil", "attacker recoil", 0.0, 1.0, 0.01], ["max_angle", "max swing (rad)", 0.1, 1.5, 0.01]]:
		var k: String = spec[0]
		ui_react[k] = _slider(v, spec[1], spec[2], spec[3], spec[4], float(react_work.get(k, 0.0)), func(x: float) -> void: _react_edit(k, x))
	var rf := HBoxContainer.new()
	v.add_child(rf)
	_label(rf, "falloff ")
	var of := OptionButton.new()
	for f in FALLOFFS:
		of.add_item(f)
	of.item_selected.connect(func(i: int) -> void: _react_edit("falloff", FALLOFFS[i]))
	rf.add_child(of)
	_label(v, "Per-bone share (a heavy torso gives less than a head):")
	var rb := HBoxContainer.new()
	v.add_child(rb)
	ui_react_bone = OptionButton.new()
	ui_react_bone.item_selected.connect(func(_i: int) -> void: _react_bone_to_slider())
	rb.add_child(ui_react_bone)
	ui_react_scale = _slider(v, "bone share", 0.0, 2.0, 0.01, 1.0, func(x: float) -> void:
		var bs: Dictionary = react_work.get("bone_scale", {})
		bs[ui_react_bone.get_item_text(ui_react_bone.selected)] = snappedf(x, 0.01)
		react_work["bone_scale"] = bs)
	_label(v, "Try it:")
	var r1 := HBoxContainer.new()
	v.add_child(r1)
	_label(r1, "hit at ")
	ui_react_sock = OptionButton.new()
	r1.add_child(ui_react_sock)
	ui_react_dir = OptionButton.new()
	for d in REACT_DIRS:
		ui_react_dir.add_item(d[0])
	r1.add_child(ui_react_dir)
	ui_react_mag = _slider(v, "blow strength", 0.2, 1.5, 0.01, 0.8, func(_x: float) -> void: pass)
	var r2 := HBoxContainer.new()
	v.add_child(r2)
	_button(r2, "Hit ACTOR", func() -> void: _react_try(false))
	_button(r2, "Hit REACTOR (actor hand recoils)", func() -> void: _react_try(true))
	var r3 := HBoxContainer.new()
	v.add_child(r3)
	_button(r3, "Save ALL fighters", func() -> void: _react_save(false))
	_button(r3, "Save this fighter", func() -> void: _react_save(true))
	_label(v, "Pose-hold: pause the clip, hit the part you want, tune until it reads as a natural flinch. Stronger blow = bigger flinch.").autowrap_mode = TextServer.AUTOWRAP_WORD


func _react_refresh_ui() -> void:
	if ui_react.is_empty():
		return
	_loading = true
	for k in ui_react:
		(ui_react[k] as HSlider).value = float(react_work.get(k, 0.0))
		((ui_react[k] as HSlider).get_parent().get_child(2) as Label).text = "%.3f" % float(react_work.get(k, 0.0))
	ui_react_bone.clear()
	for b in bones:
		ui_react_bone.add_item(b)
	ui_react_sock.clear()
	for n in sock_specs:
		ui_react_sock.add_item(str(n))
	_loading = false
	_react_bone_to_slider()


func _react_bone_to_slider() -> void:
	if ui_react_bone == null or ui_react_bone.item_count == 0:
		return
	_loading = true
	var v := float((react_work.get("bone_scale", {}) as Dictionary).get(ui_react_bone.get_item_text(ui_react_bone.selected), 1.0))
	ui_react_scale.value = v
	(ui_react_scale.get_parent().get_child(2) as Label).text = "%.3f" % v
	_loading = false


func _react_edit(k: String, v: Variant) -> void:
	if _loading:
		return
	react_work[k] = v


func _react_try(with_recoil: bool) -> void:
	var sock := ui_react_sock.get_item_text(maxi(ui_react_sock.selected, 0)) if ui_react_sock.item_count > 0 else "chest"
	var local_dir: Vector3 = REACT_DIRS[ui_react_dir.selected][1]
	var mag := ui_react_mag.value
	if with_recoil:
		if not show_reactor:
			ui_pair_show.button_pressed = true
		var rs: Skeleton3D = rmodel.find_children("*", "Skeleton3D", true, false)[0]
		var bi := rs.find_bone("chest")
		var spot := rs.global_transform * rs.get_bone_global_pose(bi).origin
		var push: Vector3 = rmodel.global_transform.basis * local_dir
		rreact.impact(spot, push, mag)
		actor_react.recoil("handR", -push, mag)
		_say("Reactor hit in the chest; the actor's right hand recoils.")
		return
	var node: Variant = sockets.get(sock)
	var at := actor_model.global_position + Vector3(0, 1.4, 0)
	if node is Node3D:
		at = (node as Node3D).global_position
	elif node is Dictionary:
		var idx := actor_skel.find_bone(str((node as Dictionary).get("bone", "")))
		if idx >= 0:
			at = actor_skel.global_transform * actor_skel.get_bone_global_pose(idx).origin
	var dir: Vector3 = actor_model.global_transform.basis * local_dir
	actor_react.impact(at, dir, mag)
	_say("Hit the actor at %s %s." % [sock, REACT_DIRS[ui_react_dir.selected][0]])


func _react_save(this_fighter_only: bool) -> void:
	var d: Dictionary = CBHitReact.data().duplicate(true)
	if this_fighter_only:
		var fighters: Dictionary = d.get("fighters", {})
		var over: Dictionary = {}
		var shared: Dictionary = d.get("settings", {})
		for k in react_work:
			if k == "bone_scale":
				var diff: Dictionary = {}
				for b in (react_work["bone_scale"] as Dictionary):
					if float((react_work["bone_scale"] as Dictionary)[b]) != float((shared.get("bone_scale", {}) as Dictionary).get(b, 1.0)):
						diff[b] = react_work["bone_scale"][b]
				if not diff.is_empty():
					over["bone_scale"] = diff
			elif react_work[k] != shared.get(k):
				over[k] = react_work[k]
		if over.is_empty():
			fighters.erase(key)
		else:
			fighters[key] = over
		d["fighters"] = fighters
	else:
		d["settings"] = react_work.duplicate(true)
	_say(("Body reaction saved (%s)." % ("only " + key if this_fighter_only else "all fighters")) if CBHitReact.save_data(d) == OK else "Could not save hit_react.json")


func _build_pair_tab() -> void:
	var v := VBoxContainer.new()
	v.name = "PAIR"
	ui_tabs.add_child(v)
	_label(v, "Stage a victim / reactor next to the actor (grabs, throws, combos): both are animated by hand.").autowrap_mode = TextServer.AUTOWRAP_WORD
	ui_pair_show = CheckBox.new()
	ui_pair_show.text = "show the reactor"
	ui_pair_show.toggled.connect(func(on: bool) -> void:
		show_reactor = on
		if rmodel != null:
			rmodel.visible = on
		_place_reactor()
		_show_other())
	v.add_child(ui_pair_show)
	var r := HBoxContainer.new()
	v.add_child(r)
	_label(r, "Reactor ")
	ui_pair_fighter = OptionButton.new()
	for f in FIGHTERS:
		ui_pair_fighter.add_item(f)
	ui_pair_fighter.select(FIGHTERS.find(rkey))
	ui_pair_fighter.item_selected.connect(func(i: int) -> void:
		if edit_reactor:
			_set_edit(false)
		_load_reactor(FIGHTERS[i])
		_refresh_pair_clips())
	r.add_child(ui_pair_fighter)
	ui_pair_edit = _label(v, "Editing: ACTOR")
	var r2 := HBoxContainer.new()
	v.add_child(r2)
	_button(r2, "Edit ACTOR", func() -> void: _set_edit(false))
	_button(r2, "Edit REACTOR", func() -> void:
		ui_pair_show.button_pressed = true
		_set_edit(true))
	_label(v, "Reactor clip (what the victim plays)")
	ui_pair_clips = ItemList.new()
	ui_pair_clips.custom_minimum_size = Vector2(0, 120)
	ui_pair_clips.item_selected.connect(func(i: int) -> void: _pair_pick_clip(str(ui_pair_clips.get_item_metadata(i))))
	v.add_child(ui_pair_clips)
	for spec in [["dx", "in front (m)", -1.0, 3.0, 0.01], ["dy", "height (m)", -1.0, 2.0, 0.01], ["dz", "to the right (m)", -2.0, 2.0, 0.01], ["yaw", "turn (deg)", -180.0, 180.0, 1.0], ["delay", "delay (frames)", 0.0, 60.0, 1.0]]:
		var k: String = spec[0]
		ui_pair_sl[k] = _slider(v, spec[1], spec[2], spec[3], spec[4], float(pair[k]), func(x: float) -> void:
			pair[k] = x
			_place_reactor()
			_show_other())
	var r3 := HBoxContainer.new()
	v.add_child(r3)
	_button(r3, "New reactor clip", _new_reactor_clip)
	_button(r3, "Save pair", _save_pair)
	_button(r3, "Clear pair", _clear_pair)
	_label(v, "Save pair: when the ACTOR's clip plays in a fight and connects, the victim is put here and plays the reactor clip. Frames line up on one timeline.").autowrap_mode = TextServer.AUTOWRAP_WORD
	_refresh_pair_clips()


func _refresh_pair_clips() -> void:
	if ui_pair_clips == null or _other.is_empty():
		return
	ui_pair_clips.clear()
	var ra: AnimationPlayer = anim if edit_reactor else _other["anim"]
	var names: Array = []
	for n in ra.get_animation_list():
		names.append(str(n))
	names.sort()
	var studio := CBClipLib.list_clips()
	for n in names:
		var i := ui_pair_clips.add_item(("* " if studio.has(n) else "") + n)
		ui_pair_clips.set_item_metadata(i, n)
		if n == str(pair.get("reactor_clip", "")):
			ui_pair_clips.select(i)


func _pair_pick_clip(n: String) -> void:
	pair["reactor_clip"] = n
	if edit_reactor:
		_select_clip(n)
	else:
		_other["clip_name"] = n
		_other["clip"] = CBClipLib.load_clip(n) if CBClipLib.list_clips().has(n) else {}
		_show_other()


func _actor_clip_name() -> String:
	return str(_other["clip_name"]) if edit_reactor else clip_name


func _new_reactor_clip() -> void:
	var base := _actor_clip_name()
	var n := base + "_react"
	while CBClipLib.list_clips().has(n) or anim.has_animation(n):
		n += "x"
	var c := CBClipLib.blank(n)
	c["frames"] = _clip_len_frames()
	CBClipLib.save_clip(c)
	_install_clip(c, anim, skel, model)
	_install_clip(c, _other["anim"], _other["skel"], _other["model"])
	pair["reactor_clip"] = n
	ui_pair_show.button_pressed = true
	if not edit_reactor:
		_other["clip_name"] = n
		_other["clip"] = c
		_set_edit(true)
	else:
		_refresh_clip_list()
		_select_clip(n)
	_refresh_pair_clips()
	_say("Reactor clip %s created: pose the victim and KEY it, then Save pair." % n)


func _save_pair() -> void:
	var an := _actor_clip_name()
	var rc := str(pair.get("reactor_clip", ""))
	if rc == "":
		_say("Pick or create a reactor clip first.")
		return
	CBPairs.set_pair(an, {"reactor_clip": rc, "dx": snappedf(float(pair["dx"]), 0.01), "dy": snappedf(float(pair["dy"]), 0.01),
		"dz": snappedf(float(pair["dz"]), 0.01), "yaw": float(pair["yaw"]), "delay": int(pair["delay"])})
	_say("Pair saved: %s -> victim plays %s (data/pairs.json)." % [an, rc] if CBPairs.save() == OK else "Could not save pairs.json")


func _clear_pair() -> void:
	CBPairs.set_pair(_actor_clip_name(), {})
	CBPairs.save()
	_say("Pair cleared for %s." % _actor_clip_name())


func _build_fx_tab() -> void:
	var v := VBoxContainer.new()
	v.name = "EFFECTS"
	ui_tabs.add_child(v)
	ui_fx_search = LineEdit.new()
	ui_fx_search.placeholder_text = "search effects (150 RMT effects + your combos *)"
	ui_fx_search.text_changed.connect(func(_t: String) -> void: _refresh_fx_list())
	v.add_child(ui_fx_search)
	ui_fx_list = ItemList.new()
	ui_fx_list.custom_minimum_size = Vector2(0, 118)
	ui_fx_list.item_selected.connect(func(i: int) -> void: fx_sel = str(ui_fx_list.get_item_metadata(i)))
	v.add_child(ui_fx_list)
	var r := HBoxContainer.new()
	v.add_child(r)
	_label(r, "on socket ")
	ui_fx_sock = OptionButton.new()
	r.add_child(ui_fx_sock)
	ui_fx_mode = OptionButton.new()
	ui_fx_mode.add_item("burst")
	ui_fx_mode.add_item("follow")
	r.add_child(ui_fx_mode)
	ui_fx_scale = _slider(v, "scale", 0.2, 4.0, 0.05, 1.0, func(_x: float) -> void: pass)
	ui_fx_dur = _slider(v, "follow secs", 0.1, 3.0, 0.05, 0.6, func(_x: float) -> void: pass)
	var r2 := HBoxContainer.new()
	v.add_child(r2)
	_button(r2, "Preview", _fx_preview)
	_button(r2, "Open RMT effect editor", func() -> void: get_tree().change_scene_to_file("res://addons/rmt_effects/studio/studio.tscn"))
	_label(v, "CUES on this clip (play when the clip passes that frame)")
	ui_cues = ItemList.new()
	ui_cues.custom_minimum_size = Vector2(0, 66)
	ui_cues.item_selected.connect(func(i: int) -> void: _goto_frame(float((cues_work[i] as Dictionary)["t"]) * _fps()))
	v.add_child(ui_cues)
	var r3 := HBoxContainer.new()
	v.add_child(r3)
	_button(r3, "Add cue at this frame", _add_cue)
	_button(r3, "Remove cue", _remove_cue)
	_button(r3, "Play clip with cues", _play_with_cues)
	_label(v, "COMBO (stack effects into one named effect)")
	ui_combo_name = LineEdit.new()
	ui_combo_name.placeholder_text = "combo name"
	v.add_child(ui_combo_name)
	ui_combo_delay = _slider(v, "layer delay s", 0.0, 1.0, 0.01, 0.0, func(_x: float) -> void: pass)
	ui_combo_list = ItemList.new()
	ui_combo_list.custom_minimum_size = Vector2(0, 40)
	v.add_child(ui_combo_list)
	var r4 := HBoxContainer.new()
	v.add_child(r4)
	_button(r4, "Add selected effect as layer", _combo_add_layer)
	_button(r4, "Save combo", _combo_save)
	_button(r4, "Clear", func() -> void:
		combo_layers = []
		_combo_refresh())


# ------------------------------------------------------------------ clips + transport

func _refresh_clip_list() -> void:
	_refresh_pair_clips()
	ui_clips.clear()
	var studio := CBClipLib.list_clips()
	var names: Array = []
	for n in anim.get_animation_list():
		names.append(str(n))
	names.sort()
	for n in names:
		var star := studio.has(n)
		var i := ui_clips.add_item(("* " if star else "") + n)
		ui_clips.set_item_metadata(i, n)
		if star:
			ui_clips.set_item_custom_fg_color(i, Color(1.0, 0.8, 0.3))


func _select_clip(name: String) -> void:
	_stop()
	clip_name = name
	var studio := CBClipLib.list_clips().has(name)
	clip = CBClipLib.load_clip(name) if studio else {}
	_loading = true
	ui_loop.button_pressed = bool(clip.get("loop", false)) if studio else (anim.get_animation(name).loop_mode != Animation.LOOP_NONE)
	ui_loop.disabled = not studio
	ui_len.editable = studio
	ui_len.value = int(clip.get("frames", _clip_len_frames()))
	ui_frame.max_value = _clip_len_frames()
	_loading = false
	cues_work = (CBCues.for_clip(name) as Array).duplicate(true)
	_refresh_cues()
	if not edit_reactor:
		var saved := CBPairs.for_clip(name)
		if not saved.is_empty():
			pair = {"reactor_clip": str(saved.get("reactor_clip", "")), "dx": float(saved.get("dx", 1.0)), "dy": float(saved.get("dy", 0.0)),
				"dz": float(saved.get("dz", 0.0)), "yaw": float(saved.get("yaw", 180.0)), "delay": int(saved.get("delay", 0))}
			_loading = true
			for k in ui_pair_sl:
				(ui_pair_sl[k] as HSlider).value = float(pair[k])
				((ui_pair_sl[k] as HSlider).get_parent().get_child(2) as Label).text = "%.3f" % float(pair[k])
			_loading = false
			if pair["reactor_clip"] != "" and not _other.is_empty():
				_other["clip_name"] = pair["reactor_clip"]
				_other["clip"] = CBClipLib.load_clip(pair["reactor_clip"]) if CBClipLib.list_clips().has(pair["reactor_clip"]) else {}
			_place_reactor()
			_refresh_pair_clips()
	for i in ui_clips.item_count:
		if ui_clips.get_item_metadata(i) == name:
			ui_clips.select(i)
	frame = 0.0
	_goto_frame(0.0)
	_refresh_keys()
	_say(("Studio clip: pose it and press KEY." if studio else "Baked clip (read only, use Duplicate -> a studio copy to edit... or New clip)."))


func _toggle_play() -> void:
	if playing:
		_stop()
		return
	if anim == null or not anim.has_animation(clip_name):
		return
	anim.active = true
	cue_player.reset(clip_name)
	CBCues.set_clip(clip_name, cues_work)
	cue_player.reset(clip_name)
	anim.play(clip_name)
	anim.seek(frame / _fps(), true)
	playing = true
	ui_play.text = "Pause"


func _play_with_cues() -> void:
	if playing:
		_stop()
	frame = 0.0
	_toggle_play()


func _stop() -> void:
	playing = false
	if ui_play != null:
		ui_play.text = "Play"
	if anim != null:
		anim.pause()


func _goto_frame(f: float) -> void:
	if _loading:
		return
	frame = clampf(f, 0.0, float(_clip_len_frames()))
	_loading = true
	ui_frame.value = frame
	_loading = false
	ui_frame_lbl.text = _frame_text()
	if playing:
		_stop()
	if not clip.is_empty():
		anim.active = false
		pose = CBClipLib.pose_at(clip, frame, bones)
		_pose_to_sliders()
		_apply()
	elif anim != null and anim.has_animation(clip_name):
		anim.active = true
		anim.play(clip_name)
		anim.seek(frame / 30.0, true)
		anim.pause()
	_show_other()


func _reinstall() -> void:
	# rebuild this clip's Animation in BOTH bodies' players so Play shows the edit on the actor and the reactor
	if clip.is_empty():
		return
	_install_clip(clip, anim, skel, model)
	if not _other.is_empty():
		_install_clip(clip, _other["anim"], _other["skel"], _other["model"])
	_show_other()


func _install_clip(c: Dictionary, an: AnimationPlayer, sk: Skeleton3D, md: Node3D) -> void:
	var lib := an.get_animation_library("")
	var nm := str(c["name"])
	if lib.has_animation(nm):
		lib.remove_animation(nm)
	lib.add_animation(nm, CBClipLib.build_animation(c, sk, md))


func _new_clip() -> void:
	var n := "clip%d" % (CBClipLib.list_clips().size() + 1)
	while CBClipLib.list_clips().has(n) or anim.has_animation(n):
		n += "x"
	clip = CBClipLib.blank(n)
	CBClipLib.save_clip(clip)
	_reinstall_new(n)


func _dup_clip() -> void:
	if clip.is_empty():
		_say("Duplicate works on studio clips. New clip makes an empty one.")
		return
	var c := clip.duplicate(true)
	var n := clip_name + "_copy"
	while CBClipLib.list_clips().has(n):
		n += "x"
	c["name"] = n
	CBClipLib.save_clip(c)
	clip = c
	_reinstall_new(n)


func _reinstall_new(n: String) -> void:
	clip_name = n
	_reinstall()
	_refresh_clip_list()
	_select_clip(n)


func _del_clip() -> void:
	if clip.is_empty():
		_say("Only studio clips can be deleted.")
		return
	CBClipLib.delete_clip(clip_name)
	var lib := anim.get_animation_library("")
	if lib.has_animation(clip_name):
		lib.remove_animation(clip_name)
	_refresh_clip_list()
	_select_clip("fightIdle")


# ------------------------------------------------------------------ pose editing

func _fill_bone_options() -> void:
	ui_bone.clear()
	for b in bones:
		ui_bone.add_item(b)
	var i := bones.find(bone_sel)
	ui_bone.select(maxi(i, 0))
	ui_s_bone.clear()
	ui_s_to.clear()
	ui_s_to.add_item("(none)")
	for b in bones:
		ui_s_bone.add_item(b)
		ui_s_to.add_item(b)
	_pose_to_sliders()


func _bone_hint(b: String) -> String:
	for k in HINTS:
		if b.begins_with(k):
			return HINTS[k]
	return "X / Y / Z: rotation about the bone's own axes (radians)"


func _pose_to_sliders() -> void:
	_loading = true
	var e: Vector3 = pose.get(bone_sel, Vector3.ZERO)
	for i in 3:
		(ui_rot[i] as HSlider).value = e[i]
		var lbl := ((ui_rot[i] as HSlider).get_parent().get_child(2) as Label)
		lbl.text = "%.3f" % e[i]
	ui_dy.value = float(pose.get("_dy", 0.0))
	ui_hint.text = _bone_hint(bone_sel)
	_loading = false


func _pick_bone(b: String) -> void:
	var i := bones.find(b)
	if i < 0:
		_say("This rig has no bone %s." % b)
		return
	bone_sel = b
	ui_bone.select(i)
	_pose_to_sliders()


## curl (1) or open (0) a hand: the fingers and tips curl together, the thumb follows
func _hand(left: bool, amount: float) -> void:
	if clip.is_empty():
		_say("Select or create a studio clip first.")
		return
	var sd := "L" if left else "R"
	pose["fingers" + sd] = Vector3(-1.2 * amount, 0, 0)
	pose["tips" + sd] = Vector3(-1.0 * amount, 0, 0)
	pose["thumb" + sd] = Vector3(-0.8 * amount, 0, 0)
	_pose_to_sliders()
	_apply()
	_say("%s hand %s (KEY to keep)." % [sd, "closed" if amount > 0.5 else "opened"])


## a smooth curl along the tail, root to tip
func _tail_curl() -> void:
	if clip.is_empty():
		_say("Select or create a studio clip first.")
		return
	for j in ["tail", "tail2", "tail3"]:
		pose[j] = Vector3(0.0, 0.0, 0.45)
	_pose_to_sliders()
	_apply()
	_say("Tail curled to the side (KEY to keep; the SECONDARY tab makes it swing by itself).")


func _set_rot(axis: int, x: float) -> void:
	if clip.is_empty():
		_say("Select or create a studio clip to pose (New clip).")
		return
	var e: Vector3 = pose.get(bone_sel, Vector3.ZERO)
	var delta := x - e[axis]
	e[axis] = x
	pose[bone_sel] = e
	if prop_on and absf(delta) > 0.0:
		_proportional(axis, delta)
	_apply()


## proportional pose: the same turn goes to the bones around the edited one (or inside the selected socket's zone), strongest at the
## centre and fading to nothing at the radius
func _proportional(axis: int, delta: float) -> void:
	var rad := prop_radius
	var kind := prop_falloff
	var centre := Vector3.ZERO
	var si := skel.find_bone(bone_sel)
	if si < 0:
		return
	centre = skel.get_bone_global_rest(si).origin
	if prop_from_socket and sock_sel != "" and sockets.get(sock_sel) is Node3D:
		centre = skel.global_transform.affine_inverse() * (sockets[sock_sel] as Node3D).global_position
		var zr := CBSockets.zone_radius(sock_specs.get(sock_sel, {}))
		if zr > 0.0:
			rad = zr
			kind = CBSockets.zone_falloff(sock_specs[sock_sel])
	for i in skel.get_bone_count():
		var b := skel.get_bone_name(i)
		if b == bone_sel:
			continue
		if prop_sub_only:
			var is_sub := false
			for pre in SUB_PREFIX:
				if b.begins_with(pre):
					is_sub = true
			if not is_sub:
				continue
		var d := skel.get_bone_global_rest(i).origin.distance_to(centre)
		if d > rad:
			continue
		var w := CBSockets.falloff(kind, d / maxf(rad, 0.001))
		var o: Vector3 = pose.get(b, Vector3.ZERO)
		o[axis] += delta * w
		pose[b] = o


func _apply() -> void:
	if skel != null:
		CBClipLib.apply_pose(skel, pose)


func _key_frame() -> void:
	if clip.is_empty():
		_say("Select or create a studio clip to key (New clip).")
		return
	var f := int(round(frame))
	var rot: Dictionary = {}
	for b in bones:
		var e: Vector3 = pose.get(b, Vector3.ZERO)
		if e.length() > 0.0005:
			rot[b] = [snappedf(e.x, 0.001), snappedf(e.y, 0.001), snappedf(e.z, 0.001)]
	var k := {"f": f, "rot": rot, "hips_dy": snappedf(float(pose.get("_dy", 0.0)), 0.001)}
	var keys: Array = clip["keys"]
	for i in keys.size():
		if int((keys[i] as Dictionary)["f"]) == f:
			keys[i] = k
			f = -1
			break
	if f >= 0:
		keys.append(k)
	_reinstall()
	_refresh_keys()
	CBClipLib.save_clip(clip)
	_say("Keyed frame %d (saved)." % int(round(frame)))


func _del_key() -> void:
	if clip.is_empty():
		return
	var f := int(round(frame))
	var keys: Array = clip["keys"]
	for i in keys.size():
		if int((keys[i] as Dictionary)["f"]) == f and keys.size() > 1:
			keys.remove_at(i)
			break
	_reinstall()
	_refresh_keys()
	CBClipLib.save_clip(clip)
	_goto_frame(frame)


func _neutral() -> void:
	pose = {}
	for b in bones:
		pose[b] = Vector3.ZERO
	pose["_dy"] = 0.0
	_pose_to_sliders()
	_apply()


func _mirror(l_to_r: bool) -> void:
	var src := "L" if l_to_r else "R"
	var dst := "R" if l_to_r else "L"
	for b in bones:
		if str(b).ends_with(src):
			var o: String = str(b).trim_suffix(src) + dst
			var e: Vector3 = pose.get(b, Vector3.ZERO)
			pose[o] = Vector3(e.x, -e.y, -e.z)   # mirror across the body: twist and side swing flip
	_pose_to_sliders()
	_apply()
	_say("Mirrored %s -> %s (key it to keep)." % [src, dst])


func _knee_check() -> void:
	var bad: Array = []
	for k in CBClipLib.sorted_keys(clip):
		for kn in ["kneeL", "kneeR"]:
			var r: Array = ((k as Dictionary).get("rot", {}) as Dictionary).get(kn, [0, 0, 0])
			if float(r[0]) < -0.01:
				bad.append("f%d %s %.2f" % [int(k["f"]), kn, float(r[0])])
	_say("Knees fine: none bend forward." if bad.is_empty() else "KNEE bends forward at: " + ", ".join(bad))


func _refresh_keys() -> void:
	ui_keys.clear()
	if clip.is_empty():
		return
	for k in CBClipLib.sorted_keys(clip):
		var i := ui_keys.add_item("frame %d   (%d bones, hips %+.2f)" % [int(k["f"]), (k["rot"] as Dictionary).size(), float(k.get("hips_dy", 0.0))])
		ui_keys.set_item_metadata(i, int(k["f"]))


# ------------------------------------------------------------------ sockets

func _fill_socket_list() -> void:
	ui_s_list.clear()
	ui_fx_sock.clear()
	for n in sock_specs:
		var i := ui_s_list.add_item("%s   (%s)" % [n, sock_specs[n].get("bone", "?")])
		ui_s_list.set_item_metadata(i, str(n))
		ui_fx_sock.add_item(str(n))
		if str(n) == sock_sel:
			ui_s_list.select(i)


func _select_socket(n: String) -> void:
	sock_sel = n
	_mark_sock()
	_loading = true
	var sp: Dictionary = sock_specs.get(n, {})
	var bi := bones.find(str(sp.get("bone", "")))
	ui_s_bone.select(maxi(bi, 0))
	var ti := bones.find(str(sp.get("to", "")))
	ui_s_to.select(ti + 1 if ti >= 0 else 0)
	ui_s_t.value = float(sp.get("t", 0.0))
	var ex: Array = sp.get("extra", [0, 0, 0])
	for i in 3:
		(ui_s_ex[i] as HSlider).value = float(ex[i])
		((ui_s_ex[i] as HSlider).get_parent().get_child(2) as Label).text = "%.3f" % float(ex[i])
	ui_s_ground.button_pressed = bool(sp.get("ground", false))
	ui_zone_r.value = CBSockets.zone_radius(sp)
	((ui_zone_r.get_parent().get_child(2)) as Label).text = "%.3f" % CBSockets.zone_radius(sp)
	ui_zone_f.select(maxi(FALLOFFS.find(CBSockets.zone_falloff(sp)), 0))
	_loading = false
	_update_gizmo()
	for i in ui_s_list.item_count:
		if ui_s_list.get_item_metadata(i) == n:
			ui_s_list.select(i)
	_say("Socket %s selected (yellow dot). Drag the sliders; the dot moves with the animation." % n)


func _edit_spec(k: String, v: Variant) -> void:
	if sock_sel == "" or _loading:
		return
	var sp: Dictionary = sock_specs[sock_sel]
	if k == "to" and str(v) == "":
		sp.erase("to")
	elif k == "ground" and not bool(v):
		sp.erase("ground")
	else:
		sp[k] = v
	_rebuild_sockets()


func _edit_zone(k: String, v: Variant) -> void:
	if sock_sel == "" or _loading:
		return
	var sp: Dictionary = sock_specs[sock_sel]
	var z: Dictionary = sp.get("zone", {})
	z[k] = v
	sp["zone"] = z
	_update_gizmo()


## a translucent sphere on the selected socket showing its zone (what an effect scatters over / what proportional pose affects)
func _update_gizmo() -> void:
	if _zone_gizmo != null and is_instance_valid(_zone_gizmo):
		_zone_gizmo.queue_free()
	_zone_gizmo = null
	var node: Variant = sockets.get(sock_sel)
	var sp: Dictionary = sock_specs.get(sock_sel, {})
	var r := CBSockets.zone_radius(sp)
	if not (node is Node3D) or r <= 0.0:
		return
	var mi := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = r
	sph.height = r * 2.0
	mi.mesh = sph
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.2, 0.18)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	(node as Node3D).add_child(mi)
	_zone_gizmo = mi


func _edit_extra() -> void:
	if sock_sel == "" or _loading:
		return
	sock_specs[sock_sel]["extra"] = [snappedf((ui_s_ex[0] as HSlider).value, 0.001), snappedf((ui_s_ex[1] as HSlider).value, 0.001), snappedf((ui_s_ex[2] as HSlider).value, 0.001)]
	_rebuild_sockets()


func _add_socket() -> void:
	var n := ui_s_name.text.strip_edges().replace(" ", "_")
	if n == "" or sock_specs.has(n):
		_say("Give the new socket a unique name.")
		return
	sock_specs[n] = {"bone": bone_sel if bone_sel != "root" else "hips"}
	ui_s_name.text = ""
	_rebuild_sockets()
	_select_socket(n)


## a socket on the floor at the middle of the unit (the root bone): for ground effects (shockwaves, cracks, dust rings)
func _add_ground_mid() -> void:
	sock_specs["ground_mid"] = {"bone": "root", "ground": true}
	_rebuild_sockets()
	_select_socket("ground_mid")
	_say("Added ground_mid: the floor point under the middle of the unit (it stays on the floor while the unit jumps).")


## sockets on the bottom of both feet: they ride the foot (follow it up when it kicks) and sit on the sole at rest
func _add_soles() -> void:
	sock_specs["sole_L"] = {"bone": "footL", "sole": true}
	sock_specs["sole_R"] = {"bone": "footR", "sole": true}
	_rebuild_sockets()
	_select_socket("sole_L")
	_say("Added sole_L and sole_R at the bottom of the feet (found from the rest pose, so it fits this fighter).")


func _remove_socket() -> void:
	if sock_sel == "":
		return
	sock_specs.erase(sock_sel)
	sock_sel = ""
	_rebuild_sockets()


func _save_sockets(this_fighter_only: bool) -> void:
	var d: Dictionary = CBSockets.data().duplicate(true)
	if this_fighter_only:
		var fighters: Dictionary = d.get("fighters", {})
		var over: Dictionary = {}
		for n in sock_specs:
			if sock_specs[n] != (d["sockets"] as Dictionary).get(n, {}):
				over[n] = sock_specs[n]
		if over.is_empty():
			(fighters as Dictionary).erase(key)
		else:
			fighters[key] = over
		d["fighters"] = fighters
	else:
		d["sockets"] = sock_specs.duplicate(true)
	var err := CBSockets.save_data(d)
	_say("Sockets saved (%s)." % ("only " + key if this_fighter_only else "all fighters") if err == OK else "Could not save sockets: %d" % err)


# ------------------------------------------------------------------ effects, cues, combos

func _refresh_fx_list() -> void:
	ui_fx_list.clear()
	var q := ui_fx_search.text.strip_edges().to_lower()
	for n in combos_work:
		if q == "" or str(n).to_lower().contains(q):
			var i := ui_fx_list.add_item("* " + str(n))
			ui_fx_list.set_item_metadata(i, str(n))
	var ids: Array = []
	for e in Library.scan():
		ids.append(str(e["id"]))
	ids.sort()
	for id in ids:
		if q == "" or str(id).to_lower().contains(q):
			var i := ui_fx_list.add_item(str(id))
			ui_fx_list.set_item_metadata(i, str(id))


func _fx_args() -> Dictionary:
	return {"fx": fx_sel, "socket": ui_fx_sock.get_item_text(maxi(ui_fx_sock.selected, 0)) if ui_fx_sock.item_count > 0 else "mid",
		"scale": snappedf(ui_fx_scale.value, 0.01), "mode": "follow" if ui_fx_mode.selected == 1 else "burst", "dur": snappedf(ui_fx_dur.value, 0.01)}


func _fx_preview() -> void:
	if fx_sel == "":
		_say("Pick an effect first.")
		return
	if combos_work.has(fx_sel):
		CBFxRmt.combos()[fx_sel] = combos_work[fx_sel]   # an unsaved combo previews too
	var c := _fx_args()
	_cue_fire_at_studio(c)
	_say("Preview: %s on %s" % [fx_sel, c["socket"]])


## cues in the Studio fire on the studio's own sockets (the Studio is not a CBFighter)
func _cue_fire_at_studio(c: Dictionary) -> void:
	var id := str(c.get("fx", ""))
	var sock := str(c.get("socket", "mid"))
	var sc := float(c.get("scale", 1.0))
	var node: Variant = sockets.get(sock)
	var at := Vector3(0, 1, 0)
	if node is Node3D:
		at = (node as Node3D).global_position
	elif node is Dictionary:
		var idx := actor_skel.find_bone(str((node as Dictionary).get("bone", "")))
		if idx >= 0:
			var p := actor_skel.global_transform * actor_skel.get_bone_global_pose(idx).origin
			at = Vector3(p.x, 0.0, p.z)
	if str(c.get("mode", "burst")) == "follow" and node is Node3D and not CBFxRmt.combos().has(id):
		var fx: Node3D = load("res://addons/rmt_effects/rmt_effect.gd").spawn(id, node as Node3D, Vector3.ZERO)
		if fx != null:
			fx.scale = Vector3.ONE * sc
			get_tree().create_timer(maxf(float(c.get("dur", 0.5)), 0.05)).timeout.connect(func() -> void: CBFxRmt.unfollow(fx))
		return
	at += CBFxRmt.scatter((sock_specs.get(sock, {}) as Dictionary).get("zone", {}))
	CBFxRmt.play_named(self, id, at, sc, 0.0)


func _refresh_cues() -> void:
	ui_cues.clear()
	cues_work.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["t"]) < float(b["t"]))
	for c in cues_work:
		ui_cues.add_item("f%d  %s -> %s  x%.2f  %s" % [int(round(float(c["t"]) * _fps())), c["fx"], c["socket"], float(c["scale"]), c["mode"]])


func _add_cue() -> void:
	if fx_sel == "":
		_say("Pick an effect first.")
		return
	var c := _fx_args()
	c["t"] = snappedf(frame / _fps(), 0.001)
	cues_work.append(c)
	_refresh_cues()
	_say("Cue added at frame %d. Save all to keep it." % int(round(frame)))


func _remove_cue() -> void:
	var sel := ui_cues.get_selected_items()
	if sel.is_empty():
		return
	cues_work.remove_at(sel[0])
	_refresh_cues()


func _combo_add_layer() -> void:
	if fx_sel == "":
		return
	combo_layers.append([fx_sel, snappedf(ui_fx_scale.value, 0.01), snappedf(ui_combo_delay.value, 0.01)])
	_combo_refresh()


func _combo_refresh() -> void:
	ui_combo_list.clear()
	for l in combo_layers:
		ui_combo_list.add_item("%s  x%.2f  +%.2fs" % [l[0], l[1], l[2]])


func _combo_save() -> void:
	var n := ui_combo_name.text.strip_edges().replace(" ", "_")
	if n == "" or combo_layers.is_empty():
		_say("Name the combo and add at least one layer.")
		return
	combos_work[n] = combo_layers.duplicate(true)
	CBFxRmt.combos()[n] = combos_work[n]
	CBFxRmt.save_combos()
	combo_layers = []
	_combo_refresh()
	_refresh_fx_list()
	_say("Combo %s saved (usable as an effect everywhere, with a star)." % n)


# ------------------------------------------------------------------ save / export

func _save_all() -> void:
	var msgs: Array = []
	if not clip.is_empty():
		CBClipLib.save_clip(clip)
		msgs.append("clip " + clip_name)
	CBCues.set_clip(clip_name, cues_work)
	CBCues.save()
	msgs.append("cues")
	CBFxRmt.combos().merge(combos_work, true)
	CBFxRmt.save_combos()
	msgs.append("combos")
	CBPairs.save()
	msgs.append("pairs")
	_say("Saved: " + ", ".join(msgs) + ". (Sockets have their own Save buttons on the SOCKETS tab.)")


func _export_glb() -> void:
	# markers are editor-only: take them out for the export
	for n in sockets:
		var node: Variant = sockets[n]
		if node is Node3D and (node as Node3D).has_node("marker"):
			(node as Node3D).get_node("marker").visible = false
	var dir := "res://game/packs/city_breaker/exports/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path := dir + "%s_studio.glb" % key
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_scene(actor_model, st)
	if err == OK:
		err = doc.write_to_filesystem(st, path)
	for n in sockets:
		var node2: Variant = sockets[n]
		if node2 is Node3D and (node2 as Node3D).has_node("marker"):
			(node2 as Node3D).get_node("marker").visible = true
	_say("Exported %s (fighter + %d clips)." % [path, anim.get_animation_list().size()] if err == OK else "Export failed: %d" % err)


func _bake_animato() -> void:
	var script := "D:/Projects/Animato/bake_studio_clips.py"
	if not FileAccess.file_exists(script):
		_say("Animato bake script not found: " + script)
		return
	var py := "D:/Projects/Animato/.venv/Scripts/python.exe"
	OS.create_process(py, [script, key])
	_say("Baking the studio clips into %s_fight.glb with Animato (Blender, headless). The original is kept in D:/Cache/chars_before_studio." % key)


# ------------------------------------------------------------------ screenshot helper (--shot)

func _demo_shot() -> void:
	await get_tree().create_timer(0.8).timeout
	if "--head" in OS.get_cmdline_user_args():
		var hi := actor_skel.find_bone("head")
		cam_target = actor_skel.global_transform * actor_skel.get_bone_global_pose(hi).origin + Vector3(0, 0.12, 0)
		cam_dist = 1.5
		cam_yaw = 0.7
		cam_pitch = 0.1
		for n in sockets:
			if sockets[n] is Node3D:
				(sockets[n] as Node3D).visible = false
		await get_tree().create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		var o := "D:/Cache/head_%s.png" % key
		get_viewport().get_texture().get_image().save_png(o)
		print("STUDIO_SHOT ", o)
		get_tree().quit()
		return
	_new_clip()
	await get_tree().create_timer(0.2).timeout
	pose = {}
	for b in bones:
		pose[b] = Vector3.ZERO
	pose["legL"] = Vector3(-0.9, 0, 0)
	pose["kneeL"] = Vector3(1.4, 0, 0)
	pose["armL"] = Vector3(-0.8, 0, -0.35)
	pose["armR"] = Vector3(-0.8, 0, 0.35)
	pose["elbowL"] = Vector3(-0.5, 0, 0)
	pose["elbowR"] = Vector3(-0.5, 0, 0)
	frame = 6.0
	_key_frame()
	_goto_frame(6.0)
	_select_socket("fist_R")
	fx_sel = "impact_spark"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tab="):
			ui_tabs.current_tab = int(a.substr(6))
	cam_yaw = 1.3
	if "--pair" in OS.get_cmdline_user_args():
		ui_pair_show.button_pressed = true
		pair["dx"] = 1.05
		_place_reactor()
		_pair_pick_clip("hit_heavy")
		_goto_frame(6.0)
		cam_yaw = 1.57
		cam_dist = 6.2
		_add_soles()
		_add_ground_mid()
		_select_socket("sole_L")
	if "--react" in OS.get_cmdline_user_args():
		ui_tabs.current_tab = 5
		cam_yaw = 1.57
		var hi2 := actor_skel.find_bone("chest")
		cam_target = actor_skel.global_transform * actor_skel.get_bone_global_pose(hi2).origin + Vector3(0, 0.15, 0)
		cam_dist = 2.6
		for i in ui_react_sock.item_count:
			if ui_react_sock.get_item_text(i) == "head":
				ui_react_sock.select(i)
		ui_react_mag.value = 1.5
		ui_react_dir.select(0)
		_goto_frame(0.0)
		await get_tree().create_timer(0.5).timeout
		if not "--nohit" in OS.get_cmdline_user_args():
			_react_try(false)
			await get_tree().create_timer(0.035).timeout
		await RenderingServer.frame_post_draw
		var o2 := "D:/Cache/react_%s.png" % ("rest" if "--nohit" in OS.get_cmdline_user_args() else "hit")
		get_viewport().get_texture().get_image().save_png(o2)
		print("STUDIO_SHOT ", o2)
		get_tree().quit()
		return
	await get_tree().create_timer(0.6).timeout
	_fx_preview()
	await get_tree().create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	var out := "D:/Cache/studio_shot.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	get_viewport().get_texture().get_image().save_png(out)
	print("STUDIO_SHOT ", out)
	CBClipLib.delete_clip(clip_name)
	get_tree().quit()
