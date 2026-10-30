class_name FSAView
extends Control
## One 3D view into the stage. Renders through its own SubViewport at the real screen resolution (times the render scale, so
## HD / 4K stay sharp), and draws the animator overlays on top in 2D: bones, joints, the rotate rings / move arrows of the
## selected bone, IK handles on hands and feet, constraint targets, sockets, the motion trail.
##
## Mouse: left = pick a joint (Shift adds) and drag it (Rotate tool: swing it in the view; Move: slide the body; IK: pull the
## hand / foot and the limb follows); drag a ring = turn about that axis only; right-drag (or Alt + left) orbits, middle-drag
## (or Shift + right) pans, wheel zooms. Double-click a joint frames it.

signal maximize_requested(view: FSAView)

const PRESETS := ["Persp", "Front", "Three-Q", "Side L", "Side R", "Back", "Top", "Follow"]
const PRESET_ANGLES := {"Persp": [0.62, 0.16], "Front": [0.0, 0.04], "Three-Q": [0.7, 0.08], "Side L": [PI * 0.5, 0.04],
	"Side R": [-PI * 0.5, 0.04], "Back": [PI, 0.04], "Top": [0.0, 1.45], "Follow": [0.62, 0.16]}
const RING_MAX := 62.0
const PICK_PX := 13.0

var app: FSAApp
var vp := SubViewport.new()
var cam := Camera3D.new()
var tex := TextureRect.new()
var ov := Control.new()
var header := HBoxContainer.new()
var preset := "Persp"
var yaw := 0.62
var pitch := 0.16
var dist := 4.4
var target := Vector3(0, 0.9, 0)
var ortho := false
var render_scale := 1.0
var is_main := false
var ui_preset: OptionButton
var ui_ortho: Button

var _drag := ""              # "", orbit, pan, ring, view_ring, swing, move_axis, move_free, ik, maybe
var _press := Vector2.ZERO
var _last := Vector2.ZERO
var _axis := -1
var _axis_world := Vector3.ZERO
var _px_per_rad := 1.0
var _tangent := Vector2.RIGHT
var _bone := ""
var _plane_point := Vector3.ZERO
var _hover_axis := -1


## gizmo radius in pixels: smaller in small views so the rings never hide the body
func ring_px() -> float:
	return clampf(minf(size.x, size.y) * 0.16, 26.0, RING_MAX)


func setup(p_app: FSAApp, p_preset: String = "Persp", main: bool = false) -> FSAView:
	app = p_app
	is_main = main
	clip_contents = true
	focus_mode = Control.FOCUS_CLICK
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(160, 120)
	vp.world_3d = app.stage.world
	vp.own_world_3d = false
	vp.msaa_3d = Viewport.MSAA_4X
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	vp.positional_shadow_atlas_size = 1024
	add_child(vp)
	cam.fov = 34.0
	cam.near = 0.03
	cam.far = 400.0
	vp.add_child(cam)
	cam.current = true
	tex.texture = vp.get_texture()
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_SCALE
	tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tex)
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.draw.connect(_draw_overlay)
	add_child(ov)
	_build_header()
	resized.connect(_fit)
	set_preset(p_preset)
	return self


func _build_header() -> void:
	header.position = Vector2(6, 6)
	header.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(header)
	ui_preset = FSATheme.option(PRESETS, PRESETS.find(preset), func(i: int) -> void: set_preset(PRESETS[i]), "Camera for this view")
	ui_preset.add_theme_font_size_override("font_size", 12)
	header.add_child(ui_preset)
	ui_ortho = FSATheme.button("ORTHO", func(on: bool) -> void:
		ortho = on
		_cam(), "Flat (orthographic) projection: no perspective, measure poses against the grid", true)
	ui_ortho.add_theme_font_size_override("font_size", 11)
	header.add_child(ui_ortho)
	var mx := FSATheme.button("[ ]", func() -> void: maximize_requested.emit(self), "Maximize this view / back to the layout (also the ` key over a view)")
	mx.add_theme_font_size_override("font_size", 11)
	header.add_child(mx)


