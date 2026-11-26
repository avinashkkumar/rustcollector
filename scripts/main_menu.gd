class_name MainMenu
extends Control
## Title screen.

signal new_game
signal continue_game
signal run_benchmark(preset: String)

var _main: VBoxContainer
var _settings: SettingsPanel
var _bench_preset := "high"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiKit.theme()
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
// Flat Martian plain at dusk: no planet, just a long horizon and drifting dust.
void fragment() {
	vec2 uv = UV;
	float horizon = 0.64 + sin(uv.x * 5.0 + 0.7) * 0.01 + sin(uv.x * 23.0) * 0.003;
	vec3 sky = mix(vec3(0.90, 0.60, 0.40), vec3(0.20, 0.09, 0.07), pow(1.0 - uv.y / horizon, 1.2));
	float sun = smoothstep(0.06, 0.0, length((uv - vec2(0.74, 0.5)) * vec2(1.7, 1.0)));
	sky += vec3(1.0, 0.85, 0.6) * sun * 0.6;
	float g = (uv.y - horizon) / (1.0 - horizon);
	vec3 ground = mix(vec3(0.55, 0.25, 0.12), vec3(0.18, 0.08, 0.05), g);
	// hexagon grid receding to the horizon
	vec2 p = vec2((uv.x - 0.5) / max(g, 0.02), 1.0 / max(g, 0.02)) * 1.2;
	vec2 s = vec2(1.0, 1.7320508);
	vec4 hc = floor(vec4(p, p - vec2(0.5, 1.0)) / s.xyxy) + 0.5;
	vec4 h = vec4(p - hc.xy * s, p - (hc.zw + 0.5) * s);
	vec2 l = dot(h.xy, h.xy) < dot(h.zw, h.zw) ? h.xy : h.zw;
	float hd = max(dot(abs(l), vec2(0.5, 0.8660254)), abs(l.x));
	ground += vec3(1.0, 0.7, 0.45) * smoothstep(0.46, 0.5, hd) * 0.18 * smoothstep(0.0, 0.3, g);
	vec3 c = uv.y < horizon ? sky : ground;
	float dust = sin(uv.x * 30.0 + TIME * 0.6) * sin(uv.y * 23.0 - TIME * 0.4);
	c += vec3(0.05, 0.025, 0.01) * dust;
	COLOR = vec4(c, 1.0);
}
"""
	sm.shader = sh
	bg.material = sm
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 90)
	margin.add_theme_constant_override("margin_top", 70)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)
	var title := UiKit.label("RUSTFALL", 86, Color(1.0, 0.92, 0.82))
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_color_override("font_outline_color", Color(0.25, 0.08, 0.03))
	col.add_child(title)
	col.add_child(UiKit.label("COLONY CLEANUP", 28, UiKit.ACCENT))
	col.add_child(UiKit.label("The storm passed. The rust stayed. Grab a brush.", 18, Color(1, 0.9, 0.82, 0.9)))
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 24
	col.add_child(spacer)

	var pc := PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(pc)
	var stack := VBoxContainer.new()
	pc.add_child(stack)
	_main = VBoxContainer.new()
	_main.add_theme_constant_override("separation", 10)
	stack.add_child(_main)
	if GameState.has_save():
		_main.add_child(UiKit.button("Continue", func() -> void: continue_game.emit(), 340))
	_main.add_child(UiKit.button("New game", func() -> void: new_game.emit(), 340))
	var bench_row := HBoxContainer.new()
	bench_row.add_theme_constant_override("separation", 8)
	var bench := UiKit.button("Run benchmark", func() -> void: run_benchmark.emit(_bench_preset), 200)
	bench_row.add_child(bench)
	var pick := OptionButton.new()
	for p in Config.PRESETS:
		pick.add_item(p.capitalize())
	pick.selected = Config.PRESETS.find(_bench_preset)
	pick.custom_minimum_size = Vector2(132, 44)
	pick.item_selected.connect(func(i: int) -> void: _bench_preset = Config.PRESETS[i])
	bench_row.add_child(pick)
	_main.add_child(bench_row)
	_main.add_child(UiKit.button("Settings", func() -> void:
		_main.visible = false
		_settings.visible = true, 340))
	_main.add_child(UiKit.button("Quit", func() -> void: get_tree().quit(), 340))
	_settings = SettingsPanel.new()
	_settings.visible = false
	_settings.closed.connect(func() -> void:
		_settings.visible = false
		_main.visible = true)
	stack.add_child(_settings)

	var foot := UiKit.label("%s  ·  %s  ·  auto preset: %s  ·  Godot %s  ·  assets: Kenney (CC0)" % [
		RenderingServer.get_video_adapter_name(), OS.get_name(), Config.detect_preset().capitalize(),
		Engine.get_version_info().string], 14, Color(1, 0.9, 0.8, 0.7))
	foot.anchor_top = 1.0
	foot.anchor_bottom = 1.0
	foot.offset_left = 90
	foot.offset_top = -40
	add_child(foot)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
