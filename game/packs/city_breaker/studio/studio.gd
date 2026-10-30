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
const FIGHTERS := ["vix", "carter", "al", "slum", "guru", "bigbill", "rhino", "goat", "hype", "vic", "kat"]
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
var pose_mode := true                    # click a joint in the view to select it, drag to swing it, Alt+drag to rotate it
var space_global := false                # POSE sliders in world axes (true) or the bone's own axes (false)
var ground_lock := false                 # hips height keeps the feet where they were: the legs bend instead of sinking
var add_sock_click := false              # the next click on the body adds a socket on the bone under the cursor
var show_skel := true
var drag_bone := ""
var drag_alt := false
var skel_mesh: MeshInstance3D
var _sock_n := 1
const PICK_PX := 20.0
const BONE_R := {"head": 0.2, "neck": 0.1, "chest": 0.28, "torso": 0.26, "hips": 0.26, "arm": 0.12, "elbow": 0.1, "hand": 0.1, "finger": 0.06, "tips": 0.05,
	"thumb": 0.05, "leg": 0.17, "knee": 0.13, "foot": 0.1, "tail": 0.12, "ear": 0.06, "crest": 0.1, "pom": 0.1, "fin": 0.08}
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
var ui_frame: Timeline
var ui_key_btn: Button
var ui_key_state: Label
var ui_del_key_btn: Button
var ui_save_chip: Label
var ui_clip_chip: Label
var pose_dirty := false                  # the pose on screen was edited and is not in a key yet
var last_saved := ""
var ui_move: CheckBox
var move_mode := false                  # the gizmo MOVES the hips along an axis (true) or turns the bone (false)
var pose_copy: Dictionary = {}           # Copy pose / Paste pose
var ui_dx: HSlider
var ui_dz: HSlider
var drag_axis := -1                      # an axis handle of the gizmo is being dragged (0 X, 1 Y, 2 Z)
const DOCK_H := 214.0
const TOP_H := 46.0
const RIGHT_W := 640.0
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
var key_blend_on := false                # KEY also moves the keys before / after by the same edit, fading with distance
var key_blend_range := 6.0
var key_blend_kind := "smooth"
var unbake_step := 2
var unbake_tol := 0.03
var unbake_auto := false                 # selecting a baked clip makes the editable copy at once
var ghosts_show := true
var ghost_sel := ""
var ghost_nodes: Dictionary = {}
var ui_ghost_list: ItemList
var ui_ghost_sl: Dictionary = {}
var ui_ghost_info: Label


## the Studio is laid out for a 1920 x 1080 canvas (16:9 HD): the window opens as large as the screen allows at that ratio and the
## whole UI scales with it, so it never gets cramped on a smaller screen
func _hd_window() -> void:
	var win := get_window()
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	win.content_scale_size = Vector2i(1920, 1080)
	if DisplayServer.get_name() == "headless":
		return
	var scr := DisplayServer.screen_get_usable_rect()
	var w := mini(1920, int(scr.size.x * 0.97))
	var h := int(w * 9 / 16)
	if h > int(scr.size.y * 0.93):
		h = int(scr.size.y * 0.93)
		w = int(h * 16 / 9)
	win.mode = Window.MODE_WINDOWED
	win.size = Vector2i(w, h)
	win.position = scr.position + (scr.size - win.size) / 2


func _ready() -> void:
	_hd_window()
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
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--clip="):
			var cn := a.substr(7)
			if cn.begins_with("ledge"):
				_open_ledge(cn)
			elif anim.has_animation(cn):
				_select_clip(cn)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--snap="):   # --snap=path.png[,frame]: save the window after a moment and quit (screenshots of a clip)
			var parts := a.substr(7).split(",")
			if parts.size() > 1:
				_goto_frame(float(parts[1]))
			for a2 in OS.get_cmdline_user_args():
				if a2.begins_with("--focus="):   # --focus=bone[,dist[,yaw]]: frame one bone close up (hand detail review)
					var fp := a2.substr(8).split(",")
					var bi := skel.find_bone(fp[0])
					if bi >= 0:
						cam_target = skel.global_transform * skel.get_bone_global_pose(bi).origin
						cam_dist = float(fp[1]) if fp.size() > 1 else 0.9
						if fp.size() > 2:
							cam_yaw = float(fp[2])
						show_skel = false
						for sn in sockets:   # socket markers would hide the hand
							if sockets[sn] is Node3D and (sockets[sn] as Node3D).get_node_or_null("marker") != null:
								((sockets[sn] as Node3D).get_node("marker") as Node3D).visible = false
			await get_tree().create_timer(1.2).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(parts[0])
			get_tree().quit()
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
			if add_sock_click:
				_click_add_socket(mb.position)
			elif ui_tabs.current_tab == 1:
				_pick_socket(mb.position)
			elif ui_tabs.get_current_tab_control() != null and ui_tabs.get_current_tab_control().name == "GHOSTS":
				_pick_ghost(mb.position)
			elif ui_tabs.current_tab == 0 and pose_mode and _pick_axis(mb.position) >= 0:
				drag_axis = _pick_axis(mb.position)
				drag_bone = bone_sel
				_say("%s %s along its %s axis (%s): drag across the handle." % ["Moving" if _moving() else "Turning", bone_sel, ["X", "Y", "Z"][drag_axis], "world" if space_global else "bone"])
			elif ui_tabs.current_tab == 0 and pose_mode:
				var hit := _pick_bone_at(mb.position)
				if hit != "":
					bone_sel = hit
					ui_bone.select(bones.find(hit))
					_pose_to_sliders()
					drag_bone = hit
					drag_alt = Input.is_key_pressed(KEY_ALT)
					_say("%s selected: drag to swing it, Alt+drag to rotate it%s." % [hit, " (drag up / down moves the hips)" if hit == "hips" else ""])
		elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			if drag_bone != "" and not clip.is_empty():
				_say("Moved %s. Press SET KEY (K) to keep it." % drag_bone)
			drag_bone = ""
			drag_axis = -1
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		if drag_bone != "" and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT):
			_drag(mm)
			return
		if _over_ui(mm.position):
			return
		if mm.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			cam_yaw -= mm.relative.x * 0.008
			cam_pitch = clampf(cam_pitch + mm.relative.y * 0.006, -1.2, 1.4)
		elif mm.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			var right := cam.global_transform.basis.x
			cam_target += (-right * mm.relative.x + Vector3.UP * mm.relative.y) * 0.004 * cam_dist
	elif ev is InputEventKey and (ev as InputEventKey).pressed and not (ev as InputEventKey).echo:
		var typing := get_viewport().gui_get_focus_owner() is LineEdit or get_viewport().gui_get_focus_owner() is SpinBox
		if (ev as InputEventKey).keycode == KEY_SPACE and not typing:
			_toggle_play()
			get_viewport().set_input_as_handled()
		elif (ev as InputEventKey).keycode == KEY_K and not typing and not Input.is_key_pressed(KEY_CTRL):
			_key_frame()
			get_viewport().set_input_as_handled()
		elif (ev as InputEventKey).keycode == KEY_G and not typing:
			_set_move(not move_mode)
			get_viewport().set_input_as_handled()
		elif (ev as InputEventKey).keycode == KEY_PERIOD and not typing:
			_goto_frame(frame + 1)
		elif (ev as InputEventKey).keycode == KEY_COMMA and not typing:
			_goto_frame(frame - 1)


func _over_ui(p: Vector2) -> bool:
	var vp := get_viewport().get_visible_rect().size
	return p.x < 340.0 or p.x > vp.x - RIGHT_W or p.y < TOP_H or p.y > vp.y - DOCK_H - 6.0


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
	_draw_skeleton()
	_update_key_ui()
	if playing and anim != null:
		var pos := anim.current_animation_position
		cue_player.tick(pos)
		var fps := _fps()
		frame = pos * fps
		_loading = true
		ui_frame.value = frame
		_loading = false
		ui_frame_lbl.text = _frame_text()
		_ghost_update(frame)
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
	if parent is VBoxContainer:   # a line in a column wraps at the panel edge instead of pushing the panel wider
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		l.custom_minimum_size = Vector2(10, 0)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	pc.anchor_top = 0.0
	pc.anchor_bottom = 1.0
	pc.offset_top = TOP_H + 4.0
	pc.offset_bottom = -(DOCK_H + 8.0)
	if anchor_right:
		pc.anchor_left = 1.0
		pc.anchor_right = 1.0
		pc.offset_left = -RIGHT_W
	else:
		pc.offset_right = 340
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if anchor_right:
		pc.add_child(v)
	else:
		var sc := ScrollContainer.new()
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		pc.add_child(sc)
		sc.add_child(v)
	return v


