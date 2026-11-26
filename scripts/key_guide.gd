class_name KeyGuide
extends Control
## PUBG-style key guide (F1): a keyboard map with every bound key labelled.
## Keys for what you are doing right now (on foot / driving) are lit; the rest are dimmed.

const FOOT := Color(1.0, 0.6, 0.25)
const DRIVE := Color(0.4, 0.85, 1.0)
const BOTH := Color(0.95, 0.92, 0.86)
const U := 54.0  # key size in pixels

# key label -> [context, on-foot word, driving word, full description]. context: "foot", "drive" or "both"
const BINDS := {
	"Esc": ["both", "Menu", "Menu", "Pause menu / close a window"],
	"F1": ["both", "Keys", "Keys", "This key guide"],
	"F3": ["both", "FPS", "FPS", "FPS counter"],
	"F11": ["both", "Full", "Full", "Fullscreen on / off (also Alt+Enter)"],
	"W": ["both", "Fwd", "Gas", "Walk forward / accelerate"],
	"A": ["both", "Left", "Steer", "Walk left / steer left"],
	"S": ["both", "Back", "Brake", "Walk back / brake, then reverse"],
	"D": ["both", "Right", "Steer", "Walk right / steer right"],
	"Shift": ["both", "Sprint", "Boost", "Sprint / boost (faster, uses more battery per km)"],
	"Space": ["both", "Jump", "Handbrake", "Jump; at a ledge, climb up / handbrake (drift)"],
	"E": ["both", "Use", "Exit", "Interact: terminal, pods, plug, drive / get out"],
	"F": ["foot", "Clean", "", "Clean the rust you aim at (same as holding LMB)"],
	"G": ["foot", "Kit", "", "Use a repair kit on the vehicle next to you"],
	"B": ["foot", "Cell", "", "Install a battery cell in the vehicle next to you"],
	"Q": ["both", "Unload", "Empty", "Tip tank into handcart, or drop a sack / Export the hopper at the depot, or bag it into a sack"],
	"R": ["both", "Rotate", "Brush", "Rotate the panel you are placing / Sweeper brush on / off"],
	"P": ["foot", "Panel", "", "Place a bought solar panel (R rotates, LMB places)"],
	"V": ["drive", "", "Cam", "Chase / hood camera"],
	"T": ["both", "Mark", "Mark", "Set a waypoint where you look (again to remove)"],
	"M": ["both", "Map", "Map", "Big map"],
	"H": ["both", "Hex", "Hex", "Hexagon grid on / off"],
	"L": ["both", "Torch", "Lights", "Torch on or off / Headlights on or off"],
}
# rows of [label, width in key units]; "" = gap
const ROWS := [
	[["Esc", 1.0], ["", 0.5], ["F1", 1.0], ["F2", 1.0], ["F3", 1.0], ["F4", 1.0], ["", 0.5], ["F11", 1.0]],
	[["`", 1.0], ["1", 1.0], ["2", 1.0], ["3", 1.0], ["4", 1.0], ["5", 1.0], ["6", 1.0], ["7", 1.0], ["8", 1.0], ["9", 1.0], ["0", 1.0]],
	[["Tab", 1.5], ["Q", 1.0], ["W", 1.0], ["E", 1.0], ["R", 1.0], ["T", 1.0], ["Y", 1.0], ["U", 1.0], ["I", 1.0], ["O", 1.0], ["P", 1.0]],
	[["Caps", 1.75], ["A", 1.0], ["S", 1.0], ["D", 1.0], ["F", 1.0], ["G", 1.0], ["H", 1.0], ["J", 1.0], ["K", 1.0], ["L", 1.0]],
	[["Shift", 2.25], ["Z", 1.0], ["X", 1.0], ["C", 1.0], ["V", 1.0], ["B", 1.0], ["N", 1.0], ["M", 1.0]],
	[["Ctrl", 1.5], ["Alt", 1.25], ["Space", 6.0]],
]

var driving := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ctx_color(ctx: String) -> Color:
	return FOOT if ctx == "foot" else DRIVE if ctx == "drive" else BOTH


func _active(ctx: String) -> bool:
	return ctx == "both" or (ctx == "drive") == driving


