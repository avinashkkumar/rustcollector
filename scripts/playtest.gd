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
	await _save_flow()
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