func set_preset(p: String) -> void:
	preset = p
	var a: Array = PRESET_ANGLES.get(p, [0.62, 0.16])
	yaw = float(a[0])
	pitch = float(a[1])
	if ui_preset != null:
		ui_preset.select(PRESETS.find(p))
	frame_body()


func frame_body() -> void:
	var h: float = app.stage.height if app != null else 1.8
	target = Vector3(0, h * 0.5, 0)
	dist = h * 2.45 if preset != "Top" else h * 3.0
	_cam()


func frame_point(p: Vector3, d: float = 1.2) -> void:
	target = p
	dist = d
	_cam()


func _fit() -> void:
	var s := get_window().content_scale_factor if get_window() != null else 1.0
	vp.size = Vector2i(maxi(16, int(size.x * s * render_scale)), maxi(16, int(size.y * s * render_scale)))
	ov.queue_redraw()


func _process(_dt: float) -> void:
	if preset == "Follow" and app != null and app.skel != null:
		var hi: int = app.skel.find_bone("hips")
		if hi >= 0:
			var hp: Vector3 = app.skel.global_transform * app.skel.get_bone_global_pose(hi).origin
			target = target.lerp(Vector3(hp.x, maxf(hp.y, 0.6), hp.z), 0.25)
			_cam()


func _cam() -> void:
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL if ortho else Camera3D.PROJECTION_PERSPECTIVE
	cam.size = dist * 0.62
	var pos := target + dir * (dist if not ortho else 30.0)
	var up := Vector3.UP if absf(pitch) < 1.4 else Vector3(-sin(yaw), 0, -cos(yaw))
	cam.transform = Transform3D(Basis.looking_at(target - pos, up), pos)   # works before the view is in the tree
	ov.queue_redraw()


# ---------------------------------------------------------------- coordinates

func _scale() -> Vector2:
	return Vector2(vp.size) / size if size.x > 0 and size.y > 0 else Vector2.ONE


func to_screen(p: Vector3) -> Vector2:
	return cam.unproject_position(p) / _scale()


func behind(p: Vector3) -> bool:
	return cam.is_position_behind(p)


func ray(local: Vector2) -> Array:
	var px := local * _scale()
	return [cam.project_ray_origin(px), cam.project_ray_normal(px)]


## world metres per screen pixel at a point
func world_per_px(p: Vector3) -> float:
	if ortho:
		return cam.size / maxf(size.y, 1.0)
	var d := (p - cam.global_position).dot(-cam.global_transform.basis.z)
	return 2.0 * maxf(d, 0.05) * tan(deg_to_rad(cam.fov) * 0.5) / maxf(size.y, 1.0)


func _plane_hit(local: Vector2, point: Vector3) -> Vector3:
	var r := ray(local)
	var n := -cam.global_transform.basis.z
	var o: Vector3 = r[0]
	var d: Vector3 = r[1]
	var den := n.dot(d)
	if absf(den) < 1e-6:
		return point
	return o + d * (n.dot(point - o) / den)


