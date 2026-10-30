class_name FSAPanels
extends RefCounted
## Every dock panel. Each one builds itself once and refreshes on app.changed.

const MCP_SCRIPT := "D:/Games/BSP-Universe/game/packs/city_breaker/animator/mcp/fight_studio_mcp.py"


static func mcp_config_text() -> String:
	return JSON.stringify({"mcpServers": {"fight-studio": {"command": "python", "args": [MCP_SCRIPT]}}}, "  ")


static func _deg(v: Vector3) -> Vector3:
	return v * (180.0 / PI)


static func _rad(v: Vector3) -> Vector3:
	return v * (PI / 180.0)


# ==================================================================== CLIPS

class Clips extends VBoxContainer:
	var app: FSAApp
	var search := LineEdit.new()
	var filter: OptionButton
	var list := ItemList.new()
	var names: Array = []
	const FILTERS := ["All", "Mine (no prefix)", "World (w_)", "Fighter moves (a_)", "This fighter's own", "Baked in the GLB"]

	func setup(a: FSAApp) -> Control:
		app = a
		var body := FSATheme.scroll_body(self)
		body.add_child(FSATheme.heading("Clips"))
		body.add_child(FSATheme.hint("Every clip the game reads (data/clips). Double-click to open. Baked GLB animations open as an editable copy."))
		search.placeholder_text = "search clips..."
		search.text_changed.connect(func(_t: String) -> void: refill())
		body.add_child(search)
		filter = FSATheme.option(FILTERS, 0, func(_i: int) -> void: refill())
		body.add_child(filter)
		list.custom_minimum_size.y = 330
		list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		list.item_activated.connect(func(i: int) -> void: _open(i))
		body.add_child(list)
		FSATheme.row(body, [FSATheme.button("OPEN", func() -> void: _open(_sel()), "Open the selected clip"),
			FSATheme.button("NEW", func() -> void: app.prompt("Name for the new clip:", "my_clip", func(n: String) -> void: app.new_clip(n, 30, 30, false, true)), "A new clip that starts from the pose on screen"),
			FSATheme.button("DUPLICATE", func() -> void: app.prompt("Save a copy of %s as:" % app.doc.name, app.doc.name + "_v2", func(n: String) -> void: app.save_as(n)), "Save this clip under a new name")])
		FSATheme.row(body, [FSATheme.button("AS LAYER", func() -> void:
				var n := _name(_sel())
				if n != "" and not n.begins_with("[baked]"):
					app.add_layer({"name": n, "source": "clip", "clip": n, "mode": "override", "mask": FSARig.MASKS["Upper body"]})
					app.dock.show_panel("Layers"), "Blend the selected clip on top of this one as a layer (upper body to start)"),
			FSATheme.button("TO TRASH", func() -> void:
				var n := _name(_sel())
				if n != "" and not n.begins_with("[baked]"):
					app.ask("Move %s to D:/Cache/fight_studio_trash?" % n, func() -> void:
						app.trash_clip(n)
						refill()), "Clips are never deleted: they move to the trash folder"),
			FSATheme.button("RELOAD", func() -> void: refill())])
		app.changed.connect(func(w: String) -> void:
			if w in ["clips", "saved", "fighter", "clip"]:
				refill())
		refill()
		return self

	func _sel() -> int:
		var s := list.get_selected_items()
		return s[0] if not s.is_empty() else -1

	func _name(i: int) -> String:
		return str(names[i]) if i >= 0 and i < names.size() else ""

	func _open(i: int) -> void:
		var n := _name(i)
		if n.begins_with("[baked] "):
			app.open_baked(n.substr(8))
		elif n != "":
			app.open_clip(n)

	func refill() -> void:
		var q := search.text.strip_edges().to_lower()
		var mode := filter.selected
		names = []
		if mode == 5:
			for n in app.baked_clips():
				names.append("[baked] " + str(n))
		else:
			for n in CBClipLib.list_clips():
				var s := str(n)
				var ok := true
				match mode:
					1:
						ok = not (s.begins_with("a_") or s.begins_with("w_"))
					2:
						ok = s.begins_with("w_")
					3:
						ok = s.begins_with("a_")
					4:
						ok = s.begins_with("a_%s_" % app.fighter)
				if ok:
					names.append(s)
		if q != "":
			names = names.filter(func(n: String) -> bool: return n.to_lower().contains(q))
		list.clear()
		for n in names:
			var i := list.add_item(str(n))
			if str(n) == app.doc.name:
				list.set_item_custom_fg_color(i, FSATheme.GOLD)
				list.select(i)


# ==================================================================== PROPERTIES

class Props extends VBoxContainer:
	var app: FSAApp
	var bone_lbl: Label
	var hint: Label
	var rot: Array = []
	var locks: Array = []
	var hips: Array = []
	var key_lbl: Label
	var key_ease: OptionButton
	var key_tag: OptionButton
	var key_lock: CheckBox
	var c_plant: CheckBox
	var c_override: CheckBox
	var c_ease: OptionButton
	var c_note: LineEdit
	var marks_box: VBoxContainer
	var _quiet := false

	func setup(a: FSAApp) -> Control:
		app = a
		var body := FSATheme.scroll_body(self)
		body.add_child(FSATheme.heading("Bone"))
		bone_lbl = FSATheme.label("", FSATheme.GOLD, 16)
		body.add_child(bone_lbl)
		hint = FSATheme.hint("")
		body.add_child(hint)
		for i in 3:
			var s := FSATheme.slider_row(body, ["X  turn", "Y  turn", "Z  turn"][i], -180, 180, 0.5, 0, func(_v: float) -> void: _rot_changed(), "Degrees, the bone's own axes on top of its rest", FSATheme.AXIS[i])
			var lk := FSATheme.check("lock", false, func(on: bool) -> void: _lock_changed(), "Freeze this channel: no tool can change it")
			lk.add_theme_font_size_override("font_size", 11)
			s.get_parent().add_child(lk)
			rot.append(s)
			locks.append(lk)
		FSATheme.row(body, [FSATheme.button("RESET BONE", func() -> void: app.reset_bones(app.sel_bones)),
			FSATheme.button("MIRROR TO OTHER SIDE", func() -> void: _mirror_bone(), "Copy this bone's turn, mirrored, onto its twin on the other side"),
			FSATheme.button("KEY", func() -> void: app.key_now())])
		FSATheme.sep(body)
		body.add_child(FSATheme.heading("Body move (hips shift)"))
		for ax in ["dx", "dy", "dz"]:
			var s := FSATheme.slider_row(body, {"dx": "side (m)", "dy": "height (m)", "dz": "forward (m)"}[ax], -1.5, 1.5, 0.005, 0, func(v: float) -> void:
				if not _quiet:
					app.set_hips_shift(ax, v), "Moves the whole body; the feet go with it", FSATheme.AXIS[["dx", "dy", "dz"].find(ax)])
			hips.append(s)
		FSATheme.sep(body)
		body.add_child(FSATheme.heading("This key"))
		key_lbl = FSATheme.label("", FSATheme.TEXT, 13)
		body.add_child(key_lbl)
		key_ease = FSATheme.option(FSADoc.EASES, 0, func(i: int) -> void: app.set_keys_field([int(round(app.frame))], "ease", FSADoc.EASES[i]), "How the motion leaves this key toward the next")
		key_tag = FSATheme.option(["key", "breakdown", "extreme"], 0, func(i: int) -> void: app.set_keys_field([int(round(app.frame))], "tag", "" if i == 0 else ["key", "breakdown", "extreme"][i]))
		key_lock = FSATheme.check("locked", false, func(on: bool) -> void: app.set_keys_field([int(round(app.frame))], "lock", on), "A locked key cannot be changed, moved or deleted")
		FSATheme.row(body, [FSATheme.label("ease", FSATheme.MUTED, 12), key_ease, FSATheme.label("type", FSATheme.MUTED, 12), key_tag, key_lock])
		FSATheme.sep(body)
		body.add_child(FSATheme.heading("Clip"))
		c_plant = FSATheme.check("plant feet (the game stands the soles on the floor, flat: Feet panel)", false, func(on: bool) -> void: app.set_clip_prop("plant", on))
		body.add_child(c_plant)
		c_override = FSATheme.check("override a baked clip of the same name", false, func(on: bool) -> void: app.set_clip_prop("override", on))
		body.add_child(c_override)
		c_ease = FSATheme.option(FSADoc.EASES, 0, func(i: int) -> void: app.set_clip_prop("ease", FSADoc.EASES[i]), "The ease of every key that has none of its own")
		FSATheme.row(body, [FSATheme.label("default ease", FSATheme.MUTED, 12), c_ease])
		c_note = LineEdit.new()
		c_note.placeholder_text = "note"
		c_note.text_submitted.connect(func(t: String) -> void: app.set_clip_prop("note", t))
		body.add_child(c_note)
		body.add_child(FSATheme.heading("Marks and markers"))
		body.add_child(FSATheme.hint("hit / clear: the frames a move's hitbox goes live and ends (the game maps the move's frame data onto them). Markers are your notes on the ruler."))
		marks_box = VBoxContainer.new()
		body.add_child(marks_box)
		FSATheme.row(body, [FSATheme.button("HIT HERE", func() -> void: _set_mark("hit")), FSATheme.button("CLEAR HERE", func() -> void: _set_mark("clear")),
			FSATheme.button("+ MARKER", func() -> void: app.prompt("Marker name:", "contact", func(n: String) -> void:
				var f := int(round(app.frame))
				app.mutate("Marker " + n, func() -> void: app.doc.add_marker(f, n))))])
		app.changed.connect(func(w: String) -> void:
			if w in ["sel", "frame", "doc", "pending", "clip", "fighter", "tool"]:
				refresh())
		refresh()
		return self

	func _set_mark(m: String) -> void:
		var marks: Dictionary = (app.doc.extra.get("marks", {}) as Dictionary).duplicate()
		marks[m] = int(round(app.frame))
		app.set_clip_prop("marks", marks)

	func _rot_changed() -> void:
		if _quiet:
			return
		var e := Vector3((rot[0] as HSlider).value, (rot[1] as HSlider).value, (rot[2] as HSlider).value)
		app.set_bone_euler(app.sel_bone, FSAPanels._rad(e))

	func _lock_changed() -> void:
		if _quiet:
			return
		var ch := ""
		for i in 3:
			if (locks[i] as CheckBox).button_pressed:
				ch += ["x", "y", "z"][i]
		app.set_lock(app.sel_bone, ch)

	func _mirror_bone() -> void:
		var m := FSARig.mirror_name(app.sel_bone)
		if m == app.sel_bone:
			app.say("%s is a centre bone." % m, "warn")
			return
		var p := app.editable_pose()
		p[m] = app.doc.guard(m, p.get(m, Vector3.ZERO), FSARig.mirror_euler(p.get(app.sel_bone, Vector3.ZERO)))
		app.edit_pose(p, "Mirror %s to %s" % [app.sel_bone, m])

	func refresh() -> void:
		_quiet = true
		var b := app.sel_bone
		var p := app.editable_pose()
		bone_lbl.text = b + ("   (%d selected)" % app.sel_bones.size() if app.sel_bones.size() > 1 else "")
		hint.text = FSARig.hint(b)
		var e := FSAPanels._deg(p.get(b, Vector3.ZERO))
		for i in 3:
			FSATheme.set_quiet(rot[i], e[i])
			(locks[i] as CheckBox).set_pressed_no_signal(app.doc.is_locked(b, i))
			(rot[i] as HSlider).editable = not app.doc.is_locked(b, i)
		for i in 3:
			FSATheme.set_quiet(hips[i], float(p.get(["_dx", "_dy", "_dz"][i], 0.0)))
		var f := int(round(app.frame))
		var k := app.doc.key_at(f)
		if k.is_empty():
			key_lbl.text = "f%d is between keys (K sets one)" % f
		else:
			var partners := app.doc.partners(f, app.bones, true)
			key_lbl.text = "f%d is a key%s%s" % [f, ("  - linked " + str(k["link"])) if str(k.get("link", "")) != "" else "",
				("  - same pose as f" + ", f".join(partners.map(func(x: int) -> String: return str(x)))) if not partners.is_empty() else ""]
			key_ease.select(maxi(0, FSADoc.EASES.find(str(k.get("ease", app.doc.ease)))))
			key_tag.select(maxi(0, ["key", "breakdown", "extreme"].find(str(k.get("tag", "key")))))
			key_lock.set_pressed_no_signal(bool(k.get("lock", false)))
		key_ease.disabled = k.is_empty()
		key_tag.disabled = k.is_empty()
		key_lock.disabled = k.is_empty()
		c_plant.set_pressed_no_signal(app.doc.plant)
		c_override.set_pressed_no_signal(app.doc.override)
		c_ease.select(maxi(0, FSADoc.EASES.find(app.doc.ease)))
		if not c_note.has_focus():
			c_note.text = str(app.doc.extra.get("note", ""))
		for ch in marks_box.get_children():
			ch.queue_free()
		var marks: Dictionary = app.doc.extra.get("marks", {})
		for m in marks:
			FSATheme.row(marks_box, [FSATheme.label("%s  f%.1f" % [m, float(marks[m])], FSATheme.RED if str(m) == "hit" else FSATheme.LEFT, 12)])
		for i in app.doc.markers.size():
			var md: Dictionary = app.doc.markers[i]
			var idx := i
			FSATheme.row(marks_box, [FSATheme.label("marker %s  f%d" % [md.get("name", ""), int(md.get("f", 0))], FSATheme.GOLD, 12),
				FSATheme.button("x", func() -> void: app.mutate("Remove marker", func() -> void: app.doc.markers.remove_at(idx)))])
		_quiet = false


