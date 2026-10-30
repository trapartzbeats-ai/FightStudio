class_name FSAMenus
extends RefCounted
## The menu bar: File, Edit, Key, Pose, Rig, View, Window, Agents, Help. Every item names its shortcut.

const OLD_STUDIO := "res://game/packs/city_breaker/studio/studio.tscn"


static func build(app: FSAApp) -> Control:
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel", FSATheme._box(FSATheme.BG0, 0, 2))
	var row := HBoxContainer.new()
	wrap.add_child(row)
	var brand := FSATheme.label(" FIGHT STUDIO ", FSATheme.ACCENT, 17)
	brand.add_theme_font_override("font", FSATheme.head_font)
	row.add_child(brand)
	var sub := FSATheme.label("ANIMATOR   ", FSATheme.GOLD, 12)
	sub.add_theme_font_override("font", FSATheme.head_font)
	row.add_child(sub)
	var bar := MenuBar.new()
	bar.flat = true
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(bar)
	_file(app, bar)
	_edit(app, bar)
	_key(app, bar)
	_pose(app, bar)
	_rig(app, bar)
	_view(app, bar)
	_window(app, bar)
	_agents(app, bar)
	_help(app, bar)
	return wrap


static func _menu(bar: MenuBar, title: String, items: Array) -> PopupMenu:
	var m := PopupMenu.new()
	m.name = title
	bar.add_child(m)
	var calls: Dictionary = {}
	var id := 0
	for it in items:
		if it == null:
			m.add_separator()
			continue
		var a: Array = it
		if a.size() >= 3 and a[2] is PopupMenu:
			m.add_submenu_node_item(str(a[0]), a[2])
			continue
		m.add_item(str(a[0]), id)
		if a.size() >= 3 and str(a[2]) != "":
			m.set_item_tooltip(m.get_item_index(id), str(a[2]))
		calls[id] = a[1]
		id += 1
	m.id_pressed.connect(func(i: int) -> void:
		if calls.has(i):
			(calls[i] as Callable).call())
	return m


static func _sub(items: Array) -> PopupMenu:
	var m := PopupMenu.new()
	var calls: Dictionary = {}
	for i in items.size():
		var a: Array = items[i]
		m.add_item(str(a[0]), i)
		calls[i] = a[1]
	m.id_pressed.connect(func(i: int) -> void: (calls[i] as Callable).call())
	return m


static func _file(app: FSAApp, bar: MenuBar) -> void:
	var baked := PopupMenu.new()
	baked.about_to_popup.connect(func() -> void:
		baked.clear()
		for n in app.baked_clips():
			baked.add_item(str(n)))
	baked.index_pressed.connect(func(i: int) -> void: app.open_baked(baked.get_item_text(i)))
	_menu(bar, "File", [
		["New clip...   Ctrl+N", func() -> void: app.prompt("Name for the new clip (starts from the pose on screen):", "my_clip", func(n: String) -> void: app.new_clip(n, 30, 30, false, true))],
		["New loop clip (walk, idle...)", func() -> void: app.prompt("Name for the new loop clip (60 frames @ 60 fps, first = last key):", "my_loop", func(n: String) -> void: app.new_clip(n, 60, 60, true, true))],
		["Open a baked GLB animation as a clip", null, baked],
		["Import motion (Mixamo FBX, GLB)...", func() -> void: FSAImportDialog.open(app), "Any Mixamo animation onto our rig as a new clip"],
		null,
		["Save   Ctrl+S", func() -> void: app.save()],
		["Save as...   Ctrl+Shift+S", func() -> void: app.prompt("Save as (clip name):", app.doc.name + "_2", func(n: String) -> void: app.save_as(n))],
		["Revert to the saved clip", func() -> void: app.ask("Throw away every change since the last save?", func() -> void: app.open_clip(app.doc.name, true))],
		null,
		["Export fighter GLB (all clips, Godot)", func() -> void: export_glb(app), "Writes exports/<fighter>_studio.glb"],
		["Bake clips into the fighter GLB (Animato + Blender)", func() -> void: bake_animato(app), "D:/Projects/Animato/bake_studio_clips.py: keys every studio clip into assets/chars/<fighter>_fight.glb, original kept in D:/Cache/chars_before_studio"],
		null,
		["Open the old Studio (effects, pairs, secondary)", func() -> void: OS.create_process(OS.get_executable_path(), ["--path", ProjectSettings.globalize_path("res://"), OLD_STUDIO, "--", "--fighter=" + app.fighter])],
		["Quit", func() -> void: app._on_close()],
	])


