class_name FSAApp
extends Control
## FIGHT STUDIO ANIMATOR - the City Breaker / BSP Universe animation app.
##
##   godot --path . res://game/packs/city_breaker/animator/animator.tscn  [-- --fighter=vix --clip=w_walk --layout=4 --api-port=47650]
##
## Every change - a drag in a view, a slider, a menu, a shortcut or an agent over the API - goes through mutate() / key_now(),
## so it is undoable, shows live in every view and window, and lands in the clip file the game reads (data/clips/<name>.json).
## README.md next to this file is the manual; mcp/ holds the MCP server that lets agents animate here.

signal changed(what: String)

const VERSION := "1.0"
const TRASH := "D:/Cache/fight_studio_trash"
const BACKUPS := "D:/Cache/fight_studio_backups"
const RENDERS := "D:/Cache/fight_studio_renders"
const POSES_DIR := "res://game/packs/city_breaker/data/poses/"
const DEFAULT_PORT := 47650

var stage: FSAStage
var dock: FSADock
var canvas: FSACanvas
var dope: FSADope
var graph: FSAGraph
var server: FSAServer
var api: FSAApi
var extra_windows: Array = []

var fighter := "vix"
var skel: Skeleton3D
var bones: Array = []
var doc: FSADoc
var history := FSAHistory.new()
var is_new := false
var frame := 0.0
var playing := false
var speed := 1.0
var play_loop := true
var play_range := Vector2i(0, -1)
var sel_bone := "hips"
var sel_bones: Array = ["hips"]
var sel_keys: Array = []
var sel_socket := ""
var active_layer := ""
var tool := "rotate"
var space_global := false
var autokey := false
var mirror_edit := false
var propagate := "pose"           # off | linked | pose | bone : how an edited key updates "the same key" elsewhere
var keep_end := true              # IK drags keep the hand / foot angle
var move_any := false
var show := {"bones": true, "labels": true, "trail": true, "sockets": false, "onion": false, "props": true, "game_feet": true}
var onion := {"before": 2, "after": 2, "step": 3, "keys": false}
var render_scale := 1.0
var strip_cols := 8
var strip_follow := false
var pending: Dictionary = {}      # an edit at the current frame that is not keyed yet
var overlay: Dictionary = {}
var agent_flash := 0.0
var api_log: Array = []
var status := ""
var ctx: Dictionary = {}
var pose_copy: Dictionary = {}
var keys_copy: Array = []
var focused_view: FSAView
var sock_specs: Dictionary = {}
var ankle_h := 0.0
var api_port := DEFAULT_PORT

var _drag_label := ""
var _drag_start: Dictionary = {}
var _drag_basis: Dictionary = {}
var _trail_key := ""
var _trail: Array = []
var _curves: Dictionary = {}
var _overlay_dirty := true
var _layer_now: Dictionary = {}
var _backed_up: Dictionary = {}
var _status_kind := "info"
var _ui: Dictionary = {}
var _confirm: ConfirmationDialog
var _confirm_action := Callable()
var _prompt: AcceptDialog
var _prompt_edit: LineEdit
var _prompt_action := Callable()


func _ready() -> void:
	theme = FSATheme.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_window()
	var want_clip := ""
	var layout := "4"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fighter="):
			fighter = a.substr(10)
		elif a.begins_with("--clip="):
			want_clip = a.substr(7)
		elif a.begins_with("--layout="):
			layout = a.substr(9)
		elif a.begins_with("--api-port="):
			api_port = int(a.substr(11))
	stage = FSAStage.new()
	add_child(stage)
	doc = FSADoc.blank("untitled", 30, 30)
	if not stage.load_fighter(fighter):
		fighter = "vix"
		stage.load_fighter(fighter)
	_bind_fighter()
	_build_ui(layout)
	if want_clip == "":
		want_clip = "w_walk" if FileAccess.file_exists(CBClipLib.DIR + "w_walk.json") else ""
	if want_clip != "" and not open_clip(want_clip, true):
		say("No clip named %s." % want_clip, "warn")
	if not ("--no-api" in OS.get_cmdline_user_args()):
		server = FSAServer.new()
		server.app = self
		add_child(server)
		if server.start(api_port) != OK:
			say("Agent API could not listen on port %d (another Animator open?)." % api_port, "warn")
	dock.load_saved()
	_apply_now()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot_and_quit(a.substr(7))


func _window() -> void:
	var win := get_window()
	win.gui_embed_subwindows = false
	win.title = "Fight Studio Animator"
	if DisplayServer.get_name() == "headless":
		return
	win.close_requested.connect(_on_close)
	get_tree().auto_accept_quit = false
	# run from the Godot editor with Embed Game on, the editor owns this window: it sizes, moves and closes it. Forcing it
	# maximized and to a minimum size clipped the app and left it stuck, and an embedded game can't open windows of its own,
	# so the "unsaved changes" question never showed. Here dialogs and pop-out panels open inside the app, at scale 1.
	if Engine.is_embedded_in_editor():
		win.gui_embed_subwindows = true
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot=") or a == "--unfocusable":
			win.unfocusable = true   # a screenshot / test run never takes your keyboard
	var scr := DisplayServer.screen_get_usable_rect(win.current_screen)
	win.content_scale_factor = clampf(float(scr.size.y) / 1040.0, 1.0, 2.0)
	if "--windowed" in OS.get_cmdline_user_args() or scr.size.x < 1600:
		win.mode = Window.MODE_WINDOWED
		var w := mini(1920, int(scr.size.x * 0.96))
		win.size = Vector2i(w, mini(int(w * 9.0 / 16.0), int(scr.size.y * 0.94)))
		win.position = scr.position + (scr.size - win.size) / 2
	else:
		win.mode = Window.MODE_MAXIMIZED
	win.min_size = Vector2i(1100, 680)


func _on_close() -> void:
	dock.save()
	if history.dirty():
		ask("\"%s\" has changes that are not saved. Quit anyway?" % doc.name, func() -> void: get_tree().quit())
	else:
		get_tree().quit()


func _bind_fighter() -> void:
	skel = stage.skel
	bones = stage.bones
	CBClipLib.apply_pose(skel, {})
	skel.force_update_all_bone_transforms()
	var lo := INF
	for b in ["footL", "footR"]:
		var i := skel.find_bone(b)
		if i >= 0:
			lo = minf(lo, (skel.global_transform * skel.get_bone_global_pose(i)).origin.y)
	ankle_h = maxf(lo, 0.0) if lo != INF else 0.0
	_load_sockets()
	stage.set_ghost_count(int(onion["before"]) + int(onion["after"]) if bool(show["onion"]) else 0)
	if not (sel_bone in bones):
		sel_bone = "hips"
		sel_bones = ["hips"]


# ================================================================ UI

func _build_ui(layout: String) -> void:
	var bg := Panel.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_theme_stylebox_override("panel", FSATheme._box(FSATheme.BG0, 0, 0))
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)
	root.add_child(FSAMenus.build(self))
	root.add_child(FSAToolbar.build(self))
	dock = FSADock.new(self)
	var left := dock.make_dock("left")
	var rt := dock.make_dock("right_top")
	var rb := dock.make_dock("right_bottom")
	var bottom := dock.make_dock("bottom")
	var main := HSplitContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(main)
	left.custom_minimum_size.x = 270
	left.size_flags_horizontal = Control.SIZE_FILL     # the canvas takes the width, docks keep theirs
	main.add_child(left)
	var mid := HSplitContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(mid)
	var center := VSplitContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(center)
	canvas = FSACanvas.new().setup(self, layout)
	canvas.custom_minimum_size.y = 260
	center.add_child(canvas)
	var low := VBoxContainer.new()
	low.add_theme_constant_override("separation", 0)
	low.custom_minimum_size.y = 220
	center.add_child(low)
	low.add_child(FSAToolbar.transport(self))
	low.add_child(bottom)
	center.split_offset = 260
	var right := VSplitContainer.new()
	right.custom_minimum_size.x = 380
	right.add_child(rt)
	right.add_child(rb)
	right.split_offset = 140
	right.size_flags_horizontal = Control.SIZE_FILL
	rt.size_flags_horizontal = Control.SIZE_FILL
	rb.size_flags_horizontal = Control.SIZE_FILL
	mid.add_child(right)
	mid.split_offset = 0
	root.add_child(FSAToolbar.status_bar(self))
	# panels
	dock.add_panel("Clips", FSAPanels.Clips.new().setup(self), "left")
	dock.add_panel("Poses", FSAPanels.Poses.new().setup(self), "left")
	dock.add_panel("Sockets", FSAPanels.Sockets.new().setup(self), "left")
	dock.add_panel("Properties", FSAPanels.Props.new().setup(self), "right_top")
	dock.add_panel("Controls", FSAPanels.Controls.new().setup(self), "right_top")
	dock.add_panel("Adjust", FSAPanels.Adjust.new().setup(self), "right_top")
	dock.add_panel("Layers", FSAPanels.Layers.new().setup(self), "right_top")
	dock.add_panel("Constraints", FSAPanels.Constraints.new().setup(self), "right_top")
	dock.add_panel("Outliner", FSAPanels.Outliner.new().setup(self), "right_bottom")
	dock.add_panel("Checks", FSAPanels.Checks.new().setup(self), "right_bottom")
	dope = FSADope.new().setup(self)
	dock.add_panel("Dope Sheet", dope, "bottom")
	graph = FSAGraph.new().setup(self)
	dock.add_panel("Graph", graph, "bottom")
	changed.connect(func(w: String) -> void:
		if w != "status" and w != "api":
			dope.queue_redraw()
			graph.queue_redraw())
	dock.add_panel("Blend Lab", FSAPanels.Blend.new().setup(self), "bottom")
	dock.add_panel("Merge", FSAPanels.Merge.new().setup(self), "bottom")
	dock.add_panel("Feet", FSAPanels.Feet.new().setup(self), "bottom")
	dock.add_panel("Agents", FSAPanels.Agents.new().setup(self), "bottom")
	dock.add_panel("History", FSAPanels.History.new().setup(self), "bottom")
	dock.add_panel("Render", FSAPanels.Render.new().setup(self), "bottom")
	_confirm = ConfirmationDialog.new()
	_confirm.title = "Fight Studio"
	_confirm.confirmed.connect(func() -> void:
		if _confirm_action.is_valid():
			_confirm_action.call())
	add_child(_confirm)
	_prompt = AcceptDialog.new()
	_prompt.title = "Fight Studio"
	_prompt_edit = LineEdit.new()
	_prompt_edit.custom_minimum_size.x = 360
	_prompt.add_child(_prompt_edit)
	_prompt.register_text_enter(_prompt_edit)
	_prompt.confirmed.connect(func() -> void:
		if _prompt_action.is_valid():
			_prompt_action.call(_prompt_edit.text.strip_edges()))
	add_child(_prompt)


