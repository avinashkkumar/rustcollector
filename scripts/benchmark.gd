class_name Benchmark
extends Node
## Deterministic scripted benchmark. Runs every game system through five stages and records
## per-frame timing (frame time, CPU/GPU render time, draw calls ...) to CSV + JSON summary.

signal finished(result_dir: String)

const VERSION := "1.0"
const WARMUP := 5.0
const STAGES := [
	{id = "flyover", name = "Colony Flyover", dur = 20.0, desc = "Base props, shadows, lights, far terrain"},
	{id = "sweep", name = "Surface Sweep", dur = 20.0, desc = "Ground-level camera, continuous rust removal, parallax layer, texture uploads, particles"},
	{id = "swarm", name = "Drone Swarm", dur = 20.0, desc = "48 autonomous drones cleaning (CPU script + particles + lights)"},
	{id = "rover", name = "Sweeper Run", dur = 20.0, desc = "Sweeper at speed with the charger cart alongside, chase camera, drones active"},
	{id = "storm", name = "Dust Storm", dur = 20.0, desc = "Max load: volumetric fog, storm particles, 16 extra lights, everything active"},
]
const SWARM_SIZE := 48
const SWARM_CENTER := Vector3(-55, 0, -42)
const SWEEP_CIRCLE := Vector3(-38, 0, 52)

var world: World
var opts := {}
var cam: Camera3D
var overlay: Label
var stage_i := -1
var stage_t := 0.0
var warm_t := 0.0
var running := false
var done := false
var _last_us := 0
var _vp_rid: RID
var _storm: GPUParticles3D
var _swarm: Array[Drone] = []
var _extras_on := true
var _base_fog := 0.0
var _base_vol := false
var _storm_lights: Array[OmniLight3D] = []
var _sweep_fx_t := 0.0
var _overlay_t := 0.0
var _ov_frames := 0
var _ov_time := 0.0

# Per-frame columns.
var c_time := PackedFloat64Array()
var c_stage := PackedInt32Array()
var c_ft := PackedFloat64Array()
var c_cpu_render := PackedFloat64Array()
var c_gpu := PackedFloat64Array()
var c_process := PackedFloat64Array()
var c_physics := PackedFloat64Array()
var c_draws := PackedInt32Array()
var c_prims := PackedInt32Array()
var c_objects := PackedInt32Array()
var c_vram := PackedFloat64Array()
var _elapsed := 0.0
var _shots_taken := {}
var _result_dir_pending := ""


