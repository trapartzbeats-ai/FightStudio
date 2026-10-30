class_name FSAGraph
extends Control
## The graph editor: the selected bone's X / Y / Z curves (degrees) over the clip, keys as dots you drag up / down to change that
## channel's value in that key, or left / right to move the key in time. The faint dashed line is the final motion after
## layers and constraints (what the game plays). Wheel zooms values, Ctrl + wheel zooms time, middle-drag pans, F fits.

const RULER_H := 26.0
const LEFT_W := 52.0

var app: FSAApp
var x0 := -1.0
var ppf := 12.0
var v_mid := 0.0              # degrees at the vertical middle
var ppd := 2.0                # pixels per degree
var channels := [true, true, true]
var show_final := true
var show_hips := false
var _drag := ""
var _press := Vector2.ZERO
var _pt: Dictionary = {}      # {f, axis, start_val}
var _fit_pending := true
var _bar: HBoxContainer
var _last_w := 0.0


func setup(p_app: FSAApp) -> FSAGraph:
	app = p_app
	clip_contents = true
	focus_mode = Control.FOCUS_CLICK
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bar = HBoxContainer.new()
	_bar.position = Vector2(LEFT_W + 6, RULER_H + 4)
	add_child(_bar)
	for i in 3:
		var b := FSATheme.button(["X", "Y", "Z"][i], func(on: bool) -> void:
			channels[i] = on
			queue_redraw(), "Show the %s channel" % ["X", "Y", "Z"][i], true)
		b.button_pressed = true
		b.add_theme_color_override("font_color", FSATheme.AXIS[i])
		_bar.add_child(b)
	var fb := FSATheme.button("FINAL", func(on: bool) -> void:
		show_final = on
		queue_redraw(), "Dashed: the final motion after layers and constraints", true)
	fb.button_pressed = true
	_bar.add_child(fb)
	var hb := FSATheme.button("HIPS MOVE", func(on: bool) -> void:
		show_hips = on
		_fit_pending = true
		queue_redraw(), "Show the hips shift (cm) instead of the rotation", true)
	_bar.add_child(hb)
	_bar.add_child(FSATheme.button("FIT", func() -> void:
		_fit_pending = true
		queue_redraw(), "Fit the curves (F)"))
	return self


func f2x(f: float) -> float:
	return LEFT_W + (f - x0) * ppf


func x2f(x: float) -> float:
	return (x - LEFT_W) / ppf + x0


func v2y(v: float) -> float:
	return RULER_H + (size.y - RULER_H) * 0.5 - (v - v_mid) * ppd


func y2v(y: float) -> float:
	return v_mid - (y - RULER_H - (size.y - RULER_H) * 0.5) / ppd


## the values shown: degrees (rotation) or centimetres (hips shift) per frame for each axis
func _series() -> Dictionary:
	var c: Dictionary = app.graph_curves(str(app.sel_bone))
	var k := 100.0 if show_hips else rad_to_deg(1.0)
	var key_name := "hips" if show_hips else "layer"
	var lay: Array = []
	for v in (c.get(key_name, []) as Array):
		lay.append((v as Vector3) * k)
	var fin: Array = []
	for v in (c.get("hips_final" if show_hips else "final", []) as Array):
		fin.append((v as Vector3) * k)
	return {"layer": lay, "final": fin, "k": k}


func fit() -> void:
	var s := _series()
	var lo := INF
	var hi := -INF
	for v in (s["layer"] as Array) + (s["final"] as Array):
		for i in 3:
			if channels[i]:
				lo = minf(lo, (v as Vector3)[i])
				hi = maxf(hi, (v as Vector3)[i])
	if lo == INF:
		lo = -10.0
		hi = 10.0
	if hi - lo < 10.0:
		var m := (hi + lo) * 0.5
		lo = m - 5.0
		hi = m + 5.0
	v_mid = (lo + hi) * 0.5
	ppd = (size.y - RULER_H - 40.0) / (hi - lo)
	ppf = clampf((size.x - LEFT_W - 20.0) / maxf(float(app.doc.frames), 1.0), 1.0, 80.0)
	x0 = -0.5
	queue_redraw()


