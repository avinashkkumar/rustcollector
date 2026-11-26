class_name GameState
extends RefCounted
## Economy (₹ INR), tool progression, power grid and save data.
## Everything that cleans (hand tools, vacuum lances, the sweeper vehicle, drones)
## collects the same Martian rust, which is exported from the base for rupees.

const SAVE_PATH := "user://save.json"
const RUST_PATH := "user://save_rust.bin"

const SELL_PRICE := 25.0  # ₹ per kg of rust exported
const DRONE_SHARE := 0.5  # drones export remotely at half price
const HEX_BONUS := 2000  # ₹ extra for every hexagon cleaned to 90 %
const HEX_CLEAR := 0.9
const MAX_DRONES := 10
const TOW_COST := 4000

# Power. Game time runs 60x: one real second is one game minute, so kWh = kW * s / 60.
const TIME_SCALE := 60.0
const PANEL_KW := 1.0
const MAX_PANELS := 40
const BANK_BASE := 20.0  # kWh
const BANK_PER_PANEL := 2.0
const PAD_CHARGE_KW := 8.0
const CART_CHARGE_KW := 6.0

const SWEEPER_COST := 55000
const CHARGER_COST := 30000
const SWEEPER_HOPPER := 900.0  # kg
const SWEEPER_BATT := [{kwh = 12.0, cost = 0}, {kwh = 18.0, cost = 15000}, {kwh = 26.0, cost = 35000}, {kwh = 36.0, cost = 70000}]
const CHARGER_BATT := 45.0
# Full-repair price per part (scaled by how worn it is).
const REPAIR_COST := {
	sweeper = {tyres = 6000, brush = 8000, motor = 12000},
	charger = {tyres = 4000, motor = 8000},
}
const PART_NAMES := {tyres = "Tyres", brush = "Brush roller", motor = "Drive motor"}
# Drone work zone: hexagon rings around the base hex (1 ring = 7 hexes, 4 rings = 61).
const DRONE_RANGE := [{rings = 1, cost = 0}, {rings = 2, cost = 25000}, {rings = 3, cost = 60000}, {rings = 4, cost = 120000}]