func ask(text: String, on_yes: Callable) -> void:
	_confirm.dialog_text = text
	_confirm_action = on_yes
	_confirm.popup_centered()


func prompt(text: String, value: String, on_ok: Callable) -> void:
	_prompt.dialog_text = text
	_prompt_edit.text = value
	_prompt_action = on_ok
	_prompt.popup_centered()
	_prompt_edit.grab_focus()
	_prompt_edit.select_all()


func say(t: String, kind: String = "info") -> void:
	status = t
	_status_kind = kind
	changed.emit("status")


func status_color() -> Color:
	return {"warn": FSATheme.ACCENT, "error": FSATheme.RED, "ok": FSATheme.OK, "agent": FSATheme.PURPLE}.get(_status_kind, FSATheme.TEXT)


func focus_view(v: FSAView) -> void:
	focused_view = v


func views() -> Array:
	var out: Array = canvas.views.duplicate()
	for w in extra_windows:
		if is_instance_valid(w) and (w as Window).has_meta("canvas"):
			out.append_array(((w as Window).get_meta("canvas") as FSACanvas).views)
	return out


## a second canvas in its own OS window (a second monitor: the strip there, the quad here)
func new_canvas_window(layout: String = "strip") -> void:
	var w := Window.new()
	w.title = "Fight Studio - canvas"
	w.theme = FSATheme.theme()
	w.size = Vector2i(1280, 720)
	w.position = DisplayServer.mouse_get_position() - Vector2i(200, 100)
	var c := FSACanvas.new().setup(self, layout)
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	w.add_child(c)
	w.set_meta("canvas", c)
	w.close_requested.connect(func() -> void:
		extra_windows.erase(w)
		w.queue_free())
	add_child(w)
	extra_windows.append(w)
	w.show()


func set_layout(l: String) -> void:
	canvas.set_layout(l)
	changed.emit("view")


# ================================================================ frame / playback

func _process(dt: float) -> void:
	if playing:
		var pr := play_range_frames()
		var f := frame + dt * float(doc.fps) * speed
		if f > float(pr.y):
			if play_loop:
				f = float(pr.x) + fmod(f - float(pr.x), maxf(1.0, float(pr.y - pr.x)))
			else:
				f = float(pr.y)
				playing = false
				changed.emit("play")
		frame = f
		_apply_now()
		changed.emit("frame")
	if agent_flash > 0.0:
		agent_flash = maxf(0.0, agent_flash - dt * 0.8)
		canvas.redraw()
	if _overlay_dirty:
		_overlay_dirty = false
		_compute_overlay()
		for v in views():
			(v as FSAView).redraw()


func play_range_frames() -> Vector2i:
	var a := clampi(play_range.x, 0, doc.frames)
	var b := doc.frames if play_range.y < 0 else clampi(play_range.y, a, doc.frames)
	return Vector2i(a, b)


func set_frame(f: float) -> void:
	f = clampf(f, 0.0, float(doc.frames))
	if absf(f - frame) < 0.0001 and pending.is_empty():
		return
	if not pending.is_empty():
		pending = {}
		say("The pose you changed was not keyed (K keys it; turn on AUTO KEY to key every edit).", "warn")
	frame = f
	_apply_now()
	changed.emit("frame")


func step(n: int) -> void:
	playing = false
	set_frame(round(frame) + n)


func goto_key(dir: int) -> void:
	var k := doc.next_key(frame) if dir > 0 else doc.prev_key(frame)
	if k >= 0:
		set_frame(float(k))


func toggle_play() -> void:
	playing = not playing
	if not playing:
		frame = round(frame)
		_apply_now()
	elif not pending.is_empty():
		pending = {}
	changed.emit("play")


# ================================================================ posing

## the pose before constraints at the current frame (an unkeyed edit wins)
func editable_pose() -> Dictionary:
	return pending.duplicate() if not pending.is_empty() else FSAEval.layer_pose(doc, frame, bones)


func final_pose_on(sk: Skeleton3D, f: float) -> Dictionary:
	var p := FSAEval.final_pose(doc, f, sk, bones, ctx)
	sk.force_update_all_bone_transforms()
	return p


func _apply_now() -> void:
	if skel == null or doc == null:
		return
	_layer_now = editable_pose()
	FSAEval.solve_pose(doc, frame, skel, bones, ctx, _layer_now)
	skel.force_update_all_bone_transforms()
	stage.model.position = Vector3.ZERO
	if bool(show["game_feet"]) and doc.plant:
		CBFeet.ground(skel, stage.model, 0.0, true)   # the match's feet: real soles on the floor, flat
	_update_onion()
	if bool(show["props"]) and not doc.props.is_empty():
		stage.place_props(skel, sock_specs)
	_overlay_dirty = true
	if canvas != null and canvas.strip != null and canvas.strip.around_now:
		canvas.mark_strip()


func _update_onion() -> void:
	if not bool(show["onion"]):
		return
	var nb := int(onion["before"])
	var na := int(onion["after"])
	if stage.ghosts.size() != nb + na:
		stage.set_ghost_count(nb + na)
	var fs: Array = []
	if bool(onion["keys"]):
		var f := frame
		for i in nb:
			var k := doc.prev_key(f)
			fs.append(float(k) if k >= 0 else -1.0)
			f = float(k) if k >= 0 else -1.0
		f = frame
		for i in na:
			var k2 := doc.next_key(f)
			fs.append(float(k2) if k2 >= 0 else -1.0)
			f = float(k2) if k2 >= 0 else 1e9
	else:
		for i in nb:
			fs.append(frame - float(onion["step"]) * (i + 1))
		for i in na:
			fs.append(frame + float(onion["step"]) * (i + 1))
	for i in stage.ghosts.size():
		var g: Dictionary = stage.ghosts[i]
		var gf := float(fs[i])
		var node: Node3D = g["node"]
		if gf < 0.0 or gf > float(doc.frames):
			node.visible = false
			continue
		node.visible = true
		final_pose_on(g["skel"], gf)
		var before := i < nb
		var depth := (i if before else i - nb) + 1
		stage.tint_ghost(i, Color(0.35, 0.65, 1.0, 0.32 / depth) if before else Color(1.0, 0.55, 0.2, 0.32 / depth))


func set_onion(on: bool) -> void:
	show["onion"] = on
	stage.set_ghost_count(int(onion["before"]) + int(onion["after"]) if on else 0)
	_apply_now()
	changed.emit("view")


func joint_world(b: String) -> Vector3:
	var i := skel.find_bone(b)
	if i < 0:
		return Vector3.ZERO
	return skel.global_transform * skel.get_bone_global_pose(i).origin


func is_bone_locked(b: String) -> bool:
	return doc.is_locked(b)


func select_bone(b: String, add: bool = false) -> void:
	if not (b in bones):
		return
	if add:
		if b in sel_bones and b != sel_bone:
			sel_bones.erase(b)
		elif not (b in sel_bones):
			sel_bones.append(b)
	else:
		sel_bones = [b]
	sel_bone = b
	_overlay_dirty = true
	changed.emit("sel")


func select_keys(fs: Array, add: bool = false) -> void:
	var out: Array = sel_keys.duplicate() if add else []
	for f in fs:
		if not (int(f) in out):
			out.append(int(f))
	sel_keys = out
	changed.emit("keysel")


func set_tool(t: String) -> void:
	tool = t
	_overlay_dirty = true
	changed.emit("tool")


## start a drag edit (views call this; the pose at the start is kept so the drag never drifts)
func drag_begin(label: String) -> void:
	_drag_label = label
	_drag_start = editable_pose()
	_drag_basis.clear()
	CBClipLib.apply_pose(stage.probe_skel, _drag_start)
	stage.probe_skel.force_update_all_bone_transforms()


func drag_end() -> void:
	if pending.is_empty():
		return
	if autokey:
		key_now(_drag_label)
	else:
		_overlay_dirty = true
		changed.emit("pending")


## turn one bone about a world axis by `angle` (relative to the drag start)
func drag_rotate(bone: String, axis_world: Vector3, angle: float) -> void:
	if _drag_start.is_empty():
		drag_begin("Turn " + bone)
	var pose := rotate_in_pose(_drag_start, bone, axis_world, angle, stage.probe_skel)
	_set_pending(pose)


func rotate_in_pose(base: Dictionary, bone: String, axis_world: Vector3, angle: float, sk: Skeleton3D) -> Dictionary:
	var pose := base.duplicate()
	var bi := sk.find_bone(bone)
	if bi < 0 or doc.is_locked(bone):
		return pose
	var p := sk.get_bone_parent(bi)
	var pb := sk.get_bone_global_pose(p).basis.orthonormalized() if p >= 0 else Basis()
	var rest := sk.get_bone_rest(bi).basis.orthonormalized()
	var own: Vector3 = base.get(bone, Vector3.ZERO)
	var total := CBClipLib.bone_rot(base, bone)
	var axis_s := (sk.global_transform.basis.inverse() * axis_world).normalized()
	var l_old := rest * CBClipLib.rot_basis(total)
	var l_new := pb.inverse() * Basis(axis_s, angle) * pb * l_old
	var e_new := FSAEval.nearest_euler((rest.inverse() * l_new).get_euler(EULER_ORDER_ZYX), total)
	var own_new := e_new - (total - own)
	pose[bone] = doc.guard(bone, own, own_new)
	_mirror_into(pose, bone)
	return pose