## a titled, collapsible section: click the header to fold it
func _section(parent: Node, title: String, open: bool = true) -> VBoxContainer:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 3)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(wrap)
	var head := Button.new()
	head.text = ("v  " if open else ">  ") + title
	head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.flat = true
	head.add_theme_font_size_override("font_size", 15)
	head.add_theme_color_override("font_color", Color(1.0, 0.82, 0.3))
	head.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.6))
	wrap.add_child(head)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	body.visible = open
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_child(body)
	head.pressed.connect(func() -> void:
		body.visible = not body.visible
		head.text = ("v  " if body.visible else ">  ") + title)
	return body


## the frame strip: ruler, key diamonds (gold), ghost keys (blue), effect cues (green) and the playhead; click or drag to scrub
class Timeline:
	extends Control
	signal scrubbed(f: float)
	var value := 0.0:
		set(v):
			value = v
			queue_redraw()
	var max_value := 24.0:
		set(v):
			max_value = maxf(v, 1.0)
			queue_redraw()
	var keys: Array = []
	var ghost_keys: Array = []
	var cues: Array = []
	var editable := true
	var dirty := false
	var _down := false

	func _init() -> void:
		custom_minimum_size = Vector2(0, 66)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _x(f: float) -> float:
		return 12.0 + (size.x - 24.0) * f / maxf(max_value, 1.0)

	func _diamond(c: Vector2, r: float, col: Color) -> void:
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), col)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.07, 0.09))
		var font := ThemeDB.fallback_font
		var step := 5 if max_value <= 60 else 10
		var f := 0
		while f <= int(max_value):
			var x := _x(float(f))
			var major := f % (step * 2) == 0
			draw_line(Vector2(x, 2), Vector2(x, 12 if major else 7), Color(0.5, 0.52, 0.6))
			if major:
				draw_string(font, Vector2(x + 2, 22), str(f), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.62, 0.7))
			f += step
		draw_string(font, Vector2(4, 36), "keys", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.5, 0.45, 0.2))
		draw_string(font, Vector2(4, 50), "ghost", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.3, 0.5, 0.7))
		draw_string(font, Vector2(4, 62), "fx", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.3, 0.6, 0.4))
		draw_line(Vector2(0, 28), Vector2(size.x, 28), Color(0.15, 0.16, 0.2))
		for k in keys:
			_diamond(Vector2(_x(float(k)), 33), 5.5, Color(1.0, 0.82, 0.25) if editable else Color(0.5, 0.5, 0.5))
		for k in ghost_keys:
			_diamond(Vector2(_x(float(k)), 47), 4.5, Color(0.45, 0.72, 1.0))
		for k in cues:
			_diamond(Vector2(_x(float(k)), 60), 3.5, Color(0.4, 0.85, 0.55))
		var px := _x(value)
		var col := Color(1.0, 0.45, 0.2) if dirty else Color(0.95, 0.95, 1.0)
		draw_line(Vector2(px, 0), Vector2(px, size.y), col, 2.0)
		draw_colored_polygon(PackedVector2Array([Vector2(px - 6, 0), Vector2(px + 6, 0), Vector2(px, 9)]), col)

	func _emit_at(x: float) -> void:
		var f := clampf(roundf((x - 12.0) / maxf(size.x - 24.0, 1.0) * max_value), 0.0, max_value)
		scrubbed.emit(f)

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_down = (ev as InputEventMouseButton).pressed
			if _down:
				_emit_at((ev as InputEventMouseButton).position.x)
		elif ev is InputEventMouseMotion and _down:
			_emit_at((ev as InputEventMouseMotion).position.x)


func _top_bar() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.11, 0.97)
	sb.set_content_margin_all(6)
	pc.add_theme_stylebox_override("panel", sb)
	pc.anchor_right = 1.0
	pc.offset_bottom = TOP_H
	layer.add_child(pc)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	pc.add_child(h)
	var title := _label(h, "FIGHT STUDIO")
	title.add_theme_font_size_override("font_size", 20)
	_label(h, "Fighter")
	ui_fighter = OptionButton.new()
	for f in FIGHTERS:
		ui_fighter.add_item(f)
	ui_fighter.item_selected.connect(func(i: int) -> void: _load_fighter(FIGHTERS[i]))
	h.add_child(ui_fighter)
	_label(h, "Clip")
	ui_clip_chip = _label(h, "")
	ui_clip_chip.add_theme_font_size_override("font_size", 15)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	ui_save_chip = _label(h, "")
	ui_save_chip.add_theme_font_size_override("font_size", 14)
	_button(h, "Save all", _save_all)
	_button(h, "Export GLB", _export_glb)
	_button(h, "Bake (Animato)", _bake_animato)
	_button(h, "Open folder", func() -> void: OS.shell_show_in_file_manager(ProjectSettings.globalize_path(CBClipLib.DIR)))


func _dock() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.12, 0.96)
	sb.set_content_margin_all(8)
	pc.add_theme_stylebox_override("panel", sb)
	pc.anchor_top = 1.0
	pc.anchor_bottom = 1.0
	pc.anchor_right = 1.0
	pc.offset_top = -DOCK_H
	pc.offset_left = 350
	pc.offset_right = -(RIGHT_W + 10.0)
	pc.offset_bottom = -6
	layer.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	pc.add_child(v)
	ui_status = Label.new()
	ui_status.add_theme_font_size_override("font_size", 14)
	ui_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	ui_status.custom_minimum_size = Vector2(0, 38)
	ui_status.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	v.add_child(ui_status)
	var tr := HBoxContainer.new()
	tr.add_theme_constant_override("separation", 6)
	v.add_child(tr)
	_button(tr, "|<", func() -> void: _goto_frame(0))
	_button(tr, "<", func() -> void: _goto_frame(frame - 1))
	ui_play = _button(tr, "Play", _toggle_play)
	ui_play.custom_minimum_size = Vector2(70, 0)
	_button(tr, ">", func() -> void: _goto_frame(frame + 1))
	ui_frame_lbl = _label(tr, "")
	ui_frame_lbl.custom_minimum_size = Vector2(190, 0)
	ui_loop = CheckBox.new()
	ui_loop.text = "loop"
	ui_loop.toggled.connect(func(on: bool) -> void:
		if not clip.is_empty() and not _loading:
			clip["loop"] = on
			_reinstall())
	tr.add_child(ui_loop)
	_label(tr, "speed")
	ui_speed = HSlider.new()
	ui_speed.min_value = 0.1
	ui_speed.max_value = 2.0
	ui_speed.step = 0.05
	ui_speed.value = 1.0
	ui_speed.custom_minimum_size = Vector2(90, 0)
	ui_speed.value_changed.connect(func(x: float) -> void: anim.speed_scale = x)
	tr.add_child(ui_speed)
	_label(tr, "length")
	ui_len = SpinBox.new()
	ui_len.min_value = 4
	ui_len.max_value = 240
	ui_len.value = 24
	ui_len.suffix = "fr"
	ui_len.value_changed.connect(func(x: float) -> void:
		if not clip.is_empty() and not _loading:
			clip["frames"] = int(x)
			ui_frame.max_value = x
			_reinstall())
	tr.add_child(ui_len)
	ui_frame = Timeline.new()
	ui_frame.scrubbed.connect(func(f: float) -> void: _goto_frame(f))
	v.add_child(ui_frame)
	var kr := HBoxContainer.new()
	kr.add_theme_constant_override("separation", 8)
	v.add_child(kr)
	ui_key_btn = Button.new()
	ui_key_btn.custom_minimum_size = Vector2(230, 38)
	ui_key_btn.add_theme_font_size_override("font_size", 15)
	ui_key_btn.pressed.connect(_key_frame)
	kr.add_child(ui_key_btn)
	ui_del_key_btn = _button(kr, "Delete key", _del_key)
	ui_del_key_btn.custom_minimum_size = Vector2(100, 38)
	ui_key_state = _label(kr, "")
	ui_key_state.add_theme_font_size_override("font_size", 14)
	ui_key_state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui_key_state.autowrap_mode = TextServer.AUTOWRAP_WORD
	var kr2 := HBoxContainer.new()
	kr2.add_theme_constant_override("separation", 8)
	v.add_child(kr2)
	_button(kr2, "Copy pose", _copy_pose)
	_button(kr2, "Paste pose", _paste_pose)
	_button(kr2, "Revert", _revert_pose)
	_button(kr2, "Close loop", _close_loop)


