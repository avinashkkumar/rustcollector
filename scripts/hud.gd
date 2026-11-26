class_name Hud
extends CanvasLayer
## In-game HUD: balances, power, minimap, missions, prompts, toasts, base terminal and pause menu.

var world: World
var root: Control
var credits_lbl: Label
var load_lbl: Label
var load_bar: ProgressBar
var batt_box: VBoxContainer
var batt_lbl: Label
var batt_bar: ProgressBar
var grid_lbl: Label
var wear_lbl: Label
var rank_lbl: Label
var tool_lbl: Label
var stats_lbl: Label
var mission_title: Label
var mission_desc: Label
var mission_bar: ProgressBar
var hex_lbl: Label
var prompt_lbl: Label
var hint_lbl: Label
var fps_lbl: Label
var cross: ColorRect
var toast_box: VBoxContainer
var hex_map: HexMap
var map_panel: PanelContainer
var shop_layer: Control
var shop_list: VBoxContainer
var shop_credits: Label
var pause_layer: Control
var pause_main: VBoxContainer
var settings: SettingsPanel
var _text_t := 0.0
var _fps_frames := 0
var _fps_t := 0.0
var _map_big := false
var key_guide: KeyGuide


func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiKit.theme()
	add_child(root)
	_build_stats()
	_build_map()
	_build_center()
	_build_shop()
	_build_pause()
	key_guide = KeyGuide.new()
	key_guide.visible = false
	root.add_child(key_guide)


func _bar(color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(268, 12)
	b.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(5)
	b.add_theme_stylebox_override("fill", fill)
	return b


func _build_stats() -> void:
	var col := VBoxContainer.new()
	col.position = Vector2(18, 18)
	col.add_theme_constant_override("separation", 10)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(col)
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(300, 0)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	pc.add_child(vb)
	credits_lbl = UiKit.label("₹0", 30, UiKit.ACCENT)
	vb.add_child(credits_lbl)
	rank_lbl = UiKit.label("", 13, UiKit.MUTED)
	vb.add_child(rank_lbl)
	load_lbl = UiKit.label("", 15, UiKit.MUTED)
	vb.add_child(load_lbl)
	load_bar = _bar(UiKit.ACCENT)
	vb.add_child(load_bar)
	batt_box = VBoxContainer.new()
	batt_box.add_theme_constant_override("separation", 4)
	batt_lbl = UiKit.label("", 15, UiKit.MUTED)
	batt_box.add_child(batt_lbl)
	batt_bar = _bar(Color(0.35, 1.0, 0.55))
	batt_box.add_child(batt_bar)
	wear_lbl = UiKit.label("", 14, Color(1.0, 0.7, 0.4))
	batt_box.add_child(wear_lbl)
	vb.add_child(batt_box)
	grid_lbl = UiKit.label("", 14, Color(0.7, 0.9, 1.0))
	vb.add_child(grid_lbl)

	var mp := PanelContainer.new()
	mp.custom_minimum_size = Vector2(300, 0)
	mp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(mp)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 3)
	mp.add_child(mv)
	mission_title = UiKit.label("", 16, UiKit.ACCENT2)
	mission_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mission_title.custom_minimum_size.x = 268
	mv.add_child(mission_title)
	mission_desc = UiKit.label("", 14)
	mission_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mission_desc.custom_minimum_size.x = 268
	mv.add_child(mission_desc)
	mission_bar = _bar(UiKit.ACCENT2)
	mission_bar.custom_minimum_size.y = 8
	mv.add_child(mission_bar)

	hint_lbl = UiKit.label("", 13, Color(0.85, 0.75, 0.66, 0.9))
	hint_lbl.anchor_top = 1.0
	hint_lbl.anchor_bottom = 1.0
	hint_lbl.offset_left = 18
	hint_lbl.offset_top = -34
	root.add_child(hint_lbl)
	fps_lbl = UiKit.label("", 16, Color(0.7, 1.0, 0.7))
	fps_lbl.anchor_left = 0.5
	fps_lbl.anchor_right = 0.5
	fps_lbl.offset_left = -120
	fps_lbl.offset_right = 120
	fps_lbl.offset_top = 10
	fps_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(fps_lbl)


func _build_map() -> void:
	map_panel = PanelContainer.new()
	map_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_panel.anchor_left = 1.0
	map_panel.anchor_right = 1.0
	root.add_child(map_panel)
	var vb := VBoxContainer.new()
	map_panel.add_child(vb)
	hex_map = HexMap.new()
	hex_map.world = world
	vb.add_child(hex_map)
	hex_lbl = UiKit.label("", 14)
	hex_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hex_lbl.custom_minimum_size.x = 10
	vb.add_child(hex_lbl)
	_set_map_size(false)


