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
	await _progression_flow()
	await _cart_flow()
	await _torch_flow()
	await _infra_flow()
	await _panel_flow()
	await _speed_flow()
	await _depot_drive_flow()
	await _sack_flow()
	await _sleep_flow()
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
	await _finish_job()


## Unloading takes a few seconds now: wait for any job the press started (up to 15 s).
func _finish_job() -> void:
	var t := 0.0
	while world and is_instance_valid(world) and world.busy() and t < 15.0:
		await get_tree().process_frame
		t += get_process_delta_time()
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
	world.hud.shop_tab = "Paint"
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
	var b := Worlds.create("Second colony", "777", "hard")
	check(Worlds.read_meta(b).difficulty == "hard", "a world remembers its difficulty")
	var c := Worlds.create("", "")
	world.save_game()  # keep playing the first world after creating the others
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


func _open_tab(tab: String) -> void:
	world.hud.shop_tab = tab
	if not world.hud.shop_layer.visible:
		world.hud.open_shop()
	else:
		world.hud._refresh_shop()
	await _frames(2)


func _row_lock(title_part: String) -> String:
	for row in world.hud.shop_list.get_children():
		if row is HBoxContainer:
			var vb: VBoxContainer = row.get_child(0)
			if (vb.get_child(0) as Label).text.contains(title_part):
				for c in vb.get_children():
					if c is Label and (c as Label).text.begins_with("Locked: "):
						return (c as Label).text
				return ""
	return "missing"


func _progression_flow() -> void:
	print("[progression]")
	var s := world.state
	s.credits = 500000.0
	s.earned = 0.0
	s.tool_lvl = 0
	s.mods = {power = 0, width = 0, reach = 0}
	s.mastery_kg = {}
	s.hexes_cleared = []
	s.sweeper_owned = false
	world._set_vehicle_present(world.sweeper, false)
	# Tabs.
	await _open_tab("Tools")
	check(world.hud._tab_bar.get_child_count() == 7, "terminal has 7 category tabs")
	check(_row_lock("Wider head").contains("mastery"), "width is locked until the tool earns a mastery star (%s)" % _row_lock("Wider head"))
	await _shot("9a_tools_tab_locked")
	var kg_needed := s.mastery_next_kg()
	check(kg_needed > 50.0, "first mastery star needs real cleaning (%.0f kg)" % kg_needed)
	s.mastery_kg["0"] = kg_needed + 1.0
	check(s.mastery_level() == 1, "cleaning that much earns ★1")
	await _open_tab("Tools")
	check(_row_lock("Wider head") == "", "★1 unlocks width level 1")
	var b := _find_button("Wider head")
	b.pressed.emit()
	await _frames(2)
	check(s.mods.width == 1 and _row_lock("Wider head").contains("★★"), "width level 2 needs ★2 (%s)" % _row_lock("Wider head"))
	check(is_equal_approx(s.tool().radius, 0.45 * 1.06), "width level adds only 6%% radius (%.3f m)" % s.tool().radius)
	check(world.price("tool") > 0, "Push Broom has no rank lock")
	s.tool_lvl = 1
	check(world.lock_reason("tool").contains("Dust Walker"), "Air Blower needs rank Dust Walker (%s)" % world.lock_reason("tool"))
	# Machines.
	await _open_tab("Vehicles")
	var lock := _row_lock("Sweeper")
	check(lock.contains("Grit Grinder") and lock.contains("25 more hexagons"), "Sweeper locked behind rank and 25 hexagons (%s)" % lock)
	check(_row_lock("Charger cart").contains("own the Sweeper"), "Charger cart needs the Sweeper first")
	await _shot("9b_vehicles_locked")
	s.earned = 70000.0
	for i in 24:
		s.hexes_cleared.append("t:%d" % i)
	check(world.lock_reason("sweeper") == "1 more hexagon cleared", "24 hexagons is not enough (%s)" % world.lock_reason("sweeper"))
	s.hexes_cleared.append("t:24")
	check(world.lock_reason("sweeper") == "" and world.price("sweeper") == 90000, "rank + 25 hexagons unlocks the Sweeper at ₹90,000")
	await _open_tab("Drones")
	check(_row_lock("Cleaning drone").contains("Hex Hunter"), "drones need rank Hex Hunter")
	world.hud.close_shop()
	# Crust.
	check(s.crust_at(0, 0) == 0 and s.crust_at(200, 0) == 1 and s.crust_at(0, 450) == 2 and s.crust_at(700, 0) == 3, "crust rings at 140 / 320 / 600 m")
	check(is_equal_approx(GameState.crust_factor(0, 1), 0.25) and GameState.crust_factor(1, 1) == 1.0, "under-tier tool cleans at 25% per missing tier")
	await _stand_near(Vector3(0, 0, 200), Vector3.ZERO, Vector3(0, 0, 190))
	p_shot_pitch()
	await _frames(20)
	await _shot("9c_crust_ii")
	# Hex bonus.
	var k := RustField.hex_key(0.0, 230.0)
	var c := RustField.key_center(k)
	var expect := world.hex_bonus(k)
	check(expect > 2000, "a Crust II hexagon pays more than the old flat ₹2,000 (%s)" % GameState.inr(expect))
	var cr0 := s.credits
	for y in range(-11, 12, 2):
		for x in range(-11, 12, 2):
			world.rust.paint(Vector3(c.x + x, 0, c.y + y), 1.6, 1.0)
	world._poll_hexes()
	check(is_equal_approx(s.credits - cr0, float(expect)), "clearing it pays exactly that bonus (+%s)" % GameState.inr(s.credits - cr0))
	# Difficulty.
	s.difficulty = "hard"
	var hard_price := world.price("panel")
	s.difficulty = "standard"
	check(hard_price > world.price("panel"), "Hard makes things dearer (panel %s vs %s)" % [GameState.inr(hard_price), GameState.inr(world.price("panel"))])
	s.difficulty = "hard"
	check(s.crust_at(0, 110) == 1, "Hard brings the crust closer to base")
	s.difficulty = "standard"


