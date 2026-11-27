class_name Vehicle
extends CharacterBody3D
## Battery-electric base vehicle with arcade driving physics, Mars-rover style wheels on
## rocker-bogie legs, and component wear (tyres, brush, motor) that is repaired in the garage.
##   kind "sweeper": front roller brush that collects rust into a hopper.
##   kind "charger": a mobile battery that only recharges other vehicles.

const STEER_MAX := 0.62  # rad at walking pace
const STEER_MIN := 0.16  # rad at top speed
const GRIP := 9.0  # how fast sideways sliding is killed
const HANDBRAKE_GRIP := 1.2

var kind := "sweeper"
var world: World
var driving := false
var autopilot := false  # benchmark drives along a scripted path
var autopilot_sweep := true
var speed := 0.0  # m/s along the forward axis
var lateral := 0.0  # m/s sideways (drift)
var heading := 0.0
var yaw_rate := 0.0
var steer := 0.0
var energy := 12.0
var battery := 12.0
var charging := false
var tool_on := true  # sweeper brush, toggled with R
var boosting := false
var flat_warned := false
var sweeping := false
var camera: Camera3D
var engine_sfx: AudioStreamPlayer3D

var max_speed := 7.0  # m/s (25 km/h) flat out; the mouse-wheel limiter caps it lower
var accel := 4.2
var brake := 9.0
var wheelbase := 2.5
var track := 2.44
var drive_kw := 1.6  # draw at full throttle
var sweep_kw := 1.2  # at top speed
const IDLE_KW := 0.05  # lights and electronics

# Component condition, 1 = new, 0 = failed. Shared with GameState.wear so it is saved.
var cond := {tyres = 1.0, brush = 1.0, motor = 1.0}
var _smoke: GPUParticles3D
var _paint: Array = []  # [material, base colour] for grime
var _tyre_mat: StandardMaterial3D
var _legs: Array = []  # [MeshInstance3D, attach point, wheel pivot]
var _wheel_r := 0.45
var _vis_t := 0.0
var _track_dist := 0.0
var _factory := []  # original [primary, secondary] colours
var _look_yaw := 0.0
var _look_pitch := 0.0
var _look_idle := 0.0
var cam_mode := 0  # 0 = chase, 1 = hood

var model: Node3D
var body_pivot: Node3D
var roller: Node3D
var _guard: Node3D
var wheels: Array[Node3D] = []
var headlights: Array[SpotLight3D] = []
var _cam_pos := Vector3.ZERO
var _cam_fov := 70.0
var _susp_y := 0.0
var _susp_v := 0.0
var _lean := 0.0
var _pitch_off := 0.0


func _ready() -> void:
	if kind == "charger":
		max_speed = 8.5
		accel = 5.0
		drive_kw = 0.9
		sweep_kw = 0.0
		wheelbase = 2.2
		track = 2.1
	collision_layer = 8
	collision_mask = 1 | 4 | 8
	floor_snap_length = 0.8
	floor_max_angle = deg_to_rad(40)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.4, 1.4, 4.2) if kind == "sweeper" else Vector3(2.2, 1.3, 3.4)
	cs.shape = box
	cs.position.y = 0.95
	add_child(cs)
	model = Node3D.new()
	add_child(model)
	body_pivot = Node3D.new()
	model.add_child(body_pivot)
	if kind == "sweeper":
		_build_sweeper()
	else:
		_build_charger()
	_smoke = DustFx.make(32, 0.9)
	_smoke.position = Vector3(0, 2.0, 1.2)
	_smoke.local_coords = false
	(_smoke.process_material as ParticleProcessMaterial).gravity = Vector3(0, 0.9, 0)
	add_child(_smoke)
	camera = Camera3D.new()
	camera.top_level = true
	camera.fov = 70.0
	add_child(camera)
	engine_sfx = AudioStreamPlayer3D.new()
	var st: AudioStreamOggVorbis = load("res://assets/sfx/engineCircular_000.ogg")
	st.loop = true
	engine_sfx.stream = st
	engine_sfx.volume_db = -14.0
	engine_sfx.unit_size = 6.0
	add_child(engine_sfx)
	snap_camera()


## Worn parts make the vehicle slower, weaker and thirstier.
func top_speed() -> float:
	var t: float = cond.tyres
	var tyre_factor := 0.3 if t <= 0.0 else 0.8 + 0.2 * t
	return max_speed * (0.55 + 0.45 * float(cond.motor)) * tyre_factor


