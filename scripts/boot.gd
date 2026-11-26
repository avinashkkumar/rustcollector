extends Node
## Entry point. Shows the menu, or runs the benchmark directly when launched with --run-benchmark.
##
## Command line (after the executable, or after "--" when running from the editor):
##   --run-benchmark              start the benchmark immediately
##   --bench-preset=low|medium|high|ultra   (default: high)
##   --bench-windowed=1920x1080   run windowed at this size instead of exclusive fullscreen
##   --bench-scale=0.67           override render scale (FSR quality modes: 0.77, 0.67, 0.59, 0.5)
##   --bench-upscaler=off|fsr1|fsr2  choose the upscaler (default: preset/auto)
##   --bench-out=/path/to/dir     where results go (default: build/benchmark_results)
##   --bench-autoquit             exit when finished (for scripted runs)
##   --playtest=DIR               developer: automated playtest of pods, kits and the paint shop

var current: Node
var _story_shown := false


func _ready() -> void:
	var args := parse_args()
	if args.has("playtest") or args.has("debug-shot"):
		GameState.save_dir = "user://dev/"  # never overwrite or delete the player's real save
	if args.has("playtest"):
		_story_shown = true
		start_game(false)
		var pt := Playtest.new()
		pt.world = current
		pt.out_dir = str(args["playtest"])
		add_child(pt)
		pt.run()
	elif args.has("debug-shot"):
		_debug_shot(str(args["debug-shot"]), float(args.get("debug-shot-delay", 4.0)), str(args.get("debug-shot-scene", "play")))
	elif args.has("run-benchmark"):
		start_benchmark(str(args.get("bench-preset", "high")), args)
	else:
		show_menu()


static func parse_args() -> Dictionary:
	var d := {}
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			d[kv[0]] = kv[1] if kv.size() > 1 else "true"
	return d


func _swap(n: Node) -> void:
	if current:
		current.queue_free()
	get_tree().paused = false
	current = n
	add_child(n)


func show_menu() -> void:
	Config.override_preset = ""
	Config.override_render_scale = -1.0
	Config.override_upscaler = ""
	Config.apply_display()
	var m := MainMenu.new()
	m.new_game.connect(func() -> void: start_game(false))
	m.continue_game.connect(func() -> void: start_game(true))
	m.run_benchmark.connect(func(p: String) -> void: start_benchmark(p, {}))
	_swap(m)


func start_game(load_save: bool) -> void:
	if not load_save:
		GameState.delete_save()
		if not _story_shown:
			_story_shown = true
			var st := Story.new()
			st.finished.connect(func() -> void: start_game.call_deferred(false))
			_swap(st)
			return
	_story_shown = false
	var w := World.new()
	w.mode = "play"
	w.load_save = load_save
	w.quit_to_menu.connect(func() -> void: show_menu.call_deferred())
	_swap(w)


func start_benchmark(preset: String, args: Dictionary) -> void:
	Config.override_preset = preset if preset in Config.PRESETS else "high"
	Config.override_render_scale = float(args.get("bench-scale", -1.0))
	Config.override_upscaler = str(args.get("bench-upscaler", ""))
	var holder := Node.new()
	var w := World.new()
	w.mode = "benchmark"
	holder.add_child(w)
	var b := Benchmark.new()
	b.world = w
	b.opts = args
	holder.add_child(b)
	w.quit_to_menu.connect(func() -> void: show_menu.call_deferred())
	_swap(holder)


## Developer helper: open a scene, wait, save a screenshot, quit.
func _debug_shot(path: String, delay: float, scene: String) -> void:
	if scene == "menu":
		show_menu()
	elif scene == "story":
		_story_shown = false
		start_game(false)
	else:
		_story_shown = true
		start_game(false)
	await get_tree().create_timer(delay).timeout
	if scene == "drive" and current is World:
		var w: World = current
		w.state.sweeper_owned = true
		w.state.panels = 6
		w._set_vehicle_present(w.sweeper, true)
		w._refresh_solar()
		w.sweeper.heading = PI  # facing out of the garage
		w.sweeper.rotation.y = PI
		w.player.set_active(false)
		w.sweeper.set_driving(true)
		Input.action_press("move_forward")
		for i in 150:
			if i == 40:
				Input.action_press("move_left")
			if i == 90:
				Input.action_release("move_left")
				Input.action_press("sprint")
			await get_tree().process_frame
		Input.action_release("move_forward")
		Input.action_release("sprint")
	if (scene == "rover" or scene == "tracks") and current is World:
		var w: World = current
		w.state.sweeper_owned = true
		w.sweeper.tool_on = scene != "tracks"
		w._set_vehicle_present(w.sweeper, true)
		w.sweeper.cond.tyres = 0.3
		w.sweeper.cond.motor = 0.2
		w.sweeper.heading = PI
		w.sweeper.rotation.y = PI
		w.player.set_active(false)
		w.sweeper.set_driving(true)
		Input.action_press("move_forward")
		for i in (260 if scene == "tracks" else 160):
			if i == 60 and scene != "tracks":
				Input.action_press("move_left")
			if i == 150 and scene == "tracks":
				Input.action_press("move_right")
			await get_tree().process_frame
		Input.action_release("move_forward")
		Input.action_release("move_left")
		Input.action_release("move_right")
		for i in 20:
			await get_tree().process_frame
		var cam := Camera3D.new()
		w.add_child(cam)
		var vp := w.sweeper.global_position
		if scene == "tracks":
			cam.global_position = vp + w.sweeper.forward() * 3.0 + w.sweeper.right() * 3.0 + Vector3(0, 6.5, 0)
			cam.look_at(vp - w.sweeper.forward() * 9.0)
		else:
			cam.global_position = vp + w.sweeper.right() * 4.2 + w.sweeper.forward() * 1.5 + Vector3(0, 1.1, 0)
			cam.look_at(vp + Vector3(0, 0.6, 0))
		cam.fov = 60.0
		cam.current = true
		w.hud.visible = false
		await get_tree().create_timer(0.3).timeout
	if scene == "features" and current is World:
		var w: World = current
		w.state.earned = 320000.0
		w.state.credits = 320000.0
		w.player.global_position = Vector3(30, w.terrain.height_at(30, 30) + 1.0, 30)
		w.player.yaw = 0.0
		w.player.pitch = -0.05
		w._pod_timer = 0.0
		await get_tree().process_frame
		await get_tree().process_frame
		w.pod.target = Vector3(28, w.terrain.height_at(28, 12), 12)
		await get_tree().create_timer(10.5).timeout
		w.player.yaw = 0.6
		await get_tree().process_frame
		w._place_waypoint()
		w.player.yaw = 0.15
		w.state.sol_kg = {you = 120.0, sweeper = 380.0, drones = 90.0}
		w.hud.sol_report(w._sol_summary())
		await get_tree().create_timer(1.0).timeout
	if scene == "clean" and current is World:
		var w: World = current
		w.player.global_position = Vector3(42, w.terrain.height_at(42, 30) + 1.0, 30)
		await get_tree().create_timer(0.5).timeout
		for i in 90:
			w.player.pitch = -0.6
			Input.action_press("clean")
			await get_tree().process_frame
			w.player.yaw += 0.02
		Input.action_release("clean")
		await get_tree().create_timer(0.3).timeout
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()
