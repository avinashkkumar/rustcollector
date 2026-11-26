class_name SettingsPanel
extends VBoxContainer
## Graphics / input / audio settings. Changes apply immediately and are saved.

signal closed

const SCALES := [0.0, 1.0, 0.85, 0.77, 0.67, 0.59, 0.5]
const SCALE_NAMES := ["Preset default", "100% (native)", "85%", "77% (FSR Ultra Quality)", "67% (FSR Quality)", "59% (FSR Balanced)", "50% (FSR Performance)"]
const UPS := ["auto", "off", "fsr1", "fsr2"]
const UP_NAMES := ["Auto (FSR 1 when scaled)", "Off (bilinear)", "AMD FSR 1.0 (spatial)", "AMD FSR 2.2 (temporal)"]
const CAPS := [0, 30, 60, 90, 120, 144]


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	add_child(UiKit.label("Settings", 28, UiKit.ACCENT))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 8)
	add_child(grid)

	var preset := OptionButton.new()
	preset.add_item("Auto (detected: %s)" % Config.detect_preset().capitalize())
	for p in Config.PRESETS:
		preset.add_item(p.capitalize())
	preset.selected = 0 if Config.preset == "auto" else Config.PRESETS.find(Config.preset) + 1
	preset.item_selected.connect(func(i: int) -> void:
		Config.preset = "auto" if i == 0 else Config.PRESETS[i - 1]
		Config.changed())
	_row(grid, "Quality preset", preset)

	var ups := OptionButton.new()
	for n in UP_NAMES:
		ups.add_item(n)
	ups.selected = maxi(UPS.find(Config.upscaler), 0)
	ups.item_selected.connect(func(i: int) -> void:
		Config.upscaler = UPS[i]
		Config.changed())
	_row(grid, "Upscaler", ups)

	var scale := OptionButton.new()
	for n in SCALE_NAMES:
		scale.add_item(n)
	scale.selected = maxi(SCALES.find(Config.render_scale), 0)
	scale.item_selected.connect(func(i: int) -> void:
		Config.render_scale = SCALES[i]
		Config.changed())
	_row(grid, "Render scale", scale)

	var cap := OptionButton.new()
	for c in CAPS:
		cap.add_item("Unlimited" if c == 0 else "%d FPS" % c)
	cap.selected = maxi(CAPS.find(Config.fps_cap), 0)
	cap.item_selected.connect(func(i: int) -> void:
		Config.fps_cap = CAPS[i]
		Config.changed())
	_row(grid, "Frame rate cap", cap)

	_row(grid, "VSync", _check(Config.vsync, func(on: bool) -> void: Config.vsync = on; Config.changed()))
	_row(grid, "Fullscreen", _check(Config.fullscreen, func(on: bool) -> void: Config.fullscreen = on; Config.changed()))
	_row(grid, "Hexagon grid (H)", _check(Config.hex_overlay, func(on: bool) -> void: Config.hex_overlay = on; Config.changed()))
	_row(grid, "Show FPS (F3)", _check(Config.show_fps, func(on: bool) -> void: Config.show_fps = on; Config.changed()))
	_row(grid, "Mouse sensitivity", _slider(0.03, 0.4, Config.mouse_sensitivity, func(v: float) -> void: Config.mouse_sensitivity = v; Config.save_settings()))
	_row(grid, "Story narrator", _check(Config.narrator, func(on: bool) -> void: Config.narrator = on; Config.save_settings()))
	_row(grid, "Volume", _slider(0.0, 1.0, Config.master_volume, func(v: float) -> void: Config.master_volume = v; Config.changed()))

	var info := UiKit.label("GPU: %s  ·  %s" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_api_version()], 14, UiKit.MUTED)
	add_child(info)
	add_child(UiKit.button("Back", func() -> void: closed.emit()))


func _row(grid: GridContainer, text: String, ctrl: Control) -> void:
	grid.add_child(UiKit.label(text))
	ctrl.custom_minimum_size.x = 300
	grid.add_child(ctrl)


func _check(on: bool, cb: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.button_pressed = on
	c.toggled.connect(cb)
	return c


func _slider(lo: float, hi: float, v: float, cb: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.01
	s.value = v
	s.custom_minimum_size = Vector2(300, 28)
	s.value_changed.connect(cb)
	return s
