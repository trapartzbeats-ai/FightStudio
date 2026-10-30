class_name FSATheme
extends RefCounted
## The Animator's look (dark plum like the review sheets, orange / gold accents, Oswald headings) and small widget makers so
## every panel is built the same way.

const BG0 := Color("0d0b0f")
const BG1 := Color("16131a")
const BG2 := Color("1f1a24")
const BG3 := Color("2a2430")
const LINE := Color("3a3342")
const TEXT := Color("f4efe6")
const MUTED := Color("9a91a6")
const ACCENT := Color("ff7a1a")
const GOLD := Color("ffc93c")
const LEFT := Color("4fd1ff")
const RIGHT := Color("ff5d8f")
const OK := Color("5ce08a")
const PURPLE := Color("a77bff")
const RED := Color("ff4d4d")
const AXIS := [Color("ff4d5e"), Color("6be36b"), Color("4d8dff")]

static var _theme: Theme
static var head_font: Font
static var body_font: Font


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	head_font = _font("res://ui/fonts/oswald600.woff2")
	body_font = ThemeDB.fallback_font
	t.default_font_size = 14
	t.set_font_size("font_size", "Button", 13)
	t.set_font_size("font_size", "OptionButton", 13)
	t.set_font_size("font_size", "CheckBox", 13)
	var panel := _box(BG1, 0)
	t.set_stylebox("panel", "Panel", panel)
	t.set_stylebox("panel", "PanelContainer", _box(BG1, 0, 6))
	t.set_stylebox("panel", "PopupMenu", _box(BG2, 4, 6, LINE))
	t.set_stylebox("panel", "PopupPanel", _box(BG2, 4, 6, LINE))
	t.set_stylebox("panel", "TooltipPanel", _box(BG2, 3, 6, ACCENT.darkened(0.3)))
	t.set_color("font_color", "TooltipLabel", TEXT)
	for c in ["Button", "OptionButton", "MenuButton", "CheckButton", "CheckBox"]:
		t.set_color("font_color", c, TEXT)
		t.set_color("font_hover_color", c, Color.WHITE)
		t.set_color("font_pressed_color", c, BG0 if c == "Button" else TEXT)
		t.set_color("font_hover_pressed_color", c, BG0 if c == "Button" else TEXT)
		t.set_color("font_disabled_color", c, MUTED.darkened(0.3))
	t.set_stylebox("normal", "Button", _box(BG3, 4, 7, LINE, 4))
	t.set_stylebox("hover", "Button", _box(BG3.lightened(0.08), 4, 7, ACCENT.darkened(0.25), 4))
	t.set_stylebox("pressed", "Button", _box(ACCENT, 4, 7, ACCENT, 4))
	t.set_stylebox("hover_pressed", "Button", _box(ACCENT.lightened(0.1), 4, 7, GOLD, 4))
	t.set_stylebox("disabled", "Button", _box(BG2, 4, 7, BG3, 4))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for c in ["OptionButton", "MenuButton"]:
		t.set_stylebox("normal", c, _box(BG3, 4, 7, LINE, 4))
		t.set_stylebox("hover", c, _box(BG3.lightened(0.08), 4, 7, ACCENT.darkened(0.25), 4))
		t.set_stylebox("pressed", c, _box(BG3.lightened(0.12), 4, 7, ACCENT, 4))
		t.set_stylebox("focus", c, StyleBoxEmpty.new())
	t.set_stylebox("normal", "MenuBar", _box(BG0, 0, 6))
	t.set_stylebox("hover", "MenuBar", _box(BG3, 3, 6))
	t.set_stylebox("pressed", "MenuBar", _box(ACCENT.darkened(0.2), 3, 6))
	t.set_color("font_color", "MenuBar", TEXT)
	t.set_color("font_hover_color", "MenuBar", Color.WHITE)
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_color("font_disabled_color", "PopupMenu", MUTED.darkened(0.3))
	t.set_color("font_accelerator_color", "PopupMenu", MUTED)
	t.set_color("font_separator_color", "PopupMenu", GOLD)
	t.set_stylebox("hover", "PopupMenu", _box(ACCENT.darkened(0.35), 3, 4))
	t.set_stylebox("separator", "PopupMenu", _line_box())
	t.set_stylebox("labeled_separator_left", "PopupMenu", _line_box())
	t.set_stylebox("labeled_separator_right", "PopupMenu", _line_box())
	for c in ["LineEdit", "SpinBox"]:
		t.set_stylebox("normal", c, _box(BG0, 3, 6, LINE))
		t.set_stylebox("focus", c, _box(BG0, 3, 6, ACCENT))
		t.set_stylebox("read_only", c, _box(BG2, 3, 6, BG3))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("caret_color", "LineEdit", GOLD)
	t.set_color("selection_color", "LineEdit", ACCENT.darkened(0.3))
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "TabContainer", _box(BG1, 0, 0))
	t.set_stylebox("tab_selected", "TabContainer", _tab(BG1, ACCENT))
	t.set_stylebox("tab_unselected", "TabContainer", _tab(BG0, BG0))
	t.set_stylebox("tab_hovered", "TabContainer", _tab(BG2, ACCENT.darkened(0.4)))
	t.set_stylebox("tab_focus", "TabContainer", StyleBoxEmpty.new())
	t.set_stylebox("tabbar_background", "TabContainer", _box(BG0, 0, 0))
	t.set_color("font_selected_color", "TabContainer", GOLD)
	t.set_color("font_unselected_color", "TabContainer", MUTED)
	t.set_color("font_hovered_color", "TabContainer", TEXT)
	t.set_font("font", "TabContainer", head_font)
	t.set_font_size("font_size", "TabContainer", 14)
	t.set_stylebox("panel", "ItemList", _box(BG0, 3, 4, BG3))
	t.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	t.set_stylebox("selected", "ItemList", _box(ACCENT.darkened(0.35), 2, 2))
	t.set_stylebox("selected_focus", "ItemList", _box(ACCENT.darkened(0.25), 2, 2))
	t.set_stylebox("hovered", "ItemList", _box(BG3, 2, 2))
	t.set_color("font_color", "ItemList", TEXT)
	t.set_color("font_selected_color", "ItemList", Color.WHITE)
	t.set_stylebox("panel", "Tree", _box(BG0, 3, 4, BG3))
	t.set_stylebox("focus", "Tree", StyleBoxEmpty.new())
	t.set_stylebox("selected", "Tree", _box(ACCENT.darkened(0.35), 2, 2))
	t.set_stylebox("selected_focus", "Tree", _box(ACCENT.darkened(0.25), 2, 2))
	t.set_color("font_color", "Tree", TEXT)
	t.set_color("font_selected_color", "Tree", Color.WHITE)
	t.set_color("guide_color", "Tree", BG3)
	t.set_stylebox("slider", "HSlider", _box(BG0, 3, 0, LINE, 4))
	t.set_stylebox("grabber_area", "HSlider", _box(ACCENT.darkened(0.2), 3, 0, Color.TRANSPARENT, 4))
	t.set_stylebox("grabber_area_highlight", "HSlider", _box(ACCENT, 3, 0, Color.TRANSPARENT, 4))
	t.set_stylebox("split_bar_background", "HSplitContainer", _box(BG0, 0, 0))
	t.set_stylebox("split_bar_background", "VSplitContainer", _box(BG0, 0, 0))
	t.set_constant("separation", "HSplitContainer", 5)
	t.set_constant("separation", "VSplitContainer", 5)
	t.set_constant("separation", "BoxContainer", 4)
	t.set_constant("separation", "VBoxContainer", 4)
	t.set_constant("separation", "HBoxContainer", 4)
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_stylebox("normal", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("pressed", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("hover", "CheckBox", _box(BG3, 3, 2))
	t.set_stylebox("hover_pressed", "CheckBox", _box(BG3, 3, 2))
	t.set_stylebox("focus", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("normal", "CheckButton", StyleBoxEmpty.new())
	t.set_stylebox("pressed", "CheckButton", StyleBoxEmpty.new())
	t.set_stylebox("hover", "CheckButton", _box(BG3, 3, 2))
	t.set_stylebox("focus", "CheckButton", StyleBoxEmpty.new())
	_theme = t
	return t


static func _font(path: String) -> Font:
	if ResourceLoader.exists(path):
		var f: Variant = load(path)
		if f is Font:
			return f
	return ThemeDB.fallback_font


static func _box(bg: Color, radius: int = 4, pad: int = 6, border: Color = Color.TRANSPARENT, pad_v: int = -1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad if pad_v < 0 else pad_v
	s.content_margin_bottom = pad if pad_v < 0 else pad_v
	if border.a > 0.0:
		s.set_border_width_all(1)
		s.border_color = border
	return s


static func _tab(bg: Color, top: Color) -> StyleBoxFlat:
	var s := _box(bg, 0, 10, Color.TRANSPARENT, 5)
	s.border_width_top = 2
	s.border_color = top
	return s


static func _line_box() -> StyleBoxLine:
	var s := StyleBoxLine.new()
	s.color = LINE
	s.thickness = 1
	return s


# ---------------------------------------------------------------- widget makers

static func label(text: String, color: Color = TEXT, size: int = 14) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	return l


static func heading(text: String, color: Color = GOLD) -> Label:
	var l := label(text.to_upper(), color, 15)
	l.add_theme_font_override("font", head_font if head_font != null else ThemeDB.fallback_font)
	return l


static func hint(text: String) -> Label:
	var l := label(text, MUTED, 12)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 120
	return l


static func button(text: String, cb: Callable, tip: String = "", toggle: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.toggle_mode = toggle
	b.focus_mode = Control.FOCUS_NONE
	if cb.is_valid():
		if toggle:
			b.toggled.connect(func(on: bool) -> void: cb.call(on))
		else:
			b.pressed.connect(cb)
	return b


static func check(text: String, on: bool, cb: Callable, tip: String = "") -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = on
	c.tooltip_text = tip
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(func(v: bool) -> void: cb.call(v))
	return c


static func option(items: Array, selected: int, cb: Callable, tip: String = "") -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(str(it))
	if selected >= 0 and selected < items.size():
		o.select(selected)
	o.tooltip_text = tip
	o.focus_mode = Control.FOCUS_NONE
	o.item_selected.connect(func(i: int) -> void: cb.call(i))
	return o


static func spin(lo: float, hi: float, step: float, val: float, cb: Callable, tip: String = "", suffix: String = "") -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = val
	s.tooltip_text = tip
	s.suffix = suffix
	s.allow_greater = true
	s.allow_lesser = true
	s.custom_minimum_size.x = 84
	s.value_changed.connect(func(v: float) -> void: cb.call(v))
	return s


## label + slider + number on one row; returns the slider (meta "spin" holds the number box)
static func slider_row(parent: Control, text: String, lo: float, hi: float, step: float, val: float, cb: Callable, tip: String = "", color: Color = TEXT) -> HSlider:
	var row := HBoxContainer.new()
	var l := label(text, color, 13)
	l.custom_minimum_size.x = 92
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = val
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.tooltip_text = tip
	s.focus_mode = Control.FOCUS_NONE
	row.add_child(s)
	var sp := SpinBox.new()
	sp.min_value = lo
	sp.max_value = hi
	sp.step = step
	sp.value = val
	sp.allow_greater = true
	sp.allow_lesser = true
	sp.custom_minimum_size.x = 78
	row.add_child(sp)
	var lock := [false]
	s.value_changed.connect(func(v: float) -> void:
		if lock[0]:
			return
		lock[0] = true
		sp.value = v
		lock[0] = false
		cb.call(v))
	sp.value_changed.connect(func(v: float) -> void:
		if lock[0]:
			return
		lock[0] = true
		s.value = v
		lock[0] = false
		cb.call(v))
	s.set_meta("spin", sp)
	s.set_meta("lock", lock)
	parent.add_child(row)
	return s


## move a slider_row's slider without calling back
static func set_quiet(s: HSlider, v: float) -> void:
	var lock: Array = s.get_meta("lock", [false])
	lock[0] = true
	s.value = v
	(s.get_meta("spin") as SpinBox).value = v
	lock[0] = false


static func row(parent: Control, kids: Array) -> HBoxContainer:
	var r := HBoxContainer.new()
	for k in kids:
		r.add_child(k as Node)
	parent.add_child(r)
	return r


static func sep(parent: Control) -> void:
	var s := HSeparator.new()
	s.add_theme_stylebox_override("separator", _line_box())
	parent.add_child(s)


## a panel body: a scroll container with a padded VBox inside; returns the VBox
static func scroll_body(parent: Control) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(sc)
	var m := MarginContainer.new()
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 8)
	sc.add_child(m)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_child(v)
	return v