# ==================================================================== CONTROLS

class Controls extends VBoxContainer:
	var app: FSAApp
	var box := VBoxContainer.new()
	var sliders: Array = []
	var name_edit := LineEdit.new()
	var bone_opt: OptionButton
	var axis_opt: OptionButton
	var amount: SpinBox
	var target_opt: OptionButton
	var _quiet := false

	func setup(a: FSAApp) -> Control:
		app = a
		var body := FSATheme.scroll_body(self)
		body.add_child(FSATheme.heading("Controls"))
		body.add_child(FSATheme.hint("One slider moves several bones together (a fist, a spine curl, a crouch). The slider reads the pose, so it always shows where the body is; key the result with K or AUTO KEY."))
		body.add_child(box)
		FSATheme.sep(body)
		body.add_child(FSATheme.heading("Add your own control"))
		name_edit.placeholder_text = "control name (new) ..."
		body.add_child(name_edit)
		target_opt = FSATheme.option(["(new control)"], 0, func(_i: int) -> void: pass, "Add the drive to an existing control, or make a new one")
		body.add_child(target_opt)
		bone_opt = OptionButton.new()
		axis_opt = FSATheme.option(["X", "Y", "Z", "move side", "move up", "move forward"], 0, func(_i: int) -> void: pass)
		amount = FSATheme.spin(-180, 180, 1, 30, func(_v: float) -> void: pass, "How far that channel goes at value 1 (degrees, or cm for moves)")
		FSATheme.row(body, [bone_opt, axis_opt, amount])
		FSATheme.row(body, [FSATheme.button("ADD DRIVE", func() -> void: _add(), "The control will also move this bone channel"),
			FSATheme.button("REMOVE CONTROL", func() -> void: _remove(), "Remove the control picked above"),
			FSATheme.button("SAVE CONTROLS", func() -> void:
				FSARig.save_data()
				app.say("Controls saved to data/animator_rig.json.", "ok"))])
		app.changed.connect(func(w: String) -> void:
			if w in ["frame", "doc", "pending", "clip", "fighter", "controls"]:
				refresh(w == "controls" or w == "fighter"))
		refresh(true)
		return self

	func _add() -> void:
		var ax: Variant = [0, 1, 2, "dx", "dy", "dz"][axis_opt.selected]
		var amt := deg_to_rad(amount.value) if typeof(ax) == TYPE_INT else amount.value / 100.0
		var bone := bone_opt.get_item_text(bone_opt.selected)
		if typeof(ax) == TYPE_STRING:
			bone = "hips"
		var ctls := FSARig.controls()
		if target_opt.selected > 0:
			((ctls[target_opt.selected - 1] as Dictionary)["drives"] as Array).append([bone, ax, amt])
		else:
			var n := name_edit.text.strip_edges()
			if n == "":
				app.say("Name the new control first.", "warn")
				return
			ctls.append({"name": n, "min": -1.0, "max": 1.0, "drives": [[bone, ax, amt]]})
		app.changed.emit("controls")
		app.say("Control updated (SAVE CONTROLS keeps it).", "ok")

	func _remove() -> void:
		if target_opt.selected <= 0:
			return
		FSARig.controls().remove_at(target_opt.selected - 1)
		app.changed.emit("controls")

	func refresh(rebuild: bool) -> void:
		var ctls := FSARig.controls()
		if rebuild or sliders.size() != ctls.size():
			for c in box.get_children():
				c.queue_free()
			sliders.clear()
			for i in ctls.size():
				var ctl: Dictionary = ctls[i]
				var usable := false
				for d in (ctl.get("drives", []) as Array):
					if str(d[0]) in app.bones:
						usable = true
				var s := FSATheme.slider_row(box, str(ctl.get("name", "")), float(ctl.get("min", -1.0)), float(ctl.get("max", 1.0)), 0.01, 0.0, func(v: float) -> void:
					if not _quiet:
						app.set_control(ctl, v), "%d bone channels" % (ctl.get("drives", []) as Array).size())
				s.get_parent().visible = usable
				sliders.append(s)
			target_opt.clear()
			target_opt.add_item("(new control)")
			for c in ctls:
				target_opt.add_item(str((c as Dictionary).get("name", "")))
			bone_opt.clear()
			for b in app.bones:
				bone_opt.add_item(str(b))
		_quiet = true
		var p := app.editable_pose()
		for i in mini(sliders.size(), ctls.size()):
			FSATheme.set_quiet(sliders[i], FSARig.control_value(ctls[i], p))
		_quiet = false


# ==================================================================== LAYERS