static func _edit(app: FSAApp, bar: MenuBar) -> void:
	_menu(bar, "Edit", [
		["Undo   Ctrl+Z", func() -> void: app.undo()],
		["Redo   Ctrl+Shift+Z / Ctrl+Y", func() -> void: app.redo()],
		null,
		["Copy pose   Ctrl+C", func() -> void: app.copy_pose()],
		["Paste pose   Ctrl+V", func() -> void: app.paste_pose(false)],
		["Paste pose mirrored   Ctrl+Shift+V", func() -> void: app.paste_pose(true)],
		["Paste pose on the selected bones only", func() -> void: app.paste_pose(false, true)],
		["Throw away the unkeyed change   Esc", func() -> void: app.revert_pending()],
		null,
		["Select all keys", func() -> void: app.select_keys(app.doc.key_frames())],
		["Clear key selection", func() -> void: app.select_keys([])],
	])


static func _key(app: FSAApp, bar: MenuBar) -> void:
	var ease := _sub(FSADoc.EASES.map(func(e: String) -> Array: return [e, func() -> void: app.set_keys_field(app.sel_keys, "ease", e)]))
	var tag := _sub([["key", func() -> void: app.set_keys_field(app.sel_keys, "tag", "")],
		["breakdown", func() -> void: app.set_keys_field(app.sel_keys, "tag", "breakdown")],
		["extreme", func() -> void: app.set_keys_field(app.sel_keys, "tag", "extreme")]])
	var prop := _sub([["Off: only the key you edit", func() -> void: _propagate(app, "off")],
		["Linked keys only", func() -> void: _propagate(app, "linked")],
		["Same pose (default): keys holding the same pose follow", func() -> void: _propagate(app, "pose")],
		["Same bone value: per bone, keys with the same value follow", func() -> void: _propagate(app, "bone")]])
	_menu(bar, "Key", [
		["Set / update key   K", func() -> void: app.key_now()],
		["Delete key here   Alt+K", func() -> void: app.delete_keys([int(round(app.frame))])],
		["Delete selected keys   Del", func() -> void: app.delete_keys(app.sel_keys)],
		null,
		["Ease to next key", null, ease],
		["Key type", null, tag],
		["When a key changes, update the same key elsewhere", null, prop],
		["Link selected keys (one pose, many frames)", func() -> void: app.link_keys(app.sel_keys)],
		["Unlink selected keys", func() -> void: app.unlink_keys(app.sel_keys)],
		["Lock selected keys", func() -> void: app.set_keys_field(app.sel_keys, "lock", true)],
		["Unlock selected keys", func() -> void: app.set_keys_field(app.sel_keys, "lock", false)],
		null,
		["Insert frames here...", func() -> void: app.prompt("Insert how many frames at f%d?" % int(round(app.frame)), "5", func(t: String) -> void: app.insert_frames(int(round(app.frame)), int(t)))],
		["Delete frames here...", func() -> void: app.prompt("Delete how many frames from f%d?" % int(round(app.frame)), "5", func(t: String) -> void: app.delete_frames(int(round(app.frame)), int(t)))],
		["Scale time (whole clip or selected keys)...", func() -> void: app.prompt("Scale time by (0.5 = twice as fast, 2 = half speed):", "1.25", func(t: String) -> void: app.scale_time(float(t), app.sel_keys))],
		["Reverse selected keys", func() -> void:
			if app.sel_keys.size() > 1:
				app.reverse_range(int(app.sel_keys.min()), int(app.sel_keys.max()))],
		["Close loop (last frame = first key, linked)", func() -> void: app.close_loop()],
		null,
		["Bake layers + constraints into keys", func() -> void: app.bake_to_keys()],
	])