func _draw() -> void:
	var font := get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.015, 0.01, 0.82))
	var kb_w := 12.0 * (U + 6.0)
	var origin := Vector2((size.x - kb_w - 620.0) * 0.5, (size.y - 6.0 * (U + 6.0)) * 0.5 + 10.0)
	draw_string(font, origin + Vector2(0, -40), "KEY GUIDE  ·  %s" % ("DRIVING" if driving else "ON FOOT"), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, UiKit.ACCENT)
	draw_string(font, origin + Vector2(0, -14), "Lit keys work right now. Press F1 or Esc to close.", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiKit.MUTED)
	for r in ROWS.size():
		var x := origin.x
		var y := origin.y + r * (U + 6.0)
		for k in ROWS[r]:
			var label: String = k[0]
			var w: float = k[1] * U + (k[1] - 1.0) * 6.0
			if label == "":
				x += w + 6.0
				continue
			var rect := Rect2(x, y, w, U)
			if BINDS.has(label):
				var ctx: String = BINDS[label][0]
				var col := _ctx_color(ctx)
				var on := _active(ctx)
				draw_rect(rect, Color(col.r, col.g, col.b, 0.28 if on else 0.08))
				draw_rect(rect, Color(col.r, col.g, col.b, 1.0 if on else 0.35), false, 2.0)
				draw_string(font, Vector2(x + 7, y + 20), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 1.0 if on else 0.45))
				var short: String = BINDS[label][2 if driving else 1]
				if short == "":
					short = BINDS[label][1] + BINDS[label][2]
				draw_string(font, Vector2(x + 6, y + U - 9), short, HORIZONTAL_ALIGNMENT_LEFT, w - 10, 11, Color(col.r, col.g, col.b, 1.0 if on else 0.4))
			else:
				draw_rect(rect, Color(1, 1, 1, 0.03))
				draw_rect(rect, Color(1, 1, 1, 0.12), false, 1.0)
				draw_string(font, Vector2(x + 7, y + 20), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.25))
			x += w + 6.0
	# Full list of what works right now.
	var tx := origin.x + kb_w + 200.0
	var ty := origin.y + 4.0
	draw_string(font, Vector2(tx, ty), "RIGHT NOW", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiKit.ACCENT)
	ty += 24.0
	for label in BINDS:
		var b: Array = BINDS[label]
		if not _active(b[0]):
			continue
		var parts := str(b[3]).split(" / ")
		var desc: String = b[3]
		if b[0] == "both" and parts.size() == 2 and label in ["W", "A", "S", "D", "Shift", "Space", "E", "L", "Q", "R"]:
			desc = parts[1] if driving else parts[0]
		draw_string(font, Vector2(tx, ty), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, _ctx_color(b[0]))
		draw_string(font, Vector2(tx + 58, ty), desc, HORIZONTAL_ALIGNMENT_LEFT, size.x - tx - 70.0, 15, Color(1, 1, 1, 0.9))
		ty += 21.0
	# Mouse.
	var mx := origin.x + kb_w + 40.0
	var my := origin.y + U + 6.0
	var body := Rect2(mx, my, 110, 170)
	draw_rect(body, Color(1, 1, 1, 0.04))
	draw_rect(body, Color(1, 1, 1, 0.25), false, 1.5)
	draw_line(Vector2(mx + 55, my), Vector2(mx + 55, my + 70), Color(1, 1, 1, 0.25), 1.5)
	var lmb := Rect2(mx + 2, my + 2, 51, 66)
	draw_rect(lmb, Color(FOOT.r, FOOT.g, FOOT.b, 0.3 if not driving else 0.08))
	draw_string(font, Vector2(mx + 8, my + 40), "LMB", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.45 if driving else 1.0))
	draw_string(font, Vector2(mx, my + 196), "LMB: clean" if not driving else "Move: look around", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, FOOT if not driving else DRIVE)
	draw_string(font, Vector2(mx, my + 218), "Move: look" if not driving else "(recentres itself)", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiKit.MUTED)
	draw_rect(Rect2(mx + 49, my + 16, 12, 30), Color(DRIVE.r, DRIVE.g, DRIVE.b, 0.6 if driving else 0.15))
	draw_string(font, Vector2(mx, my + 244), "Wheel: speed limit", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, DRIVE if driving else UiKit.MUTED)
	draw_string(font, Vector2(mx, my + 264), "(while driving)", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiKit.MUTED)
	# Legend.
	var ly := origin.y + 6.0 * (U + 6.0) + 30.0
	var items := [[FOOT, "On foot only"], [DRIVE, "Driving only"], [BOTH, "Everywhere (meaning can change)"]]
	var lx := origin.x
	for it in items:
		draw_rect(Rect2(lx, ly - 12, 14, 14), it[0])
		draw_string(font, Vector2(lx + 22, ly), it[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.85))
		lx += 260.0
