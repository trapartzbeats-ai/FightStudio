class_name FSAStrip
extends Control
## The review sheet as a live canvas (the look of game/tools/clip_views): rows = camera angles (front, three-quarter, side,
## back), columns = moments of the clip. Every cell is a real 3D render of the final pose (layers + constraints), refreshed when
## the clip changes, so you see the whole motion from four sides while you edit. Click a cell to jump to that frame.
##
## Each column is its own little world (its own body, light and floor), shared by that column's four cameras.

const ANGLES := [["front", 0.0], ["three_q", 40.0], ["side", 90.0], ["back", 180.0]]
const LABEL_W := 70.0
const TOP_H := 40.0

var app: FSAApp
var cols := 8
var around_now := false        # columns centred on the current frame instead of spread over the clip
var cells: Array = []          # [col] -> {world, model, skel, vps: [SubViewport x4], cams: [...], frame}
var _dirty := true
var _cell_size := Vector2.ZERO
var _fighter := ""
var _tex_layer := Control.new()
var _hover := Vector2i(-1, -1)


func setup(p_app: FSAApp, p_cols: int = 8) -> FSAStrip:
	app = p_app
	cols = p_cols
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tex_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tex_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tex_layer)
	resized.connect(func() -> void: _dirty = true)
	return self


func mark_dirty() -> void:
	_dirty = true


func _build() -> void:
	for c in cells:
		for vp in (c["vps"] as Array):
			(vp as SubViewport).queue_free()
	cells.clear()
	for ch in _tex_layer.get_children():
		ch.queue_free()
	_fighter = str(app.fighter)
	for ci in cols:
		var world := World3D.new()
		var env := Environment.new()
		FSAStage.build_env(env)
		world.environment = env
		var vps: Array = []
		var cams: Array = []
		var model: Node3D = null
		var skel: Skeleton3D = null
		for ri in ANGLES.size():
			var vp := SubViewport.new()
			vp.world_3d = world
			vp.own_world_3d = false
			vp.msaa_3d = Viewport.MSAA_4X
			vp.render_target_update_mode = SubViewport.UPDATE_ONCE
			add_child(vp)
			if ri == 0:
				var sun := DirectionalLight3D.new()
				sun.rotation_degrees = Vector3(-50, -35, 0)
				sun.shadow_enabled = true
				sun.light_energy = 1.15
				vp.add_child(sun)
				var fl := MeshInstance3D.new()
				fl.mesh = FSAStage.floor_mesh()
				fl.material_override = FSAStage.floor_material()
				vp.add_child(fl)
				model = FSAStage.instance_fighter(_fighter)
				if model != null:
					vp.add_child(model)
					skel = FSAStage.skeleton_of(model)
			var cam := Camera3D.new()
			cam.fov = 34.0
			vp.add_child(cam)
			cam.current = true
			vps.append(vp)
			cams.append(cam)
			var tr := TextureRect.new()
			tr.texture = vp.get_texture()
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_SCALE
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_tex_layer.add_child(tr)
			tr.set_meta("cell", Vector2i(ci, ri))
		cells.append({"world": world, "model": model, "skel": skel, "vps": vps, "cams": cams, "frame": 0.0})


func _process(_dt: float) -> void:
	if app == null or not is_visible_in_tree():
		return
	if cells.size() != cols or str(app.fighter) != _fighter:
		_build()
		_dirty = true
	if _dirty:
		_dirty = false
		_refresh()


func sample_frames() -> Array:
	var n := float(app.doc.frames)
	var out: Array = []
	if around_now:
		var step := maxf(1.0, round(n / float(cols * 2)))
		var start := float(app.frame) - step * floorf(cols / 2.0)
		for i in cols:
			out.append(clampf(start + step * i, 0.0, n))
	else:
		for i in cols:
			out.append(n * float(i) / float(cols))
	return out