static func _propagate(app: FSAApp, mode: String) -> void:
	app.propagate = mode
	app.changed.emit("tool")
	app.say("Same-key updates: %s." % mode)


static func _pose(app: FSAApp, bar: MenuBar) -> void:
	_menu(bar, "Pose", [
		["Reset selected bones", func() -> void: app.reset_bones(app.sel_bones)],
		["Reset the whole pose", func() -> void: app.reset_bones(app.bones + ["hips_move"])],
		null,
		["Mirror left to right   Ctrl+M", func() -> void: app.pose_mirror("l2r")],
		["Mirror right to left   Ctrl+Shift+M", func() -> void: app.pose_mirror("r2l")],
		["Flip pose (swap sides)", func() -> void: app.pose_mirror("flip")],
		null,
		["Save pose to the library...", func() -> void: app.prompt("Pose name:", "pose_%s_f%d" % [app.doc.name, int(round(app.frame))], func(n: String) -> void: app.save_library_pose(n))],
		["Save selected bones as a partial pose...", func() -> void: app.prompt("Partial pose name (only the selected bones):", "hand_%s" % app.sel_bone, func(n: String) -> void: app.save_library_pose(n, true))],
		null,
		["Breakdown 25% (toward the previous key)", func() -> void: app.breakdown(0.25)],
		["Breakdown 50%", func() -> void: app.breakdown(0.5)],
		["Breakdown 75% (toward the next key)", func() -> void: app.breakdown(0.75)],
	])


static func _rig(app: FSAApp, bar: MenuBar) -> void:
	var ik := _sub([["Arm L", func() -> void: app.add_constraint({"type": "ik", "limb": "armL"})],
		["Arm R", func() -> void: app.add_constraint({"type": "ik", "limb": "armR"})],
		["Leg L", func() -> void: app.add_constraint({"type": "ik", "limb": "legL"})],
		["Leg R", func() -> void: app.add_constraint({"type": "ik", "limb": "legR"})]])
	var chans := _sub([["Lock X only", func() -> void: app.set_lock(app.sel_bone, "x")], ["Lock Y only", func() -> void: app.set_lock(app.sel_bone, "y")],
		["Lock Z only", func() -> void: app.set_lock(app.sel_bone, "z")], ["Lock Y + Z (only X turns)", func() -> void: app.set_lock(app.sel_bone, "yz")],
		["Unlock all channels", func() -> void: app.set_lock(app.sel_bone, "")]])
	_menu(bar, "Rig", [
		["Lock / unlock selected bones   L", func() -> void: app.toggle_lock_selected()],
		["Lock channels of the selected bone", null, chans],
		["Freeze selected bone in the world from here (pin)", func() -> void: app.pin_selected()],
		null,
		["Add IK", null, ik],
		["Add aim (head looks at a target)", func() -> void: app.add_constraint({"type": "aim", "bone": "head", "axis": "+z"})],
		["Add limit to the selected bone", func() -> void: app.add_constraint({"type": "limit", "bone": app.sel_bone, "min": [-1.0, -1.0, -1.0], "max": [1.0, 1.0, 1.0]})],
		["Add copy rotation (selected copies its mirror bone)", func() -> void: app.add_constraint({"type": "copy_rot", "bone": app.sel_bone, "source": FSARig.mirror_name(app.sel_bone), "mirror": true})],
		["Add floor (nothing sinks under it)", func() -> void: app.add_constraint({"type": "floor", "bones": ["footL", "footR"], "mode": "floor"})],
		["Add plant (lowest foot stands on the floor)", func() -> void: app.add_constraint({"type": "floor", "bones": ["footL", "footR"], "mode": "plant", "name": "PLANT feet"})],
		null,
		["Run checks (knees, limits, loop, feet)", func() -> void: app.dock.show_panel("Checks")],
		["Controls (one slider, many bones)", func() -> void: app.dock.show_panel("Controls")],
	])


