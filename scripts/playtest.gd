class_name Playtest
extends Node
## Developer playtest (--playtest=DIR): drives the supply pod, repair kit / battery cell and paint
## shop flows through the real input and UI paths, checks the results and saves screenshots.

var world: World
var out_dir := ""
var passed := 0
var failed := 0


func run() -> void:
	seed(1234)
	DirAccess.make_dir_recursive_absolute(out_dir)
	await _frames(30)
	await _pod_flow()
	await _kit_flow()
	await _paint_flow()
	await _key_guide_flow()
	await _torch_flow()
	await _save_flow()
	await _worlds_flow()
	await _menu_flow()
	print("PLAYTEST RESULT: %d passed, %d failed" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


# ---------------------------------------------------------------- helpers

func check(ok: bool, what: String) -> void:
	if ok:
		passed += 1
		print("  PASS  ", what)
	else:
		failed += 1
		print("  FAIL  ", what)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _press(action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	await _frames(2)
	var r := InputEventAction.new()
	r.action = action
	r.pressed = false
	Input.parse_input_event(r)
	await _frames(2)


func _shot(name: String) -> void:
	await _frames(3)
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))


func _stand_near(p: Vector3, offset: Vector3, look_at_point: Vector3) -> void:
	var at := p + offset
	world.player.global_position = Vector3(at.x, world.terrain.height_at(at.x, at.z) + 0.3, at.z)
	world.player.velocity = Vector3.ZERO
	var d := look_at_point - at
	world.player.yaw = atan2(-d.x, -d.z)
	world.player.pitch = -0.25
	await _frames(6)


func _find_button(title_part: String) -> Button:
	for row in world.hud.shop_list.get_children():
		if not row is HBoxContainer:
			continue
		var title: Label = row.get_child(0).get_child(0)
		if title.text.contains(title_part):
			var last := row.get_child(row.get_child_count() - 1)
			return last as Button
	return null


# ---------------------------------------------------------------- flows

func _pod_flow() -> void:
	print("[supply pod]")
	var s := world.state
	world._pod_timer = 0.0
	await _frames(2)
	check(world.pod != null, "a pod is scheduled and spawned when the timer runs out")
	var land := Vector3(30, 0, 28)
	land.y = world.terrain.height_at(land.x, land.z)
	world.pod.target = land
	await _stand_near(land, Vector3(0, 0, 9), land)
	check(not world.pod.landed, "pod is still descending right after spawning")
	await get_tree().create_timer(SupplyPod.FALL_TIME + 0.6).timeout
	check(world.pod.landed, "pod lands after its descent")
	check(world.pod.beacon != null, "landed pod shows a beacon")
	await _shot("1_pod_landed")
	await _stand_near(land, Vector3(0, 0, 2.6), land)
	check(world._act == "open_pod", "standing next to the pod offers [E] Open (prompt: %s)" % world.hud.prompt_lbl.text)
	var credits0 := s.credits
	var kits0 := s.repair_kits
	var cells0 := s.battery_cells
	var pod_ref := world.pod
	await _press("interact")
	check(s.pods_opened == 1, "opening counts the pod")
	check(s.credits > credits0 + 2999.0, "pod pays at least ₹3,000 (got %s)" % GameState.inr(s.credits - credits0))
	check(world.pod == null, "world no longer tracks the opened pod")
	print("        loot: %s, kits +%d, cells +%d" % [GameState.inr(s.credits - credits0), s.repair_kits - kits0, s.battery_cells - cells0])
	await _shot("2_pod_opened")
	await get_tree().create_timer(0.8).timeout
	check(not is_instance_valid(pod_ref), "opened pod is removed from the world")
	await _press("interact")
	check(s.pods_opened == 1, "pressing E again where the pod was does nothing")