func p_shot_pitch() -> void:
	world.player.pitch = -0.35


func _cart_flow() -> void:
	print("[handcart and sacks]")
	var s := world.state
	s.credits = 50000.0
	s.tank = 0.0
	await _open_tab("Gear")
	var b := _find_button("Handcart")
	check(b != null and b.text.contains("6,000"), "handcart costs ₹6,000 in the Gear tab (%s)" % (b.text if b else "missing"))
	b.pressed.emit()
	await _frames(3)
	world.hud.close_shop()
	check(world.cart != null and s.cart_lvl == 0, "buying it puts a handcart by the depot")
	world.cart.place(Vector3(30, 0, 40), 0.0)  # open ground
	await _stand_near(world.cart.global_position, Vector3(0, 0, 2.0), world.cart.global_position)
	check(world._act == "cart_grab", "next to the cart: [E] push it")
	await _press("interact")
	check(world.cart.pushing, "E grabs the cart")
	var start := world.cart.global_position
	world.player.yaw = 0.0  # walk north
	Input.action_press("move_forward")
	await get_tree().create_timer(2.0).timeout
	Input.action_release("move_forward")
	await _frames(5)
	var moved := world.cart.global_position.distance_to(start)
	check(moved > 4.0, "the cart rolls ahead of you (%.1f m)" % moved)
	check(world.player.velocity.length() < 3.2, "pushing is slower than walking")
	await _shot("10a_pushing_cart")
	await _press("interact")
	check(not world.cart.pushing, "E lets go")
	s.tank = 20.0
	await _press("vehicle_empty")
	check(is_equal_approx(world.cart.load_kg, 20.0) and s.tank == 0.0, "Q next to the cart tips the tank in")
	world.cart.place(World.DEPOT + Vector3(-4, 0, 4), 0.0)
	s.tank = 5.0
	await _stand_near(World.DEPOT, Vector3(-2, 0, 2), World.DEPOT)
	check(world._act == "export" and world.hud.prompt_lbl.text.contains("25.0 kg"), "depot exports tank + cart (%s)" % world.hud.prompt_lbl.text)
	var cr0 := s.credits
	await _press("interact")
	check(world.cart.load_kg == 0.0 and s.tank == 0.0 and s.credits > cr0, "both are sold at full price")
	# Sacks.
	await _stand_near(Vector3(40, 0, -40), Vector3.ZERO, Vector3(40, 0, -50))
	s.tank = 24.0
	await _press("vehicle_empty")
	check(s.sacks.size() == 1 and s.tank == 0.0, "Q away from the cart drops a sack")
	await _shot("10b_sack")
	cr0 = s.credits
	var gross := 24.0 * s.price_now()
	world._haul_t = 0.01
	await _frames(3)
	check(s.sacks.is_empty() and absf((s.credits - cr0) - gross * 0.75) < 2.0, "the hauler pays 75%% on Standard (+%s)" % GameState.inr(s.credits - cr0))
	world.save_game()
	var loaded := GameState.new()
	loaded.load_into(RustField.new())
	check(loaded.cart_lvl == 0, "the handcart is saved")