class Layers extends VBoxContainer:
	var app: FSAApp
	var list := ItemList.new()
	var edit := VBoxContainer.new()
	var clip_edit := LineEdit.new()
	var sel_id := ""

	func setup(a: FSAApp) -> Control:
		app = a
		var body := FSATheme.scroll_body(self)
		body.add_child(FSATheme.heading("Layers"))
		body.add_child(FSATheme.hint("Stack motion on the clip: a KEYS layer holds its own keys (tweak an arm without touching the base), a CLIP layer blends another clip in (wave over a walk, a run fading into a stop). add = adds its turns, add_delta = adds a clip's motion from its first frame, override = blends toward it. Masks pick the bones, fades blend in and out. Saving bakes them for the game."))
		FSATheme.row(body, [FSATheme.button("+ KEYS LAYER", func() -> void:
				var l := app.add_layer({"name": "tweak %d" % (app.doc.layers.size() + 1), "mode": "add", "source": "keys"})
				sel_id = str(l["id"])
				app.set_active_layer(sel_id), "A layer of keys added on top; it becomes the one you key into"),
			FSATheme.button("BASE", func() -> void: app.set_active_layer(""), "Key into the base clip again")])
		clip_edit.placeholder_text = "clip to blend in (name)"
		clip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		FSATheme.row(body, [clip_edit, FSATheme.button("+ CLIP LAYER", func() -> void:
			var n := clip_edit.text.strip_edges()
			if CBClipLib.load_clip(n).is_empty():
				app.say("No clip named %s." % n, "warn")
				return
			var l := app.add_layer({"name": n, "mode": "override", "source": "clip", "clip": n, "mask": FSARig.MASKS["Upper body"]})
			sel_id = str(l["id"]))])
		list.custom_minimum_size.y = 120
		list.item_selected.connect(func(i: int) -> void:
			sel_id = str((app.doc.layers[i] as Dictionary)["id"])
			_build_edit())
		body.add_child(list)
		body.add_child(edit)
		FSATheme.row(body, [FSATheme.button("BAKE ALL INTO KEYS", func() -> void: app.bake_to_keys(), "Layers and constraints become plain keys (undo brings them back)")])
		app.changed.connect(func(w: String) -> void:
			if w in ["doc", "clip", "layer"]:
				refresh())
		refresh()
		return self

	func refresh() -> void:
		list.clear()
		for l in app.doc.layers:
			var ld: Dictionary = l
			var t := "%s%s  [%s %s %.0f%%]%s" % ["> " if str(ld["id"]) == app.active_layer else "", ld.get("name", ""), ld.get("source", "keys"), ld.get("mode", "add"),
				float(ld.get("weight", 1.0)) * 100.0, "  MUTED" if bool(ld.get("mute", false)) else ("  SOLO" if bool(ld.get("solo", false)) else "")]
			var i := list.add_item(t)
			if str(ld["id"]) == sel_id:
				list.select(i)
		_build_edit()

	func _put(k: String, v: Variant) -> void:
		app.set_layer(sel_id, {k: v})

	func _build_edit() -> void:
		for c in edit.get_children():
			c.queue_free()
		var l := app.doc.layer_by_id(sel_id)
		if l.is_empty():
			return
		FSATheme.sep(edit)
		var nm := LineEdit.new()
		nm.text = str(l.get("name", ""))
		nm.text_submitted.connect(func(t: String) -> void: _put("name", t))
		edit.add_child(nm)
		var modes := ["add", "add_delta", "override"]
		FSATheme.row(edit, [FSATheme.label("mode", FSATheme.MUTED, 12), FSATheme.option(modes, modes.find(str(l.get("mode", "add"))), func(i: int) -> void: _put("mode", modes[i])),
			FSATheme.check("mute", bool(l.get("mute", false)), func(on: bool) -> void: _put("mute", on)),
			FSATheme.check("solo", bool(l.get("solo", false)), func(on: bool) -> void: _put("solo", on))])
		FSATheme.slider_row(edit, "weight", 0.0, 1.0, 0.01, float(l.get("weight", 1.0)), func(v: float) -> void: _put("weight", v))
		var masks := FSARig.MASKS.keys()
		var cur := 0
		for i in masks.size():
			if str(FSARig.MASKS[masks[i]]) == str(l.get("mask", [])):
				cur = i
		FSATheme.row(edit, [FSATheme.label("bones", FSATheme.MUTED, 12), FSATheme.option(masks, cur, func(i: int) -> void: _put("mask", FSARig.MASKS[masks[i]]))])
		FSATheme.row(edit, [FSATheme.label("from", FSATheme.MUTED, 12), FSATheme.spin(0, 9999, 1, float(l.get("start", 0)), func(v: float) -> void: _put("start", int(v))),
			FSATheme.label("to", FSATheme.MUTED, 12), FSATheme.spin(-1, 9999, 1, float(l.get("end", -1)), func(v: float) -> void: _put("end", int(v)), "-1 = to the end")])
		FSATheme.row(edit, [FSATheme.label("fade in", FSATheme.MUTED, 12), FSATheme.spin(0, 999, 1, float(l.get("fade_in", 0)), func(v: float) -> void: _put("fade_in", int(v))),
			FSATheme.label("out", FSATheme.MUTED, 12), FSATheme.spin(0, 999, 1, float(l.get("fade_out", 0)), func(v: float) -> void: _put("fade_out", int(v)))])
		if str(l.get("source", "keys")) == "clip":
			var ce := LineEdit.new()
			ce.text = str(l.get("clip", ""))
			ce.text_submitted.connect(func(t: String) -> void: _put("clip", t))
			FSATheme.row(edit, [FSATheme.label("clip", FSATheme.MUTED, 12), ce])
			FSATheme.row(edit, [FSATheme.label("offset", FSATheme.MUTED, 12), FSATheme.spin(-999, 999, 1, float(l.get("offset", 0)), func(v: float) -> void: _put("offset", int(v))),
				FSATheme.label("speed", FSATheme.MUTED, 12), FSATheme.spin(0.05, 8, 0.05, float(l.get("speed", 1.0)), func(v: float) -> void: _put("speed", v)),
				FSATheme.check("cycle", bool(l.get("cycle", true)), func(on: bool) -> void: _put("cycle", on))])
		else:
			var ed := FSATheme.button("KEYS GO HERE" if app.active_layer != sel_id else "KEYING THIS LAYER", func() -> void: app.set_active_layer(sel_id), "Pose and press K: the key lands in this layer")
			edit.add_child(ed)
		FSATheme.row(edit, [FSATheme.button("UP", func() -> void: _move(-1)), FSATheme.button("DOWN", func() -> void: _move(1)),
			FSATheme.button("REMOVE", func() -> void:
				app.remove_layer(sel_id)
				sel_id = "")])

	func _move(d: int) -> void:
		app.mutate("Reorder layers", func() -> void:
			for i in app.doc.layers.size():
				if str((app.doc.layers[i] as Dictionary)["id"]) == sel_id:
					var j := clampi(i + d, 0, app.doc.layers.size() - 1)
					var l: Variant = app.doc.layers[i]
					app.doc.layers.remove_at(i)
					app.doc.layers.insert(j, l)
					return)


# ==================================================================== CONSTRAINTS

