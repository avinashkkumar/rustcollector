class_name MainMenu
extends Control
## Title screen.

signal play_world(id: String, is_new: bool)
signal run_benchmark(preset: String)

var _main: VBoxContainer
var _worlds: VBoxContainer
var _world_list: VBoxContainer
var _create: VBoxContainer
var _name_edit: LineEdit
var _seed_edit: LineEdit
var _diff_pick: OptionButton
var _diff_desc: Label
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
	var all := Worlds.list()
	if not all.is_empty():
		var last: Dictionary = all[0]
		var cont := UiKit.button("Continue: %s" % last.name, func() -> void: play_world.emit(last.id, not last.played), 340)
		cont.clip_text = true
		_main.add_child(cont)
	_main.add_child(UiKit.button("Worlds (%d)" % all.size() if not all.is_empty() else "New world", func() -> void:
		if all.is_empty():
			_show(_create)
		else:
			show_worlds(), 340))
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
	_build_worlds(stack)
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


func _show(panel: Control) -> void:
	for p in [_main, _worlds, _create]:
		p.visible = p == panel
	if panel == _create:
		_name_edit.text = ""
		_name_edit.placeholder_text = Worlds.next_default_name()
		_seed_edit.text = ""
		_name_edit.grab_focus()


func show_worlds() -> void:
	_refresh_worlds()
	_show(_worlds)


func _build_worlds(stack: VBoxContainer) -> void:
	_worlds = VBoxContainer.new()
	_worlds.add_theme_constant_override("separation", 10)
	_worlds.visible = false
	stack.add_child(_worlds)
	_worlds.add_child(UiKit.label("WORLDS", 26, UiKit.ACCENT))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(860, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_worlds.add_child(scroll)
	_world_list = VBoxContainer.new()
	_world_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_world_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_world_list)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	bar.add_child(UiKit.button("Create new world", func() -> void: _show(_create), 300))
	bar.add_child(UiKit.button("Back", func() -> void: _show(_main), 160))
	_worlds.add_child(bar)

	_create = VBoxContainer.new()
	_create.add_theme_constant_override("separation", 10)
	_create.visible = false
	stack.add_child(_create)
	_create.add_child(UiKit.label("CREATE NEW WORLD", 26, UiKit.ACCENT))
	_create.add_child(UiKit.label("World name", 16, UiKit.MUTED))
	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size = Vector2(520, 44)
	_name_edit.max_length = 40
	_create.add_child(_name_edit)
	_create.add_child(UiKit.label("Seed for the terrain (leave blank for a random one; any word or number works)", 16, UiKit.MUTED))
	_seed_edit = LineEdit.new()
	_seed_edit.custom_minimum_size = Vector2(520, 44)
	_seed_edit.placeholder_text = "random"
	_seed_edit.max_length = 40
	_create.add_child(_seed_edit)
	_create.add_child(UiKit.label("Difficulty (can't be changed later)", 16, UiKit.MUTED))
	_diff_pick = OptionButton.new()
	_diff_pick.custom_minimum_size = Vector2(520, 44)
	for k in GameState.DIFFICULTY_ORDER:
		_diff_pick.add_item(GameState.DIFFICULTIES[k].name)
	_diff_pick.selected = 1
	_create.add_child(_diff_pick)
	_diff_desc = UiKit.label(GameState.DIFFICULTIES.standard.desc, 14, UiKit.MUTED)
	_create.add_child(_diff_desc)
	_diff_pick.item_selected.connect(func(i: int) -> void:
		_diff_desc.text = GameState.DIFFICULTIES[GameState.DIFFICULTY_ORDER[i]].desc)
	var go := func() -> void:
		var id := Worlds.create(_name_edit.text, _seed_edit.text, GameState.DIFFICULTY_ORDER[_diff_pick.selected])
		play_world.emit(id, true)
	_name_edit.text_submitted.connect(func(_t: String) -> void: go.call())
	_seed_edit.text_submitted.connect(func(_t: String) -> void: go.call())
	var bar2 := HBoxContainer.new()
	bar2.add_theme_constant_override("separation", 10)
	bar2.add_child(UiKit.button("Create & play", go, 300))
	bar2.add_child(UiKit.button("Cancel", func() -> void:
		if Worlds.list().is_empty():
			_show(_main)
		else:
			show_worlds(), 160))
	_create.add_child(bar2)


func _refresh_worlds() -> void:
	for c in _world_list.get_children():
		c.queue_free()
	for w in Worlds.list():
		var row := PanelContainer.new()
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		row.add_child(hb)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var title := UiKit.label(str(w.name), 20)
		info.add_child(title)
		info.add_child(UiKit.label(Worlds.describe(w), 13, UiKit.MUTED))
		hb.add_child(info)
		var id: String = w.id
		var is_new: bool = not w.played
		hb.add_child(UiKit.button("Play", func() -> void: play_world.emit(id, is_new), 100))
		var rename_btn := UiKit.button("Rename", Callable(), 110)
		rename_btn.pressed.connect(func() -> void: _start_rename(info, title, id))
		hb.add_child(rename_btn)
		var del := UiKit.button("Delete", Callable(), 110)
		del.pressed.connect(func() -> void:
			if del.text == "Delete":
				del.text = "Sure?"
				del.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
				get_tree().create_timer(3.0).timeout.connect(func() -> void:
					if is_instance_valid(del):
						del.text = "Delete"
						del.remove_theme_color_override("font_color"))
			else:
				Worlds.delete(id)
				if Worlds.list().is_empty():
					_show(_main)
					_rebuild_main_buttons()
				else:
					_refresh_worlds())
		hb.add_child(del)
		_world_list.add_child(row)


func _start_rename(info: VBoxContainer, title: Label, id: String) -> void:
	var edit := LineEdit.new()
	edit.text = title.text
	edit.max_length = 40
	edit.custom_minimum_size = Vector2(360, 36)
	title.visible = false
	info.add_child(edit)
	info.move_child(edit, 0)
	edit.grab_focus()
	edit.select_all()
	var state := {done = false}
	var done := func(t: String) -> void:
		if state.done:
			return
		state.done = true
		Worlds.rename(id, t)
		_refresh_worlds()
	edit.text_submitted.connect(done)
	edit.focus_exited.connect(func() -> void: done.call(edit.text))


## After the last world is deleted the main column must lose its "Continue" button.
func _rebuild_main_buttons() -> void:
	get_parent().call_deferred("show_menu")
