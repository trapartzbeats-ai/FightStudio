class_name FSADock
extends RefCounted
## Panels live in tab docks (left, right top, right bottom, bottom). Drag a tab onto another dock to move it. Right-click a tab
## (or use the Window menu) to float the panel into its own OS window - put the dope sheet on a second monitor - and close that
## window to dock it back where it was. The arrangement is saved per user (user://fight_studio_layout.json).

const LAYOUT_FILE := "user://fight_studio_layout.json"

var app: Control
var docks: Dictionary = {}      # dock name -> TabContainer
var panels: Dictionary = {}     # title -> Control
var home: Dictionary = {}       # title -> dock it returns to
var windows: Dictionary = {}    # title -> Window
var _menu := PopupMenu.new()
var _menu_title := ""


func _init(p_app: Control) -> void:
	app = p_app
	app.add_child(_menu)
	_menu.id_pressed.connect(_on_menu)


func make_dock(dock_name: String) -> TabContainer:
	var tc := TabContainer.new()
	tc.name = dock_name
	tc.drag_to_rearrange_enabled = true
	tc.tabs_rearrange_group = 7
	tc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tc.set_meta("dock", dock_name)
	tc.clip_contents = true
	var bar := tc.get_tab_bar()
	bar.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
			var idx := bar.get_tab_idx_at_point((ev as InputEventMouseButton).position)
			if idx >= 0:
				_open_menu(str(tc.get_tab_control(idx).name), app.get_global_mouse_position()))
	docks[dock_name] = tc
	return tc


func add_panel(title: String, ctl: Control, dock_name: String) -> void:
	ctl.name = title
	ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	(docks[dock_name] as TabContainer).add_child(ctl)
	panels[title] = ctl
	home[title] = dock_name


func dock_of(title: String) -> String:
	if windows.has(title):
		return "float"
	var ctl: Control = panels.get(title)
	if ctl == null or ctl.get_parent() == null:
		return ""
	return str(ctl.get_parent().get_meta("dock", ""))


func _open_menu(title: String, at: Vector2) -> void:
	_menu_title = title
	_menu.clear()
	_menu.add_item("Float \"%s\" in its own window" % title, 1)
	_menu.add_separator("Move to")
	var i := 10
	for d in docks:
		_menu.add_item(str(d), i)
		_menu.set_item_metadata(_menu.get_item_index(i), str(d))
		i += 1
	_menu.add_separator()
	_menu.add_item("Hide (Window menu brings it back)", 2)
	_menu.popup(Rect2i(DisplayServer.mouse_get_position(), Vector2i.ZERO))


func _on_menu(id: int) -> void:
	if id == 1:
		float_panel(_menu_title)
	elif id == 2:
		hide_panel(_menu_title)
	elif id >= 10:
		move_panel(_menu_title, str(_menu.get_item_metadata(_menu.get_item_index(id))))


func move_panel(title: String, dock_name: String) -> void:
	var ctl: Control = panels.get(title)
	if ctl == null or not docks.has(dock_name):
		return
	if windows.has(title):
		var w: Window = windows[title]
		windows.erase(title)
		ctl.get_parent().remove_child(ctl)
		w.queue_free()
	elif ctl.get_parent() != null:
		ctl.get_parent().remove_child(ctl)
	var tc: TabContainer = docks[dock_name]
	tc.add_child(ctl)
	home[title] = dock_name
	tc.current_tab = tc.get_tab_idx_from_control(ctl)
	tc.set_tab_hidden(tc.current_tab, false)


func float_panel(title: String, rect: Rect2i = Rect2i()) -> void:
	var ctl: Control = panels.get(title)
	if ctl == null or windows.has(title):
		return
	var from := dock_of(title)
	if from != "":
		home[title] = from
	var w := Window.new()
	w.title = "Fight Studio - " + title
	w.theme = FSATheme.theme()
	w.wrap_controls = false
	w.min_size = Vector2i(320, 240)
	var sz := Vector2i(maxi(420, int(ctl.size.x)), maxi(360, int(ctl.size.y)))
	w.size = rect.size if rect.size.x > 0 else sz
	w.position = rect.position if rect.size.x > 0 else DisplayServer.mouse_get_position() - Vector2i(40, 20)
	var bg := PanelContainer.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_theme_stylebox_override("panel", FSATheme._box(FSATheme.BG1, 0, 0))
	w.add_child(bg)
	ctl.get_parent().remove_child(ctl)
	bg.add_child(ctl)
	ctl.visible = true
	w.close_requested.connect(func() -> void: move_panel(title, str(home.get(title, "right_top"))))
	app.add_child(w)
	windows[title] = w
	w.show()


func hide_panel(title: String) -> void:
	var ctl: Control = panels.get(title)
	if ctl == null:
		return
	if windows.has(title):
		move_panel(title, str(home.get(title, "right_top")))
	var tc := ctl.get_parent() as TabContainer
	if tc != null:
		tc.set_tab_hidden(tc.get_tab_idx_from_control(ctl), true)


func show_panel(title: String) -> void:
	var ctl: Control = panels.get(title)
	if ctl == null:
		return
	if windows.has(title):
		(windows[title] as Window).grab_focus()
		return
	var tc := ctl.get_parent() as TabContainer
	if tc != null:
		var idx := tc.get_tab_idx_from_control(ctl)
		tc.set_tab_hidden(idx, false)
		tc.current_tab = idx


func is_shown(title: String) -> bool:
	if windows.has(title):
		return true
	var ctl: Control = panels.get(title)
	var tc := ctl.get_parent() as TabContainer if ctl != null else null
	return tc != null and not tc.is_tab_hidden(tc.get_tab_idx_from_control(ctl))


func state() -> Dictionary:
	var out := {"panels": {}}
	for t in panels:
		var e := {"dock": dock_of(str(t)), "home": str(home.get(t, "")), "shown": is_shown(str(t))}
		if windows.has(t):
			var w: Window = windows[t]
			e["rect"] = [w.position.x, w.position.y, w.size.x, w.size.y]
		(out["panels"] as Dictionary)[t] = e
	return out


func apply(d: Dictionary) -> void:
	var ps: Dictionary = d.get("panels", {})
	for t in ps:
		if not panels.has(t):
			continue
		var e: Dictionary = ps[t]
		var dk := str(e.get("dock", ""))
		if dk == "float":
			var r: Array = e.get("rect", [])
			var rect := Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3])) if r.size() == 4 else Rect2i()
			home[t] = str(e.get("home", home.get(t, "right_top")))
			if docks.has(home[t]) and dock_of(str(t)) != home[t]:
				move_panel(str(t), str(home[t]))
			float_panel(str(t), rect)
		elif docks.has(dk) and dk != dock_of(str(t)):
			move_panel(str(t), dk)
		if not bool(e.get("shown", true)):
			hide_panel(str(t))


func save() -> void:
	var f := FileAccess.open(LAYOUT_FILE, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(state(), "  "))
		f.close()


func load_saved() -> void:
	var f := FileAccess.open(LAYOUT_FILE, FileAccess.READ)
	if f == null:
		return
	var p: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(p) == TYPE_DICTIONARY:
		apply(p)
