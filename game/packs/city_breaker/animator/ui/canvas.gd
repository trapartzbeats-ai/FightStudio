class_name FSACanvas
extends PanelContainer
## The canvas: the views in a layout. "1" one big view, "2" side by side, "3" one big + two, "4" quad (front, side, three-quarter,
## free), "strip" the four-angle film strip of the whole clip, "4+strip" quad over a strip. Any view can be maximized and back.
## A canvas can also live in its own window (Window > New canvas window) for a second monitor.

const LAYOUTS := ["1", "2", "3", "4", "strip", "4+strip"]
const DEFAULT_PRESETS := {"1": ["Persp"], "2": ["Front", "Side L"], "3": ["Persp", "Front", "Side L"], "4": ["Front", "Side L", "Three-Q", "Persp"],
	"strip": [], "4+strip": ["Front", "Side L", "Three-Q", "Persp"]}

var app: FSAApp
var layout := "4"
var views: Array = []
var strip: FSAStrip
var maximized: FSAView
var _root: Control
var _presets: Dictionary = {}     # layout -> presets the user picked


func setup(p_app: FSAApp, p_layout: String = "4") -> FSACanvas:
	app = p_app
	add_theme_stylebox_override("panel", FSATheme._box(Color("0d0b0f"), 0, 0))
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	set_layout(p_layout)
	return self


func set_layout(l: String) -> void:
	if not (l in LAYOUTS):
		l = "4"
	_remember()
	layout = l
	maximized = null
	_rebuild()


func _remember() -> void:
	var ps: Array = []
	for v in views:
		ps.append((v as FSAView).preset)
	if not ps.is_empty():
		_presets[layout] = ps


func _rebuild() -> void:
	if _root != null:
		_root.queue_free()
	views.clear()
	strip = null
	var presets: Array = _presets.get(layout, DEFAULT_PRESETS[layout])
	match layout:
		"1":
			_root = _view(presets, 0)
		"2":
			var h := HSplitContainer.new()
			h.add_child(_view(presets, 0))
			h.add_child(_view(presets, 1))
			_root = h
		"3":
			var h := HSplitContainer.new()
			h.add_child(_view(presets, 0))
			var v := VSplitContainer.new()
			v.add_child(_view(presets, 1))
			v.add_child(_view(presets, 2))
			v.custom_minimum_size.x = 300
			h.add_child(v)
			h.split_offset = 260
			_root = h
		"4":
			_root = _quad(presets)
		"strip":
			strip = FSAStrip.new().setup(app, int(app.strip_cols))
			_root = strip
		"4+strip":
			var v2 := VSplitContainer.new()
			v2.add_child(_quad(presets))
			strip = FSAStrip.new().setup(app, int(app.strip_cols))
			strip.custom_minimum_size.y = 220
			v2.add_child(strip)
			v2.split_offset = 160
			_root = v2
	_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_root)
	if not views.is_empty():
		app.focus_view(views[views.size() - 1] if layout == "4" or layout == "4+strip" else views[0])


func _quad(presets: Array) -> Control:
	var v := VSplitContainer.new()
	var top := HSplitContainer.new()
	top.add_child(_view(presets, 0))
	top.add_child(_view(presets, 1))
	var bot := HSplitContainer.new()
	bot.add_child(_view(presets, 2))
	bot.add_child(_view(presets, 3))
	v.add_child(top)
	v.add_child(bot)
	return v


func _view(presets: Array, i: int) -> FSAView:
	var p := str(presets[i]) if i < presets.size() else "Persp"
	var v := FSAView.new().setup(app, p, views.is_empty())
	v.render_scale = float(app.render_scale)
	v.maximize_requested.connect(_toggle_max)
	views.append(v)
	return v


func _toggle_max(v: FSAView) -> void:
	if maximized != null:
		maximized = null
		for vv in views:
			(vv as FSAView).visible = true
		if strip != null:
			strip.visible = true
		_unhide(_root)
		return
	maximized = v
	if strip != null:
		strip.visible = false
	for vv in views:
		(vv as FSAView).visible = vv == v
	_hide_empty(_root)


## hide split containers whose children are all hidden, so the maximized view takes the whole canvas
func _hide_empty(n: Node) -> bool:
	if n is FSAView or n is FSAStrip:
		return (n as Control).visible
	var any := false
	for c in n.get_children():
		if c is Control and _hide_empty(c):
			any = true
	if n is Control and n != _root:
		(n as Control).visible = any
	return any


func _unhide(n: Node) -> void:
	if n is Control:
		(n as Control).visible = true
	for c in n.get_children():
		if c is SplitContainer or c is FSAView or c is FSAStrip:
			_unhide(c)


func redraw() -> void:
	for v in views:
		(v as FSAView).redraw()


func mark_strip() -> void:
	if strip != null:
		strip.mark_dirty()


func set_render_scale(s: float) -> void:
	for v in views:
		(v as FSAView).render_scale = s
		(v as FSAView)._fit()
