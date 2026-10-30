class_name FSAToolbar
extends RefCounted
## The tool bar (fighter, clip chip, tools, axes, mirror, auto key, same-key mode, onion, trail, layouts, save), the transport
## (play, step, keys, frame, length, fps, loop, speed, play range, the big KEY button) and the status bar.


static func _bar() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", FSATheme._box(FSATheme.BG2, 0, 4))
	return p


## a bar's row inside a horizontal scroller: on a narrow window the bar scrolls instead of pushing the panels off screen
static func _row(p: PanelContainer) -> HBoxContainer:
	var sc := ScrollContainer.new()
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	sc.custom_minimum_size.y = 34
	p.add_child(sc)
	var r := HBoxContainer.new()
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(r)
	sc.resized.connect(func() -> void: r.custom_minimum_size.x = sc.size.x)
	return r


static func _group(btns: Array) -> void:
	var g := ButtonGroup.new()
	for b in btns:
		(b as Button).button_group = g


static func build(app: FSAApp) -> Control:
	var p := _bar()
	var r := _row(p)
	var keys: Array = CBRoster.keys()
	var fsel := FSATheme.option(keys.map(func(k: String) -> String: return CBRoster.display(k)), keys.find(app.fighter), func(i: int) -> void: app.set_fighter(str(keys[i])), "The body you animate on (every fighter shares the rig, so a clip plays on all of them)")
	fsel.custom_minimum_size.x = 150
	r.add_child(fsel)
	var chip := FSATheme.label("", FSATheme.GOLD, 14)
	chip.custom_minimum_size.x = 170
	chip.add_theme_font_override("font", FSATheme.head_font)
	r.add_child(chip)
	r.add_child(VSeparator.new())
	var tools := {}
	for t in [["SELECT", "select", "Q: pick joints only"], ["ROTATE", "rotate", "E: drag a joint to swing it, drag a ring to turn about one axis"],
			["MOVE", "move", "W: slide the whole body (hips shift); arrows move along one axis"], ["IK", "ik", "T: pull a hand or foot and the limb bends to reach; pull any other joint and its parents bend"]]:
		var b := FSATheme.button(str(t[0]), func(on: bool) -> void:
			if on:
				app.set_tool(str(t[1])), str(t[2]), true)
		tools[str(t[1])] = b
		r.add_child(b)
	_group(tools.values())
	var space := FSATheme.button("LOCAL", func(on: bool) -> void:
		app.space_global = on
		app.changed.emit("tool"), "X: rings / sliders in the bone's own axes (LOCAL) or the world's (GLOBAL)", true)
	r.add_child(space)
	r.add_child(VSeparator.new())
	var mir := FSATheme.button("X-MIRROR", func(on: bool) -> void:
		app.mirror_edit = on
		app.changed.emit("tool"), "M: edits on one side are mirrored to the other side", true)
	r.add_child(mir)
	var ak := FSATheme.button("AUTO KEY", func(on: bool) -> void:
		app.autokey = on
		app.changed.emit("tool"), "N: every edit is keyed at once (off: edit, then K)", true)
	r.add_child(ak)
	var modes := ["off", "linked", "pose", "bone"]
	var prop := FSATheme.option(["SAME KEY off", "SAME KEY linked", "SAME KEY pose", "SAME KEY value"], modes.find(app.propagate), func(i: int) -> void:
		app.propagate = modes[i]
		app.say("When a key changes, %s." % ["only that key changes", "its linked keys follow", "keys holding the same pose follow", "keys holding the same bone value follow (per bone)"][i]),
		"When you update a key, the same key elsewhere in the clip takes the same change: linked keys, keys with the same pose (a loop's first and last), or per bone the same value")
	r.add_child(prop)
	r.add_child(VSeparator.new())
	var onion := FSATheme.button("ONION", func(on: bool) -> void: app.set_onion(on), "O: ghosts of the frames before (blue) and after (orange)", true)
	r.add_child(onion)
	var trail := FSATheme.button("TRAIL", func(on: bool) -> void:
		app.show["trail"] = on
		app._apply_now(), "The path the selected joint travels over the clip", true)
	trail.button_pressed = bool(app.show["trail"])
	r.add_child(trail)
	r.add_child(VSeparator.new())
	var lays := {}
	for l in [["1", "1"], ["2", "2"], ["3", "3"], ["4", "4"], ["STRIP", "strip"], ["4+S", "4+strip"]]:
		var b := FSATheme.button(str(l[0]), func(on: bool) -> void:
			if on and app.canvas.layout != str(l[1]):
				app.set_layout(str(l[1])), "Canvas layout (keys 1-6)", true)
		lays[str(l[1])] = b
		r.add_child(b)
	_group(lays.values())
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(spacer)
	var undo := FSATheme.button("UNDO", func() -> void: app.undo(), "Ctrl+Z")
	r.add_child(undo)
	var redo := FSATheme.button("REDO", func() -> void: app.redo(), "Ctrl+Shift+Z")
	r.add_child(redo)
	var save := FSATheme.button("SAVE", func() -> void: app.save(), "Ctrl+S: writes data/clips/<name>.json, where the game reads it")
	save.add_theme_color_override("font_color", FSATheme.GOLD)
	r.add_child(save)
	var refresh := func(_w: String) -> void:
		var tag := "NEW" if app.is_new else ("BAKED LAYERS" if app.doc.needs_bake() else "CLIP")
		chip.text = "%s  [%s]%s" % [app.doc.name, tag, "  *" if app.history.dirty() else ""]
		chip.add_theme_color_override("font_color", FSATheme.ACCENT if app.history.dirty() else FSATheme.GOLD)
		for t in tools:
			(tools[t] as Button).set_pressed_no_signal(t == app.tool)
		space.set_pressed_no_signal(app.space_global)
		space.text = "GLOBAL" if app.space_global else "LOCAL"
		mir.set_pressed_no_signal(app.mirror_edit)
		ak.set_pressed_no_signal(app.autokey)
		ak.add_theme_color_override("font_color", FSATheme.RED if app.autokey else FSATheme.TEXT)
		onion.set_pressed_no_signal(bool(app.show["onion"]))
		trail.set_pressed_no_signal(bool(app.show["trail"]))
		prop.select(modes.find(app.propagate))
		for l in lays:
			(lays[l] as Button).set_pressed_no_signal(l == app.canvas.layout if app.canvas != null else false)
		fsel.select(keys.find(app.fighter))
		undo.disabled = not app.history.can_undo()
		redo.disabled = not app.history.can_redo()
	app.changed.connect(refresh)
	refresh.call_deferred("init")
	return p