static func _view(app: FSAApp, bar: MenuBar) -> void:
	var lay := _sub([["1 view   1", func() -> void: app.set_layout("1")], ["2 views   2", func() -> void: app.set_layout("2")],
		["3 views   3", func() -> void: app.set_layout("3")], ["Quad   4", func() -> void: app.set_layout("4")],
		["Strip: front / 3-q / side / back x time   5", func() -> void: app.set_layout("strip")], ["Quad + strip   6", func() -> void: app.set_layout("4+strip")]])
	var cols := _sub([6, 8, 10, 12, 16].map(func(n: int) -> Array: return ["%d columns" % n, func() -> void: _set_cols(app, n)]))
	var rs := _sub([1.0, 1.5, 2.0].map(func(s: float) -> Array: return ["%.1fx" % s, func() -> void: _set_render_scale(app, s)]))
	_menu(bar, "View", [
		["Layout", null, lay],
		["Strip columns", null, cols],
		["Render scale (HD / supersampling)", null, rs],
		null,
		["Onion skin on / off   O", func() -> void: app.set_onion(not bool(app.show["onion"]))],
		["Onion skin: by keys / by frames", func() -> void:
			app.onion["keys"] = not bool(app.onion["keys"])
			app._apply_now()],
		["Motion trail on / off", func() -> void: _flip(app, "trail")],
		["Bones on / off", func() -> void: _flip(app, "bones")],
		["Bone names on / off", func() -> void: _flip(app, "labels")],
		["Sockets on / off", func() -> void: _flip(app, "sockets")],
		["Props on / off", func() -> void: _flip(app, "props")],
		["Game feet (plant + flat feet like a match)", func() -> void: _flip(app, "game_feet")],
		["Strip camera follows the body (walks, runs)", func() -> void:
			app.strip_follow = not app.strip_follow
			app.canvas.mark_strip()],
		["Strip around the current frame / whole clip", func() -> void:
			if app.canvas.strip != null:
				app.canvas.strip.around_now = not app.canvas.strip.around_now
				app.canvas.mark_strip()],
	])


static func _set_cols(app: FSAApp, n: int) -> void:
	app.strip_cols = n
	app.canvas.set_layout(app.canvas.layout)


static func _set_render_scale(app: FSAApp, s: float) -> void:
	app.render_scale = s
	app.canvas.set_render_scale(s)


static func _flip(app: FSAApp, k: String) -> void:
	app.show[k] = not bool(app.show[k])
	app._apply_now()
	app.changed.emit("view")


static func _window(app: FSAApp, bar: MenuBar) -> void:
	var panels := PopupMenu.new()
	panels.about_to_popup.connect(func() -> void:
		panels.clear()
		for t in app.dock.panels:
			panels.add_item(str(t)))
	panels.index_pressed.connect(func(i: int) -> void: app.dock.show_panel(panels.get_item_text(i)))
	var floats := PopupMenu.new()
	floats.about_to_popup.connect(func() -> void:
		floats.clear()
		for t in app.dock.panels:
			floats.add_item(str(t)))
	floats.index_pressed.connect(func(i: int) -> void: app.dock.float_panel(floats.get_item_text(i)))
	_menu(bar, "Window", [
		["Show panel", null, panels],
		["Float a panel in its own window", null, floats],
		null,
		["New canvas window: strip (second monitor)", func() -> void: app.new_canvas_window("strip")],
		["New canvas window: quad", func() -> void: app.new_canvas_window("4")],
		["New canvas window: one big view", func() -> void: app.new_canvas_window("1")],
		null,
		["Save this window layout", func() -> void:
			app.dock.save()
			app.say("Layout saved.", "ok")],
		["Reset the layout (next start)", func() -> void:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(FSADock.LAYOUT_FILE))
			app.say("Layout reset: restart the Animator.")],
		["Full screen on / off   F11", func() -> void:
			var w := app.get_window()
			w.mode = Window.MODE_FULLSCREEN if w.mode != Window.MODE_FULLSCREEN else Window.MODE_MAXIMIZED],
	])