func _mirror_into(pose: Dictionary, bone: String) -> void:
	if not mirror_edit:
		return
	var m := FSARig.mirror_name(bone)
	if m == bone or not (m in bones):
		return
	var old: Vector3 = pose.get(m, Vector3.ZERO)
	pose[m] = doc.guard(m, old, FSARig.mirror_euler(pose[bone]))


## slide the whole body (hips shift) by a world offset from the drag start
func drag_move(delta_world: Vector3) -> void:
	if _drag_start.is_empty():
		drag_begin("Move body")
	if doc.is_locked("hips"):
		return
	var pose := _drag_start.duplicate()
	var hi := stage.probe_skel.find_bone("hips")
	var p := stage.probe_skel.get_bone_parent(hi)
	var pb := stage.probe_skel.get_bone_global_pose(p).basis.orthonormalized() if p >= 0 else Basis()
	var d := pb.inverse() * (stage.probe_skel.global_transform.basis.inverse() * delta_world)
	var lock := doc.lock_channels("hips_move")
	pose["_dx"] = float(_drag_start.get("_dx", 0.0)) + (0.0 if "x" in lock else d.x)
	pose["_dy"] = float(_drag_start.get("_dy", 0.0)) + (0.0 if "y" in lock else d.y)
	pose["_dz"] = float(_drag_start.get("_dz", 0.0)) + (0.0 if "z" in lock else d.z)
	_set_pending(pose)


## pull a joint to a world point: hands / feet bend their limb (two-bone IK), other joints bend up to 3 parents (CCD)
func drag_ik(bone: String, target_world: Vector3) -> void:
	if _drag_start.is_empty():
		drag_begin("IK " + bone)
	var sk := stage.probe_skel
	CBClipLib.apply_pose(sk, _drag_start)
	sk.force_update_all_bone_transforms()
	var bi := sk.find_bone(bone)
	if bi < 0:
		return
	var touched: Dictionary = {}
	var limb := FSARig.limb_of_end(bone)
	if limb != "":
		var ids: Array = []
		for b in (FSARig.LIMBS[limb] as Array):
			ids.append(sk.find_bone(str(b)))
		var keep: Variant = sk.get_bone_global_pose(ids[2]).basis.orthonormalized() if keep_end else null
		FSAEval.solve_two_bone(sk, ids[0], ids[1], ids[2], sk.global_transform.affine_inverse() * target_world, FSAEval.auto_pole(sk, limb, ids[0], ids[1], ids[2]), keep, 1.0)
		for i in ids:
			touched[i] = true
	elif bone == "hips":
		drag_move(target_world - joint_world_on(sk, "hips", _drag_start))
		return
	else:
		for i in FSAEval.ccd(sk, bi, target_world):
			touched[i] = true
	var pose := FSAEval.read_back(sk, _drag_start, touched)
	for i in touched:
		var bn := sk.get_bone_name(int(i))
		pose[bn] = doc.guard(bn, _drag_start.get(bn, Vector3.ZERO), pose[bn])
		_mirror_into(pose, bn)
	_set_pending(pose)


func joint_world_on(sk: Skeleton3D, b: String, pose: Dictionary) -> Vector3:
	CBClipLib.apply_pose(sk, pose)
	sk.force_update_all_bone_transforms()
	var i := sk.find_bone(b)
	return sk.global_transform * sk.get_bone_global_pose(i).origin if i >= 0 else Vector3.ZERO


func _set_pending(pose: Dictionary) -> void:
	pending = pose
	_apply_now()
	changed.emit("pending")


## change the pose at the current frame from a panel / the API (keys it at once with auto-key or `key`)
func edit_pose(pose: Dictionary, label: String, key: bool = false, who: String = "you") -> void:
	_set_pending(pose)
	if autokey or key:
		key_now(label, who)


func set_bone_euler(bone: String, e_own: Vector3, label: String = "") -> void:
	var pose := editable_pose()
	pose[bone] = doc.guard(bone, pose.get(bone, Vector3.ZERO), e_own)
	_mirror_into(pose, bone)
	edit_pose(pose, label if label != "" else "Set " + bone)


func set_hips_shift(ax: String, v: float) -> void:
	var pose := editable_pose()
	pose["_" + ax] = v
	edit_pose(pose, "Hips " + ax)


func revert_pending() -> void:
	if pending.is_empty():
		return
	pending = {}
	_apply_now()
	changed.emit("pending")
	say("Unkeyed changes thrown away.")


# ================================================================ document changes

## every document change goes through here: snapshot, change, history, refresh
func mutate(label: String, fn: Callable, who: String = "you") -> void:
	var before := doc.to_dict()
	fn.call()
	doc.normalize()
	history.commit(label, before, doc.to_dict(), who)
	if who != "you":
		agent_flash = 1.0
	_doc_changed()


func _doc_changed() -> void:
	ctx.clear()
	_trail_key = ""
	_curves.clear()
	sel_keys = sel_keys.filter(func(f: int) -> bool: return doc.has_key(f))
	stage.build_props(doc.props, sock_specs)
	_apply_now()
	if canvas != null:
		canvas.mark_strip()
		for w in extra_windows:
			if is_instance_valid(w) and (w as Window).has_meta("canvas"):
				((w as Window).get_meta("canvas") as FSACanvas).mark_strip()
	_update_title()
	changed.emit("doc")


func _update_title() -> void:
	get_window().title = "Fight Studio Animator - %s / %s%s" % [fighter, doc.name, " *" if history.dirty() else ""]


func undo() -> void:
	var e := history.undo()
	if e.is_empty():
		say("Nothing to undo.")
		return
	doc.load_dict(e["before"])
	pending = {}
	_doc_changed()
	say("Undid: " + str(e["label"]))


func redo() -> void:
	var e := history.redo()
	if e.is_empty():
		say("Nothing to redo.")
		return
	doc.load_dict(e["after"])
	pending = {}
	_doc_changed()
	say("Redid: " + str(e["label"]))


# ================================================================ keys

## store the pose at the current frame as a key (into the active layer when one is being edited). Keys that are "the same key"
## (linked, or holding the same pose / bone values, per the propagate mode) take the same change.
func key_now(label: String = "", who: String = "you") -> Dictionary:
	var f := int(round(frame))
	if doc.is_key_locked(f):
		say("The key at f%d is locked (Key menu > Unlock)." % f, "warn")
		return {"ok": false, "error": "key locked"}
	var pose := editable_pose()
	var updated: Array = []
	if active_layer != "" and not doc.layer_by_id(active_layer).is_empty():
		_key_layer(f, pose, label, who)
	else:
		mutate(label if label != "" else "Key f%d" % f, func() -> void:
			var before := doc.write_key(f, pose, bones)
			if not before.is_empty() and propagate != "off":
				updated.append_array(doc.propagate(f, before, pose, bones, propagate)), who)
	pending = {}
	_apply_now()
	var msg := "Keyed f%d" % f
	if not updated.is_empty():
		msg += " - also updated the same key at f" + ", f".join(updated.map(func(x: int) -> String: return str(x)))
	say(msg, "agent" if who != "you" else "ok")
	changed.emit("pending")
	return {"ok": true, "frame": f, "also_updated": updated}


## key into a layer: the layer takes the difference between what you posed and what the other layers already give
func _key_layer(f: int, want: Dictionary, label: String, who: String) -> void:
	var l := doc.layer_by_id(active_layer)
	if str(l.get("source", "keys")) != "keys":
		say("Layer %s plays a clip; pick a keys layer (or the base) to key into." % l.get("name", ""), "warn")
		return
	var now := FSAEval.layer_pose(doc, float(f), bones)
	var w := maxf(0.05, FSAEval.layer_weight(l, float(f), doc.frames))
	var own := FSAEval.layer_value(l, float(f), bones, doc.loop)
	var lp: Dictionary = {}
	for b in bones:
		lp[b] = own.get(b, Vector3.ZERO)
	for b in FSARig.mask_bones(l.get("mask", []) as Array, bones):
		var d: Vector3 = (want.get(b, Vector3.ZERO) as Vector3) - (now.get(b, Vector3.ZERO) as Vector3)
		if d.length() > 1e-6:
			lp[b] = (lp[b] as Vector3) + d / w
	for ax in ["_dy", "_dx", "_dz"]:
		lp[ax] = float(own.get(ax, 0.0)) + (float(want.get(ax, 0.0)) - float(now.get(ax, 0.0))) / w
	mutate(label if label != "" else "Key layer %s f%d" % [l.get("name", ""), f], func() -> void:
		var ks: Array = l.get("keys", [])
		var found := false
		for k in ks:
			if int((k as Dictionary)["f"]) == f:
				FSADoc.fill_key(k, lp, bones)
				found = true
		if not found:
			var nk := {"f": f}
			FSADoc.fill_key(nk, lp, bones)
			ks.append(nk)
		l["keys"] = ks, who)


func delete_keys(fs: Array, who: String = "you") -> void:
	if fs.is_empty():
		fs = [int(round(frame))]
	var locked: Array = fs.filter(func(f: int) -> bool: return doc.is_key_locked(int(f)))
	mutate("Delete keys", func() -> void:
		for f in fs:
			if not doc.is_key_locked(int(f)):
				doc.delete_key(int(f)), who)
	sel_keys = []
	say("Deleted %d key(s)%s." % [fs.size() - locked.size(), (" (%d locked kept)" % locked.size()) if not locked.is_empty() else ""])


func move_keys(fs: Array, delta: int, who: String = "you") -> bool:
	for f in fs:
		var nf := int(f) + delta
		if doc.is_key_locked(int(f)):
			say("A locked key cannot move.", "warn")
			return false
		if nf < 0 or (doc.has_key(nf) and not (nf in fs)):
			say("Keys cannot land on other keys or before frame 0.", "warn")
			return false
	mutate("Move keys %+d" % delta, func() -> void: doc.move_keys(fs, delta), who)
	sel_keys = fs.map(func(f: int) -> int: return int(f) + delta)
	changed.emit("keysel")
	return true


