class_name Drone
extends Node3D
## Autonomous cleaning drone: works inside its hexagon zone, seeking the rustiest spots,
## and climbs over base buildings and vehicles rather than flying through them.

const SPEED := 3.2
const HOVER := 1.6
const RADIUS := 1.0
const RATE := 1.6

static var _body_mesh: SphereMesh
static var _ring_mesh: TorusMesh
static var _body_mat: StandardMaterial3D
static var _ring_mat: StandardMaterial3D

var world: World
var home := Vector3.ZERO
var target := Vector3.ZERO
var rng := RandomNumberGenerator.new()
var fx: GPUParticles3D
var light: OmniLight3D
var _t := 0.0
var _retarget := 0.0
var _fx_t := 0.0
var _rotor: Node3D
var _probe_t := 0.0
var _obstacle_top := -INF


func setup(w: World, home_pos: Vector3, seed_value: int, particles: float) -> void:
	world = w
	home = home_pos
	rng.seed = seed_value
	_t = rng.randf() * 10.0
	fx = DustFx.make(int(24 * particles), 0.7)
	fx.amount_ratio = 1.0


func _ready() -> void:
	if _body_mesh == null:
		_body_mesh = SphereMesh.new()
		_body_mesh.radius = 0.3
		_body_mesh.height = 0.36
		_body_mesh.radial_segments = 32
		_body_mesh.rings = 16
		_ring_mesh = TorusMesh.new()
		_ring_mesh.inner_radius = 0.42
		_ring_mesh.outer_radius = 0.52
		_ring_mesh.rings = 40
		_ring_mesh.ring_segments = 10
		_body_mat = StandardMaterial3D.new()
		_body_mat.albedo_color = Color(0.9, 0.9, 0.92)
		_body_mat.metallic = 0.4
		_body_mat.roughness = 0.35
		_ring_mat = StandardMaterial3D.new()
		_ring_mat.albedo_color = Color(0.2, 0.8, 1.0)
		_ring_mat.emission_enabled = true
		_ring_mat.emission = Color(0.2, 0.8, 1.0)
		_ring_mat.emission_energy_multiplier = 2.5
	var b := MeshInstance3D.new()
	b.mesh = _body_mesh
	b.material_override = _body_mat
	add_child(b)
	_rotor = Node3D.new()
	var r := MeshInstance3D.new()
	r.mesh = _ring_mesh
	r.material_override = _ring_mat
	r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rotor.add_child(r)
	_rotor.position.y = 0.05
	add_child(_rotor)
	fx.top_level = true
	add_child(fx)
	_pick_target()


func set_light(on: bool) -> void:
	if on and light == null:
		light = OmniLight3D.new()
		light.light_color = Color(0.35, 0.8, 1.0)
		light.omni_range = 4.0
		light.light_energy = 1.4
		light.position.y = -0.3
		add_child(light)
	if light:
		light.visible = on


## Picks the rustiest of a few random hexes inside the drone zone, then the rustiest
## of a few random spots inside that hex (staying within the hex's inner circle).
func _pick_target() -> void:
	_retarget = rng.randf_range(5.0, 9.0)
	var zone: Array[Vector2i] = world.drone_hexes
	if zone.is_empty():
		target = home
		return
	var best_hex: Vector2i = zone[rng.randi() % zone.size()]
	var best_clean := 2.0
	for i in 3:
		var k: Vector2i = zone[rng.randi() % zone.size()]
		var c: float = world.hex_cache.get(k, 0.0)
		if c < best_clean:
			best_clean = c
			best_hex = k
	var centre := RustField.key_center(best_hex)
	var best := -1
	for i in 4:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * RustField.HEX_W * 0.45
		var p := centre + Vector2(cos(a), sin(a)) * r
		var v := world.rust.value_at(p.x, p.y)
		if v > best:
			best = v
			target = Vector3(p.x, 0, p.y)


func _process(dt: float) -> void:
	_t += dt
	_retarget -= dt
	var p := global_position
	var flat := Vector2(target.x - p.x, target.z - p.z)
	var dist := flat.length()
	var dir := Vector2.ZERO
	if dist < 0.6 or _retarget <= 0.0:
		_pick_target()
	elif dist > 0.001:
		dir = flat / dist
		var step := dir * minf(SPEED * dt, dist)
		p.x += step.x
		p.z += step.y
		rotation.y = lerp_angle(rotation.y, atan2(-flat.x, -flat.y), 1.0 - exp(-4.0 * dt))
	var gy := world.terrain.height_at(p.x, p.z)
	# Fly over buildings and vehicles instead of through them: probe straight down here and a
	# little ahead, and keep clear of the highest thing found (re-probed ~10 times a second).
	_probe_t -= dt
	if _probe_t <= 0.0:
		_probe_t = 0.1
		_obstacle_top = maxf(_top_at(p.x, p.z), _top_at(p.x + dir.x * 3.0, p.z + dir.y * 3.0))
	var want := maxf(gy + HOVER, _obstacle_top + 1.2) + sin(_t * 2.3) * 0.12
	p.y = lerpf(p.y, want, 1.0 - exp(-(8.0 if want > p.y else 3.0) * dt))
	global_position = p
	_rotor.rotation.y += dt * 9.0
	var ground := Vector3(p.x, gy, p.z)
	# Only clean when actually down near the ground (not while hopping over a hangar).
	if p.y - gy < HOVER + 1.0 and world.drone_clean(ground, RADIUS, RATE * dt):
		_fx_t = 0.15
	_fx_t -= dt
	fx.global_position = ground
	fx.emitting = _fx_t > 0.0


## Height of the top of any building/vehicle at (x, z), or -INF if none.
func _top_at(x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 60.0, z), Vector3(x, -20.0, z), 4 | 8)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position.y if hit else -INF