func _ready() -> void:
	process_priority = -1000  # run first each frame so the timestamp marks the frame boundary
	_vp_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp_rid, true)
	# Uncapped: measure the real load, not the display refresh rate.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	if opts.has("bench-windowed"):
		var wh: PackedStringArray = str(opts["bench-windowed"]).split("x")
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		if wh.size() == 2:
			DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))
			var scr := DisplayServer.screen_get_usable_rect()
			DisplayServer.window_set_position(scr.position + (scr.size - DisplayServer.window_get_size()) / 2)
	elif opts.has("bench-exclusive"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	else:
		# Borderless fullscreen at native resolution: no display mode switch (which can upset
		# compositors) and the same pixel count as exclusive fullscreen.
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	cam = Camera3D.new()
	cam.fov = 72.0
	cam.far = float(world.params.view_dist)
	world.add_child(cam)
	cam.current = true
	_pose_flyover(0.0)
	var cl := CanvasLayer.new()
	add_child(cl)
	overlay = UiKit.label("", 18, Color(1, 0.95, 0.85))
	overlay.position = Vector2(16, 12)
	overlay.add_theme_constant_override("outline_size", 6)
	overlay.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	cl.add_child(overlay)
	_prepare_extras()
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_last_us = Time.get_ticks_usec()
	running = true


func _process(dt: float) -> void:
	if done:
		return
	var now := Time.get_ticks_usec()
	var ft := (now - _last_us) / 1000.0
	_last_us = now
	if stage_i < 0:
		warm_t += dt
		if warm_t < WARMUP * 0.5:
			# Phase 1: show every effect once so shaders, pipelines and buffers are created now,
			# not as a hitch in the middle of a measured stage.
			_set_extras(true)
			_run_swarm(0.5)
			_storm.global_position = cam.global_position
			_run_rover(0.25)
		else:
			# Phase 2: fly the whole flyover path once at speed so everything along it
			# (lights' shadow maps, label glyphs, LODs) is drawn before measuring starts.
			_set_extras(false)
			_pose_flyover(clampf((warm_t - WARMUP * 0.5) / (WARMUP * 0.4), 0.0, 1.0) if warm_t < WARMUP * 0.9 else 0.0)
		overlay.text = "RUSTFALL BENCHMARK  ·  preset %s  ·  %s %d%%  ·  warming up (compiling shaders) %.0f s" % [Config.resolved_preset().to_upper(),
			Config.effective_upscaler(world.params).to_upper(), roundi(Config.effective_render_scale(world.params) * 100), maxf(WARMUP - warm_t, 0.0)]
		if warm_t >= WARMUP:
			_enter_stage(0)
		return
	_record(ft)
	stage_t += dt
	_elapsed += dt
	var st: Dictionary = STAGES[stage_i]
	if stage_t >= float(st.dur):
		if stage_i + 1 < STAGES.size():
			_enter_stage(stage_i + 1)
			st = STAGES[stage_i]
		else:
			_finish()
			return
	var u := clampf(stage_t / float(st.dur), 0.0, 1.0)
	match st.id:
		"flyover":
			_pose_flyover(u)
		"sweep":
			_run_sweep(u, dt)
		"swarm":
			_run_swarm(u)
		"rover":
			_run_rover(u)
		"storm":
			_run_storm(u)
	_update_overlay(dt, ft, st)
	if opts.has("bench-screenshots") and not _shots_taken.has(stage_i) and stage_t > float(st.dur) * 0.5:
		_shots_taken[stage_i] = get_viewport().get_texture().get_image()


func _update_overlay(dt: float, ft: float, st: Dictionary) -> void:
	_ov_frames += 1
	_ov_time += ft
	_overlay_t -= dt
	if _overlay_t > 0.0:
		return
	_overlay_t = 0.25
	var fps := _ov_frames * 1000.0 / maxf(_ov_time, 0.001)
	_ov_frames = 0
	_ov_time = 0.0
	overlay.text = "RUSTFALL BENCHMARK  ·  Stage %d/%d: %s  ·  %.1f s\n%.0f FPS  ·  GPU %.2f ms  ·  draws %d" % [
		stage_i + 1, STAGES.size(), st.name, stage_t, fps,
		RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)]


func _record(ft: float) -> void:
	c_time.append(_elapsed)
	c_stage.append(stage_i)
	c_ft.append(ft)
	c_cpu_render.append(RenderingServer.viewport_get_measured_render_time_cpu(_vp_rid) + RenderingServer.get_frame_setup_time_cpu())
	c_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid))
	c_process.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	c_physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	c_draws.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	c_prims.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	c_objects.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)))
	c_vram.append(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0)


# ---------------------------------------------------------------- stages

func _enter_stage(i: int) -> void:
	stage_i = i
	stage_t = 0.0
	match STAGES[i].id:
		"swarm":
			_set_drones(true)
		"rover":
			world.sweeper.autopilot = true
			world.charger.autopilot = true
			world.cart_linked = true
			world.sweeper.engine_sfx.play()
			world.sweeper.camera.far = cam.far
			_run_rover(0.0)
			world.sweeper.snap_camera()
			world.sweeper.camera.current = true
		"storm":
			cam.current = true
			_set_storm(true)


## Creates the stage-specific load up front (hidden) so later stages start without allocation hitches.
func _prepare_extras() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	for k in SWARM_SIZE:
		var home := SWARM_CENTER + Vector3(rng.randf_range(-26, 26), 0, rng.randf_range(-22, 22))
		_swarm.append(world.spawn_drone(k, home))
	_storm = DustFx.make_storm(int(3000 * clampf(float(world.params.particles), 0.35, 1.5)))
	world.add_child(_storm)
	rng.seed = 99
	for k in 16:
		var l := OmniLight3D.new()
		var a := k * TAU / 16.0
		l.position = Vector3(cos(a) * 14.0, 2.5 + rng.randf() * 2.0, sin(a) * 14.0)
		l.light_color = Color.from_hsv(rng.randf_range(0.0, 0.15) if k % 2 == 0 else 0.55, 0.6, 1.0)
		l.omni_range = 10.0
		l.light_energy = 2.0
		l.shadow_enabled = bool(world.params.omni_shadows) and k % 2 == 0
		world.add_child(l)
		_storm_lights.append(l)
	_base_fog = world.env.fog_density
	_base_vol = world.env.volumetric_fog_enabled
	_set_extras(false)