func _hold(action: String, seconds: float) -> void:
	Input.action_press(action)
	await get_tree().create_timer(seconds).timeout
	Input.action_release(action)
	await _frames(3)


func _infra_flow() -> void:
	print("[buildings, climbing, fullscreen]")
	var p := world.player
	world.state.time_of_day = 0.35
	# Garage ladder up to the roof.
	var l: Dictionary = {}
	for ld in world.ladders:
		if (ld.base as Vector3).x > World.GARAGE.x + 7.0:
			l = ld
	await _stand_near(l.base + l.out * 1.2, Vector3.ZERO, l.base)
	p.pitch = 0.0
	Input.action_press("move_forward")
	var t := 0.0
	while t < 5.0 and p.global_position.y < 5.0:
		await get_tree().create_timer(0.1).timeout
		t += 0.1
	await get_tree().create_timer(0.5).timeout
	Input.action_release("move_forward")
	await _frames(20)
	check(p.global_position.y > 5.0 and p.is_on_floor(), "the garage ladder takes you onto the roof (feet at %.1f m)" % p.global_position.y)
	# Hangar ladder: you end up standing on its curved roof.
	var hl: Dictionary = world.ladders[0]
	await _stand_near(hl.base + hl.out * 1.2, Vector3.ZERO, hl.base)
	p.pitch = 0.0
	Input.action_press("move_forward")
	t = 0.0
	while t < 5.0 and p.global_position.y < 4.0:
		await get_tree().create_timer(0.1).timeout
		t += 0.1
	await get_tree().create_timer(0.3).timeout
	Input.action_release("move_forward")
	await _frames(20)
	await get_tree().create_timer(1.0).timeout
	var fl := "floor normal %s" % str(p.get_floor_normal()) if p.is_on_floor() else "not on floor, vel %s" % str(p.velocity)
	check(p.global_position.y > 3.5 and p.is_on_floor(), "the hangar ladder puts you on its roof (feet at %.1f m, %s)" % [p.global_position.y, fl])
	p.yaw += PI
	p.pitch = -0.5
	await _shot("11b_hangar_roof")
	await _stand_near(l.base + l.out * 1.2, Vector3.ZERO, l.base)
	Input.action_press("move_forward")
	t = 0.0
	while t < 5.0 and p.global_position.y < 5.0:
		await get_tree().create_timer(0.1).timeout
		t += 0.1
	await get_tree().create_timer(0.5).timeout
	Input.action_release("move_forward")
	await _frames(10)
	p.yaw += PI * 0.75
	p.pitch = -0.4
	await _shot("11a_on_garage_roof")
	# Ledge climb onto the large barrel tank (2.4 m): jump, then Space again near the top.
	var tank_pos := World.DEPOT + Vector3(4, 0, 6)
	await _stand_near(tank_pos, Vector3(0, 0, 2.6), tank_pos)
	var y0 := p.global_position.y
	Input.action_press("move_forward")
	await _press("jump")
	var t2 := 0.0
	while t2 < 1.5 and p.global_position.y - y0 < 1.8:
		await get_tree().create_timer(0.05).timeout
		t2 += 0.05
	Input.action_release("move_forward")
	await get_tree().create_timer(1.0).timeout
	check(p.global_position.y - y0 > 1.8, "jump + climb gets you on top of a 2.4 m tank (+%.1f m)" % (p.global_position.y - y0))
	check(p.is_on_floor(), "and you stand on its real surface (+%.1f m)" % (p.global_position.y - y0))
	# Real shapes, not boxes: the round glass hangar is lower at its edge than its bounding box.
	var space := p.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(11 + 4.6, 20, -12), Vector3(11 + 4.6, -1, -12), 4)
	var hit := space.intersect_ray(q)
	check(hit and hit.position.y < 3.9, "dome edge collides at its real height (%.2f m, box top would be 4.2)" % (hit.position.y if hit else -1.0))
	# Fullscreen.
	var ev := InputEventKey.new()
	ev.keycode = KEY_F11
	ev.pressed = true
	var was := DisplayServer.window_get_mode()
	Input.parse_input_event(ev)
	await _wait_mode(func(m): return m != was)
	var now := DisplayServer.window_get_mode()
	check(now != was, "F11 switches between windowed and fullscreen (%d -> %d)" % [was, now])
	if now == DisplayServer.WINDOW_MODE_FULLSCREEN:
		check(DisplayServer.window_get_size() == DisplayServer.screen_get_size(), "fullscreen covers the whole screen (%s)" % str(DisplayServer.window_get_size()))
	Input.parse_input_event(ev)
	var was_fs := was == DisplayServer.WINDOW_MODE_FULLSCREEN
	await _wait_mode(func(m): return (m == DisplayServer.WINDOW_MODE_FULLSCREEN) == was_fs)
	check((DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN) == was_fs,
		"F11 again goes back (%d -> %d)" % [now, DisplayServer.window_get_mode()])