static func _agents(app: FSAApp, bar: MenuBar) -> void:
	_menu(bar, "Agents", [
		["Show the agent log", func() -> void: app.dock.show_panel("Agents")],
		["Copy the MCP config (paste into an agent's MCP settings)", func() -> void:
			DisplayServer.clipboard_set(FSAPanels.mcp_config_text())
			app.say("MCP config copied.", "ok")],
		["Copy the API address", func() -> void:
			DisplayServer.clipboard_set("http://127.0.0.1:%d/rpc" % app.api_port)
			app.say("API address copied.", "ok")],
	])


static func _help(app: FSAApp, bar: MenuBar) -> void:
	_menu(bar, "Help", [
		["Shortcuts", func() -> void: shortcuts(app)],
		["Open the manual (README.md)", func() -> void: OS.shell_open(ProjectSettings.globalize_path("res://game/packs/city_breaker/animator/README.md"))],
	])


static func shortcuts(app: FSAApp) -> void:
	var d := AcceptDialog.new()
	d.title = "Fight Studio Animator - shortcuts"
	d.dialog_text = """VIEWS   left-drag a joint: Rotate swings it / Move slides the body / IK pulls it (hands + feet bend the limb)
        drag a coloured ring: turn about that axis only     outer white ring: turn in the view
        right-drag orbit   middle-drag pan   wheel zoom   double-click a joint: frame it   ` maximize a view
TOOLS   Q select   E rotate   W move   T IK   X local / global axes   M X-mirror edits   N auto key
KEYS    K set / update key   Alt+K delete key   Del delete selected keys   Esc throw away an unkeyed change
TIME    Space play   , . or Left Right step   Up Down next / previous key   Home End
POSE    Ctrl+C / Ctrl+V copy / paste   Ctrl+Shift+V paste mirrored   Ctrl+M mirror L>R   L lock bone   O onion skin
FILE    Ctrl+S save   Ctrl+Shift+S save as   Ctrl+Z undo   Ctrl+Shift+Z redo
LAYOUT  1 2 3 4 views   5 strip   6 quad + strip   F frame the selected joint
DOPE    click / Shift-click keys, drag to box-select, drag keys to retime, right-click for ease, link, lock, copy, paste"""
	app.add_child(d)
	d.popup_centered()
	d.confirmed.connect(d.queue_free)
	d.canceled.connect(d.queue_free)


static func export_glb(app: FSAApp) -> void:
	var m := FSAStage.instance_fighter(app.fighter)
	if m == null:
		return
	app.add_child(m)
	var sk := FSAStage.skeleton_of(m)
	var aps := m.find_children("*", "AnimationPlayer", true, false)
	if not aps.is_empty():
		CBClipLib.install(aps[0] as AnimationPlayer, m, sk)
	var dir := "res://game/packs/city_breaker/exports/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path := dir + "%s_studio.glb" % app.fighter
	var gd := GLTFDocument.new()
	var st := GLTFState.new()
	var err := gd.append_from_scene(m, st)
	if err == OK:
		err = gd.write_to_filesystem(st, path)
	m.queue_free()
	app.say("Exported %s" % ProjectSettings.globalize_path(path) if err == OK else "Export failed (%d)." % err, "ok" if err == OK else "error")


static func bake_animato(app: FSAApp) -> void:
	var script := "D:/Projects/Animato/bake_studio_clips.py"
	var py := "D:/Projects/Animato/.venv/Scripts/python.exe"
	if not FileAccess.file_exists(script) or not FileAccess.file_exists(py):
		app.say("Animato not found at D:/Projects/Animato.", "error")
		return
	if app.history.dirty():
		app.say("Save the clip first (the bake reads the saved files).", "warn")
		return
	app.ask("Bake every studio clip into %s_fight.glb with Animato (headless Blender)?\nThe original GLB is kept in D:/Cache/chars_before_studio." % app.fighter, func() -> void:
		OS.create_process(py, [script, app.fighter])
		app.say("Animato is baking %s in the background (Blender, headless)." % app.fighter, "ok"))
