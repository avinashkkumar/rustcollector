class_name Missions
extends RefCounted
## Story-driven mission chain. One mission is active at a time; completing it pays a ₹ reward.
## After the last mission the game continues endlessly.

const LIST := [
	{id = "first_rust", title = "First scrapings", desc = "Collect 10 kg of rust.", reward = 500},
	{id = "first_export", title = "Off-world shipment", desc = "Export rust at the depot.", reward = 500},
	{id = "broom", title = "A proper tool", desc = "Buy the Push Broom at the base terminal.", reward = 1000},
	{id = "mod", title = "Tinkerer", desc = "Buy any tool upgrade (power, width or reach).", reward = 1500},
	{id = "first_hex", title = "Hex by hex", desc = "Clean one hexagon to 90%.", reward = 2000},
	{id = "panel1", title = "First light", desc = "Buy your first solar panel at the terminal.", reward = 1500},
	{id = "panels4", title = "Power the base", desc = "Own 4 solar panels.", reward = 3000},
	{id = "tank", title = "Bigger loads", desc = "Upgrade your rust tank.", reward = 3000},
	{id = "sweeper", title = "Wheels on Mars", desc = "Buy the Sweeper vehicle.", reward = 6000},
	{id = "hex5", title = "Clearing the plain", desc = "Clean 5 hexagons.", reward = 8000},
	{id = "charger", title = "Lifeline", desc = "Buy the Charger cart, so nobody gets stranded.", reward = 6000},
	{id = "repair", title = "Grease monkey", desc = "Repair a worn vehicle part at the garage (base terminal, Workshop).", reward = 4000},
	{id = "pod", title = "Special delivery", desc = "Open a supply pod (they land somewhere on the plain; follow the beacon).", reward = 3000},
	{id = "drones2", title = "Automation", desc = "Deploy 2 cleaning drones.", reward = 10000},
	{id = "export5t", title = "Five tonnes", desc = "Export 5,000 kg of rust in total.", reward = 20000},
	{id = "panels15", title = "Solar farm", desc = "Own 15 solar panels.", reward = 25000},
	{id = "vacuum", title = "Heavy suction", desc = "Buy the Vacuum Pump.", reward = 30000},
	{id = "hex25", title = "Red to brown", desc = "Clean 25 hexagons.", reward = 60000},
	{id = "lakh10", title = "Rust tycoon", desc = "Earn ₹10,00,000 in total.", reward = 100000},
]


func current(s: GameState) -> Dictionary:
	for m in LIST:
		if not s.missions_done.has(m.id):
			return m
	return {}


func progress(s: GameState, id: String) -> float:
	match id:
		"first_rust":
			return s.collected / 10.0
		"first_export":
			return 1.0 if s.total_sold > 0.0 else 0.0
		"broom":
			return 1.0 if s.tool_lvl >= 1 else 0.0
		"mod":
			return 1.0 if s.mods.power + s.mods.width + s.mods.reach > 0 else 0.0
		"first_hex":
			return s.hexes_cleared.size() / 1.0
		"panel1":
			return s.panels / 1.0
		"panels4":
			return s.panels / 4.0
		"tank":
			return 1.0 if s.tank_lvl >= 1 else 0.0
		"sweeper":
			return 1.0 if s.sweeper_owned else 0.0
		"hex5":
			return s.hexes_cleared.size() / 5.0
		"charger":
			return 1.0 if s.charger_owned else 0.0
		"repair":
			return 1.0 if s.repairs_done > 0 else 0.0
		"pod":
			return 1.0 if s.pods_opened > 0 else 0.0
		"drones2":
			return s.drones / 2.0
		"export5t":
			return s.total_sold / 5000.0
		"panels15":
			return s.panels / 15.0
		"vacuum":
			return 1.0 if s.tool_lvl >= 3 else 0.0
		"hex25":
			return s.hexes_cleared.size() / 25.0
		"lakh10":
			return s.earned / 1000000.0
	return 0.0


## Completes the active mission (and any following ones already satisfied). Returns those completed.
func check(s: GameState) -> Array:
	var out := []
	while true:
		var m := current(s)
		if m.is_empty() or progress(s, m.id) < 1.0:
			break
		s.missions_done.append(m.id)
		s.credits += m.reward
		s.earned += m.reward
		out.append(m)
	return out