## Window-mode changes are asynchronous on some window managers: wait up to 3 s.
func _wait_mode(ok: Callable) -> void:
	for i in 30:
		await get_tree().create_timer(0.1).timeout
		if ok.call(DisplayServer.window_get_mode()):
			return


func _panel_flow() -> void:
	print("[solar panels]")
	var s := world.state
	var p := world.player
	s.panel_spots = []
	world._refresh_solar()
	s.panel_stock = 0
	s.credits = 100000.0
	var gen0 := s.gen_kw()
	check(world.buy("panel") and s.panel_stock == 1 and s.panels == 0, "buying a panel puts it in your inventory, not on the ground")
	check(is_equal_approx(s.gen_kw(), gen0), "an unplaced panel makes no power")
	world.buy("panel")
	# Aim at open ground near the base.
	await _stand_near(Vector3(-20, 0, 20), Vector3.ZERO, Vector3(-20, 0, 30))
	p.pitch = -0.45
	await _press("place_panel")
	await _frames(4)
	check(world.placing and world._ghost.visible, "P shows a preview where you aim")
	check(world._ghost_why == "", "open ground near the base is a valid spot (%s)" % world._ghost_why)
	await _shot("12a_placing_valid")
	await _press("vehicle_tool")
	await _frames(3)
	check(is_equal_approx(world._ghost_yaw, PI / 4.0), "R rotates the panel 45°")
	await _press("clean")
	check(s.panels == 1 and s.panel_stock == 1 and world.placing, "left-click places it; still placing the second one")
	await _frames(4)
	check(world._ghost_why.contains("another panel"), "panels can't overlap (%s)" % world._ghost_why)
	await _shot("12b_placing_blocked")
	await _stand_near(Vector3(70, 0, 40), Vector3.ZERO, Vector3(70, 0, 50))
	p.pitch = -0.45
	await _frames(4)
	check(world._ghost_why.contains("too far"), "too far from the base is refused (%s)" % world._ghost_why)
	await _press("clean")
	check(s.panels == 1, "a red preview can't be placed")
	await _press("pause")
	check(not world.placing and not get_tree().paused, "Esc cancels placing without opening the menu")
	var pos := Vector3(float(s.panel_spots[0][0]), 0, float(s.panel_spots[0][1]))
	await _stand_near(pos, Vector3(0, 0, 2.0), pos)
	check(world._act == "panel_pickup", "E next to a placed panel offers to pick it up")
	await _press("interact")
	check(s.panels == 0 and s.panel_stock == 2, "picking up returns it to your inventory (panels %d, stock %d, act '%s', prompt '%s')" % [s.panels, s.panel_stock, world._act, world.hud.prompt_lbl.text])
	world.save_game()
	var loaded := GameState.new()
	loaded.load_into(RustField.new())
	check(loaded.panel_stock == 2, "unplaced panels are saved")


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