func worst_part() -> Array:
	var worst := ["", 2.0]
	for k in cond:
		if k == "brush" and kind != "sweeper":
			continue
		if float(cond[k]) < float(worst[1]):
			worst = [k, cond[k]]
	return worst


func forward() -> Vector3:
	return Vector3(-sin(heading), 0, -cos(heading))


func right() -> Vector3:
	return Vector3(cos(heading), 0, -sin(heading))


func display_name() -> String:
	return "Sweeper" if kind == "sweeper" else "Charger cart"


func set_driving(on: bool) -> void:
	driving = on
	parked = false
	if on:
		camera.current = true
		snap_camera()
		engine_sfx.play()
	else:
		engine_sfx.stop()


func _has_ground_below() -> bool:
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.0, global_position + Vector3.DOWN * 3.0, 1 | 4)
	q.exclude = [get_rid()]
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func snap_camera() -> void:
	_cam_pos = global_position + Basis(Vector3.UP, heading) * Vector3(0, 4.0, 9.0)


# ---------------------------------------------------------------- driving physics

## A vehicle nobody drives is parked: it stops simulating, so it stays put even after you walk
## far enough away that the terrain under it no longer has collision (it used to fall through).
var parked := false
var _park_pos := Vector3.ZERO
const RIDE := 0.25  # the body's collision box sits this far above the vehicle's origin