func _kit_flow() -> void:
	print("[repair kits and battery cells]")
	var s := world.state
	s.sweeper_owned = true
	world._set_vehicle_present(world.sweeper, true)
	var v := world.sweeper
	v.cond.tyres = 0.2
	v.cond.motor = 0.9
	v.energy = 2.0
	s.repair_kits = 0
	s.battery_cells = 0
	await _stand_near(v.global_position, Vector3(3.0, 0, 0), v.global_position)
	check(not world.hud.prompt_lbl.text.contains("[G]"), "no kit hint when you have no kits")
	await _press("use_kit")
	check(is_equal_approx(float(v.cond.tyres), 0.2), "G with no kits changes nothing")
	s.repair_kits = 2
	s.battery_cells = 1
	await _frames(4)
	check(world.hud.prompt_lbl.text.contains("[G] repair kit ×2") and world.hud.prompt_lbl.text.contains("[B] battery cell ×1"),
		"prompt lists kits and cells (prompt: %s)" % world.hud.prompt_lbl.text)
	await _press("use_kit")
	check(is_equal_approx(float(v.cond.tyres), 0.7), "kit repairs the worst part (tyres 20%% -> %d%%)" % roundi(float(v.cond.tyres) * 100.0))
	check(s.repair_kits == 1, "one kit used")
	await _press("use_kit")
	check(is_equal_approx(float(v.cond.tyres), 1.0) or is_equal_approx(float(v.cond.motor), 1.0), "second kit goes to the next-worst part")
	check(s.repair_kits == 0, "both kits used")
	await _press("use_cell")
	check(is_equal_approx(v.energy, 12.0), "cell adds 10 kWh (2 -> %.1f kWh)" % v.energy)
	check(s.battery_cells == 0, "cell used")
	s.battery_cells = 1
	v.energy = v.battery - 1.0
	await _press("use_cell")
	check(is_equal_approx(v.energy, v.battery), "cell never overfills the battery")
	# Kits work on a plugged-in vehicle too (you stand next to it at the post).
	s.repair_kits = 1
	v.cond.brush = 0.1
	world.plugged[v] = 0
	await _stand_near(v.global_position, Vector3(3.0, 0, 0), v.global_position)
	await _press("use_kit")
	check(float(v.cond.brush) > 0.5, "kit works while the vehicle is plugged in")
	world.plugged.erase(v)
	# Far away: keys do nothing.
	s.repair_kits = 1
	v.cond.tyres = 0.3
	await _stand_near(v.global_position, Vector3(15.0, 0, 0), v.global_position)
	await _press("use_kit")
	check(s.repair_kits == 1 and is_equal_approx(float(v.cond.tyres), 0.3), "G does nothing away from vehicles")


func _paint_flow() -> void:
	print("[paint shop]")
	var s := world.state
	var v := world.sweeper
	v.cond.tyres = 1.0
	v.cond.brush = 1.0
	v.cond.motor = 1.0
	s.credits = 50000.0
	await _stand_near(World.TERMINAL, Vector3(2.0, 0, 0), World.TERMINAL)
	check(world._act == "shop", "terminal offers the shop")
	await _press("interact")
	check(world.hud.shop_layer.visible and world.ui_open, "terminal opens")
	var b := _find_button("Sweeper: Saffron Strike")
	check(b != null and b.text.contains("15,000"), "Saffron Strike is listed at ₹15,000 (%s)" % (b.text if b else "missing"))
	check(_find_button("Charger cart: Saffron Strike") == null, "no paint jobs for a vehicle you don't own")
	b.pressed.emit()
	await _frames(3)
	check(s.livery.sweeper == "saffron", "buying applies the paint job")
	check(is_equal_approx(s.credits, 35000.0), "₹15,000 charged (balance %s)" % GameState.inr(s.credits))
	await get_tree().create_timer(0.2).timeout
	check(world.hud.credits_lbl.text == "₹35,000", "HUD balance updates while the terminal is open (%s)" % world.hud.credits_lbl.text)
	check((v._paint[0][1] as Color).is_equal_approx(GameState.LIVERIES[1].primary), "sweeper body uses the Saffron colour")
	var applied := _find_button("Sweeper: Saffron Strike")
	check(applied == null, "applied paint shows no button")
	var factory := _find_button("Sweeper: Factory")
	check(factory != null and factory.text == "Apply", "owned Factory paint shows a free Apply button")
	await _shot("3_paint_shop")
	factory.pressed.emit()
	await _frames(3)
	check(s.livery.sweeper == "factory" and is_equal_approx(s.credits, 35000.0), "switching back to Factory is free")
	var again := _find_button("Sweeper: Saffron Strike")
	check(again != null and again.text == "Apply", "bought paint can be re-applied for free")
	again.pressed.emit()
	await _frames(3)
	check(s.livery.sweeper == "saffron" and is_equal_approx(s.credits, 35000.0), "re-applying costs nothing")
	s.credits = 100.0
	world.hud._refresh_shop()
	await _frames(2)
	var chrome := _find_button("Sweeper: Chrome Rover")
	check(chrome != null and chrome.disabled, "too expensive paint is disabled")
	await _press("pause")
	check(not world.hud.shop_layer.visible and not world.ui_open, "Esc closes the terminal")
	await _stand_near(v.global_position, Vector3(4.0, 0, 3.5), v.global_position + Vector3(0, 0.8, 0))
	world.hud.visible = false
	await _shot("4_saffron_sweeper")
	world.hud.visible = true