func set_keys_field(fs: Array, field: String, value: Variant, who: String = "you") -> void:
	if fs.is_empty():
		fs = [int(round(frame))]
	mutate("Key %s" % field, func() -> void:
		for f in fs:
			doc.set_key_field(int(f), field, value), who)


func set_key_channel(f: int, bone: String, axis: int, value: float, who: String = "you") -> void:
	var k := doc.key_at(f)
	if k.is_empty():
		return
	if doc.is_key_locked(f) or doc.is_locked(bone, axis):
		say("Locked.", "warn")
		return
	var before := FSADoc.pose_of_key(k, bones)
	var after := before.duplicate()
	var e: Vector3 = after.get(bone, Vector3.ZERO)
	e[axis] = value
	after[bone] = FSARig.clamp_limits(bone, e)
	mutate("Set %s %s f%d" % [bone, ["X", "Y", "Z"][axis], f], func() -> void:
		doc.write_key(f, after, bones)
		if propagate != "off":
			doc.propagate(f, before, after, bones, propagate), who)


func set_key_hips(f: int, ax: String, value: float, who: String = "you") -> void:
	var k := doc.key_at(f)
	if k.is_empty() or doc.is_key_locked(f):
		return
	var before := FSADoc.pose_of_key(k, bones)
	var after := before.duplicate()
	after["_" + ax] = value
	mutate("Hips %s f%d" % [ax, f], func() -> void:
		doc.write_key(f, after, bones)
		if propagate != "off":
			doc.propagate(f, before, after, bones, propagate), who)


func link_keys(fs: Array, who: String = "you") -> void:
	if fs.size() < 2:
		say("Select two or more keys to link (they become the same key: edit one, all follow).", "warn")
		return
	var id := [""]
	mutate("Link keys", func() -> void: id[0] = doc.link_keys(fs, bones, true), who)
	say("Linked f%s as %s: they now share one pose." % [", f".join(fs.map(func(x: int) -> String: return str(x))), id[0]], "ok")


func unlink_keys(fs: Array, who: String = "you") -> void:
	mutate("Unlink keys", func() -> void: doc.unlink_keys(fs), who)


func copy_keys(fs: Array) -> void:
	keys_copy = []
	var lo := 1 << 30
	for f in fs:
		lo = mini(lo, int(f))
	for f in fs:
		var k := doc.key_at(int(f)).duplicate(true)
		k["f"] = int(f) - lo
		k.erase("link")
		k.erase("lock")
		keys_copy.append(k)
	say("Copied %d key(s)." % keys_copy.size())


func paste_keys(at: int, who: String = "you") -> void:
	if keys_copy.is_empty():
		say("No keys copied.", "warn")
		return
	mutate("Paste keys at f%d" % at, func() -> void:
		for k in keys_copy:
			var nf := at + int((k as Dictionary)["f"])
			if doc.is_key_locked(nf):
				continue
			doc.write_key(nf, FSADoc.pose_of_key(k, bones), bones)
			for fld in ["ease", "tag"]:
				if (k as Dictionary).has(fld):
					doc.set_key_field(nf, fld, k[fld]), who)


func mirror_keys(fs: Array, who: String = "you") -> void:
	mutate("Mirror keys", func() -> void:
		for f in fs:
			var k := doc.key_at(int(f))
			if k.is_empty() or bool(k.get("lock", false)):
				continue
			doc.write_key(int(f), mirrored(FSADoc.pose_of_key(k, bones), "flip"), bones), who)


# ================================================================ frames / clip settings

func insert_frames(at: int, n: int, who: String = "you") -> void:
	mutate("Insert %d frames at f%d" % [n, at], func() -> void: doc.insert_frames(at, n), who)


func delete_frames(at: int, n: int, who: String = "you") -> void:
	mutate("Delete %d frames at f%d" % [n, at], func() -> void: doc.delete_frames(at, n), who)
	set_frame(minf(frame, float(doc.frames)))


func scale_time(factor: float, fs: Array = [], who: String = "you") -> void:
	var pivot := 0
	if not fs.is_empty():
		pivot = int(fs.min())
	mutate("Scale time x%.2f" % factor, func() -> void: doc.scale_time(factor, pivot, fs), who)


func reverse_range(a: int, b: int, who: String = "you") -> void:
	mutate("Reverse f%d-f%d" % [a, b], func() -> void: doc.reverse(a, b), who)


func set_clip_prop(prop: String, value: Variant, who: String = "you") -> void:
	mutate("Clip %s" % prop, func() -> void: _clip_prop(prop, value), who)
	if frame > float(doc.frames):
		set_frame(float(doc.frames))


func _clip_prop(prop: String, value: Variant) -> void:
	match prop:
		"frames":
			doc.frames = maxi(1, int(value))
		"fps":
			doc.fps = maxi(1, int(value))
		"loop":
			doc.loop = bool(value)
		"plant":
			doc.plant = bool(value)
		"override":
			doc.override = bool(value)
		"ease":
			doc.ease = str(value)
		"note":
			doc.extra["note"] = str(value)
		"marks":
			doc.extra["marks"] = value


## make the last frame the same key as the first (a seamless loop), linked so they stay the same
func close_loop(who: String = "you") -> void:
	var k0 := doc.key_at(int(doc.key_frames()[0]))
	mutate("Close loop", func() -> void:
		doc.write_key(doc.frames, FSADoc.pose_of_key(k0, bones), bones)
		doc.loop = true
		doc.link_keys([int(k0["f"]), doc.frames], bones, false), who)
	say("Frame %d is now the same key as frame %d (linked): the loop is seamless." % [doc.frames, int(k0["f"])], "ok")


func set_lock(bone: String, channels: String, who: String = "you") -> void:
	mutate("Lock %s %s" % [bone, channels if channels != "" else "off"], func() -> void: doc.set_lock(bone, channels), who)


func toggle_lock_selected() -> void:
	var lock_all := not doc.is_locked(sel_bone)
	mutate("Lock" if lock_all else "Unlock", func() -> void:
		for b in sel_bones:
			doc.set_lock(str(b), "xyz" if lock_all else ""))
	say(("Locked " if lock_all else "Unlocked ") + ", ".join(sel_bones) + (" (frozen: tools cannot change it)" if lock_all else ""))


# ================================================================ pose tools

func mirrored(pose: Dictionary, mode: String) -> Dictionary:
	var out := pose.duplicate()
	for b in bones:
		var m := FSARig.mirror_name(str(b))
		var e: Vector3 = pose.get(b, Vector3.ZERO)
		if m == str(b):
			if mode == "flip":
				out[b] = FSARig.mirror_euler(e)
			continue
		var side := FSARig.side_of(str(b))
		if mode == "flip" or (mode == "l2r" and side == "L") or (mode == "r2l" and side == "R"):
			out[m] = FSARig.mirror_euler(e)
	if mode == "flip":
		out["_dx"] = -float(pose.get("_dx", 0.0))
	return out


func pose_mirror(mode: String, who: String = "you") -> void:
	var p := editable_pose()
	var m := mirrored(p, mode)
	for b in bones:
		m[b] = doc.guard(str(b), p.get(b, Vector3.ZERO), m.get(b, Vector3.ZERO), false)
	edit_pose(m, {"flip": "Flip pose", "l2r": "Mirror L to R", "r2l": "Mirror R to L"}.get(mode, "Mirror"), false, who)


func reset_bones(list: Array, who: String = "you") -> void:
	var p := editable_pose()
	for b in list:
		if str(b) == "hips_move":
			p["_dx"] = 0.0
			p["_dy"] = 0.0
			p["_dz"] = 0.0
		elif not doc.is_locked(str(b)):
			p[b] = doc.guard(str(b), p.get(b, Vector3.ZERO), Vector3.ZERO, false)
	edit_pose(p, "Reset " + (", ".join(list) if list.size() < 4 else "%d bones" % list.size()), false, who)


func copy_pose() -> void:
	pose_copy = editable_pose()
	say("Pose copied (f%d)." % int(round(frame)))


func paste_pose(mirror: bool = false, only_selected: bool = false) -> void:
	if pose_copy.is_empty():
		say("No pose copied.", "warn")
		return
	var src := mirrored(pose_copy, "flip") if mirror else pose_copy
	edit_pose(apply_pose_dict(editable_pose(), src, sel_bones if only_selected else [], 1.0), "Paste pose")


## blend a pose into another: only `only` bones when given, by weight; locks hold
func apply_pose_dict(base: Dictionary, src: Dictionary, only: Array, weight: float) -> Dictionary:
	var out := base.duplicate()
	var list: Array = only if not only.is_empty() else bones
	for b in list:
		if not src.has(b) and not (str(b) in bones):
			continue
		var cur: Vector3 = base.get(b, Vector3.ZERO)
		var want: Vector3 = (src.get(b, Vector3.ZERO) as Vector3)
		out[b] = doc.guard(str(b), cur, cur.lerp(want, weight))
	if only.is_empty() or "hips" in only:
		for ax in ["_dy", "_dx", "_dz"]:
			out[ax] = lerpf(float(base.get(ax, 0.0)), float(src.get(ax, 0.0)), weight)
	return out


## a breakdown: the pose between the keys before and after, leaning toward one side (t 0 = previous key, 1 = next)
func breakdown(t: float, who: String = "you") -> void:
	var a := doc.prev_key(frame + 0.001)
	var b := doc.next_key(frame)
	if a < 0 or b < 0:
		say("A breakdown needs a key before and after this frame.", "warn")
		return
	var pa := FSADoc.pose_of_key(doc.key_at(a), bones)
	var pb := FSADoc.pose_of_key(doc.key_at(b), bones)
	edit_pose(apply_pose_dict(editable_pose(), _lerp_pose(pa, pb, t), [], 1.0), "Breakdown %d%%" % int(t * 100), false, who)