func _set_map_size(big: bool) -> void:
	_map_big = big
	var s := 480.0 if big else 230.0
	hex_map.custom_minimum_size = Vector2(s, s)
	hex_map.span = 360.0 if big else 170.0
	map_panel.offset_right = -18
	map_panel.offset_left = -18 - s - 34
	map_panel.offset_top = 18
	map_panel.offset_bottom = 18 + s + 70


func _build_center() -> void:
	cross = ColorRect.new()
	cross.color = Color(1, 1, 1, 0.8)
	cross.size = Vector2(6, 6)
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.position -= Vector2(3, 3)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cross)
	prompt_lbl = UiKit.label("", 20, Color(1, 0.95, 0.85))
	prompt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_lbl.anchor_right = 1.0
	prompt_lbl.anchor_top = 0.5
	prompt_lbl.anchor_bottom = 0.5
	prompt_lbl.offset_top = 40
	prompt_lbl.add_theme_constant_override("outline_size", 6)
	prompt_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	root.add_child(prompt_lbl)
	toast_box = VBoxContainer.new()
	toast_box.anchor_left = 0.5
	toast_box.anchor_right = 0.5
	toast_box.anchor_top = 1.0
	toast_box.anchor_bottom = 1.0
	toast_box.offset_left = -420
	toast_box.offset_right = 420
	toast_box.offset_top = -230
	toast_box.offset_bottom = -60
	toast_box.alignment = BoxContainer.ALIGNMENT_END
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toast_box)


func toast(msg: String, secs := 3.0, color := Color(1, 0.92, 0.8)) -> void:
	var l := UiKit.label(msg, 19, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	toast_box.add_child(l)
	while toast_box.get_child_count() > 4:
		toast_box.get_child(0).free()
	var tw := l.create_tween()
	tw.tween_interval(secs)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)


## CS-style end-of-round card, shown at the end of every sol. Fades out on its own.
func sol_report(d: Dictionary) -> void:
	var pc := PanelContainer.new()
	pc.anchor_left = 0.5
	pc.anchor_right = 0.5
	pc.offset_left = -230
	pc.offset_right = 230
	pc.offset_top = 70
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	pc.add_child(vb)
	vb.add_child(UiKit.label("SOL %d COMPLETE" % d.sol, 24, UiKit.ACCENT))
	vb.add_child(UiKit.label("%s kg of rust  ·  %s earned" % [_fmt_int(int(d.kg)), GameState.inr(d.earned)], 18))
	vb.add_child(UiKit.label("%d hexagons  ·  %d relics  ·  %d supply pods" % [d.hexes, d.relics, d.pods], 16, UiKit.MUTED))
	if float(d.kg) > 0.0:
		var who := {you = "You (on foot)", sweeper = "The Sweeper", drones = "The drone fleet"}
		vb.add_child(UiKit.label("MVP: %s  (%d%% of the rust)" % [who[d.mvp], roundi(float(d.mvp_share) * 100.0)], 16, UiKit.ACCENT2))
	var tw := pc.create_tween()
	tw.tween_interval(10.0)
	tw.tween_property(pc, "modulate:a", 0.0, 1.0)
	tw.tween_callback(pc.queue_free)


func mission_complete(m: Dictionary) -> void:
	toast("MISSION COMPLETE: %s   +%s" % [m.title, GameState.inr(m.reward)], 5.0, Color(0.55, 0.95, 1.0))


func set_prompt(t: String) -> void:
	if prompt_lbl.text != t:
		prompt_lbl.text = t


func _process(dt: float) -> void:
	_fps_frames += 1
	_fps_t += dt
	if _fps_t >= 0.5:
		fps_lbl.text = "%d FPS  ·  %.1f ms" % [roundi(_fps_frames / _fps_t), _fps_t * 1000.0 / _fps_frames] if Config.show_fps else ""
		_fps_frames = 0
		_fps_t = 0.0
	if world.ui_open:
		_text_t -= dt
		if _text_t <= 0.0:
			_text_t = 0.1
			_update_text()  # balances must stay right while the terminal is open
		return
	if Input.is_action_just_pressed("key_guide"):
		key_guide.driving = world.driven() != null
		key_guide.visible = not key_guide.visible
		key_guide.queue_redraw()
	if Input.is_action_just_pressed("toggle_fps"):
		Config.show_fps = not Config.show_fps
		Config.save_settings()
	if Input.is_action_just_pressed("toggle_map"):
		_set_map_size(not _map_big)
	if Input.is_action_just_pressed("toggle_hex"):
		Config.hex_overlay = not Config.hex_overlay
		Config.changed()
	var aim: bool = world.player.active and world.player.aim_valid
	cross.color = Color(1.0, 0.6, 0.2, 1.0) if aim else Color(1, 1, 1, 0.7)
	cross.visible = world.player.active
	_text_t -= dt
	if _text_t > 0.0:
		return
	_text_t = 0.1
	_update_text()


