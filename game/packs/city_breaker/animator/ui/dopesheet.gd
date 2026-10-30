class_name FSADope
extends Control
## The dope sheet: a ruler (click / drag to scrub; markers, the move's hit / clear marks and effect cues on it), the summary row
## (every key: drag to retime, gold = key, blue = breakdown, red = extreme, purple ring = linked "same key", grey = locked),
## a row per layer and constraint (their frame ranges), and a row per bone grouped by body part (a diamond where the key holds
## that bone). Click a key to select it (Shift adds), drag across empty rows to box-select, drag selected keys to move them,
## right-click for ease, tags, link, lock, copy / paste, delete. Ctrl + wheel zooms time, middle-drag pans, wheel scrolls rows.

const NAME_W := 168.0
const RULER_H := 30.0
const ROW_H := 21.0

var app: FSAApp
var x0 := 0.0                 # frame at the left edge
var ppf := 14.0               # pixels per frame
var scroll := 0.0
var collapsed: Dictionary = {"Hand L": true, "Hand R": true, "Ears": true, "Extras": true}
var rows: Array = []          # [{kind, label, bone, layer, con, group, y}]
var _drag := ""
var _press := Vector2.ZERO
var _drag_delta := 0
var _box := Rect2()
var _menu := PopupMenu.new()
var _ease_menu := PopupMenu.new()
var _tag_menu := PopupMenu.new()
var _fit_done := false
var _user_zoom := false
var _last_w := 0.0


func setup(p_app: FSAApp) -> FSADope:
	app = p_app
	clip_contents = true
	focus_mode = Control.FOCUS_CLICK
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(300, 120)
	_ease_menu.name = "ease"
	for e in FSADoc.EASES:
		_ease_menu.add_item(str(e))
	_ease_menu.index_pressed.connect(func(i: int) -> void: app.set_keys_field(app.sel_keys, "ease", FSADoc.EASES[i]))
	_tag_menu.name = "tag"
	for t in FSADoc.TAGS:
		_tag_menu.add_item(str(t))
	_tag_menu.index_pressed.connect(func(i: int) -> void: app.set_keys_field(app.sel_keys, "tag", "" if FSADoc.TAGS[i] == "key" else FSADoc.TAGS[i]))
	_menu.add_submenu_node_item("Ease to next key", _ease_menu)
	_menu.add_submenu_node_item("Key type", _tag_menu)
	_menu.add_separator()
	_menu.add_item("Link as the same key (edit one, all follow)", 1)
	_menu.add_item("Unlink", 2)
	_menu.add_item("Lock (protect from edits)", 3)
	_menu.add_item("Unlock", 4)
	_menu.add_separator()
	_menu.add_item("Copy keys", 5)
	_menu.add_item("Paste keys at the current frame", 6)
	_menu.add_item("Mirror the pose of these keys", 7)
	_menu.add_item("Select all keys", 8)
	_menu.add_separator()
	_menu.add_item("Delete keys", 9)
	_menu.id_pressed.connect(_on_menu)
	add_child(_menu)
	return self


func _on_menu(id: int) -> void:
	match id:
		1:
			app.link_keys(app.sel_keys)
		2:
			app.unlink_keys(app.sel_keys)
		3:
			app.set_keys_field(app.sel_keys, "lock", true)
		4:
			app.set_keys_field(app.sel_keys, "lock", false)
		5:
			app.copy_keys(app.sel_keys)
		6:
			app.paste_keys(int(round(float(app.frame))))
		7:
			app.mirror_keys(app.sel_keys)
		8:
			app.select_keys(app.doc.key_frames(), false)
		9:
			app.delete_keys(app.sel_keys)


func fit() -> void:
	var n := float(app.doc.frames)
	ppf = clampf((size.x - NAME_W - 30.0) / maxf(n, 1.0), 2.0, 60.0)
	x0 = -1.0
	queue_redraw()


func f2x(f: float) -> float:
	return NAME_W + (f - x0) * ppf