# ---------------------------------------------------------------- input

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.pressed:
			grab_focus()
			app.focus_view(self)
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			dist = maxf(0.25, dist * 0.9)
			_cam()
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			dist = minf(60.0, dist * 1.1)
			_cam()
			accept_event()
			return
		if mb.pressed:
			_press = mb.position
			_last = mb.position
			if mb.button_index == MOUSE_BUTTON_RIGHT:
				_drag = "pan" if mb.shift_pressed else "orbit"
			elif mb.button_index == MOUSE_BUTTON_MIDDLE:
				_drag = "pan"
			elif mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.alt_pressed:
					_drag = "orbit"
				elif mb.double_click:
					var b := _pick_bone(mb.position)
					if b != "":
						frame_point(app.joint_world(b), 1.1)
					_drag = ""
				else:
					_left_press(mb)
			accept_event()
		else:
			if _drag in ["ring", "view_ring", "swing", "move_axis", "move_free", "ik"]:
				app.drag_end()
			_drag = ""
			_axis = -1
			ov.queue_redraw()
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		var d := mm.position - _last
		_last = mm.position
		match _drag:
			"orbit":
				yaw -= d.x * 0.008
				pitch = clampf(pitch + d.y * 0.008, -1.45, 1.52)
				if preset != "Persp" and preset != "Follow":
					preset = "Persp"
					ui_preset.select(0)
				_cam()
			"pan":
				var k := world_per_px(target)
				target += (-cam.global_transform.basis.x * d.x + cam.global_transform.basis.y * d.y) * k
				_cam()
			"maybe":
				if mm.position.distance_to(_press) > 4.0:
					_start_tool_drag()
			"ring":
				var ang := (mm.position - _press).dot(_tangent) / maxf(_px_per_rad, 1e-3)
				app.drag_rotate(_bone, _axis_world, ang)
			"view_ring", "swing":
				var c := to_screen(app.joint_world(_bone))
				var a0 := (_press - c).angle()
				var a1 := (mm.position - c).angle()
				var fwd := -cam.global_transform.basis.z
				app.drag_rotate(_bone, -fwd, -wrapf(a1 - a0, -PI, PI))
			"move_axis":
				var s := (mm.position - _press).dot(_tangent) / maxf(_px_per_rad, 1e-3)
				app.drag_move(_axis_world * s)
			"move_free":
				app.drag_move(_plane_hit(mm.position, _plane_point) - _plane_hit(_press, _plane_point))
			"ik":
				app.drag_ik(_bone, _plane_hit(mm.position, _plane_point))
			"":
				var h := _hit_gizmo(mm.position)
				if h != _hover_axis:
					_hover_axis = h
					ov.queue_redraw()
		accept_event()


func _left_press(mb: InputEventMouseButton) -> void:
	var sel: String = app.sel_bone
	if sel != "" and app.tool in ["rotate", "move"]:
		var h := _hit_gizmo(mb.position)
		if h >= 0:
			_begin_gizmo(h, sel, mb.position)
			return
	var b := _pick_bone(mb.position)
	if b == "":
		_drag = ""
		return
	app.select_bone(b, mb.shift_pressed)
	_bone = b
	_drag = "maybe" if app.tool != "select" else ""


func _start_tool_drag() -> void:
	if app.is_bone_locked(_bone):
		app.say("%s is locked (Rig > Unlock, or the lock in the Outliner)." % _bone, "warn")
		_drag = ""
		return
	_plane_point = app.joint_world(_bone)
	match str(app.tool):
		"rotate":
			_drag = "swing"
			_press = _last
			app.drag_begin("Turn " + _bone)
		"move":
			_drag = "move_free"
			_press = _last
			app.drag_begin("Move body")
		"ik":
			_drag = "ik"
			app.drag_begin("IK " + _bone)
		_:
			_drag = ""


func _begin_gizmo(h: int, bone: String, at: Vector2) -> void:
	_bone = bone
	_press = at
	var c: Vector3 = app.joint_world(bone)
	if app.tool == "move":
		_axis_world = [Vector3.RIGHT, Vector3.UP, Vector3.BACK][h]
		var tip := to_screen(c + _axis_world * ring_px() * world_per_px(c))
		var base := to_screen(c)
		_tangent = (tip - base).normalized()
		_px_per_rad = (tip - base).length() / (ring_px() * world_per_px(c))
		_drag = "move_axis"
		_axis = h
		app.drag_begin("Move body")
		return
	if h == 3:
		_drag = "view_ring"
		_axis = 3
		app.drag_begin("Turn " + bone)
		return
	_axis_world = gizmo_axis(bone, h)
	var r := ring_px() * world_per_px(c)
	var basis := _ring_basis(_axis_world)
	var best_t := 0.0
	var bd := INF
	for i in 64:
		var t := TAU * i / 64.0
		var sp := to_screen(c + (basis[0] * cos(t) + basis[1] * sin(t)) * r)
		var dd := sp.distance_to(at)
		if dd < bd:
			bd = dd
			best_t = t
	var eps := 0.02
	var p0 := to_screen(c + (basis[0] * cos(best_t) + basis[1] * sin(best_t)) * r)
	var p1 := to_screen(c + (basis[0] * cos(best_t + eps) + basis[1] * sin(best_t + eps)) * r)
	var tv := (p1 - p0) / eps
	_px_per_rad = maxf(tv.length(), 8.0)
	_tangent = tv.normalized()
	_drag = "ring"
	_axis = h
	app.drag_begin("Turn %s %s" % [bone, ["X", "Y", "Z"][h]])