func _draw() -> void:
	if app == null or app.doc == null:
		return
	if size.x > 50 and absf(size.x - _last_w) > 40.0:
		_last_w = size.x
		_fit_pending = true
	if _fit_pending and size.x > 50:
		_fit_pending = false
		fit()
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, size), FSATheme.BG0)
	var n := int(app.doc.frames)
	draw_rect(Rect2(Vector2(f2x(0), RULER_H), Vector2(n * ppf, size.y)), FSATheme.BG1)
	# value grid
	var vstep := 5.0
	for s in [1.0, 2.0, 5.0, 10.0, 15.0, 30.0, 45.0, 90.0]:
		if s * ppd >= 22.0:
			vstep = s
			break
	var vtop := y2v(RULER_H)
	var v := floorf(y2v(size.y) / vstep) * vstep
	while v <= vtop:
		var y := v2y(v)
		draw_line(Vector2(LEFT_W, y), Vector2(size.x, y), Color(FSATheme.LINE, 0.6 if absf(v) < 0.001 else 0.25))
		draw_string(font, Vector2(4, y + 4), ("%d" % int(v)) + ("cm" if show_hips else "°"), HORIZONTAL_ALIGNMENT_LEFT, LEFT_W - 6, 10, FSATheme.MUTED)
		v += vstep
	var s := _series()
	var lay: Array = s["layer"]
	var fin: Array = s["final"]
	for ax in 3:
		if not channels[ax]:
			continue
		var col: Color = FSATheme.AXIS[ax]
		if show_final and not fin.is_empty():
			for f in range(0, fin.size() - 1):
				if f % 2 == 0:
					draw_line(Vector2(f2x(f), v2y((fin[f] as Vector3)[ax])), Vector2(f2x(f + 1), v2y((fin[f + 1] as Vector3)[ax])), Color(col, 0.35), 1.0)
		var pts := PackedVector2Array()
		for f in lay.size():
			pts.append(Vector2(f2x(f), v2y((lay[f] as Vector3)[ax])))
		if pts.size() > 1:
			draw_polyline(pts, col, 2.0, true)
	# keys
	var bone := str(app.sel_bone)
	for k in app.doc.keys:
		var kd: Dictionary = k
		var f := int(kd["f"])
		var vals := _key_values(kd, bone, s["k"])
		for ax in 3:
			if not channels[ax]:
				continue
			var shown_f := f
			var shown_v: float = vals[ax]
			if _drag == "point" and int(_pt["f"]) == f and int(_pt["axis"]) == ax:
				shown_v = float(_pt["val"])
			var p := Vector2(f2x(shown_f), v2y(shown_v))
			var sel: bool = f in app.sel_keys
			draw_circle(p, 5.5 if sel else 4.5, Color.WHITE if sel else FSATheme.AXIS[ax])
			draw_arc(p, 5.5 if sel else 4.5, 0, TAU, 12, FSATheme.BG0, 1.0)
	# ruler + now
	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, RULER_H)), FSATheme.BG2)
	var step := 1
	for st in [1, 2, 5, 10, 20, 50]:
		if st * ppf >= 9.0:
			step = st
			break
	var fi := int(floor(x0 / step) * step)
	while f2x(fi) < size.x:
		if fi >= 0 and f2x(fi) >= LEFT_W and fi % (step * 5) == 0:
			draw_string(font, Vector2(f2x(fi) + 2, 13), str(fi), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, FSATheme.MUTED)
		fi += step
	var nx := f2x(float(app.frame))
	draw_line(Vector2(nx, 0), Vector2(nx, size.y), FSATheme.ACCENT, 2.0)
	var title := bone + ("  hips shift" if show_hips else "  rotation")
	draw_string(font, Vector2(LEFT_W + 6, RULER_H + 46), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, FSATheme.GOLD)
	draw_string(font, Vector2(LEFT_W + 6, RULER_H + 62), FSARig.hint(bone), HORIZONTAL_ALIGNMENT_LEFT, size.x - LEFT_W - 20, 11, FSATheme.MUTED)