const TOOLS := [
	{name = "Scrub Brush", desc = "Hand brush. Slow, but it's a start.", radius = 0.45, rate = 2.2, reach = 3.4, cost = 0},
	{name = "Push Broom", desc = "Wide head, long handle.", radius = 0.8, rate = 2.6, reach = 3.9, cost = 3000},
	{name = "Air Blower", desc = "Blasts rust loose over a wide area.", radius = 1.3, rate = 3.0, reach = 4.6, cost = 11000},
	{name = "Vacuum Pump", desc = "Backpack suction pump. Fast and far.", radius = 2.0, rate = 3.8, reach = 5.5, cost = 35000},
	{name = "Ion Sweeper", desc = "Electrostatic field lifts everything.", radius = 3.0, rate = 5.0, reach = 6.5, cost = 100000},
]
# Upgrade tracks that apply on top of whichever tool you hold.
const TOOL_MODS := {
	power = {name = "Motor power", desc = "+15% cleaning speed per level", per = 0.15, max = 6, cost = 900},
	width = {name = "Wider head", desc = "+12% cleaning radius per level", per = 0.12, max = 6, cost = 1100},
	reach = {name = "Extension arm", desc = "+10% reach per level", per = 0.10, max = 4, cost = 700},
}
# Things buried under the rust. Found at random while cleaning; each pays once.
const RELICS := [
	{name = "Cracked helmet visor", value = 1500}, {name = "Rover wheel (2030s)", value = 2500},
	{name = "Iron meteorite", value = 4000}, {name = "Lost survey drone", value = 3000},
	{name = "Sealed seed vault tube", value = 6000}, {name = "Prospector's logbook", value = 2000},
	{name = "Fused glass sphere", value = 5000}, {name = "Antique lander strut", value = 7000},
	{name = "Tiffin box (still sealed!)", value = 1111}, {name = "Gold-foil probe panel", value = 9000},
	{name = "Fossil-like rock fern", value = 12000}, {name = "Founders' plaque", value = 15000},
]
# Contractor ranks by lifetime earnings; each rank adds +3% to the export price.
const RANKS := [
	{name = "Rust Rookie", earned = 0}, {name = "Dust Walker", earned = 20000},
	{name = "Grit Grinder", earned = 60000}, {name = "Plain Sweeper", earned = 150000},
	{name = "Hex Hunter", earned = 300000}, {name = "Crater Captain", earned = 600000},
	{name = "Iron Oxide Ace", earned = 1200000}, {name = "Red Planet Elite", earned = 2500000},
	{name = "Martian Master", earned = 5000000}, {name = "Legend of Rustfall", earned = 10000000},
]
const RANK_BONUS := 0.03
# Paint jobs for vehicles (cosmetic). primary/secondary replace the body colours.
const LIVERIES := [
	{id = "factory", name = "Factory", cost = 0},
	{id = "saffron", name = "Saffron Strike", cost = 15000, primary = Color(1.0, 0.6, 0.12), secondary = Color(0.07, 0.5, 0.2), metal = 0.2},
	{id = "nightops", name = "Night Ops", cost = 20000, primary = Color(0.13, 0.14, 0.16), secondary = Color(0.3, 0.32, 0.35), metal = 0.4},
	{id = "tiger", name = "Desert Tiger", cost = 25000, primary = Color(0.78, 0.62, 0.38), secondary = Color(0.36, 0.26, 0.16), metal = 0.1},
	{id = "neon", name = "Neon Pulse", cost = 40000, primary = Color(0.32, 0.12, 0.6), secondary = Color(0.1, 0.85, 0.8), metal = 0.3},
	{id = "chrome", name = "Chrome Rover", cost = 60000, primary = Color(0.86, 0.87, 0.9), secondary = Color(0.6, 0.62, 0.66), metal = 1.0},
]
const SOL_SECONDS := 960.0  # one Martian day lasts 16 real minutes

const TANKS := [
	{cap = 25.0, cost = 0}, {cap = 60.0, cost = 2000}, {cap = 140.0, cost = 8000},
	{cap = 300.0, cost = 25000}, {cap = 650.0, cost = 75000},
]
const BOOTS := [{mult = 1.0, cost = 0}, {mult = 1.15, cost = 4000}, {mult = 1.3, cost = 14000}, {mult = 1.5, cost = 40000}]

var credits := 0.0
var tank := 0.0
var hopper := 0.0
var tool_lvl := 0
var mods := {power = 0, width = 0, reach = 0}
var tank_lvl := 0
var boots_lvl := 0
var drones := 0
var drone_range := 1
var panels := 0  # nothing at the start: panels must be bought
var bank := 10.0  # the base battery starts half charged
var sweeper_owned := false
var charger_owned := false
var sweeper_batt_lvl := 0
var sweeper_energy := 12.0
var charger_energy := CHARGER_BATT
var vehicles := {}  # name -> [x, y, z, heading] last parked position
var wear := {sweeper = {tyres = 1.0, brush = 1.0, motor = 1.0}, charger = {tyres = 1.0, motor = 1.0}}
var repairs_done := 0
var repair_kits := 0
var battery_cells := 0
var pods_opened := 0
var liveries := {sweeper = ["factory"], charger = ["factory"]}
var livery := {sweeper = "factory", charger = "factory"}
var sol_start := {}  # snapshot at the start of the current sol, for the end-of-sol report
var sol_kg := {you = 0.0, sweeper = 0.0, drones = 0.0}
var total_sold := 0.0
var collected := 0.0  # kg ever picked up
var earned := 0.0  # ₹ ever earned
var missions_done: Array = []
var story_seen := false
var relics_found: Array = []
var dig_meter := 0.0
var next_relic_kg := 80.0
var time_of_day := 0.3  # 0..1, 0.5 = noon
var sol := 1
var hexes_cleared: Array = []
var player_pos := Vector3(0, 1, 9)
var player_yaw := 0.0
var play_time := 0.0