class Constraints extends VBoxContainer:
	var app: FSAApp
	var list := ItemList.new()
	var edit := VBoxContainer.new()
	var sel_id := ""

	func setup(a: FSAApp) -> Control:
		app = a
		var body := FSATheme.scroll_body(self)
		body.add_child(FSATheme.heading("Constraints"))
		body.add_child(FSATheme.hint("Rules solved every frame on top of the keys: IK (a hand or foot reaches a target), FREEZE (a bone stays put in the world: planted feet, a hand on a wall), AIM (the head follows a point), LIMIT, COPY (one bone copies another), FLOOR / PLANT. Purple crosshairs in the views are their targets. Saving bakes them for the game."))
		var add := GridContainer.new()
		add.columns = 3
		body.add_child(add)
		for it in [["IK ARM L", {"type": "ik", "limb": "armL"}], ["IK ARM R", {"type": "ik", "limb": "armR"}], ["IK LEG L", {"type": "ik", "limb": "legL"}],
				["IK LEG R", {"type": "ik", "limb": "legR"}], ["AIM HEAD", {"type": "aim", "bone": "head", "axis": "+z"}], ["FLOOR", {"type": "floor", "bones": ["footL", "footR"], "mode": "floor"}],
				["PLANT FEET", {"type": "floor", "bones": ["footL", "footR"], "mode": "plant", "name": "PLANT feet"}]]:
			var def: Dictionary = it[1]
			add.add_child(FSATheme.button(str(it[0]), func() -> void:
				var c := app.add_constraint(def.duplicate(true))
				sel_id = str(c.get("id", ""))
				refresh()))
		add.add_child(FSATheme.button("FREEZE SEL", func() -> void:
			app.pin_selected()
			sel_id = str((app.doc.constraints[app.doc.constraints.size() - 1] as Dictionary)["id"])
			refresh(), "Freeze the selected bone where it is now, from this frame on"))
		add.add_child(FSATheme.button("LIMIT SEL", func() -> void:
			var c := app.add_constraint({"type": "limit", "bone": app.sel_bone, "min": [-1.0, -1.0, -1.0], "max": [1.0, 1.0, 1.0]})
			sel_id = str(c.get("id", ""))))
		list.custom_minimum_size.y = 120
		list.item_selected.connect(func(i: int) -> void:
			sel_id = str((app.doc.constraints[i] as Dictionary)["id"])
			_build_edit())
		body.add_child(list)
		body.add_child(edit)
		FSATheme.row(body, [FSATheme.button("BAKE ALL INTO KEYS", func() -> void: app.bake_to_keys())])
		app.changed.connect(func(w: String) -> void:
			if w in ["doc", "clip"]:
				refresh())
		refresh()
		return self

	func refresh() -> void:
		list.clear()
		for c in app.doc.constraints:
			var cd: Dictionary = c
			var i := list.add_item("%s%s  %.0f%%  f%d-%s" % ["" if bool(cd.get("enabled", true)) else "(off) ", cd.get("name", ""), float(cd.get("influence", 1.0)) * 100.0,
				int(cd.get("start", 0)), "end" if int(cd.get("end", -1)) < 0 else str(int(cd["end"]))])
			if str(cd["id"]) == sel_id:
				list.select(i)
		_build_edit()

	func _put(k: String, v: Variant) -> void:
		app.set_constraint(sel_id, {k: v})

	func _vec_row(label: String, v: Vector3, cb: Callable) -> void:
		var r := HBoxContainer.new()
		r.add_child(FSATheme.label(label, FSATheme.MUTED, 12))
		var vals := [v.x, v.y, v.z]
		var boxes: Array = []
		for i in 3:
			var s := FSATheme.spin(-50, 50, 0.01, vals[i], func(_x: float) -> void:
				cb.call(Vector3((boxes[0] as SpinBox).value, (boxes[1] as SpinBox).value, (boxes[2] as SpinBox).value)))
			s.custom_minimum_size.x = 76
			boxes.append(s)
			r.add_child(s)
		edit.add_child(r)

	func _build_edit() -> void:
		for c in edit.get_children():
			c.queue_free()
		var c := app.doc.constraint_by_id(sel_id)
		if c.is_empty():
			return
		FSATheme.sep(edit)
		var t := str(c.get("type", ""))
		edit.add_child(FSATheme.label(str(c.get("name", t)), FSATheme.PURPLE, 15))
		FSATheme.row(edit, [FSATheme.check("on", bool(c.get("enabled", true)), func(on: bool) -> void: _put("enabled", on))])
		FSATheme.slider_row(edit, "influence", 0.0, 1.0, 0.01, float(c.get("influence", 1.0)), func(v: float) -> void: _put("influence", v))
		FSATheme.row(edit, [FSATheme.label("from", FSATheme.MUTED, 12), FSATheme.spin(0, 9999, 1, float(c.get("start", 0)), func(v: float) -> void: _put("start", int(v))),
			FSATheme.label("to", FSATheme.MUTED, 12), FSATheme.spin(-1, 9999, 1, float(c.get("end", -1)), func(v: float) -> void: _put("end", int(v)), "-1 = to the end"),
			FSATheme.label("blend", FSATheme.MUTED, 12), FSATheme.spin(0, 99, 1, float(c.get("blend", 0)), func(v: float) -> void: _put("blend", int(v)), "Frames to fade in / out at the range edges")])
		match t:
			"ik", "aim":
				var tg: Dictionary = c.get("target", {})
				var p := FSAEval.target_point(tg, app.frame, app.skel)
				_vec_row("target", p, func(v: Vector3) -> void: _put("target", {"pos": [v.x, v.y, v.z]}))
				FSATheme.row(edit, [FSATheme.button("TARGET = HERE NOW", func() -> void:
						var end := _end_bone(c)
						var w := app.joint_world(end) if t == "ik" else app.joint_world(end) + Vector3(0, 0, 1.5)
						_put("target", {"pos": [snappedf(w.x, 0.001), snappedf(w.y, 0.001), snappedf(w.z, 0.001)]}), "Put the target where the joint is in this frame"),
					FSATheme.button("KEY TARGET", func() -> void: _key_target(c), "Key the target at this frame: it moves between its keys")])
				var nk := ((tg.get("keys", []) as Array).size())
				if nk > 0:
					edit.add_child(FSATheme.hint("%d target keys (it moves between them)." % nk))
				if t == "ik":
					edit.add_child(FSATheme.check("hand / foot keeps its angle", bool(c.get("keep_end", true)), func(on: bool) -> void: _put("keep_end", on)))
				else:
					var axes := ["+z", "-z", "+x", "-x", "+y", "-y"]
					FSATheme.row(edit, [FSATheme.label("bone", FSATheme.MUTED, 12), _bone_opt(str(c.get("bone", "head")), func(b: String) -> void: _put("bone", b)),
						FSATheme.label("looks along", FSATheme.MUTED, 12), FSATheme.option(axes, axes.find(str(c.get("axis", "+z"))), func(i: int) -> void: _put("axis", axes[i]))])
			"pin":
				var whats := ["both", "position", "rotation"]
				FSATheme.row(edit, [FSATheme.label("bone", FSATheme.MUTED, 12), _bone_opt(str(c.get("bone", "")), func(b: String) -> void: _put("bone", b)),
					FSATheme.option(whats, whats.find(str(c.get("what", "both"))), func(i: int) -> void: _put("what", whats[i]))])
				FSATheme.row(edit, [FSATheme.label("frozen as at f", FSATheme.MUTED, 12), FSATheme.spin(0, 9999, 1, float(c.get("pin_frame", 0)), func(v: float) -> void: _put("pin_frame", int(v))),
					FSATheme.button("AT THIS FRAME", func() -> void: _put("pin_frame", int(round(app.frame))))])
			"limit":
				edit.add_child(_bone_opt(str(c.get("bone", "")), func(b: String) -> void: _put("bone", b)))
				var lo := FSAPanels._deg(FSAEval._v3(c.get("min", [-1, -1, -1])))
				var hi := FSAPanels._deg(FSAEval._v3(c.get("max", [1, 1, 1])))
				_vec_row("min deg", lo, func(v: Vector3) -> void: _put("min", [deg_to_rad(v.x), deg_to_rad(v.y), deg_to_rad(v.z)]))
				_vec_row("max deg", hi, func(v: Vector3) -> void: _put("max", [deg_to_rad(v.x), deg_to_rad(v.y), deg_to_rad(v.z)]))
			"copy_rot":
				FSATheme.row(edit, [FSATheme.label("bone", FSATheme.MUTED, 12), _bone_opt(str(c.get("bone", "")), func(b: String) -> void: _put("bone", b)),
					FSATheme.label("copies", FSATheme.MUTED, 12), _bone_opt(str(c.get("source", "")), func(b: String) -> void: _put("source", b))])
				FSATheme.slider_row(edit, "mix", -2.0, 2.0, 0.01, float(c.get("mix", 1.0)), func(v: float) -> void: _put("mix", v))
				edit.add_child(FSATheme.check("mirrored", bool(c.get("mirror", false)), func(on: bool) -> void: _put("mirror", on)))
			"floor":
				var modes := ["floor", "plant"]
				FSATheme.row(edit, [FSATheme.option(modes, modes.find(str(c.get("mode", "floor"))), func(i: int) -> void: _put("mode", modes[i]), "floor: nothing sinks under; plant: the lowest one stands on it"),
					FSATheme.label("height", FSATheme.MUTED, 12), FSATheme.spin(-5, 5, 0.01, float(c.get("height", 0.0)), func(v: float) -> void: _put("height", v))])
				var be := LineEdit.new()
				be.text = ",".join(c.get("bones", ["footL", "footR"]))
				be.text_submitted.connect(func(tt: String) -> void: _put("bones", Array(tt.replace(" ", "").split(","))))
				FSATheme.row(edit, [FSATheme.label("bones", FSATheme.MUTED, 12), be])
		FSATheme.row(edit, [FSATheme.button("UP", func() -> void: app.move_constraint(sel_id, -1)), FSATheme.button("DOWN", func() -> void: app.move_constraint(sel_id, 1)),
			FSATheme.button("REMOVE", func() -> void:
				app.remove_constraint(sel_id)
				sel_id = "")])

	func _end_bone(c: Dictionary) -> String:
		if str(c.get("type", "")) == "ik":
			return str((FSARig.LIMBS.get(str(c.get("limb", "")), ["", "", "head"]) as Array)[2])
		return str(c.get("bone", "head"))

	func _key_target(c: Dictionary) -> void:
		var tg: Dictionary = (c.get("target", {}) as Dictionary).duplicate(true)
		var ks: Array = tg.get("keys", [])
		var f := int(round(app.frame))
		var p := FSAEval.target_point(tg, app.frame, app.skel)
		ks = ks.filter(func(k: Dictionary) -> bool: return int(k["f"]) != f)
		ks.append({"f": f, "pos": [snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001)]})
		ks.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x["f"]) < int(y["f"]))
		tg["keys"] = ks
		tg.erase("pos")
		_put("target", tg)

	func _bone_opt(cur: String, cb: Callable) -> OptionButton:
		var o := OptionButton.new()
		for b in app.bones:
			o.add_item(str(b))
		o.select(app.bones.find(cur))
		o.item_selected.connect(func(i: int) -> void: cb.call(str(app.bones[i])))
		return o


# ==================================================================== OUTLINER

class Outliner extends VBoxContainer:
	var app: FSAApp
	var tree := Tree.new()
	var _quiet := false

	func setup(a: FSAApp) -> Control:
		app = a
		add_child(FSATheme.heading("  Outliner"))
		add_child(FSATheme.hint("  Bones by body part. Tick LOCK to freeze a bone (no tool can turn it). Click a group to select all of it."))
		tree.columns = 3
		tree.hide_root = true
		tree.select_mode = Tree.SELECT_ROW
		tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
		tree.set_column_title(0, "bone")
		tree.set_column_title(1, "lock")
		tree.set_column_title(2, "keys")
		tree.column_titles_visible = true
		tree.set_column_expand(1, false)
		tree.set_column_custom_minimum_width(1, 50)
		tree.set_column_expand(2, false)
		tree.set_column_custom_minimum_width(2, 50)
		tree.item_selected.connect(_picked)
		tree.item_edited.connect(_edited)
		add_child(tree)
		app.changed.connect(func(w: String) -> void:
			if w in ["doc", "fighter", "clip"]:
				refresh()
			elif w == "sel":
				_mark_sel())
		refresh()
		return self

	func refresh() -> void:
		_quiet = true
		tree.clear()
		var root := tree.create_item()
		var counts: Dictionary = {}
		for k in app.doc.keys:
			for b in ((k as Dictionary).get("rot", {}) as Dictionary):
				counts[b] = int(counts.get(b, 0)) + 1
		var adj := FSAAdjust.adjusted_bones(app.doc)
		for g in FSARig.grouped(app.bones):
			var gi := tree.create_item(root)
			gi.set_text(0, str(g[0]))
			gi.set_custom_color(0, FSATheme.GOLD)
			gi.set_metadata(0, "@" + str(g[0]))
			gi.collapsed = str(g[0]) in ["Hand L", "Hand R", "Extras", "Ears"]
			for b in (g[1] as Array):
				var it := tree.create_item(gi)
				it.set_text(0, str(b) + ("  *" if adj.has(b) else ""))
				if adj.has(b):
					it.set_tooltip_text(0, "Adjusted (Adjust panel): RESTORE takes it off")
				it.set_metadata(0, str(b))
				var side := FSARig.side_of(str(b))
				it.set_custom_color(0, FSATheme.LEFT if side == "L" else (FSATheme.RIGHT if side == "R" else FSATheme.TEXT))
				it.set_cell_mode(1, TreeItem.CELL_MODE_CHECK)
				it.set_editable(1, true)
				it.set_checked(1, app.doc.is_locked(str(b)))
				if app.doc.lock_channels(str(b)) != "" and not app.doc.is_locked(str(b)):
					it.set_text(1, app.doc.lock_channels(str(b)))
				it.set_text(2, str(counts.get(b, 0)))
		_quiet = false
		_mark_sel()

	func _mark_sel() -> void:
		_quiet = true
		var it := tree.get_root().get_first_child() if tree.get_root() != null else null
		while it != null:
			var ch := it.get_first_child()
			while ch != null:
				if str(ch.get_metadata(0)) == app.sel_bone:
					ch.select(0)
					tree.scroll_to_item(ch)
				ch = ch.get_next()
			it = it.get_next()
		_quiet = false

	func _picked() -> void:
		if _quiet:
			return
		var it := tree.get_selected()
		if it == null:
			return
		var m := str(it.get_metadata(0))
		if m.begins_with("@"):
			var bs := FSARig.mask_bones([m], app.bones)
			if not bs.is_empty():
				app.select_bone(str(bs[0]))
				for b in bs.slice(1):
					app.select_bone(str(b), true)
		else:
			app.select_bone(m)

	func _edited() -> void:
		if _quiet:
			return
		var it := tree.get_edited()
		if it != null:
			app.set_lock(str(it.get_metadata(0)), "xyz" if it.is_checked(1) else "")


# ==================================================================== POSES

