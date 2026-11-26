extends Node
## Global settings, input map and graphics quality presets. Autoloaded as "Config".

signal settings_changed

const SETTINGS_PATH := "user://settings.cfg"
const PRESETS: Array[String] = ["low", "medium", "high", "ultra"]

var preset := "auto"
var render_scale := 0.0  # 0 = use preset default
var upscaler := "auto"  # auto | off | fsr1 | fsr2
var vsync := true
var fps_cap := 0
var fullscreen := false
var mouse_sensitivity := 0.12
var master_volume := 0.8
var show_fps := false
var hex_overlay := true
var narrator := true

## Benchmark overrides (never saved).
var override_preset := ""
var override_render_scale := -1.0
var override_upscaler := ""

const UPSCALERS: Array[String] = ["off", "fsr1", "fsr2"]
## AMD's standard FSR quality modes (render scale per axis).
const FSR_MODES := [
	{name = "Native AA", scale = 1.0}, {name = "Ultra Quality", scale = 0.77}, {name = "Quality", scale = 0.67},
	{name = "Balanced", scale = 0.59}, {name = "Performance", scale = 0.5},
]


func _ready() -> void:
	_setup_input()
	load_settings()
	apply_display()


func resolved_preset() -> String:
	if override_preset in PRESETS:
		return override_preset
	if preset in PRESETS:
		return preset
	return detect_preset()


## Picks a preset from the GPU class. Integrated GPUs (e.g. Radeon 860M) get "medium".
func detect_preset() -> String:
	match RenderingServer.get_video_adapter_type():
		RenderingDevice.DEVICE_TYPE_DISCRETE_GPU:
			return "high"
		RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU:
			return "medium"
		RenderingDevice.DEVICE_TYPE_CPU, RenderingDevice.DEVICE_TYPE_VIRTUAL_GPU:
			return "low"
	return "medium"


func preset_params(name: String) -> Dictionary:
	var hard := RenderingServer.SHADOW_QUALITY_HARD
	match name:
		"low":
			return {scale = 0.6, msaa = 0, fxaa = true, shadow_size = 1024, shadow_splits = 1,
				shadow_dist = 45.0, soft = hard, ssao = false, ssil = false, glow = false,
				vol_fog = false, particles = 0.35, view_dist = 170.0, omni_shadows = false,
				drone_lights = false, headlights = false, pom = 0}
		"medium":
			return {scale = 0.85, msaa = 1, fxaa = false, shadow_size = 2048, shadow_splits = 2,
				shadow_dist = 70.0, soft = RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW, ssao = false,
				ssil = false, glow = true, vol_fog = false, particles = 0.6, view_dist = 260.0,
				omni_shadows = false, drone_lights = false, headlights = true, pom = 6}
		"high":
			return {scale = 1.0, msaa = 1, fxaa = false, shadow_size = 4096, shadow_splits = 4,
				shadow_dist = 110.0, soft = RenderingServer.SHADOW_QUALITY_SOFT_LOW, ssao = true,
				ssil = false, glow = true, vol_fog = false, particles = 1.0, view_dist = 340.0,
				omni_shadows = true, drone_lights = true, headlights = true, pom = 10}
		"ultra":
			return {scale = 1.0, msaa = 2, fxaa = false, shadow_size = 4096, shadow_splits = 4,
				shadow_dist = 170.0, soft = RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, ssao = true,
				ssil = true, glow = true, vol_fog = true, particles = 1.5, view_dist = 400.0,
				omni_shadows = true, drone_lights = true, headlights = true, pom = 16}
	return preset_params("medium")


func effective_render_scale(p: Dictionary) -> float:
	if override_render_scale > 0.0:
		return override_render_scale
	if render_scale > 0.0:
		return render_scale
	return p.scale


func effective_upscaler(p: Dictionary) -> String:
	if override_upscaler in UPSCALERS:
		return override_upscaler
	if upscaler in UPSCALERS:
		return upscaler
	return "fsr1" if effective_render_scale(p) < 0.999 else "off"