func tool() -> Dictionary:
	var t: Dictionary = TOOLS[tool_lvl].duplicate()
	t.radius = float(t.radius) * (1.0 + mods.width * TOOL_MODS.width.per)
	t.rate = float(t.rate) * (1.0 + mods.power * TOOL_MODS.power.per)
	t.reach = float(t.reach) * (1.0 + mods.reach * TOOL_MODS.reach.per)
	return t


func mod_cost(m: String) -> int:
	var lvl: int = mods[m]
	var base: float = TOOL_MODS[m].cost
	return int(round(base * pow(1.65, lvl) * (1.0 + tool_lvl * 0.6) / 100.0)) * 100


func capacity() -> float:
	return TANKS[tank_lvl].cap


func boots_mult() -> float:
	return BOOTS[boots_lvl].mult


func sweeper_battery() -> float:
	return SWEEPER_BATT[sweeper_batt_lvl].kwh


func drone_cost() -> int:
	return 20000 + drones * 11000


func panel_cost() -> int:
	return 6000 + panels * 600


func bank_cap() -> float:
	return BANK_BASE + panels * BANK_PER_PANEL


func gen_kw() -> float:
	return panels * PANEL_KW


## The off-world rust price drifts slowly between roughly ₹19 and ₹32 per kg; ranks add a bonus.
func price_now() -> float:
	var t := play_time / 240.0
	return SELL_PRICE * (1.0 + 0.16 * sin(t * 0.9) + 0.08 * sin(t * 2.3 + 1.7)) * (1.0 + RANK_BONUS * rank_index())


func rank_index() -> int:
	var r := 0
	for i in RANKS.size():
		if earned >= float(RANKS[i].earned):
			r = i
	return r


func rank_name() -> String:
	return RANKS[rank_index()].name


func start_sol_report() -> void:
	sol_start = {earned = earned, hexes = hexes_cleared.size(), relics = relics_found.size(), pods = pods_opened}
	sol_kg = {you = 0.0, sweeper = 0.0, drones = 0.0}


## 0 at night, 1 at noon. Solar panels follow this.
func daylight() -> float:
	return clampf(sin((time_of_day - 0.25) * TAU) * 1.4, 0.0, 1.0)


func repair_cost(kind: String, part: String) -> int:
	var c: float = wear[kind][part]
	return int(ceil((1.0 - c) * float(REPAIR_COST[kind][part]) / 50.0)) * 50


func sell(kg: float) -> float:
	var c := kg * price_now()
	credits += c
	earned += c
	total_sold += kg
	return c


## Indian-style grouping: ₹12,34,567
static func inr(v: float) -> String:
	var n := int(round(v))
	var s := str(absi(n))
	var out := s
	if s.length() > 3:
		out = "," + s.right(3)
		s = s.left(s.length() - 3)
		while s.length() > 2:
			out = "," + s.right(2) + out
			s = s.left(s.length() - 2)
		out = s + out
	return ("-" if n < 0 else "") + "₹" + out


func to_dict() -> Dictionary:
	return {
		credits = credits, tank = tank, hopper = hopper, tool_lvl = tool_lvl, mods = mods,
		tank_lvl = tank_lvl, boots_lvl = boots_lvl, drones = drones, panels = panels, bank = bank,
		sweeper_owned = sweeper_owned, charger_owned = charger_owned, sweeper_batt_lvl = sweeper_batt_lvl,
		sweeper_energy = sweeper_energy, charger_energy = charger_energy, vehicles = vehicles,
		total_sold = total_sold, hexes_cleared = hexes_cleared, drone_range = drone_range,
		collected = collected, earned = earned, missions_done = missions_done, story_seen = story_seen,
		relics_found = relics_found, wear = wear, repairs_done = repairs_done, repair_kits = repair_kits,
		battery_cells = battery_cells, pods_opened = pods_opened, liveries = liveries, livery = livery,
		sol_start = sol_start, sol_kg = sol_kg, dig_meter = dig_meter, next_relic_kg = next_relic_kg, time_of_day = time_of_day, sol = sol,
		player_pos = [player_pos.x, player_pos.y, player_pos.z], player_yaw = player_yaw, play_time = play_time,
	}