class Poses extends VBoxContainer:
	var app: FSAApp
	var list := ItemList.new()
	var weight: HSlider
	var tween: HSlider

	func setup(a: FSAApp) -> Control:
		app = a
		var body := FSATheme.scroll_body(self)
		body.add_child(FSATheme.heading("Pose tools"))
		var g := GridContainer.new()
		g.columns = 3
		body.add_child(g)
		for it in [["MIRROR L>R", func() -> void: app.pose_mirror("l2r")], ["MIRROR R>L", func() -> void: app.pose_mirror("r2l")], ["FLIP", func() -> void: app.pose_mirror("flip")],
				["COPY", func() -> void: app.copy_pose()], ["PASTE", func() -> void: app.paste_pose(false)], ["PASTE MIRROR", func() -> void: app.paste_pose(true)],
				["RESET SEL", func() -> void: app.reset_bones(app.sel_bones)], ["RESET ALL", func() -> void: app.reset_bones(app.bones + ["hips_move"])], ["KEY  K", func() -> void: app.key_now()]]:
			g.add_child(FSATheme.button(str(it[0]), it[1]))
		FSATheme.sep(body)
		body.add_child(FSATheme.heading("Breakdown"))
		body.add_child(FSATheme.hint("Between the key before and the key after: slide toward either, then key it."))
		tween = FSATheme.slider_row(body, "lean", 0.0, 1.0, 0.01, 0.5, func(v: float) -> void: app.breakdown(v), "0 = the previous key, 1 = the next key")
		FSATheme.sep(body)
		body.add_child(FSATheme.heading("Pose library"))
		body.add_child(FSATheme.hint("Poses you keep (data/poses). Apply the whole body or only the selected bones, mirrored, blended by weight."))
		list.custom_minimum_size.y = 180
		list.item_activated.connect(func(_i: int) -> void: _apply(false, false))
		body.add_child(list)
		weight = FSATheme.slider_row(body, "weight", 0.0, 1.0, 0.01, 1.0, func(_v: float) -> void: pass, "How much of the pose to blend in")
		FSATheme.row(body, [FSATheme.button("APPLY", func() -> void: _apply(false, false)), FSATheme.button("ON SELECTED", func() -> void: _apply(true, false)),
			FSATheme.button("MIRRORED", func() -> void: _apply(false, true))])
		FSATheme.row(body, [FSATheme.button("SAVE POSE", func() -> void: app.prompt("Pose name:", "pose_%s_f%d" % [app.doc.name, int(round(app.frame))], func(n: String) -> void: app.save_library_pose(n))),
			FSATheme.button("SAVE SELECTED", func() -> void: app.prompt("Partial pose (selected bones):", "part_%s" % app.sel_bone, func(n: String) -> void: app.save_library_pose(n, true)))])
		app.changed.connect(func(w: String) -> void:
			if w == "poses":
				refresh())
		refresh()
		return self

	func refresh() -> void:
		list.clear()
		for p in app.list_poses():
			list.add_item(str(p))

	func _apply(sel_only: bool, mirror: bool) -> void:
		var s := list.get_selected_items()
		if s.is_empty():
			app.say("Pick a pose in the list.", "warn")
			return
		app.apply_library_pose(list.get_item_text(s[0]), sel_only, weight.value, mirror)


# ==================================================================== SOCKETS + PROPS

class Sockets extends VBoxContainer:
	var app: FSAApp
	var list := ItemList.new()
	var edit := VBoxContainer.new()
	var props := ItemList.new()
	var prop_edit := VBoxContainer.new()
	var names: Array = []
	var prop_sel := ""

	func setup(a: FSAApp) -> Control:
		app = a
		var body := FSATheme.scroll_body(self)
		body.add_child(FSATheme.heading("Sockets"))
		body.add_child(FSATheme.hint("Named points on bones (effects, props, hit points). Pink diamonds in the views. Shared by every fighter unless saved for this one."))
		body.add_child(FSATheme.check("show sockets in the views", bool(app.show["sockets"]), func(on: bool) -> void:
			app.show["sockets"] = on
			app._apply_now()))
		list.custom_minimum_size.y = 140
		list.item_selected.connect(func(i: int) -> void:
			app.sel_socket = str(names[i])
			app._apply_now()
			_build_edit())
		body.add_child(list)
		body.add_child(edit)
		FSATheme.row(body, [FSATheme.button("+ SOCKET", func() -> void: app.prompt("Socket name:", "my_socket", func(n: String) -> void:
				app.sock_specs[n] = {"bone": app.sel_bone, "offset": [0.0, 0.0, 0.0]}
				app.sel_socket = n
				refresh()), "A new socket on the selected bone"),
			FSATheme.button("SAVE ALL", func() -> void: app.save_sockets(false), "For every fighter"),
			FSATheme.button("SAVE THIS FIGHTER", func() -> void: app.save_sockets(true), "Only this fighter's differences")])
		FSATheme.sep(body)
		body.add_child(FSATheme.heading("Props on sockets"))
		body.add_child(FSATheme.hint("Stand-in objects held at a socket (a bat, a blade, a ball, a phone) so you can animate with them. Saved in the clip, never in the game."))
		props.custom_minimum_size.y = 90
		props.item_selected.connect(func(i: int) -> void:
			prop_sel = str((app.doc.props[i] as Dictionary)["id"])
			_build_prop())
		body.add_child(props)
		var shape := FSATheme.option(FSAStage.PROP_SHAPES, 1, func(_i: int) -> void: pass)
		FSATheme.row(body, [shape, FSATheme.button("+ PROP AT SOCKET", func() -> void:
			var s := app.sel_socket if app.sel_socket != "" else "fist_R"
			app.mutate("Add prop", func() -> void:
				app.doc.props.append({"id": FSADoc.new_id(app.doc.props, "prop"), "name": FSAStage.PROP_SHAPES[shape.selected], "shape": FSAStage.PROP_SHAPES[shape.selected], "socket": s,
					"offset": [0, 0, 0], "rot": [0, 0, 0], "scale": 1.0, "color": "#c8c0d0"})))])
		body.add_child(prop_edit)
		app.changed.connect(func(w: String) -> void:
			if w in ["fighter", "clip", "doc"]:
				refresh())
		refresh()
		return self

	func refresh() -> void:
		names = app.sock_specs.keys()
		names.sort()
		list.clear()
		for n in names:
			var i := list.add_item("%s   (%s)" % [n, (app.sock_specs[n] as Dictionary).get("bone", "")])
			if str(n) == app.sel_socket:
				list.select(i)
		_build_edit()
		props.clear()
		for p in app.doc.props:
			var i := props.add_item("%s on %s" % [(p as Dictionary).get("name", ""), (p as Dictionary).get("socket", "")])
			if str((p as Dictionary)["id"]) == prop_sel:
				props.select(i)
		_build_prop()

	func _build_edit() -> void:
		for c in edit.get_children():
			c.queue_free()
		var sp: Dictionary = app.sock_specs.get(app.sel_socket, {})
		if sp.is_empty():
			return
		var o := OptionButton.new()
		for b in app.bones:
			o.add_item(str(b))
		o.select(app.bones.find(str(sp.get("bone", ""))))
		o.item_selected.connect(func(i: int) -> void:
			sp["bone"] = str(app.bones[i])
			app._apply_now())
		FSATheme.row(edit, [FSATheme.label("bone", FSATheme.MUTED, 12), o])
		var off := FSAEval._v3(sp.get("offset", [0, 0, 0]))
		var boxes: Array = []
		var r := HBoxContainer.new()
		r.add_child(FSATheme.label("offset", FSATheme.MUTED, 12))
		for i in 3:
			var s := FSATheme.spin(-2, 2, 0.005, off[i], func(_v: float) -> void:
				sp["offset"] = [(boxes[0] as SpinBox).value, (boxes[1] as SpinBox).value, (boxes[2] as SpinBox).value]
				app._apply_now())
			s.custom_minimum_size.x = 76
			boxes.append(s)
			r.add_child(s)
		edit.add_child(r)
		edit.add_child(FSATheme.check("on the ground under the bone", bool(sp.get("ground", false)), func(on: bool) -> void:
			sp["ground"] = on
			app._apply_now()))

	func _build_prop() -> void:
		for c in prop_edit.get_children():
			c.queue_free()
		var p: Dictionary = {}
		for x in app.doc.props:
			if str((x as Dictionary)["id"]) == prop_sel:
				p = x
		if p.is_empty():
			return
		var socks: Array = app.sock_specs.keys()
		socks.sort()
		FSATheme.row(prop_edit, [FSATheme.label("socket", FSATheme.MUTED, 12), FSATheme.option(socks, socks.find(str(p.get("socket", ""))), func(i: int) -> void: _set_prop(p, "socket", str(socks[i])))])
		for fld in ["offset", "rot"]:
			var v := FSAEval._v3(p.get(fld, [0, 0, 0]))
			var boxes: Array = []
			var r := HBoxContainer.new()
			r.add_child(FSATheme.label(fld + (" deg" if fld == "rot" else " m"), FSATheme.MUTED, 12))
			var field: String = fld
			for i in 3:
				var s := FSATheme.spin(-360 if fld == "rot" else -2, 360 if fld == "rot" else 2, 1 if fld == "rot" else 0.005, v[i], func(_x: float) -> void:
					_set_prop(p, field, [(boxes[0] as SpinBox).value, (boxes[1] as SpinBox).value, (boxes[2] as SpinBox).value]))
				s.custom_minimum_size.x = 70
				boxes.append(s)
				r.add_child(s)
			prop_edit.add_child(r)
		FSATheme.slider_row(prop_edit, "scale", 0.1, 4.0, 0.05, float(p.get("scale", 1.0)), func(v: float) -> void: _set_prop(p, "scale", v))
		var cp := ColorPickerButton.new()
		cp.color = Color(str(p.get("color", "#c8c0d0")))
		cp.custom_minimum_size = Vector2(60, 26)
		cp.color_changed.connect(func(c: Color) -> void: _set_prop(p, "color", "#" + c.to_html(false)))
		FSATheme.row(prop_edit, [cp, FSATheme.button("REMOVE PROP", func() -> void:
			app.mutate("Remove prop", func() -> void: app.doc.remove_by_id(app.doc.props, prop_sel)))])

	func _set_prop(p: Dictionary, k: String, v: Variant) -> void:
		var id := str(p["id"])
		app.mutate("Prop " + k, func() -> void:
			for x in app.doc.props:
				if str((x as Dictionary)["id"]) == id:
					(x as Dictionary)[k] = v)