## Drives `v` toward `target` with real throttle and steering input until it is within `r` metres
## (or `limit` seconds pass). Returns the closest distance reached.
func _drive_to(v: Vehicle, target: Vector3, r: float, limit := 22.0) -> float:
	var best := 999.0
	var t := 0.0
	while t < limit and best >= r:
		var to := target - v.global_position
		var err := wrapf(atan2(-to.x, -to.z) - v.heading, -PI, PI)
		Input.action_release("move_left")
		Input.action_release("move_right")
		if err > 0.05:
			Input.action_press("move_left", clampf(err * 2.0, 0.2, 1.0))
		elif err < -0.05:
			Input.action_press("move_right", clampf(-err * 2.0, 0.2, 1.0))
		Input.action_press("move_forward", 0.6)
		await get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		best = minf(best, Vector2(to.x, to.z).length())
	for a in ["move_forward", "move_left", "move_right"]:
		Input.action_release(a)
	v.speed = 0.0
	await _frames(10)
	return best


func _put_vehicle(v: Vehicle, at: Vector3, face: Vector3) -> void:
	v.global_position = Vector3(at.x, world.terrain.height_at(at.x, at.z) + 0.5, at.z)
	var d := face - at
	v.heading = atan2(-d.x, -d.z)
	v.rotation.y = v.heading
	v.speed = 0.0
	v.velocity = Vector3.ZERO


func _enter(v: Vehicle) -> void:
	await _stand_near(v.global_position, Vector3(3, 0, 0), v.global_position)
	await _press("interact")
	await _frames(10)


## The Sweeper must drive back onto the base pad and up to the depot from every open side
## (the pad's edge used to be a wall a vehicle body could not climb).
func _depot_drive_flow() -> void:
	print("[sweeper to the export depot]")
	var s := world.state
	s.sweeper_owned = true
	world._set_vehicle_present(world.sweeper, true)
	var v := world.sweeper
	v.energy = v.battery
	for leg: Array in [[Vector3(45, 0, 3), World.DEPOT], [Vector3(40, 0, -30), World.DEPOT], [Vector3(40, 0, 30), World.DEPOT],
			[Vector3(-35, 0, 1), World.DEPOT]]:
		_put_vehicle(v, leg[0], leg[1])
		await _enter(v)
		check(world.driven() == v, "in the Sweeper at %s" % leg[0])
		var best := await _drive_to(v, leg[1], World.DEPOT_DRIVE_R - 1.0)
		check(best < World.DEPOT_DRIVE_R, "Sweeper from %s drives up to the depot (closest %.1f m)" % [leg[0], best])
		if leg[0] == Vector3(45, 0, 3):
			s.hopper = 120.0
			await _frames(3)
			check(world.hud.prompt_lbl.text.contains("[Q] Export the hopper"), "depot prompt shows in the Sweeper (%s)" % world.hud.prompt_lbl.text)
			var c0 := s.credits
			await _press("vehicle_empty")
			check(s.hopper == 0.0 and s.credits > c0, "Q at the depot exports the hopper (+%s)" % GameState.inr(s.credits - c0))
		await _press("interact")
		await _frames(10)
	# Off the pad and back on again across each edge (north and south lanes are clear of buildings).
	for leg: Array in [[Vector3(-30, 0, -45), Vector3(-30, 0, -12)], [Vector3(14, 0, 45), Vector3(14, 0, 17)]]:
		_put_vehicle(v, leg[0], leg[1])
		await _enter(v)
		var best := await _drive_to(v, leg[1], 2.0)
		check(best < 2.5, "Sweeper crosses the pad edge from %s (closest %.1f m to %s)" % [leg[0], best, leg[1]])
		await _press("interact")
		await _frames(10)