func _update_text() -> void:
	var s := world.state
	var v := world.driven()
	credits_lbl.text = GameState.inr(s.credits)
	var r := s.rank_index()
	rank_lbl.text = "%s%s" % [s.rank_name(), "" if r == 0 else "  ·  exports +%d%%" % roundi(r * GameState.RANK_BONUS * 100.0)]
	if v == world.sweeper:
		load_lbl.text = "Hopper %.0f / %.0f kg · brush %s" % [s.hopper, GameState.SWEEPER_HOPPER, "on" if v.tool_on else "off"]
		load_bar.max_value = GameState.SWEEPER_HOPPER
		load_bar.value = s.hopper
	else:
		load_lbl.text = "Rust tank %.1f / %.0f kg" % [s.tank, s.capacity()]
		load_bar.max_value = s.capacity()
		load_bar.value = s.tank
	batt_box.visible = v != null
	if v:
		var pct := v.energy / v.battery * 100.0
		var kw := v.drive_kw + (v.sweep_kw if v.tool_on else 0.0) + 0.15
		var range_km := v.energy / kw * GameState.TIME_SCALE * v.max_speed / 1000.0
		batt_lbl.text = "Battery %d%% · ~%.1f km%s%s" % [roundi(pct), range_km, " · BOOST" if v.boosting else "", " · charging" if v.charging else ""]
		batt_bar.max_value = v.battery
		batt_bar.value = v.energy
		# Only shown once something needs attention.
		var parts := PackedStringArray()
		for k in v.cond:
			if float(v.cond[k]) < 0.7:
				parts.append("%s %d%%" % [GameState.PART_NAMES[k], roundi(float(v.cond[k]) * 100.0)])
		wear_lbl.visible = not parts.is_empty()
		wear_lbl.text = "Wear: " + " · ".join(parts)
	# Grid power only matters at the base or while driving.
	var near_base := Vector2(world.focus_point().x, world.focus_point().z).length() < 40.0
	grid_lbl.visible = near_base or v != null
	grid_lbl.text = "Base grid %.0f/%.0f kWh · solar +%.1f kW" % [s.bank, s.bank_cap(), s.gen_kw() * s.daylight()]
	var m := world.missions.current(s)
	mission_bar.max_value = 1.0
	if m.is_empty():
		mission_title.text = "ALL MISSIONS COMPLETE"
		mission_desc.text = "The plain is endless. Keep clearing hexagons for bonuses."
		mission_bar.value = 1.0
	else:
		mission_title.text = "%s  (+%s)" % [m.title, GameState.inr(m.reward)]
		mission_desc.text = m.desc
		mission_bar.value = clampf(world.missions.progress(s, m.id), 0.0, 1.0)
	var f := world.focus_point()
	var hk := RustField.hex_key(f.x, f.z)
	var clean: float = world.hex_cache.get(hk, -1.0)
	if clean < 0.0:
		clean = world.rust.hex_clean(hk)
		world.hex_cache[hk] = clean
	var done := s.hexes_cleared.has(RustField.hex_name(hk))
	var hh := int(s.time_of_day * 24.0)
	var mm := int(fmod(s.time_of_day * 1440.0, 60.0))
	var hc := RustField.key_center(hk)
	var crust := s.crust_at(hc.x, hc.y)
	var tail := " · bonus paid" if done else (" · %s at 90%%" % GameState.inr(world.hex_bonus(hk)) if world.rust.hex_pristine_kg(hk) >= 40.0 else "")
	hex_lbl.text = "Hex %s · %s · %d%%%s\nSol %d %02d:%02d · rust %s/kg" % [RustField.hex_name(hk), GameState.CRUST_NAMES[crust],
		roundi(clean * 100.0), tail, s.sol, hh, mm, GameState.inr(s.price_now())]
	hint_lbl.visible = s.play_time < 180.0
	if key_guide.visible and key_guide.driving != (v != null):
		key_guide.driving = v != null
		key_guide.queue_redraw()
	if v:
		hint_lbl.text = "WASD drive · Shift boost · Space handbrake · mouse look · V camera · %sT waypoint · E exit · F1 all keys" % [
			"R brush on/off · Q empty hopper · " if v == world.sweeper else ""]
	else:
		hint_lbl.text = "WASD move · Shift sprint · LMB/F clean · E interact · Q unload tank · L torch · T waypoint · M map · F1 all keys"