func _build_ui() -> void:
	_top_bar()
	_dock()
	var left := _panel(false)
	var sc := _section(left, "CLIPS")
	_label(sc, "* gold = studio clip (editable)    [baked] = read only")
	ui_clips = ItemList.new()
	ui_clips.custom_minimum_size = Vector2(0, 300)
	ui_clips.item_selected.connect(func(i: int) -> void: _select_clip(ui_clips.get_item_metadata(i)))
	sc.add_child(ui_clips)
	var r2 := HBoxContainer.new()
	sc.add_child(r2)
	_button(r2, "New clip", _new_clip)
	_button(r2, "Duplicate", _dup_clip)
	_button(r2, "Delete", _del_clip)
	var sb := _section(left, "BAKED ANIMATION")
	_label(sb, "A [baked] clip is dense and read only. Posing or keying one makes an editable copy automatically; this does it on purpose.").autowrap_mode = TextServer.AUTOWRAP_WORD
	var rb := HBoxContainer.new()
	sb.add_child(rb)
	_button(rb, "UNBAKE -> editable copy", _unbake)
	var rb2 := HBoxContainer.new()
	sb.add_child(rb2)
	_label(rb2, "key every ")
	var sp1 := SpinBox.new()
	sp1.min_value = 1
	sp1.max_value = 8
	sp1.value = unbake_step
	sp1.suffix = "fr"
	sp1.value_changed.connect(func(x: float) -> void: unbake_step = int(x))
	rb2.add_child(sp1)
	_label(rb2, " tolerance ")
	var sp2 := SpinBox.new()
	sp2.min_value = 0.0
	sp2.max_value = 0.3
	sp2.step = 0.005
	sp2.value = unbake_tol
	sp2.suffix = "rad"
	sp2.value_changed.connect(func(x: float) -> void: unbake_tol = x)
	rb2.add_child(sp2)
	var cua := CheckBox.new()
	cua.text = "unbake when a baked clip is opened"
	cua.toggled.connect(func(on: bool) -> void: unbake_auto = on)
	sb.add_child(cua)
	var sl := _section(left, "LEDGE SET (with ghost edge)")
	var rl := HBoxContainer.new()
	sl.add_child(rl)
	_button(rl, "Grab", func() -> void: _open_ledge("ledge_grab"))
	_button(rl, "Hang", func() -> void: _open_ledge("ledge_hang"))
	_button(rl, "Climb", func() -> void: _open_ledge("ledge_climb"))
	var sh := _section(left, "KEYS AND SHORTCUTS", false)
	_label(sh, "K            set / update the key at this frame\nSpace     play / pause\n, and .     previous / next frame\nX / Y / Z  hold while dragging a joint: turn about that axis only\nAlt+drag  free rotate     drag a coloured handle: turn about it\nRight mouse orbit    middle mouse pan    wheel zoom").autowrap_mode = TextServer.AUTOWRAP_WORD

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
	_build_ghost_tab()
	# every tab scrolls on its own: nothing hides below the fold
	for c in ui_tabs.get_children():
		var nm := str(c.name)
		ui_tabs.remove_child(c)
		var sc2 := ScrollContainer.new()
		sc2.name = nm
		sc2.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		(c as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc2.add_child(c)
		ui_tabs.add_child(sc2)
	_say("Pick a clip, scrub the timeline, pose a joint and press SET KEY (or K). A [baked] clip becomes an editable copy as soon as you pose it.")


## the key button, the key state line and the two chips in the top bar follow what is on screen
func _update_key_ui() -> void:
	if ui_key_btn == null:
		return
	var studio := not clip.is_empty()
	var f := int(round(frame))
	var keyed := false
	if studio:
		for k in (clip["keys"] as Array):
			if int((k as Dictionary)["f"]) == f:
				keyed = true
	var txt := ""
	var col := Color(0.8, 0.84, 0.95)
	var btn := ""
	if not studio:
		btn = "SET KEY (makes an editable copy)"
		txt = "Baked clip: read only. Posing or pressing SET KEY makes an editable copy for you."
	elif keyed and pose_dirty:
		btn = "UPDATE KEY  (frame %d)" % f
		txt = "Frame %d has a key and you changed the pose. Press UPDATE KEY (K) to store it." % f
		col = Color(1.0, 0.6, 0.25)
	elif keyed:
		btn = "UPDATE KEY  (frame %d)" % f
		txt = "Frame %d is a KEY. Everything shown is stored." % f
		col = Color(0.5, 0.9, 0.55)
	elif pose_dirty:
		btn = "SET KEY  (frame %d)" % f
		txt = "Frame %d is in between and you changed the pose. Press SET KEY (K) to store it as a key." % f
		col = Color(1.0, 0.6, 0.25)
	else:
		btn = "SET KEY  (frame %d)" % f
		txt = "Frame %d is in between: interpolated from the keys around it. Pose, then SET KEY." % f
	ui_key_btn.text = btn
	ui_key_state.text = txt
	ui_key_state.add_theme_color_override("font_color", col)
	ui_del_key_btn.disabled = not (studio and keyed)
	ui_frame.dirty = pose_dirty
	ui_frame.editable = studio
	if pose_dirty:
		ui_save_chip.text = "EDITED - not keyed yet (press K)"
		ui_save_chip.add_theme_color_override("font_color", Color(1.0, 0.6, 0.25))
	else:
		ui_save_chip.text = ("saved %s" % last_saved) if last_saved != "" else "nothing to save"
		ui_save_chip.add_theme_color_override("font_color", Color(0.5, 0.9, 0.55))
	ui_clip_chip.text = "%s  [%s]" % [clip_name, "STUDIO - editable" if studio else "BAKED - read only"]
	ui_clip_chip.add_theme_color_override("font_color", Color(1.0, 0.82, 0.3) if studio else Color(0.7, 0.72, 0.8))


func _refresh_timeline() -> void:
	if ui_frame == null:
		return
	var ks: Array = []
	for k in (CBClipLib.sorted_keys(clip) if not clip.is_empty() else []):
		ks.append(int((k as Dictionary)["f"]))
	ui_frame.keys = ks
	var gk: Array = []
	for n in (clip.get("ghost_keys", {}) as Dictionary):
		for k in (clip["ghost_keys"][n] as Array):
			var gf := int((k as Dictionary)["f"])
			if not gk.has(gf):
				gk.append(gf)
	ui_frame.ghost_keys = gk
	var cf: Array = []
	for c in cues_work:
		cf.append(int(round(float((c as Dictionary)["t"]) * _fps())))
	ui_frame.cues = cf
	ui_frame.queue_redraw()


## posing a [baked] clip makes the editable copy first (so a pose is never refused) and puts you back on the same frame
func _ensure_editable() -> bool:
	if not clip.is_empty():
		return true
	if anim != null and anim.has_animation(clip_name):
		var f := frame
		var from := clip_name
		_unbake()
		_goto_frame(f)
		_say("%s is baked (read only), so I made the editable copy %s. Carry on posing." % [from, clip_name])
		return not clip.is_empty()
	_say("Select a clip first, or press New clip.")
	return false


func _save_clip() -> void:
	CBClipLib.save_clip(clip)
	last_saved = Time.get_time_string_from_system()


func _say(t: String) -> void:
	if ui_status != null:
		ui_status.text = t


func _build_pose_tab() -> void:
	var v := VBoxContainer.new()
	v.name = "POSE"
	ui_tabs.add_child(v)
	var root := v
	v = _section(root, "1   MODE")
	var rm := HBoxContainer.new()
	v.add_child(rm)
	var cpm := CheckBox.new()
	cpm.text = "pose mode (click + drag)"
	cpm.button_pressed = true
	cpm.toggled.connect(func(on: bool) -> void: pose_mode = on)
	rm.add_child(cpm)
	var csk := CheckBox.new()
	csk.text = "skeleton"
	csk.button_pressed = true
	csk.toggled.connect(func(on: bool) -> void: show_skel = on)
	rm.add_child(csk)
	ui_move = CheckBox.new()
	ui_move.text = "MOVE joints (G)"
	ui_move.toggled.connect(_set_move)
	rm.add_child(ui_move)
	var rs2 := HBoxContainer.new()
	v.add_child(rs2)
	var cgl := CheckBox.new()
	cgl.text = "GLOBAL axes"
	cgl.toggled.connect(func(on: bool) -> void:
		space_global = on
		_pose_to_sliders()
		_say("Angles are now %s." % ("GLOBAL: world axes, the same turn whatever the bone's own axes are" if on else "LOCAL: the bone's own axes")))
	rs2.add_child(cgl)
	var cgr := CheckBox.new()
	cgr.text = "ground lock (feet)"
	cgr.toggled.connect(func(on: bool) -> void:
		ground_lock = on
		_say("Ground lock %s: hips height %s." % ["ON" if on else "off", "bends the legs so the feet stay put" if on else "moves the whole body"]))
	rs2.add_child(cgr)
	_label(v, "Click a joint in the view (yellow = selected). Drag = swing it toward the mouse. Alt+drag = rotate it. Drag the hips up / down = hips height.").autowrap_mode = TextServer.AUTOWRAP_WORD
	v = _section(root, "2   POSE THE BONE")
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
	ui_dy = _slider(v, "hips height", -0.9, 0.4, 0.005, 0.0, func(x: float) -> void: _set_dy(x))
	ui_dx = _slider(v, "hips side (X)", -1.0, 1.0, 0.005, 0.0, func(x: float) -> void: _set_shift("_dx", x))
	ui_dz = _slider(v, "hips depth (Z)", -1.0, 1.0, 0.005, 0.0, func(x: float) -> void: _set_shift("_dz", x))
	var r := HBoxContainer.new()
	v.add_child(r)
	_button(r, "Neutral", _neutral)
	var r2 := HBoxContainer.new()
	v.add_child(r2)
	_button(r2, "Mirror L -> R", func() -> void: _mirror(true))
	_button(r2, "Mirror R -> L", func() -> void: _mirror(false))
	_button(r2, "Knees OK?", _knee_check)
	_label(v, "Other axes: the yellow joint shows three handles (red X, green Y, blue Z). Drag a handle to turn the bone about that axis only, or hold X / Y / Z while you drag the joint. GLOBAL axes switches the handles to world axes.").autowrap_mode = TextServer.AUTOWRAP_WORD
	v = _section(root, "3   PROPORTIONAL AND PARTS")
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
	var rh := HBoxContainer.new()
	v.add_child(rh)
	_label(rh, "Hands (hand_ref): ")
	_button(rh, "Fist", func() -> void: _hand_ref(10, ["fingers", "tips", "thumb"], "fist"))
	_button(rh, "Carry", func() -> void: _hand_ref(20, ["fingers", "tips", "thumb", "hand"], "carry (palms up)"))
	_button(rh, "Side hold", func() -> void: _hand_ref(30, ["fingers", "tips", "thumb"], "side hold (palms in)"))
	_button(rh, "Grab arms", func() -> void: _hand_ref(0, ["arm", "elbow", "hand"], "grab arms", 10))
	_button(rh, "Hold arms", func() -> void: _hand_ref(10, ["arm", "elbow", "hand", "fingers", "tips", "thumb"], "hold arms"))
	v = _section(root, "4   KEY BLEND")
	_label(v, "With key blend on, SET KEY also moves the keys before and after by the same edit, fading over the range.").autowrap_mode = TextServer.AUTOWRAP_WORD
	var rkb := HBoxContainer.new()
	v.add_child(rkb)
	var ckb := CheckBox.new()
	ckb.text = "key blend"
	ckb.tooltip_text = "KEY also moves the keys before and after by the same edit, fading with distance"
	ckb.toggled.connect(func(on: bool) -> void: key_blend_on = on)
	rkb.add_child(ckb)
	_slider(rkb, "range (frames)", 1.0, 30.0, 1.0, key_blend_range, func(x: float) -> void: key_blend_range = x)
	var okb := OptionButton.new()
	for fo in CBAnimTools.FALLOFFS:
		okb.add_item(fo)
	okb.item_selected.connect(func(i: int) -> void: key_blend_kind = CBAnimTools.FALLOFFS[i])
	rkb.add_child(okb)
	v = _section(root, "5   KEYS OF THIS CLIP")
	_label(v, "Click a key to jump to it.")
	ui_keys = ItemList.new()
	ui_keys.custom_minimum_size = Vector2(0, 120)
	ui_keys.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ui_keys.item_selected.connect(func(i: int) -> void: _goto_frame(float(ui_keys.get_item_metadata(i))))
	v.add_child(ui_keys)
	_label(v, "Pose at a frame, press SET KEY. The in-betweens are interpolated. Spin = hips rotation.").autowrap_mode = TextServer.AUTOWRAP_WORD


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
	var cac := CheckBox.new()
	cac.text = "CLICK-ADD: click the character to put a socket right there"
	cac.toggled.connect(func(on: bool) -> void:
		add_sock_click = on
		_say("Click-add ON: click anywhere on the body, a socket is created on the nearest bone at that spot." if on else "Click-add off."))
	v.add_child(cac)
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
		var i := ui_clips.add_item(("* " if star else "") + n + ("" if star else "   [baked]"))
		ui_clips.set_item_metadata(i, n)
		if star:
			ui_clips.set_item_custom_fg_color(i, Color(1.0, 0.8, 0.3))


func _select_clip(name: String) -> void:
	_stop()
	if unbake_auto and not CBClipLib.list_clips().has(name) and anim != null and anim.has_animation(name):
		clip_name = name
		clip = {}
		_unbake()
		return
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
	_ghost_rebuild()
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
		pose_dirty = false
	elif anim != null and anim.has_animation(clip_name):
		anim.active = true
		anim.play(clip_name)
		anim.seek(frame / 30.0, true)
		anim.pause()
	_ghost_update(frame)
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
	_save_clip()
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
	if space_global and skel != null:
		e = _global_euler(bone_sel)
	for i in 3:
		(ui_rot[i] as HSlider).value = e[i]
		var lbl := ((ui_rot[i] as HSlider).get_parent().get_child(2) as Label)
		lbl.text = "%.3f" % e[i]
	ui_dy.value = float(pose.get("_dy", 0.0))
	ui_dx.value = float(pose.get("_dx", 0.0))
	ui_dz.value = float(pose.get("_dz", 0.0))
	ui_hint.text = _bone_hint(bone_sel)
	_loading = false


# ------------------------------------------------------------------ pose mode: skeleton overlay, picking, dragging

func _bone_o(i: int) -> Vector3:
	return skel.global_transform * skel.get_bone_global_pose(i).origin


func _bone_tip(i: int) -> Vector3:
	var o := _bone_o(i)
	var kids := skel.get_bone_children(i)
	if not kids.is_empty():
		return _bone_o(kids[0])
	var par := skel.get_bone_parent(i)
	if par >= 0:
		var d := (o - _bone_o(par)).normalized()
		return o + d * 0.09
	return o + Vector3.UP * 0.1


func _draw_skeleton() -> void:
	if skel == null:
		return
	if skel_mesh == null:
		skel_mesh = MeshInstance3D.new()
		skel_mesh.mesh = ImmediateMesh.new()
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.no_depth_test = true
		m.render_priority = 5
		skel_mesh.material_override = m
		add_child(skel_mesh)
	var im := skel_mesh.mesh as ImmediateMesh
	im.clear_surfaces()
	skel_mesh.visible = show_skel
	if not show_skel:
		return
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var right := cam.global_transform.basis.x
	var up := cam.global_transform.basis.y
	for i in skel.get_bone_count():
		var b := skel.get_bone_name(i)
		var sel := b == bone_sel
		var col := Color(1.0, 0.9, 0.1) if sel else (Color(0.3, 0.8, 1.0) if not str(b).begins_with(("ear")) else Color(0.5, 1.0, 0.6))
		var o := _bone_o(i)
		var t := _bone_tip(i)
		im.surface_set_color(col)
		im.surface_add_vertex(o)
		im.surface_add_vertex(t)
		# a small diamond at the joint (so it reads as a handle)
		var r := 0.035 if sel else 0.022
		for pair in [[right, up], [up, -right], [-right, -up], [-up, right]]:
			im.surface_add_vertex(o + pair[0] * r)
			im.surface_add_vertex(o + pair[1] * r)
	# the axis gizmo on the selected joint: three handles, each turns the bone about that axis (MOVE hips: slides the body instead)
	var si := skel.find_bone(bone_sel)
	if si >= 0 and pose_mode:
		var so := _bone_o(si)
		for ax in 3:
			var tip := so + _axis_vec(si, ax) * AXIS_LEN
			var gc: Color = AXIS_COL[ax]
			if ax == drag_axis:
				gc = Color(1, 1, 1)
			im.surface_set_color(gc)
			im.surface_add_vertex(so)
			im.surface_add_vertex(tip)
			var hr := 0.05 if move_mode else 0.028
			for pair2 in [[right, up], [up, -right], [-right, -up], [-up, right]]:
				im.surface_add_vertex(tip + pair2[0] * hr)
				im.surface_add_vertex(tip + pair2[1] * hr)
	im.surface_end()


## the bone whose joint / segment is nearest the mouse (within PICK_PX), or ""
func _pick_bone_at(p: Vector2) -> String:
	# joints first (the diamonds): the bone whose own joint is nearest the mouse
	var best := ""
	var bd := PICK_PX
	for i in skel.get_bone_count():
		var d := p.distance_to(cam.unproject_position(_bone_o(i)))
		if d < bd:
			bd = d
			best = skel.get_bone_name(i)
	if best != "":
		return best
	# then the bone segments (a click along a limb picks that limb)
	bd = PICK_PX
	for i in skel.get_bone_count():
		var a := cam.unproject_position(_bone_o(i))
		var b2 := cam.unproject_position(_bone_tip(i))
		var ab := b2 - a
		var t := 0.0 if ab.length_squared() < 1.0 else clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var d2 := p.distance_to(a + ab * t)
		if d2 < bd:
			bd = d2
			best = skel.get_bone_name(i)
	return best


## the world direction of one of the selected bone's three axes (the bone's own, or the world's when GLOBAL is on)
func _axis_vec(i: int, ax: int) -> Vector3:
	if space_global or _moving():
		return [Vector3.RIGHT, Vector3.UP, Vector3.BACK][ax]
	var bb := skel.global_transform.basis * skel.get_bone_global_pose(i).basis
	return [bb.x, bb.y, bb.z][ax].normalized()


## G: handles TURN the selected joint (default) or MOVE it along world X / Y / Z
func _set_move(on: bool) -> void:
	move_mode = on
	if ui_move != null and ui_move.button_pressed != on:
		ui_move.set_pressed_no_signal(on)
	_say("MOVE: the handles slide the selected joint along world X / Y / Z, the bones above it bend to follow (hips and tail slide the whole body). Press G to go back to turning." if on else "TURN: the handles rotate the selected joint. Press G to move joints instead.")


func _moving() -> bool:
	return move_mode


const AXIS_COL := [Color(1.0, 0.3, 0.3), Color(0.35, 0.95, 0.4), Color(0.4, 0.55, 1.0)]
const AXIS_LEN := 0.3


func _pick_axis(p: Vector2) -> int:
	if skel == null or not show_skel:
		return -1
	var i := skel.find_bone(bone_sel)
	if i < 0:
		return -1
	var o := _bone_o(i)
	var best := -1
	var bd := 16.0
	for ax in 3:
		var d := p.distance_to(cam.unproject_position(o + _axis_vec(i, ax) * AXIS_LEN))
		if d < bd:
			bd = d
			best = ax
	return best


## turn the bone about one axis: drag across the handle's line (like turning a knob)
func _drag_axis(mm: InputEventMouseMotion, i: int, ax: int) -> void:
	var o := _bone_o(i)
	var a := _axis_vec(i, ax)
	var sdir := cam.unproject_position(o + a * AXIS_LEN) - cam.unproject_position(o)
	if _moving():
		# slide along the world axis: metres = pixels along the handle * (handle length / its pixel length)
		if sdir.length() > 6.0:
			var metres := mm.relative.dot(sdir.normalized()) * AXIS_LEN / sdir.length()
			if bone_sel != "hips" and _move_ik(i, a * metres):
				_pose_to_sliders()
				return
			var local_axis := (skel.global_transform.basis.inverse() * a).normalized()
			var cur := Vector3(float(pose.get("_dx", 0.0)), float(pose.get("_dy", 0.0)), float(pose.get("_dz", 0.0)))
			var nxt := cur + local_axis * metres
			pose["_dx"] = clampf(nxt.x, -1.0, 1.0)
			pose["_dz"] = clampf(nxt.z, -1.0, 1.0)
			if absf(nxt.y - cur.y) > 0.00001:
				_set_dy(clampf(nxt.y, -0.9, 0.4))
			_apply()
			_pose_to_sliders()
		return
	var ang := 0.0
	if sdir.length() > 6.0:
		ang = mm.relative.dot(Vector2(-sdir.y, sdir.x).normalized()) * 0.014
	else:
		ang = mm.relative.x * 0.014   # the axis points at the camera
	_apply_world_delta(i, _skel_basis_of(Basis(a, ang)))
	_apply()
	_pose_to_sliders()


## move a joint by `delta` (world): the bones above it (up to three, never the hips) swing to bring it there (CCD), so a hand or foot
## can be placed instead of turned; knees never bend forward
func _move_ik(i: int, delta: Vector3) -> bool:
	var target := _bone_o(i) + delta
	var chain: Array = []
	var j := skel.get_bone_parent(i)
	while j >= 0 and chain.size() < 3 and skel.get_bone_name(j) != "hips":
		chain.append(j)
		j = skel.get_bone_parent(j)
	if chain.is_empty():
		return false   # attached straight to the hips: the caller slides the whole body
	for it in 12:
		for c in chain:
			var jo := _bone_o(c)
			var a := _bone_o(i) - jo
			var b := target - jo
			if a.length() < 0.001 or b.length() < 0.001:
				continue
			var ax := a.cross(b)
			if ax.length() < 0.00001:
				continue
			_apply_world_delta(c, _skel_basis_of(Basis(ax.normalized(), a.angle_to(b) * 0.7)))
			_apply()
	return true


func _skel_basis_of(w: Basis) -> Basis:
	var g := skel.global_transform.basis
	return g.inverse() * w * g


## apply a world-space rotation `w` (skeleton space) to a bone: it turns about its own joint, children follow
func _apply_world_delta(i: int, w: Basis) -> void:
	var par := skel.get_bone_parent(i)
	var pb := skel.get_bone_global_pose(par).basis if par >= 0 else Basis.IDENTITY
	var cur := skel.get_bone_pose(i).basis
	var rest_b := skel.get_bone_rest(i).basis
	var lnew := pb.inverse() * w * pb * cur
	var r := rest_b.inverse() * lnew
	_store_euler(i, r.orthonormalized().get_euler(EULER_ORDER_ZYX))


func _store_euler(i: int, e: Vector3) -> void:
	var b := skel.get_bone_name(i)
	if (b == "kneeL" or b == "kneeR") and e.x < 0.0:
		e.x = 0.0   # a knee never bends forward
	pose[b] = e


func _drag(mm: InputEventMouseMotion) -> void:
	if not _ensure_editable():
		drag_bone = ""
		drag_axis = -1
		return
	var i := skel.find_bone(drag_bone)
	if i < 0:
		return
	var ax := drag_axis
	if ax < 0:
		ax = 0 if Input.is_key_pressed(KEY_X) else (1 if Input.is_key_pressed(KEY_Y) else (2 if Input.is_key_pressed(KEY_Z) else -1))
	if ax >= 0:
		_drag_axis(mm, i, ax)
		return
	if drag_bone == "hips" and not Input.is_key_pressed(KEY_ALT):
		_set_dy(clampf(float(pose.get("_dy", 0.0)) - mm.relative.y * 0.004, -0.9, 0.4))
		_pose_to_sliders()
		return
	if Input.is_key_pressed(KEY_ALT):
		# free rotate: horizontal drag turns about the view's vertical axis, vertical drag about its horizontal axis
		var cb := cam.global_transform.basis
		var w := Basis(cb.y, mm.relative.x * 0.012) * Basis(cb.x, mm.relative.y * 0.012)
		_apply_world_delta(i, _skel_basis_of(w))
	else:
		# swing: turn the bone so its tip follows the mouse
		var o := _bone_o(i)
		var tip := _bone_tip(i)
		var plane := Plane(-cam.global_transform.basis.z, tip)
		var hit: Variant = plane.intersects_ray(cam.project_ray_origin(mm.position), cam.project_ray_normal(mm.position))
		if hit == null:
			return
		var want: Vector3 = ((hit as Vector3) - o).normalized()
		var cur_d := (tip - o).normalized()
		if want.length() < 0.5 or cur_d.length() < 0.5:
			return
		var q := Quaternion(cur_d, want)
		var ang := q.get_angle()
		if ang > 0.6:
			q = Quaternion(q.get_axis(), 0.6)   # never a flip in one step
		_apply_world_delta(i, _skel_basis_of(Basis(q)))
	_apply()
	_pose_to_sliders()


# ---- local / global euler for one bone
func _global_euler(b: String) -> Vector3:
	var i := skel.find_bone(b)
	if i < 0:
		return Vector3.ZERO
	var g := skel.get_bone_global_pose(i).basis * skel.get_bone_global_rest(i).basis.inverse()
	return g.orthonormalized().get_euler(EULER_ORDER_ZYX)


func _set_global_euler(b: String, g: Vector3) -> void:
	var i := skel.find_bone(b)
	if i < 0:
		return
	var par := skel.get_bone_parent(i)
	var pb := skel.get_bone_global_pose(par).basis if par >= 0 else Basis.IDENTITY
	var bg := CBClipLib.rot_basis(g) * skel.get_bone_global_rest(i).basis
	var lnew := pb.inverse() * bg
	var r := skel.get_bone_rest(i).basis.inverse() * lnew
	_store_euler(i, r.orthonormalized().get_euler(EULER_ORDER_ZYX))


# ---- hips height with the feet locked to the ground
func _set_dy(x: float) -> void:
	if clip.is_empty() and ground_lock:
		pose["_dy"] = x
		_apply()
		return
	if not ground_lock:
		pose["_dy"] = x
		_apply()
		return
	# remember where each foot is with the hips at their old height, drop the hips, then bend the legs to bring the feet back
	var old_dy := float(pose.get("_dy", 0.0))
	var targets: Dictionary = {}
	_apply()
	for side in ["L", "R"]:
		targets[side] = skel.get_bone_global_pose(skel.find_bone("foot" + side)).origin
	pose["_dy"] = x
	_apply()
	for side in ["L", "R"]:
		_solve_leg(side, targets[side])
	_apply()
	_pose_to_sliders()


## two-bone leg solve in the hips' own frame: sets thigh X, knee X (>= 0) and keeps the foot level, so the foot origin lands on `target`
func _solve_leg(side: String, target: Vector3) -> void:
	var li := skel.find_bone("leg" + side)
	var ki := skel.find_bone("knee" + side)
	var fi := skel.find_bone("foot" + side)
	var hi := skel.find_bone("hips")
	if li < 0 or ki < 0 or fi < 0 or hi < 0:
		return
	var l1 := skel.get_bone_global_rest(li).origin.distance_to(skel.get_bone_global_rest(ki).origin)
	var l2 := skel.get_bone_global_rest(ki).origin.distance_to(skel.get_bone_global_rest(fi).origin)
	var aim := target
	for iter in 3:
		var hb := skel.get_bone_global_pose(hi).basis
		var hip := skel.get_bone_global_pose(li).origin
		var v := hb.inverse() * (aim - hip)          # target in the hips frame: x side, y up, z forward
		var h := -v.y
		var f := v.z
		var d := clampf(sqrt(h * h + f * f), 0.05, l1 + l2 - 0.002)
		var cos_k := clampf((l1 * l1 + l2 * l2 - d * d) / (2.0 * l1 * l2), -1.0, 1.0)
		var knee := PI - acos(cos_k)
		var cos_t := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
		var thigh := atan2(f, h) + acos(cos_t)       # thigh forward angle
		var e: Vector3 = pose.get("leg" + side, Vector3.ZERO)
		e.x = -thigh
		pose["leg" + side] = e
		var ek: Vector3 = pose.get("knee" + side, Vector3.ZERO)
		ek.x = maxf(knee, 0.0)
		pose["knee" + side] = ek
		var ef: Vector3 = pose.get("foot" + side, Vector3.ZERO)
		ef.x = thigh - knee                           # foot stays level with the floor
		pose["foot" + side] = ef
		_apply()
		var err := target - skel.get_bone_global_pose(fi).origin
		if err.length() < 0.004:
			break
		aim = aim + err


# ---- click on the body to add a socket on the bone under the cursor
func _bone_radius(b: String) -> float:
	for k in BONE_R:
		if b.begins_with(k):
			return BONE_R[k]
	return 0.1


## nearest ray hit on a capsule around each bone: returns {bone, point} or {}
func _ray_body(p: Vector2) -> Dictionary:
	var ro := cam.project_ray_origin(p)
	var rd := cam.project_ray_normal(p)
	var best: Dictionary = {}
	var bt := 1e9
	for i in skel.get_bone_count():
		var a := _bone_o(i)
		var b2 := _bone_tip(i)
		var r := _bone_radius(skel.get_bone_name(i))
		# sample the segment: the closest approach of the ray to each sample, accept if within the radius
		for k in 7:
			var c := a.lerp(b2, float(k) / 6.0)
			var t := (c - ro).dot(rd)
			if t <= 0.0:
				continue
			var closest := ro + rd * t
			var dist := closest.distance_to(c)
			if dist <= r and t < bt:
				bt = t
				var back := sqrt(maxf(r * r - dist * dist, 0.0))
				best = {"bone": skel.get_bone_name(i), "point": ro + rd * (t - back)}
	return best


func _click_add_socket(p: Vector2) -> void:
	var hit := _ray_body(p)
	if hit.is_empty():
		var nb := _pick_bone_at(p)
		if nb == "":
			_say("Nothing under the cursor: click on the character.")
			return
		hit = {"bone": nb, "point": _bone_o(skel.find_bone(nb))}
	var b := str(hit["bone"])
	var bi := skel.find_bone(b)
	var local := skel.get_bone_global_pose(bi).affine_inverse() * (skel.global_transform.affine_inverse() * (hit["point"] as Vector3))
	var n := "%s_%d" % [b, _sock_n]
	while sock_specs.has(n):
		_sock_n += 1
		n = "%s_%d" % [b, _sock_n]
	sock_specs[n] = {"bone": b, "extra": [snappedf(local.x, 0.001), snappedf(local.y, 0.001), snappedf(local.z, 0.001)]}
	_rebuild_sockets()
	_select_socket(n)
	_say("Socket %s added on %s, exactly where you clicked. Drag its offset sliders to fine-tune, or click again for another." % [n, b])


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
	if not _ensure_editable():
		return
	var sd := "L" if left else "R"
	pose["fingers" + sd] = Vector3(-1.2 * amount, 0, 0)
	pose["tips" + sd] = Vector3(-1.0 * amount, 0, 0)
	pose["thumb" + sd] = Vector3(-0.8 * amount, 0, 0)
	_pose_to_sliders()
	_apply()
	_say("%s hand %s (KEY to keep)." % [sd, "closed" if amount > 0.5 else "opened"])


## the user's hand shapes (clip hand_ref, posed on Vix): the RIGHT side of key f as it is, and its true mirror on the left. Every rig
## has identity rests (data/rig_rests.json), so the mirror keeps X and flips Y and Z. fist_f also puts the fist on the fingers.
func _hand_ref(f: int, parts: Array, label: String, fist_f: int = -1) -> void:
	if not _ensure_editable():
		return
	var ref := CBClipLib.load_clip("hand_ref")
	var rot: Dictionary = {}
	var fist_rot: Dictionary = {}
	for k in (ref.get("keys", []) as Array):
		if int((k as Dictionary)["f"]) == f:
			rot = (k as Dictionary)["rot"]
		if int((k as Dictionary)["f"]) == fist_f:
			fist_rot = (k as Dictionary)["rot"]
	if rot.is_empty():
		_say("hand_ref has no key at frame %d." % f)
		return
	var sets: Array = [[rot, parts]]
	if not fist_rot.is_empty():
		sets.append([fist_rot, ["fingers", "tips", "thumb"]])
	for st in sets:
		for b in (st[1] as Array):
			var r: Array = (st[0] as Dictionary).get(str(b) + "R", [0.0, 0.0, 0.0])
			var e := Vector3(float(r[0]), float(r[1]), float(r[2]))
			if skel.find_bone(str(b) + "R") >= 0:
				pose[str(b) + "R"] = e
			if skel.find_bone(str(b) + "L") >= 0:
				pose[str(b) + "L"] = Vector3(e.x, -e.y, -e.z)
	_pose_to_sliders()
	_apply()
	pose_dirty = true
	_say("Hands: %s (your right hand from hand_ref, mirrored to the left). KEY to keep." % label)


## a smooth curl along the tail, root to tip
func _tail_curl() -> void:
	if not _ensure_editable():
		return
	for j in ["tail", "tail2", "tail3"]:
		pose[j] = Vector3(0.0, 0.0, 0.45)
	_pose_to_sliders()
	_apply()
	_say("Tail curled to the side (KEY to keep; the SECONDARY tab makes it swing by itself).")


func _set_rot(axis: int, x: float) -> void:
	if not _ensure_editable():
		return
	if space_global:
		var g := _global_euler(bone_sel)
		g[axis] = x
		_set_global_euler(bone_sel, g)
		_apply()
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
	pose_dirty = true


func _key_frame() -> void:
	if not _ensure_editable():
		return
	var f := int(round(frame))
	var blended := 0
	if key_blend_on:
		# what the clip had at this frame before the edit; the difference is shared with the keys around it
		var before := CBClipLib.pose_at(clip, float(f), bones)
		blended = CBAnimTools.blend_neighbours(clip, f, CBAnimTools.pose_delta(pose, before, bones), key_blend_range, key_blend_kind)
	var rot: Dictionary = {}
	for b in bones:
		var e: Vector3 = pose.get(b, Vector3.ZERO)
		if e.length() > 0.0005:
			rot[b] = [snappedf(e.x, 0.001), snappedf(e.y, 0.001), snappedf(e.z, 0.001)]
	var k := {"f": f, "rot": rot, "hips_dy": snappedf(float(pose.get("_dy", 0.0)), 0.001)}
	if absf(float(pose.get("_dx", 0.0))) > 0.0005:
		k["hips_dx"] = snappedf(float(pose["_dx"]), 0.001)
	if absf(float(pose.get("_dz", 0.0))) > 0.0005:
		k["hips_dz"] = snappedf(float(pose["_dz"]), 0.001)
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
	_save_clip()
	pose_dirty = false
	_say("Key stored at frame %d and saved to %s.json%s." % [int(round(frame)), clip_name, (" (blended into %d neighbouring keys)" % blended) if key_blend_on else ""])


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
	_save_clip()
	_goto_frame(frame)


func _neutral() -> void:
	if not _ensure_editable():
		return
	pose = {}
	for b in bones:
		pose[b] = Vector3.ZERO
	pose["_dy"] = 0.0
	pose["_dx"] = 0.0
	pose["_dz"] = 0.0
	_pose_to_sliders()
	_apply()


func _set_shift(k: String, x: float) -> void:
	if _loading:
		return
	pose[k] = x
	_apply()


## Copy pose / Paste pose: any frame's pose can be put on any other frame (then press SET KEY)
func _copy_pose() -> void:
	pose_copy = pose.duplicate()
	_say("Pose copied. Go to another frame and press Paste pose, then SET KEY.")


func _paste_pose() -> void:
	if pose_copy.is_empty():
		_say("Nothing copied yet: press Copy pose first.")
		return
	if not _ensure_editable():
		return
	pose = pose_copy.duplicate()
	_pose_to_sliders()
	_apply()
	_say("Pasted. Press SET KEY (K) to store it at frame %d." % int(round(frame)))


## drop every edit you have not keyed and show the stored pose of this frame again
func _revert_pose() -> void:
	_goto_frame(frame)
	_say("Back to what the clip stores at frame %d." % int(round(frame)))


## the last frame becomes a copy of the first key, so the clip loops without a jump
func _close_loop() -> void:
	if not _ensure_editable():
		return
	var keys := CBClipLib.sorted_keys(clip)
	if keys.size() < 2:
		return
	var first: Dictionary = keys[0]
	var last_f := _clip_len_frames()
	var n: Dictionary = first.duplicate(true)
	n["f"] = last_f
	var ks: Array = clip["keys"]
	for i in ks.size():
		if int((ks[i] as Dictionary)["f"]) == last_f:
			ks.remove_at(i)
			break
	ks.append(n)
	if int(first["f"]) != 0:
		var z: Dictionary = first.duplicate(true)
		z["f"] = 0
		ks.append(z)
	_reinstall()
	_refresh_keys()
	_save_clip()
	_goto_frame(frame)
	_say("Loop closed: frame %d now equals frame %d." % [last_f, int(first["f"])])


func _mirror(l_to_r: bool) -> void:
	if not _ensure_editable():
		return
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
	_refresh_timeline()
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
	_refresh_timeline()
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
		_save_clip()
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
	if "--posemode" in OS.get_cmdline_user_args():
		_new_clip()
		await get_tree().create_timer(0.3).timeout
		cam_yaw = 0.0
		cam_dist = 3.6
		ground_lock = true
		_set_dy(-0.3)
		bone_sel = "armL"
		drag_bone = "armL"
		var ev := InputEventMouseMotion.new()
		var jp := cam.unproject_position(_bone_o(actor_skel.find_bone("handL")))
		ev.position = jp + Vector2(50, -90)
		ev.relative = Vector2(50, -90)
		_drag(ev)
		_select_socket("fist_R")
		await get_tree().create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("D:/Cache/posemode.png")
		print("STUDIO_SHOT D:/Cache/posemode.png")
		CBClipLib.delete_clip(clip_name)
		get_tree().quit()
		return
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
		CBClipLib.delete_clip(clip_name)
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


# ------------------------------------------------------------------ unbake: a baked clip becomes sparse keys you can edit

func _unbake() -> void:
	if anim == null or not anim.has_animation(clip_name):
		_say("Select a clip first.")
		return
	var src := clip_name
	var c: Dictionary
	if not clip.is_empty():
		# a studio clip that was baked dense (a key on every frame): thin it out, keeping the motion
		c = clip.duplicate(true)
		var before := (c["keys"] as Array).size()
		CBAnimTools.reduce_keys(c, bones, unbake_tol)
		c["name"] = src + "_edit"
		_say("%s: %d keys -> %d (tolerance %.3f rad)." % [src, before, (c["keys"] as Array).size(), unbake_tol])
	else:
		c = CBAnimTools.unbake(anim, skel, src, bones, unbake_step, unbake_tol)
		_say("Unbaked %s into %d keys (a sample every %d frames, redundant ones dropped). The baked original is untouched." % [src, (c["keys"] as Array).size(), unbake_step])
	var n := str(c["name"])
	while CBClipLib.list_clips().has(n):
		n += "x"
	c["name"] = n
	c["override"] = false
	CBClipLib.save_clip(c)
	clip = c
	_reinstall_new(n)


# ------------------------------------------------------------------ ghost blocks

func _build_ghost_tab() -> void:
	var v := VBoxContainer.new()
	v.name = "GHOSTS"
	ui_tabs.add_child(v)
	_label(v, "Ghost blocks: see-through props that live in the clip (an edge to hang from, a crate, a wall). They are never in the game, they are there to animate against. Click one in the view to select it.").autowrap_mode = TextServer.AUTOWRAP_WORD
	var rs := HBoxContainer.new()
	v.add_child(rs)
	var csh := CheckBox.new()
	csh.text = "show ghosts"
	csh.button_pressed = true
	csh.toggled.connect(func(on: bool) -> void:
		ghosts_show = on
		_ghost_update(frame))
	rs.add_child(csh)
	ui_ghost_list = ItemList.new()
	ui_ghost_list.custom_minimum_size = Vector2(0, 90)
	ui_ghost_list.item_selected.connect(func(i: int) -> void:
		ghost_sel = str(ui_ghost_list.get_item_metadata(i))
		_ghost_to_sliders()
		_ghost_update(frame))
	v.add_child(ui_ghost_list)
	var r1 := HBoxContainer.new()
	v.add_child(r1)
	_button(r1, "+ Block", func() -> void: _ghost_add(CBAnimTools.new_ghost("", Vector3(0.0, 0.5, 0.9), Vector3(1.0, 1.0, 1.0))))
	_button(r1, "+ Ledge", func() -> void: _ghost_add(CBAnimTools.ledge_ghost()))
	_button(r1, "Duplicate", _ghost_dup)
	_button(r1, "Delete", _ghost_del)
	ui_ghost_info = _label(v, "")
	ui_ghost_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	for pair_k in [["pos", 0, "x"], ["pos", 1, "y"], ["pos", 2, "z"]]:
		var kk: String = pair_k[0]
		var ax: int = pair_k[1]
		ui_ghost_sl["pos%d" % ax] = _slider(v, "position " + str(pair_k[2]), -4.0, 4.0, 0.01, 0.0, func(x: float) -> void: _ghost_edit(kk, ax, x))
	for pair_s in [["size", 0, "width"], ["size", 1, "height"], ["size", 2, "depth"]]:
		var ax2: int = pair_s[1]
		ui_ghost_sl["size%d" % ax2] = _slider(v, "size " + str(pair_s[2]), 0.05, 8.0, 0.01, 1.0, func(x: float) -> void: _ghost_edit("size", ax2, x))
	ui_ghost_sl["yaw"] = _slider(v, "turn (deg)", -180.0, 180.0, 1.0, 0.0, func(x: float) -> void: _ghost_edit("yaw", 0, x))
	var r2 := HBoxContainer.new()
	v.add_child(r2)
	_button(r2, "KEY ghost this frame", _ghost_key)
	_button(r2, "Clear ghost keys", _ghost_clear_keys)
	_label(v, "A ghost with no keys stays put. KEY ghost stores its position and turn at this frame; from then on the sliders key it as you scrub, and it moves while the clip plays. Size is the same for the whole clip.").autowrap_mode = TextServer.AUTOWRAP_WORD


func _ghosts() -> Array:
	if clip.is_empty():
		return []
	if not clip.has("ghosts"):
		clip["ghosts"] = []
	return clip["ghosts"]


func _ghost_by_name(n: String) -> Dictionary:
	for g in _ghosts():
		if str((g as Dictionary)["name"]) == n:
			return g
	return {}


func _ghost_add(g: Dictionary) -> void:
	if clip.is_empty():
		_say("Select or create a studio clip first (New clip), the ghosts are saved inside it.")
		return
	var base := str(g["name"]) if str(g["name"]) != "" else "block"
	var n := base
	var i := 2
	while not _ghost_by_name(n).is_empty():
		n = "%s%d" % [base, i]
		i += 1
	g["name"] = n
	_ghosts().append(g)
	ghost_sel = n
	_save_clip()
	_ghost_rebuild()
	_say("Ghost '%s' added to %s." % [n, clip_name])


func _ghost_dup() -> void:
	var g := _ghost_by_name(ghost_sel)
	if g.is_empty():
		return
	var c := g.duplicate(true)
	c["name"] = ghost_sel
	var p := CBAnimTools.ghost_vec(c, "pos")
	c["pos"] = [p.x + 0.4, p.y, p.z]
	var gk: Dictionary = clip.get("ghost_keys", {})
	_ghost_add(c)
	if gk.has(ghost_sel):
		pass


func _ghost_del() -> void:
	if ghost_sel == "" or clip.is_empty():
		return
	var gs := _ghosts()
	for i in gs.size():
		if str((gs[i] as Dictionary)["name"]) == ghost_sel:
			gs.remove_at(i)
			break
	(clip.get("ghost_keys", {}) as Dictionary).erase(ghost_sel)
	ghost_sel = ""
	_save_clip()
	_ghost_rebuild()


func _ghost_rebuild() -> void:
	for n in ghost_nodes:
		(ghost_nodes[n] as Node).queue_free()
	ghost_nodes.clear()
	if ui_ghost_list == null:
		return
	ui_ghost_list.clear()
	var gs := _ghosts()
	var found := false
	for g in gs:
		var nm := str((g as Dictionary)["name"])
		var mi := MeshInstance3D.new()
		mi.mesh = BoxMesh.new()
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(str(g.get("color", "#6fb7ff")), 0.28)
		mi.material_override = m
		mi.name = "Ghost_" + nm
		add_child(mi)
		ghost_nodes[nm] = mi
		var i := ui_ghost_list.add_item(nm + ("   (keyed)" if (clip.get("ghost_keys", {}) as Dictionary).has(nm) else ""))
		ui_ghost_list.set_item_metadata(i, nm)
		if nm == ghost_sel:
			ui_ghost_list.select(i)
			found = true
	if not found:
		ghost_sel = ""
		if gs.size() > 0:
			ghost_sel = str((gs[0] as Dictionary)["name"])
			ui_ghost_list.select(0)
	_ghost_to_sliders()
	_ghost_update(frame)


## put every block where it is at this frame; the selected one is brighter
func _ghost_update(f: float) -> void:
	for g in _ghosts():
		var nm := str((g as Dictionary)["name"])
		var mi: MeshInstance3D = ghost_nodes.get(nm)
		if mi == null or not is_instance_valid(mi):
			continue
		var d := CBAnimTools.ghost_at(clip, g, f)
		var sz: Vector3 = d["size"]
		mi.position = d["pos"]
		mi.rotation_degrees = Vector3(0.0, float(d["yaw"]), 0.0)
		mi.scale = sz
		mi.visible = ghosts_show
		(mi.material_override as StandardMaterial3D).albedo_color = Color(str(g.get("color", "#6fb7ff")), 0.24 if nm == ghost_sel else 0.12)


func _ghost_to_sliders() -> void:
	if ui_ghost_info == null:
		return
	var g := _ghost_by_name(ghost_sel)
	if g.is_empty():
		ui_ghost_info.text = "No ghost selected."
		return
	var d := CBAnimTools.ghost_at(clip, g, frame)
	var pos: Vector3 = d["pos"]
	var size: Vector3 = d["size"]
	_loading = true
	for ax in 3:
		(ui_ghost_sl["pos%d" % ax] as HSlider).value = pos[ax]
		(ui_ghost_sl["size%d" % ax] as HSlider).value = size[ax]
		((ui_ghost_sl["pos%d" % ax] as HSlider).get_parent().get_child(2) as Label).text = "%.2f" % pos[ax]
		((ui_ghost_sl["size%d" % ax] as HSlider).get_parent().get_child(2) as Label).text = "%.2f" % size[ax]
	(ui_ghost_sl["yaw"] as HSlider).value = float(d["yaw"])
	((ui_ghost_sl["yaw"] as HSlider).get_parent().get_child(2) as Label).text = "%.0f" % float(d["yaw"])
	_loading = false
	var keyed := (clip.get("ghost_keys", {}) as Dictionary).has(ghost_sel)
	ui_ghost_info.text = "%s: %s" % [ghost_sel, "keyed: the sliders key it at the current frame" if keyed else "static: the sliders move it for the whole clip"]


func _ghost_edit(k: String, axis: int, x: float) -> void:
	if _loading or clip.is_empty():
		return
	var g := _ghost_by_name(ghost_sel)
	if g.is_empty():
		return
	var keyed := (clip.get("ghost_keys", {}) as Dictionary).has(ghost_sel)
	if k == "size":
		var a: Array = g["size"]
		a[axis] = x
	elif keyed:
		var d := CBAnimTools.ghost_at(clip, g, frame)
		var p: Vector3 = d["pos"]
		var yaw := float(d["yaw"])
		if k == "pos":
			p[axis] = x
		else:
			yaw = x
		CBAnimTools.set_ghost_key(clip, ghost_sel, int(round(frame)), p, yaw)
	elif k == "pos":
		var a2: Array = g["pos"]
		a2[axis] = x
	else:
		g["yaw"] = x
	_ghost_update(frame)
	_save_clip()


func _ghost_key() -> void:
	var g := _ghost_by_name(ghost_sel)
	if g.is_empty() or clip.is_empty():
		_say("Select a ghost first.")
		return
	var d := CBAnimTools.ghost_at(clip, g, frame)
	# the first KEY also stores the starting transform at frame 0 so the block does not jump
	if not (clip.get("ghost_keys", {}) as Dictionary).has(ghost_sel) and int(round(frame)) != 0:
		CBAnimTools.set_ghost_key(clip, ghost_sel, 0, d["pos"], float(d["yaw"]))
	CBAnimTools.set_ghost_key(clip, ghost_sel, int(round(frame)), d["pos"], float(d["yaw"]))
	_save_clip()
	_ghost_rebuild()
	_say("Ghost '%s' keyed at frame %d." % [ghost_sel, int(round(frame))])


func _ghost_clear_keys() -> void:
	if ghost_sel == "" or clip.is_empty():
		return
	var g := _ghost_by_name(ghost_sel)
	var d := CBAnimTools.ghost_at(clip, g, frame)
	(clip.get("ghost_keys", {}) as Dictionary).erase(ghost_sel)
	g["pos"] = [d["pos"].x, d["pos"].y, d["pos"].z]
	g["yaw"] = d["yaw"]
	_save_clip()
	_ghost_rebuild()


func _pick_ghost(p: Vector2) -> void:
	var ro := cam.project_ray_origin(p)
	var rd := cam.project_ray_normal(p)
	var best := ""
	var best_t := 1e9
	for nm in ghost_nodes:
		var mi: MeshInstance3D = ghost_nodes[nm]
		if not is_instance_valid(mi) or not mi.visible:
			continue
		var inv := mi.global_transform.affine_inverse()
		var hit: Variant = AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE).intersects_ray(inv * ro, (inv.basis * rd).normalized())
		if hit != null:
			var t := ro.distance_to(mi.global_transform * (hit as Vector3))
			if t < best_t:
				best_t = t
				best = str(nm)
	if best != "":
		ghost_sel = best
		for i in ui_ghost_list.item_count:
			if str(ui_ghost_list.get_item_metadata(i)) == best:
				ui_ghost_list.select(i)
		_ghost_to_sliders()
		_ghost_update(frame)
		_say("Ghost '%s' selected." % best)


## the ledge set: open one of the ledge clips with its ghost edge and a side view of the hands
func _open_ledge(clip_name_to_open: String) -> void:
	if not anim.has_animation(clip_name_to_open):
		_say("No clip %s: run the ledge clip generator first." % clip_name_to_open)
		return
	_select_clip(clip_name_to_open)
	if not clip.is_empty() and _ghosts().is_empty():
		_ghost_add(CBAnimTools.ledge_ghost())
	cam_target = Vector3(0.0, 1.5, 0.3)
	cam_yaw = 1.45
	cam_pitch = 0.1
	cam_dist = 4.2
	for i in ui_tabs.get_tab_count():
		if ui_tabs.get_tab_control(i).name == "GHOSTS":
			ui_tabs.current_tab = 0
	_say("%s opened with its ghost edge. Pose the hands on the edge, KEY, and turn KEY BLEND on to share the edit with the neighbouring keys." % clip_name_to_open)