func _wheel(up: bool, times: int) -> void:
	for i in times:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
		e.pressed = true
		Input.parse_input_event(e)
		await _frames(2)


## Holds full throttle for `seconds` and returns the top speed reached (km/h).
func _top_kmh(v: Vehicle, seconds: float) -> float:
	var top := 0.0
	Input.action_press("move_forward")
	var t := 0.0
	while t < seconds:
		await get_tree().physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		top = maxf(top, absf(v.speed) * 3.6)
	Input.action_release("move_forward")
	return top


func _speed_flow() -> void:
	print("[vehicle speed and the mouse-wheel limiter]")
	var s := world.state
	s.sweeper_owned = true
	world._set_vehicle_present(world.sweeper, true)
	var v := world.sweeper
	v.energy = v.battery
	for k in v.cond:
		v.cond[k] = 1.0
	_put_vehicle(v, Vector3(80, 0, -80), Vector3(80, 0, -400))
	await _enter(v)
	v.tool_on = false  # getting in switches the brush on; measure driving alone
	check(is_equal_approx(s.drive_limit, 0.6), "new worlds start at a 60%% limit (%d km/h)" % roundi(v.top_speed() * 0.6 * 3.6))
	await _wheel(false, 10)
	check(is_equal_approx(s.drive_limit, 0.2), "scrolling down bottoms out at 20%% (%.1f)" % s.drive_limit)
	var slow := await _top_kmh(v, 5.0)
	check(slow <= v.top_speed() * 0.2 * 3.6 + 0.5, "at 20%% the Sweeper stays under %d km/h (%.1f)" % [roundi(v.top_speed() * 0.2 * 3.6), slow])
	check(world.hud.batt_lbl.text.contains("km/h"), "HUD shows the speed (%s)" % world.hud.batt_lbl.text)
	await _wheel(true, 12)
	check(is_equal_approx(s.drive_limit, 1.0), "scrolling up tops out at 100%")
	var fast := await _top_kmh(v, 9.0)
	check(fast > slow * 3.0 and fast <= 26.0, "flat out is %.1f km/h (was 32 before), well above the limited %.1f" % [fast, slow])
	# Scroll down while moving: it eases off to the new limit.
	Input.action_press("move_forward")
	await _wheel(false, 6)
	await get_tree().create_timer(3.0).timeout
	var eased := absf(v.speed) * 3.6
	Input.action_release("move_forward")
	check(eased <= v.top_speed() * 0.4 * 3.6 + 0.5, "lowering the limit at speed slows you to it (%.1f km/h)" % eased)
	# Battery per kilometre: slower is cheaper.
	var per_km := {}
	for lim in [0.3, 1.0]:
		s.drive_limit = lim
		v.energy = v.battery
		await _top_kmh(v, 6.0)  # get up to speed
		Input.action_press("move_forward")
		var e0 := v.energy
		var p0 := v.global_position
		await get_tree().create_timer(5.0).timeout
		var km := Vector2(v.global_position.x - p0.x, v.global_position.z - p0.z).length() / 1000.0
		Input.action_release("move_forward")
		per_km[lim] = (e0 - v.energy) / maxf(km, 0.0001)
	check(per_km[0.3] < per_km[1.0] * 0.6, "at 30%% the Sweeper uses %.2f kWh/km, flat out %.2f" % [per_km[0.3], per_km[1.0]])
	s.drive_limit = 0.4
	await _frames(3)
	var r40 := world.hud.batt_lbl.text
	s.drive_limit = 1.0
	await _frames(3)
	check(v.range_at(v.top_speed() * 0.4 * 3.6) > v.range_at(v.top_speed() * 3.6) * 1.5, "HUD range grows when you scroll the limit down (%s  vs  %s)" % [r40, world.hud.batt_lbl.text])
	v.speed = 0.0
	s.drive_limit = 0.6
	await _press("interact")
	await _frames(10)