## FSR 1.0 (spatial) and FSR 2.2 (temporal) both run as Vulkan compute shaders inside Godot,
## so the same upscaler code runs on Linux and Windows.
func apply_viewport(vp: Viewport, p: Dictionary) -> void:
	var s := effective_render_scale(p)
	var up := effective_upscaler(p)
	vp.scaling_3d_scale = s
	match up:
		"fsr1":
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
		"fsr2":
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
		_:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.fsr_sharpness = 0.25
	var msaa_modes := [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X]
	if up == "fsr2":
		# FSR 2 does its own temporal anti-aliasing; MSAA/FXAA on top only costs time.
		vp.msaa_3d = Viewport.MSAA_DISABLED
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	else:
		vp.msaa_3d = msaa_modes[p.msaa]
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if p.fxaa else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = false
	RenderingServer.directional_shadow_atlas_set_size(p.shadow_size, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(p.soft)
	RenderingServer.positional_soft_shadow_filter_set_quality(p.soft)


func apply_display() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = fps_cap
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != want:
		DisplayServer.window_set_mode(want)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))


func changed() -> void:
	save_settings()
	apply_display()
	settings_changed.emit()


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	preset = cf.get_value("video", "preset", preset)
	render_scale = cf.get_value("video", "render_scale", render_scale)
	upscaler = cf.get_value("video", "upscaler", upscaler)
	vsync = cf.get_value("video", "vsync", vsync)
	fps_cap = cf.get_value("video", "fps_cap", fps_cap)
	fullscreen = cf.get_value("video", "fullscreen", fullscreen)
	show_fps = cf.get_value("video", "show_fps", show_fps)
	hex_overlay = cf.get_value("video", "hex_overlay", hex_overlay)
	narrator = cf.get_value("audio", "narrator", narrator)
	mouse_sensitivity = cf.get_value("input", "mouse_sensitivity", mouse_sensitivity)
	master_volume = cf.get_value("audio", "master_volume", master_volume)


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("video", "preset", preset)
	cf.set_value("video", "render_scale", render_scale)
	cf.set_value("video", "upscaler", upscaler)
	cf.set_value("video", "vsync", vsync)
	cf.set_value("video", "fps_cap", fps_cap)
	cf.set_value("video", "fullscreen", fullscreen)
	cf.set_value("video", "show_fps", show_fps)
	cf.set_value("video", "hex_overlay", hex_overlay)
	cf.set_value("audio", "narrator", narrator)
	cf.set_value("input", "mouse_sensitivity", mouse_sensitivity)
	cf.set_value("audio", "master_volume", master_volume)
	cf.save(SETTINGS_PATH)


func _setup_input() -> void:
	_key("move_forward", [KEY_W, KEY_UP])
	_key("move_back", [KEY_S, KEY_DOWN])
	_key("move_left", [KEY_A, KEY_LEFT])
	_key("move_right", [KEY_D, KEY_RIGHT])
	_key("jump", [KEY_SPACE])
	_key("sprint", [KEY_SHIFT])
	_key("interact", [KEY_E])
	_key("pause", [KEY_ESCAPE])
	_key("toggle_fps", [KEY_F3])
	_key("key_guide", [KEY_F1])
	_key("toggle_map", [KEY_M])
	_key("toggle_hex", [KEY_H])
	_key("vehicle_tool", [KEY_R])
	_key("vehicle_empty", [KEY_Q])
	_key("waypoint", [KEY_T])
	_key("camera_toggle", [KEY_V])
	_key("use_kit", [KEY_G])
	_key("use_cell", [KEY_B])
	if not InputMap.has_action("clean"):
		InputMap.add_action("clean")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("clean", mb)
		var k := InputEventKey.new()
		k.physical_keycode = KEY_F
		InputMap.action_add_event("clean", k)


func _key(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for code in keys:
		var e := InputEventKey.new()
		e.physical_keycode = code
		InputMap.action_add_event(action, e)