func _key_values(kd: Dictionary, bone: String, k: float) -> Vector3:
	if show_hips:
		return Vector3(float(kd.get("hips_dx", 0.0)), float(kd.get("hips_dy", 0.0)), float(kd.get("hips_dz", 0.0))) * k
	var r: Array = (kd.get("rot", {}) as Dictionary).get(bone, [0.0, 0.0, 0.0])
	return Vector3(float(r[0]), float(r[1]), float(r[2])) * k


func _hit_point(p: Vector2) -> Dictionary:
	var s_k := 100.0 if show_hips else rad_to_deg(1.0)
	var best: Dictionary = {}
	var bd := 9.0
	for k in app.doc.keys:
		var kd: Dictionary = k
		var vals := _key_values(kd, str(app.sel_bone), s_k)
		for ax in 3:
			if not channels[ax]:
				continue
			var d := p.distance_to(Vector2(f2x(int(kd["f"])), v2y(vals[ax])))
			if d < bd:
				bd = d
				best = {"f": int(kd["f"]), "axis": ax, "start": vals[ax], "val": vals[ax], "k": s_k}
	return best


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventKey and (ev as InputEventKey).pressed and (ev as InputEventKey).keycode == KEY_F:
		fit()
		accept_event()
		return
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var up := mb.button_index == MOUSE_BUTTON_WHEEL_UP
			if mb.ctrl_pressed:
				var fm := x2f(mb.position.x)
				ppf = clampf(ppf * (1.15 if up else 1 / 1.15), 0.5, 200.0)
				x0 = fm - (mb.position.x - LEFT_W) / ppf
			else:
				var vm := y2v(mb.position.y)
				ppd = clampf(ppd * (1.15 if up else 1 / 1.15), 0.05, 80.0)
				v_mid += vm - y2v(mb.position.y)
			queue_redraw()
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_drag = "pan" if mb.pressed else ""
			accept_event()
			return
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			grab_focus()
			_press = mb.position
			if mb.position.y < RULER_H:
				_drag = "scrub"
				app.set_frame(clampf(round(x2f(mb.position.x)), 0.0, float(app.doc.frames)))
			else:
				_pt = _hit_point(mb.position)
				if not _pt.is_empty():
					app.select_keys([int(_pt["f"])], mb.shift_pressed)
					_drag = "point"
				else:
					_drag = "scrub"
					app.set_frame(clampf(round(x2f(mb.position.x)), 0.0, float(app.doc.frames)))
		else:
			if _drag == "point":
				var df := int(round((mb.position.x - _press.x) / ppf))
				var dv := float(_pt["val"]) - float(_pt["start"])
				if absf(dv) > 1e-5:
					var ax := int(_pt["axis"])
					if show_hips:
						app.set_key_hips(int(_pt["f"]), ["dx", "dy", "dz"][ax], float(_pt["val"]) / 100.0)
					else:
						app.set_key_channel(int(_pt["f"]), str(app.sel_bone), ax, deg_to_rad(float(_pt["val"])))
				elif df != 0:
					app.move_keys([int(_pt["f"])], df)
			_drag = ""
			queue_redraw()
		accept_event()
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		match _drag:
			"pan":
				x0 -= mm.relative.x / ppf
				v_mid += mm.relative.y / ppd
				queue_redraw()
			"scrub":
				app.set_frame(clampf(round(x2f(mm.position.x)), 0.0, float(app.doc.frames)))
			"point":
				if absf(mm.position.y - _press.y) > absf(mm.position.x - _press.x) or mm.shift_pressed:
					_pt["val"] = float(_pt["start"]) + (_press.y - mm.position.y) / ppd
				queue_redraw()
		accept_event()