func _set_extras(on: bool) -> void:
	if _extras_on == on:
		return
	_extras_on = on
	_set_drones(on, false)  # visible for shader warmup, but frozen so the run stays deterministic
	for d in _swarm:
		d.fx.emitting = on
	_set_storm(on)
	world.sweeper.autopilot = on
	world.charger.autopilot = on
	if not on:
		world.sweeper.autopilot_place(World.BAYS[0], 0.0, 0.0)
		world.charger.autopilot_place(World.BAYS[1], 0.0, 0.0)
		cam.current = true
	world.cart_linked = on


func _set_drones(on: bool, active := true) -> void:
	# Drones stay in the tree (re-adding 48 nodes in one frame causes a hitch); hidden ones
	# are skipped by the renderer, paused ones cost no script time.
	for d in _swarm:
		d.visible = on
		d.fx.visible = on
		d.process_mode = Node.PROCESS_MODE_INHERIT if on and active else Node.PROCESS_MODE_DISABLED
		d.fx.emitting = false


## Hidden nodes still cost culling work, so inactive extras are detached from the tree entirely.
## Their shaders/pipelines stay cached, so re-attaching them does not hitch.
func _attach(n: Node, on: bool) -> void:
	if on and not n.is_inside_tree():
		world.add_child(n)
	elif not on and n.is_inside_tree():
		world.remove_child(n)


func _set_storm(on: bool) -> void:
	world.env.volumetric_fog_enabled = on or _base_vol
	world.env.volumetric_fog_density = 0.018 if on else 0.006
	world.env.fog_density = 0.012 if on else _base_fog
	_attach(_storm, on)
	_storm.emitting = on
	for l in _storm_lights:
		_attach(l, on)


func _pose_flyover(u: float) -> void:
	var a := lerpf(0.4, 0.4 + TAU * 0.8, u)
	var r := lerpf(46.0, 20.0, u)
	var h := lerpf(24.0, 6.0, u)
	cam.global_position = Vector3(cos(a) * r, h, sin(a) * r)
	cam.look_at(Vector3(0, 2.0, 0))


func _sweep_path(u: float) -> Vector3:
	return Vector3(32.0 + 52.0 * u, 0, 26.0 + 16.0 * sin(u * TAU * 1.5))


func _run_sweep(u: float, dt: float) -> void:
	var p := _sweep_path(u)
	var f := (_sweep_path(minf(u + 0.01, 1.0)) - _sweep_path(maxf(u - 0.01, 0.0)))
	f.y = 0
	f = f.normalized()
	var t := world.terrain
	cam.global_position = Vector3(p.x, t.height_at(p.x, p.z) + 1.7, p.z)
	var aim := p + f * 3.2
	var ground := Vector3(aim.x, t.height_at(aim.x, aim.z), aim.z)
	cam.look_at(ground + Vector3(0, 0.6, 0))
	# Paint a 2.2 m swath like a vacuum lance; side swaths stress the CPU painter further.
	var side := f.cross(Vector3.UP)
	for k in [-1.0, 0.0, 1.0]:
		var q: Vector3 = aim + side * k * 2.6
		world.rust.paint(Vector3(q.x, 0, q.z), 2.2, 4.0 * dt)
	world.player_fx.global_position = ground
	world.player_fx.emitting = true
	world._player_fx_t = 0.2


func _run_swarm(u: float) -> void:
	var c := SWARM_CENTER
	var x := lerpf(-28.0, 28.0, u)
	var gy := world.terrain.height_at(c.x + x, c.z + 26.0)
	cam.global_position = Vector3(c.x + x, gy + 15.0, c.z + 26.0)
	cam.look_at(Vector3(c.x + x * 0.5, world.terrain.height_at(c.x + x * 0.5, c.z), c.z))