# ==================================================================== BLEND LAB

class Blend extends VBoxContainer:
	var app: FSAApp
	var clip_b := LineEdit.new()
	var at: SpinBox
	var span: SpinBox
	var new_name := LineEdit.new()
	var mask_opt: OptionButton
	var w: HSlider
	var found := ItemList.new()

	func setup(a: FSAApp) -> Control:
		app = a
		var body := FSATheme.scroll_body(self)
		body.add_child(FSATheme.heading("Blend Lab"))
		body.add_child(FSATheme.hint("Blend this clip with another one. TRANSITION: this clip, then B takes over at a frame, crossfading over N frames (try it as a layer, or make it a new clip). MIX: B on top of this clip on some bones only (a wave over a walk). Everything lands as layers you can tune in the Layers panel."))
		clip_b.placeholder_text = "clip B (type to search)"
		clip_b.text_changed.connect(func(t: String) -> void: _search(t))
		body.add_child(clip_b)
		found.custom_minimum_size.y = 90
		found.item_selected.connect(func(i: int) -> void: clip_b.text = found.get_item_text(i))
		body.add_child(found)
		var row := HBoxContainer.new()
		row.add_child(FSATheme.label("B starts at f", FSATheme.MUTED, 12))
		at = FSATheme.spin(0, 9999, 1, 12, func(_v: float) -> void: pass)
		row.add_child(at)
		row.add_child(FSATheme.label("crossfade frames", FSATheme.MUTED, 12))
		span = FSATheme.spin(0, 120, 1, 6, func(_v: float) -> void: pass)
		row.add_child(span)
		row.add_child(FSATheme.button("AT CURRENT FRAME", func() -> void: at.value = round(app.frame)))
		body.add_child(row)
		FSATheme.row(body, [FSATheme.button("TRY AS LAYER", func() -> void: _transition_layer(), "Adds an override layer: B fades in at the frame"),
			new_name, FSATheme.button("MAKE TRANSITION CLIP", func() -> void: _make())])
		new_name.placeholder_text = "new clip name"
		new_name.custom_minimum_size.x = 160
		FSATheme.sep(body)
		var masks := FSARig.MASKS.keys()
		mask_opt = FSATheme.option(masks, masks.find("Upper body"), func(_i: int) -> void: pass)
		w = FSATheme.slider_row(body, "mix weight", 0.0, 1.0, 0.01, 1.0, func(_v: float) -> void: pass)
		FSATheme.row(body, [FSATheme.label("bones", FSATheme.MUTED, 12), mask_opt, FSATheme.button("MIX B ON THESE BONES", func() -> void: _mix("override")),
			FSATheme.button("ADD B'S MOTION", func() -> void: _mix("add_delta"), "Adds B's movement (from its first frame) on top: a breathing or bounce layer")])
		_search("")
		return self

	func _search(t: String) -> void:
		found.clear()
		var n := 0
		for c in CBClipLib.list_clips():
			if t == "" or str(c).contains(t):
				found.add_item(str(c))
				n += 1
				if n > 60:
					break

	func _ok() -> bool:
		if CBClipLib.load_clip(clip_b.text.strip_edges()).is_empty():
			app.say("Pick clip B first.", "warn")
			return false
		return true

	func _transition_layer() -> void:
		if not _ok():
			return
		var b := clip_b.text.strip_edges()
		app.add_layer({"name": "to " + b, "mode": "override", "source": "clip", "clip": b, "offset": int(at.value), "cycle": false, "start": int(at.value), "fade_in": int(span.value)})
		app.dock.show_panel("Layers")

	func _make() -> void:
		if not _ok():
			return
		var n := new_name.text.strip_edges()
		if n == "":
			n = "%s_to_%s" % [app.doc.name, clip_b.text.strip_edges()]
		app.make_transition_clip(clip_b.text.strip_edges(), int(at.value), int(span.value), n)

	func _mix(mode: String) -> void:
		if not _ok():
			return
		var b := clip_b.text.strip_edges()
		app.add_layer({"name": "%s %s" % [b, mode], "mode": mode, "source": "clip", "clip": b, "weight": w.value, "mask": FSARig.MASKS[mask_opt.get_item_text(mask_opt.selected)]})
		app.dock.show_panel("Layers")


# ==================================================================== ADJUST

## a "drag to tilt" handle: press and move the mouse left / right to turn the part (hold Shift for fine)
class TiltDrag extends Button:
	signal dragged(delta_deg: float)
	var _down := false

	func _init() -> void:
		text = "< TILT >"
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_HSIZE
		tooltip_text = "Press and drag left / right to turn (hold Shift for fine steps)"

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_down = (e as InputEventMouseButton).pressed
			accept_event()
		elif e is InputEventMouseMotion and _down:
			var m := e as InputEventMouseMotion
			dragged.emit(m.relative.x * (0.05 if m.shift_pressed else 0.25))
			accept_event()


class Adjust extends VBoxContainer:
	var app: FSAApp
	var part: OptionButton
	var both: CheckBox
	var axis_hint: Label
	var scope_opt: OptionButton
	var ease_spin: SpinBox
	var from_spin: SpinBox
	var to_spin: SpinBox
	var range_row: HBoxContainer
	var deg: Array = []
	var list := VBoxContainer.new()
	var _bones: Array = []
	var _quiet := false

	func setup(a: FSAApp) -> Control:
		app = a
		var body := FSATheme.scroll_body(self)
		body.add_child(FSATheme.heading("Adjust"))
		body.add_child(FSATheme.hint("Tilt a body part across the whole clip, a frame range, or around this frame, without touching its keys: the shoulders up on every frame of a walk, an arm straighter, the hands meeting for a clap. Pick the part (or click it in a view), the scope, then drag TILT on an axis. Adjusted parts get a * in the Outliner; RESTORE takes an adjustment off."))
		part = FSATheme.option([], -1, func(i: int) -> void:
			if not _quiet:
				app.select_bone(str(_bones[i])))
		both = FSATheme.check("both sides", false, func(_on: bool) -> void: pass, "The other side gets the same turn, mirrored")
		FSATheme.row(body, [FSATheme.label("part", FSATheme.MUTED, 12), part, both])
		axis_hint = FSATheme.label("", FSATheme.MUTED, 12)
		axis_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(axis_hint)
		scope_opt = FSATheme.option(["all frames", "around this frame", "frame range"], 0, func(_i: int) -> void:
			range_row.visible = scope_opt.selected == 2
			_load())
		ease_spin = FSATheme.spin(0, 60, 1, 6, func(_v: float) -> void: _load(), "Frames it eases in and out over (0 = sharp)")
		FSATheme.row(body, [FSATheme.label("on", FSATheme.MUTED, 12), scope_opt, FSATheme.label("ease", FSATheme.MUTED, 12), ease_spin])
		from_spin = FSATheme.spin(0, 9999, 1, 0, func(_v: float) -> void: _load())
		to_spin = FSATheme.spin(0, 9999, 1, 30, func(_v: float) -> void: _load())
		range_row = FSATheme.row(body, [FSATheme.label("from f", FSATheme.MUTED, 12), from_spin, FSATheme.label("to f", FSATheme.MUTED, 12), to_spin,
			FSATheme.button("PLAY RANGE", func() -> void:
				from_spin.set_value_no_signal(app.play_range.x)
				to_spin.set_value_no_signal(app.play_range.y if app.play_range.y >= 0 else app.doc.frames)
				_load(), "Use the IN / OUT play range")])
		range_row.visible = false
		var cols := [FSATheme.RED, FSATheme.OK, FSATheme.LEFT]
		for i in 3:
			var axis := i
			var sb := FSATheme.spin(-180, 180, 0.5, 0, func(_v: float) -> void:
				if not _quiet:
					_apply(), "Degrees, the total turn of this adjustment", "deg")
			sb.custom_minimum_size.x = 132   # room for "-180.0 deg"
			deg.append(sb)
			var drag := TiltDrag.new()
			drag.dragged.connect(func(d: float) -> void: (deg[axis] as SpinBox).value += d)
			FSATheme.row(body, [FSATheme.label(["X", "Y", "Z"][i], cols[i], 16), drag, sb,
				FSATheme.button("0", func() -> void: (deg[axis] as SpinBox).value = 0.0, "No turn on this axis")])
		FSATheme.sep(body)
		body.add_child(FSATheme.label("Adjusted", FSATheme.GOLD, 14))
		body.add_child(list)
		FSATheme.row(body, [FSATheme.button("RESTORE ALL", func() -> void: app.adjust_restore(), "Every adjustment off: the keys as they were"),
			FSATheme.button("APPLY INTO KEYS", func() -> void: app.bake_to_keys(), "Bake layers (adjustments too) and constraints into plain keys (undo brings them back)")])
		app.changed.connect(func(w: String) -> void:
			if w == "fighter":
				_fill()
			if w in ["doc", "clip", "fighter"]:
				_list()
			if w in ["sel", "clip", "fighter"] or (w == "frame" and scope_opt.selected == 1):
				_show_bone()
				_load())
		_fill()
		_list()
		_show_bone()
		_load()
		return self

	func _fill() -> void:
		_quiet = true
		part.clear()
		_bones = []
		for g in FSARig.grouped(app.bones):
			for b in (g[1] as Array):
				_bones.append(str(b))
				part.add_item(str(b))
		_quiet = false

	func _show_bone() -> void:
		_quiet = true
		var i := _bones.find(app.sel_bone)
		if i >= 0:
			part.select(i)
		both.disabled = not FSARig.is_side(app.sel_bone)
		axis_hint.text = FSARig.hint(app.sel_bone)
		_quiet = false

	func _scope() -> String:
		return FSAAdjust.SCOPES[scope_opt.selected]

	## the current value of this part / scope into the three boxes (no edit)
	func _load() -> void:
		var v := app.adjust_value(app.sel_bone, _scope(), -1, int(from_spin.value), int(to_spin.value), int(ease_spin.value))
		_quiet = true
		for i in 3:
			(deg[i] as SpinBox).set_value_no_signal(snappedf(rad_to_deg(v[i]), 0.1))
		_quiet = false

	func _apply() -> void:
		var v := Vector3(deg_to_rad((deg[0] as SpinBox).value), deg_to_rad((deg[1] as SpinBox).value), deg_to_rad((deg[2] as SpinBox).value))
		app.adjust_part(app.sel_bone, v, _scope(), -1, int(from_spin.value), int(to_spin.value), int(ease_spin.value), both.button_pressed and not both.disabled)

	func _list() -> void:
		for c in list.get_children():
			c.queue_free()
		var ls := FSAAdjust.adjust_layers(app.doc)
		if ls.is_empty():
			list.add_child(FSATheme.label("Nothing adjusted.", FSATheme.MUTED, 12))
			return
		for l in ls:
			var id := str(l["id"])
			var bone := str(l.get("bone", ""))
			var r := HBoxContainer.new()
			var lb := FSATheme.label("* " + FSAAdjust.describe(l), FSATheme.TEXT, 13)
			lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			r.add_child(lb)
			r.add_child(FSATheme.button("PICK", func() -> void: app.select_bone(bone), "Select this part"))
			r.add_child(FSATheme.button("RESTORE", func() -> void: app.adjust_restore(id), "Take this adjustment off"))
			list.add_child(r)