func _physics_process(dt: float) -> void:
	if autopilot:
		return
	if not driving:
		var ground := world.terrain.height_at(global_position.x, global_position.z) - RIDE
		if global_position.y < ground - 1.0:
			# Fell through the ground in an older save, or got pushed under it: put it back on top.
			global_position.y = ground + 0.3
			velocity = Vector3.ZERO
			parked = false
		speed = move_toward(speed, 0.0, brake * dt)  # nobody aboard: the parking brake holds it
		lateral = move_toward(lateral, 0.0, brake * dt)
		if parked and global_position.distance_squared_to(_park_pos) > 0.0001:
			parked = false  # moved by a tow, a save load or a test: settle again
		if parked:
			return
		if absf(speed) < 0.05 and (is_on_floor() or not _has_ground_below()):
			# Settled (or no collision here any more): rest on the terrain and stop simulating.
			if not is_on_floor():
				global_position.y = ground
			speed = 0.0
			lateral = 0.0
			velocity = Vector3.ZERO
			parked = true
			_park_pos = global_position
			return
	var throttle := 0.0
	var steer_in := 0.0
	var handbrake := false
	boosting = false
	if driving and not world.ui_open:
		throttle = Input.get_axis("move_back", "move_forward")
		steer_in = Input.get_axis("move_right", "move_left")
		handbrake = Input.is_action_pressed("jump")
		boosting = Input.is_action_pressed("sprint") and throttle > 0.0 and energy > 0.0
	var powered := energy > 0.0 and float(cond.motor) > 0.0
	if float(cond.motor) <= 0.0 and driving and not flat_warned:
		flat_warned = true
		world.vehicle_broken(self)
	if not powered:
		throttle = minf(throttle, 0.0) if speed > 0.1 else maxf(throttle, 0.0) if speed < -0.1 else 0.0
		if driving and not flat_warned:
			flat_warned = true
			world.vehicle_flat(self)
	var f := forward()
	# Engine / brake. Pressing against the direction of travel brakes first, then reverses.
	if throttle != 0.0 and (speed == 0.0 or signf(throttle) == signf(speed) or absf(speed) < 0.3):
		# Shift boosts past the limiter; otherwise forward speed is capped by the wheel setting.
		var top := (top_speed() * (1.35 if boosting else limit())) if throttle > 0.0 else top_speed() * 0.45
		var headroom := clampf(1.0 - absf(speed) / top, 0.0, 1.0)
		var motor_k := 0.5 + 0.5 * float(cond.motor)
		speed += throttle * accel * motor_k * (1.4 if boosting else 1.0) * (0.35 + 0.65 * sqrt(headroom)) * dt
	elif throttle != 0.0:
		speed = move_toward(speed, 0.0, brake * dt)
	else:
		speed = move_toward(speed, 0.0, (0.9 + absf(speed) * 0.08) * dt)  # rolling resistance + drag
	if handbrake:
		speed = move_toward(speed, 0.0, brake * 0.7 * dt)
	# Scrolled the limiter down: ease off to the new cap instead of snapping to it.
	if driving and not boosting and speed > top_speed() * limit():
		speed = move_toward(speed, top_speed() * limit(), brake * 0.35 * dt)
	# Slopes: gravity pulls along the ground's downhill direction.
	var n := world.terrain.normal_at(global_position.x, global_position.z)
	var downhill := Vector3(n.x, 0, n.z)
	speed += downhill.dot(f) * world.gravity * 1.6 * dt
	if is_on_floor():
		lateral += downhill.dot(right()) * world.gravity * 0.4 * dt
	speed = clampf(speed, -max_speed * 0.45, max_speed * 1.6)
	# Steering: bicycle model, less lock at speed, smoothed like a real steering rack.
	var lock := lerpf(STEER_MAX, STEER_MIN, clampf(absf(speed) / max_speed, 0.0, 1.0))
	steer = move_toward(steer, steer_in * lock, dt * 2.4)
	var target_yaw := speed / wheelbase * tan(steer)
	yaw_rate = lerpf(yaw_rate, target_yaw, 1.0 - exp(-(3.0 if handbrake else 8.0) * dt))
	heading += yaw_rate * dt
	# Handbrake turns trade forward speed for a sideways slide.
	if handbrake:
		lateral -= yaw_rate * speed * 0.18 * dt
	var grip := (HANDBRAKE_GRIP if handbrake else GRIP) * (0.4 + 0.6 * float(cond.tyres))
	lateral = move_toward(lateral, 0.0, grip * dt)
	rotation.y = heading
	var v := forward() * speed + right() * lateral
	velocity.x = v.x
	velocity.z = v.z
	if is_on_floor():
		velocity.y = -0.6
	else:
		velocity.y -= world.gravity * dt
	move_and_slide()
	# Hitting something bleeds speed instead of sliding along at full pace.
	if get_slide_collision_count() > 0:
		for i in get_slide_collision_count():
			var c := get_slide_collision(i)
			var hit := absf(c.get_normal().dot(f))
			if c.get_normal().y < 0.6 and hit > 0.3:
				# Crashes hurt: damage scales with how hard and how fast you hit.
				var force := hit * clampf(absf(speed) / max_speed, 0.0, 1.5)
				if driving and force > 0.15:
					cond.motor = maxf(float(cond.motor) - force * 0.03, 0.0)
					cond.tyres = maxf(float(cond.tyres) - force * 0.015, 0.0)
				speed *= 1.0 - hit * 0.6
				world.sfx("impactMetal_002")
	# Battery drain (game time runs at TIME_SCALE).
	if driving:
		var draw := (drive_power(throttle) * (1.0 + 0.5 * (1.0 - float(cond.motor))) + (brush_power() if sweeping else 0.0) + IDLE_KW) * float(world.state.diff().drain)
		energy = maxf(energy - draw * dt / GameState.TIME_SCALE, 0.0)
		if energy > 0.5 and float(cond.motor) > 0.0:
			flat_warned = false
		# Wear: tyres by distance (boost wears them ~3x faster), motor by throttle, brush by use.
		var frac := absf(speed) / max_speed
		var wm := float(world.state.diff().wear)
		cond.tyres = maxf(float(cond.tyres) - dt * frac * (0.0022 if boosting else 0.0007) * wm, 0.0)
		cond.motor = maxf(float(cond.motor) - dt * absf(throttle) * (0.0012 if boosting else 0.00035) * wm, 0.0)
		if sweeping:
			cond.brush = maxf(float(cond.brush) - dt * 0.0009 * wm, 0.0)


## Benchmark: place the vehicle on the terrain and face along the path.
func autopilot_place(pos: Vector3, new_heading: float, new_speed: float) -> void:
	var dh := wrapf(new_heading - heading, -PI, PI)
	yaw_rate = dh / maxf(get_process_delta_time(), 0.001) if new_speed > 0.0 else 0.0
	heading = new_heading
	rotation.y = heading
	speed = new_speed
	lateral = 0.0
	global_position = Vector3(pos.x, world.terrain.height_at(pos.x, pos.z), pos.z)


# ---------------------------------------------------------------- visuals