func _lerp_pose(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out: Dictionary = {}
	for bn in bones:
		out[bn] = (a.get(bn, Vector3.ZERO) as Vector3).lerp(b.get(bn, Vector3.ZERO), t)
	for ax in ["_dy", "_dx", "_dz"]:
		out[ax] = lerpf(float(a.get(ax, 0.0)), float(b.get(ax, 0.0)), t)
	return out


func set_control(ctl: Dictionary, value: float, who: String = "you") -> void:
	var p := editable_pose()
	var np := FSARig.set_control(ctl, p, value)
	for b in bones:
		np[b] = doc.guard(str(b), p.get(b, Vector3.ZERO), np.get(b, Vector3.ZERO))
	edit_pose(np, "Control " + str(ctl.get("name", "")), false, who)


# ---- pose library (data/poses/<name>.json)

func list_poses() -> Array:
	var out: Array = []
	if DirAccess.dir_exists_absolute(POSES_DIR):
		for f in DirAccess.get_files_at(POSES_DIR):
			if f.ends_with(".json"):
				out.append(f.get_basename())
	out.sort()
	return out


func save_library_pose(pname: String, only_selected: bool = false) -> bool:
	pname = pname.strip_edges().replace(" ", "_")
	if pname == "" or not pname.is_valid_filename():
		say("Not a good pose name.", "warn")
		return false
	var p := editable_pose()
	var rot: Dictionary = {}
	for b in (sel_bones if only_selected else bones):
		var e: Vector3 = p.get(b, Vector3.ZERO)
		if e.length_squared() > 1e-10 or only_selected:
			rot[b] = [snappedf(e.x, 0.0001), snappedf(e.y, 0.0001), snappedf(e.z, 0.0001)]
	var d := {"name": pname, "rot": rot, "hips_dy": p.get("_dy", 0.0), "hips_dx": p.get("_dx", 0.0), "hips_dz": p.get("_dz", 0.0),
		"partial": only_selected, "from": "%s f%d" % [doc.name, int(round(frame))]}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(POSES_DIR))
	var f := FileAccess.open(POSES_DIR + pname + ".json", FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(d, "  "))
	f.close()
	say("Saved pose \"%s\"." % pname, "ok")
	changed.emit("poses")
	return true


func load_library_pose(pname: String) -> Dictionary:
	var f := FileAccess.open(POSES_DIR + pname + ".json", FileAccess.READ)
	if f == null:
		return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return d if typeof(d) == TYPE_DICTIONARY else {}


func apply_library_pose(pname: String, only_selected: bool, weight: float, mirror: bool, who: String = "you") -> bool:
	var d := load_library_pose(pname)
	if d.is_empty():
		return false
	var p := FSADoc.pose_of_key({"rot": d.get("rot", {}), "hips_dy": d.get("hips_dy", 0.0), "hips_dx": d.get("hips_dx", 0.0), "hips_dz": d.get("hips_dz", 0.0)}, bones)
	if mirror:
		p = mirrored(p, "flip")
	var only: Array = sel_bones if only_selected else []
	if bool(d.get("partial", false)) and only.is_empty():
		only = (d.get("rot", {}) as Dictionary).keys()
	edit_pose(apply_pose_dict(editable_pose(), p, only, weight), "Pose " + pname, false, who)
	return true


# ================================================================ layers / constraints

func add_layer(def: Dictionary, who: String = "you") -> Dictionary:
	var made := [{}]
	mutate("Add layer", func() -> void: made[0] = doc.add_layer(def), who)
	return made[0]


func set_layer(id: String, props: Dictionary, who: String = "you") -> void:
	var l := doc.layer_by_id(id)
	if l.is_empty():
		return
	if props.has("clip"):
		FSAEval.forget_clips()
	mutate("Layer %s" % ", ".join(props.keys()), func() -> void:
		for k in props:
			l[k] = props[k], who)


func remove_layer(id: String, who: String = "you") -> void:
	if active_layer == id:
		active_layer = ""
	mutate("Remove layer", func() -> void: doc.remove_by_id(doc.layers, id), who)


func set_active_layer(id: String) -> void:
	active_layer = id
	pending = {}
	_apply_now()
	var l := doc.layer_by_id(id)
	say("Keys now go into layer \"%s\"." % l.get("name", "") if not l.is_empty() else "Keys now go into the base clip.", "info")
	changed.emit("layer")


func add_constraint(def: Dictionary, who: String = "you") -> Dictionary:
	var made := [{}]
	if str(def.get("type", "")) in ["ik"] and (def.get("target", {}) as Dictionary).is_empty():
		var end := str((FSARig.LIMBS.get(str(def.get("limb", "")), ["", "", ""]) as Array)[2])
		if end != "":
			var p := joint_world(end)
			def["target"] = {"pos": [snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001)]}
	if str(def.get("type", "")) == "aim" and (def.get("target", {}) as Dictionary).is_empty():
		var h := joint_world(str(def.get("bone", "head")))
		def["target"] = {"pos": [snappedf(h.x, 0.001), snappedf(h.y, 0.001), snappedf(h.z + 1.5, 0.001)]}
	if str(def.get("type", "")) == "pin" and not def.has("pin_frame"):
		def["pin_frame"] = int(round(frame))
		if not def.has("start"):
			def["start"] = int(round(frame))
	mutate("Add %s" % str(def.get("type", "constraint")), func() -> void: made[0] = doc.add_constraint(def), who)
	return made[0]


func set_constraint(id: String, props: Dictionary, who: String = "you") -> void:
	var c := doc.constraint_by_id(id)
	if c.is_empty():
		return
	mutate("Constraint %s" % ", ".join(props.keys()), func() -> void:
		for k in props:
			c[k] = props[k], who)


func remove_constraint(id: String, who: String = "you") -> void:
	mutate("Remove constraint", func() -> void: doc.remove_by_id(doc.constraints, id), who)


func move_constraint(id: String, dir: int) -> void:
	mutate("Reorder constraints", func() -> void:
		for i in doc.constraints.size():
			if str((doc.constraints[i] as Dictionary)["id"]) == id:
				var j := clampi(i + dir, 0, doc.constraints.size() - 1)
				var c: Variant = doc.constraints[i]
				doc.constraints.remove_at(i)
				doc.constraints.insert(j, c)
				return)


## freeze the selected bone where it is now (a hand on a wall, a planted foot) from this frame to `end` (-1: to the end)
func pin_selected(end: int = -1, who: String = "you") -> void:
	add_constraint({"type": "pin", "bone": sel_bone, "what": "both", "pin_frame": int(round(frame)), "start": int(round(frame)), "end": end, "name": "FREEZE " + sel_bone}, who)
	say("%s is frozen in the world from f%d (Constraints panel: range, influence, blend)." % [sel_bone, int(round(frame))], "ok")


## layers and constraints become plain keys (a key per frame) and are switched off: what the game plays, fully editable
func bake_to_keys(who: String = "you") -> void:
	var baked := FSAEval.bake(doc, stage.probe_skel, bones, ctx)
	mutate("Bake layers + constraints into keys", func() -> void:
		doc.keys = baked
		for l in doc.layers:
			(l as Dictionary)["mute"] = true
		for c in doc.constraints:
			(c as Dictionary)["enabled"] = false, who)
	say("Baked %d frames into keys; layers muted, constraints off (undo brings them back)." % baked.size(), "ok")


## Adjust (core/adjust.gd): `bone` turned by `turn` (radians, the total for this span) on top of its keys, over a scope:
## "all" frames, "frame" = around frame `at` (-1: the current one) easing over `ease` frames, "range" = from..to (to -1: the end).
## mirror: the other side gets the mirrored turn. A zero turn removes the adjustment. Returns the adjustment layers.
func adjust_part(bone: String, turn: Vector3, scope: String = "all", at: int = -1, from: int = 0, to: int = -1, ease: int = 6,
		mirror: bool = false, who: String = "you") -> Array:
	if skel == null or skel.find_bone(bone) < 0:
		say("No bone %s on %s." % [bone, fighter], "warn")
		return []
	if at < 0:
		at = int(round(frame))
	if to < 0:
		to = doc.frames
	var sp := FSAAdjust.span(scope, at, from, to, ease)
	var targets: Array = [[bone, turn]]
	if mirror and FSARig.is_side(bone) and skel.find_bone(FSARig.mirror_name(bone)) >= 0:
		targets.append([FSARig.mirror_name(bone), FSARig.mirror_euler(turn)])
	var out: Array = []
	mutate("Adjust %s" % bone, func() -> void:
		for t in targets:
			var b: String = t[0]
			var v: Vector3 = t[1]
			var l := FSAAdjust.find(doc, b, scope, sp)
			if v.length() < 1e-5:
				if not l.is_empty():
					doc.remove_by_id(doc.layers, str(l["id"]))
				continue
			var def := FSAAdjust.layer_def(b, scope, sp, v)
			if l.is_empty():
				out.append(doc.add_layer(def))
			else:
				for k in def:
					l[k] = def[k]
				out.append(l), who)
	return out


## the turn an adjustment of `bone` with this scope has now (radians; zero = none)
func adjust_value(bone: String, scope: String = "all", at: int = -1, from: int = 0, to: int = -1, ease: int = 6) -> Vector3:
	if at < 0:
		at = int(round(frame))
	if to < 0:
		to = doc.frames
	return FSAAdjust.value(FSAAdjust.find(doc, bone, scope, FSAAdjust.span(scope, at, from, to, ease)))


## take an adjustment off (its id), or every adjustment of a bone, or all of them (bone "")
func adjust_restore(id: String = "", bone: String = "", who: String = "you") -> int:
	var gone := FSAAdjust.adjust_layers(doc).filter(func(l: Dictionary) -> bool:
		return (id != "" and str(l["id"]) == id) or (id == "" and (bone == "" or str(l.get("bone", "")) == bone)))
	if gone.is_empty():
		return 0
	mutate("Restore %s" % (bone if bone != "" else ("adjustment" if id != "" else "all adjustments")), func() -> void:
		for l in gone:
			doc.remove_by_id(doc.layers, str(l["id"])), who)
	say("Restored %d adjustment%s: the keys are as they were." % [gone.size(), "" if gone.size() == 1 else "s"], "ok")
	return gone.size()