func _layout() -> void:
	var w := maxf(32.0, (size.x - LABEL_W) / float(cols))
	var h := maxf(32.0, (size.y - TOP_H) / float(ANGLES.size()))
	_cell_size = Vector2(w, h)
	var s := get_window().content_scale_factor if get_window() != null else 1.0
	for tr in _tex_layer.get_children():
		var c: Vector2i = tr.get_meta("cell")
		(tr as TextureRect).position = Vector2(LABEL_W + c.x * w, TOP_H + c.y * h)
		(tr as TextureRect).size = Vector2(w - 2, h - 2)
	for col in cells:
		for vp in (col["vps"] as Array):
			(vp as SubViewport).size = Vector2i(maxi(16, int((w - 2) * s)), maxi(16, int((h - 2) * s)))


func _refresh() -> void:
	_layout()
	var fs := sample_frames()
	for ci in cells.size():
		var col: Dictionary = cells[ci]
		var sk: Skeleton3D = col["skel"]
		if sk == null:
			continue
		var f := float(fs[ci])
		col["frame"] = f
		var pose: Dictionary = app.final_pose_on(sk, f)
		var body_c := Vector3(0, 0.85 * float(app.stage.height) / 1.8, 0)
		var hi := sk.find_bone("hips")
		if hi >= 0 and bool(app.strip_follow):
			var hp := sk.global_transform * sk.get_bone_global_pose(hi).origin
			body_c.x = hp.x
			body_c.z = hp.z
		var d := 4.4 * float(app.stage.height) / 1.8
		for ri in ANGLES.size():
			var cam: Camera3D = (col["cams"] as Array)[ri]
			var yaw := deg_to_rad(float(ANGLES[ri][1]))
			cam.global_position = body_c + Vector3(sin(yaw), 0.12, cos(yaw)) * d
			cam.look_at(body_c, Vector3.UP)
			((col["vps"] as Array)[ri] as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE
		if pose.is_empty():
			pass
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("0d0b0f"))
	if app == null:
		return
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(6, 16), "%s  %s" % [app.fighter, app.doc.name], HORIZONTAL_ALIGNMENT_LEFT, size.x - 12, 13, Color(1.0, 0.79, 0.24))
	for ri in ANGLES.size():
		draw_string(font, Vector2(4, TOP_H + ri * _cell_size.y + _cell_size.y * 0.5), str(ANGLES[ri][0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.96, 0.94, 0.9))
	var now := float(app.frame)
	for ci in cells.size():
		var f := float((cells[ci] as Dictionary)["frame"])
		var x := LABEL_W + ci * _cell_size.x
		var is_key: bool = app.doc.has_key(int(round(f))) and absf(f - round(f)) < 0.01
		var col := Color(1.0, 0.79, 0.24) if is_key else Color(0.7, 0.66, 0.75)
		draw_string(font, Vector2(x + 4, 34), "f %d%s" % [int(round(f)), "  KEY" if is_key else ""], HORIZONTAL_ALIGNMENT_LEFT, _cell_size.x - 6, 12, col)
		if absf(f - now) < 0.5:
			draw_rect(Rect2(Vector2(x, TOP_H - 2), Vector2(_cell_size.x - 2, _cell_size.y * ANGLES.size() + 2)), Color(1.0, 0.48, 0.1), false, 2.0)
	if _hover.x >= 0:
		draw_rect(Rect2(Vector2(LABEL_W + _hover.x * _cell_size.x, TOP_H + _hover.y * _cell_size.y), _cell_size - Vector2(2, 2)), Color(1, 1, 1, 0.5), false, 1.0)


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var c := _cell_at((ev as InputEventMouseMotion).position)
		if c != _hover:
			_hover = c
			queue_redraw()
	elif ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var c := _cell_at((ev as InputEventMouseButton).position)
		if c.x >= 0 and c.x < cells.size():
			app.set_frame(float((cells[c.x] as Dictionary)["frame"]))
		accept_event()


func _cell_at(p: Vector2) -> Vector2i:
	if _cell_size.x <= 0.0 or p.x < LABEL_W or p.y < TOP_H:
		return Vector2i(-1, -1)
	var c := Vector2i(int((p.x - LABEL_W) / _cell_size.x), int((p.y - TOP_H) / _cell_size.y))
	if c.x >= cols or c.y >= ANGLES.size():
		return Vector2i(-1, -1)
	return c