func _process(dt: float) -> void:
	var p := global_position
	var f := forward()
	var r := right()
	# Sample the ground under each wheel to get pitch and roll.
	var hw := wheelbase * 0.5
	var ht := track * 0.5
	var fl := world.terrain.height_at(p.x + f.x * hw - r.x * ht, p.z + f.z * hw - r.z * ht)
	var fr := world.terrain.height_at(p.x + f.x * hw + r.x * ht, p.z + f.z * hw + r.z * ht)
	var bl := world.terrain.height_at(p.x - f.x * hw - r.x * ht, p.z - f.z * hw - r.z * ht)
	var br := world.terrain.height_at(p.x - f.x * hw + r.x * ht, p.z - f.z * hw + r.z * ht)
	var pitch := atan2(((fl + fr) - (bl + br)) * 0.5, wheelbase)
	var roll := atan2(((fr + br) - (fl + bl)) * 0.5, track)
	# Body leans out of turns and squats under acceleration (spring-damper on the visuals).
	_lean = lerpf(_lean, clampf(-yaw_rate * speed * 0.025, -0.12, 0.12), 1.0 - exp(-5.0 * dt))
	var accel_now := (speed - _pitch_off) / maxf(dt, 0.001)
	_pitch_off = speed
	var mid := (fl + fr + bl + br) * 0.25 - p.y
	_susp_v += ((mid - _susp_y) * 140.0 - _susp_v * 14.0) * dt
	_susp_y += _susp_v * dt
	var tilt := Basis.from_euler(Vector3(pitch, 0, -roll))
	model.basis = model.basis.slerp(tilt, 1.0 - exp(-10.0 * dt))
	model.position.y = _susp_y
	body_pivot.rotation = Vector3(clampf(accel_now * 0.004, -0.05, 0.05), 0, _lean)
	# Rocker-bogie feel: every wheel finds its own ground height and the legs follow.
	var mt := model.global_transform
	for w in wheels:
		var rest: Vector3 = w.get_meta("rest")
		var wp := mt * rest
		var dy := clampf(world.terrain.height_at(wp.x, wp.z) + _wheel_r - wp.y, -0.3, 0.3)
		w.position.y = lerpf(w.position.y, rest.y + dy, 1.0 - exp(-18.0 * dt))
		var spin: Node3D = w.get_child(0)
		spin.rotate_object_local(Vector3.UP, speed * dt / _wheel_r * (1.0 if w.get_meta("right") else -1.0))
		if w.get_meta("front", false):
			w.rotation.y = steer
		elif w.get_meta("rear", false):
			w.rotation.y = -steer * 0.6  # corner wheels steer both ends, like the real rovers
	for leg in _legs:
		var a: Vector3 = leg[1]
		var b: Vector3 = (leg[2] as Node3D).position
		var d := b - a
		var y := d.normalized()
		var x := y.cross(Vector3.FORWARD)
		x = Vector3.RIGHT if x.length_squared() < 0.0001 else x.normalized()
		(leg[0] as MeshInstance3D).transform = Transform3D(Basis(x, y * d.length(), x.cross(y)), (a + b) * 0.5)
	# Tyre tracks: each wheel presses into the rust every ~15 cm travelled.
	_track_dist += absf(speed) * dt
	if _track_dist > 0.15 and visible:
		_track_dist = 0.0
		for w in wheels:
			var c := (w as Node3D).global_position
			world.rust.press(Vector3(c.x, 0, c.z), 0.24, 0.95)
	var brush: float = cond.get("brush", 0.0)
	sweeping = kind == "sweeper" and brush > 0.0 and absf(speed) > 0.4 and (energy > 0.0 or autopilot) and (
		(driving and tool_on) or (autopilot and autopilot_sweep))
	if sweeping:
		roller.rotate_object_local(Vector3.UP, -dt * 14.0)
		var front := p + f * 2.5
		# A worn brush leaves more behind and covers less width.
		world.vehicle_clean(self, Vector3(front.x, world.terrain.height_at(front.x, front.z), front.z),
			head_width * 0.5 * (0.7 + 0.3 * brush), 4.0 * (0.3 + 0.7 * brush) * dt)
	_vis_t -= dt
	if _vis_t <= 0.0:
		_vis_t = 0.5
		_update_wear_visuals()
	if engine_sfx.playing:
		engine_sfx.pitch_scale = 0.7 + absf(speed) / max_speed * 0.6 + (0.25 if boosting else 0.0)
	_look_idle += dt
	if _look_idle > 1.5:
		_look_yaw = lerpf(_look_yaw, 0.0, 1.0 - exp(-3.0 * dt))
		_look_pitch = lerpf(_look_pitch, 0.0, 1.0 - exp(-3.0 * dt))
	if driving and cam_mode == 1 and not autopilot:
		# Hood camera: on the cab roof, looking where the vehicle (plus free look) points.
		var cab := model.global_transform * Vector3(0, 2.35 if kind == "sweeper" else 2.05, -0.5)
		camera.global_position = cab
		var dir := Basis(Vector3.UP, heading + _look_yaw) * Basis(Vector3.RIGHT, _look_pitch - 0.12) * Vector3(0, 0, -1)
		camera.look_at(cab + dir)
		camera.fov = lerpf(camera.fov, 78.0 + (6.0 if boosting else 0.0), 1.0 - exp(-3.0 * dt))
	elif driving or autopilot:
		var dist := 8.5 + absf(speed) * 0.25
		var want := p + Basis(Vector3.UP, heading + _look_yaw) * Vector3(0, 3.6 + absf(speed) * 0.06 + _look_pitch * 6.0, dist)
		want.y = maxf(want.y, world.terrain.height_at(want.x, want.z) + 1.5)
		# Spring arm: pull the camera in front of walls/buildings between it and the vehicle.
		var pivot := p + Vector3(0, 2.2, 0)
		var q := PhysicsRayQueryParameters3D.create(pivot, want, 4)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit:
			want = (hit.position as Vector3) + (pivot - want).normalized() * 0.4
			_cam_pos = want  # snap in so the wall never fills the view
		_cam_pos = _cam_pos.lerp(want, 1.0 - exp(-4.5 * dt))
		camera.global_position = _cam_pos
		camera.look_at(p + Vector3(0, 1.3, 0) + f * (2.0 + absf(speed) * 0.35))
		_cam_fov = lerpf(_cam_fov, 68.0 + absf(speed) * 1.2 + (6.0 if boosting else 0.0), 1.0 - exp(-3.0 * dt))
		camera.fov = _cam_fov