func _sack_flow() -> void:
	print("[rust sacks]")
	var s := world.state
	var v := world.sweeper
	var spot := Vector3(60, 0, 60)
	world.cart.place(Vector3(-30, 0, 30), 0.0)
	s.sacks.clear()
	for n in world._sack_nodes:
		n.queue_free()
	world._sack_nodes.clear()
	world._haul_t = GameState.HAUL_INTERVAL
	# Sweeper: Q away from the depot bags the whole hopper into one sack.
	_put_vehicle(v, spot, spot + Vector3(0, 0, -10))
	await _enter(v)
	v.tool_on = false
	s.hopper = 300.0
	await _press("vehicle_empty")
	check(s.hopper == 0.0 and s.sacks.size() == 1, "Q in the Sweeper bags the hopper (%d sack)" % s.sacks.size())
	check(s.sacks.size() == 1 and is_equal_approx(float(s.sacks[0][3]), 300.0), "the sack holds all 300 kg")
	await _shot("sack_from_sweeper")
	# Turn round and drive over it with the brush on: every kilogram comes back.
	var sp: Array = s.sacks[0]
	var sack_pos := Vector3(sp[0], sp[1], sp[2])
	_put_vehicle(v, sack_pos + Vector3(0, 0, -8), sack_pos)
	v.tool_on = true
	var before := s.hopper
	await _drive_to(v, sack_pos, 0.5, 8.0)
	for i in 60:
		if s.sacks.is_empty():
			break
		await get_tree().create_timer(0.1).timeout
	check(s.sacks.is_empty(), "driving over the sack with the brush on scoops it up")
	check(s.hopper - before >= 300.0, "hopper got the full 300 kg back (+%.0f kg)" % (s.hopper - before))
	v.tool_on = false
	await _press("interact")
	await _frames(10)
	s.hopper = 0.0
	# On foot: drop the tank, pick it straight back up with E.
	await _stand_near(spot + Vector3(12, 0, 0), Vector3.ZERO, spot + Vector3(12, 0, -10))
	s.tank = 20.0
	# Unloading takes time, and walking off cancels it.
	var e := InputEventAction.new()
	e.action = "vehicle_empty"
	e.pressed = true
	Input.parse_input_event(e)
	await _frames(3)
	e = e.duplicate()
	e.pressed = false
	Input.parse_input_event(e)
	await get_tree().create_timer(0.5).timeout
	check(world.busy() and s.tank == 20.0 and s.sacks.is_empty(), "filling a sack takes time (%.1f s for 20 kg)" % World.task_time("tank", 20.0))
	check(world.hud.prompt_lbl.text.contains("%"), "progress shows in the prompt (%s)" % world.hud.prompt_lbl.text)
	await _shot("unload_progress")
	world.player.global_position += Vector3(1.5, 0, 0)
	await _frames(3)
	check(not world.busy() and s.tank == 20.0 and s.sacks.is_empty(), "walking away cancels it and keeps the rust in the tank")
	await _stand_near(spot + Vector3(12, 0, 0), Vector3.ZERO, spot + Vector3(12, 0, -10))
	var t0 := Time.get_ticks_msec()
	await _press("vehicle_empty")
	check(s.tank == 0.0 and s.sacks.size() == 1, "Q on foot drops a 20 kg sack (after %.1f s)" % ((Time.get_ticks_msec() - t0) / 1000.0))
	await _frames(3)
	check(world.hud.prompt_lbl.text.contains("[E] Pick up the 20 kg rust sack"), "pick-up prompt (%s)" % world.hud.prompt_lbl.text)
	await _press("interact")
	check(is_equal_approx(s.tank, 20.0) and s.sacks.is_empty(), "E puts all 20 kg back in the tank")
	# Partial pick-up when the tank is nearly full.
	await _press("vehicle_empty")
	s.tank = s.capacity() - 5.0
	await _frames(3)
	await _press("interact")
	check(is_equal_approx(s.tank, s.capacity()), "a nearly full tank takes what fits")
	check(s.sacks.size() == 1 and is_equal_approx(float(s.sacks[0][3]), 15.0), "the other 15 kg stay in the sack")
	await _frames(3)
	check(not world.hud.prompt_lbl.text.contains("[E] Pick up"), "no pick-up prompt with a full tank")
	# With the handcart beside you the sack goes into the cart.
	s.tank = 0.0
	var p := world.player.global_position
	world.cart.place(p + Vector3(2.0, 0, 0), 0.0)
	world.cart.load_kg = 0.0
	await _frames(3)
	check(world.hud.prompt_lbl.text.contains("into the handcart"), "prompt offers the handcart (%s)" % world.hud.prompt_lbl.text)
	await _press("interact")
	check(is_equal_approx(world.cart.load_kg, 15.0) and s.sacks.is_empty() and s.tank == 0.0, "E loads the sack into the handcart")
	await _shot("sack_into_cart")
	world.cart.empty()
	world.cart.place(Vector3(World.DEPOT.x - 4.0, 0, World.DEPOT.z + 4.0), 0.0)