func x2f(x: float) -> float:
	return (x - NAME_W) / ppf + x0


func _build_rows() -> void:
	rows.clear()
	var y := RULER_H - scroll
	rows.append({"kind": "summary", "label": "ALL KEYS", "y": y})
	y += ROW_H
	for l in app.doc.layers:
		var ld: Dictionary = l
		rows.append({"kind": "layer", "label": "layer  " + str(ld.get("name", "")), "layer": str(ld.get("id", "")), "y": y})
		y += ROW_H
	for c in app.doc.constraints:
		var cd: Dictionary = c
		rows.append({"kind": "con", "label": str(cd.get("name", cd.get("type", ""))), "con": str(cd.get("id", "")), "y": y})
		y += ROW_H
	for g in FSARig.grouped(app.bones):
		var gname := str(g[0])
		rows.append({"kind": "group", "label": gname, "group": gname, "y": y})
		y += ROW_H
		if collapsed.get(gname, false):
			continue
		for b in (g[1] as Array):
			rows.append({"kind": "bone", "label": str(b), "bone": str(b), "y": y})
			y += ROW_H


func _process(_dt: float) -> void:
	if size.x > 100 and (not _fit_done or (not _user_zoom and absf(size.x - _last_w) > 2.0)):
		_fit_done = true
		_last_w = size.x
		fit()


func _draw() -> void:
	if app == null or app.doc == null:
		return
	_build_rows()
	var font := ThemeDB.fallback_font
	var n := int(app.doc.frames)
	draw_rect(Rect2(Vector2.ZERO, size), FSATheme.BG0)
	# frame range shade + rows
	draw_rect(Rect2(Vector2(f2x(0), RULER_H), Vector2(n * ppf, size.y - RULER_H)), Color(FSATheme.BG1, 1.0))
	for r in rows:
		var rd: Dictionary = r
		var y := float(rd["y"])
		if y < RULER_H - ROW_H or y > size.y:
			continue
		var kind := str(rd["kind"])
		var bg := FSATheme.BG2 if kind in ["summary", "group"] else Color(0, 0, 0, 0)
		if kind == "bone" and str(rd["bone"]) in app.sel_bones:
			bg = Color(FSATheme.ACCENT, 0.12)
		if bg.a > 0:
			draw_rect(Rect2(Vector2(0, y), Vector2(size.x, ROW_H - 1)), bg)
		draw_line(Vector2(0, y + ROW_H - 1), Vector2(size.x, y + ROW_H - 1), Color(FSATheme.LINE, 0.35))
	# vertical frame grid
	var step := _tick_step()
	var f0 := int(floor(x0 / step) * step)
	var fi := f0
	while f2x(fi) < size.x:
		if fi >= 0:
			var x := f2x(fi)
			draw_line(Vector2(x, RULER_H), Vector2(x, size.y), Color(FSATheme.LINE, 0.25 if fi % (step * 5) != 0 else 0.5))
		fi += step
	# rows content
	for r in rows:
		var rd: Dictionary = r
		var y := float(rd["y"])
		if y < RULER_H - ROW_H or y > size.y:
			continue
		var cy := y + ROW_H * 0.5
		match str(rd["kind"]):
			"summary":
				_draw_summary(cy)
			"bone":
				_draw_bone_row(str(rd["bone"]), cy)
			"layer":
				_draw_layer_row(app.doc.layer_by_id(str(rd["layer"])), y, cy)
			"con":
				_draw_con_row(app.doc.constraint_by_id(str(rd["con"])), y)
	# box select
	if _drag == "box":
		draw_rect(_box.abs(), Color(FSATheme.ACCENT, 0.12))
		draw_rect(_box.abs(), FSATheme.ACCENT, false, 1.0)
	# name column on top
	draw_rect(Rect2(Vector2(0, RULER_H), Vector2(NAME_W, size.y)), FSATheme.BG1)
	for r in rows:
		var rd: Dictionary = r
		var y := float(rd["y"])
		if y < RULER_H - ROW_H or y > size.y:
			continue
		var kind := str(rd["kind"])
		var col := FSATheme.TEXT
		var x := 10.0
		var label := str(rd["label"])
		if kind == "group":
			col = FSATheme.GOLD
			label = ("+ " if collapsed.get(str(rd["group"]), false) else "- ") + label
		elif kind == "bone":
			x = 22.0
			var b := str(rd["bone"])
			col = FSATheme.LEFT if FSARig.side_of(b) == "L" else (FSATheme.RIGHT if FSARig.side_of(b) == "R" else FSATheme.TEXT)
			if b == app.sel_bone:
				col = Color.WHITE
			if app.doc.is_locked(b):
				label += "  [lock]"
				col = FSATheme.MUTED
			elif app.doc.lock_channels(b) != "":
				label += "  [%s]" % app.doc.lock_channels(b)
		elif kind == "summary":
			col = FSATheme.ACCENT
		elif kind == "layer":
			col = FSATheme.OK if str(app.active_layer) != str(rd["layer"]) else Color.WHITE
		elif kind == "con":
			col = FSATheme.PURPLE
		draw_string(font, Vector2(x, y + ROW_H - 6), label, HORIZONTAL_ALIGNMENT_LEFT, NAME_W - x - 4, 13, col)
	draw_line(Vector2(NAME_W, RULER_H), Vector2(NAME_W, size.y), FSATheme.LINE)
	_draw_ruler(font, n, step)
	# now line
	var nx := f2x(float(app.frame))
	if nx >= NAME_W:
		draw_line(Vector2(nx, 0), Vector2(nx, size.y), FSATheme.ACCENT, 2.0)
		draw_rect(Rect2(Vector2(nx - 16, 2), Vector2(32, 16)), FSATheme.ACCENT)
		draw_string(font, Vector2(nx - 16, 15), str(int(round(float(app.frame)))), HORIZONTAL_ALIGNMENT_CENTER, 32, 12, FSATheme.BG0)