## Grime builds up as parts wear; a dying motor smokes.
func _update_wear_visuals() -> void:
	var total := 0.0
	var n := 0
	for k in cond:
		if k == "brush" and kind != "sweeper":
			continue
		total += 1.0 - float(cond[k])
		n += 1
	var wear := total / maxf(n, 1)
	for pm in _paint:
		var m: StandardMaterial3D = pm[0]
		m.albedo_color = (pm[1] as Color).lerp(Color(0.33, 0.19, 0.11), wear * 0.6)
		m.roughness = lerpf(0.45, 0.9, wear)
	if _tyre_mat:
		_tyre_mat.albedo_color = Color(0.72, 0.72, 0.74).lerp(Color(0.36, 0.25, 0.18), 1.0 - float(cond.tyres))
	_smoke.emitting = float(cond.motor) < 0.35 and (driving or absf(speed) > 0.5) and visible


## Paint job: swaps the primary/secondary body colours (wear grime is applied on top).
func apply_livery(lv: Dictionary) -> void:
	if _factory.is_empty():
		_factory = [_paint[0][1], _paint[1][1]]
	var factory: bool = lv.id == "factory"
	_paint[0][1] = _factory[0] if factory else lv.primary
	_paint[1][1] = _factory[1] if factory else lv.secondary
	for pm in _paint:
		(pm[0] as StandardMaterial3D).metallic = 0.3 if factory else float(lv.metal)
	_update_wear_visuals()


## PUBG-style free look: move the mouse to look around; the camera recentres when you stop.
func _unhandled_input(e: InputEvent) -> void:
	if not driving or world.ui_open:
		return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var s := Config.mouse_sensitivity * 0.01
		_look_yaw = clampf(_look_yaw - e.relative.x * s, -PI * 0.95, PI * 0.95)
		_look_pitch = clampf(_look_pitch - e.relative.y * s, -0.5, 0.6)
		_look_idle = 0.0
	elif e.is_action_pressed("camera_toggle"):
		cam_mode = 1 - cam_mode
		snap_camera()
	elif e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var st := world.state
		var step := 0.1 if e.button_index == MOUSE_BUTTON_WHEEL_UP else -0.1
		st.drive_limit = clampf(snappedf(st.drive_limit + step, 0.1), 0.2, 1.0)
		var lim := top_speed() * limit() * 3.6
		world.hud.toast("Speed limit %d km/h  ·  range ~%.1f km  ·  slower goes further, Shift boosts past it" % [
			roundi(lim), range_at(lim)], 1.6)
		get_viewport().set_input_as_handled()