# ==================================================================== FEET

## the feet across the clip: one lane per foot, a cell per frame coloured by how it stands (FSAApp.feet_report); click a cell
## to go to that frame
class FeetLanes extends Control:
	var app: FSAApp
	var report: Dictionary = {}
	const COLORS := {"flat": Color(0.36, 0.78, 0.45), "pivot": Color(0.95, 0.68, 0.25), "limit": Color(0.72, 0.55, 0.95),
		"sink": Color(0.92, 0.3, 0.3), "air": Color(0.25, 0.27, 0.32)}
	const LABEL_W := 22.0

	func _init() -> void:
		custom_minimum_size = Vector2(240, 58)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _draw() -> void:
		var fr: Array = report.get("frames", [])
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.11, 0.13))
		if fr.is_empty():
			return
		var w := (size.x - LABEL_W) / float(fr.size())
		var rh := (size.y - 6.0) / 2.0
		for li in 2:
			var b: String = ["footL", "footR"][li]
			draw_string(get_theme_default_font(), Vector2(2, 3 + rh * li + rh * 0.7), ["L", "R"][li], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, FSATheme.MUTED)
			for i in fr.size():
				var st := str(((fr[i] as Dictionary).get(b, {}) as Dictionary).get("state", "air"))
				draw_rect(Rect2(LABEL_W + i * w, 3 + rh * li + 1, maxf(1.0, w - 0.5), rh - 2), COLORS.get(st, Color.GRAY))
		var last := float(int((fr[fr.size() - 1] as Dictionary)["f"]))
		var x := LABEL_W + (app.frame / maxf(1.0, last)) * (size.x - LABEL_W - w) + w * 0.5
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(1, 1, 1, 0.9), 2.0)

	func _gui_input(e: InputEvent) -> void:
		var fr: Array = report.get("frames", [])
		if fr.is_empty() or not (e is InputEventMouse):
			return
		var press := e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
		var drag := e is InputEventMouseMotion and ((e as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
		if press or drag:
			var i := clampi(int(((e as InputEventMouse).position.x - LABEL_W) / ((size.x - LABEL_W) / float(fr.size()))), 0, fr.size() - 1)
			app.set_frame(float(int((fr[i] as Dictionary)["f"])))


class Feet extends VBoxContainer:
	var app: FSAApp
	var planted: CheckBox
	var soles_lb: Label
	var now_lb: Label
	var counts_lb: Label
	var lanes := FeetLanes.new()
	var _dirty := true
	const SAY := {"flat": "standing flat on the floor", "pivot": "on its toes / heel (pivot)", "limit": "standing, heel up: the ankle is at its natural bend",
		"sink": "INTO the floor", "air": "off the floor"}

	func setup(a: FSAApp) -> Control:
		app = a
		lanes.app = a
		var body := FSATheme.scroll_body(self)
		# the lanes and this frame first: the dock is short on a laptop screen, the explanation goes last
		planted = FSATheme.check("planted (ground the feet, as the match does)", false, func(on: bool) -> void: app.set_clip_prop("plant", on),
			"Clips on the ground: on. Clips in the air (jumps, aerials, falls): off")
		FSATheme.row(body, [FSATheme.heading("Feet"), planted, FSATheme.button("REFRESH", func() -> void: _dirty = true, "Measure the feet again")])
		lanes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_child(lanes)
		now_lb = FSATheme.label("", FSATheme.TEXT, 13)
		now_lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(now_lb)
		counts_lb = FSATheme.label("", FSATheme.MUTED, 12)
		counts_lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(counts_lb)
		soles_lb = FSATheme.label("", FSATheme.MUTED, 12)
		soles_lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(soles_lb)
		body.add_child(FSATheme.hint("Lanes: green flat on the floor, amber pivot (toes / heel), violet heel up at the ankle's limit, red INTO the floor, grey off it; click one to go to that frame. A planted clip stands each foot on its real sole (read from the model, which is not always level at rest), levels every standing foot and reaches the legs down with the knee's own bend; a foot the clip keys onto its toes or heel pivots there."))
		app.changed.connect(func(w: String) -> void:
			if w in ["doc", "clip", "fighter", "saved", "layer"]:
				_dirty = true
			if w in ["frame", "play"]:
				_show_now()
				lanes.queue_redraw())
		return self

	func _process(_d: float) -> void:
		if not _dirty or not is_visible_in_tree() or app.doc == null or app.stage == null or app.stage.probe_skel == null:
			return
		_dirty = false
		lanes.report = app.feet_report(1)
		planted.set_pressed_no_signal(app.doc.plant)
		var so: Dictionary = lanes.report.get("soles", {})
		var parts: PackedStringArray = []
		for b in so:
			parts.append("%s sole %.0f deg off level at rest, ankle %.1f cm over it" % [b, float(so[b]["tilt0"]), float(so[b]["ankle_cm"])])
		soles_lb.text = "This model: " + "; ".join(parts)
		var c: Dictionary = lanes.report.get("counts", {})
		var cp: PackedStringArray = []
		for k in ["flat", "pivot", "limit", "sink", "air"]:
			if int(c.get(k, 0)) > 0:
				cp.append("%s %d" % [k, int(c[k])])
		counts_lb.text = "Foot-frames: " + ", ".join(cp)
		_show_now()
		lanes.queue_redraw()

	func _show_now() -> void:
		var fr: Array = lanes.report.get("frames", [])
		if fr.is_empty():
			now_lb.text = ""
			return
		var i := clampi(int(round(app.frame)), 0, fr.size() - 1)
		var row: Dictionary = fr[i]
		var lines: PackedStringArray = []
		for b in ["footL", "footR"]:
			var d: Dictionary = row.get(b, {})
			lines.append("%s  %s  (%+.1f cm, %.0f deg)" % [b, SAY.get(str(d.get("state", "")), ""), float(d.get("low_cm", 0.0)), float(d.get("tilt", 0.0))])
		now_lb.text = "f%d  " % int(row["f"]) + "   |   ".join(lines)


# ==================================================================== MERGE

class Merge extends VBoxContainer:
	var app: FSAApp
	var find := LineEdit.new()
	var found := ItemList.new()
	var rows := VBoxContainer.new()
	var base_lbl: Label
	var len_lbl: Label
	var name_edit := LineEdit.new()
	var rebuild_btn: Button
	var _ids := ""

	func setup(a: FSAApp) -> Control:
		app = a
		var body := FSATheme.scroll_body(self)
		body.add_child(FSATheme.heading("Merge"))
		body.add_child(FSATheme.hint("One animation from several. The open clip is the BASE: it gives the body. Each clip ON TOP gives only the parts you light up (the arms of a cheer over a run, a clap over a walk), from its start frame, blending in and out. Play to see it. BAKE makes one new clip; the base stays as it is."))
		base_lbl = FSATheme.label("", FSATheme.GOLD, 14)
		body.add_child(base_lbl)
		find.placeholder_text = "clip to put on top (type to search)"
		find.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		find.text_changed.connect(func(t: String) -> void: _search(t))
		found.custom_minimum_size.y = 84
		found.item_activated.connect(func(i: int) -> void: _add(found.get_item_text(i)))
		FSATheme.row(body, [find, FSATheme.button("PUT ON TOP", func() -> void:
			var sel := found.get_selected_items()
			_add(found.get_item_text(sel[0]) if not sel.is_empty() else find.text.strip_edges()), "From the current frame, the arms and hands first; light up other parts on its row")])
		body.add_child(found)
		FSATheme.sep(body)
		body.add_child(rows)
		FSATheme.sep(body)
		len_lbl = FSATheme.label("", FSATheme.MUTED, 12)
		body.add_child(len_lbl)
		name_edit.placeholder_text = "name of the merged clip"
		name_edit.custom_minimum_size.x = 220
		rebuild_btn = FSATheme.button("REBUILD THE SETUP", func() -> void:
			if app.history.dirty():
				app.ask("Rebuild the merge behind %s? Changes to it are lost." % app.doc.name, func() -> void: app.merge_rebuild())
			else:
				app.merge_rebuild(), "This clip was merged: open its base with the clips on top again")
		FSATheme.row(body, [name_edit, FSATheme.button("BAKE INTO ONE CLIP", func() -> void:
			var n := name_edit.text.strip_edges()
			if n == "":
				n = app.doc.name + "_merged"
			app.merge_bake(n), "One new clip with everything above in it (opens unsaved; the base is not touched)"), rebuild_btn])
		_search("")
		app.changed.connect(func(w: String) -> void:
			if w in ["doc", "clip", "layer"]:
				refresh())
		refresh()
		return self

	func _search(t: String) -> void:
		found.clear()
		var n := 0
		for c in CBClipLib.list_clips():
			if t == "" or str(c).contains(t):
				found.add_item(str(c))
				n += 1
				if n > 80:
					break

	func _add(clip: String) -> void:
		if clip == "":
			app.say("Pick a clip to put on top.", "warn")
			return
		app.merge_add(clip)

	func refresh() -> void:
		var ml := FSAMerge.merge_layers(app.doc)
		base_lbl.text = "Base: %s  (%d frames%s)" % [app.doc.name, app.doc.frames, ", loops: repeats under longer clips" if app.doc.loop else ""]
		len_lbl.text = "The merged clip runs %d frames." % FSAMerge.length(app.doc) if not ml.is_empty() else "Nothing on top yet."
		rebuild_btn.visible = app.doc.extra.has("merge")
		if name_edit.text == "" or name_edit.text.ends_with("_merged"):
			name_edit.text = app.doc.name + "_merged"
		var ids := ",".join(ml.map(func(l: Dictionary) -> String: return str(l["id"])))
		if ids == _ids:
			return   # same rows: the widgets already show the values (no rebuild while you type)
		_ids = ids
		for c in rows.get_children():
			c.queue_free()
		for l in ml:
			rows.add_child(_row(l))

	func _row(l: Dictionary) -> Control:
		var id := str(l["id"])
		var box := VBoxContainer.new()
		var top := HBoxContainer.new()
		top.add_child(FSATheme.label(str(l.get("clip", "")), FSATheme.TEXT, 14))
		var parts: Array = (l.get("parts", []) as Array).duplicate()
		for p in FSAMerge.PARTS:
			var part: String = p
			var chip := FSATheme.button(part.to_upper(), func(on: bool) -> void:
				var cur: Array = (app.doc.layer_by_id(id).get("parts", []) as Array).duplicate()
				if on and not part in cur:
					cur.append(part)
				elif not on:
					cur.erase(part)
				app.merge_set(id, {"parts": cur}), "This part comes from this clip", true)
			chip.set_pressed_no_signal(part in parts)   # no toggle signal: building the row is not an edit
			top.add_child(chip)
		box.add_child(top)
		FSATheme.row(box, [FSATheme.label("start f", FSATheme.MUTED, 12), FSATheme.spin(0, 9999, 1, float(l.get("start", 0)), func(v: float) -> void: app.merge_set(id, {"start": int(v)})),
			FSATheme.button("NOW", func() -> void: app.merge_set(id, {"start": int(round(app.frame))}), "Start at the current frame"),
			FSATheme.label("blend in", FSATheme.MUTED, 12), FSATheme.spin(0, 240, 1, float(l.get("fade_in", 0)), func(v: float) -> void: app.merge_set(id, {"blend_in": int(v)})),
			FSATheme.label("out", FSATheme.MUTED, 12), FSATheme.spin(0, 240, 1, float(l.get("fade_out", 0)), func(v: float) -> void: app.merge_set(id, {"blend_out": int(v)})),
			FSATheme.label("weight", FSATheme.MUTED, 12), FSATheme.spin(0.0, 1.0, 0.05, float(l.get("weight", 1.0)), func(v: float) -> void: app.merge_set(id, {"weight": v})),
			FSATheme.check("loop it", bool(l.get("cycle", false)), func(on: bool) -> void: app.merge_set(id, {"cycle": on}), "Repeat this clip to the end"),
			FSATheme.check("mute", bool(l.get("mute", false)), func(on: bool) -> void: app.merge_set(id, {"mute": on})),
			FSATheme.button("REMOVE", func() -> void: app.remove_layer(id))])
		FSATheme.sep(box)
		return box


# ==================================================================== AGENTS

class Agents extends VBoxContainer:
	var app: FSAApp
	var log_list := ItemList.new()
	var head: Label

	func setup(a: FSAApp) -> Control:
		app = a
		var h := HBoxContainer.new()
		add_child(h)
		var left := VBoxContainer.new()
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left.size_flags_stretch_ratio = 1.6
		h.add_child(left)
		head = FSATheme.label("", FSATheme.PURPLE, 14)
		left.add_child(head)
		log_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		log_list.custom_minimum_size.y = 150
		left.add_child(log_list)
		var right := VBoxContainer.new()
		right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(right)
		right.add_child(FSATheme.heading("Connect an agent"))
		right.add_child(FSATheme.hint("Agents animate here through MCP: they read the rig, pose, key, blend, add constraints, render pictures to check their work, and save. Their edits show live (purple frame), are in History and undo like yours."))
		var te := TextEdit.new()
		te.text = FSAPanels.mcp_config_text()
		te.editable = false
		te.custom_minimum_size.y = 110
		right.add_child(te)
		FSATheme.row(right, [FSATheme.button("COPY MCP CONFIG", func() -> void:
				DisplayServer.clipboard_set(FSAPanels.mcp_config_text())
				app.say("MCP config copied.", "ok")),
			FSATheme.button("CLEAR LOG", func() -> void:
				app.api_log.clear()
				refresh())])
		app.changed.connect(func(w: String) -> void:
			if w in ["api", "status"]:
				refresh())
		refresh()
		return self

	func refresh() -> void:
		head.text = ("AGENT API listening on http://127.0.0.1:%d/rpc  -  %d calls" % [app.api_port, app.api_log.size()]) if app.server != null and app.server.listening else "AGENT API is off"
		if log_list.item_count == app.api_log.size():
			return
		log_list.clear()
		for i in range(app.api_log.size() - 1, maxi(-1, app.api_log.size() - 300), -1):
			var e: Dictionary = app.api_log[i]
			var idx := log_list.add_item("%s  %s  %s" % [e.get("time", ""), e.get("method", ""), e.get("summary", "")])
			log_list.set_item_custom_fg_color(idx, FSATheme.TEXT if bool(e.get("ok", true)) else FSATheme.RED)


# ==================================================================== HISTORY

class History extends VBoxContainer:
	var app: FSAApp
	var list := ItemList.new()

	func setup(a: FSAApp) -> Control:
		app = a
		FSATheme.row(self, [FSATheme.heading("  History"), FSATheme.button("UNDO", func() -> void: app.undo()), FSATheme.button("REDO", func() -> void: app.redo()),
			FSATheme.hint("newest first; [agent] = made by an agent. Double-click undoes back to that step.")])
		list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		list.item_activated.connect(func(i: int) -> void:
			for n in i + 1:
				app.undo())
		add_child(list)
		app.changed.connect(func(w: String) -> void:
			if w in ["doc", "clip", "saved"]:
				refresh())
		refresh()
		return self

	func refresh() -> void:
		list.clear()
		for t in app.history.labels(200):
			var i := list.add_item(str(t))
			if str(t).begins_with("[agent]"):
				list.set_item_custom_fg_color(i, FSATheme.PURPLE)


# ==================================================================== CHECKS

class Checks extends VBoxContainer:
	var app: FSAApp
	var list := ItemList.new()
	var results: Array = []

	func setup(a: FSAApp) -> Control:
		app = a
		FSATheme.row(self, [FSATheme.heading("  Checks"), FSATheme.button("RUN", func() -> void: run(), "Knees never bend forward, joint limits, the loop seam, planted feet sliding, unkeyed edits")])
		list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		list.item_selected.connect(func(i: int) -> void:
			var f := int((results[i] as Dictionary).get("f", -1))
			if f >= 0:
				app.set_frame(float(f)))
		add_child(list)
		app.changed.connect(func(w: String) -> void:
			if w in ["saved", "clip"]:
				run())
		return self

	func run() -> void:
		results = app.run_checks()
		list.clear()
		for r in results:
			var rd: Dictionary = r
			var i := list.add_item(str(rd["text"]))
			list.set_item_custom_fg_color(i, {"error": FSATheme.RED, "warn": FSATheme.ACCENT, "ok": FSATheme.OK}.get(str(rd["level"]), FSATheme.TEXT))


# ==================================================================== RENDER

class Render extends VBoxContainer:
	var app: FSAApp
	var res: OptionButton
	var cols: SpinBox
	var from_f: SpinBox
	var to_f: SpinBox
	var last: Label
	const SIZES := [["HD 1280 x 720", 1280, 720], ["Full HD 1920 x 1080", 1920, 1080], ["QHD 2560 x 1440", 2560, 1440], ["4K 3840 x 2160", 3840, 2160],
		["Square 1080", 1080, 1080], ["Vertical 1080 x 1920", 1080, 1920]]

	func setup(a: FSAApp) -> Control:
		app = a
		var body := FSATheme.scroll_body(self)
		body.add_child(FSATheme.heading("Render"))
		body.add_child(FSATheme.hint("Pictures of your animation at HD or 4K, saved to " + FSAApp.RENDERS + ". The still and the sequence use the view you clicked last."))
		res = FSATheme.option(SIZES.map(func(s: Array) -> String: return str(s[0])), 1, func(_i: int) -> void: pass)
		body.add_child(res)
		FSATheme.row(body, [FSATheme.button("STILL OF THE VIEW", func() -> void: _still()),
			FSATheme.label("sheet columns", FSATheme.MUTED, 12), _cols(), FSATheme.button("REVIEW SHEET (4 ANGLES)", func() -> void: _sheet())])
		from_f = FSATheme.spin(0, 9999, 1, 0, func(_v: float) -> void: pass)
		to_f = FSATheme.spin(0, 9999, 1, app.doc.frames, func(_v: float) -> void: pass)
		FSATheme.row(body, [FSATheme.label("frames", FSATheme.MUTED, 12), from_f, FSATheme.label("to", FSATheme.MUTED, 12), to_f, FSATheme.button("PNG SEQUENCE", func() -> void: _seq())])
		FSATheme.row(body, [FSATheme.button("OPEN THE FOLDER", func() -> void:
			DirAccess.make_dir_recursive_absolute(FSAApp.RENDERS)
			OS.shell_open(FSAApp.RENDERS))])
		last = FSATheme.hint("")
		body.add_child(last)
		app.changed.connect(func(w: String) -> void:
			if w == "clip":
				to_f.value = app.doc.frames)
		return self

	func _cols() -> SpinBox:
		cols = FSATheme.spin(2, 24, 1, 8, func(_v: float) -> void: pass)
		return cols

	func _wh() -> Vector2i:
		var s: Array = SIZES[res.selected]
		return Vector2i(int(s[1]), int(s[2]))

	func _still() -> void:
		var wh := _wh()
		var p: String = await app.render_view(wh.x, wh.y)
		last.text = p

	func _sheet() -> void:
		var wh := _wh()
		var p: String = await app.render_strip(wh.x, wh.y, int(cols.value))
		last.text = p

	func _seq() -> void:
		var wh := _wh()
		var p: String = await app.render_sequence(wh.x, wh.y, int(from_f.value), int(to_f.value))
		last.text = p