## the world direction of the gizmo's axis h for a bone (the bone's own axes, or the world's when Global is on)
func gizmo_axis(bone: String, h: int) -> Vector3:
	if app.space_global or app.skel == null:
		return [Vector3.RIGHT, Vector3.UP, Vector3.BACK][h]
	var bi: int = app.skel.find_bone(bone)
	var bb: Basis = (app.skel.global_transform.basis * app.skel.get_bone_global_pose(bi).basis).orthonormalized()
	return [bb.x, bb.y, bb.z][h].normalized()


static func _ring_basis(a: Vector3) -> Array:
	var u := a.cross(Vector3.UP)
	if u.length() < 0.1:
		u = a.cross(Vector3.RIGHT)
	u = u.normalized()
	return [u, a.cross(u).normalized()]


## which gizmo part is under the mouse: 0..2 an axis ring / arrow, 3 the view ring, -1 none
func _hit_gizmo(p: Vector2) -> int:
	var sel: String = app.sel_bone
	if sel == "" or app.skel == null or not (app.tool in ["rotate", "move"]):
		return -1
	if app.tool == "move" and sel != "hips" and not app.move_any:
		return -1
	var c: Vector3 = app.joint_world(sel)
	if behind(c):
		return -1
	var cs := to_screen(c)
	var r := ring_px() * world_per_px(c)
	if app.tool == "move":
		for h in 3:
			var tip := to_screen(c + [Vector3.RIGHT, Vector3.UP, Vector3.BACK][h] * r)
			if Geometry2D.get_closest_point_to_segment(p, cs, tip).distance_to(p) < 9.0:
				return h
		return -1
	var best := -1
	var bd := 8.0
	for h in 3:
		var a := gizmo_axis(sel, h)
		var bs := _ring_basis(a)
		var prev := Vector2.ZERO
		for i in 49:
			var t := TAU * i / 48.0
			var sp := to_screen(c + (bs[0] * cos(t) + bs[1] * sin(t)) * r)
			if i > 0:
				var d := Geometry2D.get_closest_point_to_segment(p, prev, sp).distance_to(p)
				if d < bd:
					bd = d
					best = h
			prev = sp
	if best >= 0:
		return best
	if absf(p.distance_to(cs) - ring_px() * 1.22) < 7.0:
		return 3
	return -1


## the joint under the mouse (joints first, then along bone segments)
func _pick_bone(p: Vector2) -> String:
	var od: Dictionary = app.overlay
	var best := ""
	var bd := PICK_PX
	for j in (od.get("joints", []) as Array):
		var jd: Dictionary = j
		if not bool(jd.get("shown", true)) or behind(jd["pos"]):
			continue
		var d := p.distance_to(to_screen(jd["pos"]))
		if d < bd:
			bd = d
			best = str(jd["bone"])
	if best != "":
		return best
	bd = PICK_PX * 0.7
	for j in (od.get("joints", []) as Array):
		var jd: Dictionary = j
		if not bool(jd.get("shown", true)) or behind(jd["pos"]) or behind(jd["tip"]):
			continue
		var d := Geometry2D.get_closest_point_to_segment(p, to_screen(jd["pos"]), to_screen(jd["tip"])).distance_to(p)
		if d < bd:
			bd = d
			best = str(jd["bone"])
	return best


# ---------------------------------------------------------------- overlay