## Motor power (kW) at the current speed. Drag and rolling losses grow with the square of speed,
## so the energy per kilometre grows with speed: driving slower stretches the battery. Accelerating
## costs extra on top, and boost (Shift) pays a further 1.8x penalty.
func drive_power(throttle: float) -> float:
	var frac := absf(speed) / max_speed
	var cruise := drive_kw * frac * frac
	var pushing := drive_kw * 0.3 * absf(throttle) * clampf(1.0 - frac / maxf(limit(), 0.2), 0.0, 1.0)
	return (cruise + pushing) * (1.8 if boosting else 1.0)


## The roller works on the ground it covers, so its draw follows speed (a little to spin it
## while standing still).
func brush_power() -> float:
	return maxf(sweep_kw * head_width / 4.6 * absf(speed) / max_speed, 0.1)


var head_width := 4.6  # m of ground the roller sweeps (the wider-head upgrade raises it)


## Fits a brush head `w` metres wide: the roller (and its guard) stretch to match.
func set_head_width(w: float) -> void:
	head_width = w
	if roller:
		roller.scale = Vector3(1.0, w / 4.6, 1.0)  # the roller's axis is its local Y
	if _guard:
		_guard.scale.x = w / 4.6


## Estimated km left driving steadily at `kmh`.
func range_at(kmh_now: float) -> float:
	var v := kmh_now / 3.6
	var frac := v / max_speed
	var kw := (drive_kw * frac * frac * (1.0 + 0.5 * (1.0 - float(cond.motor))) + (maxf(sweep_kw * head_width / 4.6 * frac, 0.1) if tool_on else 0.0) + IDLE_KW) * float(world.state.diff().drain)
	return energy / kw * GameState.TIME_SCALE * v / 1000.0


## Fraction of top speed the mouse-wheel limiter allows (the benchmark has no limiter).
func limit() -> float:
	return world.state.drive_limit if world.mode == "play" else 1.0


func kmh() -> int:
	return roundi(absf(speed) * 3.6)


var lights_override := -1  # -1 automatic (on at night), 0 off, 1 on: set with L while driving


func set_headlights(on: bool) -> void:
	if lights_override >= 0:
		on = lights_override == 1
	for h in headlights:
		h.visible = on


func headlights_lit() -> bool:
	return not headlights.is_empty() and headlights[0].visible


# ---------------------------------------------------------------- models

func _build_sweeper() -> void:
	var orange := _mat(Color(0.93, 0.45, 0.12), 0.45, 0.3)
	var white := _mat(Color(0.88, 0.88, 0.86), 0.5, 0.1)
	_paint = [[orange, orange.albedo_color], [white, white.albedo_color]]
	var dark := _mat(Color(0.12, 0.12, 0.13), 0.85, 0.0)
	var glass := _mat(Color(0.15, 0.3, 0.4), 0.08, 0.7)
	var yellow := _mat(Color(0.95, 0.8, 0.2), 0.7, 0.0)
	_rbox(Vector3(2.2, 0.55, 3.8), Vector3(0, 0.95, 0), orange, 0.12)
	_rbox(Vector3(1.7, 0.95, 1.5), Vector3(0, 1.68, -0.4), white, 0.14)
	_rbox(Vector3(1.5, 0.5, 0.06), Vector3(0, 1.88, -1.17), glass, 0.02)
	_rbox(Vector3(1.9, 0.8, 1.4), Vector3(0, 1.6, 1.25), white, 0.12)
	_guard = _rbox(Vector3(2.5, 0.15, 0.5), Vector3(0, 0.62, -2.05), dark, 0.05)
	_wheels([-1.25, 0.0, 1.25], 1.22, 0.45, Vector3(0.95, 1.0, 0.45))
	roller = Node3D.new()
	roller.position = Vector3(0, 0.36, -2.3)
	roller.rotation_degrees.z = 90
	var rm := MeshInstance3D.new()
	rm.mesh = _cyl(0.34, 2.6, 40)
	rm.material_override = yellow
	roller.add_child(rm)
	body_pivot.add_child(roller)
	_beacon(Vector3(0.6, 2.25, -0.4), Color(1.0, 0.5, 0.1))
	_lights([-0.75, 0.75], Vector3(0, 1.1, -1.95))