static func _fmt_int(n: int) -> String:
	return GameState.inr(n).trim_prefix("₹")


# ---------------------------------------------------------------- base terminal

func _build_shop() -> void:
	shop_layer = Control.new()
	shop_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shop_layer.visible = false
	root.add_child(shop_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shop_layer.add_child(dim)
	var vb := UiKit.centered_panel(shop_layer, Vector2(820, 0))
	vb.custom_minimum_size.x = 790
	vb.add_child(UiKit.label("BASE TERMINAL", 30, UiKit.ACCENT2))
	shop_credits = UiKit.label("", 20, UiKit.ACCENT)
	vb.add_child(shop_credits)
	_tab_bar = HBoxContainer.new()
	_tab_bar.add_theme_constant_override("separation", 6)
	vb.add_child(_tab_bar)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(780, 560)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	shop_list = VBoxContainer.new()
	shop_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_list.add_theme_constant_override("separation", 8)
	scroll.add_child(shop_list)
	vb.add_child(UiKit.button("Close  [Esc]", close_shop))


func open_shop() -> void:
	world.ui_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	shop_layer.visible = true
	_refresh_shop()


func close_shop() -> void:
	shop_layer.visible = false
	world.ui_open = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _section(title: String) -> void:
	shop_list.add_child(UiKit.label(title, 17, UiKit.ACCENT))


const SHOP_TABS := ["Tools", "Gear", "Power", "Vehicles", "Workshop", "Drones", "Paint"]
var shop_tab := "Tools"
var _tab_bar: HBoxContainer


func _refresh_shop() -> void:
	var s := world.state
	shop_credits.text = "Balance: %s   ·   rust sells for %s/kg   ·   %s   ·   %s" % [GameState.inr(s.credits),
		GameState.inr(s.price_now()), s.rank_name(), s.diff().name]
	for c in _tab_bar.get_children():
		c.queue_free()
	for t in SHOP_TABS:
		var b := UiKit.button(t, func() -> void:
			shop_tab = t
			_refresh_shop(), 104)
		b.toggle_mode = true
		b.button_pressed = t == shop_tab
		_tab_bar.add_child(b)
	for c in shop_list.get_children():
		c.queue_free()
	match shop_tab:
		"Tools":
			var cur := s.tool()
			var star := s.mastery_level()
			var nk := s.mastery_next_kg()
			_section("%s  %s" % [cur.name.to_upper(), "★".repeat(star) + "☆".repeat(GameState.MASTERY_KG.size() - 1 - star)])
			shop_list.add_child(UiKit.label(("Mastery grows as you clean with it: %.0f kg to the next star (+%d%% speed each). Upgrades can't go above your stars." % [nk, roundi(GameState.MASTERY_BONUS * 100.0)]) if nk > 0.0 else "Fully mastered.", 14, UiKit.MUTED))
			if s.tool_lvl < GameState.TOOLS.size() - 1:
				var t: Dictionary = GameState.TOOLS[s.tool_lvl + 1]
				_row("Next tool: %s" % t.name, "%s Tier %d: handles %s. Upgrades carry over; mastery starts again." % [t.desc, s.tool_lvl + 2, GameState.CRUST_NAMES[s.tool_lvl + 1]], "tool")
			else:
				_row("Tool: %s" % cur.name, "Top-tier tool installed.", "")
			for m in ["power", "width", "reach"]:
				var d: Dictionary = GameState.TOOL_MODS[m]
				_row("%s  (level %d/%d)" % [d.name, s.mods[m], d.max], d.desc, m)
		"Gear":
			var nt := s.tank_lvl + 1
			_row("Rust tank: %.0f kg" % (GameState.TANKS[nt].cap if nt < GameState.TANKS.size() else s.capacity()),
				"Carry more rust per trip (now %.0f kg)." % s.capacity(), "tank")
			var nc := s.cart_lvl + 1
			_row(("Handcart  (%.0f kg)" % GameState.CARTS[0].cap) if s.cart_lvl < 0 else ("Bigger handcart bin: %.0f kg" % (GameState.CARTS[nc].cap if nc < GameState.CARTS.size() else s.cart_capacity())),
				"Push it to where you work, tip your tank in with Q, push it back to the depot. No fee." if s.cart_lvl < 0 else "Now %.0f kg." % s.cart_capacity(), "cart")
			var nb := s.boots_lvl + 1
			_row("Servo boots  +%d%%" % int(((GameState.BOOTS[nb].mult if nb < GameState.BOOTS.size() else s.boots_mult()) - 1.0) * 100),
				"Walk and sprint faster.", "boots")
			shop_list.add_child(UiKit.label("Away from the depot, Q drops your tank as a sack. The hauler collects sacks every %d min for a %d%% fee." % [roundi(GameState.HAUL_INTERVAL / 60.0), roundi(s.haul_fee() * 100.0)], 14, UiKit.MUTED))
		"Power":
			_row("Solar panel  (%d/%d installed)" % [s.panels, GameState.MAX_PANELS],
				"+%.0f kW generation and +%.0f kWh of base battery. Vehicles charge from it at the garage posts." % [GameState.PANEL_KW, GameState.BANK_PER_PANEL], "panel")
		"Vehicles":
			_row("Sweeper", "Drivable 4.6 m roller brush with a %.0f kg hopper. Handles up to Crust III. Runs on battery." % GameState.SWEEPER_HOPPER, "sweeper")
			if s.sweeper_owned:
				var nlv := s.sweeper_batt_lvl + 1
				_row("Sweeper battery pack", "Capacity %.0f kWh%s." % [s.sweeper_battery(),
					(" -> %.0f kWh" % GameState.SWEEPER_BATT[nlv].kwh) if nlv < GameState.SWEEPER_BATT.size() else " (max)"], "sweeper_batt")
			_row("Charger cart", "Mobile %.0f kWh battery. Park it next to a stranded Sweeper and connect its cable." % GameState.CHARGER_BATT, "charger")
			if s.sweeper_owned:
				_row("Tow sweeper to the garage", "Recover a stranded sweeper to its garage bay.", "tow_sweeper")
			if s.charger_owned:
				_row("Tow charger cart to the garage", "Recover the charger cart to its garage bay.", "tow_charger")
		"Workshop":
			var any := false
			for veh in [world.sweeper, world.charger]:
				if not world.owns(veh):
					continue
				any = true
				var in_bay := world.bay_of(veh) >= 0
				var parts: Array = ["tyres", "brush", "motor"] if veh == world.sweeper else ["tyres", "motor"]
				for part in parts:
					var c: float = s.wear[veh.kind][part]
					var desc := "Condition %d%%." % roundi(c * 100.0)
					if c >= 0.995:
						desc += " As good as new."
					elif not in_bay:
						desc += " Park it in its garage bay (or tow it) to repair."
					_row("%s: %s" % [veh.display_name(), GameState.PART_NAMES[part]], desc, "repair_%s_%s" % [veh.kind, part])
			if not any:
				shop_list.add_child(UiKit.label("Repairs for your vehicles appear here once you own one.", 15, UiKit.MUTED))
		"Paint":
			var any := false
			for veh in [world.sweeper, world.charger]:
				if not world.owns(veh):
					continue
				any = true
				for lv in GameState.LIVERIES:
					var owned: bool = (s.liveries[veh.kind] as Array).has(lv.id)
					var on: bool = s.livery[veh.kind] == lv.id
					var desc := "Applied." if on else ("Owned: apply for free." if owned else "Cosmetic paint job.")
					_row("%s: %s" % [veh.display_name(), lv.name], desc, "paint_%s_%s" % [veh.kind, lv.id])
			if not any:
				shop_list.add_child(UiKit.label("Paint jobs for your vehicles appear here once you own one.", 15, UiKit.MUTED))
		"Drones":
			_row("Cleaning drone  (%d/%d)" % [s.drones, GameState.MAX_DRONES], "Works on its own inside the drone zone; exports remotely at 50%. Handles Crust II.", "drone")
			if s.drones > 0:
				_row("Drone relay range  (%d ring%s)" % [s.drone_range, "" if s.drone_range == 1 else "s"],
					"Extends the drone zone by one ring of hexagons around the base.", "drone_range")


func _row(title: String, desc: String, item: String) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(UiKit.label(title, 18))
	var d := UiKit.label(desc, 14, UiKit.MUTED)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(d)
	hb.add_child(vb)
	var cost := world.price(item) if item != "" else -1
	var lock := world.lock_reason(item) if item != "" else ""
	if lock != "":
		(vb.get_child(0) as Label).modulate = Color(1, 1, 1, 0.55)
		var l := UiKit.label("Locked: " + lock, 14, Color(1.0, 0.6, 0.4))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(l)
		var lk := UiKit.label("🔒", 22, UiKit.MUTED)
		lk.custom_minimum_size.x = 190
		lk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hb.add_child(lk)
	elif cost >= 0:
		var b := UiKit.button(("Buy  %s" % GameState.inr(cost)) if cost > 0 else "Apply", func() -> void:
			if world.buy(item):
				toast(("Purchased: %s" if cost > 0 else "Applied: %s") % title, 2.5)
			_refresh_shop(), 190)
		b.disabled = world.state.credits < cost
		hb.add_child(b)
	else:
		var l := UiKit.label("—", 16, UiKit.MUTED)
		l.custom_minimum_size.x = 190
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hb.add_child(l)
	shop_list.add_child(hb)


# ---------------------------------------------------------------- pause

func _build_pause() -> void:
	pause_layer = Control.new()
	pause_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_layer.visible = false
	root.add_child(pause_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_layer.add_child(dim)
	var vb := UiKit.centered_panel(pause_layer, Vector2(560, 0))
	pause_main = VBoxContainer.new()
	pause_main.add_theme_constant_override("separation", 10)
	vb.add_child(pause_main)
	pause_main.add_child(UiKit.label("Paused" + ("  ·  " + world.world_name if world.world_name != "" else ""), 30, UiKit.ACCENT))
	pause_main.add_child(UiKit.button("Resume", toggle_pause, 520))
	pause_main.add_child(UiKit.button("Mission log & stats", _show_log, 520))
	pause_main.add_child(UiKit.button("Settings", func() -> void:
		pause_main.visible = false
		settings.visible = true, 520))
	pause_main.add_child(UiKit.button("Save game", func() -> void:
		world.save_game()
		toast("Game saved.", 2.0), 520))
	pause_main.add_child(UiKit.button("Save & return to main menu", func() -> void:
		get_tree().paused = false
		world.exit_to_menu(), 520))
	pause_main.add_child(UiKit.button("Save & quit to desktop", func() -> void:
		world.save_game()
		get_tree().quit(), 520))
	settings = SettingsPanel.new()
	settings.visible = false
	settings.closed.connect(func() -> void:
		settings.visible = false
		pause_main.visible = true)
	vb.add_child(settings)


func _show_log() -> void:
	var s := world.state
	var lines := PackedStringArray()
	for m in Missions.LIST:
		lines.append("%s  %s: %s" % ["[x]" if s.missions_done.has(m.id) else "[  ]", m.title, m.desc])
	lines.append("")
	lines.append("Rust collected: %s kg   ·   exported: %s kg" % [_fmt_int(int(s.collected)), _fmt_int(int(s.total_sold))])
	lines.append("Total earned: %s   ·   hexagons cleared: %d   ·   play time: %d min   ·   sol %d" % [GameState.inr(s.earned), s.hexes_cleared.size(), int(s.play_time / 60.0), s.sol])
	lines.append("Tool: %s (power %d, width %d, reach %d)   ·   drones: %d   ·   solar panels: %d" % [s.tool().name, s.mods.power, s.mods.width, s.mods.reach, s.drones, s.panels])
	lines.append("")
	lines.append("Relics found (%d/%d): %s" % [s.relics_found.size(), GameState.RELICS.size(), ", ".join(PackedStringArray(s.relics_found)) if not s.relics_found.is_empty() else "none yet"])
	var dlg := AcceptDialog.new()
	dlg.title = "Mission log"
	dlg.dialog_text = "\n".join(lines)
	dlg.theme = UiKit.theme()
	root.add_child(dlg)
	dlg.popup_centered()
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause"):
		toggle_pause()
		get_viewport().set_input_as_handled()


func toggle_pause() -> void:
	if key_guide.visible:
		key_guide.visible = false
		return
	if shop_layer.visible:
		close_shop()
		return
	var on := not pause_layer.visible
	pause_layer.visible = on
	settings.visible = false
	pause_main.visible = true
	world.ui_open = on
	get_tree().paused = on
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on else Input.MOUSE_MODE_CAPTURED