func from_dict(d: Dictionary) -> void:
	credits = d.get("credits", 0.0)
	tank = d.get("tank", 0.0)
	hopper = d.get("hopper", 0.0)
	tool_lvl = clampi(int(d.get("tool_lvl", 0)), 0, TOOLS.size() - 1)
	var m: Dictionary = d.get("mods", {})
	for k in mods:
		mods[k] = clampi(int(m.get(k, 0)), 0, int(TOOL_MODS[k].max))
	tank_lvl = clampi(int(d.get("tank_lvl", 0)), 0, TANKS.size() - 1)
	boots_lvl = clampi(int(d.get("boots_lvl", 0)), 0, BOOTS.size() - 1)
	drones = clampi(int(d.get("drones", 0)), 0, MAX_DRONES)
	panels = clampi(int(d.get("panels", 0)), 0, MAX_PANELS)
	bank = d.get("bank", 20.0)
	sweeper_owned = d.get("sweeper_owned", false)
	charger_owned = d.get("charger_owned", false)
	sweeper_batt_lvl = clampi(int(d.get("sweeper_batt_lvl", 0)), 0, SWEEPER_BATT.size() - 1)
	sweeper_energy = d.get("sweeper_energy", sweeper_battery())
	charger_energy = d.get("charger_energy", CHARGER_BATT)
	vehicles = d.get("vehicles", {})
	total_sold = d.get("total_sold", 0.0)
	hexes_cleared = d.get("hexes_cleared", [])
	drone_range = clampi(int(d.get("drone_range", 1)), 1, DRONE_RANGE.size())
	collected = d.get("collected", 0.0)
	earned = d.get("earned", 0.0)
	missions_done = d.get("missions_done", [])
	story_seen = d.get("story_seen", true)
	relics_found = d.get("relics_found", [])
	repairs_done = int(d.get("repairs_done", 0))
	repair_kits = int(d.get("repair_kits", 0))
	battery_cells = int(d.get("battery_cells", 0))
	pods_opened = int(d.get("pods_opened", 0))
	var lv: Dictionary = d.get("liveries", {})
	var la: Dictionary = d.get("livery", {})
	for kind in liveries:
		liveries[kind] = lv.get(kind, ["factory"])
		livery[kind] = la.get(kind, "factory")
	sol_start = d.get("sol_start", {})
	var sk: Dictionary = d.get("sol_kg", {})
	for k in sol_kg:
		sol_kg[k] = float(sk.get(k, 0.0))
	var w: Dictionary = d.get("wear", {})
	for kind in wear:
		for part in wear[kind]:
			wear[kind][part] = clampf(float(w.get(kind, {}).get(part, 1.0)), 0.0, 1.0)
	dig_meter = d.get("dig_meter", 0.0)
	next_relic_kg = d.get("next_relic_kg", 80.0)
	time_of_day = d.get("time_of_day", 0.3)
	sol = int(d.get("sol", 1))
	var p: Array = d.get("player_pos", [0, 1, 9])
	player_pos = Vector3(p[0], p[1], p[2])
	player_yaw = d.get("player_yaw", 0.0)
	play_time = d.get("play_time", 0.0)


func save(rust: RustField) -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(to_dict(), "  "))
	var r := FileAccess.open(RUST_PATH, FileAccess.WRITE)
	if r:
		r.store_var(rust.to_save())


func load_into(rust: RustField) -> bool:
	if not has_save():
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(d) != TYPE_DICTIONARY:
		return false
	from_dict(d)
	if FileAccess.file_exists(RUST_PATH):
		var r := FileAccess.open(RUST_PATH, FileAccess.READ)
		var v = r.get_var()
		if typeof(v) == TYPE_DICTIONARY:
			rust.from_save(v)
	return true


static func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


static func delete_save() -> void:
	for p in [SAVE_PATH, RUST_PATH, "user://save_dust.bin"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