func _sleep_flow() -> void:
	print("[sleeping in the bunk]")
	var s := world.state
	var v := world.sweeper
	s.time_of_day = 0.5  # noon
	await _stand_near(World.BED, Vector3(0, 0, 1.6), World.BED)
	await _frames(3)
	check(world.hud.prompt_lbl.text.contains("once it is dark"), "no sleeping at noon (%s)" % world.hud.prompt_lbl.text)
	await _press("interact")
	check(not world.sleeping and is_equal_approx(s.time_of_day, 0.5) or s.time_of_day < 0.52, "E at noon does nothing")
	# Night, but broke.
	s.time_of_day = 0.85
	s.credits = 100.0
	await _frames(3)
	check(world.hud.prompt_lbl.text.contains("[E] Sleep until 06:30"), "bunk offers sleep at night (%s)" % world.hud.prompt_lbl.text)
	await _press("interact")
	await _frames(5)
	check(not world.sleeping and s.time_of_day > 0.8 and s.credits == 100.0, "can't sleep without the money")
	# Night with money, the Sweeper plugged in and the base battery full.
	s.credits = 20000.0
	s.sweeper_owned = true
	world._set_vehicle_present(v, true)
	v.global_position = Vector3(World.BAYS[0].x, world.terrain.height_at(World.BAYS[0].x, World.BAYS[0].z) + 0.3, World.BAYS[0].z)
	v.energy = 2.0
	world.plugged[v] = 0
	s.bank = s.bank_cap()
	s.sacks.clear()  # so the hauler has nothing to pay out overnight
	for n in world._sack_nodes:
		n.queue_free()
	world._sack_nodes.clear()
	var sol0 := s.sol
	await _stand_near(World.BED, Vector3(0, 0, 1.6), World.BED)
	await _press("interact")
	await _frames(5)
	check(world.sleeping, "E at night puts you to sleep")
	await get_tree().create_timer(0.8).timeout
	await _shot("sleeping")
	var t := 0.0
	while world.sleeping and t < 10.0:
		await get_tree().create_timer(0.1).timeout
		t += 0.1
	check(not world.sleeping, "you wake up again (%.1f s)" % t)
	check(absf(s.time_of_day - 0.27) < 0.01, "it is morning, %s" % World.clock(s.time_of_day))
	check(s.sol == sol0 + 1, "a new sol began (Sol %d -> %d)" % [sol0, s.sol])
	check(is_equal_approx(s.credits, 20000.0 - world.sleep_cost()), "the night cost %s" % GameState.inr(world.sleep_cost()))
	check(v.energy > 10.0, "the plugged-in Sweeper charged overnight (2 -> %.1f kWh)" % v.energy)
	await _frames(10)
	await _shot("good_morning")
	world.plugged.erase(v)