static func transport(app: FSAApp) -> Control:
	var p := _bar()
	var r := _row(p)
	r.add_child(FSATheme.button("|<", func() -> void: app.set_frame(0.0), "Home: first frame"))
	r.add_child(FSATheme.button("<K", func() -> void: app.goto_key(-1), "Down: previous key"))
	r.add_child(FSATheme.button("<", func() -> void: app.step(-1), ", or Left: back a frame"))
	var play := FSATheme.button("PLAY", func() -> void: app.toggle_play(), "Space")
	play.custom_minimum_size.x = 64
	r.add_child(play)
	r.add_child(FSATheme.button(">", func() -> void: app.step(1), ". or Right: forward a frame"))
	r.add_child(FSATheme.button("K>", func() -> void: app.goto_key(1), "Up: next key"))
	r.add_child(FSATheme.button(">|", func() -> void: app.set_frame(float(app.doc.frames)), "End: last frame"))
	var fr := FSATheme.spin(0, 9999, 1, 0, func(v: float) -> void: app.set_frame(v), "Current frame")
	fr.custom_minimum_size.x = 70
	r.add_child(fr)
	var of := FSATheme.label("/", FSATheme.MUTED)
	r.add_child(of)
	var length := FSATheme.spin(1, 9999, 1, app.doc.frames, func(v: float) -> void:
		if int(v) != app.doc.frames:
			app.set_clip_prop("frames", int(v)), "Clip length in frames")
	length.custom_minimum_size.x = 70
	r.add_child(length)
	var fps := FSATheme.option(["24 fps", "30 fps", "60 fps"], [24, 30, 60].find(app.doc.fps), func(i: int) -> void: app.set_clip_prop("fps", [24, 30, 60][i]), "Frames per second (the game plays fighters' clips on its 60 Hz clock, stretched to each move)")
	r.add_child(fps)
	var loop := FSATheme.button("LOOP", func(on: bool) -> void: app.set_clip_prop("loop", on), "The clip loops in the game (idle, walk, run)", true)
	r.add_child(loop)
	var spd := FSATheme.option(["x0.25", "x0.5", "x1", "x2"], 2, func(i: int) -> void: app.speed = [0.25, 0.5, 1.0, 2.0][i], "Playback speed")
	r.add_child(spd)
	r.add_child(FSATheme.button("IN", func() -> void:
		app.play_range.x = int(round(app.frame))
		app.changed.emit("doc"), "Play range starts here"))
	r.add_child(FSATheme.button("OUT", func() -> void:
		app.play_range.y = int(round(app.frame))
		app.changed.emit("doc"), "Play range ends here"))
	r.add_child(FSATheme.button("ALL", func() -> void:
		app.play_range = Vector2i(0, -1)
		app.changed.emit("doc"), "Play the whole clip"))
	r.add_child(VSeparator.new())
	var layer := FSATheme.label("", FSATheme.OK, 12)
	r.add_child(layer)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(spacer)
	var info := FSATheme.label("", FSATheme.MUTED, 12)
	info.clip_text = true
	info.custom_minimum_size.x = 120
	r.add_child(info)
	var ease := FSATheme.option(FSADoc.EASES, 0, func(i: int) -> void: app.set_keys_field([int(round(app.frame))], "ease", FSADoc.EASES[i]), "How this key eases into the next one: in = whips into it (strikes), out = settles, inout = smooth, hold = jumps, spline = flows (cycles)")
	r.add_child(ease)
	var del := FSATheme.button("DEL KEY", func() -> void: app.delete_keys([int(round(app.frame))]), "Alt+K")
	r.add_child(del)
	var key := FSATheme.button("SET KEY", func() -> void: app.key_now(), "K: store this pose as a key")
	key.custom_minimum_size.x = 120
	key.add_theme_font_override("font", FSATheme.head_font)
	key.add_theme_font_size_override("font_size", 16)
	r.add_child(key)
	var refresh := func(_w: String) -> void:
		play.text = "PAUSE" if app.playing else "PLAY"
		fr.set_value_no_signal(round(app.frame))
		fr.max_value = app.doc.frames
		length.set_value_no_signal(app.doc.frames)
		fps.select(maxi(0, [24, 30, 60].find(app.doc.fps)))
		loop.set_pressed_no_signal(app.doc.loop)
		var f := int(round(app.frame))
		var k := app.doc.key_at(f)
		var on_key := not k.is_empty()
		ease.visible = on_key
		del.visible = on_key
		if on_key:
			ease.select(maxi(0, FSADoc.EASES.find(str(k.get("ease", app.doc.ease)))))
		var pend := not app.pending.is_empty()
		key.text = ("UPDATE KEY" if on_key else "SET KEY") + (" *" if pend else "")
		var sb := FSATheme._box(FSATheme.ACCENT if pend else (FSATheme.BG3 if not on_key else FSATheme.GOLD.darkened(0.55)), 4, 8, FSATheme.GOLD if on_key else FSATheme.LINE)
		key.add_theme_stylebox_override("normal", sb)
		key.add_theme_color_override("font_color", FSATheme.BG0 if pend else FSATheme.TEXT)
		var flags: Array = []
		if on_key:
			if str(k.get("link", "")) != "":
				flags.append("linked %s with f%s" % [k["link"], ", f".join(app.doc.partners(f, app.bones, false).map(func(x: int) -> String: return str(x)))])
			if bool(k.get("lock", false)):
				flags.append("LOCKED")
			if str(k.get("tag", "")) != "":
				flags.append(str(k["tag"]))
		info.text = ("f%d: " % f + ", ".join(flags)) if not flags.is_empty() else ""
		var l := app.doc.layer_by_id(app.active_layer)
		layer.text = "KEYS > " + ("BASE" if l.is_empty() else "LAYER " + str(l.get("name", "")).to_upper())
	app.changed.connect(refresh)
	refresh.call_deferred("init")
	return p


static func status_bar(app: FSAApp) -> Control:
	var p := _bar()
	p.add_theme_stylebox_override("panel", FSATheme._box(FSATheme.BG0, 0, 4))
	var r := HBoxContainer.new()
	p.add_child(r)
	var msg := FSATheme.label("Ready.", FSATheme.TEXT, 13)
	msg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	msg.clip_text = true
	r.add_child(msg)
	var sel := FSATheme.label("", FSATheme.MUTED, 12)
	r.add_child(sel)
	var api := FSATheme.label("", FSATheme.PURPLE, 12)
	r.add_child(api)
	var refresh := func(_w: String) -> void:
		msg.text = app.status
		msg.add_theme_color_override("font_color", app.status_color())
		sel.text = "   %s  |  %s  |  %d keys  |  f %d / %d   " % [app.sel_bone if app.sel_bones.size() < 2 else "%d bones" % app.sel_bones.size(), app.tool.to_upper(), app.doc.keys.size(), int(round(app.frame)), app.doc.frames]
		api.text = ("AGENT API :%d  (%d calls)" % [app.api_port, app.api_log.size()]) if app.server != null and app.server.listening else "AGENT API OFF"
	app.changed.connect(refresh)
	refresh.call_deferred("init")
	return p