func _run_rover(u: float) -> void:
	var a := u * TAU * 1.1
	var r := 30.0
	var pos := SWEEP_CIRCLE + Vector3(cos(a), 0, sin(a)) * r
	var tangent := Vector3(-sin(a), 0, cos(a))
	var heading := atan2(-tangent.x, -tangent.z)
	var spd := r * TAU * 1.1 / float(STAGES[3].dur)
	world.sweeper.autopilot_place(pos, heading, spd)
	# The charger cart drives alongside the sweeper with its charge cable connected.
	var a2 := a + 0.16  # slightly ahead, so its tracks run through the chase camera view
	var pos2 := SWEEP_CIRCLE + Vector3(cos(a2), 0, sin(a2)) * (r + 4.4)  # outside the swept swath so its tracks show
	var t2 := Vector3(-sin(a2), 0, cos(a2))
	world.charger.autopilot_place(pos2, atan2(-t2.x, -t2.z), spd)
	world.sweeper.energy = world.sweeper.battery * 0.5  # keeps the cart charging over the cable


func _run_storm(u: float) -> void:
	var p := Vector3(-26, 0, 22).lerp(Vector3(26, 0, -18), u)
	cam.global_position = Vector3(p.x, world.terrain.height_at(p.x, p.z) + 3.2 + sin(u * PI) * 2.0, p.z)
	cam.look_at(Vector3(0, 2.0, 0).lerp(Vector3(20, 3, -20), u * 0.6))
	_storm.global_position = cam.global_position + Vector3(-25, 0, -8)
	for i in _storm_lights.size():
		_storm_lights[i].light_energy = 1.5 + 1.2 * sin(stage_t * (3.0 + i * 0.37) + i)
	# Keep the rover sweeping off-camera so its systems stay loaded.
	_run_rover(fmod(0.5 + u * 0.5, 1.0))


# ---------------------------------------------------------------- results

func _exit_tree() -> void:
	# Detached extras are not freed with the scene; free them explicitly.
	for n in _storm_lights + [_storm]:
		if is_instance_valid(n) and not n.is_inside_tree():
			n.free()


func _finish() -> void:
	done = true
	running = false
	world.sweeper.autopilot = false
	world.charger.autopilot = false
	world.cart_linked = false
	world.sweeper.engine_sfx.stop()
	var summary := build_summary()
	var dir := _write_results(summary)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if opts.has("bench-windowed") else DisplayServer.WINDOW_MODE_FULLSCREEN)
	_show_results(summary, dir)
	finished.emit(dir)
	if opts.has("bench-autoquit"):
		get_tree().quit()