func _key_guide_flow() -> void:
	print("[key guide]")
	await _press("key_guide")
	check(world.hud.key_guide.visible and not world.hud.key_guide.driving, "F1 opens the key guide (on-foot view)")
	await _shot("5_key_guide")
	await _press("key_guide")
	check(not world.hud.key_guide.visible, "F1 again closes it")
	await _press("key_guide")
	await _press("pause")
	check(not world.hud.key_guide.visible and not get_tree().paused, "Esc closes the key guide without opening the pause menu")


func _worlds_flow() -> void:
	print("[worlds]")
	check(Worlds.root == "user://dev/worlds/", "playtest worlds live in the developer folder")
	var a: String = Worlds.list()[0].id
	check(GameState.save_dir == Worlds.dir_of(a), "the running world saves into its own folder")
	check(Worlds.parse_seed("12345") == 12345, "a number seed is used as-is")
	check(Worlds.parse_seed("mars") == Worlds.parse_seed("mars") and Worlds.parse_seed("mars") != Worlds.parse_seed("moon"), "word seeds are stable and distinct")
	var b := Worlds.create("Second colony", "777")
	var c := Worlds.create("", "")
	check(Worlds.read_meta(c).name == "Colony 1", "blank name gets a default (%s)" % Worlds.read_meta(c).name)
	check(Worlds.list().size() == 3, "three worlds listed")
	check(Worlds.list()[0].id == a, "the world with progress is listed first")
	Worlds.select(b)
	check(not GameState.has_save(), "a new world starts without a save")
	Worlds.select(a)
	check(GameState.has_save(), "the first world still has its save")
	# Different seeds give different terrain.
	var t1 := Terrain.new()
	t1.seed_value = 4242
	t1.setup()
	var t2 := Terrain.new()
	t2.seed_value = 777
	t2.setup()
	var differs := false
	for i in 8:
		if absf(t1.height_at(60.0 + i * 37.0, -80.0) - t2.height_at(60.0 + i * 37.0, -80.0)) > 0.05:
			differs = true
	check(differs, "different seeds make different terrain")
	t1.free()
	t2.free()
	Worlds.rename(b, "  Red Valley  ")
	check(Worlds.read_meta(b).name == "Red Valley", "rename trims and saves the name")
	Worlds.rename(b, "   ")
	check(Worlds.read_meta(b).name == "Red Valley", "a blank rename is ignored")
	Worlds.delete(c)
	check(Worlds.read_meta(c).is_empty() and not DirAccess.dir_exists_absolute(Worlds.dir_of(c)), "delete removes the world folder")
	check(Worlds.select(a).name == "Dev world", "deleting one world leaves the others alone")
	# Legacy single save -> its own world.
	DirAccess.make_dir_recursive_absolute("user://dev/legacy/")
	DirAccess.copy_absolute(Worlds.dir_of(a) + "save.json", "user://dev/legacy/save.json")
	DirAccess.copy_absolute(Worlds.dir_of(a) + "save_rust.bin", "user://dev/legacy/save_rust.bin")
	var m := Worlds.migrate_legacy("user://dev/legacy/")
	check(m != "" and FileAccess.file_exists(Worlds.dir_of(m) + "save.json") and not FileAccess.file_exists("user://dev/legacy/save.json"),
		"an old single save moves into a world called %s" % Worlds.read_meta(m).get("name", "?"))
	check(Worlds.read_meta(m).seed == 4242, "the migrated world keeps the old terrain seed")
	Worlds.delete(m)
	Worlds.select(a)