## Merge (core/merge.gd): `clip` on top of the open clip, giving only `parts` (FSAMerge.PARTS), its frame 0 at `start`
## (-1: the current frame), blending in and out over that many frames
func merge_add(clip: String, parts: Array = FSAMerge.DEFAULT_PARTS, start: int = -1, blend_in: int = 10, blend_out: int = 10,
		weight: float = 1.0, cycle: bool = false, who: String = "you") -> Dictionary:
	if FSAEval.clip_src(clip).is_empty():
		say("No clip named %s." % clip, "warn")
		return {}
	if start < 0:
		start = int(round(frame))
	var l := add_layer(FSAMerge.layer_def(clip, parts, start, blend_in, blend_out, weight, cycle), who)
	say("%s on top from f%d (%s). Play to see it; Bake makes one clip." % [clip, start, ", ".join(PackedStringArray(parts))], "agent" if who != "you" else "ok")
	return l


## change a clip on top: parts, start, blend_in / blend_out, weight, cycle, speed, mute (the fields that follow move with it)
func merge_set(id: String, props: Dictionary, who: String = "you") -> void:
	var l := doc.layer_by_id(id)
	if l.is_empty():
		return
	var p := props.duplicate()
	if p.has("blend_in"):
		p["fade_in"] = p["blend_in"]
		p.erase("blend_in")
	if p.has("blend_out"):
		p["fade_out"] = p["blend_out"]
		p.erase("blend_out")
	set_layer(id, FSAMerge.follow(l, p), who)


## the merge as ONE new clip (opens unsaved; the base clip is not touched)
func merge_bake(new_name: String, who: String = "you") -> Dictionary:
	if not _good_name(new_name):
		return {"error": "bad clip name"}
	if FSAMerge.merge_layers(doc).is_empty():
		say("Add a clip on top first (Merge panel).", "warn")
		return {"error": "no clips on top"}
	var base := doc.name
	var nd := FSAMerge.bake(doc, stage.probe_skel, bones, new_name)
	_set_doc(nd, true)
	if who != "you":
		agent_flash = 1.0
	say("Merged into %s: %d frames, %d keys (%s is unchanged). Save it to keep it." % [new_name, nd.frames, nd.keys.size(), base], "agent" if who != "you" else "ok")
	return {"name": new_name, "frames": nd.frames, "keys": nd.keys.size(), "base": base}


## a merged clip's recipe back as a live setup: its base opens with the clips on top again (changes to the open clip are lost)
func merge_rebuild(who: String = "you") -> bool:
	var r: Dictionary = doc.extra.get("merge", {})
	if r.is_empty():
		return false
	var made_from := doc.name
	if not open_clip(str(r.get("base", "")), true):
		say("The base clip %s is gone." % r.get("base", ""), "warn")
		return false
	for d in (r.get("layers", []) as Array):
		var dd: Dictionary = d
		add_layer(FSAMerge.layer_def(str(dd["clip"]), dd.get("parts", FSAMerge.DEFAULT_PARTS), int(dd.get("start", 0)), int(dd.get("blend_in", 0)),
			int(dd.get("blend_out", 0)), float(dd.get("weight", 1.0)), bool(dd.get("cycle", false)), float(dd.get("speed", 1.0))), who)
	say("Rebuilt the merge behind %s: %s with %d clips on top." % [made_from, doc.name, (r.get("layers", []) as Array).size()], "ok")
	return true


## a new clip from a blend: this clip, then `clip_b` taking over at `at` over `blend` frames (a transition you can edit)
func make_transition_clip(clip_b: String, at: int, blend: int, new_name: String, who: String = "you") -> bool:
	var cb := FSAEval.clip_src(clip_b)
	if cb.is_empty():
		say("No clip named %s." % clip_b, "warn")
		return false
	var tmp := FSADoc.from_clip(doc.to_clip())
	tmp.add_layer({"name": "to " + clip_b, "mode": "override", "source": "clip", "clip": clip_b, "offset": at, "cycle": bool(cb.get("loop", false)), "start": at, "fade_in": blend})
	tmp.frames = at + int(cb.get("frames", 24))
	tmp.constraints = []
	var baked := FSAEval.bake(tmp, stage.probe_skel, bones, {})
	var nd := FSADoc.blank(new_name, tmp.frames, doc.fps)
	nd.keys = baked
	nd.loop = false
	nd.plant = doc.plant
	nd.extra["note"] = "Blend Lab: %s -> %s at f%d over %d frames" % [doc.name, clip_b, at, blend]
	_set_doc(nd, true)
	say("Made %s (%d frames). Save it to keep it." % [new_name, nd.frames], "ok")
	return true


# ================================================================ clips

func list_clips(filter: String = "") -> Array:
	var out: Array = []
	for n in CBClipLib.list_clips():
		if filter == "" or str(n).contains(filter):
			out.append(n)
	return out


func baked_clips() -> Array:
	var aps := stage.model.find_children("*", "AnimationPlayer", true, false)
	if aps.is_empty():
		return []
	var out: Array = Array((aps[0] as AnimationPlayer).get_animation_list())
	out.sort()
	return out


func open_clip(cname: String, discard: bool = false) -> bool:
	if history.dirty() and not discard:
		ask("\"%s\" has changes that are not saved. Open \"%s\" anyway (changes are lost)?" % [doc.name, cname], func() -> void: open_clip(cname, true))
		return false
	var c := CBClipLib.load_clip(cname)
	if c.is_empty():
		return false
	_set_doc(FSADoc.from_clip(c), false)
	if doc.outside_edit:
		say("%s was changed outside the Animator after it was baked: those keys are the base now, layers and constraints are off." % cname, "warn")
	else:
		say("Opened %s (%d frames @ %d fps, %d keys)." % [cname, doc.frames, doc.fps, doc.keys.size()])
	return true


## outside motion (a Mixamo FBX, a GLB / glTF with a Mixamo-style skeleton) onto our rig as a new, unsaved clip
## (FSAMotionImport). opts: name, anim, in_place, limits, fingers, plant, loop, tolerance. Returns the import report or {"error"}.
func import_motion(path: String, opts: Dictionary = {}, who: String = "you") -> Dictionary:
	var holder := Node3D.new()
	holder.visible = false
	add_child(holder)
	var src := FSAMotionImport.load_source(path, holder)
	var r := FSAMotionImport.retarget(src, skel, opts)
	holder.queue_free()
	if r.has("error"):
		say("Import: %s." % r["error"], "error")
		return r
	if str((r["clip"] as Dictionary)["name"]) != "" and not _good_name(str((r["clip"] as Dictionary)["name"])):
		return {"error": "bad clip name"}
	_set_doc(FSADoc.from_clip(r["clip"]), true)
	var rep: Dictionary = r["report"]
	if who != "you":
		agent_flash = 1.0
	say("Imported %s from %s: %d bones, %d frames, %d keys%s%s%s. Save it to keep it." % [rep["name"], path.get_file(), rep["bones"],
		rep["frames"], rep["keys"], ", loops" if rep["loop"] else "", ", planted" if rep["plant"] else "",
		(", %d joint turns kept inside the rig limits" % rep["clamped"]) if int(rep["clamped"]) > 0 else ""], "agent" if who != "you" else "ok")
	return rep


## a baked GLB animation as an editable clip: sampled into keys (a key every `step` frames, flat stretches thinned)
func open_baked(anim_name: String) -> bool:
	var aps := stage.probe.find_children("*", "AnimationPlayer", true, false)
	if aps.is_empty():
		return false
	var ap := aps[0] as AnimationPlayer
	if not ap.has_animation(anim_name):
		return false
	var c := CBAnimTools.unbake(ap, stage.probe_skel, anim_name, bones, 2, 0.02)
	ap.active = false
	_set_doc(FSADoc.from_clip(c), true)
	say("Unbaked %s into %s (%d keys). Save it to keep it; the GLB is not touched." % [anim_name, doc.name, doc.keys.size()], "ok")
	return true


func _set_doc(d: FSADoc, as_new: bool) -> void:
	doc = d
	is_new = as_new
	history.clear()
	if as_new:
		history.saved_at = -1
	pending = {}
	sel_keys = []
	active_layer = ""
	frame = 0.0
	playing = false
	play_range = Vector2i(0, -1)
	_doc_changed()
	changed.emit("clip")


func new_clip(cname: String, n_frames: int, fps: int, looped: bool, from_pose: bool, who: String = "you") -> bool:
	cname = cname.strip_edges()
	if not _good_name(cname):
		return false
	var start := editable_pose()
	var d := FSADoc.blank(cname, n_frames, fps, looped)
	if from_pose:
		d.write_key(0, start, bones)
		if looped:
			d.write_key(n_frames, start, bones)
			d.link_keys([0, n_frames], bones, false)
	_set_doc(d, true)
	say("New clip %s. Pose it, key it (K), save it (Ctrl+S)." % cname, "ok")
	if who != "you":
		agent_flash = 1.0
	return true


func _good_name(n: String) -> bool:
	var re := RegEx.new()
	re.compile("^[A-Za-z0-9_\\-]+$")
	if re.search(n) == null:
		say("Clip names use letters, digits, _ and - only.", "warn")
		return false
	return true


func save(who: String = "you") -> Dictionary:
	if doc.name == "" or doc.name == "untitled":
		prompt("Name for this clip:", "my_clip", func(n: String) -> void: save_as(n))
		return {"ok": false, "error": "needs a name"}
	var path := CBClipLib.DIR + doc.name + ".json"
	if FileAccess.file_exists(path) and not _backed_up.has(doc.name):
		DirAccess.make_dir_recursive_absolute(BACKUPS)
		DirAccess.copy_absolute(ProjectSettings.globalize_path(path), "%s/%s_%s.json" % [BACKUPS, doc.name, Time.get_datetime_string_from_system().replace(":", "-")])
		_backed_up[doc.name] = true
	var baked: Array = []
	if doc.needs_bake():
		doc.baked_on = fighter
		baked = FSAEval.bake(doc, stage.probe_skel, bones, {})
	var was := doc.saved
	doc.saved = Time.get_datetime_string_from_system()
	var err := CBClipLib.save_clip(doc.to_clip(baked))
	if err != OK:
		doc.saved = was
		say("Could not save %s (error %d)." % [doc.name, err], "error")
		return {"ok": false, "error": "write failed %d" % err}
	FSAEval.forget_clips()
	history.mark_saved()
	is_new = false
	_update_title()
	say("Saved %s%s.%s" % [doc.name, " (layers + constraints baked for the game)" if not baked.is_empty() else "",
		" It is yours now: the clip generators (gen_*.py) leave it alone." if was == "" else ""], "agent" if who != "you" else "ok")
	changed.emit("saved")
	return {"ok": true, "path": ProjectSettings.globalize_path(path), "baked": not baked.is_empty(), "saved": doc.saved}