func _draw_overlay() -> void:
	if app == null or app.skel == null:
		return
	var od: Dictionary = app.overlay
	var show: Dictionary = app.show
	var font := ThemeDB.fallback_font
	# motion trail of the selected bone
	if bool(show.get("trail", true)):
		var tr: Array = od.get("trail", [])
		var prev := Vector2.INF
		for i in tr.size():
			var pt: Vector3 = tr[i]
			if behind(pt):
				prev = Vector2.INF
				continue
			var sp := to_screen(pt)
			if prev != Vector2.INF:
				ov.draw_line(prev, sp, Color(FSATheme.GOLD, 0.55), 1.5, true)
			prev = sp
		for kf in (od.get("trail_keys", []) as Array):
			if int(kf) < tr.size() and not behind(tr[int(kf)]):
				ov.draw_circle(to_screen(tr[int(kf)]), 3.5, FSATheme.GOLD)
		var cf := int(od.get("trail_now", -1))
		if cf >= 0 and cf < tr.size() and not behind(tr[cf]):
			ov.draw_arc(to_screen(tr[cf]), 6.0, 0, TAU, 16, Color.WHITE, 1.5, true)
	# bones
	if bool(show.get("bones", true)):
		for j in (od.get("joints", []) as Array):
			var jd: Dictionary = j
			if not bool(jd.get("shown", true)) or behind(jd["pos"]):
				continue
			var a := to_screen(jd["pos"])
			var b := to_screen(jd["tip"]) if not behind(jd["tip"]) else a
			var col: Color = jd["color"]
			var w := 2.0
			if bool(jd.get("sel", false)):
				col = Color.WHITE
				w = 3.0
			ov.draw_line(a, b, Color(0, 0, 0, 0.55), w + 2.0, true)
			ov.draw_line(a, b, col, w, true)
		for j in (od.get("joints", []) as Array):
			var jd: Dictionary = j
			if not bool(jd.get("shown", true)) or behind(jd["pos"]):
				continue
			var a := to_screen(jd["pos"])
			var r := 5.5 if bool(jd.get("sel", false)) else 3.8
			ov.draw_circle(a, r + 1.5, Color(0, 0, 0, 0.6))
			ov.draw_circle(a, r, Color.WHITE if bool(jd.get("sel", false)) else (jd["color"] as Color))
			if bool(jd.get("locked", false)):
				ov.draw_rect(Rect2(a + Vector2(5, -10), Vector2(7, 6)), FSATheme.MUTED)
				ov.draw_arc(a + Vector2(8.5, -10), 2.6, PI, TAU, 8, FSATheme.MUTED, 1.4)
			if bool(jd.get("ik", false)):
				ov.draw_rect(Rect2(a - Vector2(8, 8), Vector2(16, 16)), FSATheme.PURPLE, false, 1.6)
			if bool(jd.get("sel", false)) and bool(show.get("labels", true)):
				ov.draw_string(font, a + Vector2(9, -8), str(jd["bone"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
	# IK handles on hands and feet when the IK tool is on
	if app.tool == "ik":
		for j in (od.get("joints", []) as Array):
			var jd: Dictionary = j
			if FSARig.limb_of_end(str(jd["bone"])) != "" and not behind(jd["pos"]):
				var a := to_screen(jd["pos"])
				ov.draw_rect(Rect2(a - Vector2(9, 9), Vector2(18, 18)), FSATheme.ACCENT, false, 2.0)
	# constraint targets
	for t in (od.get("targets", []) as Array):
		var td: Dictionary = t
		if behind(td["pos"]):
			continue
		var a := to_screen(td["pos"])
		var c: Color = td.get("color", FSATheme.PURPLE)
		ov.draw_line(a - Vector2(9, 0), a + Vector2(9, 0), c, 2.0)
		ov.draw_line(a - Vector2(0, 9), a + Vector2(0, 9), c, 2.0)
		ov.draw_arc(a, 6.0, 0, TAU, 16, c, 1.5, true)
		ov.draw_string(font, a + Vector2(9, 14), str(td.get("label", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, c)
	# sockets
	if bool(show.get("sockets", false)):
		for s in (od.get("sockets", []) as Array):
			var sd: Dictionary = s
			if behind(sd["pos"]):
				continue
			var a := to_screen(sd["pos"])
			var col := Color(1.0, 0.3, 0.9) if str(sd["name"]) != str(app.sel_socket) else Color.WHITE
			ov.draw_colored_polygon(PackedVector2Array([a + Vector2(0, -5), a + Vector2(5, 0), a + Vector2(0, 5), a + Vector2(-5, 0)]), col)
			ov.draw_string(font, a + Vector2(7, 4), str(sd["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(col, 0.85))
	_draw_gizmo()
	_draw_axes_corner()
	# view label + frame
	var info := "%s   f %d / %d" % [preset.to_upper(), int(round(float(app.frame))), int(app.doc.frames)]
	var iw := font.get_string_size(info, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	ov.draw_rect(Rect2(Vector2(6, size.y - 24), Vector2(iw + 10, 18)), Color(0.05, 0.04, 0.06, 0.7))
	ov.draw_string(font, Vector2(11, size.y - 10), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.85))
	if app.agent_flash > 0.0:
		ov.draw_rect(Rect2(Vector2.ZERO, size), Color(FSATheme.PURPLE, app.agent_flash * 0.8), false, 3.0)
		ov.draw_string(font, Vector2(size.x - 150, size.y - 10), "AGENT EDITING", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, FSATheme.PURPLE)


func _draw_gizmo() -> void:
	var sel: String = app.sel_bone
	if sel == "" or not (app.tool in ["rotate", "move"]):
		return
	if app.tool == "move" and sel != "hips" and not app.move_any:
		return
	var c: Vector3 = app.joint_world(sel)
	if behind(c):
		return
	var cs := to_screen(c)
	var r := ring_px() * world_per_px(c)
	if app.tool == "move":
		for h in 3:
			var col: Color = FSATheme.AXIS[h]
			if h == _axis or h == _hover_axis:
				col = Color.WHITE
			var tip := to_screen(c + [Vector3.RIGHT, Vector3.UP, Vector3.BACK][h] * r)
			ov.draw_line(cs, tip, col, 2.5, true)
			var dirv := (tip - cs).normalized()
			var n := Vector2(-dirv.y, dirv.x)
			ov.draw_colored_polygon(PackedVector2Array([tip + dirv * 10, tip + n * 5, tip - n * 5]), col)
		ov.draw_rect(Rect2(cs - Vector2(5, 5), Vector2(10, 10)), Color(1, 1, 1, 0.8), false, 1.5)
		return
	var campos := cam.global_position
	for h in 3:
		var a := gizmo_axis(sel, h)
		var bs := _ring_basis(a)
		var col: Color = FSATheme.AXIS[h]
		if h == _axis or h == _hover_axis:
			col = Color.WHITE
		var prev := Vector2.ZERO
		var prev_front := true
		for i in 49:
			var t := TAU * i / 48.0
			var wp: Vector3 = c + (bs[0] * cos(t) + bs[1] * sin(t)) * r
			var sp := to_screen(wp)
			var front: bool = (wp - c).dot(campos - c) >= -0.0001
			if i > 0:
				ov.draw_line(prev, sp, col if (front and prev_front) else Color(col, 0.28), 2.2 if front else 1.2, true)
			prev = sp
			prev_front = front
	var vcol := Color(1, 1, 1, 0.9) if (_axis == 3 or _hover_axis == 3) else Color(1, 1, 1, 0.35)
	ov.draw_arc(cs, ring_px() * 1.22, 0, TAU, 64, vcol, 1.5, true)


func _draw_axes_corner() -> void:
	var o := Vector2(size.x - 34, 40)
	var b := cam.global_transform.basis
	var names := ["X", "Y", "Z"]
	var font := ThemeDB.fallback_font
	for h in 3:
		var w: Vector3 = [Vector3.RIGHT, Vector3.UP, Vector3.BACK][h]
		var v := Vector2(w.dot(b.x), -w.dot(b.y)) * 20.0
		ov.draw_line(o, o + v, FSATheme.AXIS[h], 2.0, true)
		ov.draw_string(font, o + v * 1.25 + Vector2(-4, 4), names[h], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, FSATheme.AXIS[h])


func redraw() -> void:
	ov.queue_redraw()


## save what this view shows at a chosen resolution (HD / 4K) without changing the window
func render_png(w: int, h: int, path: String) -> Error:
	var off := SubViewport.new()
	off.size = Vector2i(w, h)
	off.world_3d = vp.world_3d
	off.msaa_3d = Viewport.MSAA_8X
	off.render_target_update_mode = SubViewport.UPDATE_ONCE
	var c2 := Camera3D.new()
	c2.fov = cam.fov
	c2.projection = cam.projection
	c2.size = cam.size
	c2.near = cam.near
	c2.far = cam.far
	off.add_child(c2)
	add_child(off)
	c2.global_transform = cam.global_transform
	c2.current = true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := off.get_texture().get_image()
	off.queue_free()
	return img.save_png(path)