func _build_charger() -> void:
	var teal := _mat(Color(0.12, 0.45, 0.5), 0.4, 0.4)
	var white := _mat(Color(0.86, 0.87, 0.86), 0.5, 0.1)
	_paint = [[teal, teal.albedo_color], [white, white.albedo_color]]
	var dark := _mat(Color(0.12, 0.12, 0.13), 0.85, 0.0)
	var glass := _mat(Color(0.15, 0.3, 0.4), 0.08, 0.7)
	var cell := _mat(Color(0.1, 0.12, 0.12), 0.4, 0.6)
	_rbox(Vector3(2.0, 0.45, 3.2), Vector3(0, 0.85, 0), white, 0.1)
	_rbox(Vector3(1.5, 0.8, 1.0), Vector3(0, 1.45, -1.0), white, 0.14)
	_rbox(Vector3(1.3, 0.42, 0.05), Vector3(0, 1.62, -1.51), glass, 0.02)
	# Battery pack with glowing charge bars.
	_rbox(Vector3(1.8, 0.9, 1.7), Vector3(0, 1.5, 0.65), teal, 0.1)
	for i in 4:
		_rbox(Vector3(0.32, 0.7, 1.6), Vector3(-0.6 + i * 0.4, 1.52, 0.65), cell, 0.04)
	var glow := _mat(Color(0.3, 1.0, 0.6), 0.3, 0.0)
	glow.emission_enabled = true
	glow.emission = Color(0.3, 1.0, 0.6)
	glow.emission_energy_multiplier = 2.0
	_rbox(Vector3(1.82, 0.06, 1.72), Vector3(0, 1.98, 0.65), glow, 0.02)
	# Cable reel.
	var reel := MeshInstance3D.new()
	reel.mesh = _cyl(0.35, 0.3, 32)
	reel.material_override = dark
	reel.rotation_degrees.z = 90
	reel.position = Vector3(1.05, 1.2, 1.25)
	body_pivot.add_child(reel)
	_wheels([-1.1, 1.1], 1.08, 0.42, Vector3(0.9, 0.95, 0.5))
	_beacon(Vector3(-0.55, 2.0, -1.0), Color(0.3, 1.0, 0.5))
	_lights([-0.6, 0.6], Vector3(0, 0.95, -1.62))


## Six (or four) rover wheels: aluminium drums with chevron grousers and curved spokes,
## each on its own leg. `attach` = leg mount (x, y, z-factor) on the body.
func _wheels(zs: Array, x: float, r: float, attach: Vector3) -> void:
	_wheel_r = r
	var mesh := rover_wheel(r, 0.4)
	var metal := _mat(Color(0.72, 0.72, 0.74), 0.35, 0.85)
	metal.cull_mode = BaseMaterial3D.CULL_DISABLED  # the open drum is seen from inside too
	_tyre_mat = _mat(Color(0.72, 0.72, 0.74), 0.5, 0.7)
	var leg_m := _mat(Color(0.55, 0.56, 0.6), 0.4, 0.8)
	var leg_mesh := BoxMesh.new()
	leg_mesh.size = Vector3(0.11, 1.0, 0.11)
	for i in zs.size():
		for xi in [-x, x]:
			var pivot := Node3D.new()
			pivot.position = Vector3(xi, r, zs[i])
			pivot.set_meta("rest", pivot.position)
			pivot.set_meta("front", i == 0)
			pivot.set_meta("rear", i == zs.size() - 1 and zs.size() > 2)
			pivot.set_meta("right", xi > 0.0)
			var spin := Node3D.new()
			spin.rotation_degrees.z = 90 if xi > 0.0 else -90
			pivot.add_child(spin)
			var tyre := MeshInstance3D.new()
			tyre.mesh = mesh
			tyre.set_surface_override_material(0, metal)
			tyre.set_surface_override_material(1, _tyre_mat)
			spin.add_child(tyre)
			model.add_child(pivot)
			wheels.append(pivot)
			var leg := MeshInstance3D.new()
			leg.mesh = leg_mesh
			leg.material_override = leg_m
			model.add_child(leg)
			_legs.append([leg, Vector3(signf(xi) * attach.x, attach.y, float(zs[i]) * attach.z), pivot])


