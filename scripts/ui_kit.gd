class_name UiKit
extends RefCounted
## Shared UI styling helpers.

const ACCENT := Color(0.98, 0.55, 0.22)
const ACCENT2 := Color(0.45, 0.85, 1.0)
const TEXT := Color(0.96, 0.92, 0.88)
const MUTED := Color(0.75, 0.66, 0.6)
const BG := Color(0.09, 0.05, 0.04, 0.82)

static var _theme: Theme


static func theme() -> Theme:
	if _theme:
		return _theme
	_theme = Theme.new()
	_theme.default_font_size = 18
	_theme.set_color("font_color", "Label", TEXT)
	var normal := _box(Color(0.22, 0.12, 0.09, 0.95), Color(0.5, 0.28, 0.18))
	var hover := _box(Color(0.36, 0.18, 0.10, 0.98), ACCENT)
	var pressed := _box(Color(0.55, 0.26, 0.12, 1.0), ACCENT)
	var disabled := _box(Color(0.14, 0.09, 0.08, 0.8), Color(0.25, 0.18, 0.15))
	for cls in ["Button", "OptionButton", "CheckButton"]:
		_theme.set_stylebox("normal", cls, normal)
		_theme.set_stylebox("hover", cls, hover)
		_theme.set_stylebox("pressed", cls, pressed)
		_theme.set_stylebox("disabled", cls, disabled)
		_theme.set_stylebox("focus", cls, StyleBoxEmpty.new())
		_theme.set_color("font_color", cls, TEXT)
		_theme.set_color("font_hover_color", cls, Color.WHITE)
		_theme.set_color("font_disabled_color", cls, Color(0.5, 0.42, 0.38))
	_theme.set_stylebox("panel", "PanelContainer", panel_style())
	_theme.set_stylebox("panel", "Panel", panel_style())
	var bar_bg := _box(Color(0.15, 0.08, 0.06, 0.9), Color(0.35, 0.2, 0.14))
	var bar_fill := _box(ACCENT, ACCENT)
	_theme.set_stylebox("background", "ProgressBar", bar_bg)
	_theme.set_stylebox("fill", "ProgressBar", bar_fill)
	return _theme


static func _box(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(6)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


static func panel_style() -> StyleBoxFlat:
	var s := _box(BG, Color(0.45, 0.24, 0.15, 0.9))
	s.set_corner_radius_all(10)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	return s


static func label(text: String, size := 18, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, cb: Callable, min_w := 260) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 44)
	b.pressed.connect(cb)
	return b


static func centered_panel(parent: Control, min_size: Vector2) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(center)
	var pc := PanelContainer.new()
	pc.custom_minimum_size = min_size
	center.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	pc.add_child(vb)
	return vb