func save_as(n: String, who: String = "you") -> Dictionary:
	if not _good_name(n):
		return {"ok": false, "error": "bad name"}
	doc.name = n
	history.saved_at = -1
	return save(who)


## clips are never deleted: they move to D:/Cache/fight_studio_trash
func trash_clip(n: String) -> bool:
	var p := ProjectSettings.globalize_path(CBClipLib.DIR + n + ".json")
	if not FileAccess.file_exists(p):
		return false
	DirAccess.make_dir_recursive_absolute(TRASH)
	var dst := "%s/%s_%s.json" % [TRASH, n, Time.get_datetime_string_from_system().replace(":", "-")]
	if DirAccess.copy_absolute(p, dst) != OK:
		return false
	DirAccess.remove_absolute(p)
	say("Moved %s to %s." % [n, TRASH])
	changed.emit("clips")
	return true


func set_fighter(k: String) -> bool:
	if not stage.load_fighter(k):
		say("No model for %s." % k, "warn")
		return false
	fighter = k
	_bind_fighter()
	for v in views():
		(v as FSAView).frame_body()
	_doc_changed()
	changed.emit("fighter")
	return true


# ================================================================ sockets

func _load_sockets() -> void:
	sock_specs = {}
	for n in (CBSockets.data().get("sockets", {}) as Dictionary):
		sock_specs[n] = CBSockets.spec(fighter, str(n))


func socket_world(n: String) -> Vector3:
	var sp: Dictionary = sock_specs.get(n, {})
	var bi := skel.find_bone(str(sp.get("bone", "")))
	if bi < 0:
		return Vector3.ZERO
	var g := skel.global_transform * skel.get_bone_global_pose(bi)
	var p := g * CBSockets.offset(skel, bi, sp)
	if bool(sp.get("ground", false)):
		p.y = 0.0
	return p


func save_sockets(this_fighter_only: bool) -> void:
	var d: Dictionary = CBSockets.data().duplicate(true)
	if this_fighter_only:
		var fd: Dictionary = (d.get("fighters", {}) as Dictionary).get(fighter, {})
		for n in sock_specs:
			var shared: Dictionary = (d.get("sockets", {}) as Dictionary).get(n, {})
			var diff: Dictionary = {}
			for k in sock_specs[n]:
				if not shared.has(k) or str(shared[k]) != str(sock_specs[n][k]):
					diff[k] = sock_specs[n][k]
			if not diff.is_empty():
				fd[n] = diff
		if not d.has("fighters"):
			d["fighters"] = {}
		d["fighters"][fighter] = fd
	else:
		for n in sock_specs:
			d["sockets"][n] = sock_specs[n]
	CBSockets.save_data(d)
	CBSockets._data = {}
	_load_sockets()
	say("Sockets saved (%s)." % ("this fighter only" if this_fighter_only else "every fighter"), "ok")


# ================================================================ overlay data for the views

func _compute_overlay() -> void:
	if skel == null:
		return
	var joints: Array = []
	var con_bones: Dictionary = {}
	for c in doc.constraints:
		var cd: Dictionary = c
		if not bool(cd.get("enabled", true)):
			continue
		if cd.has("limb"):
			for b in (FSARig.LIMBS.get(str(cd["limb"]), []) as Array):
				con_bones[b] = true
		if cd.has("bone"):
			con_bones[str(cd["bone"])] = true
	for i in skel.get_bone_count():
		var b := skel.get_bone_name(i)
		if b == "root" or b.begins_with("nail"):
			continue
		var pos := skel.global_transform * skel.get_bone_global_pose(i).origin
		var tip := pos
		var kids := skel.get_bone_children(i)
		if not kids.is_empty():
			tip = skel.global_transform * skel.get_bone_global_pose(kids[0]).origin
		else:
			var p := skel.get_bone_parent(i)
			if p >= 0:
				var pp := skel.global_transform * skel.get_bone_global_pose(p).origin
				tip = pos + (pos - pp).normalized() * minf(0.08, pos.distance_to(pp) * 0.6)
		var side := FSARig.side_of(b)
		var col := FSATheme.GOLD if side == "" else (FSATheme.LEFT if side == "L" else FSATheme.RIGHT)
		var grp := FSARig.group_of(b)
		if grp in ["Hand L", "Hand R", "Ears", "Tail", "Extras"]:
			col = col.darkened(0.15)
		if doc.is_locked(b):
			col = FSATheme.MUTED
		var shown := true
		if grp in ["Hand L", "Hand R"] and not bool(show.get("fingers", false)):
			shown = FSARig.group_of(sel_bone) == grp or b in ["fingersL", "fingersR", "thumbL", "thumbR"]
		joints.append({"bone": b, "pos": pos, "tip": tip, "color": col, "sel": b in sel_bones, "locked": doc.is_locked(b),
			"ik": con_bones.has(b), "shown": shown})
	overlay["joints"] = joints
	# constraint targets
	var targets: Array = []
	for c in doc.constraints:
		var cd: Dictionary = c
		if not bool(cd.get("enabled", true)):
			continue
		match str(cd.get("type", "")):
			"ik", "aim":
				targets.append({"pos": FSAEval.target_point(cd.get("target", {}) as Dictionary, frame, skel), "color": FSATheme.PURPLE, "label": str(cd.get("name", ""))})
			"pin":
				var cap: Variant = ctx.get("pin:" + str(cd.get("id", "")))
				if cap is Transform3D:
					targets.append({"pos": FSAEval.s2w(skel, (cap as Transform3D).origin), "color": FSATheme.OK, "label": str(cd.get("name", ""))})
	overlay["targets"] = targets
	var socks: Array = []
	if bool(show["sockets"]):
		for n in sock_specs:
			socks.append({"name": str(n), "pos": socket_world(str(n))})
	overlay["sockets"] = socks
	if bool(show["trail"]):
		var key := "%s|%d" % [sel_bone, history.undo_stack.size()]
		if key != _trail_key:
			_trail_key = key
			_trail = []
			var bi := stage.probe_skel.find_bone(sel_bone)
			if bi >= 0:
				for f in doc.frames + 1:
					final_pose_on(stage.probe_skel, float(f))
					_trail.append(stage.probe_skel.global_transform * stage.probe_skel.get_bone_global_pose(bi).origin)
		overlay["trail"] = _trail
		overlay["trail_keys"] = doc.key_frames()
		overlay["trail_now"] = int(round(frame))
	else:
		overlay["trail"] = []


## curves for the graph editor: the selected bone's rotation per frame (before / after constraints) and the hips shift
func graph_curves(bone: String) -> Dictionary:
	var key := "%s|%d" % [bone, history.undo_stack.size()]
	if _curves.has(key):
		return _curves[key]
	var lay: Array = []
	var fin: Array = []
	var hips: Array = []
	var hips_f: Array = []
	var live := FSAEval.has_live_constraints(doc)
	for f in doc.frames + 1:
		var lp := FSAEval.layer_pose(doc, float(f), bones)
		lay.append(lp.get(bone, Vector3.ZERO))
		hips.append(Vector3(float(lp.get("_dx", 0.0)), float(lp.get("_dy", 0.0)), float(lp.get("_dz", 0.0))))
		if live:
			var fp := FSAEval.solve_pose(doc, float(f), stage.probe_skel, bones, ctx, lp)
			fin.append(fp.get(bone, Vector3.ZERO))
			hips_f.append(Vector3(float(fp.get("_dx", 0.0)), float(fp.get("_dy", 0.0)), float(fp.get("_dz", 0.0))))
	_curves.clear()
	_curves[key] = {"layer": lay, "final": fin, "hips": hips, "hips_final": hips_f}
	return _curves[key]


func cue_frames() -> Array:
	var out: Array = []
	for c in CBCues.for_clip(doc.name):
		out.append(float((c as Dictionary).get("t", 0.0)) * float(doc.fps))   # cues are timed in seconds
	return out


# ================================================================ checks

func run_checks() -> Array:
	var out: Array = []
	for k in doc.keys:
		var kd: Dictionary = k
		for b in (kd.get("rot", {}) as Dictionary):
			var r: Array = kd["rot"][b]
			var e := Vector3(float(r[0]), float(r[1]), float(r[2]))
			if str(b).begins_with("knee") and e.x < -0.01:
				out.append({"level": "error", "f": int(kd["f"]), "text": "%s bends FORWARD at f%d (%.0f°): a knee never does" % [b, int(kd["f"]), rad_to_deg(e.x)]})
			elif FSARig.breaks_limits(str(b), e):
				out.append({"level": "warn", "f": int(kd["f"]), "text": "%s is past its limit at f%d" % [b, int(kd["f"])]})
		if int(kd["f"]) > doc.frames:
			out.append({"level": "warn", "f": int(kd["f"]), "text": "key at f%d is after the end (f%d)" % [int(kd["f"]), doc.frames]})
	if doc.loop:
		var a := FSAEval.layer_pose(doc, 0.0, bones)
		var b2 := FSAEval.layer_pose(doc, float(doc.frames), bones)
		var worst := 0.0
		var wb := ""
		for bn in bones:
			var d := (a.get(bn, Vector3.ZERO) as Vector3).distance_to(b2.get(bn, Vector3.ZERO))
			if d > worst:
				worst = d
				wb = str(bn)
		if worst > 0.02:
			out.append({"level": "warn", "f": doc.frames, "text": "loop seam: %s jumps %.0f° from the last frame to the first (Key > Close loop)" % [wb, rad_to_deg(worst)]})
	if doc.plant:
		var slide := _foot_slide()
		if slide > 0.04:
			out.append({"level": "warn", "f": -1, "text": "planted foot slides %.1f cm while on the floor (pin it: select the foot, Rig > Freeze)" % (slide * 100.0)})
	if doc.outside_edit:
		out.append({"level": "warn", "f": -1, "text": "keys were edited outside the Animator after a bake; layers / constraints were switched off"})
	if not pending.is_empty():
		out.append({"level": "warn", "f": int(round(frame)), "text": "the pose at f%d is changed but not keyed" % int(round(frame))})
	if out.is_empty():
		out.append({"level": "ok", "f": -1, "text": "All good: knees, limits, loop seam, feet."})
	return out