static var _wheel_cache := {}


## Builds (once) a merged wheel mesh: surface 0 = drum, hub and spokes; surface 1 = grousers.
static func rover_wheel(r: float, w: float) -> ArrayMesh:
	var key := "%.3f/%.3f" % [r, w]
	if _wheel_cache.has(key):
		return _wheel_cache[key]
	var body := SurfaceTool.new()
	body.begin(Mesh.PRIMITIVE_TRIANGLES)
	var drum := CylinderMesh.new()
	drum.top_radius = r * 0.93
	drum.bottom_radius = r * 0.93
	drum.height = w
	drum.radial_segments = 40
	drum.rings = 1
	drum.cap_top = false  # open-faced like a real rover wheel: you see the spokes and hub
	drum.cap_bottom = false
	body.append_from(drum, 0, Transform3D())
	var lip := TorusMesh.new()
	lip.inner_radius = r * 0.86
	lip.outer_radius = r * 0.95
	lip.rings = 40
	lip.ring_segments = 8
	for side in [-1.0, 1.0]:
		body.append_from(lip, 0, Transform3D(Basis().scaled(Vector3(1, 0.6, 1)), Vector3(0, side * w * 0.5, 0)))
	var hub := CylinderMesh.new()
	hub.top_radius = r * 0.2
	hub.bottom_radius = r * 0.24
	hub.height = w + 0.1
	hub.radial_segments = 20
	hub.rings = 1
	body.append_from(hub, 0, Transform3D())
	# Curved spokes on both faces: three joined pieces bending around the hub.
	var spoke := BoxMesh.new()
	for k in 6:
		var phi := k * TAU / 6.0
		var pts: Array[Vector3] = []
		for j in 4:
			var t := j / 3.0
			pts.append(Basis(Vector3.UP, phi + t * t * 0.55) * Vector3(lerpf(r * 0.2, r * 0.9, t), 0, 0))
		for side in [-1.0, 1.0]:
			var off := Vector3(0, side * (w * 0.5 - 0.01), 0)
			for j in 3:
				var d: Vector3 = pts[j + 1] - pts[j]
				var x := d.normalized()
				var z := x.cross(Vector3.UP)
				spoke.size = Vector3(d.length() + 0.02, 0.035, 0.045)
				body.append_from(spoke, 0, Transform3D(Basis(x, Vector3.UP, z), (pts[j] + pts[j + 1]) * 0.5 + off))
	var mesh := body.commit()
	# Chevron grousers around the tread.
	var tread := SurfaceTool.new()
	tread.begin(Mesh.PRIMITIVE_TRIANGLES)
	var g := BoxMesh.new()
	g.size = Vector3(r * 0.08, w * 0.5, 0.04)
	for k in 22:
		var theta := k * TAU / 22.0
		for half in [-1.0, 1.0]:
			var local := Transform3D(Basis(Vector3.RIGHT, half * 0.5), Vector3(r * 0.93 + r * 0.03, half * w * 0.24, 0))
			tread.append_from(g, 0, Transform3D(Basis(Vector3.UP, theta), Vector3.ZERO) * local)
	tread.commit(mesh)
	_wheel_cache[key] = mesh
	return mesh


func _beacon(pos: Vector3, c: Color) -> void:
	var bm := _mat(c, 0.3, 0.0)
	bm.emission_enabled = true
	bm.emission = c
	bm.emission_energy_multiplier = 3.0
	var s := SphereMesh.new()
	s.radius = 0.12
	s.height = 0.24
	s.radial_segments = 24
	s.rings = 12
	var mi := MeshInstance3D.new()
	mi.mesh = s
	mi.material_override = bm
	mi.position = pos
	body_pivot.add_child(mi)


func _lights(xs: Array, base: Vector3) -> void:
	for xi in xs:
		var s := SpotLight3D.new()
		s.position = base + Vector3(xi, 0, 0)
		s.spot_range = 22.0
		s.spot_angle = 32.0
		s.light_energy = 3.0
		s.light_color = Color(1.0, 0.95, 0.85)
		body_pivot.add_child(s)
		headlights.append(s)


func _rbox(size: Vector3, pos: Vector3, m: Material, _bevel: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = m
	mi.position = pos
	body_pivot.add_child(mi)
	return mi


static func _cyl(r: float, h: float, seg: int) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


static func _mat(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m