func _menu_flow() -> void:
	print("[world menu]")
	world.hud.visible = false
	var menu := MainMenu.new()
	var played := []
	menu.play_world.connect(func(id: String, is_new: bool) -> void: played.append([id, is_new]))
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	layer.add_child(menu)
	await _frames(3)
	var cont: Button = menu._main.get_child(0)
	check(cont.text == "Continue: Dev world", "Continue offers the last played world (%s)" % cont.text)
	menu.show_worlds()
	await _frames(3)
	check(menu._world_list.get_child_count() == 2, "world list shows both worlds")
	await _shot("6_worlds")
	var row: Control = menu._world_list.get_child(1)
	var hb: HBoxContainer = row.get_child(0)
	var del: Button = hb.get_child(3)
	del.pressed.emit()
	check(del.text == "Sure?" and Worlds.list().size() == 2, "first Delete click only asks to confirm")
	del.pressed.emit()
	await _frames(3)
	check(Worlds.list().size() == 1 and menu._world_list.get_child_count() == 1, "second click deletes the world")
	var rename_btn: Button = (menu._world_list.get_child(0).get_child(0) as HBoxContainer).get_child(2)
	rename_btn.pressed.emit()
	await _frames(2)
	var info: VBoxContainer = (menu._world_list.get_child(0).get_child(0) as HBoxContainer).get_child(0)
	var edit: LineEdit = info.get_child(0)
	edit.text = "Olympus Base"
	edit.text_submitted.emit(edit.text)
	await _frames(3)
	check(Worlds.list()[0].name == "Olympus Base", "rename in the list works")
	var play: Button = (menu._world_list.get_child(0).get_child(0) as HBoxContainer).get_child(1)
	play.pressed.emit()
	check(played.size() == 1 and played[0][0] == Worlds.list()[0].id and played[0][1] == false, "Play opens that world (not as new)")
	menu._show(menu._create)
	await _frames(2)
	check(menu._name_edit.placeholder_text == "Colony 1", "create screen suggests a name")
	menu._name_edit.text = "Hellas Camp"
	menu._seed_edit.text = "dusty"
	await _shot("7_create_world")
	menu._seed_edit.text_submitted.emit("dusty")
	await _frames(2)
	var made := Worlds.read_meta(played[-1][0])
	check(played.size() == 2 and played[-1][1] == true and made.name == "Hellas Camp" and made.seed == Worlds.parse_seed("dusty"),
		"Create & play makes the world with that name and seed and starts it as new")
	layer.queue_free()


func _torch_flow() -> void:
	print("[torch]")
	var p := world.player
	world.state.time_of_day = 0.0  # midnight
	await _stand_near(Vector3(20, 0, 30), Vector3.ZERO, Vector3(20, 0, 10))
	p.pitch = -0.3
	await get_tree().create_timer(0.3).timeout
	check(not p.torch_on and not p.torch_light.visible, "torch starts off")
	check(world.hud.toast_box.get_children().any(func(c: Node) -> bool: return c is Label and (c as Label).text.contains("Press L")), "at night the game hints to press L")
	await _shot("8a_night_no_torch")
	await _press("torch")
	await _frames(10)
	check(p.torch_on and p.torch_light.visible, "L turns the torch on")
	await _shot("8b_night_torch")
	await _press("torch")
	check(not p.torch_light.visible, "L again turns it off")
	await _press("torch")
	var v := world.sweeper
	world.plugged.erase(v)
	p.set_active(false)
	v.set_driving(true)
	await _frames(4)
	check(not p.torch_light.visible, "torch beam is hidden while driving")
	await _press("torch")
	var lit := v.headlights_lit()
	await _press("torch")
	check(lit != v.headlights_lit(), "L while driving toggles the headlights")
	world._exit_vehicle(v)
	await _frames(4)
	check(p.torch_light.visible, "torch comes back on when you get out")
	world.state.time_of_day = 0.35


func _save_flow() -> void:
	print("[save and reload]")
	var s := world.state
	s.repair_kits = 3
	s.battery_cells = 2
	world.save_game()
	var loaded := GameState.new()
	var r := RustField.new()
	r.setup(world.seed_value)
	loaded.load_into(r)
	check(loaded.livery.sweeper == "saffron", "paint job survives a reload")
	check((loaded.liveries.sweeper as Array).has("saffron"), "owned paint jobs survive a reload")
	check(loaded.repair_kits == 3 and loaded.battery_cells == 2, "kits and cells survive a reload")
	check(loaded.pods_opened == 1, "opened pod count survives a reload")