## per frame, how the feet stand once the match grounds them (CBFeet on the hidden probe model; changes nothing):
## {"planted", "soles": {footL: {tilt0 (degrees the model's own sole is off level at rest), ankle_cm (ankle over the sole)}},
##  "frames": [{"f", "footL": {"state", "low_cm", "tilt"}, "footR": ...}], "counts": {state: foot-frames}}
## state: "flat" standing levelled on the floor | "pivot" on its toes / heel (the clip keys the ankle there, or the leg cannot
## put it flat there) | "limit" standing with the heel up, the ankle at its natural bend | "sink" into the floor (a clip that
## is not planted) | "air" off the floor
func feet_report(step: int = 1) -> Dictionary:
	var sk := stage.probe_skel
	var model := stage.probe
	var soles := CBFeet.sole_info(sk)
	var out := {"planted": doc.plant, "soles": {}, "frames": [], "counts": {}}
	var scale := sk.global_transform.basis.get_scale().y
	for b in soles:
		out["soles"][b] = {"tilt0": snappedf(float(soles[b]["tilt0"]), 0.1), "ankle_cm": snappedf(float(soles[b]["h"]) * scale * 100.0, 0.1)}
	var counts := {}
	for f in range(0, doc.frames + 1, maxi(1, step)):
		final_pose_on(sk, float(f))
		model.position = Vector3.ZERO
		var st := CBFeet.standing(sk, soles)
		var did := CBFeet.ground(sk, model, 0.0, true) if doc.plant else {}
		var up_s := (sk.global_transform.basis.inverse() * Vector3.UP).normalized()
		var row := {"f": f}
		for b in soles:
			var low := CBFeet.lowest(sk, b, soles)
			var n := (sk.get_bone_global_pose(sk.find_bone(b)).basis.orthonormalized() * (soles[b]["n"] as Vector3)).normalized()
			var tilt := rad_to_deg(n.angle_to(up_s))
			var state := "air"
			if low < -0.01:
				state = "sink"
			elif low < 0.05:
				if float(st[b]["pivot"]) >= 0.5 or float(st[b]["w"]) < 0.5:
					state = "pivot"
				elif bool((did.get(b, {}) as Dictionary).get("limit", false)) and tilt > 8.0:
					state = "limit"
				else:
					state = "flat"
			row[b] = {"state": state, "low_cm": snappedf(low * 100.0, 0.1), "tilt": snappedf(tilt, 0.1)}
			counts[state] = int(counts.get(state, 0)) + 1
		out["frames"].append(row)
	model.position = Vector3.ZERO
	out["counts"] = counts
	return out


## the most the planted foot drifts in one stretch of contact, after taking out the clip's own steady travel (a walk cycle slides
## its planted foot back by the stride on the spot: the game moves the body forward at that speed)
func _foot_slide() -> float:
	var sk := stage.probe_skel
	var fl := sk.find_bone("footL")
	var fr := sk.find_bone("footR")
	if fl < 0 or fr < 0:
		return 0.0
	var runs: Array = []   # [f0, p0, f1, p1]
	var cur := -1
	for f in doc.frames + 1:
		final_pose_on(sk, float(f))
		var a := sk.global_transform * sk.get_bone_global_pose(fl).origin
		var b := sk.global_transform * sk.get_bone_global_pose(fr).origin
		var low := 0 if a.y <= b.y else 1
		var p: Vector3 = [a, b][low]
		if low != cur:
			cur = low
			runs.append([f, p, f, p])
		var r: Array = runs[runs.size() - 1]
		r[2] = f
		r[3] = p
	var d := Vector2.ZERO
	var dt := 0.0
	for r in runs:
		d += Vector2((r[3] as Vector3).x - (r[1] as Vector3).x, (r[3] as Vector3).z - (r[1] as Vector3).z)
		dt += float(r[2]) - float(r[0])
	var v := d / dt if dt > 0.0 else Vector2.ZERO
	var worst := 0.0
	for r in runs:
		var t := float(r[2]) - float(r[0])
		worst = maxf(worst, (Vector2((r[3] as Vector3).x - (r[1] as Vector3).x, (r[3] as Vector3).z - (r[1] as Vector3).z) - v * t).length())
	return worst


# ================================================================ render

func render_view(w: int, h: int, path: String = "") -> String:
	var v: FSAView = focused_view if focused_view != null and is_instance_valid(focused_view) else (canvas.views[0] if not canvas.views.is_empty() else null)
	if v == null:
		return ""
	if path == "":
		path = "%s/%s_%s_f%03d_%dx%d.png" % [RENDERS, fighter, doc.name, int(round(frame)), w, h]
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err: Error = await v.render_png(w, h, path)
	say("Rendered %s" % path if err == OK else "Render failed (%d)" % err, "ok" if err == OK else "error")
	return path if err == OK else ""


## the four-angle review sheet (front / three-quarter / side / back x columns) as one PNG at any size
func render_strip(w: int, h: int, cols: int, path: String = "") -> String:
	if path == "":
		path = "%s/%s_%s_sheet_%dx%d.png" % [RENDERS, fighter, doc.name, w, h]
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var off := SubViewport.new()
	off.size = Vector2i(w, h)
	off.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	off.gui_embed_subwindows = true
	add_child(off)
	var s := FSAStrip.new().setup(self, cols)
	s.size = Vector2(w, h)
	s.theme = FSATheme.theme()
	off.add_child(s)
	for i in 6:
		await RenderingServer.frame_post_draw
	var img := off.get_texture().get_image()
	off.queue_free()
	var err := img.save_png(path)
	say("Rendered sheet %s" % path if err == OK else "Render failed (%d)" % err, "ok" if err == OK else "error")
	return path if err == OK else ""


func render_sequence(w: int, h: int, a: int, b: int, dir: String = "") -> String:
	if dir == "":
		dir = "%s/%s_%s_seq_%dx%d" % [RENDERS, fighter, doc.name, w, h]
	DirAccess.make_dir_recursive_absolute(dir)
	var was := frame
	for f in range(a, b + 1):
		frame = float(f)
		pending = {}
		_apply_now()
		await render_view(w, h, "%s/f%04d.png" % [dir, f])
	frame = was
	_apply_now()
	say("Rendered frames %d-%d to %s" % [a, b, dir], "ok")
	return dir


func _shot_and_quit(path: String) -> void:
	for i in 40:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()


# ================================================================ keyboard

func _typing() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit


func _unhandled_key_input(ev: InputEvent) -> void:
	var k := ev as InputEventKey
	if k == null or not k.pressed or _typing():
		return
	var ctrl := k.ctrl_pressed or k.meta_pressed
	var handled := true
	match k.keycode:
		KEY_SPACE:
			toggle_play()
		KEY_K:
			if k.alt_pressed:
				delete_keys([int(round(frame))])
			else:
				key_now()
		KEY_I:
			key_now()
		KEY_DELETE, KEY_BACKSPACE:
			delete_keys(sel_keys if not sel_keys.is_empty() else [int(round(frame))])
		KEY_LEFT, KEY_COMMA:
			step(-1)
		KEY_RIGHT, KEY_PERIOD:
			step(1)
		KEY_UP:
			goto_key(1)
		KEY_DOWN:
			goto_key(-1)
		KEY_HOME:
			set_frame(0.0)
		KEY_END:
			set_frame(float(doc.frames))
		KEY_Q:
			set_tool("select")
		KEY_E, KEY_R:
			set_tool("rotate")
		KEY_W, KEY_G:
			set_tool("move")
		KEY_T:
			set_tool("ik")
		KEY_X:
			space_global = not space_global
			changed.emit("tool")
		KEY_Z:
			if ctrl and k.shift_pressed:
				redo()
			elif ctrl:
				undo()
			else:
				handled = false
		KEY_Y:
			if ctrl:
				redo()
			else:
				handled = false
		KEY_S:
			if ctrl:
				if k.shift_pressed:
					prompt("Save as (clip name):", doc.name + "_2", func(n: String) -> void: save_as(n))
				else:
					save()
			else:
				handled = false
		KEY_C:
			if ctrl:
				copy_pose()
			else:
				handled = false
		KEY_V:
			if ctrl:
				paste_pose(k.shift_pressed)
			else:
				handled = false
		KEY_M:
			if ctrl:
				pose_mirror("l2r" if not k.shift_pressed else "r2l")
			else:
				mirror_edit = not mirror_edit
				changed.emit("tool")
		KEY_L:
			toggle_lock_selected()
		KEY_O:
			set_onion(not bool(show["onion"]))
		KEY_N:
			autokey = not autokey
			changed.emit("tool")
		KEY_ESCAPE:
			revert_pending()
		KEY_F:
			if focused_view != null and is_instance_valid(focused_view):
				focused_view.frame_point(joint_world(sel_bone), 1.3)
		KEY_QUOTELEFT:
			if focused_view != null and is_instance_valid(focused_view):
				focused_view.maximize_requested.emit(focused_view)
		KEY_1:
			set_layout("1")
		KEY_2:
			set_layout("2")
		KEY_3:
			set_layout("3")
		KEY_4:
			set_layout("4")
		KEY_5:
			set_layout("strip")
		KEY_6:
			set_layout("4+strip")
		_:
			handled = false
	if handled:
		get_viewport().set_input_as_handled()
