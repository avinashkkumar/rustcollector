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
	await _stand_near(world.cart.global_position, Vector3(0, 0, 2.0), world.cart.global_position)
	check(world._act == "cart_grab", "next to the cart: [E] push it")
	await _press("interact")
	check(world.cart.pushing, "E grabs the cart")
	var start := world.cart.global_position
	world.player.yaw = PI  # walk south, away from the base
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
