class_name HexMap
extends Control
## North-up minimap of the hexagon grid around the player. Each hex is shaded by how clean it is.

const RUST := Color(0.86, 0.45, 0.22)
const CLEAN := Color(0.26, 0.16, 0.11)

var world: World
var span := 170.0  # metres across the map
var _t := 0.0
var _corners := PackedVector2Array()


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var r := RustField.HEX_W / sqrt(3.0)
	for i in 6:
		var a := deg_to_rad(90.0 + 60.0 * i)
		_corners.append(Vector2(cos(a), sin(a)) * r)


func _process(dt: float) -> void:
	_t -= dt
	if _t <= 0.0:
		_t = 0.05  # 20 Hz is plenty for a minimap
		queue_redraw()


func _hex_points(centre: Vector2, ppm: float, shrink := 1.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for c in _corners:
		pts.append(centre + c * ppm * shrink)
	return pts


func _draw() -> void:
	var sz := size
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0.08, 0.04, 0.03, 0.92))
	var f := world.focus_point()
	var me := Vector2(f.x, f.z)
	var ppm := sz.x / span
	var w := RustField.HEX_W
	var half := span * 0.5 + w
	var budget := 8  # new hex statistics computed per redraw
	var ky0 := floori((me.y - half) / (w * 0.8660254))
	var ky1 := ceili((me.y + half) / (w * 0.8660254))
	var kx0 := floori((me.x - half) / (w * 0.5))
	var kx1 := ceili((me.x + half) / (w * 0.5))
	var focus_key := RustField.hex_key(f.x, f.z)
	for ky in range(ky0, ky1 + 1):
		for kx in range(kx0, kx1 + 1):
			if (kx + ky) % 2 != 0:
				continue
			var k := Vector2i(kx, ky)
			var sp := (RustField.key_center(k) - me) * ppm + sz * 0.5
			if sp.x < -20 or sp.y < -20 or sp.x > sz.x + 20 or sp.y > sz.y + 20:
				continue
			var clean := 0.0
			if world.hex_cache.has(k):
				clean = world.hex_cache[k]
			elif budget > 0:
				budget -= 1
				clean = world.rust.hex_clean(k)
				world.hex_cache[k] = clean
			var col := RUST.lerp(CLEAN, clean)
			var pts := _hex_points(sp, ppm, 0.96)
			draw_colored_polygon(pts, col)
			if clean >= GameState.HEX_CLEAR:
				draw_colored_polygon(_hex_points(sp, ppm, 0.3), Color(0.4, 1.0, 0.55, 0.8))
	# Drone work zone.
	for k in world.drone_hexes:
		var sp := (RustField.key_center(k) - me) * ppm + sz * 0.5
		var pts := _hex_points(sp, ppm, 0.96)
		pts.append(pts[0])
		draw_polyline(pts, Color(0.35, 0.85, 1.0, 0.55), 1.0)
	var fp := _hex_points((RustField.key_center(focus_key) - me) * ppm + sz * 0.5, ppm)
	fp.append(fp[0])
	draw_polyline(fp, Color(1, 0.95, 0.8), 2.0)
	# Markers.
	var to_map := func(p: Vector3) -> Vector2: return (Vector2(p.x, p.z) - me) * ppm + sz * 0.5
	draw_rect(Rect2(to_map.call(World.DEPOT) - Vector2(4, 4), Vector2(8, 8)), Color(1, 0.7, 0.3))
	draw_rect(Rect2(to_map.call(World.TERMINAL) - Vector2(4, 4), Vector2(8, 8)), Color(0.5, 0.85, 1))
	var g: Vector2 = to_map.call(World.GARAGE)
	draw_rect(Rect2(g - Vector2(7, 5.5) * ppm, Vector2(14, 11) * ppm), Color(0.4, 1, 0.6), false, 1.5)
	for d in world.drones:
		draw_circle(to_map.call(d.global_position), 2.0, Color(0.5, 0.95, 1))
	for v in [world.sweeper, world.charger]:
		if world.owns(v):
			draw_circle(to_map.call(v.global_position), 4.0, Color(1, 0.85, 0.2) if v == world.sweeper else Color(0.4, 1, 0.6))
	var yaw: float = world.driven().heading if world.driven() else world.player.yaw
	var c: Vector2 = sz * 0.5
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var side := Vector2(fwd.y, -fwd.x)
	draw_colored_polygon(PackedVector2Array([c + fwd * 9, c - fwd * 6 + side * 6, c - fwd * 6 - side * 6]), Color.WHITE)
	draw_string(get_theme_default_font(), Vector2(sz.x - 16, 16), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.7))