func system_info() -> Dictionary:
	var drv := OS.get_video_adapter_driver_info()
	var vp := get_viewport()
	# 3D renders at the real window size (the UI canvas is stretched), so report physical pixels.
	var px := DisplayServer.window_get_size()
	var mem := OS.get_memory_info()
	var info := {
		os = OS.get_name(),
		os_version = OS.get_version(),
		os_distribution = OS.get_distribution_name(),
		cpu = OS.get_processor_name(),
		cpu_threads = OS.get_processor_count(),
		ram_gb = snappedf(float(mem.get("physical", 0)) / 1073741824.0, 0.1),
		gpu = RenderingServer.get_video_adapter_name(),
		gpu_vendor = RenderingServer.get_video_adapter_vendor(),
		gpu_api_version = RenderingServer.get_video_adapter_api_version(),
		gpu_driver = _driver_string(drv),
		rendering_driver = str(RenderingServer.call("get_current_rendering_driver_name")) if RenderingServer.has_method("get_current_rendering_driver_name") else str(ProjectSettings.get_setting("rendering/rendering_device/driver")),
		rendering_method = str(ProjectSettings.get_setting("rendering/renderer/rendering_method")),
		display_server = DisplayServer.get_name(),
		window_mode = "windowed" if opts.has("bench-windowed") else ("exclusive_fullscreen" if opts.has("bench-exclusive") else "borderless_fullscreen"),
		resolution = "%dx%d" % [px.x, px.y],
		window_size = "%dx%d" % [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
		render_scale = Config.effective_render_scale(world.params),
		upscaler = Config.effective_upscaler(world.params),
		internal_resolution = "%dx%d" % [roundi(px.x * Config.effective_render_scale(world.params)), roundi(px.y * Config.effective_render_scale(world.params))],
		ui_canvas = "%dx%d" % [vp.get_visible_rect().size.x, vp.get_visible_rect().size.y],
		terrain_chunks = world.terrain.chunks.size(),
		refresh_rate = DisplayServer.screen_get_refresh_rate(),
		vsync = "disabled (forced)",
		engine = Engine.get_version_info().string,
		preset = Config.resolved_preset(),
		benchmark_version = VERSION,
		build = "exported" if OS.has_feature("template") else "editor",
	}
	return info


static func _driver_string(drv: PackedStringArray) -> String:
	var parts := PackedStringArray()
	for p in drv:
		if p.strip_edges() != "":
			parts.append(p.strip_edges())
	if parts.is_empty() and OS.get_name() == "Linux":
		# Mesa version is the useful number on Linux.
		var out := []
		if OS.execute("sh", ["-c", "glxinfo -B 2>/dev/null | grep -m1 'OpenGL version' | sed 's/.*Mesa/Mesa/'"], out) == 0 and out.size() > 0:
			var m := str(out[0]).strip_edges()
			if m != "":
				parts.append(m)
	return " ".join(parts) if parts.size() > 0 else "unknown"


static func stats(ft: PackedFloat64Array) -> Dictionary:
	var n := ft.size()
	if n < 2:
		return {}
	var s := ft.duplicate()
	s.sort()
	var total := 0.0
	for v in ft:
		total += v
	var mean := total / n
	var var_acc := 0.0
	for v in ft:
		var_acc += (v - mean) * (v - mean)
	var sd := sqrt(var_acc / n)
	# Frame pacing: how much each frame differs from the previous one.
	var deltas := PackedFloat64Array()
	deltas.resize(n - 1)
	var dsum := 0.0
	var over2 := 0
	var over4 := 0
	for i in range(1, n):
		var d := absf(ft[i] - ft[i - 1])
		deltas[i - 1] = d
		dsum += d
		if d > 2.0:
			over2 += 1
		if d > 4.0:
			over4 += 1
	deltas.sort()
	# Stutters: frames > 2x the rolling average of the previous 30 frames (and > 4 ms above it).
	var stutters := 0
	var hitches := 0
	var roll := 0.0
	var win := 30
	for i in n:
		if i >= 8:
			var avg := roll / mini(i, win)
			if ft[i] > avg * 2.0 and ft[i] - avg > 4.0:
				stutters += 1
		if i >= win:
			roll -= ft[i - win]
		if ft[i] > 50.0:
			hitches += 1
		roll += ft[i]
	var worst1 := 0.0
	var k1 := maxi(int(n * 0.01), 1)
	for i in k1:
		worst1 += s[n - 1 - i]
	var worst01 := 0.0
	var k01 := maxi(int(n * 0.001), 1)
	for i in k01:
		worst01 += s[n - 1 - i]
	return {
		frames = n,
		duration_s = total / 1000.0,
		avg_fps = 1000.0 * n / total,
		median_fps = 1000.0 / _pct(s, 0.5),
		low_1pct_fps = 1000.0 / (worst1 / k1),
		low_01pct_fps = 1000.0 / (worst01 / k01),
		p99_fps = 1000.0 / _pct(s, 0.99),
		p999_fps = 1000.0 / _pct(s, 0.999),
		min_fps = 1000.0 / s[n - 1],
		max_fps = 1000.0 / s[0],
		ft_avg_ms = mean,
		ft_p50_ms = _pct(s, 0.5),
		ft_p90_ms = _pct(s, 0.9),
		ft_p95_ms = _pct(s, 0.95),
		ft_p99_ms = _pct(s, 0.99),
		ft_p999_ms = _pct(s, 0.999),
		ft_max_ms = s[n - 1],
		ft_stddev_ms = sd,
		ft_cv_pct = sd / mean * 100.0,
		pacing_avg_delta_ms = dsum / (n - 1),
		pacing_p95_delta_ms = _pct(deltas, 0.95),
		pacing_p99_delta_ms = _pct(deltas, 0.99),
		pacing_delta_over_2ms_pct = 100.0 * over2 / (n - 1),
		pacing_delta_over_4ms_pct = 100.0 * over4 / (n - 1),
		stutters = stutters,
		hitches_over_50ms = hitches,
	}


static func _pct(sorted: PackedFloat64Array, q: float) -> float:
	var n := sorted.size()
	return sorted[clampi(int(ceil(q * n)) - 1, 0, n - 1)]


static func _avg(a: PackedFloat64Array) -> float:
	if a.is_empty():
		return 0.0
	var t := 0.0
	for v in a:
		t += v
	return t / a.size()


func _stage_extra(idx: int) -> Dictionary:
	var gpu := PackedFloat64Array()
	var cpu := PackedFloat64Array()
	var proc := PackedFloat64Array()
	var phys := PackedFloat64Array()
	var draws := PackedFloat64Array()
	var prims := PackedFloat64Array()
	var vram_max := 0.0
	for i in c_ft.size():
		if idx >= 0 and c_stage[i] != idx:
			continue
		gpu.append(c_gpu[i])
		cpu.append(c_cpu_render[i])
		proc.append(c_process[i])
		phys.append(c_physics[i])
		draws.append(c_draws[i])
		prims.append(c_prims[i])
		vram_max = maxf(vram_max, c_vram[i])
	var sg := gpu.duplicate()
	sg.sort()
	return {
		gpu_avg_ms = _avg(gpu), gpu_p99_ms = _pct(sg, 0.99) if sg.size() > 0 else 0.0,
		cpu_render_avg_ms = _avg(cpu), process_avg_ms = _avg(proc), physics_avg_ms = _avg(phys),
		draw_calls_avg = _avg(draws), primitives_avg = _avg(prims), vram_max_mb = vram_max,
	}


func build_summary() -> Dictionary:
	var stages_out := []
	for i in STAGES.size():
		var ft := PackedFloat64Array()
		for k in c_ft.size():
			if c_stage[k] == i:
				ft.append(c_ft[k])
		var d := stats(ft)
		d.merge(_stage_extra(i))
		d["id"] = STAGES[i].id
		d["name"] = STAGES[i].name
		d["description"] = STAGES[i].desc
		stages_out.append(d)
	var overall := stats(c_ft)
	overall.merge(_stage_extra(-1))
	return {
		timestamp = Time.get_datetime_string_from_system(false, true),
		system = system_info(),
		overall = overall,
		stages = stages_out,
		rust_cleaned_kg = world.cleaned_kg_total,
		texture_uploads = world.rust.uploads,
		track_chunks = world.rust.tracks.size(),
	}


func _results_root() -> String:
	if opts.has("bench-out"):
		return str(opts["bench-out"])
	if OS.has_feature("template"):
		# build/<os>/Rustfall(.exe) -> build/benchmark_results (shared by both OS on a common drive)
		return OS.get_executable_path().get_base_dir().path_join("../benchmark_results").simplify_path()
	return ProjectSettings.globalize_path("res://build/benchmark_results")


func _write_results(summary: Dictionary) -> String:
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var name := "%s_%s_%s_%s%d" % [stamp, OS.get_name(), Config.resolved_preset(), Config.effective_upscaler(world.params),
		roundi(Config.effective_render_scale(world.params) * 100)]
	var dir := _results_root().path_join(name)
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		dir = ProjectSettings.globalize_path("user://benchmark_results").path_join(name)
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("summary.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(summary, "  "))
	f.close()
	var csv := FileAccess.open(dir.path_join("frames.csv"), FileAccess.WRITE)
	csv.store_line("frame,time_s,stage,frametime_ms,fps,cpu_render_ms,gpu_ms,godot_time_process_ms,physics_ms,draw_calls,primitives,objects,vram_mb")
	for i in c_ft.size():
		csv.store_line("%d,%.4f,%s,%.4f,%.2f,%.4f,%.4f,%.4f,%.4f,%d,%d,%d,%.1f" % [
			i, c_time[i], STAGES[c_stage[i]].id, c_ft[i], 1000.0 / maxf(c_ft[i], 0.001), c_cpu_render[i],
			c_gpu[i], c_process[i], c_physics[i], c_draws[i], c_prims[i], c_objects[i], c_vram[i]])
	csv.close()
	var txt := FileAccess.open(dir.path_join("summary.txt"), FileAccess.WRITE)
	txt.store_string(text_report(summary))
	txt.close()
	for k in _shots_taken:
		(_shots_taken[k] as Image).save_png(dir.path_join("stage%d_%s.png" % [k + 1, STAGES[k].id]))
	print(text_report(summary))
	print("Benchmark results written to: ", dir)
	return dir


static func text_report(s: Dictionary) -> String:
	var sys: Dictionary = s.system
	var o: Dictionary = s.overall
	var lines := PackedStringArray()
	lines.append("RUSTFALL BENCHMARK %s  —  %s" % [sys.benchmark_version, s.timestamp])
	lines.append("OS: %s %s (%s)   Display: %s %s" % [sys.os, sys.os_version, sys.os_distribution, sys.display_server, sys.resolution])
	lines.append("CPU: %s (%d threads)   RAM: %.1f GB" % [sys.cpu, sys.cpu_threads, sys.ram_gb])
	lines.append("GPU: %s   Driver: %s   API: %s %s" % [sys.gpu, sys.gpu_driver, sys.rendering_driver, sys.gpu_api_version])
	lines.append("Preset: %s   Upscaler: %s @ %.2f (internal %s)   Engine: %s" % [sys.preset, sys.upscaler, sys.render_scale, sys.internal_resolution, sys.engine])
	lines.append("")
	lines.append("%-16s %8s %8s %8s %9s %9s %8s %8s %8s %8s" % ["Stage", "Avg FPS", "1% low", "0.1%low", "p99 ms", "SD ms", "Pace ms", "Stutter", "GPU ms", "Draws"])
	var rows: Array = s.stages.duplicate()
	var ov := o.duplicate()
	ov["name"] = "OVERALL"
	rows.append(ov)
	for r in rows:
		lines.append("%-16s %8.1f %8.1f %8.1f %9.2f %9.2f %8.2f %8d %8.2f %8.0f" % [
			r.name, r.avg_fps, r.low_1pct_fps, r.low_01pct_fps, r.ft_p99_ms, r.ft_stddev_ms,
			r.pacing_avg_delta_ms, r.stutters, r.gpu_avg_ms, r.draw_calls_avg])
	return "\n".join(lines) + "\n"


func _show_results(s: Dictionary, dir: String) -> void:
	overlay.text = ""
	var cl := CanvasLayer.new()
	cl.layer = 20
	add_child(cl)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = UiKit.theme()
	cl.add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var vb := UiKit.centered_panel(root, Vector2(1100, 0))
	var o: Dictionary = s.overall
	var sys: Dictionary = s.system
	vb.add_child(UiKit.label("Benchmark complete", 30, UiKit.ACCENT))
	vb.add_child(UiKit.label("%.1f avg FPS   ·   %.1f 1%% low   ·   %.1f 0.1%% low   ·   %d stutters" % [o.avg_fps, o.low_1pct_fps, o.low_01pct_fps, o.stutters], 22))
	vb.add_child(UiKit.label("%s · %s · %s · %s · preset %s @ %s · %s %d%%" % [sys.os, sys.gpu, sys.rendering_driver, sys.display_server,
		sys.preset, sys.resolution, sys.upscaler.to_upper(), roundi(sys.render_scale * 100)], 15, UiKit.MUTED))
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 22)
	vb.add_child(grid)
	for h in ["Stage", "Avg FPS", "1% low", "0.1% low", "p99 frame", "Frame SD", "Pacing Δ", "GPU"]:
		grid.add_child(UiKit.label(h, 15, UiKit.ACCENT2))
	for r in s.stages:
		for v in [r.name, "%.1f" % r.avg_fps, "%.1f" % r.low_1pct_fps, "%.1f" % r.low_01pct_fps,
				"%.2f ms" % r.ft_p99_ms, "%.2f ms" % r.ft_stddev_ms, "%.2f ms" % r.pacing_avg_delta_ms, "%.2f ms" % r.gpu_avg_ms]:
			grid.add_child(UiKit.label(str(v), 16))
	var path_lbl := UiKit.label("Saved to: %s" % dir, 14, UiKit.MUTED)
	path_lbl.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	vb.add_child(path_lbl)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	vb.add_child(hb)
	hb.add_child(UiKit.button("Open results folder", func() -> void: OS.shell_open(dir)))
	hb.add_child(UiKit.button("Main menu", func() -> void: world.quit_to_menu.emit()))
	hb.add_child(UiKit.button("Quit", func() -> void: get_tree().quit()))