func _tick_step() -> int:
	for s in [1, 2, 5, 10, 20, 50, 100]:
		if s * ppf >= 9.0:
			return s
	return 200


func _draw_ruler(font: Font, n: int, step: int) -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, RULER_H)), FSATheme.BG2)
	var fi := int(floor(x0 / step) * step)
	while f2x(fi) < size.x:
		if fi >= 0 and f2x(fi) >= NAME_W:
			var x := f2x(fi)
			var major := fi % (step * 5) == 0
			draw_line(Vector2(x, RULER_H - (10 if major else 5)), Vector2(x, RULER_H), FSATheme.MUTED)
			if major or step * ppf > 28:
				draw_string(font, Vector2(x + 2, 13), str(fi), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, FSATheme.MUTED if fi <= n else Color(FSATheme.MUTED, 0.4))
		fi += step
	# end of clip
	var ex := f2x(n)
	if ex > NAME_W:
		draw_line(Vector2(ex, 0), Vector2(ex, size.y), Color(FSATheme.GOLD, 0.6), 1.0)
	# play range
	var pr: Vector2i = app.play_range_frames()
	if pr.x > 0 or pr.y < n:
		draw_rect(Rect2(Vector2(f2x(pr.x), RULER_H - 4), Vector2((pr.y - pr.x) * ppf, 4)), FSATheme.OK)
	# effect cues
	for cf in app.cue_frames():
		var x := f2x(float(cf))
		if x > NAME_W:
			draw_rect(Rect2(Vector2(x - 1, RULER_H - 12), Vector2(3, 8)), FSATheme.OK)
	# the move's marks (hit / clear) and markers
	var marks: Dictionary = app.doc.extra.get("marks", {})
	for mk in marks:
		var x := f2x(float(marks[mk]))
		if x > NAME_W:
			var c := FSATheme.RED if str(mk) == "hit" else FSATheme.LEFT
			draw_colored_polygon(PackedVector2Array([Vector2(x, RULER_H - 2), Vector2(x - 5, RULER_H - 10), Vector2(x + 5, RULER_H - 10)]), c)
			draw_string(font, Vector2(x + 6, RULER_H - 3), str(mk), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, c)
	for m in app.doc.markers:
		var md: Dictionary = m
		var x := f2x(float(md.get("f", 0)))
		if x > NAME_W:
			draw_line(Vector2(x, 14), Vector2(x, RULER_H), FSATheme.GOLD, 1.5)
			draw_rect(Rect2(Vector2(x, 14), Vector2(7, 6)), FSATheme.GOLD)
			draw_string(font, Vector2(x + 9, 22), str(md.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, FSATheme.GOLD)
	draw_rect(Rect2(Vector2.ZERO, Vector2(NAME_W, RULER_H)), FSATheme.BG2)
	draw_string(font, Vector2(8, 19), "%s  %d f @ %d" % [str(app.doc.name), n, int(app.doc.fps)], HORIZONTAL_ALIGNMENT_LEFT, NAME_W - 10, 12, FSATheme.GOLD)


func _key_color(k: Dictionary) -> Color:
	if bool(k.get("lock", false)):
		return FSATheme.MUTED
	match str(k.get("tag", "key")):
		"breakdown":
			return FSATheme.LEFT
		"extreme":
			return FSATheme.RIGHT
	return FSATheme.GOLD


func _diamond(c: Vector2, r: float, fill: Color, outline: Color) -> void:
	var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
	draw_colored_polygon(pts, fill)
	pts.append(pts[0])
	draw_polyline(pts, outline, 1.2, true)


func _shift_of(f: int) -> int:
	return _drag_delta if (_drag == "move" and f in app.sel_keys) else 0


func _draw_summary(cy: float) -> void:
	var ks: Array = app.doc.keys
	var links: Dictionary = {}
	for i in ks.size():
		var k: Dictionary = ks[i]
		var f := int(k["f"]) + _shift_of(int(k["f"]))
		var x := f2x(f)
		if i + 1 < ks.size():
			var nf := int((ks[i + 1] as Dictionary)["f"]) + _shift_of(int((ks[i + 1] as Dictionary)["f"]))
			var ez := str(k.get("ease", app.doc.ease))
			var ec := {"linear": FSATheme.MUTED, "in": FSATheme.ACCENT, "out": FSATheme.LEFT, "inout": FSATheme.OK, "hold": FSATheme.RED, "spline": FSATheme.PURPLE}.get(ez, FSATheme.MUTED) as Color
			draw_line(Vector2(x + 7, cy + 6), Vector2(f2x(nf) - 7, cy + 6), Color(ec, 0.7), 2.0 if ez != "hold" else 3.0)
		var l := str(k.get("link", ""))
		if l != "":
			if not links.has(l):
				links[l] = []
			(links[l] as Array).append(x)
	for l in links:
		var xs: Array = links[l]
		for j in range(1, xs.size()):
			draw_arc(Vector2((float(xs[j - 1]) + float(xs[j])) * 0.5, cy - 6), (float(xs[j]) - float(xs[j - 1])) * 0.5, PI, TAU, 24, Color(FSATheme.PURPLE, 0.7), 1.2)
	for k in ks:
		var kd: Dictionary = k
		var f := int(kd["f"]) + _shift_of(int(kd["f"]))
		var x := f2x(f)
		if x < NAME_W - 8 or x > size.x + 8:
			continue
		var sel: bool = int(kd["f"]) in app.sel_keys
		var r := 7.0 if str(kd.get("tag", "")) != "breakdown" else 5.5
		if str(kd.get("tag", "")) == "extreme":
			r = 8.0
		_diamond(Vector2(x, cy), r, Color.WHITE if sel else _key_color(kd), FSATheme.ACCENT if sel else FSATheme.BG0)
		if str(kd.get("link", "")) != "":
			draw_arc(Vector2(x, cy), r + 3, 0, TAU, 16, FSATheme.PURPLE, 1.5, true)
		if int(kd["f"]) > int(app.doc.frames):
			draw_line(Vector2(x - 6, cy - 6), Vector2(x + 6, cy + 6), FSATheme.RED, 1.5)


func _draw_bone_row(b: String, cy: float) -> void:
	for k in app.doc.keys:
		var kd: Dictionary = k
		var has := (kd.get("rot", {}) as Dictionary).has(b)
		if b == "hips" and not has:
			has = absf(float(kd.get("hips_dy", 0.0))) + absf(float(kd.get("hips_dx", 0.0))) + absf(float(kd.get("hips_dz", 0.0))) > 0.0
		var f := int(kd["f"]) + _shift_of(int(kd["f"]))
		var x := f2x(f)
		if x < NAME_W - 6 or x > size.x + 6:
			continue
		var sel: bool = int(kd["f"]) in app.sel_keys
		if has:
			_diamond(Vector2(x, cy), 5.0, Color.WHITE if sel else _key_color(kd), FSATheme.BG0)
		else:
			draw_circle(Vector2(x, cy), 1.8, Color(FSATheme.MUTED, 0.5))


func _draw_layer_row(l: Dictionary, y: float, cy: float) -> void:
	if l.is_empty():
		return
	var a := float(l.get("start", 0))
	var b := float(l.get("end", -1))
	if b < 0:
		b = float(app.doc.frames)
	var muted := bool(l.get("mute", false))
	var c := FSATheme.OK if not muted else FSATheme.MUTED
	var r := Rect2(Vector2(f2x(a), y + 4), Vector2((b - a) * ppf, ROW_H - 9))
	draw_rect(r, Color(c, 0.18))
	var w := clampf(float(l.get("weight", 1.0)), 0.0, 1.0)
	draw_rect(Rect2(r.position + Vector2(0, r.size.y * (1.0 - w)), Vector2(r.size.x, r.size.y * w)), Color(c, 0.35))
	draw_rect(r, Color(c, 0.8), false, 1.0)
	if str(l.get("source", "keys")) == "keys":
		for k in (l.get("keys", []) as Array):
			_diamond(Vector2(f2x(float((k as Dictionary)["f"])), cy), 5.0, FSATheme.OK, FSATheme.BG0)
	else:
		draw_string(ThemeDB.fallback_font, r.position + Vector2(4, 11), "clip " + str(l.get("clip", "")), HORIZONTAL_ALIGNMENT_LEFT, maxf(10, r.size.x - 6), 10, FSATheme.TEXT)


func _draw_con_row(c: Dictionary, y: float) -> void:
	if c.is_empty():
		return
	var a := float(c.get("start", 0))
	var b := float(c.get("end", -1))
	if b < 0:
		b = float(app.doc.frames)
	var on := bool(c.get("enabled", true))
	var col := FSATheme.PURPLE if on else FSATheme.MUTED
	var r := Rect2(Vector2(f2x(a), y + 5), Vector2((b - a) * ppf, ROW_H - 11))
	draw_rect(r, Color(col, 0.3 * float(c.get("influence", 1.0)) + 0.1))
	draw_rect(r, col, false, 1.0)
	if c.has("pin_frame"):
		var px := f2x(float(c["pin_frame"]))
		draw_line(Vector2(px, y + 3), Vector2(px, y + ROW_H - 3), Color.WHITE, 2.0)


# ---------------------------------------------------------------- input

func _key_at(p: Vector2) -> int:
	for r in rows:
		var rd: Dictionary = r
		var y := float(rd["y"])
		if p.y < y or p.y > y + ROW_H or not (str(rd["kind"]) in ["summary", "bone"]):
			continue
		var best := -1
		var bd := 8.0
		for k in app.doc.keys:
			var kf := int((k as Dictionary)["f"])
			var d := absf(f2x(kf) - p.x)
			if d < bd:
				bd = d
				best = kf
		return best
	return -1


func _row_at(p: Vector2) -> Dictionary:
	for r in rows:
		var rd: Dictionary = r
		var y := float(rd["y"])
		if p.y >= y and p.y < y + ROW_H:
			return rd
	return {}


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var up := mb.button_index == MOUSE_BUTTON_WHEEL_UP
			if mb.ctrl_pressed:
				_user_zoom = true
				var fm := x2f(mb.position.x)
				ppf = clampf(ppf * (1.15 if up else 1.0 / 1.15), 1.0, 120.0)
				x0 = fm - (mb.position.x - NAME_W) / ppf
			elif mb.shift_pressed:
				x0 += (-4.0 if up else 4.0) * 10.0 / ppf
			else:
				scroll = maxf(0.0, scroll + (-ROW_H * 2 if up else ROW_H * 2))
			queue_redraw()
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_drag = "pan" if mb.pressed else ""
			_press = mb.position
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var kf := _key_at(mb.position)
			if kf >= 0 and not (kf in app.sel_keys):
				app.select_keys([kf], false)
			_menu.popup(Rect2i(DisplayServer.mouse_get_position(), Vector2i.ZERO))
			accept_event()
			return
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			grab_focus()
			_press = mb.position
			if mb.position.y < RULER_H and mb.position.x > NAME_W:
				_drag = "scrub"
				app.set_frame(clampf(round(x2f(mb.position.x)), 0.0, float(app.doc.frames)))
			elif mb.position.x < NAME_W:
				var rd := _row_at(mb.position)
				if str(rd.get("kind", "")) == "group":
					collapsed[str(rd["group"])] = not collapsed.get(str(rd["group"]), false)
				elif str(rd.get("kind", "")) == "bone":
					app.select_bone(str(rd["bone"]), mb.shift_pressed)
				elif str(rd.get("kind", "")) == "layer":
					app.set_active_layer(str(rd["layer"]))
				elif str(rd.get("kind", "")) == "summary":
					app.set_active_layer("")
				queue_redraw()
			else:
				var kf := _key_at(mb.position)
				if kf >= 0:
					if mb.double_click:
						app.set_frame(float(kf))
					if mb.shift_pressed:
						var s: Array = app.sel_keys.duplicate()
						if kf in s:
							s.erase(kf)
						else:
							s.append(kf)
						app.select_keys(s, false)
					elif not (kf in app.sel_keys):
						app.select_keys([kf], false)
					_drag = "move"
					_drag_delta = 0
				else:
					_drag = "box"
					_box = Rect2(mb.position, Vector2.ZERO)
					if not mb.shift_pressed:
						app.select_keys([], false)
		else:
			if _drag == "move" and _drag_delta != 0:
				app.move_keys(app.sel_keys, _drag_delta)
			elif _drag == "box":
				_finish_box(mb.shift_pressed)
			_drag = ""
			_drag_delta = 0
			queue_redraw()
		accept_event()
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		match _drag:
			"pan":
				x0 -= mm.relative.x / ppf
				scroll = maxf(0.0, scroll - mm.relative.y)
				queue_redraw()
			"scrub":
				app.set_frame(clampf(round(x2f(mm.position.x)), 0.0, float(app.doc.frames)))
			"move":
				_drag_delta = int(round((mm.position.x - _press.x) / ppf))
				queue_redraw()
			"box":
				_box.size = mm.position - _box.position
				queue_redraw()
		accept_event()


func _finish_box(add: bool) -> void:
	var r := _box.abs()
	var picked: Array = app.sel_keys.duplicate() if add else []
	for row in rows:
		var rd: Dictionary = row
		var y := float(rd["y"]) + ROW_H * 0.5
		if y < r.position.y or y > r.end.y or not (str(rd["kind"]) in ["summary", "bone"]):
			continue
		for k in app.doc.keys:
			var kf := int((k as Dictionary)["f"])
			var x := f2x(kf)
			if x >= r.position.x and x <= r.end.x and not (kf in picked):
				picked.append(kf)
	app.select_keys(picked, false)
